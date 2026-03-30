# ForgeDMC Toolkit — Changelog

All notable changes are documented here.
Format: `[version] YYYY-MM-DD — Summary`

---

## v1.1.0 — 2026-03-21  ·  Bug-fix & completion release

### 🔴 Critical fixes (would not load)

**ForgeDB.lua**
- `ForgeDB:New()` constructor was entirely missing — body now written
- Removed duplicate file body (file was concatenated with itself) that
  caused a Lua syntax error preventing the entire addon from loading
- `char` scope key now uses `UnitName("player") .. "-" .. GetRealmName()`
  for true per-character-realm uniqueness
- `applyDefaults()`: fixed edge-case where a non-table `target[k]` blocked
  a table-typed default from being stamped (deep-copied the default instead)
- `DeleteProfile()`: added assertion that the profile actually exists

**ForgeLocale.lua** *(complete rewrite)*
- Previous file contained a full copy of `ForgeWidgets.lua` and registered
  `_G.ForgeWidgets` — no locale system existed at all
- New implementation: `Register(addonName, locale)` returns a proxy table;
  `L["key"] = true` marks a key as using itself as the translation (enUS pattern)
- `Get(addonName)` returns the proxy for the current client locale with
  automatic `enUS` fallback, then first-registered fallback, then key-as-string
- Reads from unregistered keys return the key string — never `nil`, never errors
- Added `GetRegisteredLocales()`, `IsLocaleRegistered()`, `DumpLocale()` utilities
- Fully idempotent: calling `Register` twice for the same addon+locale is safe

---

### 🟡 Naming fixes (wrong global exported)

**ForgeComm.lua**
- Renamed `NativeComm` → `ForgeComm` throughout to match toolkit convention
- Added `SendChunked(prefix, message, channel, target)` — splits payloads into
  250-byte packets with a `FGC|total|seq|payload` header; the receiver's callback
  fires once with the fully reassembled string, transparent to the caller
- `Send()` now asserts message ≤ 255 bytes and explicitly directs larger payloads
  to `SendChunked()` with a clear error message
- Added warning log when `RegisterAddonMessagePrefix` fails (Blizzard ~64 cap)
- Cleans up `_incoming` reassembly buffer after successful delivery

**ForgeOptions.lua**
- Renamed `NativeOptions` → `ForgeOptions` throughout
- Fixed `Settings.RegisterAddOnSetting()` argument order to match the actual
  Dragonflight/TWW API signature: `(category, varName, key, db, varType, label, default)`
  (was passing `label` as `name` and omitting `label` in the display position)
- Replaced the broken `panelMethods` copy-onto-`NativeOptions` pattern with a
  proper `Panel` metatable — instances from `:Create()` now correctly inherit
  methods without shared-state confusion
- Added `AddHeader(text)` — section label via `Settings.CreateSectionHeader` (TWW+)
- Added `CreateSubcategory(title)` — child category in the Settings sidebar
- `databaseTable` parameter to `:Create()` is now optional

---

### 🟡 Runtime bug fixes

**ForgeTimer.lua**
- `invoke()`: function callbacks now receive `self` as the first argument
  (was `callback(...)` — self was silently dropped; now `callback(self, ...)`)
- Added `Throttle(key, interval, callback, ...)` — fire-immediately then
  block for interval; complements `Debounce`
- Added `CancelDebounce(key)` — cancel a pending debounce without firing it
- `CancelAllTimers()` now also cancels pending debounce and throttle handles

**ForgeWidgets.lua**
- `CreateCheckBox()`: was crashing with `_G[nil.."Text"]` because `CheckButton`
  was created with `nil` name; now generates a unique name via `uniqueName()`
  so `UICheckButtonTemplate`'s `<n>Text` sub-frame is always accessible
- `CreateSlider()`: same crash (`_G[nil.."Low"]` etc.); fixed with unique name
- `CreateDropdown()`: `UIDropDownMenuTemplate` is deprecated in TWW 11.0+;
  now auto-detects `DropdownButtonMixin` and uses `WowStyle1DropdownTemplate`
  on 11.0+ clients, falling back to legacy template on older clients
- `CreateEditBox()`: added `OnEscapePressed` to clear focus (standard UX)
- Added `CreateTabStrip(parent, tabNames, onTabChange)` — horizontal tab button
  row with active-state highlighting; returns the strip frame and a `showTab(index)`
  function for programmatic tab switching
- `uniqueName(prefix)` internal counter generates collision-free global frame names

---

## v1.0.0 — 2026-03-20  ·  Initial release

### Core Toolkit (Ace3 replacements)
- **ForgeCore** — AceAddon + AceEvent + AceConsole
- **ForgeDB** — AceDB-3.0
- **ForgeComm** — AceComm-3.0
- **ForgeHook** — AceHook-3.0
- **ForgeLocale** — AceLocale-3.0
- **ForgeOptions** — AceConfig + AceConfigDialog + AceConfigRegistry + AceDBOptions
- **ForgeTimer** — AceTimer + AceBucket
- **ForgeWidgets** — AceGUI-3.0

### Extended Toolkit (common library replacements)
- **ForgeStub** — LibStub
- **ForgeBabble** — LibBabble-Boss/Faction/SubZone-3.0
- **ForgeBroker** — LibDataBroker-1.1 + LibDBIcon-1.0
- **ForgeMinimapButton** — LibDBIcon-1.0
- **ForgeDialog** — LibDialog-1.0
- **ForgeGeo** — HereBeDragons
- **ForgeGlow** — LibCustomGlow
- **ForgeMedia** — LibSharedMedia-3.0
- **ForgePacker** — LibDeflate (serialisation layer) + AceSerializer
- **ForgeQueue** — ChatThrottleLib
- **ForgeRange** — LibRangeCheck
- **ForgeSkin** — Masque
- **ForgeWindow** — LibWindow
