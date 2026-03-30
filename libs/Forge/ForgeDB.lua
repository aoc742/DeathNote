-- ============================================================
--  ForgeDB.lua  |  v1.1.0
--  ForgeDMC Toolkit
--
--  Replaces : AceDB-3.0
--  Author   : ForgeDMC  |  2026-03-21  |  MIT
--
--  FIXES v1.1.0
--  ------------
--  * ForgeDB:New() constructor written (was entirely missing)
--  * Removed duplicate file body that caused Lua syntax error on load
--  * char scope key uses UnitName+GetRealmName for per-character uniqueness
--  * applyDefaults: fixed edge-case where a non-table target[k] blocked
--    a table-typed default from being stamped
--  * DeleteProfile now asserts the profile exists before nil-ing it
--
--  SCOPES
--  ------
--  db.global   — account-wide, shared across all characters
--  db.char     — per-character, keyed as "Name-Realm"
--  db.profile  — switchable named profiles
--
--  USAGE
--  -----
--  -- In your .toc:
--  ## SavedVariables: MyAddonDB
--
--  -- In OnInitialize:
--  self.db = ForgeDB:New("MyAddonDB", {
--      global  = { seenVersion = 0 },
--      char    = { lastZone = "" },
--      profile = { scale = 1.0, showFrame = true },
--  })
--
--  self.db.global.seenVersion = 1
--  self.db.char.lastZone      = "Stormwind City"
--  self.db.profile.scale      = 1.5
--
--  self.db:SetProfile("Tank")
--  self.db:CopyProfile("Default")
--  self.db:ResetProfile()
--  self.db:GetProfiles()        -- { "Default", "Tank", ... }
--  self.db:DeleteProfile("Old")
--  self.db:RegisterCallback("OnProfileChanged", function(db, name) end)
-- ============================================================

ForgeDB = ForgeDB or {}

-- ── Utilities ─────────────────────────────────────────────────

local function deepCopy(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do t[k] = deepCopy(v) end
    return t
end

-- Non-destructive deep merge: write default values for any missing key.
local function applyDefaults(target, defaults)
    if type(defaults) ~= "table" or type(target) ~= "table" then return end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                -- target[k] is nil or a primitive — stamp a deep copy of the default.
                target[k] = deepCopy(v)
            else
                applyDefaults(target[k], v)
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

-- Character scope key — unique per character+realm combination.
local function charKey()
    local name  = UnitName("player") or "Unknown"
    local realm = GetRealmName()     or "Unknown"
    return name .. "-" .. realm
end

-- ── DB Prototype ──────────────────────────────────────────────

local DB = {}
DB.__index = DB

-- ·· Callbacks ·················································
-- Supports multiple callbacks per event, keyed by an optional tag.
-- Usage:
--   db:RegisterCallback("OnProfileChanged", fn)        -- anonymous
--   db:RegisterCallback("OnProfileChanged", fn, "tag") -- tagged (replaceable)

function DB:RegisterCallback(event, fn, tag)
    self.__cbs = self.__cbs or {}
    self.__cbs[event] = self.__cbs[event] or {}
    local key = tag or fn
    self.__cbs[event][key] = fn
end

function DB:UnregisterCallback(event, tag_or_fn)
    if not (self.__cbs and self.__cbs[event]) then return end
    self.__cbs[event][tag_or_fn] = nil
end

function DB:_fire(event, ...)
    if not (self.__cbs and self.__cbs[event]) then return end
    for _, fn in pairs(self.__cbs[event]) do
        fn(self, ...)
    end
end

-- ·· Profile API ···············································

function DB:GetCurrentProfile()
    return self.__sv.currentProfile or "Default"
end

function DB:SetProfile(name)
    name                      = name or "Default"
    self.__sv.currentProfile  = name
    self.__sv.profiles[name]  = self.__sv.profiles[name] or {}
    applyDefaults(self.__sv.profiles[name], self.__defaults.profile)
    self.profile = self.__sv.profiles[name]
    self:_fire("OnProfileChanged", name)
end

function DB:CopyProfile(fromName, silent)
    local src = self.__sv.profiles[fromName]
    if not src then
        if silent then return end
        error("ForgeDB:CopyProfile - profile '" .. tostring(fromName) .. "' does not exist")
    end
    local cur = self:GetCurrentProfile()
    self.__sv.profiles[cur] = deepCopy(src)
    applyDefaults(self.__sv.profiles[cur], self.__defaults.profile)
    self.profile = self.__sv.profiles[cur]
    self:_fire("OnProfileChanged", cur)
end

function DB:ResetProfile()
    local cur = self:GetCurrentProfile()
    self.__sv.profiles[cur] = {}
    applyDefaults(self.__sv.profiles[cur], self.__defaults.profile)
    self.profile = self.__sv.profiles[cur]
    self:_fire("OnProfileChanged", cur)
end

function DB:GetProfiles()
    local list = {}
    for name in pairs(self.__sv.profiles) do
        list[#list + 1] = name
    end
    table.sort(list)
    return list
end

--- Returns true if a profile with the given name exists (including the active one).
function DB:HasProfile(name)
    return self.__sv.profiles[name] ~= nil
end

--- Returns the character scope key ("Name-Realm") for the current character.
-- Useful for debugging or manual data inspection.
function DB:GetCharKey()
    return charKey()
end

function DB:DeleteProfile(name)
    assert(name ~= self:GetCurrentProfile(),
        "ForgeDB:DeleteProfile - cannot delete the active profile '" .. tostring(name) .. "'")
    assert(self.__sv.profiles[name] ~= nil,
        "ForgeDB:DeleteProfile - profile '" .. tostring(name) .. "' does not exist")
    self.__sv.profiles[name] = nil
end

-- ── Constructor ───────────────────────────────────────────────

--- Create a new database proxy backed by a SavedVariables global.
-- @param svName   string   Must match ## SavedVariables: <svName> in your .toc
-- @param defaults table    Optional: { global={}, char={}, profile={} }
-- @return db      table    Proxy with .global / .char / .profile scopes
function ForgeDB:New(svName, defaults)
    assert(type(svName) == "string" and svName ~= "",
        "ForgeDB:New - svName must be a non-empty string")

    defaults         = defaults or {}
    defaults.global  = defaults.global  or {}
    defaults.char    = defaults.char    or {}
    defaults.profile = defaults.profile or {}

    -- WoW loads the SavedVariables global before ADDON_LOADED fires.
    -- Guard in case it's somehow absent.
    if type(_G[svName]) ~= "table" then _G[svName] = {} end
    local sv = _G[svName]

    -- Ensure top-level scope containers exist.
    sv.global   = sv.global   or {}
    sv.chars    = sv.chars    or {}
    sv.profiles = sv.profiles or {}

    -- Apply defaults into the global scope.
    applyDefaults(sv.global, defaults.global)

    -- Resolve the active profile (default to "Default").
    local profileName        = sv.currentProfile or "Default"
    sv.currentProfile        = profileName
    sv.profiles[profileName] = sv.profiles[profileName] or {}
    applyDefaults(sv.profiles[profileName], defaults.profile)

    -- Resolve the char scope for the current character.
    local ckey     = charKey()
    sv.chars[ckey] = sv.chars[ckey] or {}
    applyDefaults(sv.chars[ckey], defaults.char)

    -- Build the proxy object.
    local db      = setmetatable({}, DB)
    db.__sv       = sv
    db.__defaults = defaults
    db.global     = sv.global
    db.char       = sv.chars[ckey]
    db.profile    = sv.profiles[profileName]

    return db
end
