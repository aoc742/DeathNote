-- ============================================================
--  ForgeComm.lua  |  v1.2.0
--  ForgeDMC Toolkit
--
--  Replaces : AceComm-3.0
--  Author   : ForgeDMC  |  2026-03-21  |  MIT
--
--  FIXES v1.1.0 / v1.2.0
--  ----------------------
--  * Renamed NativeComm -> ForgeComm throughout
--  * CHUNK_SIZE reduced 250->220 (250-byte payload + 14-byte header = 264 >
--    255 Blizzard hard limit; 220+14=234, safely under 255)
--  * Added _objHandlers table and OBJ_MAGIC constant ("\x02FO")
--  * PLAYER_LOGIN now registers prefixes from BOTH _handlers + _objHandlers
--  * dispatch() helper routes OBJ_MAGIC payloads to object handlers and
--    plain strings to string handlers; either handler may be absent
--  * RegisterObject(prefix, callback) -- receive tables serialized by SendObject
--  * SendObject(prefix, obj, ch, tgt) -- ForgePacker.PackCompressed + chunked
--  * Unregister() clears both _handlers and _objHandlers
--  * IsRegistered() checks both tables
--  * GetRegisteredPrefixes() deduplicates across both tables
--
--  USAGE
--  -----
--  -- String handler (safe to call before PLAYER_LOGIN):
--  ForgeComm:Register("MYADDON", function(prefix, msg, channel, sender)
--      print("Got:", msg, "from", sender)
--  end)
--
--  -- Object handler:
--  ForgeComm:RegisterObject("MYADDON", function(prefix, tbl, channel, sender)
--      print("Got table with", tbl.key)
--  end)
--
--  -- Send a short string (<= 255 bytes):
--  ForgeComm:Send("MYADDON", "ping", "PARTY")
--
--  -- Send a large string (auto-chunked):
--  ForgeComm:SendChunked("MYADDON", bigStr, "RAID")
--
--  -- Send a table (serialized + compressed):
--  ForgeComm:SendObject("MYADDON", { x = 1, y = 2 }, "GUILD")
--
--  LIMITS
--  ------
--  * Prefix  : 1-16 characters (Blizzard hard limit)
--  * Chunk   : 220 bytes per packet payload
--  * Sending : only valid after PLAYER_LOGIN (queued prefixes register then)
-- ============================================================

ForgeComm = ForgeComm or {}

-- ── Chunking constants ────────────────────────────────────────

local CHUNK_SIZE  = 220        -- max payload bytes per packet
local CHUNK_MAGIC = "FGC"      -- 3-byte header magic
local SEP         = "\031"     -- ASCII Unit Separator

-- ── State ─────────────────────────────────────────────────────

local _handlers    = {}   -- [prefix] = callback  (string messages)
local _objHandlers = {}   -- [prefix] = callback  (deserialized tables)
local _registered  = {}   -- [prefix] = true  (ack'd by C_ChatInfo)
local _incoming    = {}   -- [prefix][sender] = { total, chunks={} }

-- Magic prefix identifying SendObject payloads (STX + "FO").
local OBJ_MAGIC = "\x02FO"

-- ── Listener frame ────────────────────────────────────────────

local _frame = CreateFrame("Frame")
_frame:RegisterEvent("PLAYER_LOGIN")
_frame:RegisterEvent("CHAT_MSG_ADDON")
_frame:RegisterEvent("PLAYER_LOGOUT")

_frame:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)

    -- ── PLAYER_LOGOUT: purge stale reassembly bags ──────────────
    if event == "PLAYER_LOGOUT" then
        _incoming = {}
        return
    end

    -- ── PLAYER_LOGIN: flush queued prefix registrations ─────────
    if event == "PLAYER_LOGIN" then
        local toRegister = {}
        for p in pairs(_handlers)    do toRegister[p] = true end
        for p in pairs(_objHandlers) do toRegister[p] = true end
        for p in pairs(toRegister) do
            if not _registered[p] then
                if C_ChatInfo.RegisterAddonMessagePrefix(p) then
                    _registered[p] = true
                else
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cffff4444ForgeComm|r: Failed to register prefix '"
                        .. p .. "' — Blizzard session cap reached?")
                end
            end
        end
        return
    end

    -- ── CHAT_MSG_ADDON: dispatch ─────────────────────────────────
    if event ~= "CHAT_MSG_ADDON" then return end

    local handler    = _handlers[prefix]
    local objHandler = _objHandlers[prefix]
    if not handler and not objHandler then return end

    local shortSender = (sender and sender:match("^([^%-]+)")) or sender

    -- Detect chunked packet: "FGC\031<total>\031<seq>\031<payload>"
    local total, seq, payload = message:match(
        "^" .. CHUNK_MAGIC .. SEP .. "(%d+)" .. SEP .. "(%d+)" .. SEP .. "(.*)")

    local function dispatch(msg)
        if objHandler and msg:sub(1, 3) == OBJ_MAGIC then
            local ok, tbl = pcall(ForgePacker.UnpackCompressed, msg:sub(4))
            if ok and type(tbl) == "table" then
                pcall(objHandler, prefix, tbl, channel, sender, shortSender)
            end
        elseif handler then
            pcall(handler, prefix, msg, channel, sender, shortSender)
        end
    end

    if total then
        total = tonumber(total)
        seq   = tonumber(seq)

        _incoming[prefix]         = _incoming[prefix]         or {}
        _incoming[prefix][sender] = _incoming[prefix][sender] or { total = total, chunks = {} }

        local bag = _incoming[prefix][sender]
        bag.chunks[seq] = payload

        local received = 0
        for _ in pairs(bag.chunks) do received = received + 1 end

        if received == total then
            local parts = {}
            for i = 1, total do
                if not bag.chunks[i] then return end
                parts[i] = bag.chunks[i]
            end
            _incoming[prefix][sender] = nil
            dispatch(table.concat(parts))
        end
    else
        dispatch(message)
    end
