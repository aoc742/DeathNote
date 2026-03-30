-- ============================================================
--  ForgeHook.lua
--  ForgeDMC Toolkit
--
--  Replaces: AceHook-3.0
-- ============================================================

local ForgeHook = {}
_G.ForgeHook = ForgeHook

local methods = {}
local hookStore = setmetatable({}, { __mode = "k" })

local function resolveHandler(self, handler, ...)
    if type(handler) == "function" then
        return handler(self, ...)
    end

    if type(handler) == "string" and type(self[handler]) == "function" then
        return self[handler](self, ...)
    end

    error("ForgeHook handler must be a function or method name")
end

local function getStore(self, target)
    hookStore[self] = hookStore[self] or setmetatable({}, { __mode = "k" })
    hookStore[self][target] = hookStore[self][target] or {}
    return hookStore[self][target]
end

function methods:Hook(target, methodName, handler)
    if type(target) ~= "table" then
        error("ForgeHook:Hook() requires a target table")
    end

    local original = target[methodName]
    if type(original) ~= "function" then
        error("ForgeHook:Hook() target method not found: " .. tostring(methodName))
    end

    local store = getStore(self, target)
    if store[methodName] then
        error("ForgeHook:Hook() method already hooked: " .. tostring(methodName))
    end

    store[methodName] = original
    target[methodName] = function(...)
        local results = { original(...) }
        resolveHandler(self, handler, ...)
        return unpack(results)
    end
end

function methods:HookScript(frame, scriptName, handler)
    if type(frame) ~= "table" or type(frame.GetScript) ~= "function" then
        error("ForgeHook:HookScript() requires a frame")
    end

    local original = frame:GetScript(scriptName)
    local store = getStore(self, frame)
    if store[scriptName] then
        error("ForgeHook:HookScript() script already hooked: " .. tostring(scriptName))
    end

    store[scriptName] = original or false
    frame:SetScript(scriptName, function(...)
        if original then
            original(...)
        end
        resolveHandler(self, handler, ...)
    end)
end

function methods:SecureHook(target, methodName, handler)
    if type(target) == "string" then
        local globalName = target
        if type(_G[globalName]) ~= "function" then
            error("ForgeHook:SecureHook() global function not found: " .. globalName)
        end
        hooksecurefunc(globalName, function(...)
            resolveHandler(self, handler, ...)
        end)
        -- Track for IsSecureHooked queries.
        local store = getStore(self, {})
        store["__secure_" .. globalName] = true
        return
    end

    if type(target) ~= "table" or type(target[methodName]) ~= "function" then
        error("ForgeHook:SecureHook() target method not found")
    end

    hooksecurefunc(target, methodName, function(...)
        resolveHandler(self, handler, ...)
    end)
    -- Track for IsSecureHooked queries.
    local store = getStore(self, target)
    store["__secure_" .. methodName] = true
end

function methods:Unhook(target, methodName)
    local store = hookStore[self] and hookStore[self][target]
    if not store or store[methodName] == nil then
        return
    end

    if store[methodName] ~= false then
        target[methodName] = store[methodName]
    end

    store[methodName] = nil
end

--- Alias: unhook a specific frame script (same as Unhook for frames).
function methods:UnhookScript(frame, scriptName)
    self:Unhook(frame, scriptName)
end

--- Returns true if this object has hooked the named method on target.
function methods:IsHooked(target, methodName)
    local store = hookStore[self] and hookStore[self][target]
    return store ~= nil and store[methodName] ~= nil
end

--- Returns true if a secure hook (hooksecurefunc) was placed on the target.
-- Note: secure hooks are permanent; this only tracks whether THIS object placed one.
function methods:IsSecureHooked(target, methodName)
    -- We track secure hooks in a separate table keyed by "__secure"
    local secKey = "__secure_" .. (type(target) == "string" and target or methodName)
    local store  = hookStore[self] and hookStore[self][secKey]
    return store ~= nil
end

function methods:UnhookAll()
    if not hookStore[self] then
        return
    end

    for target, methodsForTarget in pairs(hookStore[self]) do
        for methodName, original in pairs(methodsForTarget) do
            if original ~= false then
                target[methodName] = original
            end
        end
    end

    hookStore[self] = nil
end

function ForgeHook:Embed(target)
    for key, value in pairs(methods) do
        target[key] = value
    end
    return target
end