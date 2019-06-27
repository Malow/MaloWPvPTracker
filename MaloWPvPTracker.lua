
-- Main
SlashCmdList["MPTCOMMAND"] = function(msg)
	local arguments = MaloWUtils_SplitStringOnSpace(msg)
	local command = arguments[1]
	if command == "toggle" then
		mpt_toggle()
	elseif command == "reset" then
		mpt_reset()
	else
		mpt_Print("Unrecognized command: " .. command)
	end
end 
SLASH_MPTCOMMAND1 = "/mpt";

-- Prints message in chatbox
function mpt_Print(msg)
	MaloWUtils_Print("MPT: " .. msg)
end



-- WPVP tracker
local MAX_TARGET_COUNT = 20
local trackedTargets = {}
local modifySecureQueue = {}
local HEIGHT_PER_BAR = 25
local TRACKED_BUFFS = { -- SpellIDs, In order of importance
	642, -- Divine Shield
	45438, -- Ice Block
	47585, -- Dispersion
	19263, -- Deterrence
	29166, -- Innervate
	1044, -- Hand of Freedom
}

function mpt_loaded()
	MaloWPvPTrackerFrame:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",tile = true, tileSize = 12, edgeSize = 12,insets = setmetatable({},{__index = function() return 2 end}) 
		});
	MaloWPvPTrackerFrame:SetBackdropColor(0,0,0,0.7)
	MaloWPvPTrackerFrame:SetBackdropBorderColor(0.8,0.7,0,0.7)
	MaloWPvPTrackerFrame:SetFrameStrata("BACKGROUND")
	MaloWPvPTrackerFrame:SetHeight(HEIGHT_PER_BAR)
		
	MaloWPvPTrackerFrame:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			self:SetMovable(true)
			self:StartMoving()
		end
	end)

	MaloWPvPTrackerFrame:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then
			self:StopMovingOrSizing()
			self:SetMovable(false)

			local left, bottom = self:GetLeft(), self:GetBottom()

			--local x = math.round((left + (self:GetWidth() / 2)) - (UIParent:GetWidth() / 2))
			--local y = math.round((bottom + (self:GetHeight() / 2)) - (UIParent:GetHeight() / 2))

			local x = math.round(left)
			local y = math.round(-UIParent:GetHeight() + bottom + self:GetHeight())

			self:ClearAllPoints()
			self:SetPoint("TopLeft", UIParent, "TopLeft", x, y)
			mpt_sv.posx = x
			mpt_sv.posy = y
		end
	end)
	
	MaloWPvPTrackerFrame.resetButton = mpt_createButton(MaloWPvPTrackerFrame, true)
	MaloWPvPTrackerFrame.resetButton:SetSize(50, 20)
	MaloWPvPTrackerFrame.resetButton:SetPoint("TOPRIGHT", -1, 18)
	MaloWPvPTrackerFrame.resetButton:SetText("Reset")
	MaloWPvPTrackerFrame.resetButton:SetScript("OnClick", function(self) mpt_reset() end)
		
	MaloWPvPTrackerFrame.nameLabel = CreateFrame("frame", nil, MaloWPvPTrackerFrame);
	MaloWPvPTrackerFrame.nameLabel:SetSize(100, 20)
	MaloWPvPTrackerFrame.nameLabel.text = MaloWPvPTrackerFrame.nameLabel.text or MaloWPvPTrackerFrame.nameLabel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	MaloWPvPTrackerFrame.nameLabel.text:SetAllPoints(true)
	MaloWPvPTrackerFrame.nameLabel:SetPoint("TOPLEFT", MaloWPvPTrackerFrame, "TOPLEFT", 5, 14)
	MaloWPvPTrackerFrame.nameLabel.text:SetText("MaloWPvPTracker")
	MaloWPvPTrackerFrame.nameLabel.text:SetJustifyH("LEFT")
	MaloWPvPTrackerFrame.nameLabel.text:SetTextColor(1, 1, 1, 1)
	
	MaloWPvPTrackerFrame.entries = {}
	for i = 1, MAX_TARGET_COUNT do
		MaloWPvPTrackerFrame.entries[i] = mpt_createEntryFrame(MaloWPvPTrackerFrame)
		MaloWPvPTrackerFrame.entries[i]:SetPoint("TOPLEFT", 3, -HEIGHT_PER_BAR * i + HEIGHT_PER_BAR - 3)
		MaloWPvPTrackerFrame.entries[i].button:SetPoint("TOPLEFT", 3, -HEIGHT_PER_BAR * i + HEIGHT_PER_BAR - 3)
	end
