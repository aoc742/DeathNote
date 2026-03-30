# ForgeDMC Toolkit

A complete, lightweight replacement for the Ace3 library suite and common WoW addon dependencies.  
Every file is standalone — use only what you need.

---

## Why ForgeDMC?

| Pain Point | Ace3 / Legacy Libs | ForgeDMC |
|---|---|---|
| **Dependency chain** | LibStub → CallbackHandler → AceEvent → AceAddon → … | One file per feature, no inter-dependencies |
| **Memory footprint** | Thousands of lines loaded regardless of use | Each module is < 300 lines |
| **UI compatibility** | Custom frames break on Blizzard UI updates | Native API calls inherit the game's current skin automatically |
| **Taint risk** | Shared library tables across 50+ addons | Isolated per-addon; no shared mutation |
| **Patch resilience** | Third-party authors must update after each patch | Wraps Blizzard's own C++ APIs — self-updating |
| **Readability** | Options tables-of-tables, LibStub version games | Imperative API: `Register()`, `Spawn()`, `Show()` |

---

## Module Overview

### Core Toolkit (Ace3 Replacements)

| File | Replaces | What It Does |
|---|---|---|
| `ForgeCore.lua` | AceAddon-3.0 + AceEvent-3.0 + AceConsole-3.0 | Addon/module lifecycle, event dispatch, chat commands |
| `ForgeDB.lua` | AceDB-3.0 | SavedVariables with global / char / profile scopes |
| `ForgeComm.lua` | AceComm-3.0 | Addon messaging via C_ChatInfo, with chunked sends |
| `ForgeHook.lua` | AceHook-3.0 | Restoreable hooks, script hooks, secure hooks |
| `ForgeLocale.lua` | AceLocale-3.0 | Locale proxy with enUS fallback |
| `ForgeOptions.lua` | AceConfig-3.0 + AceConfigDialog-3.0 | Native Settings API panels (Dragonflight+) |
| `ForgeTimer.lua` | AceTimer-3.0 + AceBucket-3.0 | One-shot, repeating, debounce, throttle, bucket events |
| `ForgeWidgets.lua` | AceGUI-3.0 | Native WoW frame/widget helpers |

### Extended Toolkit (Common Library Replacements)

| File | Replaces | What It Does |
|---|---|---|
| `ForgeStub.lua` | LibStub | Versioned library registration without global mutation |
| `ForgeBabble.lua` | LibBabble-Boss/Faction/SubZone-3.0 | Live game-data name lookups via EJ / C_Map / C_Reputation |
| `ForgeBroker.lua` | LibDataBroker-1.1 | Data object pub/sub — attribute change callbacks |
| `ForgeMinimapButton.lua` | LibDBIcon-1.0 | Draggable minimap button with shape math + AddonCompartment |
| `ForgeDialog.lua` | LibDialog-1.0 | Modal confirm/input dialogs using native Blizzard backdrop |

---

## Requirements

- **World of Warcraft: Dragonflight (10.0)** or later for `ForgeOptions.lua` (Settings API)  
- All other modules are compatible with **Shadowlands (9.x)** and later  
- `ForgeWidgets:CreateDropdown` auto-detects TWW 11.0+ and uses `DropdownButtonMixin`  
- `ForgeMinimapButton` auto-registers with `AddonCompartmentFrame` on TWW 11.0+  
- No external library dependencies — every file is self-contained  

---

## Quick Start

### 1. Add files to your addon

Copy only the files you need into your addon folder and reference them in your `.toc`:

```
## SavedVariables: MyAddonDB

Libs\ForgeStub.lua
Libs\ForgeCore.lua
Libs\ForgeDB.lua
Libs\ForgeTimer.lua
Libs\ForgeComm.lua
Libs\ForgeHook.lua
Libs\ForgeOptions.lua
Libs\ForgeWidgets.lua
Libs\ForgeLocale.lua
Libs\ForgeBabble.lua
Libs\ForgeBroker.lua
Libs\ForgeMinimapButton.lua
Libs\ForgeDialog.lua

MyAddon.lua
```

### 2. Minimal addon skeleton

```lua
-- MyAddon.lua
local MyAddon = ForgeCore:NewAddon("MyAddon")

function MyAddon:OnInitialize()
    self.db = ForgeDB:New("MyAddonDB", {
        profile = { scale = 1.0, showFrame = true },
        global  = { seenVersion = 0 },
    })

    -- Options panel
    local opts = ForgeOptions:Create("MyAddon", "My Addon", self.db.profile)
    opts:AddCheckbox("showFrame", "Show Frame", "Toggle the main frame.", true)
    opts:AddSlider("scale", "Scale", "Resize.", 0.5, 2.0, 0.05, 1.0)
    opts:Register(self)

    -- Slash command
    self:RegisterChatCommand("myaddon", "OnSlash")
end

function MyAddon:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")

    ForgeMinimapButton:Register("MyAddon", {
        icon    = "Interface\\Icons\\Trade_Engineering",
        tooltip = "My Addon\nClick to toggle.",
        db      = self.db.global,
        OnClick = function(_, btn)
            if btn == "LeftButton" then self:OpenOptions()
            else self:Toggle() end
        end,
    })
end

function MyAddon:PLAYER_ENTERING_WORLD()
    self:Print("Hello, Azeroth!")
end

function MyAddon:OnSlash(msg)
    if msg == "config" then self:OpenOptions()
    else self:Toggle() end
end
```

