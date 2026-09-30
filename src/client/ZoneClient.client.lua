--[[
	ZoneClient
	Debug/feedback UI for the Zone system.

	Listens for ZoneEntryFlash from the server and shows a brief on-screen
	banner like:

		  ENTRY DENIED
		  Chaotic players cannot enter Stormhaven

	The flash is for testing/feedback ONLY. Actual entry prevention is not
	yet implemented — the player still crosses the boundary; we just tell them.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")

local ZoneConfig      = require(ReplicatedStorage:WaitForChild("ZoneConfig"))
local VolumeSettings  = require(ReplicatedStorage:WaitForChild("VolumeSettings"))
local MusicPlayback   = require(
	ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("MusicPlayback")
)
local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local ZoneEntryFlash  = GameEvents:WaitForChild("ZoneEntryFlash")
local ZoneEntryNotify = GameEvents:WaitForChild("ZoneEntryNotify")
local ZoneMusicSync   = GameEvents:WaitForChild("ZoneMusicSync")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Build the ScreenGui once and reuse it.
local sg = Instance.new("ScreenGui")
sg.Name           = "ZoneEntryFlashGui"
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = true
sg.DisplayOrder   = 220
sg.Enabled        = true
sg.Parent         = playerGui

local panel = Instance.new("Frame")
panel.Name                   = "FlashPanel"
panel.AnchorPoint            = Vector2.new(0.5, 0)
panel.Position               = UDim2.new(0.5, 0, 0, 80)
panel.Size                   = UDim2.fromOffset(420, 64)
panel.BackgroundColor3       = Color3.fromRGB(20, 10, 10)
panel.BackgroundTransparency = 1
panel.BorderSizePixel        = 0
panel.Visible                = false
panel.Parent                 = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", panel)
stroke.Thickness    = 2
stroke.Color        = Color3.fromRGB(255, 90, 90)
stroke.Transparency = 1

local title = Instance.new("TextLabel")
title.Name                   = "Title"
title.BackgroundTransparency = 1
title.Position               = UDim2.fromOffset(0, 6)
title.Size                   = UDim2.new(1, 0, 0, 22)
title.Font                   = Enum.Font.GothamBold
title.TextSize               = 18
title.TextColor3             = Color3.fromRGB(255, 90, 90)
title.TextStrokeTransparency = 0.5
title.TextTransparency       = 1
title.Text                   = "ENTRY DENIED"
title.Parent                 = panel

local body = Instance.new("TextLabel")
body.Name                   = "Body"
body.BackgroundTransparency = 1
body.Position               = UDim2.fromOffset(0, 30)
body.Size                   = UDim2.new(1, 0, 0, 28)
body.Font                   = Enum.Font.GothamMedium
body.TextSize               = 14
body.TextColor3             = Color3.fromRGB(240, 220, 220)
body.TextStrokeTransparency = 0.5
body.TextTransparency       = 1
body.Text                   = ""
body.TextWrapped            = true
body.Parent                 = panel

local activeToken = 0

local function show(zoneName, zoneAlignment, playerAlignment)
	activeToken = activeToken + 1
	local myToken = activeToken

	local accent = ZoneConfig.ALIGNMENT_COLORS[zoneAlignment] or Color3.fromRGB(255, 90, 90)
	stroke.Color   = accent
	title.TextColor3 = accent
	title.Text       = "ENTRY DENIED"
	body.Text = string.format("%s players cannot enter %s",
		tostring(playerAlignment or "?"), tostring(zoneName or "this zone"))

	panel.Visible = true
	local inTween = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(panel,  inTween, { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(stroke, inTween, { Transparency = 0 }):Play()
	TweenService:Create(title,  inTween, { TextTransparency = 0 }):Play()
	TweenService:Create(body,   inTween, { TextTransparency = 0 }):Play()

	task.delay(ZoneConfig.FLASH_DURATION_SEC, function()
		if myToken ~= activeToken then return end
		local outTween = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(panel,  outTween, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, outTween, { Transparency = 1 }):Play()
		TweenService:Create(title,  outTween, { TextTransparency = 1 }):Play()
		TweenService:Create(body,   outTween, { TextTransparency = 1 }):Play()
		task.delay(0.4, function()
			if myToken == activeToken then
				panel.Visible = false
			end
		end)
	end)
end

ZoneEntryFlash.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	show(payload.zoneName, payload.zoneAlignment, payload.playerAlignment)
end)

----------------------------------------------------------------------
-- Zone entry banner (centered, informational — all players, all zones)
----------------------------------------------------------------------

local entrySg = Instance.new("ScreenGui")
entrySg.Name           = "ZoneEntryBannerGui"
entrySg.ResetOnSpawn   = false
entrySg.IgnoreGuiInset = true
entrySg.DisplayOrder   = 215
entrySg.Enabled        = true
entrySg.Parent         = playerGui

local entryPanel = Instance.new("Frame")
entryPanel.Name                   = "EntryBanner"
entryPanel.AnchorPoint            = Vector2.new(0.5, 0.5)
entryPanel.Position               = UDim2.new(0.5, 0, 0.4, 0)
entryPanel.Size                   = UDim2.fromOffset(480, 72)
entryPanel.BackgroundTransparency = 1
entryPanel.BorderSizePixel        = 0
entryPanel.Visible                = false
entryPanel.Parent                 = entrySg

local entryZoneName = Instance.new("TextLabel")
entryZoneName.Name                   = "ZoneName"
entryZoneName.BackgroundTransparency = 1
entryZoneName.Position               = UDim2.fromOffset(0, 0)
entryZoneName.Size                   = UDim2.new(1, 0, 0, 40)
entryZoneName.Font                   = Enum.Font.GothamBold
entryZoneName.TextSize               = 30
entryZoneName.TextColor3             = Color3.fromRGB(240, 235, 225)
entryZoneName.TextStrokeTransparency = 0.4
entryZoneName.TextTransparency       = 1
entryZoneName.Text                   = ""
entryZoneName.TextXAlignment         = Enum.TextXAlignment.Center
entryZoneName.Parent                 = entryPanel

local entryAlignLabel = Instance.new("TextLabel")
entryAlignLabel.Name                   = "AlignLabel"
entryAlignLabel.BackgroundTransparency = 1
entryAlignLabel.Position               = UDim2.fromOffset(0, 40)
entryAlignLabel.Size                   = UDim2.new(1, 0, 0, 22)
entryAlignLabel.Font                   = Enum.Font.GothamMedium
entryAlignLabel.TextSize               = 15
entryAlignLabel.TextColor3             = Color3.fromRGB(200, 190, 170)
entryAlignLabel.TextStrokeTransparency = 0.5
entryAlignLabel.TextTransparency       = 1
entryAlignLabel.Text                   = ""
entryAlignLabel.TextXAlignment         = Enum.TextXAlignment.Center
entryAlignLabel.Parent                 = entryPanel

-- First entry into a zone (the world map, SSS/MinimapService): a header line above the name.
local entryHeader = Instance.new("TextLabel")
entryHeader.Name                   = "DiscoveredHeader"
entryHeader.BackgroundTransparency = 1
entryHeader.Position               = UDim2.fromOffset(0, -26)
entryHeader.Size                   = UDim2.new(1, 0, 0, 22)
entryHeader.Font                   = Enum.Font.GothamBold
entryHeader.TextSize               = 16
entryHeader.TextColor3             = Color3.fromRGB(226, 206, 150)
entryHeader.TextStrokeTransparency = 0.5
entryHeader.TextTransparency       = 1
entryHeader.Text                   = "REGION DISCOVERED"
entryHeader.TextXAlignment         = Enum.TextXAlignment.Center
entryHeader.Parent                 = entryPanel

local entryToken = 0

local function showEntryBanner(zoneName, zoneAlignment, discovered)
	entryToken = entryToken + 1
	local myToken = entryToken

	local accentColor = ZoneConfig.ALIGNMENT_COLORS[zoneAlignment] or Color3.fromRGB(200, 190, 170)
	entryZoneName.Text      = tostring(zoneName or ""):upper()
	-- Discovery shows the alignment on its own line ("WILDERNESS"); plain entry keeps "... ZONE".
	entryAlignLabel.Text    = ZoneConfig.DisplayAlignment(zoneAlignment):upper() .. (discovered and "" or " ZONE")
	entryAlignLabel.TextColor3 = accentColor

	entryPanel.Visible = true
	local inTween = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(entryZoneName,   inTween, { TextTransparency = 0 }):Play()
	TweenService:Create(entryAlignLabel, inTween, { TextTransparency = 0 }):Play()
	entryHeader.TextTransparency = 1
	if discovered then TweenService:Create(entryHeader, inTween, { TextTransparency = 0 }):Play() end

	task.delay(discovered and 4 or 2.5, function()
		if myToken ~= entryToken then return end
		local outTween = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(entryZoneName,   outTween, { TextTransparency = 1 }):Play()
		TweenService:Create(entryAlignLabel, outTween, { TextTransparency = 1 }):Play()
		TweenService:Create(entryHeader,     outTween, { TextTransparency = 1 }):Play()
		task.delay(0.45, function()
			if myToken == entryToken then
				entryPanel.Visible = false
			end
		end)
	end)
end

ZoneEntryNotify.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	showEntryBanner(payload.zoneName, payload.zoneAlignment, payload.discovered == true)
end)

----------------------------------------------------------------------
-- Zone soundtrack: looped SoundService track that crossfades when the
-- player's active music zone changes (set on ZoneService via SetZoneMusic).
-- Default is no music — silence until a zone with a musicId is entered.
----------------------------------------------------------------------

local zoneMusic = Instance.new("Sound")
zoneMusic.Name    = "ZoneMusic"
zoneMusic.Looped  = true
zoneMusic.Volume  = 0
zoneMusic.SoundId = ""
zoneMusic.Parent  = SoundService

local currentMusicId = ""
local musicFadeToken = 0

-- ZoneMusic lives outside the SoundService.Main tree (it needs to keep
-- playing independent of gameplay SFX groups), so it can't inherit a
-- Master multiplier via SoundGroup nesting the way Movement/Effects do.
-- Bake VolumeSettings.master into the target volume by hand instead;
-- SettingsClient's Master slider re-applies this live via the same formula.
--
-- The current track's VolumeScale (MusicPlayback) rides on the Sound itself as
-- an attribute rather than in a local here, because SettingsClient writes this
-- same Volume directly when a slider moves -- it reads the attribute for the
-- same reason. One source of truth, on the instance both sides already touch.
local function targetMusicVolume()
	local scale = tonumber(zoneMusic:GetAttribute("TrackVolumeScale")) or 1
	return (VolumeSettings.master or 1) * VolumeSettings.music * scale * (VolumeSettings.OUTPUT_GAIN or 1)
end

-- Seeking needs the asset loaded: set TimePosition on an unloaded Sound and it
-- snaps back to 0. Applied again on Loaded for that reason, and again on every
-- loop -- Looped restarts at 0, not at the offset, so without DidLoop a track
-- would skip its intro once and then play it on every repeat.
local function applyTrackStart()
	local startTime = MusicPlayback.Get(currentMusicId).StartTime or 0
	if startTime <= 0 then return end
	if zoneMusic.TimeLength > 0 and startTime >= zoneMusic.TimeLength then return end
	zoneMusic.TimePosition = startTime
end

zoneMusic.DidLoop:Connect(applyTrackStart)

local function setZoneMusic(musicId)
	musicId = type(musicId) == "string" and musicId or ""
	if musicId == currentMusicId then return end
	currentMusicId = musicId
	musicFadeToken += 1
	local myToken = musicFadeToken

	local fadeOut = TweenService:Create(zoneMusic,
		TweenInfo.new(ZoneConfig.ZONE_MUSIC_FADE_SEC * (musicId == "" and 1 or 0.5), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Volume = 0 })

	if musicId == "" then
		if not zoneMusic.IsPlaying then return end
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if myToken == musicFadeToken then zoneMusic:Stop() end
		end)
		return
	end

	local function swapAndFadeIn()
		if myToken ~= musicFadeToken then return end
		zoneMusic.SoundId = musicId
		zoneMusic:SetAttribute("TrackVolumeScale", MusicPlayback.Get(musicId).VolumeScale)
		zoneMusic.Volume  = 0
		zoneMusic:Play()
		applyTrackStart()
		if not zoneMusic.IsLoaded then
			-- Still streaming: the seek above was a no-op, so redo it once the
			-- asset arrives (guarded, in case the track changed while loading).
			zoneMusic.Loaded:Once(function()
				if myToken == musicFadeToken and zoneMusic.SoundId == musicId then
					applyTrackStart()
				end
			end)
		end
		TweenService:Create(zoneMusic,
			TweenInfo.new(ZoneConfig.ZONE_MUSIC_FADE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Volume = targetMusicVolume() }):Play()
	end

	if zoneMusic.IsPlaying then
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if myToken == musicFadeToken then swapAndFadeIn() end
		end)
	else
		swapAndFadeIn()
	end
end

ZoneMusicSync.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	setZoneMusic(payload.musicId)
end)
