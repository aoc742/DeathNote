-- ============================================================
--  ForgeWidgets.lua  |  v1.1.0
--  ForgeDMC Toolkit
--
--  Replaces : AceGUI-3.0
--  Author   : ForgeDMC  |  2026-03-21  |  MIT
--
--  FIXES v1.1.0
--  ------------
--  * CreateCheckBox: was crashing with _G[nil.."Text"] because CheckButton
--    frames were created with nil name. Now generates a unique name via
--    uniqueName() so UICheckButtonTemplate's sub-frames are accessible.
--  * CreateSlider: same crash (_G[nil.."Low"] etc.). Fixed with unique name.
--  * CreateDropdown: UIDropDownMenuTemplate is deprecated in TWW 11.0+.
--    Now auto-detects DropdownButtonMixin and uses WowStyle1DropdownTemplate
--    on 11.0+ clients; falls back gracefully to legacy template on older ones.
--  * CreateEditBox: added OnEscapePressed handler to clear focus (standard UX).
--  * Added CreateTabStrip(parent, tabNames, onTabChange) — horizontal tab
--    button row with active-state highlighting.
--  * uniqueName() internal counter generates collision-free frame names.
--
--  USAGE
--  -----
--  local win        = ForgeWidgets:CreateWindow("MyFrame", nil, "Title", 700, 500)
--  local panel      = ForgeWidgets:CreatePanel(win)
--  local hdr        = ForgeWidgets:CreateHeader(panel, "Section")
--  local lbl        = ForgeWidgets:CreateLabel(panel, "Some text")
--  local btn        = ForgeWidgets:CreateButton(panel, "Click Me", 120, 22, fn)
--  local chk        = ForgeWidgets:CreateCheckBox(panel, "Enable", "Tooltip", fn)
--  local sld        = ForgeWidgets:CreateSlider(panel, "Scale", 0, 100, 1, fn)
--  local box        = ForgeWidgets:CreateEditBox(panel, 180, 24, fn)
--  local scr, child = ForgeWidgets:CreateScrollFrame(panel, "MyScroll")
--  local dd         = ForgeWidgets:CreateDropdown(panel, 160, items, fn)
--  local tabs, show = ForgeWidgets:CreateTabStrip(panel, {"General","Adv"}, fn)
-- ============================================================

local ForgeWidgets = {}
_G.ForgeWidgets = ForgeWidgets

-- ── Unique name generator ─────────────────────────────────────
-- Many WoW templates require a global string name so their sub-frames
-- are accessible via _G["FrameName" .. "SubKey"].
-- Anonymous (nil-named) frames make those lookups crash with a nil error.

local _nameCounter = 0
local function uniqueName(prefix)
    _nameCounter = _nameCounter + 1
    return (prefix or "ForgeWidget") .. _nameCounter
end

-- ── Window ────────────────────────────────────────────────────

--- Create a movable, closeable top-level window.
-- Registered in UISpecialFrames so Escape closes it automatically.
-- @param name    string  Global frame name (required for Esc; auto-generated if nil)
-- @param parent  frame   Defaults to UIParent
-- @param title   string  Title bar text
-- @param width   number
-- @param height  number
function ForgeWidgets:CreateWindow(name, parent, title, width, height)
    name = name or uniqueName("ForgeWindow")
    local frame = CreateFrame("Frame", name, parent or UIParent, "ButtonFrameTemplate")
    frame:SetSize(width or 700, height or 500)
    frame:SetPoint("CENTER")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:Hide()

    -- BUG FIX: TWW 11.x moved the title FontString from frame.TitleText to
    -- frame.TitleContainer.TitleText.  Check both so the title is set on all clients.
    local titleText = (frame.TitleContainer and frame.TitleContainer.TitleText)
                   or frame.TitleText
    if titleText then
        titleText:SetText(title or name)
    end

    table.insert(UISpecialFrames, frame:GetName())
    return frame
end

-- ── Panel ─────────────────────────────────────────────────────