---

## Module Usage Summaries

### ForgeStub

```lua
local lib, isNew = ForgeStub:NewLibrary("MyLib", 3)
if not lib then return end   -- older version already loaded

function lib:DoThing() end

-- Elsewhere:
local myLib = ForgeStub:GetLibrary("MyLib")
```

### ForgeCore

```lua
local addon = ForgeCore:NewAddon("MyAddon")

function addon:OnInitialize() end  -- ADDON_LOADED
function addon:OnEnable()    end  -- PLAYER_LOGIN
function addon:OnDisable()   end  -- when Disable() is called

addon:RegisterEvent("ZONE_CHANGED", "OnZoneChanged")
addon:RegisterChatCommand("cmd", "OnSlash")
addon:Print("message")
addon:Printf("value = %d", 42)

local mod = addon:NewModule("MyModule")
addon:GetModule("MyModule")
for name, mod in addon:IterateModules() do end
```

### ForgeDB

```lua
self.db = ForgeDB:New("MyAddonDB", {
    global  = { seen = 0 },
    char    = { lastZone = "" },
    profile = { scale = 1.0 },
})

self.db.global.seen   = 1
self.db.char.lastZone = "Stormwind City"
self.db.profile.scale = 1.5

self.db:SetProfile("Tank")
self.db:GetCurrentProfile()     -- "Tank"
self.db:GetProfiles()           -- { "Default", "Tank" }
self.db:ResetProfile()
self.db:RegisterCallback("OnProfileChanged", function(db, name) end)
```

### ForgeComm

```lua
ForgeComm:Register("MYADDON", function(prefix, msg, channel, sender)
    print(sender, msg)
end)

ForgeComm:Send("MYADDON", "ping", "PARTY")
ForgeComm:SendChunked("MYADDON", veryLongString, "GUILD")
ForgeComm:Unregister("MYADDON")
```

### ForgeHook

```lua
ForgeHook:Embed(MyAddon)

MyAddon:Hook(SomeObject, "MethodName", "MyHandlerMethod")
MyAddon:HookScript(myFrame, "OnShow", function(f) end)
MyAddon:SecureHook("GlobalFunc", nil, handler)
MyAddon:SecureHook(table, "method", handler)

MyAddon:Unhook(SomeObject, "MethodName")
MyAddon:UnhookScript(myFrame, "OnShow")
MyAddon:UnhookAll()

MyAddon:IsHooked(SomeObject, "MethodName")
MyAddon:IsSecureHooked(SomeObject, "MethodName")
```

### ForgeLocale

```lua
-- Locale-enUS.lua
local L = ForgeLocale:Register("MyAddon", "enUS")
L["Open Settings"] = true
L["Toggle Frame"]  = true

-- Locale-deDE.lua
local L = ForgeLocale:Register("MyAddon", "deDE")
L["Open Settings"] = "Einstellungen öffnen"

-- MyAddon.lua
local L = ForgeLocale:Get("MyAddon")
print(L["Open Settings"])   -- "Einstellungen öffnen" on deDE, "Open Settings" otherwise
```

### ForgeOptions

```lua
local opts = ForgeOptions:Create("MyAddon", "My Addon Title", self.db.profile)
opts:AddHeader("General")
opts:AddCheckbox("show",  "Show Frame",  "Toggle.",         true)
opts:AddSlider("scale",   "Scale",       "Resize.",  0.5, 2.0, 0.05, 1.0)
opts:AddDropdown("mode",  "Mode",        "Behaviour.",
    { {value="A", label="Alpha"}, {value="B", label="Beta"} }, "A")

local adv = opts:CreateSubcategory("Advanced")
adv:AddCheckbox("debug", "Debug Mode", "Verbose output.", false)

opts:Register(MyAddon)   -- sets MyAddon.optionsCategory
opts:Open()
```

### ForgeTimer

```lua
ForgeTimer:Embed(MyAddon)

local h = MyAddon:ScheduleTimer("OnTimeout", 2.0)
local h = MyAddon:ScheduleRepeatingTimer("OnTick", 0.5)
MyAddon:CancelTimer(h)
MyAddon:CancelAllTimers()

MyAddon:Debounce("key", 0.3, "OnSettled")
MyAddon:Throttle("key", 1.0, "OnAction")
MyAddon:RegisterBucketEvent("BAG_UPDATE", 0.2, "OnBags")
MyAddon:UnregisterBucketEvent("BAG_UPDATE")
```

