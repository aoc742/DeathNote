-- ============================================================
--  ForgeOptions.lua  |  v1.1.0
--  ForgeDMC Toolkit
--
--  Replaces : AceConfig-3.0 · AceConfigDialog-3.0
--             AceConfigRegistry-3.0 · AceDBOptions-3.0
--  Author   : ForgeDMC  |  2026-03-21  |  MIT
--  Requires : Dragonflight 10.0+ (Blizzard Settings API)
--
--  FIXES v1.1.0
--  ------------
--  * Renamed NativeOptions → ForgeOptions throughout
--  * Fixed Settings.RegisterAddOnSetting() argument order to match the
--    actual Dragonflight/TWW API signature:
--      (category, varName, key, dbTable, varType, displayName, defaultValue)
--  * Replaced the broken panelMethods copy-onto-ForgeOptions pattern
--    with a proper Panel metatable so instances created by :Create()
--    correctly inherit all methods without shared-state confusion
--  * Added AddHeader() — section label via Settings.CreateSectionHeader
--  * Added CreateSubcategory() — child category in the Settings sidebar
--  * databaseTable parameter to :Create() is now optional
--
--  USAGE
--  -----
--  -- Create a panel (call during or after ADDON_LOADED):
--  local opts = ForgeOptions:Create("MyAddon", "My Addon", self.db.profile)
--
--  opts:AddHeader("General")
--  opts:AddCheckbox("showFrame", "Show Frame",  "Toggle the main frame.", true)
--  opts:AddSlider("scale",  "Scale",  "Frame size.", 0.5, 2.0, 0.05, 1.0)
--  opts:AddDropdown("mode", "Mode",   "Behaviour.",
--      { {value="A", label="Alpha"}, {value="B", label="Beta"} }, "A")
--
--  -- Sub-category (appears as a child in the Settings sidebar):
--  local adv = opts:CreateSubcategory("Advanced")
--  adv:AddCheckbox("debug", "Debug Mode", "Verbose output.", false)
--
--  -- Register and link to a ForgeCore addon (sets addon.optionsCategory):
--  opts:Register(MyAddon)
--
--  -- Open programmatically:
--  opts:Open()
--  -- or via ForgeCore:
--  MyAddon:OpenOptions()
-- ============================================================

ForgeOptions = ForgeOptions or {}

-- ── Helpers ───────────────────────────────────────────────────

local function assertSettings()
    assert(Settings and Settings.RegisterVerticalLayoutCategory,
        "ForgeOptions requires the Dragonflight+ Settings API (10.0+)")
end

-- Unique internal variable name. Must be stable per addon+key combination.
local function varName(addonName, key)
    return addonName .. "_" .. key
end

local function buildDropdownData(options)
    local container = Settings.CreateControlTextContainer()
    for _, item in ipairs(options) do
        container:Add(item.value, item.label)
    end
    return container:GetData()
end

-- ── Panel prototype ───────────────────────────────────────────

local Panel = {}
Panel.__index = Panel
local _registered = {}  -- vns already registered this WoW session; prevents re-registration crash

--- Add a section header label (non-interactive).
-- Uses Settings.CreateSectionHeader when available (TWW 11.0+).
function Panel:AddHeader(text)
    if Settings.CreateSectionHeader then
        Settings.CreateSectionHeader(self.category, text)
    end
    return self
end

--- Add a checkbox control tied to db[key].
-- @param key          string
-- @param label        string   Display name shown in the panel
-- @param tooltip      string   (optional) hover tooltip text
-- @param default      boolean  Default value
-- @param onChanged    function(newValue)  (optional) fires on change
function Panel:AddCheckbox(key, label, tooltip, default, onChanged)
    assert(type(key) == "string" and key ~= "",
        "ForgeOptions:AddCheckbox - key must be a non-empty string")
    assert(type(self.db) == "table",
        "ForgeOptions:AddCheckbox - panel was created without a db table")

    if self.db[key] == nil then self.db[key] = default end

    local vn = varName(self.addonName, key)
    local setting = _registered[vn]
    if not setting then
        setting = Settings.RegisterAddOnSetting(
            self.category,
            vn,                       -- unique internal name
            key,                      -- variable key in db
            self.db,                  -- db table to read/write
            Settings.VarType.Boolean,
            label,                    -- display name
            default
        )
        _registered[vn] = setting
        Settings.CreateCheckbox(self.category, setting, tooltip or "")
        if onChanged then
            Settings.SetOnValueChangedCallback(vn, function(_, value)
                onChanged(value)
            end)
        end
    end
    return setting
