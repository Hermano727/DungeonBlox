--[[
	FoodService
	Handles "eat food" requests from food Tools' embedded LocalScript.

	Flow:
	  1. Client right-click-holds while a Food Tool is equipped.
	  2. Tool LocalScript counts down TimeToEat (instant for fish), then fires EatFoodRequest with the
	     item UUID. Cancellation (release / unequip) prevents the fire.
	  3. This service validates ownership + Kind, then applies hunger and BuffService buffs, then
	     consumes 1 of the item via ProfileService.ConsumeItemId.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local HungerData = require(ServerScriptService:WaitForChild("HungerData"))
local BuffService = require(ServerScriptService:WaitForChild("BuffService"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local ConsumableRequestUtil = require(ReplicatedStorage:WaitForChild("ConsumableRequestUtil"))

local gameEventsFolder = ConsumableRequestUtil.EnsureGameEventsFolder()
local EatFoodRequest = ConsumableRequestUtil.EnsureRemoteEvent(gameEventsFolder, "EatFoodRequest")

-- Per-player minimum spacing between eats. Even instant fish should not be spammable faster than this.
local MIN_EAT_INTERVAL = 0.2
local eatLimiter = ConsumableRequestUtil.NewRateLimiter(MIN_EAT_INTERVAL)

EatFoodRequest.OnServerEvent:Connect(function(player, itemUuid)
	if not player or not player.Parent then return end
	if type(itemUuid) ~= "string" or itemUuid == "" then return end

	if not eatLimiter:Check(player.UserId) then
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
	if not ConsumableRequestUtil.FindHotbarSlotForUuid(profile, itemUuid) then
		return
	end

	if cfg.hungerAmount > 0 then
		HungerData.eat(player, cfg.hungerAmount)
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
	eatLimiter:Clear(p.UserId)
end)

print("[FoodService] ready")
