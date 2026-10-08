local PotionAction = require(game:GetService("ReplicatedStorage"):WaitForChild("PotionAction"))
--[[
	FoodService
	Every way of eating goes through one eat() here: hunger, BuffService buffs, then exactly that
	stack loses one (ConsumeFromStack, so a banked stack is never eaten).

	Three ways in:
	  1. GameEvents/EatFoodRequest (uuid): a held Food Tool's right-click hold (its LocalScript
	     counts down TimeToEat first). The item must be on the hotbar.
	  2. GameEvents/EatFromBag (RF, uuid): the bag's right-click "Eat" (2026-10-03). Any carried
	     food, not the bank. This is how the buff fish are eaten.
	  3. GameEvents/QuickEatFish (RF, itemId): Keys.QuickEat eats one of the selected quick-eat
	     kind (CookingConfig.QUICK_EAT_ITEMS; the plain fish when none is given) from wherever
	     it's carried (FishQuickEatClient).
	The two RFs return ok, reason ("full", "none", "banked", ...) so the client can say why not.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local HungerData = require(ServerScriptService:WaitForChild("HungerData"))
local BuffService = require(ServerScriptService:WaitForChild("BuffService"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local CookingConfig = require(ReplicatedStorage:WaitForChild("CookingConfig"))
local ConsumableRequestUtil = require(ReplicatedStorage:WaitForChild("ConsumableRequestUtil"))

local gameEventsFolder = ConsumableRequestUtil.EnsureGameEventsFolder()
local EatFoodRequest = ConsumableRequestUtil.EnsureRemoteEvent(gameEventsFolder, "EatFoodRequest")
local EatFromBag = ConsumableRequestUtil.EnsureRemoteFunction(gameEventsFolder, "EatFromBag")
local QuickEatFish = ConsumableRequestUtil.EnsureRemoteFunction(gameEventsFolder, "QuickEatFish")

-- Per-player minimum spacing between eats. Even instant fish should not be spammable faster than this.
local MIN_EAT_INTERVAL = 0.2
local eatLimiter = ConsumableRequestUtil.NewRateLimiter(MIN_EAT_INTERVAL)

local function isBanked(profile, itemUuid)
	if type(profile.chestSlots) ~= "table" then return false end
	for _, uuid in pairs(profile.chestSlots) do
		if uuid == itemUuid then return true end
	end
	return false
end

-- source: "hotbar" (held tool), "bag" (right-click Eat) or "quick" (the quick-eat key).
local function eat(player, itemUuid, source)
	if not player or not player.Parent then return false, "gone" end
	if PotionAction.IsLocked(player.Character) then return false, "busy" end
	if type(itemUuid) ~= "string" or itemUuid == "" then return false, "bad_item" end
	if not eatLimiter:Check(player.UserId) then return false, "too_fast" end

	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile then return false, "no_profile" end
	local item = profile.inventory and profile.inventory[itemUuid]
	if type(item) ~= "table" then return false, "missing" end
	local itemId = item.itemId
	if type(itemId) ~= "string" or itemId == "" then return false, "bad_item" end
	local cfg = ItemDefinitions.GetFoodConfig(itemId)
	if not cfg then return false, "not_food" end

	if source == "hotbar" then
		-- The held tool path: it must be on the hotbar (it was equipped to right-click eat).
		if not ConsumableRequestUtil.FindHotbarSlotForUuid(profile, itemUuid) then return false, "not_held" end
	elseif isBanked(profile, itemUuid) then
		return false, "banked"
	end

	-- Food that only fills hunger is wasted on a full stomach; food with buffs is still worth it.
	local hunger = HungerData.get(player)
	if #cfg.buffs == 0 and hunger and hunger.hunger >= hunger.maxHunger then
		return false, "full"
	end

	local ok, err = DungeonProfile.ConsumeFromStack(player, itemUuid, 1)
	if not ok then
		warn("[FoodService] ConsumeFromStack failed for", player.Name, itemId, err)
		return false, "missing"
	end
	if cfg.hungerAmount > 0 then
		HungerData.eat(player, cfg.hungerAmount)
	end
	if #cfg.buffs > 0 then
		BuffService.ApplyBuffs(player, cfg.buffs)
	end
	return true, itemId
end

EatFoodRequest.OnServerEvent:Connect(function(player, itemUuid)
	eat(player, itemUuid, "hotbar")
end)

EatFromBag.OnServerInvoke = function(player, itemUuid)
	return eat(player, itemUuid, "bag")
end

-- itemId: which quick-eat kind (the client's selection); anything else means the plain fish.
QuickEatFish.OnServerInvoke = function(player, itemId)
	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile then return false, "no_profile" end
	local want = CookingConfig.IsQuickEat(itemId) and itemId or CookingConfig.QUICK_EAT_ITEM
	local stacks = CookingConfig.CarriedStacks(profile, function(id) return id == want end)
	if #stacks == 0 then return false, "none" end
	-- The smallest stack first, so stragglers get used up.
	table.sort(stacks, function(a, b) return a.count < b.count end)
	return eat(player, stacks[1].uuid, "quick")
end

Players.PlayerRemoving:Connect(function(p)
	eatLimiter:Clear(p.UserId)
end)

print("[FoodService] ready")