end


function mpt_update()
	mpt_findAndAddTargets()
		
	mpt_handleSecureQueue()
	
	mpt_resizeFrameHeight()
	
	mpt_setBarColors()
	
	mpt_setTargetedTexts()
	
	mpt_setBuffIcon()
end

function mpt_setBuffIcon()
	for i = 1, MAX_TARGET_COUNT do
		if MaloWPvPTrackerFrame.entries[i].target and MaloWPvPTrackerFrame.entries[i].target.buff then 
			MaloWPvPTrackerFrame.entries[i].buffIcon:Show()
			MaloWPvPTrackerFrame.entries[i].buffIcon.texture:SetTexture(MaloWPvPTrackerFrame.entries[i].target.buff.icon)
			local timeRemaining = MaloWPvPTrackerFrame.entries[i].target.buff.expirationTime - GetTime()
			if timeRemaining < 0 then 
				MaloWPvPTrackerFrame.entries[i].target.buff = nil
				return
			end
			local text = string.sub(tostring(timeRemaining), 1, 3)
			local dotIndex = string.find(text, "%.")
			if dotIndex then 
				if dotIndex == 3 then 
					text = string.sub(tostring(timeRemaining), 1, 2) .. "s"
				elseif dotIndex > 3 then 
					text = ">1m"
				elseif dotIndex == 2 then 
					-- text = text .. "s" -- omit "s" if we're in the decimal range
				else
					text = ""
				end
			else
				text = ""
			end
			MaloWPvPTrackerFrame.entries[i].buffIcon.text:SetText(text)
		else
			MaloWPvPTrackerFrame.entries[i].buffIcon:Hide()
		end
	end
end

function mpt_setBarColors()
	local playerName = UnitName("target")
	for i = 1, MAX_TARGET_COUNT do
		if MaloWPvPTrackerFrame.entries[i].text:GetText() == playerName then 
			if MaloWPvPTrackerFrame.entries[i].target and MaloWPvPTrackerFrame.entries[i].target.isDead then
				MaloWPvPTrackerFrame.entries[i].bar:SetStatusBarColor(0.8, 0.3, 0.2)
			else
				MaloWPvPTrackerFrame.entries[i].bar:SetStatusBarColor(0.7, 1.0, 0.7)
			end
		elseif MaloWPvPTrackerFrame.entries[i].target and MaloWPvPTrackerFrame.entries[i].target.isDead then
			MaloWPvPTrackerFrame.entries[i].bar:SetStatusBarColor(0.4, 0.15, 0.1)
		elseif MaloWPvPTrackerFrame.entries[i].hasSecuredSet then 
			MaloWPvPTrackerFrame.entries[i].bar:SetStatusBarColor(0.3, 0.7, 0.3)
		else
			MaloWPvPTrackerFrame.entries[i].bar:SetStatusBarColor(0.2, 0.4, 0.2)
		end
	end
end

function mpt_setTargetedTexts()
	local targets = {}
	if UnitInRaid("player") then 
		for i = 1, 40 do
			if UnitExists("raid" .. i) then 
				local playerName = UnitName("raid" .. i .. "target")
				if playerName then
					if targets[playerName] then 
						targets[playerName] = 1 + 1
					else
						targets[playerName] = 1
					end
				end
			end
		end
	elseif UnitInParty("player") then
		for i = 1, 4 do
			if UnitExists("party" .. i) then 
				local playerName = UnitName("party" .. i .. "target")
				if playerName then
					if targets[playerName] then 
						targets[playerName] = 1 + 1
					else
						targets[playerName] = 1
					end
				end
			end
		end
	end

	for i = 1, MAX_TARGET_COUNT do
		local playerName = MaloWPvPTrackerFrame.entries[i].text:GetText()
		if playerName == "" then 
			MaloWPvPTrackerFrame.entries[i].targetedText:SetText("")
		else
			MaloWPvPTrackerFrame.entries[i].targetedText:SetText(targets[playerName])
		end
	end
end

