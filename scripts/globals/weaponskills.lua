-- Contains all common weaponskill calculations including but not limited to:
-- fSTR
-- Alpha
-- Ratio -> cRatio
-- min/max cRatio
-- applications of fTP
-- applications of critical hits ('Critical hit rate varies with TP.')
-- applications of accuracy mods ('Accuracy varies with TP.')
-- applications of damage mods ('Damage varies with TP.')
-- performance of the actual WS (rand numbers, etc)
require("scripts/globals/magicburst")
require("scripts/globals/ability")
require("scripts/globals/status")
require("scripts/globals/magic")
require("scripts/globals/utils")
require("scripts/globals/msg")

-- params contains: ftp100, ftp200, ftp300, str_wsc, dex_wsc, vit_wsc, int_wsc, mnd_wsc, canCrit, crit100, crit200, crit300, acc100, acc200, acc300, ignoresDef, ignore100, ignore200, ignore300, atk100, atk200, atk300, kick
function doPhysicalWeaponskill(attacker, target, wsID, tp, primary, action, taChar, params)
    local criticalHit = false
    local bonusTP = 0
    if (params.bonusTP ~= nil) then
        bonusTP = params.bonusTP
    end
    local multiHitfTP = false
    if (params.multiHitfTP ~= nil) then
        multiHitfTP = params.multiHitfTP
    end
    local bonusfTP, bonusacc = handleWSGorgetBelt(attacker)
    bonusacc = bonusacc + attacker:getMod(dsp.mod.WSACC)

    -- get fstr
    local fstr = fSTR(attacker:getStat(dsp.mod.STR),target:getStat(dsp.mod.VIT),attacker:getWeaponDmgRank())

    -- apply WSC
    local weaponDamage = attacker:getWeaponDmg()
    local weaponType = attacker:getWeaponSkillType(dsp.slot.MAIN)
    local damageType = attacker:getWeaponDamageType(dsp.slot.MAIN)

    if weaponType == dsp.skill.HAND_TO_HAND or weaponType == dsp.skill.NONE then
        local h2hSkill = attacker:getSkillLevel(1) * 0.11 + 3
        weaponDamage = attacker:getWeaponDmg()

        if params.kick and attacker:hasStatusEffect(dsp.effect.FOOTWORK) then
            weaponDamage = attacker:getMod(dsp.mod.KICK_DMG) -- Use Kick damage if footwork is on
        end

        weaponDamage = weaponDamage + h2hSkill
    end

    local base = weaponDamage + fstr +
        (attacker:getStat(dsp.mod.STR) * params.str_wsc + attacker:getStat(dsp.mod.DEX) * params.dex_wsc +
         attacker:getStat(dsp.mod.VIT) * params.vit_wsc + attacker:getStat(dsp.mod.AGI) * params.agi_wsc +
         attacker:getStat(dsp.mod.INT) * params.int_wsc + attacker:getStat(dsp.mod.MND) * params.mnd_wsc +
         attacker:getStat(dsp.mod.CHR) * params.chr_wsc) * getAlpha(attacker:getMainLvl())

    -- Applying fTP multiplier
    local ftp = fTP(tp,params.ftp100,params.ftp200,params.ftp300) + bonusfTP

    local ignoredDef = 0
    if (params.ignoresDef == not nil and params.ignoresDef == true) then
        ignoredDef = calculatedIgnoredDef(tp, target:getStat(dsp.mod.DEF), params.ignored100, params.ignored200, params.ignored300)
    end

    -- get cratio min and max
    local cratio, ccritratio = cMeleeRatio(attacker, target, params, ignoredDef)
    local ccmin = 0
    local ccmax = 0
    local hasMightyStrikes = attacker:hasStatusEffect(dsp.effect.MIGHTY_STRIKES)
    local isSneakValid = attacker:hasStatusEffect(dsp.effect.SNEAK_ATTACK)
    if (isSneakValid and not (attacker:isBehind(target) or attacker:hasStatusEffect(dsp.effect.HIDE) or target:hasStatusEffect(dsp.effect.DOUBT))) then
        isSneakValid = false
    end
    attacker:delStatusEffectsByFlag(dsp.effectFlag.DETECTABLE)
    attacker:delStatusEffect(dsp.effect.SNEAK_ATTACK)
    local isTrickValid = taChar ~= nil

    local isAssassinValid = isTrickValid
    if (isAssassinValid and not attacker:hasTrait(68)) then
        isAssassinValid = false
    end

    local critrate = 0
    local nativecrit = 0

    if (params.canCrit) then -- work out critical hit ratios, by +1ing
        critrate = fTP(tp,params.crit100,params.crit200,params.crit300)
        -- add on native crit hit rate (guesstimated, it actually follows an exponential curve)
        local flourisheffect = attacker:getStatusEffect(dsp.effect.BUILDING_FLOURISH)
        if flourisheffect ~= nil and flourisheffect:getPower() > 1 then
            critrate = critrate + (10 + flourisheffect:getSubPower()/2)/100
        end
        nativecrit = (attacker:getStat(dsp.mod.DEX) - target:getStat(dsp.mod.AGI))*0.005; -- assumes +0.5% crit rate per 1 dDEX

        if (nativecrit > 0.2) then -- caps only apply to base rate, not merits and mods
            nativecrit = 0.2
        elseif (nativecrit < 0.05) then
            nativecrit = 0.05
        end

        nativecrit = nativecrit + (attacker:getMod(dsp.mod.CRITHITRATE)/100) + attacker:getMerit(dsp.merit.CRIT_HIT_RATE)/100 - target:getMerit(dsp.merit.ENEMY_CRIT_RATE)/100

        -- Handle Fencer
        local mainEquip = attacker:getStorageItem(0, 0, dsp.slot.MAIN)

        if mainEquip and not mainEquip:isTwoHanded() and not mainEquip:isHandToHand() then
            local subEquip = attacker:getStorageItem(0, 0, dsp.slot.SUB)
            if subEquip == nil or subEquip:getSkillType() == dsp.skill.NONE or subEquip:isShield() then
                nativecrit = nativecrit + attacker:getMod(dsp.mod.FENCER_CRITHITRATE) / 100
            end
        end

        if (attacker:hasStatusEffect(dsp.effect.INNIN) and attacker:isBehind(target, 23)) then -- Innin acc boost attacker is behind target
            nativecrit = nativecrit + attacker:getStatusEffect(dsp.effect.INNIN):getPower()
        end

        critrate = critrate + nativecrit
    end

    -- Applying pDIF
    local pdif = generatePdif (cratio[1], cratio[2], true)

    local missChance = math.random()
    local finaldmg = 0
    local hitrate = getHitRate(attacker,target,true,bonusacc)
    if (params.acc100~=0) then
        -- ACCURACY VARIES WITH TP, APPLIED TO ALL HITS.
        -- print("Accuracy varies with TP.")
        hr = accVariesWithTP(getHitRate(attacker,target,false,bonusacc),attacker:getACC(),tp,params.acc100,params.acc200,params.acc300)
        hitrate = hr
    end

    local dmg = base * ftp
    local tpHitsLanded = 0
    local shadowsAbsorbed = 0
    if ((missChance <= hitrate or isSneakValid or isAssassinValid or math.random() < attacker:getMod(dsp.mod.ZANSHIN)/100) and
            not target:hasStatusEffect(dsp.effect.PERFECT_DODGE) and not target:hasStatusEffect(dsp.effect.ALL_MISS) ) then
        if not shadowAbsorb(target) then
            if (params.canCrit or isSneakValid or isAssassinValid or hasMightyStrikes) then
                local critchance = math.random()
                if (critchance <= critrate or hasMightyStrikes or isSneakValid or isAssassinValid) then -- crit hit!
                    local cpdif = generatePdif (ccritratio[1], ccritratio[2], true)
                    finaldmg = dmg * cpdif
                    if (isSneakValid and attacker:getMainJob() == dsp.job.THF) then -- have to add on DEX bonus if on THF main
                        finaldmg = finaldmg + (attacker:getStat(dsp.mod.DEX) * (1 + attacker:getMod(dsp.mod.SNEAK_ATK_DEX)/100) * ftp * cpdif) * ((100+(attacker:getMod(dsp.mod.AUGMENTS_SA)))/100)
                    end
                    if (isTrickValid and attacker:getMainJob() == dsp.job.THF) then
                        finaldmg = finaldmg + (attacker:getStat(dsp.mod.AGI) * (1 + attacker:getMod(dsp.mod.TRICK_ATK_AGI)/100) * ftp * cpdif) * ((100+(attacker:getMod(dsp.mod.AUGMENTS_TA)))/100)
                    end
                else
                    finaldmg = dmg * pdif
                    if (isTrickValid and attacker:getMainJob() == dsp.job.THF) then
                        finaldmg = finaldmg + (attacker:getStat(dsp.mod.AGI) * (1 + attacker:getMod(dsp.mod.TRICK_ATK_AGI)/100) * ftp * pdif) * ((100+(attacker:getMod(dsp.mod.AUGMENTS_TA)))/100)
                    end
                end
            else
                finaldmg = dmg * pdif
                if (isTrickValid and attacker:getMainJob() == dsp.job.THF) then
                    finaldmg = finaldmg + (attacker:getStat(dsp.mod.AGI) * (1 + attacker:getMod(dsp.mod.TRICK_ATK_AGI)/100) * ftp * pdif) * ((100+(attacker:getMod(dsp.mod.AUGMENTS_TA)))/100)
                end
            end
            tpHitsLanded = 1
        else
            shadowsAbsorbed = shadowsAbsorbed + 1
        end
    end

    if not multiHitfTP then dmg = base end

    if ((attacker:getOffhandDmg() ~= 0) and (attacker:getOffhandDmg() > 0 or weaponType==dsp.skill.HAND_TO_HAND)) then

        local chance = math.random()
        if ((chance<=hitrate or math.random() < attacker:getMod(dsp.mod.ZANSHIN)/100 or isSneakValid)
                and not target:hasStatusEffect(dsp.effect.PERFECT_DODGE) and not target:hasStatusEffect(dsp.effect.ALL_MISS) ) then -- it hit
            if not shadowAbsorb(target) then
                pdif = generatePdif (cratio[1], cratio[2], true)
                if (params.canCrit) then
                    critchance = math.random()
                    if (critchance <= nativecrit or hasMightyStrikes) then -- crit hit!
                        criticalHit = true
                        cpdif = generatePdif (ccritratio[1], ccritratio[2], true)
                        finaldmg = finaldmg + dmg * cpdif
                    else
                        finaldmg = finaldmg + dmg * pdif
                    end
                else
                    finaldmg = finaldmg + dmg * pdif
                end
                tpHitsLanded = tpHitsLanded + 1
            else
                shadowsAbsorbed = shadowsAbsorbed + 1
            end
        end
    end

    -- Store first hit bonus for use after other calcs are done..
    local firstHitBonus = ((finaldmg * attacker:getMod(dsp.mod.ALL_WSDMG_FIRST_HIT))/100)

    local numHits = getMultiAttacks(attacker, target, params.numHits)
    local extraHitsLanded = 0

    if (numHits > 1) then

        local hitsdone = 1
        while (hitsdone < numHits) do
            local chance = math.random()
            local targetHP = target:getHP()
            if ((chance<=hitrate or math.random() < attacker:getMod(dsp.mod.ZANSHIN)/100) and
                    not target:hasStatusEffect(dsp.effect.PERFECT_DODGE) and not target:hasStatusEffect(dsp.effect.ALL_MISS) ) then  -- it hit
                if not shadowAbsorb(target) then
                    pdif = generatePdif (cratio[1], cratio[2], true)
                    if (params.canCrit) then
                        critchance = math.random()
                        if (critchance <= nativecrit or hasMightyStrikes) then -- crit hit!
                            criticalHit = true
                            cpdif = generatePdif (ccritratio[1], ccritratio[2], true)
                            finaldmg = finaldmg + dmg * cpdif
                        else
                            finaldmg = finaldmg + dmg * pdif
                        end
                    else
                        finaldmg = finaldmg + dmg * pdif
                    end
                    extraHitsLanded = extraHitsLanded + 1
                else
                    shadowsAbsorbed = shadowsAbsorbed + 1
                end
            end
            hitsdone = hitsdone + 1
            if (finaldmg > targetHP) then
                break
            end
        end
    end
    finaldmg = finaldmg + souleaterBonus(attacker, (tpHitsLanded+extraHitsLanded))
    -- print("Landed " .. hitslanded .. "/" .. numHits .. " hits with hitrate " .. hitrate .. "!")


    -- DMG Bonus for any WS
    local bonusdmg = attacker:getMod(dsp.mod.ALL_WSDMG_ALL_HITS)

    -- Ws Specific DMG Bonus
    if (attacker:getMod(dsp.mod.WEAPONSKILL_DAMAGE_BASE + wsID) > 0) then
        bonusdmg = bonusdmg + attacker:getMod(dsp.mod.WEAPONSKILL_DAMAGE_BASE + wsID)
    end

    -- Add in bonusdmg
    finaldmg = finaldmg * ((100 + bonusdmg)/100)
    finaldmg = finaldmg + firstHitBonus

    -- Check for reductions from PDT
    finaldmg = target:physicalDmgTaken(finaldmg, damageType)

    -- Check for reductions from phys resistances
    if (weaponType == dsp.skill.HAND_TO_HAND) then
        finaldmg = finaldmg * target:getMod(dsp.mod.HTHRES) / 1000
    elseif (weaponType == dsp.skill.DAGGER or weaponType == dsp.skill.POLEARM) then
        finaldmg = finaldmg * target:getMod(dsp.mod.PIERCERES) / 1000
    elseif (weaponType == dsp.skill.CLUB or weaponType == dsp.skill.STAFF) then
        finaldmg = finaldmg * target:getMod(dsp.mod.IMPACTRES) / 1000
    else
        finaldmg = finaldmg * target:getMod(dsp.mod.SLASHRES) / 1000
    end

    attacker:delStatusEffectSilent(dsp.effect.BUILDING_FLOURISH)
    finaldmg = finaldmg * WEAPON_SKILL_POWER
    finaldmg = takeWeaponskillDamage(target, attacker, params, primary, finaldmg, dsp.attackType.PHYSICAL, damageType, dsp.slot.MAIN, tpHitsLanded, extraHitsLanded, shadowsAbsorbed, bonusTP, action, taChar)
    return finaldmg, criticalHit, tpHitsLanded, extraHitsLanded
