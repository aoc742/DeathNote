local name, ns = ...
ns.DeathEvents = {}
local DeathEvents = ns.DeathEvents
local L = ForgeLocale:Get("DeathNote")

-- After 12.0.0 Midnight (Addon Apocalypse), there are 2 cases where you can collect combat log data:
-- 1. When you are in combat (PLAYER_REGEN_DISABLED). In this case, combat log events are 
--    now limited to addons. This affects times where you may want to view your death log 
--    but combat is still enabled. Examples:
--      a. You died in a raid, but your raid group has not full-wiped. 
--      b. You died in a dungeon, but your party is still alive and in combat.
--      c. You died in PvP, but the Arena or Battleground match is still going on.
-- 2. When you leave combat (PLAYER_REGEN_ENABLED). Once combat ends for you and your entire group,
--    the API allows more details on the combat log events that previouslly occurred during combat.

-- Here's the general flow of how the addon captures death data:
-- 1. Await for combat to start. 
-- 2. 


-- Store global values that are called a lot as locals because global _G indexing is slow.
local C_Secrets = C_Secrets
local C_InstanceEncounter = C_InstanceEncounter


-- Returns true if Combat secret restrictions are enabled.
-- This check is relevant after 12.0.0 Midnight expansions changes (aka Addon Apocalypse)
function DeathEvents:SecretRestrictionsEnabled(includeAuras)
    if C_Secrets and (C_Secrets.ShouldCooldownsBeSecret() or C_Secrets.ShouldAurasBeSecret()) then
        return true
    end

    -- Backup check just in case the above new API calls fail.
    if (C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress) then 
        return true
    end
    return false
end