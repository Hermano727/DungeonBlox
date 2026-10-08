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
-- Zone entry banner (centred, all players, all zones). Rebuilt 2026-10-02 after a
-- "mission title" reference: a long gold line across the screen with the region name under it.
--
--                    (gold tree glowing behind)
--                        Region Discovered            small, gold, above the line
--   *---------------------------<>---------------------------*   opens outward, sparkles ride its ends
--                           OAKHAVEN                   the biggest thing on screen
--                            Lawful                    under the name, in the alignment's colour
--
-- First visits (SSS/MinimapService `discovered`) get the full banner with the tree; every later
-- crossing gets a smaller one (shorter line, smaller name, no tree or header). Every size is a
-- share of the screen, so it looks the same at any resolution; text is TextScaled.
----------------------------------------------------------------------

local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local HudArt = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("HudArt"))

local GOLD = Color3.fromRGB(240, 206, 128)
local GOLD_BRIGHT = Color3.fromRGB(255, 240, 196)
local NAME_COLOR = Color3.fromRGB(250, 246, 236)
local INK = Color3.fromRGB(16, 10, 6)

local LAYOUTS = {
	discovered = {
		lineY = 0.40, lineW = 0.8, hold = 4.2, tree = true, header = true,
		nameH = 0.17, nameW = 0.72, alignH = 0.036,
	},
	entry = {
		lineY = 0.3, lineW = 0.42, hold = 2.6, tree = false, header = false,
		nameH = 0.075, nameW = 0.45, alignH = 0.026,
	},
}

local entrySg = Instance.new("ScreenGui")
entrySg.Name           = "ZoneEntryBannerGui"
entrySg.ResetOnSpawn   = false
entrySg.IgnoreGuiInset = true
entrySg.DisplayOrder   = 215
entrySg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
entrySg.Enabled        = true
entrySg.Parent         = playerGui

local entryPanel = Instance.new("Frame")
entryPanel.Name                   = "EntryBanner"
entryPanel.Size                   = UDim2.fromScale(1, 1)
entryPanel.BackgroundTransparency = 1
entryPanel.Visible                = false
entryPanel.Parent                 = entrySg

local function new(className, props)
	local item = Instance.new(className)
	for key, value in pairs(props) do item[key] = value end
	return item
end

-- The tree, standing on the line, tinted gold, with a soft halo behind it.
local treeHolder = new("Frame", {
	Name = "Tree", AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, ZIndex = 0, Parent = entryPanel,
})
new("UIAspectRatioConstraint", { AspectRatio = HudArt.ZONE_TREE_ASPECT or 1.5, DominantAxis = Enum.DominantAxis.Height, Parent = treeHolder })
local treeScale = new("UIScale", { Parent = treeHolder })
local halo = new("ImageLabel", {
	Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(1.9, 2.1),
	BackgroundTransparency = 1, Image = HudArt.GLOW_SOFT, ImageColor3 = GOLD, ImageTransparency = 1, ZIndex = 0,
	Parent = treeHolder,
})
local tree = new("ImageLabel", {
	Name = "Silhouette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
	Image = HudArt.ZONE_TREE or "", ImageColor3 = GOLD, ImageTransparency = 1, ZIndex = 1, Parent = treeHolder,
})

local function textRow(name, font, color, maxSize, gradient)
	local label = new("TextLabel", {
		Name = name, AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, FontFace = font,
		TextScaled = true, TextColor3 = color, TextStrokeColor3 = INK, TextStrokeTransparency = 0.35,
		TextTransparency = 1, ZIndex = 3, Parent = entryPanel,
	})
	new("UITextSizeConstraint", { MaxTextSize = maxSize, Parent = label })
	if gradient then
		-- A little brighter at the top, like the reference's gilded lettering.
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(GOLD_BRIGHT, GOLD), Parent = label })
	end
	return label
end
local entryHeader     = textRow("DiscoveredHeader", UIFonts.SerifBold, Color3.new(1, 1, 1), 40, true)
entryHeader.AnchorPoint = Vector2.new(0.5, 1)
entryHeader.Text      = "Region Discovered"
local entryZoneName   = textRow("ZoneName", UIFonts.SerifBold, NAME_COLOR, 240, false)
local entryAlignLabel = textRow("AlignLabel", UIFonts.SerifBold, GOLD, 36, false)

-- The line: a bright core and a soft glow, both fading toward the ends, opening from the centre.
local line = new("Frame", {
	Name = "Line", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 2, Parent = entryPanel,
})
local fadeEnds = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0.25),
	NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.82, 0.25), NumberSequenceKeypoint.new(1, 1),
})
local lineGlow = new("Frame", {
	Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 16),
	BackgroundColor3 = GOLD, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = line,
})
new("UIGradient", { Transparency = fadeEnds, Parent = lineGlow })
local lineCore = new("Frame", {
	Name = "Core", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 3),
	BackgroundColor3 = GOLD_BRIGHT, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = line,
})
new("UIGradient", { Transparency = fadeEnds, Parent = lineCore })
-- The centre: an outlined diamond flanked by two small solid ones.
local ornaments = {}
local function diamond(offsetX, size, filled)
	local d = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, offsetX, 0.5, 0), Size = UDim2.fromOffset(size, size),
		Rotation = 45, BackgroundColor3 = filled and GOLD_BRIGHT or INK, BackgroundTransparency = 1, BorderSizePixel = 0,
		ZIndex = 4, Parent = line,
	})
	local stroke = new("UIStroke", { Color = GOLD_BRIGHT, Thickness = filled and 0 or 1.5, Transparency = 1, Parent = d })
	table.insert(ornaments, { frame = d, stroke = stroke, fillTo = filled and 0 or 0.15 })