function mpt_handleSecureQueue()
	while MaloWUtils_TableLength(modifySecureQueue) > 0 and not InCombatLockdown() do 
		local index = table.remove(modifySecureQueue, 1)
		MaloWPvPTrackerFrame.entries[index].button:SetAttribute("macrotext1", "/targetexact " .. MaloWPvPTrackerFrame.entries[index].target.name)
		MaloWPvPTrackerFrame.entries[index].button:SetAttribute("macrotext2", "/targetexact " .. MaloWPvPTrackerFrame.entries[index].target.name .. "\n/focus\n/targetlasttarget")
		MaloWPvPTrackerFrame.entries[index].button:Show()
		MaloWPvPTrackerFrame.entries[index].hasSecuredSet = true
	end
end

function mpt_resizeFrameHeight()
	local tableSize = MaloWUtils_TableLength(trackedTargets)
	if tableSize == 0 then 
		MaloWPvPTrackerFrame:SetHeight(25)
	elseif tableSize > MAX_TARGET_COUNT then
		MaloWPvPTrackerFrame:SetHeight(MAX_TARGET_COUNT * HEIGHT_PER_BAR + 6)
	else 
		MaloWPvPTrackerFrame:SetHeight(tableSize * HEIGHT_PER_BAR + 6)
	end
end

function mpt_findAndAddTargets()
	mpt_checkWithTargets("mouseover")
	mpt_checkWithTargets("target")
	mpt_checkWithTargets("focus")
	if UnitInRaid("player") then 
		for i = 1, 40 do
			if UnitExists("raid" .. i) then 
				mpt_checkWithTargets("raid" .. i)
			end
		end
	elseif UnitInParty("player") then
		for i = 1, 4 do
			if UnitExists("party" .. i) then 
				mpt_checkWithTargets("party" .. i)
			end
		end
	end
end

function mpt_checkWithTargets(unit)
	mpt_checkAndTrackPlayer(unit)
	mpt_checkAndTrackPlayer(unit .. "target")
	mpt_checkAndTrackPlayer(unit .. "targettarget")
	mpt_checkAndTrackPlayer(unit .. "targettargettarget")
end

function mpt_reset()
	if InCombatLockdown() then 
		mpt_Print("Please leave combat before resetting.")
		return
	end
	trackedTargets = {}
	modifySecureQueue = {}
	for i = 1, MAX_TARGET_COUNT do
		MaloWPvPTrackerFrame.entries[i].target = nil
		MaloWPvPTrackerFrame.entries[i].text:SetText("")
		MaloWPvPTrackerFrame.entries[i].button:Hide()
		MaloWPvPTrackerFrame.entries[i]:Hide()
	end
	MaloWPvPTrackerFrame:SetHeight(25)
end

function mpt_checkAndTrackPlayer(unit)
	if UnitIsPlayer(unit) and UnitIsEnemy("player", unit) then
		local playerName = UnitName(unit)
		if playerName and playerName ~= "Unknown" then 
			local player = {}
			player.name = playerName
			player.health = UnitHealth(unit)
			player.maxhealth = UnitHealthMax(unit)
			player.level = UnitLevel(unit)
			player.inrange = UnitInRange(unit) == 1
			player.buff = mpt_getBuff(unit)
			player.isDead = UnitIsDeadOrGhost(unit)
			trackedTargets[playerName] = player
			mpt_updateOrCreateListEntry(player)
		end
	end
end

function mpt_getBuff(unit)
	local highestPrio = nil
	local highestPrioIcon = nil
	local highestPrioExpirationTime = nil
	for i = 1, 40 do 
		local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = UnitBuff(unit, i); 
		if name then
			local prio = mpt_getBuffPriorityForSpellId(spellId)
			if prio then 
				if highestPrio then
					if prio < highestPrio then 
						highestPrio = prio
						highestPrioIcon = icon
						highestPrioExpirationTime = expirationTime
					end
				else
					highestPrio = prio
					highestPrioIcon = icon
					highestPrioExpirationTime = expirationTime
				end
			end
		end
	end
	if highestPrio == nil then 
		return nil
	end
	
	local buff = {}
	buff.icon = highestPrioIcon
	buff.expirationTime = highestPrioExpirationTime
	return buff
end

