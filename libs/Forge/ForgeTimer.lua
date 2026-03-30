-- ============================================================
--  ForgeTimer.lua  |  v1.1.0
--  ForgeDMC Toolkit
--
--  Replaces : AceTimer-3.0 · AceBucket-3.0
--  Author   : ForgeDMC  |  2026-03-21  |  MIT
--
--  FIXES v1.1.0
--  ------------
--  * Fixed invoke(): function callbacks now receive self as the first
--    argument, making them consistent with method-name callbacks.
--    Previous behaviour: callback(...) — self was silently dropped.
--    Fixed behaviour:    callback(self, ...) — matches method calls.
--  * Added Throttle(key, interval, callback, ...) — fires immediately
--    on the first call, then silently drops subsequent calls until the
--    interval has elapsed. Complements Debounce.
--  * Added CancelDebounce(key) — cancel a pending debounce by key.
--  * CancelAllTimers now also cancels pending debounce and throttle handles.
--
--  USAGE
--  -----
--  ForgeTimer:Embed(MyAddon)
--
--  -- One-shot:
--  local h = self:ScheduleTimer("OnTimeout", 2.0)
--  local h = self:ScheduleTimer(function(self) end, 2.0)
--  self:CancelTimer(h)
--  self:IsTimerActive(h)
--
--  -- Repeating:
--  local h = self:ScheduleRepeatingTimer("OnTick", 0.5)
--  self:CancelTimer(h)
--
--  -- Debounce (restart delay on every call; fire once after silence):
--  self:Debounce("myKey", 0.3, "OnSettled", arg1)
--  self:CancelDebounce("myKey")
--
--  -- Throttle (fire immediately, then block for interval):
--  self:Throttle("myKey", 1.0, "OnAction")
--
--  -- Bucket events (coalesce rapid events; fire handler with all payloads):
--  self:RegisterBucketEvent("BAG_UPDATE", 0.2, "OnBagUpdate")
--  -- handler(self, event, payloads)  where payloads = {{...},{...},...}
--  self:UnregisterBucketEvent("BAG_UPDATE")
--
--  -- Cancel everything (call from OnDisable):
--  self:CancelAllTimers()
-- ============================================================

local ForgeTimer = {}
_G.ForgeTimer = ForgeTimer

local methods = {}

-- ── invoke ────────────────────────────────────────────────────
-- Calls the callback as a method on self (string) or as a function.
-- Function callbacks receive self as the first argument so all callbacks
-- have a consistent calling convention.

local function invoke(self, callback, ...)
    if type(callback) == "function" then
        callback(self, ...)   -- FIX: was callback(...), now passes self
        return
    end
    if type(callback) == "string" then
        local fn = self[callback]
        if type(fn) == "function" then
            fn(self, ...)
            return
        end
        error("ForgeTimer: method '" .. callback .. "' not found on object '" .. tostring(self.name or self) .. "'")
    end
    error("ForgeTimer: callback must be a function or method name string, got " .. type(callback))
end

-- ── One-shot timer ────────────────────────────────────────────

function methods:ScheduleTimer(callback, delay, ...)
    self._forgeTimers     = self._forgeTimers or {}
    self._forgeTimerMeta  = self._forgeTimerMeta or {}
    local args = { ... }
    local handle

    handle = C_Timer.NewTimer(delay, function()
        if self._forgeTimers     then self._forgeTimers[handle]    = nil end
        if self._forgeTimerMeta  then self._forgeTimerMeta[handle] = nil end
        invoke(self, callback, unpack(args))
    end)

    self._forgeTimers[handle]   = true
    self._forgeTimerMeta[handle] = { start = GetTime(), delay = delay, repeating = false }
    return handle
end

-- ── Repeating timer ───────────────────────────────────────────

function methods:ScheduleRepeatingTimer(callback, interval, ...)
    self._forgeTimers     = self._forgeTimers or {}
    self._forgeTimerMeta  = self._forgeTimerMeta or {}
    local args = { ... }

    local handle = C_Timer.NewTicker(interval, function()
        invoke(self, callback, unpack(args))
    end)

    self._forgeTimers[handle]    = true
    self._forgeTimerMeta[handle] = { start = GetTime(), delay = interval, repeating = true }
    return handle
end

-- ── Cancel ────────────────────────────────────────────────────

function methods:CancelTimer(handle)
    if not handle then return end
    if self._forgeTimers and self._forgeTimers[handle] then
        handle:Cancel()
        self._forgeTimers[handle] = nil
        if self._forgeTimerMeta then self._forgeTimerMeta[handle] = nil end
    end
end