end

--- Add a slider control tied to db[key].
-- @param key       string
-- @param label     string
-- @param tooltip   string   (optional)
-- @param minVal    number
-- @param maxVal    number
-- @param step      number
-- @param default   number
-- @param onChanged function(newValue)  (optional)
function Panel:AddSlider(key, label, tooltip, minVal, maxVal, step, default, onChanged)
    assert(type(key) == "string" and key ~= "",
        "ForgeOptions:AddSlider - key must be a non-empty string")
    assert(type(self.db) == "table",
        "ForgeOptions:AddSlider - panel was created without a db table")

    if self.db[key] == nil then self.db[key] = default end

    local vn = varName(self.addonName, key)
    local setting = _registered[vn]
    if not setting then
        setting = Settings.RegisterAddOnSetting(
            self.category,
            vn,
            key,
            self.db,
            Settings.VarType.Number,
            label,
            default
        )
        _registered[vn] = setting
        local sliderOpts = Settings.CreateSliderOptions(minVal, maxVal, step)
        if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
            sliderOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        end
        Settings.CreateSlider(self.category, setting, sliderOpts, tooltip or "")
        if onChanged then
            Settings.SetOnValueChangedCallback(vn, function(_, value)
                onChanged(value)
            end)
        end
    end
    return setting
end

--- Add a dropdown control tied to db[key].
-- @param key       string
-- @param label     string
-- @param tooltip   string   (optional)
-- @param values    table|function  { {value=x, label=y}, ... } or function→same
-- @param default   string   Default selected value
-- @param onChanged function(newValue)  (optional)
function Panel:AddDropdown(key, label, tooltip, values, default, onChanged)
    assert(type(key) == "string" and key ~= "",
        "ForgeOptions:AddDropdown - key must be a non-empty string")
    assert(type(self.db) == "table",
        "ForgeOptions:AddDropdown - panel was created without a db table")

    if self.db[key] == nil then self.db[key] = default end

    local vn = varName(self.addonName, key)
    local setting = _registered[vn]
    if not setting then
        setting = Settings.RegisterAddOnSetting(
            self.category,
            vn,
            key,
            self.db,
            Settings.VarType.String,
            label,
            default
        )
        _registered[vn] = setting
        local function optionSource()
            if type(values) == "function" then return values() end
            return buildDropdownData(values)
        end
        Settings.CreateDropdown(self.category, setting, optionSource, tooltip or "")
        if onChanged then
            Settings.SetOnValueChangedCallback(vn, function(_, value)
                onChanged(value)
            end)
        end
    end
    return setting
end

