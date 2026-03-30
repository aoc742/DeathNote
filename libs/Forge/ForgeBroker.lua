-- ============================================================
--  ForgeBroker.lua  |  v1.0.0
--  ForgeDMC Toolkit
--
--  Replaces: LibDataBroker-1.1 + LibDBIcon-1.0
--
--  These two libraries are always used together:
--    LibDataBroker  — a data object with attributes (icon, text, OnClick…)
--    LibDBIcon      — reads that object and creates the minimap button
--
--  ForgeBroker merges them into a single, self-contained module.
--  No CallbackHandler, no LibStub, no separate icon library needed.
--
--  USAGE
--  -----
--  -- Minimal (just a click handler):
--  local btn = ForgeBroker:Register("MyAddon", {
--      icon    = "Interface\\Icons\\Trade_Engineering",
--      label   = "My Addon",           -- tooltip title
--      OnClick = function(frame, button)
--          if button == "LeftButton" then MyAddon:Toggle() end
--          if button == "RightButton" then MyAddon:OpenOptions() end
--      end,
--      OnTooltipShow = function(tip)
--          tip:AddLine("My Addon", 1, 1, 1)
--          tip:AddLine("Left-click to toggle.", 0.8, 0.8, 0.8)
--      end,
--  }, MyAddon.db.profile)   -- db scope must contain { minimapPos, hide, lock }
--
--  -- Control visibility:
--  ForgeBroker:Show("MyAddon")
--  ForgeBroker:Hide("MyAddon")
--  ForgeBroker:SetShown("MyAddon", MyAddon.db.profile.showMinimap)
--
--  -- Lock/unlock dragging:
--  ForgeBroker:Lock("MyAddon")
--  ForgeBroker:Unlock("MyAddon")
--
--  -- Update the icon texture at runtime:
--  ForgeBroker:SetIcon("MyAddon", "Interface\\Icons\\Spell_Nature_Lightning")
--
--  -- AddonCompartment (the button tray next to the minimap, TWW+):
--  ForgeBroker:AddToCompartment("MyAddon")
--  ForgeBroker:RemoveFromCompartment("MyAddon")
--
--  -- DB keys used (all optional — ForgeBroker falls back to defaults):
--  db.minimapPos  number   Angle in degrees (0-360). Default: 225.
--  db.hide        boolean  Whether the button is hidden. Default: false.
--  db.lock        boolean  Whether dragging is disabled. Default: false.
-- ============================================================

ForgeBroker = ForgeBroker or {}

local _objects  = {}   -- [name] = button frame
local _tooltip  = nil  -- shared GameTooltip, created on first use

-- ── Math helpers ──────────────────────────────────────────────

local rad, cos, sin, atan2, deg = math.rad, math.cos, math.sin, math.atan2, math.deg
local sqrt, max, min             = math.sqrt, math.max, math.min
local RADIUS                     = 5   -- pixels of clearance beyond minimap edge

-- All minimap shapes shipped with the game, mapping quadrant flags to
-- whether that quadrant is round (true) or square-clipped (false).
local MINIMAP_SHAPES = {
    ["ROUND"]                  = {true,  true,  true,  true },
    ["SQUARE"]                 = {false, false, false, false},
    ["CORNER-TOPLEFT"]         = {false, false, false, true },
    ["CORNER-TOPRIGHT"]        = {false, false, true,  false},
    ["CORNER-BOTTOMLEFT"]      = {false, true,  false, false},
    ["CORNER-BOTTOMRIGHT"]     = {true,  false, false, false},
    ["SIDE-LEFT"]              = {false, true,  false, true },
    ["SIDE-RIGHT"]             = {true,  false, true,  false},
    ["SIDE-TOP"]               = {false, false, true,  true },
    ["SIDE-BOTTOM"]            = {true,  true,  false, false},
    ["TRICORNER-TOPLEFT"]      = {false, true,  true,  true },
    ["TRICORNER-TOPRIGHT"]     = {true,  false, true,  true },
    ["TRICORNER-BOTTOMLEFT"]   = {true,  true,  false, true },
    ["TRICORNER-BOTTOMRIGHT"]  = {true,  true,  true,  false},
}

local function updatePosition(button, angleDeg)
    angleDeg = angleDeg or 225
    local angle = rad(angleDeg)
    local x, y  = cos(angle), sin(angle)

    -- Determine quadrant (1=SE, 2=SW, 3=NW, 4=NE in WoW coord space).
    local q = 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end

    local shape     = (GetMinimapShape and GetMinimapShape()) or "ROUND"
    local quadTable = MINIMAP_SHAPES[shape] or MINIMAP_SHAPES["ROUND"]
    local w = (Minimap:GetWidth()  / 2) + RADIUS
    local h = (Minimap:GetHeight() / 2) + RADIUS

    if quadTable[q] then
        x, y = x * w, y * h
    else
        local dw = sqrt(2 * w * w) - 10
        local dh = sqrt(2 * h * h) - 10
        x = max(-w, min(x * dw, w))
        y = max(-h, min(y * dh, h))
    end

    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- ── Tooltip anchor helper ─────────────────────────────────────

