-----------------------------------
-- Area: Lower Delkfutt's Tower
--  MOB: Magic Pot
-----------------------------------
require("scripts/globals/regimes")
-----------------------------------

function onMobDeath(mob, player, isKiller)
    dsp.regime.checkRegime(player, mob, 781, 2, dsp.regime.type.GROUNDS)
end