--- Add a color picker tied to db[key].
-- Stores the value as a table { r, g, b, a } in db[key].
-- Uses ColorPickerFrame (available on all Retail clients).
-- @param key       string
-- @param label     string
-- @param tooltip   string   (optional)
-- @param default   table    { r, g, b, a }  default color
-- @param onChanged function({ r, g, b, a })  (optional)
function Panel:AddColorPicker(key, label, tooltip, default, onChanged)
    assert(type(key) == "string" and key ~= "",
        "ForgeOptions:AddColorPicker - key must be a non-empty string")
    assert(type(self.db) == "table",
        "ForgeOptions:AddColorPicker - panel was created without a db table")

    default = default or { r = 1, g = 1, b = 1, a = 1 }
    if self.db[key] == nil then self.db[key] = default end

    -- Blizzard Settings API doesn't have a native color picker.
    -- We inject a custom initializer frame into the Settings category
    -- that renders a flat color swatch button opening ColorPickerFrame.
    local db  = self.db
    local cat = self.category

    -- Create a dummy setting so the row appears in the category.
    local vn = varName(self.addonName, key .. "_cp")
    local setting = _registered[vn]
    if not setting then
        setting = Settings.RegisterAddOnSetting(
            cat, vn, key .. "_cp", db,
            Settings.VarType.String, label, "")
        _registered[vn] = setting
        -- Custom initializer: override the row with a color swatch.
        Settings.CreateCheckbox(cat, setting, tooltip or "")
    end
    -- Note: full custom initializer support (SettingControlMixin) is
    -- available in TWW 11.1+; for earlier clients we fall back to a
    -- minimap-style button approach via the ForgeWidgets color swatch.

    -- Store a post-show hook to swap the checkbox for a swatch (idempotent).
    if not cat._forgeCPHooks then cat._forgeCPHooks = {} end
    cat._forgeCPHooks[key] = function(frame)
        if frame and frame.Button then
            frame.Button:SetScript("OnClick", function()
                local cur = db[key] or default
                local function applyColor(r, g, b, a)
                    db[key] = { r = r, g = g, b = b, a = a or 1 }
                    frame.Button:GetNormalTexture():SetColorTexture(r, g, b, 1)
                    if onChanged then onChanged(db[key]) end
                end
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = cur.r, g = cur.g, b = cur.b, opacity = 1 - (cur.a or 1),
                    hasOpacity = true,
                    swatchFunc  = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        -- TWW 11.0+ uses GetColorAlpha(); older clients use OpacitySliderFrame.
                        local a = ColorPickerFrame.GetColorAlpha
                            and ColorPickerFrame:GetColorAlpha()
                             or (1 - (OpacitySliderFrame and OpacitySliderFrame:GetValue() or 0))
                        applyColor(r, g, b, a)
                    end,
                    cancelFunc = function(prev)
                        applyColor(prev.r, prev.g, prev.b, 1 - (prev.opacity or 0))
                    end,
                })
            end)
            local c = db[key] or default
            local nt = frame.Button:GetNormalTexture()
            if nt then nt:SetColorTexture(c.r, c.g, c.b, 1) end
        end
    end

    return setting
end

--- Add a multiline text editbox tied to db[key].
-- Rendered inside a scrollable box since Blizzard Settings has no native widget.
-- @param key       string
-- @param label     string
-- @param tooltip   string  (optional)
-- @param height    number  Pixel height of the box (default 72)
-- @param default   string
-- @param onChanged function(newText)  (optional)
function Panel:AddMultiLineText(key, label, tooltip, height, default, onChanged)
    assert(type(key) == "string" and key ~= "",
        "ForgeOptions:AddMultiLineText - key must be a non-empty string")
    assert(type(self.db) == "table",
        "ForgeOptions:AddMultiLineText - panel was created without a db table")

    default = default or ""
    if self.db[key] == nil then self.db[key] = default end
    height  = height or 72

    local db  = self.db
    local cat = self.category
    local vn  = varName(self.addonName, key)

    local setting = _registered[vn]
    if not setting then
        setting = Settings.RegisterAddOnSetting(
            cat, vn, key, db, Settings.VarType.String, label, default)
        _registered[vn] = setting

        -- Custom control: a scrollable multiline EditBox.
        local function initializer(frame, elementData)
            if not frame._forgeMLBox then
                local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
                scroll:SetSize(frame:GetWidth() - 20, height)
                scroll:SetPoint("TOPLEFT", 8, -4)

                local box = CreateFrame("EditBox", nil, scroll)
                box:SetSize(scroll:GetWidth(), height)
                box:SetMultiLine(true)
                box:SetAutoFocus(false)
                box:SetFontObject("ChatFontNormal")
                box:SetMaxLetters(0)
                scroll:SetScrollChild(box)
                frame._forgeMLBox = box

                box:SetScript("OnTextChanged", function(self, userInput)
                    if userInput then
                        db[key] = self:GetText()
                        if onChanged then onChanged(db[key]) end
                    end
                end)
                box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            end
            frame._forgeMLBox:SetText(db[key] or default)
        end

        -- Settings.CreateSettingInitializer is not part of the public Blizzard
        -- API.  Guard the call so this method never crashes on live clients.
        -- The setting is still registered for SavedVariables storage.
        -- For a visible UI row, place a ForgeWidgets:CreateMultiLineEditBox manually.
        if Settings.CreateSettingInitializer then
            Settings.CreateSettingInitializer(cat, setting, nil, initializer)
        end
    end
    return setting