--- Create a standard inset content panel that fills its parent.
function ForgeWidgets:CreatePanel(parent, name)
    local panel = CreateFrame("Frame", name, parent, "InsetFrameTemplate")
    panel:SetPoint("TOPLEFT",     12,  -28)
    panel:SetPoint("BOTTOMRIGHT", -12,  12)
    return panel
end

-- ── Text labels ───────────────────────────────────────────────

function ForgeWidgets:CreateLabel(parent, text, template)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    label:SetText(text or "")
    label:SetJustifyH("LEFT")
    return label
end

function ForgeWidgets:CreateHeader(parent, text)
    return self:CreateLabel(parent, text, "GameFontNormalLarge")
end

-- ── Button ────────────────────────────────────────────────────

function ForgeWidgets:CreateButton(parent, text, width, height, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 120, height or 22)
    btn:SetText(text or "Button")
    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

-- ── CheckBox ──────────────────────────────────────────────────
-- FIX: UICheckButtonTemplate sub-frames (e.g. <Name>Text) are only accessible
-- by name when the frame itself has a global name. Generate one explicitly.

function ForgeWidgets:CreateCheckBox(parent, label, tooltip, onClick)
    local name  = uniqueName("ForgeCheckBox")
    local check = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")

    -- Template creates a FontString named <FrameName>Text.
    local textObj = _G[name .. "Text"]
    if textObj then
        textObj:SetText(label or "")
    else
        -- Safety fallback (shouldn't happen with UICheckButtonTemplate).
        local fs = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("LEFT", check, "RIGHT", 4, 1)
        fs:SetText(label or "")
        check.text = fs
    end

    if tooltip then
        check.tooltipText = tooltip
    end

    if onClick then
        check:SetScript("OnClick", function(self)
            onClick(self:GetChecked())
        end)
    end

    return check
end

-- ── Slider ────────────────────────────────────────────────────
-- FIX: OptionsSliderTemplate sub-frames (Low/High/Text) require a named frame.

function ForgeWidgets:CreateSlider(parent, label, minValue, maxValue, step, onValueChanged)
    local name   = uniqueName("ForgeSlider")
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minValue or 0, maxValue or 100)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)

    local low  = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local txt  = _G[name .. "Text"]

    if low  then low:SetText(tostring(minValue or 0))   end
    if high then high:SetText(tostring(maxValue or 100)) end
    if txt  then txt:SetText(label or "Slider")          end

    if onValueChanged then
        slider:SetScript("OnValueChanged", function(_, value)
            onValueChanged(value)
        end)
    end

    return slider
end

-- ── EditBox ───────────────────────────────────────────────────

function ForgeWidgets:CreateEditBox(parent, width, height, onEnterPressed)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetSize(width or 180, height or 24)

    if onEnterPressed then
        box:SetScript("OnEnterPressed", function(self)
            onEnterPressed(self:GetText())
            self:ClearFocus()
        end)
    end

    -- FIX: clear focus on Escape (standard WoW text input UX).
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    return box
end

-- ── ScrollFrame ───────────────────────────────────────────────

function ForgeWidgets:CreateScrollFrame(parent, name)
    local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local child  = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll.child = child
    return scroll, child
end

-- ── Dropdown ─────────────────────────────────────────────────
-- FIX: UIDropDownMenuTemplate is deprecated in TWW 11.0+ (interface 110000+).
-- Detect DropdownButtonMixin at runtime and use the modern path when available.