function mpt_getBuffPriorityForSpellId(spellId)
	for i = 1, #TRACKED_BUFFS do 
		if TRACKED_BUFFS[i] == spellId then
			return i
		end
	end
	return nil
end

function mpt_updateOrCreateListEntry(player)
	for i = 1, MAX_TARGET_COUNT do
		if MaloWPvPTrackerFrame.entries[i].text:GetText() == player.name then 
			if player.isDead then 
				MaloWPvPTrackerFrame.entries[i].bar:SetValue(1.0)
			else
				MaloWPvPTrackerFrame.entries[i].bar:SetValue(player.health / player.maxhealth)
			end
			MaloWPvPTrackerFrame.entries[i].target = player
			return
		end
	end
	local tableSize = MaloWUtils_TableLength(trackedTargets)
	if tableSize < MAX_TARGET_COUNT + 1 then
		MaloWPvPTrackerFrame.entries[tableSize].target = player
		MaloWPvPTrackerFrame:SetHeight(tableSize * HEIGHT_PER_BAR + 6)
		MaloWPvPTrackerFrame.entries[tableSize]:Show()
		MaloWPvPTrackerFrame.entries[tableSize].text:SetText(player.name)
		PlaySound("RaidWarning")
		if not InCombatLockdown() then
			MaloWPvPTrackerFrame.entries[tableSize].button:SetAttribute("macrotext1", "/targetexact " .. player.name)
			MaloWPvPTrackerFrame.entries[tableSize].button:SetAttribute("macrotext2", "/targetexact " .. player.name .. "\n/focus\n/targetlasttarget")
			MaloWPvPTrackerFrame.entries[tableSize].button:Show()
			MaloWPvPTrackerFrame.entries[tableSize].hasSecuredSet = true
		else
			table.insert(modifySecureQueue, tableSize)
			MaloWPvPTrackerFrame.entries[tableSize].hasSecuredSet = false
		end
	end
end

function mpt_toggle()
	if MaloWPvPTrackerFrame:IsShown() then 
		MaloWPvPTrackerFrame:Hide() 
	else 
		MaloWPvPTrackerFrame:Show() 
	end
	-- mpt_printTrackedTargets()
end

function mpt_printTrackedTargets()
	mpt_Print("")
	for _, player in pairs(trackedTargets) do
		mpt_Print(player.name .. " - " .. tostring((player.health / player.maxhealth) * 100) .. "% hp - lvl " .. player.level .. " - inrange: " .. tostring(player.inrange))
	end
	mpt_Print("")
end


function mpt_createButton(parent, textured)
	local button = CreateFrame("BUTTON", nil, parent, "SecureActionButtonTemplate");

	button:RegisterForClicks("AnyUp")
	button:SetNormalFontObject("GameFontNormalSmall")
	if textured then 
		button:SetNormalTexture("Interface/Buttons/UI-Panel-Button-Up")
	else
		button:SetNormalTexture("")
	end
	button:SetHighlightTexture("Interface/Buttons/UI-Panel-Button-Highlight")
	button:SetPushedTexture("Interface/Buttons/UI-Panel-Button-Down")
	
	button:SetDisabledFontObject(GameFontDisable)
	button:SetHighlightFontObject(GameFontHighlight)
	button:SetNormalFontObject(GameFontNormal)
	
	local ntex = button:CreateTexture()
	if textured then 
		ntex:SetTexture("Interface/Buttons/UI-Panel-Button-Up")
	else
		ntex:SetTexture("")
	end
	ntex:SetTexCoord(0, 0.625, 0, 0.6875)
	ntex:SetAllPoints()	
	button:SetNormalTexture(ntex)
	
	local htex = button:CreateTexture()
	htex:SetTexture("Interface/Buttons/UI-Panel-Button-Highlight")
	htex:SetTexCoord(0, 0.625, 0, 0.6875)
	htex:SetAllPoints()
	button:SetHighlightTexture(htex)
	
	local ptex = button:CreateTexture()
	if textured then 
		ptex:SetTexture("Interface/Buttons/UI-Panel-Button-Down")
	else
		ptex:SetTexture("")
	end
	ptex:SetTexCoord(0, 0.625, 0, 0.6875)
	ptex:SetAllPoints()
	button:SetPushedTexture(ptex)
	
	button:SetFrameStrata("MEDIUM")
	return button
end

