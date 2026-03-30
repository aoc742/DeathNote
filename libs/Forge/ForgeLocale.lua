-- ============================================================
--  ForgeLocale.lua  |  v1.1.0
--  ForgeDMC Toolkit
--
--  Replaces : AceLocale-3.0
--  Author   : ForgeDMC  |  2026-03-21  |  MIT
--
--  FIXES v1.1.0
--  ------------
--  * Complete rewrite — the previous file contained a copy of
--    ForgeWidgets.lua and registered _G.ForgeWidgets instead of
--    _G.ForgeLocale. No locale system existed at all.
--
--  HOW IT WORKS
--  ------------
--  Each supported language is registered as a separate proxy table.
--  ForgeLocale:Get() returns the proxy for the current client locale,
--  falling back to enUS if the client locale was not registered.
--  Reading any key from the proxy returns:
--    1. The registered translation for that locale
--    2. The enUS translation (fallback)
--    3. The key string itself (final fallback — never nil, never errors)
--
--  USAGE
--  -----
--  -- Locale-enUS.lua  (loaded first, acts as the master string list):
--  local L = ForgeLocale:Register("MyAddon", "enUS")
--  L["Open Settings"]  = true    -- true = use the key itself as the string
--  L["Toggle Frame"]   = true
--  L["Version: %s"]    = true
--
--  -- Locale-deDE.lua:
--  local L = ForgeLocale:Register("MyAddon", "deDE")
--  L["Open Settings"]  = "Einstellungen öffnen"
--  L["Toggle Frame"]   = "Rahmen umschalten"
--  -- "Version: %s" not listed → falls back to enUS automatically
--
--  -- In MyAddon.lua:
--  local L = ForgeLocale:Get("MyAddon")
--  print(L["Open Settings"])            -- locale-correct string
--  print(L["Version: %s"]:format("1.2"))
--  print(L["Unknown key"])              -- returns "Unknown key" (safe)
--
--  -- Debug:
--  ForgeLocale:GetRegisteredLocales("MyAddon")  -- { "deDE", "enUS" }
--  ForgeLocale.locale                           -- e.g. "enUS"
-- ============================================================

ForgeLocale       = ForgeLocale or {}
ForgeLocale.locale = GetLocale()   -- client locale; set once at load time

-- Internal registry.
-- _registry[addonName][locale] = { rawData={}, proxy=proxyTable }
local _registry = {}

-- ── Proxy factory ─────────────────────────────────────────────
-- Returns a table whose __newindex writes into rawData and whose
-- __index looks up rawData then falls back to enUS then to the key.

local function makeProxy(addonName, locale, rawData)
    return setmetatable({}, {

        __newindex = function(_, key, value)
            -- L["key"] = true  → use key as-is (enUS pattern)
            -- L["key"] = "str" → use the explicit translation
            if value == true then
                rawData[key] = key
            elseif value ~= false and value ~= nil then
                rawData[key] = tostring(value)
            end
        end,

        __index = function(_, key)
            -- 1. This locale's own data.
            local v = rawData[key]
            if v ~= nil then return v end

            -- 2. enUS fallback (only if this is not already enUS).
            if locale ~= "enUS" then
                local addonReg = _registry[addonName]
                if addonReg then
                    local enEntry = addonReg["enUS"]
                    if enEntry then
                        local ev = enEntry.rawData[key]
                        if ev ~= nil then return ev end
                    end
                end
            end

            -- 3. Return the key itself — always a non-nil string.
            return key
        end,

        -- Allow debug iteration over this locale's translations.
        __pairs = function(_)
            return pairs(rawData)
        end,

        __tostring = function(_)
            return "ForgeLocale[" .. addonName .. "/" .. locale .. "]"
        end,
    })
end

-- ── Public API ────────────────────────────────────────────────

--- Register (or retrieve) a locale table for an addon.
-- Call this at the top of each locale file, before assigning translations.
--
-- @param addonName  string   Must match the ForgeCore addon name
-- @param locale     string   e.g. "enUS", "deDE", "zhCN", "koKR"
-- @return proxy     table    Assign translations: L["key"] = "value" or true
function ForgeLocale:Register(addonName, locale)
    assert(type(addonName) == "string" and addonName ~= "",
        "ForgeLocale:Register - addonName must be a non-empty string")
    assert(type(locale) == "string" and locale ~= "",
        "ForgeLocale:Register - locale must be a non-empty string")

    _registry[addonName] = _registry[addonName] or {}

    -- Idempotent: return existing proxy if called twice.
    if _registry[addonName][locale] then
        return _registry[addonName][locale].proxy
    end

    local rawData = {}
    local proxy   = makeProxy(addonName, locale, rawData)

    _registry[addonName][locale] = { rawData = rawData, proxy = proxy }

    return proxy
end

--- Retrieve the active locale proxy for use in addon code.
-- Returns the proxy for the current client locale if registered,
-- falls back to enUS, then to the first registered locale.
-- If nothing is registered at all, returns a safe no-op proxy.
--
-- @param addonName  string
-- @return proxy     table   L["key"] → translation or key
function ForgeLocale:Get(addonName)
    assert(type(addonName) == "string" and addonName ~= "",
        "ForgeLocale:Get - addonName must be a non-empty string")

    local addonReg = _registry[addonName]
    if not addonReg then
        -- Nothing registered for this addon — return a harmless proxy.
        return setmetatable({}, { __index = function(_, key) return key end })
    end

    -- Try client locale first.
    local clientLocale = self.locale
    if addonReg[clientLocale] then
        return addonReg[clientLocale].proxy
    end

    -- Fall back to enUS.
    if addonReg["enUS"] then
        return addonReg["enUS"].proxy
    end

    -- Last resort: first registered locale (deterministic via table iteration).
    local firstLocale = next(addonReg)
    if firstLocale then
        return addonReg[firstLocale].proxy
    end

    return setmetatable({}, { __index = function(_, key) return key end })
end

--- Return a sorted list of locale codes registered for an addon.
-- @param addonName  string
-- @return list      table   e.g. { "deDE", "enUS", "frFR" }
function ForgeLocale:GetRegisteredLocales(addonName)
    local list     = {}
    local addonReg = _registry[addonName]
    if not addonReg then return list end
    for loc in pairs(addonReg) do
        list[#list + 1] = loc
    end
    table.sort(list)
    return list
end

--- Returns true if a locale has been registered for an addon.
function ForgeLocale:IsLocaleRegistered(addonName, locale)
    local addonReg = _registry[addonName]
    return addonReg ~= nil and addonReg[locale] ~= nil
end

--- Return a raw copy of all translations for a specific locale (for debug/export).
-- @return table  { key = translation, ... }
function ForgeLocale:DumpLocale(addonName, locale)
    local addonReg = _registry[addonName]
    if not addonReg or not addonReg[locale] then return {} end
    local copy = {}
    for k, v in pairs(addonReg[locale].rawData) do copy[k] = v end
    return copy
end