function methods:CancelAllTimers()
    if self._forgeTimers then
        for handle in pairs(self._forgeTimers) do handle:Cancel() end
        self._forgeTimers    = {}
        self._forgeTimerMeta = {}
    end
    if self._forgeDebounces then
        for _, handle in pairs(self._forgeDebounces) do handle:Cancel() end
        self._forgeDebounces = {}
    end
    if self._forgeThrottles then
        for _, entry in pairs(self._forgeThrottles) do
            if entry.handle then entry.handle:Cancel() end
        end
        self._forgeThrottles = {}
    end
end

--- Returns true if the timer handle is still running.
function methods:IsTimerActive(handle)
    if not handle then return false end
    if not (self._forgeTimers and self._forgeTimers[handle]) then return false end
    -- C_Timer handles expose IsCancelled(); tickers do not have it removed.
    if handle.IsCancelled then return not handle:IsCancelled() end
    return true
end

--- Returns the approximate remaining time on a one-shot timer, or nil.
-- For repeating timers returns the time until the next tick.
-- Not precise — based on wall-clock time at schedule.
function methods:TimeLeft(handle)
    if not handle then return nil end
    local meta = self._forgeTimerMeta and self._forgeTimerMeta[handle]
    if not meta then return nil end
    if not self:IsTimerActive(handle) then return 0 end
    local elapsed = GetTime() - meta.start
    if meta.repeating then
        return math.max(0, meta.delay - (elapsed % meta.delay))
    else
        return math.max(0, meta.delay - elapsed)
    end
end

-- ── Debounce ──────────────────────────────────────────────────
-- Restarts the delay on every call. Fires once after silence.

function methods:Debounce(key, delay, callback, ...)
    self._forgeDebounces = self._forgeDebounces or {}

    local prev = self._forgeDebounces[key]
    if prev then prev:Cancel() end

    local args = { ... }
    self._forgeDebounces[key] = C_Timer.NewTimer(delay, function()
        if self._forgeDebounces then
            self._forgeDebounces[key] = nil
        end
        invoke(self, callback, unpack(args))
    end)
end

--- Cancel a pending debounce without firing its callback.
function methods:CancelDebounce(key)
    if self._forgeDebounces and self._forgeDebounces[key] then
        self._forgeDebounces[key]:Cancel()
        self._forgeDebounces[key] = nil
    end
end

-- ── Throttle ──────────────────────────────────────────────────
-- Fires immediately on the first call, then blocks for `interval` seconds.
-- Calls arriving during the block are silently dropped.

function methods:Throttle(key, interval, callback, ...)
    self._forgeThrottles = self._forgeThrottles or {}
    local entry = self._forgeThrottles[key]

    if entry and entry.blocked then return end   -- in cooldown — drop

    -- Fire immediately.
    invoke(self, callback, ...)

    -- Open the block window.
    local newEntry = { blocked = true, handle = nil }
    self._forgeThrottles[key] = newEntry
    newEntry.handle = C_Timer.NewTimer(interval, function()
        if self._forgeThrottles then
            self._forgeThrottles[key] = nil
        end
    end)
end

-- ── Bucket events ─────────────────────────────────────────────
-- Coalesces rapid WoW events and delivers a single batched callback.

function methods:RegisterBucketEvent(event, interval, callback)
    assert(type(self.RegisterEvent) == "function",
        "ForgeTimer:RegisterBucketEvent() - object must have RegisterEvent() "
        .. "(embed ForgeTimer onto a ForgeCore addon or module)")

    self._forgeBuckets = self._forgeBuckets or {}
    if self._forgeBuckets[event] then return end   -- already registered

    local bucket = { timer = nil, payloads = {} }
    self._forgeBuckets[event] = bucket

    self:RegisterEvent(event, function(_, firedEvent, ...)
        bucket.payloads[#bucket.payloads + 1] = { ... }
        if bucket.timer then return end   -- timer already ticking

        bucket.timer = C_Timer.NewTimer(interval, function()
            local payloads     = bucket.payloads
            bucket.payloads    = {}
            bucket.timer       = nil
            invoke(self, callback, firedEvent, payloads)
        end)
    end)
end

function methods:UnregisterBucketEvent(event)
    if not self._forgeBuckets then return end
    local bucket = self._forgeBuckets[event]
    if not bucket then return end

    if bucket.timer then bucket.timer:Cancel() end
    self._forgeBuckets[event] = nil

    if type(self.UnregisterEvent) == "function" then
        self:UnregisterEvent(event)
    end
end

-- ── Embed ─────────────────────────────────────────────────────

function ForgeTimer:Embed(target)
    for key, value in pairs(methods) do
        target[key] = value
    end
    return target
end