function mpt_createEntryFrame(parent)
	-- Main frame
	local entryFrame = CreateFrame("frame", nil, parent);
	entryFrame:SetSize(144, HEIGHT_PER_BAR)
	entryFrame:Hide()
	entryFrame:SetFrameStrata("MEDIUM")
	-- Name text
	entryFrame.text = entryFrame.text or entryFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	entryFrame.text:SetAllPoints(true)
	entryFrame.text:SetJustifyH("LEFT")
	entryFrame.text:SetPoint("TOPLEFT", entryFrame, "TOPLEFT", 3, 0)
	entryFrame.text:SetTextColor(1, 1, 1, 1)
	entryFrame.text:SetText("")
	-- Targeted Text
	entryFrame.targetedText = entryFrame.targetedText or entryFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	entryFrame.targetedText:SetAllPoints(true)
	entryFrame.targetedText:SetJustifyH("RIGHT")
	entryFrame.targetedText:SetPoint("TOPRIGHT", entryFrame, "TOPRIGHT", -3, 0)
	entryFrame.targetedText:SetTextColor(1, 1, 1, 1)
	entryFrame.targetedText:SetText("")
	-- Button for targeting/focusing
	local button = mpt_createButton(parent, false)
	button:SetSize(144, HEIGHT_PER_BAR)
	button:SetText("")
	button:Hide()
	button:SetAttribute("type1", "macro")
	button:SetAttribute("type2", "macro")
	button:SetAttribute("macrotext1", "")
	button:SetAttribute("macrotext2", "")
	-- Status bar for health with background
	local bar = CreateFrame("StatusBar", nil, entryFrame);
	bar:SetFrameStrata("LOW")
	bar:SetPoint("CENTER", entryFrame, "CENTER", 0, 0)
	bar:SetSize(144, HEIGHT_PER_BAR)
	bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
	bar:GetStatusBarTexture():SetHorizTile(false)
	bar:GetStatusBarTexture():SetVertTile(false)
	bar:SetStatusBarColor(0.3, 0.7, 0.3)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
	bar.bg:SetAllPoints(true)
	bar.bg:SetVertexColor(0.2, 0.2, 0)
	-- Buff icon with text
	local buffIcon = CreateFrame("frame", nil, entryFrame)
	buffIcon:SetPoint("LEFT", entryFrame, "LEFT", -HEIGHT_PER_BAR, 0)
	buffIcon:SetSize(HEIGHT_PER_BAR, HEIGHT_PER_BAR)
	buffIcon:SetFrameStrata("BACKGROUND")
	buffIcon:Hide()
	buffIcon.texture = buffIcon:CreateTexture(nil, "BACKGROUND ") -- Space here?
	buffIcon.texture:SetAllPoints(true)
	buffIcon.text = buffIcon.text or buffIcon:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	local fontName, fontHeight, fontFlags = buffIcon.text:GetFont()
	buffIcon.text:SetFont(fontName, fontHeight, "OUTLINE")
	buffIcon.text:SetAllPoints(true)
	buffIcon.text:SetJustifyH("CENTER")
	buffIcon.text:SetPoint("CENTER", buffIcon, "CENTER", 0, 0)
	buffIcon.text:SetTextColor(1, 1, 1, 1)
	buffIcon.text:SetText("")
	
	entryFrame.button = button
	entryFrame.bar = bar
	entryFrame.buffIcon = buffIcon
	return entryFrame
end


math.round = function(num, decimals)
    local mult = 10^(decimals or 0)

    return math.floor(num * mult + 0.5) / mult
end


-- Events
function mpt_onEvent(self, event, arg1, ...)
	if event == "ADDON_LOADED" and arg1 == "MaloWPvPTracker" then
		if mpt_sv == nil then
			mpt_sv = {}
		end	
		
		if mpt_sv.posx and mpt_sv.posy then 
			MaloWPvPTrackerFrame:ClearAllPoints()
			MaloWPvPTrackerFrame:SetPoint("TopLeft", UIParent, "TopLeft", mpt_sv.posx, mpt_sv.posy)
		end
	elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then 
		local newZone = GetZoneText()
		if newZone == "Stormwind City" then 
			mpt_reset()
			MaloWPvPTrackerFrame:Hide()
		else
			MaloWPvPTrackerFrame:Show()
		end
	end
end






