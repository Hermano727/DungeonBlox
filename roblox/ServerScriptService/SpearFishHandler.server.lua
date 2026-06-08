-- SpearFishHandler
-- Validates water server-side, rolls catch chance, then grants Fish via DungeonProfile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))
local QuestProgress = require(ServerScriptService:WaitForChild("QuestProgressService"))
local SpearFishRequest = ReplicatedStorage:WaitForChild("SpearFishRequest")
local FishingXPEvent = ReplicatedStorage:WaitForChild("FishingXPEvent")

local FISH_CATCH_CHANCE = 0.25
local FISH_ATTEMPT_COOLDOWN = 0.35
local MAX_AIM_DISTANCE_FROM_HRP = 280
-- Player must be this close (studs) to the water surface the server validates.
local MAX_PLAYER_DISTANCE_TO_WATER = 5
local XP_PER_FISH = 5

-- Weighted random catch table. All entries must reference Food/SubKind="Fish" ItemDefinitions.
local FISH_DROP_TABLE = {
	{ id = "Fish",       weight = 60 },
	{ id = "SwiftFish",  weight = 18 },
	{ id = "LuckyFish",  weight = 18 },
	{ id = "GoldenFish", weight = 4  },
}

local function rollFishId()
	local total = 0
	for _, e in ipairs(FISH_DROP_TABLE) do
		total = total + e.weight
	end
	local r = math.random() * total
	local cum = 0
	for _, e in ipairs(FISH_DROP_TABLE) do
		cum = cum + e.weight
		if r <= cum then return e.id end
	end
	return "Fish"
end

local lastAttempt = {}

local VALID_SPEAR_ITEM_IDS = {
	WoodenSpear = true,
	TrainingSpear = true,
}

local VALID_SPEAR_TOOL_NAMES = {
	WoodenSpear = true,
	Spear = true,
	["Wooden Spear"] = true,
	["Training Spear"] = true,
}

local function ownsSpear(player)
	local function isSpearTool(t)
		if not t or not t:IsA("Tool") then
			return false
		end
		local itemId = t:GetAttribute("DungeonItemId")
		if type(itemId) == "string" and VALID_SPEAR_ITEM_IDS[itemId] then
			return true
		end
		local n = t.Name
		return VALID_SPEAR_TOOL_NAMES[n] == true
	end
	local character = player.Character
	if character then
		for _, c in ipairs(character:GetChildren()) do
			if isSpearTool(c) then
				return true
			end
		end
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		for _, c in ipairs(bp:GetChildren()) do
			if isSpearTool(c) then
				return true
			end
		end
	end
	return false
end

local function buildRaycastParams(player)
	local filter = {}
	local character = player.Character
	if character then
		table.insert(filter, character)
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = filter
	rayParams.IgnoreWater = false
	return rayParams
end

local function waterNearAim(player, aimWorldPos, hrpPosition)
	local rayParams = buildRaycastParams(player)

	local offsets = {}
	for dx = -16, 16, 4 do
		for dz = -16, 16, 4 do
			table.insert(offsets, Vector3.new(dx, 0, dz))
		end
	end
	table.insert(offsets, Vector3.new())

	for _, o in ipairs(offsets) do
		local base = aimWorldPos + o
		local origins = {
			base + Vector3.new(0, 24, 0),
			base + Vector3.new(0, 8, 0),
			base + Vector3.new(0, 2, 0),
		}
		for _, origin in ipairs(origins) do
			local hit = Workspace:Raycast(origin, Vector3.new(0, -120, 0), rayParams)
			if hit and hit.Material == Enum.Material.Water then
				if (hrpPosition - hit.Position).Magnitude <= MAX_PLAYER_DISTANCE_TO_WATER then
					return true
				end
			end
		end
	end

	return false
end

local function validateWater(player, aimWorldPos, hrpPosition)
	return waterNearAim(player, aimWorldPos, hrpPosition)
end

SpearFishRequest.OnServerEvent:Connect(function(player, aimWorldPos, _surfaceMatName)
	if typeof(aimWorldPos) ~= "Vector3" then
		return
	end

	if not ownsSpear(player) then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	if (aimWorldPos - hrp.Position).Magnitude > MAX_AIM_DISTANCE_FROM_HRP then
		return
	end

	if not validateWater(player, aimWorldPos, hrp.Position) then
		return
	end

	local uid = player.UserId
	local now = os.clock()
	if (lastAttempt[uid] or 0) + FISH_ATTEMPT_COOLDOWN > now then
		return
	end
	lastAttempt[uid] = now

	if math.random(1, 100) > math.floor(FISH_CATCH_CHANCE * 100) then
		return
	end

	DungeonProfile.AddSkillXP(player, "fishing", XP_PER_FISH)
	FishingXPEvent:FireClient(player, XP_PER_FISH)

	local fishId = rollFishId()
	local ok, err = DungeonProfile.GrantItemId(player, fishId, 1)
	if not ok then
		warn("[SpearFish] GrantItemId failed for", player.Name, fishId, err)
		return
	end
	QuestProgress.OnSpearFishCaught(player, 1)
end)

Players.PlayerRemoving:Connect(function(player)
	lastAttempt[player.UserId] = nil
end)
