local addon, ns = ...

ns.DeathNote = ForgeCore:NewAddon("DeathNote")
local DeathNote = ns.DeathNote

local L = ForgeLocale:Get("DeathNote")

function DeathNote:OnInitialize()
	-- initialize database
	self.db = ForgeDB:New("DeathNoteDB", self.OptionsDefaults)
	self.settings = self.db.profile
	self.settings.others_death_time = 0 -- Clean options -- TODO: remove this when implemented

	local options = ForgeOptions:Create("DeathNote", "Death Note", self.db.profile)
	options:Register(DeathNote)
	-- TODO Add table into Blizzard's default Interface options panel
	-- LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Death Note", L["Death Note"])


	local function ChatCommand(msg)
		if (msg == "reset") then
			ns.DataCapture:ResetData();
			DeathNote:UpdateLDB();
		else
			ns.UI:Show();
		end
	end
	self:RegisterChatCommand({"deathnote", "dn"}, ChatCommand)


	-- Register data broker object for clicking minimap icon
	-- self.ldb = ForgeBroker:Register("DeathNote", {
	-- 	icon = "Interface\\AddOns\\DeathNote\\Textures\\icon.tga",
	-- 	label = "|cFF8F8F8F" .. L["Death Note"] .. "|r",
	-- 	OnClick = function(self, button)
	-- 		if button == "LeftButton" then
	-- 			if IsShiftKeyDown() then
	-- 				DeathNote:CleanData(true)
	-- 				collectgarbage("collect")
	-- 				DeathNote:UpdateLDB()
	-- 			elseif IsControlKeyDown() then
	-- 				DeathNote:ResetData()
	-- 				DeathNote:UpdateLDB()
	-- 			else
	-- 				DeathNote:ShowUnit(UnitName("target"))
	-- 			end
	-- 		elseif button == "RightButton" then
	-- 			InterfaceOptionsFrame_OpenToCategory(L["Death Note"])
	-- 		end
	-- 	end,
	-- 	OnTooltipShow = function(tooltip)
	-- 		tooltip:AddLine(L["Death Note"])
	-- 		tooltip:AddLine(L["|cFFEDA55FClick|r to open Death Note. |cFFEDA55FRight-Click|r to show options. |cFFEDA55FShift-Click|r to optimize data. |cFFEDA55FCtrl-Click|r to reset data."], 0.2, 1, 0.2, 1)
	-- 	end,

	-- }, self.db.profile)

	-- Override default Blizzard death recap button
	OpenDeathRecapUI = function ()
		DeathNote:ShowUnit(UnitName("player"))
	end

	ns.DataCapture:Initialize()
	
	ns.Output:Initialize()
	
	self:UpdateLDB()

end

function DeathNote:OnEnable()
	-- self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("CHAT_MSG_SYSTEM", ns.DataCapture.CHAT_MSG_SYSTEM)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", ns.DataCapture.PLAYER_REGEN_ENABLED)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", ns.DataCapture)
	self:RegisterEvent("PLAYER_FLAGS_CHANGED", ns.DataCapture.PLAYER_FLAGS_CHANGED)
	self:RegisterEvent("PLAYER_LEAVING_WORLD", ns.DataCapture.PLAYER_LEAVING_WORLD)
	self:RegisterEvent("CHANNEL_UI_UPDATE", ns.DataCapture.CHANNEL_UI_UPDATE)
	self.db.RegisterCallback("OnProfileChanged", ns.DataCapture.OnProfileChanged)

	self:ScheduleRepeatingTimer("UpdateLDB", 5)

	if self.settings.debugging then
		if ns.UI then ns.UI:Show() end
	end
end

function DeathNote:OnDisable()
	self:UnregisterAllEvents()
	self.db.UnregisterAllCallbacks(self)
	self:CancelAllTimers()
end

-- Replaces AceConsole:Print so that the addon name can be localized
function DeathNote:Print(...)
	local str = "|cff33ff99" .. L["Death Note"] .. "|r: "
	local count = select("#", ...)
	for i = 1, count do
		str = str .. tostring(select(i, ...))
		if i < count then
			str = str .. " "
		end
	end
	DEFAULT_CHAT_FRAME:AddMessage(str)
end

function DeathNote:Debug(...)
	if self.settings.debugging then
		self:Print(...)
	end
end

function DeathNote:UpdateLDB()
	if not self.ldb then return end
	self.ldb.text = string.format(L["%i deaths"], #DeathNoteData.deaths)
end

------------------------------------------------------------------------------
-- Reports
------------------------------------------------------------------------------

function DeathNote:SendReport(channel, arg)
	local target
	if channel == "WHISPER" then
		target = UnitName("target")
		if not target then
			return
		end
	elseif channel == "CHANNEL" then
		target = arg
	end

	local func
	if self.settings.report.style == "COMBAT_LOG" then
		func = self.FormatReportCombatLog
	else
		func = self.FormatReportCompact
	end

	local msg = string.format(L["Death Note: Death report for %s at %s"], self.current_death.name, date("%X", self.current_death.timestamp))
	SendChatMessage(msg, channel, nil, target)

	self.report_line_count = 0
	for i = self.dropdown_line, 1, -1 do
		if self.report_line_count >= self.settings.report.max_lines then
			self:Print(string.format(L["Limiting report to %i lines"], self.settings.report.max_lines))
			break
		end

		local entry = self.logframe:GetLineUserdata(i)

		func(self, entry, channel, target)
	end
	self.report_line_count = nil
end
