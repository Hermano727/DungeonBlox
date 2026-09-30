--[[
	AppearanceService -- the server side of the wardrobe (character customization).

	  * Saves each player's appearance in profile.appearance (RS/ProfileTypes), always run
	    through AppearanceOptions.Sanitize: the client only ever proposes.
	  * Applies it (RS/AppearanceApply) to every character the player spawns, and again right
	    after a save, so everyone sees it (server-side changes replicate).
	  * Turns every Workspace model whose name ends in "Wardrobe" (or tagged "Wardrobe") into a
	    wardrobe: its ProximityPrompt (created if missing) is renamed "WardrobePrompt" and
	    relabelled; the client (Wardrobe) opens the menu on it. Wardrobes only go in safe
	    zones, so nothing here checks zones.

	Remote: GameEvents/AppearanceRequest (RemoteFunction)
		("get")              -> appearance
		("set", appearance)  -> true, savedAppearance  |  false, reason
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local RemoteUtils = require(ReplicatedStorage:WaitForChild("RemoteUtils"))
local AppearanceOptions = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Appearance"):WaitForChild("AppearanceOptions"))
local AppearanceApply = require(ReplicatedStorage:WaitForChild("AppearanceApply"))
local ProfileService = require(ServerScriptService:WaitForChild("ProfileService"))

local WARDROBE_TAG = "Wardrobe"
local PROMPT_NAME = "WardrobePrompt"
local SET_COOLDOWN = 0.5

local ge = RemoteUtils.EnsureFolder(ReplicatedStorage, "GameEvents")
local request = RemoteUtils.EnsureRemoteFunction(ge, "AppearanceRequest")

local lastSet = {}

local function getProfile(player)
	local profile = ProfileService.Get(player)
	if type(profile) ~= "table" then return nil end
	profile.appearance = AppearanceOptions.Sanitize(profile.appearance)
	return profile
end

local function applyTo(player)
	local profile = getProfile(player)
	local character = player.Character
	if not profile or not character then return end
	AppearanceApply.Apply(character, profile.appearance)
end

request.OnServerInvoke = function(player, action, payload)
	if action == "get" then
		local profile = getProfile(player)
		return profile and profile.appearance or AppearanceOptions.Default()
	elseif action == "set" then
		local now = os.clock()
		if lastSet[player] and now - lastSet[player] < SET_COOLDOWN then return false, "slow_down" end
		lastSet[player] = now
		local profile = getProfile(player)
		if not profile then return false, "no_profile" end
		profile.appearance = AppearanceOptions.Sanitize(payload)
		applyTo(player)
		return true, profile.appearance
	end
	return false, "bad_action"
end

-- Every spawn: wait for the body mesh (it streams in with the character), then apply.
local function onCharacter(player, character)
	task.spawn(function()
		local body = character:WaitForChild("Hero_Character", 15)
		if not body then return end
		-- The profile can still be loading on a first spawn; give it a moment.
		local deadline = os.clock() + 15
		while not ProfileService.Get(player) and os.clock() < deadline and character.Parent do task.wait(.25) end
		if character.Parent and player.Character == character then applyTo(player) end
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character) onCharacter(player, character) end)
	if player.Character then onCharacter(player, player.Character) end
end

for _, player in ipairs(Players:GetPlayers()) do onPlayer(player) end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player) lastSet[player] = nil end)

----------------------------------------------------------------------
-- Wardrobes
----------------------------------------------------------------------

local function isWardrobe(inst)
	return inst:IsA("Model") and (CollectionService:HasTag(inst, WARDROBE_TAG) or inst.Name:match("Wardrobe$") ~= nil)
end

local function setupWardrobe(model)
	if model:GetAttribute("WardrobeReady") then return end
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if not anchor then return end
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = anchor
	end
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Customize"
	prompt.ObjectText = "Wardrobe"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 8)
	prompt.Enabled = true
	model:SetAttribute("WardrobeReady", true)
end

for _, inst in ipairs(Workspace:GetDescendants()) do
	if isWardrobe(inst) then setupWardrobe(inst) end
end
Workspace.DescendantAdded:Connect(function(inst)
	if isWardrobe(inst) then task.defer(setupWardrobe, inst) end
end)

print("[AppearanceService] ready")