local function tooltipAnchor(frame)
    local x, y   = frame:GetCenter()
    local W, H   = UIParent:GetWidth(), UIParent:GetHeight()
    local hside   = (x > W * 2 / 3) and "RIGHT" or (x < W / 3) and "LEFT" or ""
    local vside   = (y > H / 2) and "TOP" or "BOTTOM"
    return vside .. hside, frame, (vside == "TOP" and "BOTTOM" or "TOP") .. hside
end

local function getTooltip()
    if not _tooltip then
        _tooltip = CreateFrame("GameTooltip", "ForgeBrokerTooltip", UIParent, "GameTooltipTemplate")
    end
    return _tooltip
end

-- ── Drag logic ────────────────────────────────────────────────

local _dragging = false

local function onDragStart(button)
    _dragging = true
    button:SetScript("OnUpdate", function(self)
        local mx, my   = Minimap:GetCenter()
        local px, py   = GetCursorPosition()
        local scale    = Minimap:GetEffectiveScale()
        local angleDeg = deg(atan2((py / scale) - my, (px / scale) - mx)) % 360

        if self.db then
            self.db.minimapPos = angleDeg
        else
            self.minimapPos = angleDeg
        end
        updatePosition(self, angleDeg)
    end)
end

local function onDragStop(button)
    _dragging = false
    button:SetScript("OnUpdate", nil)
end

-- ── Mouse events ──────────────────────────────────────────────

local function onEnter(self)
    local obj = self.dataObject
    local tip = getTooltip()

    if obj.OnTooltipShow then
        tip:SetOwner(self, "ANCHOR_NONE")
        tip:SetPoint(tooltipAnchor(self))
        tip:ClearLines()
        if obj.label and obj.label ~= "" then
            tip:AddLine(obj.label, 1, 1, 1)
        end
        obj.OnTooltipShow(tip)
        tip:Show()
    elseif obj.OnEnter then
        obj.OnEnter(self)
    end
end

local function onLeave(self)
    getTooltip():Hide()
    local obj = self.dataObject
    if obj.OnLeave then obj.OnLeave(self) end
end

local function onClick(self, mouseButton)
    local obj = self.dataObject
    if obj.OnClick then obj.OnClick(self, mouseButton) end
end

local function onMouseDown(self)
    self.isMouseDown = true
    -- BUG FIX: was identical to OnMouseUp (no visual pressed feedback).
    -- Slight inward crop gives a subtle "zoom-in" press effect.
    if self.icon then self.icon:SetTexCoord(0.12, 0.88, 0.12, 0.88) end
end

local function onMouseUp(self)
    self.isMouseDown = false
    if self.icon then self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
end

-- ── Button factory ────────────────────────────────────────────

