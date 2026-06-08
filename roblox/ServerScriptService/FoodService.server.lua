--[[
	FoodService
	Handles "eat food" requests from food Tools' embedded LocalScript.

	Flow:
	  1. Client right-click-holds while a Food Tool is equipped.
	  2. Tool LocalScript counts down TimeToEat (instant for fish), then fires EatFoodRequest with the
	     item UUID. Cancellation (release / unequip) prevents the fire.
	  3. This service validates ownership + Kind, then applies hunger and BuffService buffs, then
	     consumes 1 of the item via DungeonProfileService.ConsumeItemId.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))
local HungerData = require(ServerScriptService:WaitForChild("HungerData"))
local BuffService = require(ServerScriptService:WaitForChild("BuffService"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local function ensureGameEventsFolder()
	local f = ReplicatedStorage:FindFirstChild("GameEvents")
	if f and f:IsA("Folder") then
		return f
	end
	if f then
		f:Destroy()
	end
	f = Instance.new("Folder")
	f.Name = "GameEvents"
	f.Parent = ReplicatedStorage
	return f
end

local gameEventsFolder = ensureGameEventsFolder()
local EatFoodRequest = gameEventsFolder:FindFirstChild("EatFoodRequest")
if EatFoodRequest and not EatFoodRequest:IsA("RemoteEvent") then
	EatFoodRequest:Destroy()
	EatFoodRequest = nil
end
if not EatFoodRequest then
	EatFoodRequest = Instance.new("RemoteEvent")
	EatFoodRequest.Name = "EatFoodRequest"
	EatFoodRequest.Parent = gameEventsFolder
end

-- Per-player minimum spacing between eats. Even instant fish should not be spammable faster than this.
local MIN_EAT_INTERVAL = 0.2
local lastEatByUid = {}

local function findHotbarSlotForUuid(profile, uuid)
	if type(profile.hotbar) ~= "table" then return nil end
	for i = 1, 9 do
		if profile.hotbar[i] == uuid then
			return i
		end
	end
	return nil
end

EatFoodRequest.OnServerEvent:Connect(function(player, itemUuid)
	if not player or not player.Parent then return end
	if type(itemUuid) ~= "string" or itemUuid == "" then return end

	local now = os.clock()
	if (lastEatByUid[player.UserId] or 0) + MIN_EAT_INTERVAL > now then
		return
	end

	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile then return end

	local item = profile.inventory and profile.inventory[itemUuid]
	if type(item) ~= "table" then return end

	local itemId = item.itemId
	if type(itemId) ~= "string" or itemId == "" then return end

	local cfg = ItemDefinitions.GetFoodConfig(itemId)
	if not cfg then return end -- not a Food item

	-- Item must be in the player's hotbar (i.e. they actually had it equipped to right-click eat).
	if not findHotbarSlotForUuid(profile, itemUuid) then
		return
	end

	lastEatByUid[player.UserId] = now

	if cfg.hungerAmount > 0 then
		HungerData.addHunger(player, cfg.hungerAmount)
	end

	if #cfg.buffs > 0 then
		BuffService.ApplyBuffs(player, cfg.buffs)
	end

	local ok, err = DungeonProfile.ConsumeItemId(player, itemId, 1)
	if not ok then
		warn("[FoodService] ConsumeItemId failed for", player.Name, itemId, err)
	end
end)

Players.PlayerRemoving:Connect(function(p)
	lastEatByUid[p.UserId] = nil
end)

print("[FoodService] ready")