end

-- params: ftp100, ftp200, ftp300, wsc_str, wsc_dex, wsc_vit, wsc_agi, wsc_int, wsc_mnd, wsc_chr,
--         ele (dsp.magic.ele.FIRE), skill (dsp.skill.STAFF), includemab = true

function doMagicWeaponskill(attacker, target, wsID, tp, primary, action, params)
    local bonusTP = 0
    if (params.bonusTP ~= nil) then
        bonusTP = params.bonusTP
    end
    local bonusfTP, bonusacc = handleWSGorgetBelt(attacker)
    bonusacc = bonusacc + attacker:getMod(dsp.mod.WSACC)

    local fint = utils.clamp(8 + (attacker:getStat(dsp.mod.INT) - target:getStat(dsp.mod.INT)), -32, 32)
    local dmg = 0
    local shadowsAbsorbed = 0

    if not shadowAbsorb(target) then

        dmg = attacker:getMainLvl() + 2 + (attacker:getStat(dsp.mod.STR) * params.str_wsc + attacker:getStat(dsp.mod.DEX) * params.dex_wsc +
             attacker:getStat(dsp.mod.VIT) * params.vit_wsc + attacker:getStat(dsp.mod.AGI) * params.agi_wsc +
             attacker:getStat(dsp.mod.INT) * params.int_wsc + attacker:getStat(dsp.mod.MND) * params.mnd_wsc +
             attacker:getStat(dsp.mod.CHR) * params.chr_wsc) + fint

        -- Applying fTP multiplier
        local ftp = fTP(tp,params.ftp100,params.ftp200,params.ftp300) + bonusfTP

        dmg = dmg * ftp

        dmg = addBonusesAbility(attacker, params.ele, target, dmg, params)
        dmg = dmg * applyResistanceAbility(attacker,target,params.ele,params.skill, bonusacc)
        dmg = target:magicDmgTaken(dmg)
        dmg = adjustForTarget(target,dmg,params.ele)

        -- Add first hit bonus..No such thing as multihit magic ws is there?
        local firstHitBonus = ((dmg * attacker:getMod(dsp.mod.ALL_WSDMG_FIRST_HIT))/100)

        -- DMG Bonus for any WS
        local bonusdmg = attacker:getMod(dsp.mod.ALL_WSDMG_ALL_HITS)

        -- Ws Specific DMG Bonus
        if (attacker:getMod(dsp.mod.WEAPONSKILL_DAMAGE_BASE + wsID) > 0) then
            bonusdmg = bonusdmg + attacker:getMod(dsp.mod.WEAPONSKILL_DAMAGE_BASE + wsID)
        end

        -- Add in bonusdmg
        dmg = dmg * ((100 + bonusdmg)/100)
        dmg = dmg + firstHitBonus

        dmg = dmg * WEAPON_SKILL_POWER
    else
        shadowsAbsorbed = shadowsAbsorbed + 1
    end
    damageType = dsp.damageType.ELEMENTAL + params.ele
    dmg = takeWeaponskillDamage(target, attacker, params, primary, dmg, dsp.attackType.MAGICAL, damageType, dsp.slot.MAIN, 1, 0, shadowsAbsorbed, bonusTP, action, nil)
    return dmg, false, 1, 0
