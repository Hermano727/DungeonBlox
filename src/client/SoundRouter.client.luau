--[[
	SoundRouter -- makes sure every Sound on this client plays through one sound bucket's
	SoundGroup, so every sound answers to a Settings > Audio slider (client only).

	The buckets and the rules live in RS/AudioCategories (the registry). This script applies the
	two rules that need a live Sound:
	  - SoundCategory attribute (AudioCategories.Tag, server or client): that bucket's group,
	    whatever group the Sound had. That's how server-made Sounds (the horse's gallop loop)
	    reach their slider, since a server can't point at a client's group.
	  - No attribute and no group (Studio-placed, toolbox, a script that forgot): filed by where it
	    lives, AudioCategories.ROOT_FALLBACK (Workspace -> Ambient & World, PlayerGui -> Interface),
	    else the catch-all, Other. 2026-09-26 check: 43 of 43 placed Sounds had no group, so
	    without this neither Master nor the output gain ever reached them.
	Sounds that already have a group and no attribute are left alone, and so is ZoneMusic, which
	bakes Master and the gain into its own Volume (ZoneClient) and would otherwise get them twice.

	Also, in Studio only, warns once about SoundEffects keys that fell through to Other, so a new
	sound nobody filed shows up in the output (AudioCategories.Audit).

	Local only: SoundGroup set on the client affects this client's playback and nothing else.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local AudioCategories = require(ReplicatedStorage:WaitForChild("AudioCategories"))

local EXCLUDED_NAMES = {
	ZoneMusic = true,
}

SoundService:WaitForChild("Main")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local function rootBucket(inst)
	if inst:IsDescendantOf(Workspace) then return AudioCategories.ROOT_FALLBACK.Workspace end
	if inst:IsDescendantOf(playerGui) then return AudioCategories.ROOT_FALLBACK.PlayerGui end
	return AudioCategories.FALLBACK
end

local function route(inst)
	if not inst:IsA("Sound") or EXCLUDED_NAMES[inst.Name] then return end
	local category = inst:GetAttribute("SoundCategory")
	if type(category) == "string" then
		inst.SoundGroup = AudioCategories.GetGroup(category)
	elseif inst.SoundGroup == nil then
		inst.SoundGroup = AudioCategories.GetGroup(rootBucket(inst) or AudioCategories.FALLBACK)
	end
end

local function watch(root)
	for _, d in ipairs(root:GetDescendants()) do route(d) end
	root.DescendantAdded:Connect(route)
end

watch(Workspace)
watch(SoundService)
watch(playerGui)

if RunService:IsStudio() then
	local soundEffects = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("SoundEffects"))
	local unfiled = AudioCategories.Audit(soundEffects)
	if #unfiled > 0 then
		warn(("[AudioCategories] %d sound key(s) fell into Other; give them a KEYS entry or a PREFIXES rule: %s")
			:format(#unfiled, table.concat(unfiled, ", ")))
	end
end