function ForgeWidgets:CreateDropdown(parent, width, items, onValueChanged)
    width = width or 160

    -- ── Modern path: TWW 11.0+ ────────────────────────────────
    if DropdownButtonMixin then
        local btn = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        btn:SetWidth(width)
        btn:SetupMenu(function(_, rootDescription)
            for _, item in ipairs(items or {}) do
                rootDescription:CreateButton(item.label, function()
                    if onValueChanged then onValueChanged(item.value) end
                end)
            end
        end)
        return btn
    end

    -- ── Legacy path: pre-TWW ─────────────────────────────────
    -- UIDropDownMenuTemplate requires a named frame for proper layout.
    local name     = uniqueName("ForgeDropdown")
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, width)

    UIDropDownMenu_Initialize(dropdown, function(_, level)
        for _, item in ipairs(items or {}) do
            local info   = UIDropDownMenu_CreateInfo()
            info.text    = item.label
            info.value   = item.value
            info.func    = function()
                UIDropDownMenu_SetSelectedValue(dropdown, item.value)
                if onValueChanged then onValueChanged(item.value) end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    return dropdown
end

-- ── Icon ──────────────────────────────────────────────────────

--- Create a simple icon texture with optional tooltip.
-- @param parent   frame
-- @param texture  string|number  Path or fileID
-- @param size     number  Width = height in px (default 32)
-- @param tooltip  string  (optional) tooltip on hover
function ForgeWidgets:CreateIcon(parent, texture, size, tooltip)
    size = size or 32
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(texture)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.tex = tex

    if tooltip and tooltip ~= "" then
        frame:EnableMouse(true)
        frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return frame
end

-- ── MultiLineEditBox ──────────────────────────────────────────

--- Create a scrollable multiline editbox.
-- @param parent    frame
-- @param width     number  (default 300)
-- @param height    number  (default 120)
-- @param onChanged function(text)  fired on user edits (optional)
function ForgeWidgets:CreateMultiLineEditBox(parent, width, height, onChanged)
    width  = width  or 300
    height = height or 120

    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetSize(width, height)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetSize(width, height)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetMaxLetters(0)
    scroll:SetScrollChild(box)
    scroll.editBox = box

    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if onChanged then
        box:SetScript("OnTextChanged", function(self, userInput)
            if userInput then onChanged(self:GetText()) end
        end)
    end

    return scroll
end

-- ── KeyBinding ────────────────────────────────────────────────

--- Create a key-binding capture button.
-- Click it, press a key combination to bind; Escape clears the binding.
-- @param parent     frame
-- @param label      string  Label to the right of the button (optional)
-- @param currentKey string  Initial binding, e.g. "CTRL-F" (optional)
-- @param onChange   function(keyString)  fires when binding changes
function ForgeWidgets:CreateKeyBinding(parent, label, currentKey, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(22)

    local btn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    btn:SetSize(140, 22)
    btn:SetPoint("LEFT", container, "LEFT", 0, 0)
    btn:SetText(currentKey and currentKey ~= "" and currentKey or "<unbound>")
    container.button = btn

    if label and label ~= "" then
        local lbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        lbl:SetText(label)
        lbl:SetPoint("LEFT", btn, "RIGHT", 8, 0)
        container.label = lbl
    end

    -- Invisible overlay EditBox to capture key events.
    local capture = CreateFrame("EditBox", nil, btn)
    capture:SetAllPoints()
    capture:SetAutoFocus(false)
    capture:Hide()

    capture:SetScript("OnKeyDown", function(self, keyName)
        if keyName == "ESCAPE" then
            btn:SetText("<unbound>")
            if onChange then onChange("") end
            capture:Hide()
            return
        end
        -- Ignore bare modifier keys.
        if keyName == "LSHIFT" or keyName == "RSHIFT"
        or keyName == "LCTRL"  or keyName == "RCTRL"
        or keyName == "LALT"   or keyName == "RALT" then return end

        local mod = ""
        if IsShiftKeyDown()   then mod = "SHIFT-"   .. mod end
        if IsControlKeyDown() then mod = "CTRL-"    .. mod end
        if IsAltKeyDown()     then mod = "ALT-"     .. mod end
        local binding = mod .. keyName
        btn:SetText(binding)
        if onChange then onChange(binding) end
        capture:Hide()
    end)

    btn:SetScript("OnClick", function()
        btn:SetText("Press a key...")
        capture:Show()
        capture:SetFocus()
    end)

    return container
end

-- ── InlineGroup ───────────────────────────────────────────────

--- Create a titled bordered box for grouping child widgets.
-- @param parent  frame
-- @param title   string  Title in the top-left border gap (optional)
-- @param width   number  (default 300)
-- @param height  number  (default 120)
-- Returns the outer frame; place children inside frame.content.
function ForgeWidgets:CreateInlineGroup(parent, title, width, height)
    width  = width  or 300
    height = height or 120

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 1, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        frame:SetBackdropColor(0.06, 0.06, 0.08, 0.8)
        frame:SetBackdropBorderColor(0.18, 0.22, 0.32, 1)
    end

    if title and title ~= "" then
        local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetText(title)
        lbl:SetPoint("TOPLEFT", 8, 6)
        frame.title = lbl
    end

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT",     6, -18)
    content:SetPoint("BOTTOMRIGHT", -6,   6)
    frame.content = content

    return frame
end

-- ── ColorSwatch ───────────────────────────────────────────────

--- Create a colored swatch button that opens ColorPickerFrame on click.
-- @param parent     frame
-- @param r,g,b,a    number  Initial RGBA (0..1); a defaults to 1
-- @param onChange   function({ r, g, b, a })  fires when color confirmed
-- @param label      string  Optional text label to the right of the swatch
function ForgeWidgets:CreateColorSwatch(parent, r, g, b, a, onChange, label)
    r, g, b = r or 1, g or 1, b or 1
    a = a or 1

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(20, 20)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(r, g, b, 1)
    btn.tex   = tex
    btn.color = { r = r, g = g, b = b, a = a }

    if label and label ~= "" then
        local lbl = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        lbl:SetText(label)
        lbl:SetPoint("LEFT", btn, "RIGHT", 6, 0)
        btn.label = lbl
    end

    btn:SetScript("OnClick", function(self)
        local cur = self.color
        local function apply(nr, ng, nb, na)
            self.color = { r = nr, g = ng, b = nb, a = na }
            tex:SetColorTexture(nr, ng, nb, 1)
            if onChange then onChange(self.color) end
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = cur.r, g = cur.g, b = cur.b,
            opacity    = 1 - cur.a,
            hasOpacity = true,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = ColorPickerFrame.GetColorAlpha
                    and ColorPickerFrame:GetColorAlpha()
                     or (1 - (OpacitySliderFrame and OpacitySliderFrame:GetValue() or 0))
                apply(nr, ng, nb, na)
            end,
            cancelFunc = function(prev)
                apply(prev.r, prev.g, prev.b, 1 - (prev.opacity or 0))
            end,
        })
    end)

    btn:SetScript("OnEnter", function(self)
        local c = self.color
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(
            string.format("R %.2f  G %.2f  B %.2f  A %.2f", c.r, c.g, c.b, c.a), 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

-- ── Tab strip ─────────────────────────────────────────────────
-- Horizontal row of tab buttons with active-state highlighting.
-- @param parent      frame
-- @param tabNames    table   { "General", "Advanced", ... }
-- @param onTabChange function(index)  called when user clicks a tab
-- @return tabFrame   frame   The strip container
-- @return showTab    function(index)  call to switch tabs in code

function ForgeWidgets:CreateTabStrip(parent, tabNames, onTabChange)
    local tabFrame = CreateFrame("Frame", nil, parent)
    tabFrame:SetHeight(24)
    tabFrame:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -4)
    tabFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -4)

    local tabs     = {}
    local selected = 1

    local function selectTab(index)
        selected = index
        for i, tab in ipairs(tabs) do
            if i == index then
                tab:SetNormalFontObject("GameFontHighlightSmall")
                tab:LockHighlight()
            else
                tab:SetNormalFontObject("GameFontNormalSmall")
                tab:UnlockHighlight()
            end
        end
        if onTabChange then onTabChange(index) end
    end

    for i, tabName in ipairs(tabNames) do
        local tab = CreateFrame("Button", nil, tabFrame, "TabButtonTemplate")
        tab:SetText(tabName)
        tab:SetID(i)
        if i == 1 then
            tab:SetPoint("BOTTOMLEFT", tabFrame, "BOTTOMLEFT", 4, 0)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -14, 0)
        end
        tab:SetScript("OnClick", function(self)
            selectTab(self:GetID())
        end)
        tabs[i] = tab
    end

    selectTab(1)
    return tabFrame, selectTab
end