end)

-- ── Public API ────────────────────────────────────────────────

--- Register a string-message handler. Safe to call before PLAYER_LOGIN.
-- @param prefix    string    1-16 characters
-- @param callback  function  (prefix, message, channel, sender, shortSender)
function ForgeComm:Register(prefix, callback)
    assert(type(prefix) == "string" and #prefix >= 1 and #prefix <= 16,
        "ForgeComm:Register - prefix must be 1-16 characters, got: " .. tostring(prefix))
    assert(type(callback) == "function",
        "ForgeComm:Register - callback must be a function")

    _handlers[prefix] = callback

    if IsLoggedIn() and not _registered[prefix] then
        if C_ChatInfo.RegisterAddonMessagePrefix(prefix) then
            _registered[prefix] = true
        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffff4444ForgeComm|r: Failed to register prefix '"
                .. prefix .. "' — Blizzard session cap reached?")
        end
    end
end

--- Register a table-object handler. Callback receives (prefix, tbl, channel, sender, shortSender).
-- A prefix may have both a Register and a RegisterObject handler simultaneously;
-- plain strings go to Register, OBJ_MAGIC payloads go to RegisterObject.
function ForgeComm:RegisterObject(prefix, callback)
    assert(type(prefix) == "string" and #prefix >= 1 and #prefix <= 16,
        "ForgeComm:RegisterObject - prefix must be 1-16 characters")
    assert(type(callback) == "function",
        "ForgeComm:RegisterObject - callback must be a function")

    _objHandlers[prefix] = callback

    if IsLoggedIn() and not _registered[prefix] then
        if C_ChatInfo.RegisterAddonMessagePrefix(prefix) then
            _registered[prefix] = true
        end
    end
end

--- Silence all callbacks for a prefix. The prefix stays registered with Blizzard.
function ForgeComm:Unregister(prefix)
    _handlers[prefix]    = nil
    _objHandlers[prefix] = nil
    _incoming[prefix]    = nil
end

--- Send a single message. Payload must be <= 255 bytes.
-- @param prefix   string
-- @param message  string   <= 255 bytes
-- @param channel  string   "PARTY"|"RAID"|"GUILD"|"OFFICER"|"INSTANCE_CHAT"|"WHISPER"
-- @param target   string   Required for WHISPER
function ForgeComm:Send(prefix, message, channel, target)
    assert(_registered[prefix],
        "ForgeComm:Send - prefix not registered (call Register first): " .. tostring(prefix))
    assert(type(message) == "string",
        "ForgeComm:Send - message must be a string")
    assert(#message <= 255,
        "ForgeComm:Send - message is " .. #message
        .. " bytes; use SendChunked() for payloads over 255 bytes")

    channel = channel or "PARTY"

    if channel == "WHISPER" then
        assert(type(target) == "string" and target ~= "",
            "ForgeComm:Send - WHISPER requires a target string")
        C_ChatInfo.SendAddonMessage(prefix, message, channel, target)
    else
        C_ChatInfo.SendAddonMessage(prefix, message, channel)
    end
end

--- Send a message of any length, split into CHUNK_SIZE-byte packets.
-- The receiver's callback fires once with the fully reassembled string.
function ForgeComm:SendChunked(prefix, message, channel, target)
    assert(_registered[prefix],
        "ForgeComm:SendChunked - prefix not registered: " .. tostring(prefix))
    assert(type(message) == "string",
        "ForgeComm:SendChunked - message must be a string")

    channel = channel or "PARTY"

    local chunks = {}
    for i = 1, #message, CHUNK_SIZE do
        chunks[#chunks + 1] = message:sub(i, i + CHUNK_SIZE - 1)
    end

    if #chunks == 1 and #message <= 255 then
        return self:Send(prefix, message, channel, target)
    end

    local total = #chunks
    for seq, chunk in ipairs(chunks) do
        local packet = CHUNK_MAGIC .. SEP .. total .. SEP .. seq .. SEP .. chunk
        if channel == "WHISPER" then
            C_ChatInfo.SendAddonMessage(prefix, packet, channel, target)
        else
            C_ChatInfo.SendAddonMessage(prefix, packet, channel)
        end
    end
end

--- Serialize a table with ForgePacker (Pack+Compress) and send it chunked.
-- The receiver must have called RegisterObject() for the same prefix.
function ForgeComm:SendObject(prefix, obj, channel, target)
    assert(_registered[prefix],
        "ForgeComm:SendObject - prefix not registered: " .. tostring(prefix))
    assert(type(obj) == "table",
        "ForgeComm:SendObject - obj must be a table")
    assert(ForgePacker, "ForgeComm:SendObject requires ForgePacker to be loaded")
    local payload = OBJ_MAGIC .. ForgePacker.PackCompressed(obj)
    return self:SendChunked(prefix, payload, channel, target)
end

--- Returns true if any handler is registered for this prefix.
function ForgeComm:IsRegistered(prefix)
    return _handlers[prefix] ~= nil or _objHandlers[prefix] ~= nil
end

--- Returns a sorted, deduplicated list of all registered prefixes.
function ForgeComm:GetRegisteredPrefixes()
    local seen = {}
    local list = {}
    for p in pairs(_handlers)    do if not seen[p] then seen[p]=true; list[#list+1]=p end end
    for p in pairs(_objHandlers) do if not seen[p] then seen[p]=true; list[#list+1]=p end end
    table.sort(list)
    return list
end