### ForgeWidgets

```lua
local win        = ForgeWidgets:CreateWindow("MyAddonFrame", UIParent, "Title", 700, 500)
local panel      = ForgeWidgets:CreatePanel(win)
local hdr        = ForgeWidgets:CreateHeader(panel, "Section")
local lbl        = ForgeWidgets:CreateLabel(panel, "Some text")
local btn        = ForgeWidgets:CreateButton(panel, "Click", 120, 22, onClick)
local chk        = ForgeWidgets:CreateCheckBox(panel, "Enable", "Tip", fn)
local sld        = ForgeWidgets:CreateSlider(panel, "Scale", 0, 100, 1, fn)
local box        = ForgeWidgets:CreateEditBox(panel, 180, 24, fn)
local scroll, ch = ForgeWidgets:CreateScrollFrame(panel)
local dd         = ForgeWidgets:CreateDropdown(panel, 160, items, fn)
local tabs, show = ForgeWidgets:CreateTabStrip(panel, {"Tab1","Tab2"}, fn)
```

### ForgeBabble

```lua
-- Boss names (Encounter Journal):
ForgeBabble:GetBossName(1853)           -- "Sylvanas Windrunner"
ForgeBabble:GetBossId("Ragnaros")       -- encounter ID number

-- Faction names (Reputation API):
ForgeBabble:GetFactionName(1270)        -- "Argent Crusade"
ForgeBabble:GetFactionId("Argent Crusade")

-- Area / SubZone names (C_Map):
ForgeBabble:GetAreaName(1519)           -- "Stormwind City"
ForgeBabble:GetAreaId("Stormwind City")
ForgeBabble:PreloadAreas({ 87, 1519, 1637 })
ForgeBabble:GetCurrentAreaName()

for id, name in ForgeBabble:IterateBosses() do end
```

### ForgeBroker

```lua
local obj = ForgeBroker:NewDataObject("MyAddon", {
    type  = "launcher",
    icon  = "Interface\\Icons\\INV_Misc_Gear_01",
    label = "My Addon",
    text  = "Ready",
    OnClick = function(frame, button) end,
})

obj.text = "5 items"    -- triggers OnAttributeChanged callbacks

ForgeBroker:RegisterCallback("OnAttributeChanged", function(name, key, value, obj) end)
ForgeBroker:RegisterCallback("OnAttributeChanged_MyAddon", fn)
ForgeBroker:GetDataObject("MyAddon")
for name, obj in ForgeBroker:DataObjectIterator() do end
```

### ForgeMinimapButton

```lua
ForgeMinimapButton:Register("MyAddon", {
    icon    = "Interface\\Icons\\Trade_Engineering",
    tooltip = "My Addon\nLeft click: toggle\nRight click: options",
    db      = self.db.global,   -- saves .minimapAngle, .minimapHidden, .minimapLocked
    OnClick = function(frame, button)
        if button == "LeftButton" then MyAddon:Toggle()
        else MyAddon:OpenOptions() end
    end,
    OnTooltipShow = function(tooltip, frame)  -- optional custom tooltip
        tooltip:AddLine("My Addon", 1, 0.8, 0)
    end,
})

ForgeMinimapButton:Show("MyAddon")
ForgeMinimapButton:Hide("MyAddon")
ForgeMinimapButton:Toggle("MyAddon")
ForgeMinimapButton:Lock("MyAddon")
ForgeMinimapButton:SetIcon("MyAddon", newTexture)
ForgeMinimapButton:SetAngle("MyAddon", 90)
ForgeMinimapButton:Refresh("MyAddon")
ForgeMinimapButton:Unregister("MyAddon")
```

### ForgeDialog

```lua
-- Register once (e.g. OnInitialize):
ForgeDialog:Register("MYADDON_CONFIRM", {
    text     = "Delete |cffff2020%s|r?",
    icon     = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
    showAlert = true,
    buttons  = {
        { text = "Delete", OnClick = function(f, data) MyAddon:Delete(data) end },
        { text = "Cancel" },
    },
})

-- Show it:
ForgeDialog:Spawn("MYADDON_CONFIRM", "Old Profile")

-- Edit box variant:
ForgeDialog:Register("MYADDON_RENAME", {
    text    = "Enter a new name:",
    editBox = { maxLetters = 24, placeholder = "Profile name" },
    buttons = {
        { text = "OK", OnClick = function(f) MyAddon:Rename(f.editBox:GetText()) end },
        { text = "Cancel" },
    },
})

ForgeDialog:Dismiss("MYADDON_CONFIRM")
ForgeDialog:IsActive("MYADDON_CONFIRM")   -- true/false
ForgeDialog:DismissAll()
```

---

## License

MIT — see individual file headers.  
ForgeDMC Toolkit © 2026 ForgeDMC.
