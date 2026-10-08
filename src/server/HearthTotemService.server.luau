--[[
	HearthTotemService (server)

	Hearthstone totems: any Workspace model or part with the attribute `HearthTotem = true` gets
	a hold-E prompt. Using it unlocks the Hearthstone for that player (profile.flags.
	hearthstoneUnlocked: the Journal tab appears and HearthstoneService lets them use it), and
	the totem lights up for them.

	The unlock is decided here on the server from the prompt's own Triggered event (the engine
	checks the player is in range); no client remote can set the flag.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileService = require(ServerScriptService:WaitForChild("ProfileService"))
local RemoteUtils = require(ReplicatedStorage:WaitForChild("RemoteUtils"))

local ATTRIBUTE = "HearthTotem"
local PROMPT_NAME = "HearthTotemPrompt"
-- Tells that player's client to light the totem up (TravelScreenClient plays it).
local litEvent = RemoteUtils.EnsureRemoteEvent(RemoteUtils.EnsureFolder(ReplicatedStorage, "GameEvents"), "HearthTotemLit")

local function promptParent(inst)
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true) end
	return nil
end

-- Prompts we've connected. A totem inside a CLONE (every tutorial copy) arrives with the
-- template's prompt already on it, but not its connection: that copy must be wired too, so
-- "has a prompt" is never a reason to skip.
local wired = setmetatable({}, { __mode = "k" })

local function setup(inst)
	if inst:GetAttribute(ATTRIBUTE) ~= true then return end
	local part = promptParent(inst)
	if not part then return end
	local prompt = part:FindFirstChild(PROMPT_NAME)
	if prompt and wired[prompt] then return end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.ActionText = "Attune"
		prompt.ObjectText = "Hearthstone Totem"
		prompt.HoldDuration = 1
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
	end
	wired[prompt] = true
	prompt.Triggered:Connect(function(player)
		local profile = ProfileService.Get(player)
		if not profile or type(profile.flags) ~= "table" then return end
		local first = profile.flags.hearthstoneUnlocked ~= true
		profile.flags.hearthstoneUnlocked = true
		ProfileService.PushProfile(player)
		litEvent:FireClient(player, inst, first)
	end)
end

for _, inst in ipairs(workspace:GetDescendants()) do
	task.spawn(setup, inst)
end
workspace.DescendantAdded:Connect(function(inst)
	task.defer(setup, inst) -- totems in a freshly cloned tutorial instance, too
end)