end

function souleaterBonus(attacker, numhits)
    if attacker:hasStatusEffect(dsp.effect.SOULEATER) then
        local damage = 0
        local percent = 0.1
        if attacker:getMainJob() ~= dsp.job.DRK then
            percent = percent / 2
        end
        percent = percent + math.min(0.02, 0.01 * attacker:getMod(dsp.mod.SOULEATER_EFFECT))

        local hitscounted = 0
        while (hitscounted < numhits) do
            local health = attacker:getHP()
            if health > 10 then
                damage = damage + health*percent
            end
            hitscounted = hitscounted + 1
        end
        attacker:takeDamage(numhits*0.10*attacker:getHP())
        return damage
    else
        return 0
    end
end

function accVariesWithTP(hitrate,acc,tp,a1,a2,a3)
    -- sadly acc varies with tp ALL apply an acc PENALTY, the acc at various %s are given as a1 a2 a3
    accpct = fTP(tp,a1,a2,a3)
    acclost = acc - (acc*accpct)
    hrate = hitrate - (0.005*acclost)
    -- cap it
    if (hrate>0.95) then
        hrate = 0.95
    end
    if (hrate<0.2) then
        hrate = 0.2
    end
    return hrate
end

function getHitRate(attacker,target,capHitRate,bonus)
    local flourisheffect = attacker:getStatusEffect(dsp.effect.BUILDING_FLOURISH)
    if flourisheffect ~= nil and flourisheffect:getPower() > 1 then
        attacker:addMod(dsp.mod.ACC, 20 + flourisheffect:getSubPower())
    end
    local acc = attacker:getACC()
    local eva = target:getEVA()
    if flourisheffect ~= nil and flourisheffect:getPower() > 1 then
        attacker:delMod(dsp.mod.ACC, 20 + flourisheffect:getSubPower())
    end
    if (bonus == nil) then
        bonus = 0
    end
    if (attacker:hasStatusEffect(dsp.effect.INNIN) and attacker:isBehind(target, 23)) then -- Innin acc boost if attacker is behind target
        bonus = bonus + attacker:getStatusEffect(dsp.effect.INNIN):getPower()
    end
    if (target:hasStatusEffect(dsp.effect.YONIN) and attacker:isFacing(target, 23)) then -- Yonin evasion boost if attacker is facing target
        bonus = bonus - target:getStatusEffect(dsp.effect.YONIN):getPower()
    end
    if (attacker:hasTrait(76) and attacker:isBehind(target, 23)) then --TRAIT_AMBUSH
        bonus = bonus + attacker:getMerit(dsp.merit.AMBUSH)
    end

    acc = acc + bonus

    if (attacker:getMainLvl() > target:getMainLvl()) then -- acc bonus!
        acc = acc + ((attacker:getMainLvl()-target:getMainLvl())*4)
    elseif (attacker:getMainLvl() < target:getMainLvl()) then -- acc penalty :(
        acc = acc - ((target:getMainLvl()-attacker:getMainLvl())*4)
    end

    local hitdiff = 0
    local hitrate = 75
    if (acc>eva) then
    hitdiff = (acc-eva)/2
    end
    if (eva>acc) then
    hitdiff = ((-1)*(eva-acc))/2
    end

    hitrate = hitrate+hitdiff
    hitrate = hitrate/100


    -- Applying hitrate caps
    if (capHitRate) then -- this isn't capped for when acc varies with tp, as more penalties are due
        if (hitrate>0.95) then
            hitrate = 0.95
        end
        if (hitrate<0.2) then
            hitrate = 0.2
        end
    end
    return hitrate
end

function getRangedHitRate(attacker,target,capHitRate,bonus)
    local acc = attacker:getRACC()
    local eva = target:getEVA()

    if (bonus == nil) then
        bonus = 0
    end
    if (target:hasStatusEffect(dsp.effect.YONIN) and target:isFacing(attacker, 23)) then -- Yonin evasion boost if defender is facing attacker
        bonus = bonus - target:getStatusEffect(dsp.effect.YONIN):getPower()
    end
    if (attacker:hasTrait(76) and attacker:isBehind(target, 23)) then --TRAIT_AMBUSH
        bonus = bonus + attacker:getMerit(dsp.merit.AMBUSH)
    end

    acc = acc + bonus

    if (attacker:getMainLvl() > target:getMainLvl()) then -- acc bonus!
        acc = acc + ((attacker:getMainLvl()-target:getMainLvl())*4)
    elseif (attacker:getMainLvl() < target:getMainLvl()) then -- acc penalty :(
        acc = acc - ((target:getMainLvl()-attacker:getMainLvl())*4)
    end

    local hitdiff = 0
    local hitrate = 75
    if (acc>eva) then
    hitdiff = (acc-eva)/2
    end
    if (eva>acc) then
    hitdiff = ((-1)*(eva-acc))/2
    end

    hitrate = hitrate+hitdiff
    hitrate = hitrate/100

    -- Applying hitrate caps
    if (capHitRate) then -- this isn't capped for when acc varies with tp, as more penalties are due
        if (hitrate>0.95) then
            hitrate = 0.95
        end
        if (hitrate<0.2) then
            hitrate = 0.2
        end
    end
    return hitrate
end

function fTP(tp,ftp1,ftp2,ftp3)
    if (tp < 1000) then
        tp = 1000
    end
    if (tp >= 1000 and tp < 2000) then
        return ftp1 + ( ((ftp2-ftp1)/1000) * (tp-1000))
    elseif (tp >= 2000 and tp <= 3000) then
        -- generate a straight line between ftp2 and ftp3 and find point @ tp
        return ftp2 + ( ((ftp3-ftp2)/1000) * (tp-2000))
    else
        print("fTP error: TP value is not between 1000-3000!")
    end
    return 1; -- no ftp mod
end

function calculatedIgnoredDef(tp, def, ignore1, ignore2, ignore3)
    if (tp>=1000 and tp <2000) then
        return (ignore1 + ( ((ignore2-ignore1)/1000) * (tp-1000)))*def
    elseif (tp>=2000 and tp<=3000) then
        return (ignore2 + ( ((ignore3-ignore2)/1000) * (tp-2000)))*def
    end
    return 1; -- no def ignore mod
end

-- Given the raw ratio value (atk/def) and levels, returns the cRatio (min then max)
function cMeleeRatio(attacker, defender, params, ignoredDef)

    local flourisheffect = attacker:getStatusEffect(dsp.effect.BUILDING_FLOURISH)
    if flourisheffect ~= nil and flourisheffect:getPower() > 1 then
        attacker:addMod(dsp.mod.ATTP, 25 + flourisheffect:getSubPower() / 2)
    end
    local atkmulti = fTP(params.atk100, params.atk200, params.atk300)
    local cratio = (attacker:getStat(dsp.mod.ATT) * atkmulti) / (defender:getStat(dsp.mod.DEF) - ignoredDef)
    cratio = utils.clamp(cratio, 0, 2.25)
    if flourisheffect ~= nil and flourisheffect:getPower() > 1 then
        attacker:delMod(dsp.mod.ATTP, 25 + flourisheffect:getSubPower() / 2)
    end
    local levelcor = 0
    if attacker:getMainLvl() < defender:getMainLvl() then
        levelcor = 0.05 * (defender:getMainLvl() - attacker:getMainLvl())
    end

    cratio = cratio - levelcor

    if cratio < 0 then
        cratio = 0
    end
    local pdifmin = 0
    local pdifmax = 0

    -- max

    if cratio < 0.5 then
        pdifmax = cratio + 0.5
    elseif cratio < 0.7 then
        pdifmax = 1
    elseif cratio < 1.2 then
        pdifmax = cratio + 0.3
    elseif cratio < 1.5 then
        pdifmax = cratio * 0.25 + cratio
    elseif cratio < 2.625 then
        pdifmax = cratio + 0.375
    else
        pdifmax = 3
    end
    -- min

    if cratio < 0.38 then
        pdifmin = 0
    elseif (cratio < 1.25) then
        pdifmin = cratio * 1176 / 1024 - 448 / 1024
    elseif cratio < 1.51 then
        pdifmin = 1
    elseif cratio < 2.44 then
        pdifmin = cratio * 1176 / 1024 - 775 / 1024
    else
        pdifmin = cratio - 0.375
    end

    local pdif = {}
    pdif[1] = pdifmin
    pdif[2] = pdifmax

    local pdifcrit = {}
    cratio = cratio + 1
    cratio = utils.clamp(cratio, 0, 3)

    -- printf("ratio: %f min: %f max %f\n", cratio, pdifmin, pdifmax)

    if cratio < 0.5 then
        pdifmax = cratio + 0.5
    elseif cratio < 0.7 then
        pdifmax = 1
    elseif (cratio < 1.2) then
        pdifmax = cratio + 0.3
    elseif cratio < 1.5 then
        pdifmax = cratio * 0.25 + cratio
    elseif cratio < 2.625 then
        pdifmax = cratio + 0.375
    else
        pdifmax = 3
    end
    -- min

    if cratio < 0.38 then
        pdifmin = 0
    elseif cratio < 1.25 then
        pdifmin = cratio * 1176 / 1024 - 448 / 1024
    elseif cratio < 1.51 then
        pdifmin = 1
    elseif cratio < 2.44 then
        pdifmin = cratio * 1176 / 1024 - 775 / 1024
    else
        pdifmin = cratio - 0.375
    end

    local critbonus = attacker:getMod(dsp.mod.CRIT_DMG_INCREASE) - defender:getMod(dsp.mod.CRIT_DEF_BONUS)
    critbonus = utils.clamp(critbonus, 0, 100)
    pdifcrit[1] = pdifmin * (100 + critbonus) / 100
    pdifcrit[2] = pdifmax * (100 + critbonus) / 100

    return pdif, pdifcrit
end

function cRangedRatio(attacker, defender, params, ignoredDef)

    local atkmulti = fTP(params.atk100, params.atk200, params.atk300)
    local cratio = attacker:getRATT() / (defender:getStat(dsp.mod.DEF) - ignoredDef)

    local levelcor = 0
    if (attacker:getMainLvl() < defender:getMainLvl()) then
        levelcor = 0.025 * (defender:getMainLvl() - attacker:getMainLvl())
    end

    cratio = cratio - levelcor

    cratio = cratio * atkmulti

    if (cratio > 3 - levelcor) then
        cratio = 3 - levelcor
    end

    if (cratio < 0) then
        cratio = 0
    end

    -- max
    local pdifmax = 0
    if (cratio < 0.9) then
        pdifmax = cratio * (10/9)
    elseif (cratio < 1.1) then
        pdifmax = 1
    else
        pdifmax = cratio
    end

    -- min
    local pdifmin = 0
    if (cratio < 0.9) then
        pdifmin = cratio
    elseif (cratio < 1.1) then
        pdifmin = 1
    else
        pdifmin = (cratio * (20/19))-(3/19)
    end

    pdif = {}
    pdif[1] = pdifmin
    pdif[2] = pdifmax
    -- printf("ratio: %f min: %f max %f\n", cratio, pdifmin, pdifmax)
    pdifcrit = {}

    pdifmin = pdifmin * 1.25
    pdifmax = pdifmax * 1.25

    pdifcrit[1] = pdifmin
    pdifcrit[2] = pdifmax

    return pdif, pdifcrit

end

-- Given the attacker's str and the mob's vit, fSTR is calculated
function fSTR(atk_str,def_vit,base_dmg)
    local dSTR = atk_str - def_vit
    if (dSTR >= 12) then
        fSTR2 = ((dSTR+4)/2)
    elseif (dSTR >= 6) then
        fSTR2 = ((dSTR+6)/2)
    elseif (dSTR >= 1) then
        fSTR2 = ((dSTR+7)/2)
    elseif (dSTR >= -2) then
        fSTR2 = ((dSTR+8)/2)
    elseif (dSTR >= -7) then
        fSTR2 = ((dSTR+9)/2)
    elseif (dSTR >= -15) then
        fSTR2 = ((dSTR+10)/2)
    elseif (dSTR >= -21) then
        fSTR2 = ((dSTR+12)/2)
    else
        fSTR2 = ((dSTR+13)/2)
    end
    -- Apply fSTR caps.
    if (fSTR2<((base_dmg/9)*(-1))) then
        fSTR2 = (base_dmg/9)*(-1)
    elseif (fSTR2>((base_dmg/9)+8)) then
        fSTR2 = (base_dmg/9)+8
    end
    return fSTR2
end

-- obtains alpha, used for working out WSC
function getAlpha(level)
    alpha = 1.00
    if (level <= 5) then
        alpha = 1.00
    elseif (level <= 11) then
        alpha = 0.99
    elseif (level <= 17) then
        alpha = 0.98
    elseif (level <= 23) then
        alpha = 0.97
    elseif (level <= 29) then
        alpha = 0.96
    elseif (level <= 35) then
        alpha = 0.95
    elseif (level <= 41) then
        alpha = 0.94
    elseif (level <= 47) then
        alpha = 0.93
    elseif (level <= 53) then
        alpha = 0.92
    elseif (level <= 59) then
        alpha = 0.91
    elseif (level <= 61) then
        alpha = 0.90
    elseif (level <= 63) then
        alpha = 0.89
    elseif (level <= 65) then
        alpha = 0.88
    elseif (level <= 67) then
        alpha = 0.87
    elseif (level <= 69) then
        alpha = 0.86
    elseif (level <= 71) then
        alpha = 0.85
    elseif (level <= 73) then
        alpha = 0.84
    elseif (level <= 75) then
        alpha = 0.83
    elseif (level < 99) then
        alpha = 0.85
    else
        alpha = 1; -- Retail has no alpha anymore!
    end
    return alpha
end

 -- params contains: ftp100, ftp200, ftp300, str_wsc, dex_wsc, vit_wsc, int_wsc, mnd_wsc, canCrit, crit100, crit200, crit300, acc100, acc200, acc300, ignoresDef, ignore100, ignore200, ignore300, atk100, atk200, atk300
 function doRangedWeaponskill(attacker, target, wsID, params, tp, primary, action)
    local bonusTP = 0
    if (params.bonusTP ~= nil) then
        bonusTP = params.bonusTP
    end
    local multiHitfTP = false
    if (params.multiHitfTP ~= nil) then
        multiHitfTP = params.multiHitfTP
    end
    local bonusfTP, bonusacc = handleWSGorgetBelt(attacker)
    bonusacc = bonusacc + attacker:getMod(dsp.mod.WSACC)

    -- get fstr
    local fstr = fSTR(attacker:getStat(dsp.mod.STR),target:getStat(dsp.mod.VIT),attacker:getRangedDmgForRank())

    -- apply WSC
    local base = attacker:getRangedDmg() + fstr +
        (attacker:getStat(dsp.mod.STR) * params.str_wsc + attacker:getStat(dsp.mod.DEX) * params.dex_wsc +
         attacker:getStat(dsp.mod.VIT) * params.vit_wsc + attacker:getStat(dsp.mod.AGI) * params.agi_wsc +
         attacker:getStat(dsp.mod.INT) * params.int_wsc + attacker:getStat(dsp.mod.MND) * params.mnd_wsc +
         attacker:getStat(dsp.mod.CHR) * params.chr_wsc) * getAlpha(attacker:getMainLvl())

    -- Applying fTP multiplier
    local ftp = fTP(tp,params.ftp100,params.ftp200,params.ftp300) + bonusfTP
    local crit = false

    local ignoredDef = 0
    if (params.ignoresDef == not nil and params.ignoresDef == true) then
        ignoredDef = calculatedIgnoredDef(tp, target:getStat(dsp.mod.DEF), params.ignored100, params.ignored200, params.ignored300)
    end

    -- get cratio min and max
    local cratio, ccritratio = cRangedRatio( attacker, target, params, ignoredDef)
    local ccmin = 0
    local ccmax = 0
    local hasMightyStrikes = attacker:hasStatusEffect(dsp.effect.MIGHTY_STRIKES)
    local critrate = 0
    if (params.canCrit) then -- work out critical hit ratios, by +1ing
        critrate = fTP(tp,params.crit100,params.crit200,params.crit300)
        -- add on native crit hit rate (guesstimated, it actually follows an exponential curve)
        local nativecrit = (attacker:getStat(dsp.mod.DEX) - target:getStat(dsp.mod.AGI))*0.005; -- assumes +0.5% crit rate per 1 dDEX

        if (nativecrit > 0.2) then -- caps only apply to base rate, not merits and mods
            nativecrit = 0.2
        elseif (nativecrit < 0.05) then
            nativecrit = 0.05
        end

        nativecrit = nativecrit + (attacker:getMod(dsp.mod.CRITHITRATE)/100) + attacker:getMerit(dsp.merit.CRIT_HIT_RATE)/100 - target:getMerit(dsp.merit.ENEMY_CRIT_RATE)/100

        -- Handle Fencer
        local mainEquip = attacker:getStorageItem(0, 0, dsp.slot.MAIN)
        if mainEquip and not mainEquip:isTwoHanded() and not mainEquip:isHandToHand() then
            local subEquip = attacker:getStorageItem(0, 0, dsp.slot.SUB)
            if subEquip == nil or subEquip:getSkillType() == dsp.skill.NONE or subEquip:isShield() then
                nativecrit = nativecrit + attacker:getMod(dsp.mod.FENCER_CRITHITRATE) / 100
            end
        end

        if (attacker:hasStatusEffect(dsp.effect.INNIN) and attacker:isBehind(target, 23)) then -- Innin crit boost if attacker is behind target
            nativecrit = nativecrit + attacker:getStatusEffect(dsp.effect.INNIN):getPower()
        end

        critrate = critrate + nativecrit
    end

    local dmg = base * ftp

    -- Applying pDIF
    local pdif = generatePdif (cratio[1],cratio[2], false)

    -- First hit has 95% acc always. Second hit + affected by hit rate.
    local missChance = math.random()
    local finaldmg = 0
    local hitrate = getRangedHitRate(attacker,target,true,bonusacc)
    if (params.acc100~=0) then
        -- ACCURACY VARIES WITH TP, APPLIED TO ALL HITS.
        -- print("Accuracy varies with TP.")
        hr = accVariesWithTP(getRangedHitRate(attacker,target,false,bonusacc),attacker:getRACC(),tp,params.acc100,params.acc200,params.acc300)
        hitrate = hr
    end

    local tpHitsLanded = 0
    local shadowsAbsorbed = 0
    if (missChance <= hitrate) then
        if not shadowAbsorb(target) then
            if (params.canCrit) then
                local critchance = math.random()
                if (critchance <= critrate or hasMightyStrikes) then -- crit hit!
                    crit = true
                    local cpdif = generatePdif (ccritratio[1], ccritratio[2], false)
                    finaldmg = dmg * cpdif
                else
                    finaldmg = dmg * pdif
                end
            else
                finaldmg = dmg * pdif
            end
            tpHitsLanded = 1
        else
            shadowsAbsorbed = shadowsAbsorbed + 1
        end
    end

    -- Store first hit bonus for use after other calcs are done..
    local firstHitBonus = ((finaldmg * attacker:getMod(dsp.mod.ALL_WSDMG_FIRST_HIT))/100)

    local numHits = params.numHits

    if not multiHitfTP then dmg = base end
    local extraHitsLanded = 0
    if (numHits>1) then
        if (params.acc100==0) then
            -- work out acc since we actually need it now
            hitrate = getRangedHitRate(attacker,target,true,bonusacc)
        end

        hitsdone = 1
        while (hitsdone < numHits) do
            chance = math.random()
            if (chance<=hitrate) then -- it hit
                if not shadowAbsorb(target) then
                    pdif = generatePdif (cratio[1],cratio[2], false)
                    if (canCrit) then
                        critchance = math.random()
                        if (critchance <= critrate or hasMightyStrikes) then -- crit hit!
                            cpdif = generatePdif (ccritratio[1], ccritratio[2], false)
                            finaldmg = finaldmg + dmg * cpdif
                        else
                            finaldmg = finaldmg + dmg * pdif
                        end
                    else
                        finaldmg = finaldmg + dmg * pdif; -- NOTE: not using 'dmg' since fTP is 1.0 for subsequent hits!!
                    end
                    extraHitsLanded = extraHitsLanded + 1
                else
                    shadowsAbsorbed = shadowsAbsorbed + 1
                end
            end
            hitsdone = hitsdone + 1
        end
    end
    -- print("Landed " .. hitslanded .. "/" .. numHits .. " hits with hitrate " .. hitrate .. "!")

    -- DMG Bonus for any WS
    local bonusdmg = attacker:getMod(dsp.mod.ALL_WSDMG_ALL_HITS)

    -- Ws Specific DMG Bonus
    if (attacker:getMod(dsp.mod.WEAPONSKILL_DAMAGE_BASE + wsID) > 0) then
        bonusdmg = bonusdmg + attacker:getMod(dsp.mod.WEAPONSKILL_DAMAGE_BASE + wsID)
    end

    -- Add in bonusdmg
    finaldmg = finaldmg * ((100 + bonusdmg)/100)
    finaldmg = finaldmg + firstHitBonus

    -- Check for reductions
    finaldmg = target:rangedDmgTaken(finaldmg)
    finaldmg = finaldmg * target:getMod(dsp.mod.PIERCERES) / 1000

    finaldmg = finaldmg * WEAPON_SKILL_POWER
    finaldmg = takeWeaponskillDamage(target, attacker, params, primary, finaldmg, dsp.attackType.RANGED, attacker:getWeaponDamageType(dsp.slot.RANGED), dsp.slot.RANGED, tpHitsLanded, extraHitsLanded, shadowsAbsorbed, bonusTP, action, nil)
    return finaldmg, crit, tpHitsLanded, extraHitsLanded, shadowsAbsorbed
end

function getMultiAttacks(attacker, target, numHits)
    local bonusHits = 0
    local multiChances = 1
    local doubleRate = (attacker:getMod(dsp.mod.DOUBLE_ATTACK) + attacker:getMerit(dsp.merit.DOUBLE_ATTACK_RATE))/100
    local tripleRate = (attacker:getMod(dsp.mod.TRIPLE_ATTACK) + attacker:getMerit(dsp.merit.TRIPLE_ATTACK_RATE))/100
    local quadRate = attacker:getMod(dsp.mod.QUAD_ATTACK)/100
    local oaThriceRate = attacker:getMod(dsp.mod.MYTHIC_OCC_ATT_THRICE)/100
    local oaTwiceRate = attacker:getMod(dsp.mod.MYTHIC_OCC_ATT_TWICE)/100

    -- Add Ambush Augments to Triple Attack
    if (attacker:hasTrait(76) and attacker:isBehind(target, 23)) then -- TRAIT_AMBUSH
        tripleRate = tripleRate + attacker:getMerit(dsp.merit.AMBUSH) / 3; -- Value of Ambush is 3 per mert, augment gives +1 Triple Attack per merit
    end

    -- QA/TA/DA can only proc on the first hit of each weapon or each fist
    if (attacker:getOffhandDmg() > 0 or attacker:getWeaponSkillType(dsp.slot.MAIN) == dsp.skill.HAND_TO_HAND) then
        multiChances = 2
    end

    for i = 1, multiChances, 1 do
        if math.random() < quadRate then
            bonusHits = bonusHits + 3
        elseif math.random() < tripleRate then
            bonusHits = bonusHits + 2
        elseif math.random() < doubleRate then
            bonusHits = bonusHits + 1
        elseif (i == 1 and math.random() < oaThriceRate) then -- Can only proc on first hit
            bonusHits = bonusHits + 2
        elseif (i == 1 and math.random() < oaTwiceRate) then -- Can only proc on first hit
            bonusHits = bonusHits + 1
        end
        if (i == 1) then
            attacker:delStatusEffect(dsp.effect.ASSASSINS_CHARGE)
            attacker:delStatusEffect(dsp.effect.WARRIOR_S_CHARGE)

            -- recalculate DA/TA/QA rate
            doubleRate = (attacker:getMod(dsp.mod.DOUBLE_ATTACK) + attacker:getMerit(dsp.merit.DOUBLE_ATTACK_RATE))/100
            tripleRate = (attacker:getMod(dsp.mod.TRIPLE_ATTACK) + attacker:getMerit(dsp.merit.TRIPLE_ATTACK_RATE))/100
            quadRate = attacker:getMod(dsp.mod.QUAD_ATTACK)/100
        end
    end

    if ((numHits + bonusHits ) > 8) then
        return 8
    end
    return numHits + bonusHits
end

function generatePdif (cratiomin, cratiomax, melee)
    local pdif = math.random(cratiomin*1000, cratiomax*1000) / 1000
    if (melee) then
        pdif = pdif * (math.random(100,105)/100)
    end
    return pdif
end

function getStepAnimation(skill)
    if skill <= 1 then
        return 15
    elseif skill <= 3 then
        return 14
    elseif skill == 4 then
        return 19
    elseif skill == 5 then
        return 16
    elseif skill <= 7 then
        return 18
    elseif skill == 8 then
        return 20
    elseif skill == 9 then
        return 21
    elseif skill == 10 then
        return 22
    elseif skill == 11 then
        return 17
    elseif skill == 12 then
        return 23
    else
        return 0
    end
end

function getFlourishAnimation(skill)
    if skill <= 1 then
        return 25
    elseif skill <= 3 then
        return 24
    elseif skill == 4 then
        return 29
    elseif skill == 5 then
        return 26
    elseif skill <= 7 then
        return 28
    elseif skill == 8 then
        return 30
    elseif skill == 9 then
        return 31
    elseif skill == 10 then
        return 32
    elseif skill == 11 then
        return 27
    elseif skill == 12 then
        return 33
    else
        return 0
    end
end

function takeWeaponskillDamage(defender, attacker, params, primary, finaldmg, attackType, damageType, slot, tpHitsLanded, extraHitsLanded, shadowsAbsorbed, bonusTP, action, taChar)
    if tpHitsLanded + extraHitsLanded > 0 then
        if finaldmg >= 0 then
            if primary then
                action:messageID(defender:getID(), dsp.msg.basic.DAMAGE)
            else
                action:messageID(defender:getID(), dsp.msg.basic.DAMAGE_SECONDARY)
            end

            if finaldmg > 0 then
                action:reaction(defender:getID(), dsp.reaction.HIT)
                action:speceffect(defender:getID(), dsp.specEffect.RECOIL)
            end
        else
            if primary then
                action:messageID(defender:getID(), dsp.msg.basic.SELF_HEAL)
            else
                action:messageID(defender:getID(), dsp.msg.basic.SELF_HEAL_SECONDARY)
            end
        end
        action:param(defender:getID(), finaldmg)
    elseif shadowsAbsorbed > 0 then
        action:messageID(defender:getID(), dsp.msg.basic.SHADOW_ABSORB)
        action:param(defender:getID(), shadowsAbsorbed)
    else
        if primary then
            action:messageID(defender:getID(), dsp.msg.basic.SKILL_MISS)
        else
            action:messageID(defender:getID(), dsp.msg.basic.EVADES)
        end
        action:reaction(defender:getID(), dsp.reaction.EVADE)
    end
    local targetTPMult = params.targetTPMult or 1
    finaldmg = defender:takeWeaponskillDamage(attacker, finaldmg, attackType, damageType, slot, primary, tpHitsLanded, (extraHitsLanded * 10) + bonusTP, targetTPMult)
    local enmityEntity = taChar or attacker
    if (params.overrideCE and params.overrideVE) then
        defender:addEnmity(enmityEntity, params.overrideCE, params.overrideVE)
    else
        local enmityMult = params.enmityMult or 1
        defender:updateEnmityFromDamage(enmityEntity, finaldmg * enmityMult)
    end

    return finaldmg
end

function handleWSGorgetBelt(attacker)
    local ftpBonus = 0
    local accBonus = 0
    if (attacker:getObjType() == dsp.objType.PC) then
        -- TODO: Get these out of itemid checks when possible.
        local elementalGorget = { 15495, 15498, 15500, 15497, 15496, 15499, 15501, 15502 }
        local elementalBelt =   { 11755, 11758, 11760, 11757, 11756, 11759, 11761, 11762 }
        local neck = attacker:getEquipID(dsp.slot.NECK)
        local belt = attacker:getEquipID(dsp.slot.WAIST)
        local SCProp1, SCProp2, SCProp3 = attacker:getWSSkillchainProp()

        for i,v in ipairs(elementalGorget) do
            if (neck == v) then
                if (doesElementMatchWeaponskill(i, SCProp1) or doesElementMatchWeaponskill(i, SCProp2) or doesElementMatchWeaponskill(i, SCProp3)) then
                    accBonus = accBonus + 10
                    ftpBonus = ftpBonus + 0.1
                end
                break
            end
        end

        if (neck == 27510) then -- Fotia Gorget
            accBonus = accBonus + 10
            ftpBonus = ftpBonus + 0.1
        end

        for i,v in ipairs(elementalBelt) do
            if (belt == v) then
                if (doesElementMatchWeaponskill(i, SCProp1) or doesElementMatchWeaponskill(i, SCProp2) or doesElementMatchWeaponskill(i, SCProp3)) then
                    accBonus = accBonus + 10
                    ftpBonus = ftpBonus + 0.1
                end
                break
            end
        end

        if (belt == 28420) then -- Fotia Belt
            accBonus = accBonus + 10
            ftpBonus = ftpBonus + 0.1
        end
    end
    return ftpBonus, accBonus
end

function shadowAbsorb(target)
    local targShadows = target:getMod(dsp.mod.UTSUSEMI)
    local shadowType = dsp.mod.UTSUSEMI

    if targShadows == 0 then
        if math.random() < 0.8 then
            targShadows = target:getMod(dsp.mod.BLINK)
            shadowType = dsp.mod.BLINK
        end
    end

    if targShadows > 0 then
        if shadowType == dsp.mod.UTSUSEMI then
            local effect = target:getStatusEffect(dsp.effect.COPY_IMAGE)
            if effect then
                if targShadows - 1 == 1 then
                    effect:setIcon(dsp.effect.COPY_IMAGE)
                elseif targShadows - 1 == 2 then
                    effect:setIcon(dsp.effect.COPY_IMAGE_2)
                elseif targShadows - 1 == 3 then
                    effect:setIcon(dsp.effect.COPY_IMAGE_3)
                end
            end
        end
        target:setMod(shadowType, targShadows - 1)
        if targShadows - 1 == 0 then
            target:delStatusEffect(dsp.effect.COPY_IMAGE)
            target:delStatusEffect(dsp.effect.COPY_BLINK)
        end
        return true
    end
    return false
end
