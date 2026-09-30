--[[
	SwordSlashSfx -- the whoosh on every melee swing (client only; numbers in RS/CombatSfxConfig).

		SwordSlashSfx.Play()   call the instant a swing starts (CombatClient's startSwing)

	Client-first on purpose: it's purely cosmetic, so there is no reason to wait on the server.
	The clip is preloaded into a template when this module loads, so even the first swing plays
	with no delay, and every swing gets its own clone so fast swinging overlaps instead of
	cutting the previous one off. Past SWORD_SLASH_MAX_VOICES the oldest fades out quickly, so
	10 CPS can't stack into a wall of noise. Routed through the Effects bus (Settings slider).
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local CombatSfxConfig = require(ReplicatedStorage:WaitForChild("CombatSfxConfig"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))

local SwordSlashSfx = {}

local VOICE_FADE = .08
local CLEANUP_AFTER = 3

local rng = Random.new()
local voices = {}
local template

local function buildTemplate()
	local id = CombatSfxConfig.SWORD_SLASH_SOUND_ID
	if type(id) ~= "string" or id == "" then return nil end
	local s = Instance.new("Sound")
	s.Name = "SwordSlash"
	s.SoundId = id
	s.Volume = CombatSfxConfig.SWORD_SLASH_VOLUME or .5
	s.SoundGroup = SfxService.GetEffectsGroup()
	s.Parent = SoundService
	task.spawn(function() pcall(ContentProvider.PreloadAsync, ContentProvider, { s }) end)
	return s
end

template = buildTemplate()

local function fadeAndDestroy(s)
	TweenService:Create(s, TweenInfo.new(VOICE_FADE), { Volume = 0 }):Play()
	task.delay(VOICE_FADE + .02, function() s:Destroy() end)
end

function SwordSlashSfx.Play()
	if not template then return end
	local s = template:Clone()
	s.PlaybackSpeed = rng:NextNumber(CombatSfxConfig.SWORD_SLASH_PITCH_MIN or 1, CombatSfxConfig.SWORD_SLASH_PITCH_MAX or 1)
	s.Parent = SoundService
	local start = tonumber(CombatSfxConfig.SWORD_SLASH_START_SEC) or 0
	if start > 0 and s.IsLoaded and s.TimeLength > start then s.TimePosition = start end
	s:Play()
	s.Ended:Connect(function() s:Destroy() end)
	task.delay(CLEANUP_AFTER, function() if s.Parent then s:Destroy() end end)

	table.insert(voices, s)
	for i = #voices, 1, -1 do
		if not voices[i].Parent then table.remove(voices, i) end
	end
	local max = CombatSfxConfig.SWORD_SLASH_MAX_VOICES or 4
	while #voices > max do
		fadeAndDestroy(table.remove(voices, 1))
	end
end

return SwordSlashSfx
