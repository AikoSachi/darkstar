---------------------------------------------
--  Drop Hammer
--
--  Description: Drops the hammer. Additional effect: Bind
--  Type: Physical
--  Utsusemi/Blink absorb: 2-3 shadows?
--  Range: Melee
--  Notes: Only used by "destroyers" (carrying massive warhammers).
---------------------------------------------

require("/scripts/globals/settings");
require("/scripts/globals/status");
require("/scripts/globals/monstertpmoves");

---------------------------------------------

function OnMobWeaponSkill(target, mob, skill)

    power = 1;
    tic = 0;
    duration = 120;

    isEnfeeble = true;
    typeEffect = EFFECT_BIND;
    statmod = MOD_INT;
    resist = applyPlayerResistance(mob,skill,target,isEnfeeble,typeEffect,statmod);
    if(resist > 0.5) then
        if(target:getStatusEffect(typeEffect) == nil) then
            target:addStatusEffect(typeEffect,power,tic,duration);
        end
    end
	
    numhits = 1;
    accmod = 1;
    dmgmod = 1;
    info = MobPhysicalMove(mob,target,skill,numhits,accmod,dmgmod,TP_NO_EFFECT);
    dmg = MobFinalAdjustments(info.dmg,mob,skill,target,MOBSKILL_PHYSICAL,MOBPARAM_NONE,MOBPARAM_3_SHADOW);
    target:delHP(dmg);
	
    return dmg;
end;