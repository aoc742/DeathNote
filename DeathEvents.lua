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
local InCombatLockdown = InCombatLockdown
local UnitAffectingCombat = UnitAffectingCombat


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

-- TODO function issecretvalue 

-- UNIT_DIED not necessary for death logs in midnight???


function DeathEvents:CombatStarted()
    -- Triggered by ENCOUNTER_START, UNIT_HEALTH, or PLAYER_REGEN_DISABLED
end

-- Check if any group member is in combat
function DeathEvents:GroupInCombat()

end


-- 
function DeathEvents:StartLogging()
    -- if IsLoggableContent()
end

function DeathEvents:PLAYER_REGEN_DISABLED()
    self:CombatStarted()
end

local devtest

function DeathEvents:Test()
    ns.DeathNote:Debug("Test command called")

    -- Returns the list of combat sessions in 
    local availableSessions = C_DamageMeter.GetAvailableCombatSessions()
	devtest.availableSessions = availableSessions

    local combatSession, name, durationSeconds = availableSessions[5]
    local session = C_DamageMeter.GetCombatSessionFromID(combatSession.sessionID, Enum.DamageMeterType.Deaths)
    devtest.session = session
    local listOfDeathsInSession = session.combatSources -- This is of type DamageMeterCombatSource (https://warcraft.wiki.gg/wiki/API_C_DamageMeter.GetCombatSessionFromType)

    local recapID = listOfDeathsInSession[3].deathRecapID
    local recap = C_DeathRecap.GetRecapEvents(recapID)
    devtest.recap = recap


    combatSession, name, durationSeconds = availableSessions[18]
    local session18 = C_DamageMeter.GetCombatSessionFromID(combatSession.sessionID, Enum.DamageMeterType.Deaths)
    devtest.session18 = session18

    local hasEvents = C_DeathRecap.HasRecapEvents(session18.combatSources[1].deathRecapID)
    devtest.hasEvents18 = hasEvents
    local recapEvents = C_DeathRecap.GetRecapEvents(session18.combatSources[1].deathRecapID)
    devtest.recapEvents18 = recapEvents
end

function DeathEvents:Initialize()
    devtest = DeathNoteData.devtest or {}
    -- ns.DeathNote:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")
    -- ns.DeathNote:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED")
    -- ns.DeathNote:RegisterEvent("ENCOUNTER_WARNING")
    -- ns.DeathNote:RegisterEvent("PLAYER_REGEN_DISABLED", ns.DeathEvents.PLAYER_REGEN_DISABLED)
end