local function createButton(name, dataObject, db)
    local button = CreateFrame("Button", "ForgeBroker_" .. name, Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")

    -- Circular mask so the button clips to the minimap edge cleanly.
    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    mask:SetAllPoints()

    -- Icon texture.
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetAllPoints()
    icon:SetTexture(dataObject.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    button.icon = icon

    -- Hover highlight ring.
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetAllPoints()
    button:SetHighlightTexture(hl)

    -- Fade-out animation for mouseover-only mode.
    local fadeGroup = button:CreateAnimationGroup()
    local fadeAnim  = fadeGroup:CreateAnimation("Alpha")
    fadeAnim:SetOrder(1)
    fadeAnim:SetDuration(0.2)
    fadeAnim:SetFromAlpha(1)
    fadeAnim:SetToAlpha(0)
    fadeAnim:SetStartDelay(1)
    fadeGroup:SetToFinalAlpha(true)
    button.fadeOut = fadeGroup

    button.dataObject = dataObject
    button.db         = db

    button:SetScript("OnEnter",     onEnter)
    button:SetScript("OnLeave",     onLeave)
    button:SetScript("OnClick",     onClick)
    button:SetScript("OnMouseDown", onMouseDown)
    button:SetScript("OnMouseUp",   onMouseUp)

    if not db or not db.lock then
        button:SetScript("OnDragStart", onDragStart)
        button:SetScript("OnDragStop",  onDragStop)
    end

    local pos = (db and db.minimapPos) or 225
    updatePosition(button, pos)

    if db and db.hide then
        button:Hide()
    else
        button:Show()
    end

    _objects[name] = button
    return button
end

-- ── Public API ────────────────────────────────────────────────

--- Create and register a minimap button.
-- @param name        string   Unique name (used for all subsequent API calls)
-- @param dataObject  table    { icon, label, OnClick, OnTooltipShow, OnEnter, OnLeave }
-- @param db          table    (optional) saved db scope { minimapPos, hide, lock }
-- @return button     frame
function ForgeBroker:Register(name, dataObject, db)
    assert(type(name) == "string" and name ~= "",
        "ForgeBroker:Register - name must be a non-empty string")
    assert(type(dataObject) == "table",
        "ForgeBroker:Register - dataObject must be a table")
    assert(not _objects[name],
        "ForgeBroker:Register - '" .. name .. "' is already registered")
    assert(dataObject.icon,
        "ForgeBroker:Register - dataObject.icon is required")

    return createButton(name, dataObject, db)
end

--- Show the minimap button.
function ForgeBroker:Show(name)
    local btn = _objects[name]
    if btn then
        btn:Show()
        updatePosition(btn, (btn.db and btn.db.minimapPos) or btn.minimapPos or 225)
        if btn.db then btn.db.hide = nil end
    end
end

--- Hide the minimap button.
function ForgeBroker:Hide(name)
    local btn = _objects[name]
    if btn then
        btn:Hide()
        if btn.db then btn.db.hide = true end
    end
end

--- Show or hide based on a boolean.
function ForgeBroker:SetShown(name, shown)
    if shown then self:Show(name) else self:Hide(name) end
end

--- Prevent the user from dragging the button.
function ForgeBroker:Lock(name)
    local btn = _objects[name]
    if btn then
        btn:SetScript("OnDragStart", nil)
        btn:SetScript("OnDragStop",  nil)
        if btn.db then btn.db.lock = true end
    end
end

--- Allow the user to drag the button again.
function ForgeBroker:Unlock(name)
    local btn = _objects[name]
    if btn then
        btn:SetScript("OnDragStart", onDragStart)
        btn:SetScript("OnDragStop",  onDragStop)
        if btn.db then btn.db.lock = nil end
    end
end

--- Change the button's icon texture at runtime.
function ForgeBroker:SetIcon(name, texture)
    local btn = _objects[name]
    if btn and btn.icon then
        btn.icon:SetTexture(texture)
        btn.dataObject.icon = texture
    end
end

--- Move the button to a specific angle (0-360 degrees).
function ForgeBroker:SetPosition(name, angleDeg)
    local btn = _objects[name]
    if btn then
        updatePosition(btn, angleDeg)
        if btn.db then btn.db.minimapPos = angleDeg end
    end
end

--- Show button only when the mouse is hovering over the minimap area.
-- @param value  boolean  true = mouseover only, false = always visible
function ForgeBroker:SetMouseoverOnly(name, value)
    local btn = _objects[name]
    if not btn then return end
    btn.showOnMouseover = value
    if value then
        btn.fadeOut:Stop()
        btn:SetAlpha(0)
    else
        btn.fadeOut:Stop()
        btn:SetAlpha(1)
    end
end

--- Returns the button frame (for advanced customisation).
function ForgeBroker:GetButton(name)
    return _objects[name]
end

--- Returns true if the named button is registered.
function ForgeBroker:IsRegistered(name)
    return _objects[name] ~= nil
end

-- ── AddonCompartment (TWW 11.0+ button tray) ─────────────────

--- Register the button with the AddonCompartment tray (if available).
function ForgeBroker:AddToCompartment(name)
    if not AddonCompartmentFrame then return end
    local btn = _objects[name]
    if not btn or btn._compartmentData then return end

    local obj = btn.dataObject
    local data = {
        text              = obj.label or name,
        icon              = obj.icon,
        notCheckable      = true,
        registerForAnyClick = true,
        func = function(frame, _, _, _, clickType)
            if obj.OnClick then obj.OnClick(frame, clickType) end
        end,
        funcOnEnter = function(frame)
            local tip = getTooltip()
            if obj.OnTooltipShow then
                tip:SetOwner(frame, "ANCHOR_NONE")
                tip:SetPoint(tooltipAnchor(frame))
                tip:ClearLines()
                if obj.label then tip:AddLine(obj.label, 1, 1, 1) end
                obj.OnTooltipShow(tip)
                tip:Show()
            elseif obj.OnEnter then
                obj.OnEnter(frame)
            end
        end,
        funcOnLeave = function()
            getTooltip():Hide()
            if obj.OnLeave then obj.OnLeave() end
        end,
    }
    btn._compartmentData = data
    AddonCompartmentFrame:RegisterAddon(data)
end

--- Remove from AddonCompartment.
function ForgeBroker:RemoveFromCompartment(name)
    if not AddonCompartmentFrame then return end
    local btn = _objects[name]
    if not btn or not btn._compartmentData then return end

    local registered = AddonCompartmentFrame.registeredAddons
    for i = #registered, 1, -1 do
        if registered[i] == btn._compartmentData then
            table.remove(registered, i)
            break
        end
    end
    btn._compartmentData = nil
    AddonCompartmentFrame:UpdateDisplay()
end

--- Returns true if the named button is in the AddonCompartment.
function ForgeBroker:IsInCompartment(name)
    local btn = _objects[name]
    return btn ~= nil and btn._compartmentData ~= nil
end
