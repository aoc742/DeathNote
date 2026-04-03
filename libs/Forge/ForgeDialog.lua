-- ============================================================
--  ForgeDialog.lua  |  v1.0.0
--  ForgeDMC Toolkit
--
--  Replaces: LibDialog-1.0
--
--  LibDialog wraps Blizzard's StaticPopup system with a cleaner
--  API and adds features like multiple editboxes and checkboxes.
--  ForgeDialog does the same using modern Blizzard APIs, with
--  frame pooling, Escape-key support, timeout timers, and a
--  queue for dialogs that arrive while 4 are already shown.
--
--  USAGE
--  -----
--  -- Define a dialog (do this once, e.g. in OnInitialize):
--  ForgeDialog:Register("MYADDON_CONFIRM_DELETE", {
--      text            = "Are you sure you want to delete this profile?",
--      icon            = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",  -- optional
--      duration        = 30,        -- auto-cancel after 30s (optional)
--      hide_on_escape  = true,
--      is_exclusive    = false,     -- if true, dismisses other exclusive dialogs
--
--      buttons = {
--          { text = "Delete",  on_click = function(dialog, data) data:Delete() end },
--          { text = "Cancel" },     -- on_click omitted = just closes
--      },
--
--      -- Optional extra widgets:
--      editboxes = {
--          { label = "New name:", max_letters = 32, auto_focus = true,
--            on_enter_pressed = function(box, data) data.name = box:GetText() end },
--      },
--      checkboxes = {
--          { label = "Also delete saved data",
--            get_value = function(cb, data) return data.deleteData end,
--            set_value = function(cb, value, data) data.deleteData = not value end },
--      },
--
--      on_show   = function(dialog, data) end,
--      on_hide   = function(dialog, data) end,
--      on_cancel = function(dialog, data, reason) end,  -- reason: "timeout"|"escape"|"override"
--      on_update = function(dialog, elapsed) end,
--  })
--
--  -- Show it:
--  ForgeDialog:Spawn("MYADDON_CONFIRM_DELETE", myProfileObject)
--
--  -- Check if it's visible:
--  ForgeDialog:IsActive("MYADDON_CONFIRM_DELETE")  -- true/false
--
--  -- Dismiss programmatically:
--  ForgeDialog:Dismiss("MYADDON_CONFIRM_DELETE")
-- ============================================================

ForgeDialog = ForgeDialog or {}

-- ── Constants ─────────────────────────────────────────────────

local MAX_ACTIVE    = 4
local DIALOG_W      = 320
local DIALOG_H      = 72
local BTN_W, BTN_H  = 120, 21
local EDIT_W        = 200
local CB_H          = 28
local TEXT_W        = 290

local BACKDROP = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile     = true, tileSize = 32, edgeSize = 32,
    insets   = { left = 11, right = 12, top = 12, bottom = 11 },
}

-- ── State ─────────────────────────────────────────────────────

local _delegates  = {}   -- [name] = definition table
local _active     = {}   -- ordered list of live dialog frames
local _queue      = {}   -- { delegate, data } entries waiting for a slot

-- Frame/widget pools (recycled to avoid allocation spam).
local _dialogPool = {}
local _btnPool    = {}
local _editPool   = {}
local _cbPool     = {}

-- ── Unique name counter ───────────────────────────────────────

local _counter = 0
local function uid(prefix)
    _counter = _counter + 1
    return (prefix or "FDlg") .. _counter
end

-- ── Anchor refresh ────────────────────────────────────────────

