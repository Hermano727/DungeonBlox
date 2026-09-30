--[[
	SoundRouter -- puts every stray Sound under the settings-controlled volume tree (client only).

	The Settings menu drives volume through SoundService.Main (Master, and the OUTPUT_GAIN in
	RS/VolumeSettings) plus Main.Character / Main.Effects. But most sounds in the game -- world
	ambience, toolbox props, NPC/mob sounds, server-created one-shots -- are plain Sounds with no
	SoundGroup, so neither the Master slider nor the gain ever reached them (2026-09-26 check: 43
	of 43 placed Sounds were ungrouped).

	Any Sound that shows up in Workspace, SoundService or the PlayerGui with SoundGroup == nil is
	assigned to SoundService.Main.World (created here if missing), so it follows Master x gain.
	Sounds that already have a group are left alone, and so is ZoneMusic, which bakes Master and
	the gain into its own Volume (ZoneClient) and would otherwise get them applied twice.

	Local only: SoundGroup set on the client affects this client's playback and nothing else.
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local EXCLUDED_NAMES = {
	ZoneMusic = true,
}

local main = SoundService:WaitForChild("Main")
local world = main:FindFirstChild("World")
if not world then
	world = Instance.new("SoundGroup")
	world.Name = "World"
	world.Volume = 1
	world.Parent = main
end

local function route(inst)
	if inst:IsA("Sound") and inst.SoundGroup == nil and not EXCLUDED_NAMES[inst.Name] then
		inst.SoundGroup = world
	end
end

local function watch(root)
	for _, d in ipairs(root:GetDescendants()) do route(d) end
	root.DescendantAdded:Connect(route)
end

watch(Workspace)
watch(SoundService)
watch(Players.LocalPlayer:WaitForChild("PlayerGui"))
