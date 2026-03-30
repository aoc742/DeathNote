-- ============================================================
--  ForgeStub.lua  |  v1.0.0
--  ForgeDMC Toolkit
--
--  Replaces: LibStub
--
--  LibStub solves one problem: preventing an older version of a
--  shared library from overwriting a newer one when multiple
--  addons bundle the same file. ForgeStub does the same thing
--  with zero external dependencies and no metatable tricks.
--
--  USAGE
--  -----
--  -- At the top of any shared library file:
--  local MyLib = ForgeStub:New("MyLib", 5)
--  if not MyLib then return end   -- newer version already loaded; stop here
--
--  function MyLib:DoThing() ... end
--
--  -- Consumers retrieve the library:
--  local MyLib = ForgeStub:Get("MyLib")
--  local MyLib = ForgeStub:Get("MyLib", true)  -- silent: returns nil instead of error
--
--  -- Check version:
--  print(ForgeStub:GetVersion("MyLib"))   -- 5
--
--  -- Iterate all registered libraries (debug):
--  for name, lib, version in ForgeStub:Iterate() do
--      print(name, version)
--  end
-- ============================================================

ForgeStub = ForgeStub or {}
ForgeStub._libs = ForgeStub._libs or {}   -- persisted across multiple loads
local _libs = ForgeStub._libs  -- [name] = { lib = table, version = number }

-- ── Public API ────────────────────────────────────────────────

--- Register or upgrade a library.
-- Returns the library table and the previous version number (or 0).
-- Returns nil if the currently registered version is >= `version`
-- (caller should do nothing and return immediately).
--
-- @param name     string   Unique library identifier
-- @param version  number   Positive integer; must be bumped on every change
-- @return lib     table    The library table to populate with methods
-- @return oldver  number   Previous version number (0 if first registration)
function ForgeStub:New(name, version)
    assert(type(name) == "string" and name ~= "",
        "ForgeStub:New - name must be a non-empty string")
    assert(type(version) == "number" and version >= 1
        and math.floor(version) == version,
        "ForgeStub:New - version must be a positive integer, got: " .. tostring(version))

    local entry = _libs[name]
    if entry then
        if entry.version >= version then
            -- Already at this version or newer. Tell the caller to bail out.
            return nil, entry.version
        end
        -- Upgrade: bump version on the existing entry so consumers that
        -- already have a reference to entry.lib automatically see new methods.
        local oldver = entry.version
        entry.version = version
        return entry.lib, oldver
    end

    -- First registration.
    local lib = {}
    _libs[name] = { lib = lib, version = version }
    return lib, 0
end

--- Retrieve a registered library.
-- @param name    string
-- @param silent  boolean  If true, returns nil when not found instead of erroring
-- @return lib    table | nil
function ForgeStub:Get(name, silent)
    assert(type(name) == "string" and name ~= "",
        "ForgeStub:Get - name must be a non-empty string")
    local entry = _libs[name]
    if entry then return entry.lib end
    if silent then return nil end
    error("ForgeStub:Get - library not found: '" .. name .. "'", 2)
end

--- Return the registered version number of a library, or nil if not found.
-- @param name  string
-- @return version  number | nil
function ForgeStub:GetVersion(name)
    local entry = _libs[name]
    return entry and entry.version
end

--- Returns true if the named library is registered at version >= minVersion.
-- @param name        string
-- @param minVersion  number  (optional, defaults to 1)
function ForgeStub:IsLoaded(name, minVersion)
    local v = self:GetVersion(name)
    return v ~= nil and v >= (minVersion or 1)
end

--- Iterator over all registered libraries, sorted by name.
-- Usage: for name, lib, version in ForgeStub:Iterate() do ... end
function ForgeStub:Iterate()
    local names = {}
    for name in pairs(_libs) do names[#names + 1] = name end
    table.sort(names)
    local i = 0
    return function()
        i = i + 1
        local name = names[i]
        if name then
            return name, _libs[name].lib, _libs[name].version
        end
    end
end