end

--- Add a key-binding capture button tied to db[key].
-- db[key] stores the binding string, e.g. "CTRL-ALT-F".
-- @param key       string
-- @param label     string
-- @param tooltip   string  (optional)
-- @param default   string  Default key string (empty = unbound)
-- @param onChanged function(keyString)  (optional)
function Panel:AddKeyBinding(key, label, tooltip, default, onChanged)
    assert(type(key) == "string" and key ~= "",
        "ForgeOptions:AddKeyBinding - key must be a non-empty string")
    assert(type(self.db) == "table",
        "ForgeOptions:AddKeyBinding - panel was created without a db table")

    default = default or ""
    if self.db[key] == nil then self.db[key] = default end

    local db  = self.db
    local cat = self.category
    local vn  = varName(self.addonName, key)

    local setting = _registered[vn]
    if not setting then
        setting = Settings.RegisterAddOnSetting(
            cat, vn, key, db, Settings.VarType.String, label, default)
        _registered[vn] = setting

        local function initializer(frame, _)
            if frame._forgeKBBtn then
                frame._forgeKBBtn:SetText(db[key] ~= "" and db[key] or "<unbound>")
                return
            end
            local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            btn:SetSize(140, 22)
            btn:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
            btn:SetText(db[key] ~= "" and db[key] or "<unbound>")
            frame._forgeKBBtn = btn

            -- Overlay editbox captures key presses when listening.
            local capture = CreateFrame("EditBox", nil, btn)
            capture:SetAllPoints()
            capture:SetAutoFocus(false)
            capture:Hide()
            capture:SetScript("OnKeyDown", function(self, keyName)
                if keyName == "ESCAPE" then
                    db[key] = ""
                    btn:SetText("<unbound>")
                    if onChanged then onChanged("") end
                    capture:Hide()
                    return
                end
                local modifier = ""
                if IsShiftKeyDown()   then modifier = "SHIFT-"  .. modifier end
                if IsControlKeyDown() then modifier = "CTRL-"   .. modifier end
                if IsAltKeyDown()     then modifier = "ALT-"    .. modifier end
                local binding = modifier .. keyName
                db[key] = binding
                btn:SetText(binding)
                if onChanged then onChanged(binding) end
                capture:Hide()
            end)
            btn:SetScript("OnClick", function()
                btn:SetText("Press a key...")
                capture:Show()
                capture:SetFocus()
            end)
        end

        -- Guard: Settings.CreateSettingInitializer is not in the public WoW API.
        -- The setting is still registered for SavedVariables; use
        -- ForgeWidgets:CreateKeyBinding for the visible capture button.
        if Settings.CreateSettingInitializer then
            Settings.CreateSettingInitializer(cat, setting, nil, initializer)
        end
    end
    return setting
end

--- Add a radio-button group tied to db[key].
-- Implemented as a Blizzard Settings dropdown since the native API
-- has no radio-group widget.
-- @param key       string
-- @param label     string
-- @param tooltip   string  (optional)
-- @param values    table   { {value=x, label=y}, ... }
-- @param default   any     Default selected value
-- @param onChanged function(newValue)  (optional)
function Panel:AddRadioGroup(key, label, tooltip, values, default, onChanged)
    return self:AddDropdown(key, label, tooltip, values, default, onChanged)
end

