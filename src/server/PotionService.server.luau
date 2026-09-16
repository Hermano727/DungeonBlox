--[[
	PotionService
	Server-authoritative potion drinking: heal-over-time + per-tier charge system.

	Flow (mirrors FoodService's EatFoodRequest pattern):
	  1. Client fires DrinkPotionRequest with an inventory item uuid (must be in hotbar).
	  2. This service validates ownership + that the item is a known potion, checks/consumes
	     1 charge from that potion's charge pool, consumes 1 inventory stack via
	     ProfileService.ConsumeItemId, then starts a heal-over-time tick.
	  3. PotionChargesSync (RemoteEvent) and RequestPotionCharges (RemoteFunction) let the
	     client show charge count + seconds-until-next-charge (mirrors BuffService's
	     ActiveBuffsSync / RequestActiveBuffs dual-remote convention).

	Charge regen model (ONE shared pool per player, not per tier -- see PotionConfig.
	SharedCharges header comment, 2026-09-10: "it should be 3 potions IN GENERAL", replacing
	the old per-tier pools that let 3 Minor + 3 Medium be drunk back to back):
	  The pool holds up to SharedCharges.maxCharges. Charges regenerate ONE AT A TIME via a
	  single chained timer (NOT one independent timer per missing charge): when below max,
	  `nextReadyAt` holds the absolute time the next charge arrives. On completion, if still
	  below max, nextReadyAt is pushed forward by another regenInterval (chained). Drinking
	  only ever *starts* this timer (when nil); it never resets or extends an already-running
	  one. Example with regenInterval=40: at 3/3, drink -> 2/3, nextReadyAt=+40. At t=8s drink
	  again -> 1/3, nextReadyAt unchanged (still 40). That first charge lands at t=40 (->2/3),
	  immediately chaining a second timer to t=80 (->3/3). So from t=8s it takes 72s to refill,
	  not 40s - the second charge's clock doesn't start until the first one finishes.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local ConsumableRequestUtil = require(ReplicatedStorage:WaitForChild("ConsumableRequestUtil"))
local PotionConfig = require(ReplicatedStorage:WaitForChild("PotionConfig"))

-- itemId -> { healPerSecond, duration (seconds healed), displayName }. Lives in
-- shared/PotionConfig now (see that file's header) -- charge count/regen no longer live per
-- tier here, see SHARED_CHARGES below.
local POTION_CONFIG = PotionConfig.Tiers
local SHARED_CHARGES = PotionConfig.SharedCharges

-- [userId] = { count = n, nextReadyAt = clockOrNil } -- ONE shared pool per player (2026-09-10),
-- not one per potion tier -- see PotionConfig.SharedCharges header comment.
local chargeState = {}
-- [userId] = array of { healPerSecond = n, expiresAt = clock }
local activeHeals = {}

local gameEventsFolder = ConsumableRequestUtil.EnsureGameEventsFolder()

local DrinkPotionRequest = ConsumableRequestUtil.EnsureRemoteEvent(gameEventsFolder, "DrinkPotionRequest")
local PotionChargesSync = ConsumableRequestUtil.EnsureRemoteEvent(gameEventsFolder, "PotionChargesSync")
local RequestPotionCharges = ConsumableRequestUtil.EnsureRemoteFunction(gameEventsFolder, "RequestPotionCharges")

local function getChargeEntry(userId)
	local e = chargeState[userId]
	if not e then
		e = { count = SHARED_CHARGES.maxCharges, nextReadyAt = nil }
		chargeState[userId] = e
	end
	return e
end

local function snapshotCharges(userId)
	local e = chargeState[userId]
	local now = os.clock()
	return {
		count = e and e.count or SHARED_CHARGES.maxCharges,
		maxCharges = SHARED_CHARGES.maxCharges,
		secondsUntilNext = (e and e.nextReadyAt) and math.max(0, e.nextReadyAt - now) or nil,
	}
end

local function pushCharges(player)
	if not player or not player.Parent then
		return
	end
	PotionChargesSync:FireClient(player, snapshotCharges(player.UserId))
end

RequestPotionCharges.OnServerInvoke = function(player)
	return snapshotCharges(player.UserId)
end

-- Even instant-feeling drinks should not be spammable faster than this.
local MIN_DRINK_INTERVAL = 0.2
local drinkLimiter = ConsumableRequestUtil.NewRateLimiter(MIN_DRINK_INTERVAL)

DrinkPotionRequest.OnServerEvent:Connect(function(player, itemUuid)
	if not player or not player.Parent then return end
	if type(itemUuid) ~= "string" or itemUuid == "" then return end

	if not drinkLimiter:Check(player.UserId) then
		return
	end

	-- Used below for both the charge-regen timer start and the heal-tick expiry; the
	-- limiter above keeps its own internal clock, so this is a fresh read, not reused from it.
	local now = os.clock()

	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile then return end

	local item = profile.inventory and profile.inventory[itemUuid]
	if type(item) ~= "table" then return end

	local itemId = item.itemId
	local cfg = POTION_CONFIG[itemId]
	if not cfg then return end -- not a known potion

	-- Item must be in the player's hotbar (i.e. they actually had it equipped/selected to drink).
	if not ConsumableRequestUtil.FindHotbarSlotForUuid(profile, itemUuid) then
		return
	end

	-- Shared pool: whichever tier is drunk, it draws from the same count (see
	-- PotionConfig.SharedCharges).
	local entry = getChargeEntry(player.UserId)
	if entry.count <= 0 then
		return
	end

	local ok = DungeonProfile.ConsumeItemId(player, itemId, 1)
	if not ok then
		return
	end

	entry.count -= 1
	if entry.nextReadyAt == nil then
		entry.nextReadyAt = now + SHARED_CHARGES.regenInterval
	end

	local heals = activeHeals[player.UserId]
	if not heals then
		heals = {}
		activeHeals[player.UserId] = heals
	end
	table.insert(heals, { healPerSecond = cfg.healPerSecond, expiresAt = now + cfg.duration })

	pushCharges(player)
end)

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()

	-- Heal-over-time ticks (multiple active drinks of any tier stack additively).
	for uid, list in pairs(activeHeals) do
		local player = Players:GetPlayerByUserId(uid)
		if not player then
			activeHeals[uid] = nil
			continue
		end
		local totalPerSecond = 0
		for i = #list, 1, -1 do
			local h = list[i]
			if h.expiresAt <= now then
				table.remove(list, i)
			else
				totalPerSecond += h.healPerSecond
			end
		end
		if #list == 0 then
			activeHeals[uid] = nil
		end
		if totalPerSecond > 0 then
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hum.Health = math.min(hum.MaxHealth, hum.Health + totalPerSecond * dt)
			end
		end
	end

	-- Charge regen (chained single-timer model, see header comment) -- one shared pool per
	-- player now, not one per tier.
	for uid, e in pairs(chargeState) do
		if e.nextReadyAt and now >= e.nextReadyAt then
			e.count = math.min(SHARED_CHARGES.maxCharges, e.count + 1)
			if e.count < SHARED_CHARGES.maxCharges then
				e.nextReadyAt = e.nextReadyAt + SHARED_CHARGES.regenInterval
			else
				e.nextReadyAt = nil
			end
			local player = Players:GetPlayerByUserId(uid)
			if player then
				pushCharges(player)
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	task.defer(function()
		getChargeEntry(player.UserId)
		pushCharges(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	chargeState[player.UserId] = nil
	activeHeals[player.UserId] = nil
	drinkLimiter:Clear(player.UserId)
end)

print("[PotionService] ready")