local function refreshAnchors()
    for i, dlg in ipairs(_active) do
        dlg:ClearAllPoints()
        if i == 1 then
            -- Stack below any visible native StaticPopups.
            local native = StaticPopup_DisplayedFrames
                       and StaticPopup_DisplayedFrames[#StaticPopup_DisplayedFrames]
            if native and native:IsShown() then
                dlg:SetPoint("TOP", native, "BOTTOM", 0, 0)
            else
                dlg:SetPoint("TOP", UIParent, "TOP", 0, -135)
            end
        else
            dlg:SetPoint("TOP", _active[i - 1], "BOTTOM", 0, 0)
        end
    end
end

-- ── Pool helpers ──────────────────────────────────────────────

local function acquireWidget(pool, createFn)
    return table.remove(pool) or createFn()
end

local function releaseWidget(widget, pool)
    widget:ClearAllPoints()
    widget:Hide()
    widget:SetParent(nil)
    pool[#pool + 1] = widget
end

-- ── Widget creators ───────────────────────────────────────────

local function createEditBox()
    local name = uid("ForgeDialogEdit")
    local box  = CreateFrame("EditBox", name, UIParent, "InputBoxTemplate")
    box:SetHeight(28)
    box:SetFontObject("ChatFontNormal")
    box:SetAutoFocus(false)

    local label = box:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("RIGHT", box, "LEFT", -6, 0)
    box.label = label

    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function createCheckBox()
    local name = uid("ForgeDialogCB")
    local cb   = CreateFrame("CheckButton", name, UIParent, "UICheckButtonTemplate")
    local lbl  = _G[name .. "Text"]
    if not lbl then
        lbl = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    end
    cb.lbl = lbl
    return cb
end

local function createButton()
    local btn = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    btn:SetSize(BTN_W, BTN_H)
    return btn
end

-- ── Dialog release ────────────────────────────────────────────

local function releaseDialog(dlg)
    -- Release child widgets back to their pools.
    if dlg._buttons then
        for _, b in ipairs(dlg._buttons) do releaseWidget(b, _btnPool) end
        dlg._buttons = nil
    end
    if dlg._editboxes then
        for _, e in ipairs(dlg._editboxes) do
            e.label:SetText("")
            releaseWidget(e, _editPool)
        end
        dlg._editboxes = nil
    end
    if dlg._checkboxes then
        for _, c in ipairs(dlg._checkboxes) do
            c:SetScript("OnClick", nil)
            releaseWidget(c, _cbPool)
        end
        dlg._checkboxes = nil
    end

    -- Remove from active list.
    for i = #_active, 1, -1 do
        if _active[i] == dlg then table.remove(_active, i) break end
    end

    dlg._delegate = nil
    dlg._data     = nil
    dlg:SetScript("OnUpdate", nil)
    dlg._timer = nil

    releaseWidget(dlg, _dialogPool)
    refreshAnchors()

    -- Drain queue if a slot just opened.
    while #_active < MAX_ACTIVE and #_queue > 0 do
        local next = table.remove(_queue, 1)
        ForgeDialog:Spawn(next.delegate, next.data)
    end
end

-- ── Build dialog ──────────────────────────────────────────────

local function buildDialog(delegate, data)
    -- Acquire or create dialog frame.
    local dlg = acquireWidget(_dialogPool, function()
        local f = CreateFrame("Frame", uid("ForgeDialog"), UIParent,
                      BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop",  f.StopMovingOrSizing)

        local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetWidth(TEXT_W)
        text:SetJustifyH("CENTER")
        text:SetJustifyV("MIDDLE")
        text:SetPoint("TOP", 0, -16)
        f._text = text

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -3, -3)
        f._closeBtn = closeBtn
        closeBtn:SetScript("OnClick", function()
            if delegate and delegate.on_cancel then
                delegate.on_cancel(f, f._data, "escape")
            end
            f:Hide()
        end)

        if f.SetBackdrop then f:SetBackdrop(BACKDROP) end
        return f
    end)

    dlg._delegate = delegate
    dlg._data     = data
    dlg._timer    = delegate.duration   -- seconds remaining (nil = no timeout)

    -- BUG FIX: reset close button script on every activation.
    -- The creation closure captures the first-ever `delegate`; recycled frames
    -- retain that stale reference.  Reassign here so the current delegate is used.
    dlg._closeBtn:SetScript("OnClick", function()
        local d = dlg._delegate
        if d and d.on_cancel then d.on_cancel(dlg, dlg._data, "escape") end
        dlg:Hide()
    end)

    dlg._text:SetText(delegate.text or "")
    dlg._closeBtn:SetShown(not delegate.no_close_button)

    -- Icon.
    if type(delegate.icon) == "string" then
        if not dlg._icon then
            dlg._icon = dlg:CreateTexture(nil, "ARTWORK")
            dlg._icon:SetSize(36, 36)
            dlg._icon:SetPoint("LEFT", 16, 0)
        end
        dlg._icon:SetTexture(delegate.icon)
        dlg._icon:Show()
    elseif dlg._icon then
        dlg._icon:Hide()
    end

    -- Buttons.
    local buttons    = delegate.buttons or {}
    local numButtons = math.min(#buttons, 3)
    dlg._buttons     = {}

    for i = 1, numButtons do
        local def = buttons[i]
        local btn = acquireWidget(_btnPool, createButton)
        btn:SetParent(dlg)
        btn:SetText(def.text or "OK")
        btn:SetID(i)

        local tw = btn:GetFontString():GetStringWidth()
        btn:SetWidth(math.max(BTN_W, tw + 20))

        btn:SetScript("OnClick", function()
            local keep = false
            if def.on_click then keep = def.on_click(dlg, dlg._data) end
            if not keep then dlg:Hide() end
        end)

        btn:Show()
        dlg._buttons[i] = btn
    end

    -- Button layout.
    for i, btn in ipairs(dlg._buttons) do
        btn:ClearAllPoints()
        if i == 1 then
            if numButtons == 3 then
                btn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOM", -72, 16)
            elseif numButtons == 2 then
                btn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOM", -6,  16)
            else
                btn:SetPoint("BOTTOM", dlg, "BOTTOM", 0, 16)
            end
        else
            btn:SetPoint("LEFT", dlg._buttons[i - 1], "RIGHT", 13, 0)
        end
    end

    -- EditBoxes.
    local editDefs   = delegate.editboxes or {}
    dlg._editboxes   = {}
    for i, def in ipairs(editDefs) do
        local box = acquireWidget(_editPool, createEditBox)
        box:SetParent(dlg)
        box:SetWidth(def.width or EDIT_W)
        box:SetMaxLetters(def.max_letters or 0)
        box:SetText(def.text or "")
        box:SetAutoFocus(def.auto_focus and true or false)

        if def.label and def.label ~= "" then
            box.label:SetText(def.label)
            box.label:Show()
        else
            box.label:Hide()
        end

        if def.on_enter_pressed then
            box:SetScript("OnEnterPressed", function(self)
                def.on_enter_pressed(self, dlg._data)
            end)
        else
            box:SetScript("OnEnterPressed", nil)
        end

        if def.on_text_changed then
            box:SetScript("OnTextChanged", function(self, userInput)
                if userInput then def.on_text_changed(self, dlg._data) end
            end)
        else
            box:SetScript("OnTextChanged", nil)
        end

        box:ClearAllPoints()
        if i == 1 then
            box:SetPoint("TOP", dlg._text, "BOTTOM", 0, -10)
        else
            box:SetPoint("TOP", dlg._editboxes[i - 1], "BOTTOM", 0, -4)
        end
        box:Show()
        dlg._editboxes[i] = box
    end

    -- Checkboxes.
    local cbDefs     = delegate.checkboxes or {}
    dlg._checkboxes  = {}
    for i, def in ipairs(cbDefs) do
        local cb = acquireWidget(_cbPool, createCheckBox)
        cb:SetParent(dlg)
        cb.lbl:SetText(def.label or "")
        cb:SetID(i)

        -- Resolve initial checked state.
        if def.get_value then
            cb:SetChecked(def.get_value(cb, data))
        else
            cb:SetChecked(false)
        end

        cb:SetScript("OnClick", function(self)
            local val = self:GetChecked()
            if def.set_value then def.set_value(self, val, dlg._data) end
            if def.get_value then self:SetChecked(def.get_value(self, dlg._data)) end
        end)

        cb:ClearAllPoints()
        local anchor = (#dlg._editboxes > 0)
                   and dlg._editboxes[#dlg._editboxes]
                   or  dlg._text
        if i == 1 then
            cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
        else
            cb:SetPoint("TOPLEFT", dlg._checkboxes[i - 1], "BOTTOMLEFT", 0, 0)
        end
        cb:Show()
        dlg._checkboxes[i] = cb
    end

    -- Auto-resize height to fit content.
    local height = 32 + dlg._text:GetHeight()
    if numButtons > 0         then height = height + BTN_H + 8 end
    height = height + (#editDefs   * (28 + 4))
    height = height + (#cbDefs     * CB_H)
    dlg:SetWidth(delegate.width  or DIALOG_W)
    dlg:SetHeight(math.max(DIALOG_H, height + 16))
    dlg._text:SetWidth((delegate.width or DIALOG_W) - 60)

    -- Lifecycle scripts.
    dlg:SetScript("OnShow", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN, "Master")
        if delegate.on_show then delegate.on_show(self, self._data) end
    end)

    dlg:SetScript("OnHide", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE, "Master")
        local d = self._delegate
        if d and d.on_hide then d.on_hide(self, self._data) end
        releaseDialog(self)
    end)

    dlg:SetScript("OnUpdate", function(self, elapsed)
        -- Timeout countdown.
        if self._timer then
            self._timer = self._timer - elapsed
            if self._timer <= 0 then
                self._timer = nil
                local d = self._delegate
                if d and d.on_cancel then d.on_cancel(self, self._data, "timeout") end
                self:Hide()
                return
            end
        end
        -- Per-frame delegate callback.
        if delegate.on_update then delegate.on_update(dlg, elapsed) end
    end)

    -- Anchor.
    dlg:ClearAllPoints()
    if #_active > 0 then
        dlg:SetPoint("TOP", _active[#_active], "BOTTOM", 0, 0)
    else
        local native = StaticPopup_DisplayedFrames
                   and StaticPopup_DisplayedFrames[#StaticPopup_DisplayedFrames]
        if native and native:IsShown() then
            dlg:SetPoint("TOP", native, "BOTTOM", 0, 0)
        else
            dlg:SetPoint("TOP", UIParent, "TOP", 0, -135)
        end
    end

    _active[#_active + 1] = dlg
    return dlg
end

-- ── Hook native StaticPopup repositioning ─────────────────────
-- Only installed once.

local _hooked = false
local function ensureHooks()
    if _hooked then return end
    _hooked = true
    hooksecurefunc("StaticPopup_OnHide",     function() refreshAnchors() end)
    hooksecurefunc("StaticPopup_SetUpPosition", function() refreshAnchors() end)

    -- Escape key: dismiss dialogs that have hide_on_escape = true.
    hooksecurefunc("StaticPopup_EscapePressed", function()
        local toClose = {}
        for _, dlg in ipairs(_active) do
            if dlg._delegate and dlg._delegate.hide_on_escape then
                toClose[#toClose + 1] = dlg
            end
        end
        for _, dlg in ipairs(toClose) do
            local d = dlg._delegate
            if d and d.on_cancel and not d.no_cancel_on_escape then
                d.on_cancel(dlg, dlg._data, "escape")
            end
            dlg:Hide()
        end
    end)
end

-- ── Public API ────────────────────────────────────────────────

--- Register a named dialog definition.
-- @param name      string
-- @param delegate  table   (see file header for all fields)
function ForgeDialog:Register(name, delegate)
    assert(type(name) == "string" and name ~= "",
        "ForgeDialog:Register - name must be a non-empty string")
    assert(type(delegate) == "table",
        "ForgeDialog:Register - delegate must be a table")
    _delegates[name] = delegate
end

--- Show a dialog. Queues if MAX_ACTIVE dialogs are already visible.
-- @param reference  string | table  Registered name or inline delegate table
-- @param data       any             Passed to all callbacks as the second arg
-- @return dialog    frame | nil
function ForgeDialog:Spawn(reference, data)
    local delegate
    if type(reference) == "string" then
        delegate = _delegates[reference]
        assert(delegate, "ForgeDialog:Spawn - no dialog registered as '" .. reference .. "'")
    else
        assert(type(reference) == "table",
            "ForgeDialog:Spawn - reference must be a name string or delegate table")
        delegate = reference
    end

    ensureHooks()

    -- Conditionals.
    if UnitIsDeadOrGhost("player") and not delegate.show_while_dead then
        if delegate.on_cancel then delegate.on_cancel(nil, data, "override") end
        return
    end

    -- Exclusive: dismiss all other exclusive dialogs.
    if delegate.is_exclusive then
        for i = #_active, 1, -1 do
            local dlg = _active[i]
            if dlg._delegate and dlg._delegate.is_exclusive then
                if dlg._delegate.on_cancel then
                    dlg._delegate.on_cancel(dlg, dlg._data, "override")
                end
                dlg:Hide()
            end
        end
    end

    -- If already showing this delegate, close it first.
    local existing = self:GetActive(reference)
    if existing then
        if not delegate.no_cancel_on_reuse and delegate.on_cancel then
            delegate.on_cancel(existing, existing._data, "override")
        end
        existing:Hide()
    end

    -- Queue if full.
    if #_active >= MAX_ACTIVE then
        _queue[#_queue + 1] = { delegate = reference, data = data }
        return nil
    end

    local dlg = buildDialog(delegate, data)
    dlg:Show()
    return dlg
end

--- Returns the live dialog frame for this delegate, or nil.
-- @param reference  string | table
function ForgeDialog:GetActive(reference)
    local delegate
    if type(reference) == "string" then
        delegate = _delegates[reference]
    else
        delegate = reference
    end
    if not delegate then return nil end
    for _, dlg in ipairs(_active) do
        if dlg._delegate == delegate then return dlg end
    end
end

--- Returns true if a dialog for this delegate is currently shown.
function ForgeDialog:IsActive(reference)
    return self:GetActive(reference) ~= nil
end

--- Programmatically close a dialog.
-- @param reference  string | table
function ForgeDialog:Dismiss(reference)
    local dlg = self:GetActive(reference)
    if dlg then dlg:Hide() end
end

--- Dismiss all active ForgeDialog dialogs.
function ForgeDialog:DismissAll()
    for i = #_active, 1, -1 do
        _active[i]:Hide()
    end
    _queue = {}
end