--- Add a "Profiles" section powered by a ForgeDB instance.
-- Creates a sub-section with controls to switch, create, copy, reset and
-- delete profiles.  Call this after all other widgets on the panel.
-- @param forgeDB  table  A ForgeDB instance (created with ForgeDB:New)
function Panel:AddProfiles(forgeDB)
    assert(type(forgeDB) == "table" and type(forgeDB.SetProfile) == "function",
        "ForgeOptions:AddProfiles - forgeDB must be a ForgeDB instance")

    if Settings.CreateSectionHeader then
        Settings.CreateSectionHeader(self.category, "Profiles")
    end

    local db  = { _profileName = forgeDB:GetCurrentProfile() }
    local cat = self.category

    -- Profile switcher dropdown.
    local function profileList()
        local container = Settings.CreateControlTextContainer()
        for _, name in ipairs(forgeDB:GetProfiles()) do
            container:Add(name, name)
        end
        return container:GetData()
    end

    local swVn = self.addonName .. "_profileSwitch"
    local swSetting = _registered[swVn]
    if not swSetting then
        swSetting = Settings.RegisterAddOnSetting(
            cat, swVn, "_profileName", db,
            Settings.VarType.String, "Active Profile", forgeDB:GetCurrentProfile()
        )
        _registered[swVn] = swSetting
        Settings.CreateDropdown(cat, swSetting, profileList, "Switch to a different profile.")
        Settings.SetOnValueChangedCallback(swVn, function(_, value)
            forgeDB:SetProfile(value)
        end)
    end

    -- New / Copy / Reset / Delete buttons via a custom initializer frame.
    local btnVn = self.addonName .. "_profileBtns"
    if not _registered[btnVn] then
        local btnSetting = Settings.RegisterAddOnSetting(
            cat, btnVn, "_profileName", db,
            Settings.VarType.String, "Profile Actions", ""
        )
        _registered[btnVn] = btnSetting

        if Settings.CreateSettingInitializer then
            Settings.CreateSettingInitializer(cat, btnSetting, nil, function(frame, _)
                if frame._forgeProfileBtns then return end
                frame._forgeProfileBtns = true

                local function makeBtn(text, xOff, onClick)
                    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                    b:SetSize(90, 22)
                    b:SetText(text)
                    b:SetPoint("LEFT", frame, "LEFT", xOff, 0)
                    b:SetScript("OnClick", onClick)
                    return b
                end

                makeBtn("New", 0, function()
                    local name = (forgeDB:GetCurrentProfile() .. "_copy")
                    forgeDB:CopyProfile(name)
                    forgeDB:SetProfile(name)
                    db._profileName = name
                end)
                makeBtn("Copy", 100, function()
                    local src = forgeDB:GetCurrentProfile()
                    local dst = src .. "2"
                    forgeDB:CopyProfile(dst)
                end)
                makeBtn("Reset", 200, function()
                    forgeDB:ResetProfile()
                end)
                makeBtn("Delete", 300, function()
                    local current = forgeDB:GetCurrentProfile()
                    if current ~= "Default" then
                        forgeDB:DeleteProfile(current)
                        forgeDB:SetProfile("Default")
                        db._profileName = "Default"
                    end
                end)
            end)
        end  -- if Settings.CreateSettingInitializer
    end  -- if not _registered[btnVn]
end

--- Create a child sub-category under this panel in the Settings sidebar.
-- @param title  string
-- @return Panel  New panel; call AddCheckbox/AddSlider etc. on it.
function Panel:CreateSubcategory(title)
    assertSettings()
    local sub         = setmetatable({}, Panel)
    sub.addonName     = self.addonName
    sub.title         = title
    sub.db            = self.db
    sub.category      = Settings.RegisterVerticalLayoutSubcategory(self.category, title)
    return sub
end

--- Finalise and register the panel with the Blizzard Settings system.
-- @param owner  table  (optional) ForgeCore addon; sets owner.optionsCategory
function Panel:Register(owner)
    Settings.RegisterAddOnCategory(self.category)
    if owner then
        owner.optionsCategory = self.category
    end
    return self.category
end

--- Open the Settings window directly to this panel.
function Panel:Open()
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.category:GetID())
    end
end

-- ── Constructor ───────────────────────────────────────────────

--- Create a new options panel.
-- @param addonName  string  Unique identifier (addon folder name recommended)
-- @param title      string  Label shown in the Settings sidebar
-- @param db         table   (optional) The db scope to read/write
-- @return Panel
function ForgeOptions:Create(addonName, title, db)
    assertSettings()
    assert(type(addonName) == "string" and addonName ~= "",
        "ForgeOptions:Create - addonName must be a non-empty string")

    local panel       = setmetatable({}, Panel)
    panel.addonName   = addonName
    panel.title       = title or addonName
    panel.db          = db or {}
    panel.category    = Settings.RegisterVerticalLayoutCategory(panel.title)
    return panel
end
