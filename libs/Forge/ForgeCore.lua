-- ============================================================
--  ForgeCore.lua
--  ForgeDMC Toolkit
--
--  Replaces: AceAddon-3.0 + AceEvent-3.0 + AceConsole-3.0
-- ============================================================

local ForgeCore = {}
_G.ForgeCore = ForgeCore

local registry = {}
local eventListeners = {}
local bootstrap = CreateFrame("Frame")

local function safeCall(target, method, ...)
    if type(method) == "function" then
        local ok, err = pcall(method, target, ...)
        if not ok then
            geterrorhandler()(err)
        end
        return
    end

    if type(method) == "string" and type(target[method]) == "function" then
        local ok, err = pcall(target[method], target, ...)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

local function dispatchEvent(event, ...)
    local listeners = eventListeners[event]
    if not listeners then
        return
    end

    for object, handler in pairs(listeners) do
        safeCall(object, handler, event, ...)
    end
end

local function ensureEvent(event)
    if not bootstrap:IsEventRegistered(event) then
        bootstrap:RegisterEvent(event)
    end
end

local objectMethods = {}

function objectMethods:GetName()
    return self.name
end

function objectMethods:IsEnabled()
    return self._forge.enabled ~= false
end

function objectMethods:SetEnabledState(enabled)
    self._forge.enabled = not not enabled
end

function objectMethods:Enable()
    if self._forge.runtimeEnabled then
        return
    end

    self._forge.runtimeEnabled = true
    if type(self.OnEnable) == "function" then
        safeCall(self, "OnEnable")
    end
end

function objectMethods:Disable()
    if not self._forge.runtimeEnabled then
        return
    end

    self._forge.runtimeEnabled = false
    self:UnregisterAllEvents()

    if type(self.OnDisable) == "function" then
        safeCall(self, "OnDisable")
    end
end

function objectMethods:RegisterEvent(event, handler)
    if type(event) ~= "string" then
        error("ForgeCore:RegisterEvent(event, handler) requires an event name")
    end

    handler = handler or event
    if type(handler) ~= "string" and type(handler) ~= "function" then
        error("ForgeCore:RegisterEvent() handler must be a method name or function")
    end

    eventListeners[event] = eventListeners[event] or {}
    eventListeners[event][self] = handler
    self._forge.events[event] = true
    ensureEvent(event)
end

function objectMethods:UnregisterEvent(event)
    local listeners = eventListeners[event]
    if not listeners then
        return
    end

    listeners[self] = nil
    self._forge.events[event] = nil

    if not next(listeners) then
        eventListeners[event] = nil
        if event ~= "ADDON_LOADED" and event ~= "PLAYER_LOGIN" then
            bootstrap:UnregisterEvent(event)
        end
    end
end

function objectMethods:UnregisterAllEvents()
    for event in pairs(self._forge.events) do
        self:UnregisterEvent(event)
    end
end

function objectMethods:RegisterChatCommand(commands, handler)
    if type(commands) == "string" then
        commands = { commands }
    end

    if type(commands) ~= "table" then
        error("ForgeCore:RegisterChatCommand() commands must be a string or table")
    end

    if type(handler) ~= "string" and type(handler) ~= "function" then
        error("ForgeCore:RegisterChatCommand() handler must be a method name or function")
    end

    for _, command in ipairs(commands) do
        local token = (self.name .. "_" .. command):upper():gsub("[^A-Z0-9]", "")
        SlashCmdList[token] = function(msg)
            safeCall(self, handler, msg or "")
        end
        _G["SLASH_" .. token .. "1"] = "/" .. command
        self._forge.commands[command] = token
    end
end

function objectMethods:UnregisterChatCommand(command)
    local token = self._forge.commands[command]
    if not token then
        return
    end

    SlashCmdList[token] = nil
    _G["SLASH_" .. token .. "1"] = nil
    self._forge.commands[command] = nil
end

function objectMethods:Print(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = tostring(select(index, ...))
    end

    local message = table.concat(parts, " ")
    DEFAULT_CHAT_FRAME:AddMessage("|cff00b4ff" .. self.name .. "|r: " .. message)
end

function objectMethods:Printf(fmt, ...)
    self:Print(string.format(fmt, ...))
end

--- Print a red error message to the default chat frame.
function objectMethods:PrintError(msg)
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffff4040" .. self.name .. "|r: " .. tostring(msg))
end

function objectMethods:NewModule(name, moduleObject)
    if type(name) ~= "string" or name == "" then
        error("ForgeCore:NewModule() requires a module name")
    end

    local module = moduleObject or {}
    for key, value in pairs(objectMethods) do
        if module[key] == nil then
            module[key] = value
        end
    end

    module.name = self.name .. ":" .. name
    module.moduleName = name
    module.parent = self
    module._forge = {
        initialized = false,
        runtimeEnabled = false,
        enabled = true,
        events = {},
        commands = {},
    }

    self.modules[name] = module

    if self._forge.initialized and not module._forge.initialized then
        module._forge.initialized = true
        if type(module.OnInitialize) == "function" then
            safeCall(module, "OnInitialize")
        end
    end

    if IsLoggedIn() and self._forge.runtimeEnabled and module:IsEnabled() then
        module:Enable()
    end

    return module
end

--- Return a named sub-module.
-- @param name    string
-- @param silent  boolean  If true, return nil for unknown modules instead of erroring.
function objectMethods:GetModule(name, silent)
    local m = self.modules[name]
    if not m and not silent then
        error("ForgeCore:GetModule() - unknown module '" .. tostring(name)
            .. "' on addon '" .. tostring(self.name) .. "'")
    end
    return m
end

function objectMethods:IterateModules()
    return pairs(self.modules)
end

function objectMethods:OpenOptions()
    if self.optionsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.optionsCategory:GetID())
    end
end

function ForgeCore:NewAddon(name, addonObject)
    if type(name) ~= "string" or name == "" then
        error("ForgeCore:NewAddon() requires an addon name")
    end

    local addon = addonObject or {}
    for key, value in pairs(objectMethods) do
        if addon[key] == nil then
            addon[key] = value
        end
    end

    addon.name = name
    addon.modules = addon.modules or {}
    addon._forge = addon._forge or {
        initialized = false,
        runtimeEnabled = false,
        enabled = true,
        events = {},
        commands = {},
    }

    registry[name] = addon
    return addon
end

--- Retrieve a registered addon by name.
-- @param name  string
-- @return      addon object or nil
function ForgeCore:GetAddon(name)
    return registry[name]
end

--- Iterate over all registered addons.
-- Usage: for name, addon in ForgeCore:IterateAddons() do ... end
function ForgeCore:IterateAddons()
    return pairs(registry)
end

bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        local addon = registry[addonName]
        if addon and not addon._forge.initialized then
            addon._forge.initialized = true
            if type(addon.OnInitialize) == "function" then
                safeCall(addon, "OnInitialize")
            end

            for _, module in addon:IterateModules() do
                if not module._forge.initialized then
                    module._forge.initialized = true
                    if type(module.OnInitialize) == "function" then
                        safeCall(module, "OnInitialize")
                    end
                end
            end
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        for _, addon in pairs(registry) do
            if addon:IsEnabled() then
                addon:Enable()
                for _, module in addon:IterateModules() do
                    if module:IsEnabled() then
                        module:Enable()
                    end
                end
            end
        end
        return
    end

    dispatchEvent(event, ...)
end)