end
diamond(0, 13, false)
diamond(-19, 6, true)
diamond(19, 6, true)
-- Sparkles riding the two ends while the line opens.
local sparkles = {}
for _, side in ipairs({ 0, 1 }) do
	table.insert(sparkles, new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(side, 0.5), Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1, Image = HudArt.GLOW_SOFT, ImageColor3 = GOLD_BRIGHT, ImageTransparency = 1,
		ZIndex = 4, Parent = line,
	}))
end

local entryToken = 0

local function tween(item, seconds, goal, style, direction)
	local t = TweenService:Create(item, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function showEntryBanner(zoneName, zoneAlignment, discovered)
	entryToken = entryToken + 1
	local myToken = entryToken
	local L = discovered and LAYOUTS.discovered or LAYOUTS.entry

	-- Lay out for this banner.
	line.Position = UDim2.fromScale(0.5, L.lineY)
	line.Size = UDim2.new(0, 0, 0, 12)
	treeHolder.Visible = L.tree
	treeHolder.Position = UDim2.fromScale(0.5, L.lineY + 0.012)
	treeHolder.Size = UDim2.fromScale(1, 0.3) -- the aspect constraint sets the width
	entryHeader.Visible = L.header
	entryHeader.Size = UDim2.fromScale(0.5, 0.04)
	entryZoneName.Size = UDim2.fromScale(L.nameW, L.nameH)
	entryAlignLabel.Size = UDim2.fromScale(0.5, L.alignH)
	local nameTop = L.lineY + 0.018
	local alignTop = nameTop + L.nameH + 0.006

	entryZoneName.Text = tostring(zoneName or "")
	local accent = ZoneConfig.ALIGNMENT_COLORS[zoneAlignment] or GOLD
	-- Discovery shows the alignment on its own ("Lawful"); plain entry keeps "Lawful zone".
	local alignment = ZoneConfig.DisplayAlignment(zoneAlignment)
	entryAlignLabel.Text = discovered and alignment or (alignment .. " zone")
	entryAlignLabel.TextColor3 = accent

	-- Reset to hidden, then play the entrance.
	for _, label in ipairs({ entryHeader, entryZoneName, entryAlignLabel }) do label.TextTransparency = 1; label.TextStrokeTransparency = 1 end
	tree.ImageTransparency, halo.ImageTransparency = 1, 1
	lineCore.BackgroundTransparency, lineGlow.BackgroundTransparency = 1, 1
	for _, o in ipairs(ornaments) do o.frame.BackgroundTransparency = 1; o.stroke.Transparency = 1 end
	for _, s in ipairs(sparkles) do s.ImageTransparency = 1 end
	entryHeader.Position = UDim2.fromScale(0.5, L.lineY - 0.004)
	entryZoneName.Position = UDim2.fromScale(0.5, nameTop + 0.02)
	entryAlignLabel.Position = UDim2.fromScale(0.5, alignTop + 0.02)
	entryPanel.Visible = true

	-- The line opens outward from the centre; the sparkles ride its ends, then fade.
	tween(line, 0.75, { Size = UDim2.new(L.lineW, 0, 0, 12) }, Enum.EasingStyle.Quart)
	tween(lineCore, 0.3, { BackgroundTransparency = 0 })
	tween(lineGlow, 0.3, { BackgroundTransparency = 0.55 })
	for _, o in ipairs(ornaments) do
		tween(o.frame, 0.3, { BackgroundTransparency = o.fillTo })
		tween(o.stroke, 0.3, { Transparency = 0 })
	end
	for _, s in ipairs(sparkles) do
		s.ImageTransparency = 0.1
		task.delay(0.6, function()
			if myToken == entryToken then tween(s, 0.5, { ImageTransparency = 1 }) end
		end)
	end
	-- The tree rises in behind; the text slides up into place.
	if L.tree then
		treeScale.Scale = 0.94
		tween(treeScale, 1.1, { Scale = 1 }, Enum.EasingStyle.Sine)
		tween(tree, 1.1, { ImageTransparency = 0.38 }, Enum.EasingStyle.Sine)
		tween(halo, 1.1, { ImageTransparency = 0.6 }, Enum.EasingStyle.Sine)
	end
	if L.header then
		tween(entryHeader, 0.45, { TextTransparency = 0, TextStrokeTransparency = 0.45, Position = UDim2.fromScale(0.5, L.lineY - 0.012) })
	end
	task.delay(0.15, function()
		if myToken ~= entryToken then return end
		tween(entryZoneName, 0.5, { TextTransparency = 0, TextStrokeTransparency = 0.35, Position = UDim2.fromScale(0.5, nameTop) }, Enum.EasingStyle.Quart)
		tween(entryAlignLabel, 0.5, { TextTransparency = 0, TextStrokeTransparency = 0.15, Position = UDim2.fromScale(0.5, alignTop) }, Enum.EasingStyle.Quart)
	end)

	task.delay(L.hold, function()
		if myToken ~= entryToken then return end
		local out = 0.6
		for _, label in ipairs({ entryHeader, entryZoneName, entryAlignLabel }) do
			tween(label, out, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		tween(tree, out, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(halo, out, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(lineCore, out, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(lineGlow, out, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(line, out, { Size = UDim2.new(L.lineW * 0.6, 0, 0, 12) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, o in ipairs(ornaments) do
			tween(o.frame, out, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(o.stroke, out, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		task.delay(out + 0.05, function()
			if myToken == entryToken then entryPanel.Visible = false end
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
