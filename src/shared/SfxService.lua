--[[
	SfxService
	Client-side one-shot effect-sound player. PlayEffect(key) looks key up in
	the SoundEffects registry, spins up a throwaway Sound routed through
	SoundService.Main.Effects, and cleans itself up when done.

	Deliberately NOT throttled/deduped per key: picking up several items in
	quick succession is meant to layer their sounds (see WorldLootService's
	pickup-sound call site) rather than swallow the 2nd/3rd/... pickup, so
	every call gets its own Sound instance.

	SoundService.Main.Effects is a Studio-side instance (SoundService is in
	Rojo's syncbackRules.ignoreTrees, same as ServerStorage) -- it already
	exists as a sibling of the existing Main.Character group SettingsClient's
	"SFX" slider uses, so this module only ever looks it up, never creates it.
	If it's ever missing (a fresh place file that hasn't had the one-time
	Studio setup done), PlayEffect fails quiet -- a missing sound is never
	worth erroring the caller over.
]]

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundEffects = require(
	ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("SoundEffects")
)

local EFFECTS_GROUP_PATH = { "Main", "Effects" } -- SoundService.Main.Effects

local SfxService = {}

-- Cached after the first successful lookup -- SoundService's tree is a
-- Studio-authored fixture, never rebuilt at runtime, so there's nothing to
-- invalidate this cache.
local cachedEffectsGroup = nil

function SfxService.GetEffectsGroup()
	if cachedEffectsGroup and cachedEffectsGroup.Parent then
		return cachedEffectsGroup
	end
	local node = SoundService
	for _, childName in ipairs(EFFECTS_GROUP_PATH) do
		node = node:FindFirstChild(childName)
		if not node then
			return nil
		end
	end
	if not node:IsA("SoundGroup") then
		return nil
	end
	cachedEffectsGroup = node
	return cachedEffectsGroup
end

-- key is a name from the SoundEffects registry (e.g. "ItemPickup"), not a
-- raw asset id -- keeps every call site free of hardcoded rbxassetid strings.
function SfxService.PlayEffect(key)
	if not RunService:IsClient() then
		return
	end
	local assetId = SoundEffects[key]
	if type(assetId) ~= "string" or assetId == "" then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. tostring(key)
	sound.SoundId = assetId
	sound.SoundGroup = SfxService.GetEffectsGroup() -- nil is a valid, harmless value here
	sound.Parent = SoundService

	local destroyed = false
	local function cleanup()
		if destroyed then
			return
		end
		destroyed = true
		sound:Destroy()
	end

	sound.Ended:Connect(cleanup)
	sound:Play()
	-- Safety net: if Ended never fires (load failure, stream hiccup), don't
	-- leak the Sound instance forever.
	task.delay(10, cleanup)
end

return SfxService
