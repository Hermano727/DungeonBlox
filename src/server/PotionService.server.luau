--[[
	PotionService
	Server-authoritative potion drinking: heal-over-time + per-tier charge system.

	Flow (mirrors FoodService's EatFoodRequest pattern):
	  1. Client fires DrinkPotionRequest with an inventory item uuid (must be in hotbar).
	  2. This service validates ownership + that the item is a known potion, checks/consumes
	     1 charge from that potion's charge pool, consumes 1 inventory stack via
	     DungeonProfileService.ConsumeItemId, then starts a heal-over-time tick.
	  3. PotionChargesSync (RemoteEvent) and RequestPotionCharges (RemoteFunction) let the
	     client show charge count + seconds-until-next-charge (mirrors BuffService's
	     ActiveBuffsSync / RequestActiveBuffs dual-remote convention).

	Charge regen model (per potion tier, per player):
	  Each tier has its own pool of up to maxCharges. Charges regenerate ONE AT A TIME via a
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

local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))

-- itemId -> { healPerSecond, duration (seconds healed), maxCharges, regenInterval (seconds per charge) }
local POTION_CONFIG = {
	MinorPotion  = { healPerSecond = 30, duration = 5, maxCharges = 3, regenInterval = 40 },
	MediumPotion = { healPerSecond = 60, duration = 5, maxCharges = 3, regenInterval = 40 },
}

-- [userId] = { [itemId] = { count = n, nextReadyAt = clockOrNil } }
local chargeState = {}
-- [userId] = array of { healPerSecond = n, expiresAt = clock }
local activeHeals = {}

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

local function ensureRemoteEvent(name)
	local ev = gameEventsFolder:FindFirstChild(name)
	if ev and not ev:IsA("RemoteEvent") then
		ev:Destroy()
		ev = nil
	end
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = gameEventsFolder
	end
	return ev
end

local function ensureRemoteFunction(name)
	local rf = gameEventsFolder:FindFirstChild(name)
	if rf and not rf:IsA("RemoteFunction") then
		rf:Destroy()
		rf = nil
	end
	if not rf then
		rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = gameEventsFolder
	end
	return rf
end

local DrinkPotionRequest = ensureRemoteEvent("DrinkPotionRequest")
local PotionChargesSync = ensureRemoteEvent("PotionChargesSync")
local RequestPotionCharges = ensureRemoteFunction("RequestPotionCharges")

local function getChargeTable(userId)
	local t = chargeState[userId]
	if not t then
		t = {}
		chargeState[userId] = t
	end
	return t
end

local function getChargeEntry(userId, itemId)
	local cfg = POTION_CONFIG[itemId]
	if not cfg then
		return nil, nil
	end
	local t = getChargeTable(userId)
	local e = t[itemId]
	if not e then
		e = { count = cfg.maxCharges, nextReadyAt = nil }
		t[itemId] = e
	end
	return e, cfg
end

local function snapshotCharges(userId)
	local t = chargeState[userId]
	if not t then
		return {}
	end
	local now = os.clock()
	local out = {}
	for itemId, e in pairs(t) do
		out[itemId] = {
			count = e.count,
			secondsUntilNext = e.nextReadyAt and math.max(0, e.nextReadyAt - now) or nil,
		}
	end
	return out
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

local function findHotbarSlotForUuid(profile, uuid)
	if type(profile.hotbar) ~= "table" then return nil end
	for i = 1, 9 do
		if profile.hotbar[i] == uuid then
			return i
		end
	end
	return nil
end

-- Even instant-feeling drinks should not be spammable faster than this.
local MIN_DRINK_INTERVAL = 0.2
local lastDrinkByUid = {}

DrinkPotionRequest.OnServerEvent:Connect(function(player, itemUuid)
	if not player or not player.Parent then return end
	if type(itemUuid) ~= "string" or itemUuid == "" then return end

	local now = os.clock()
	if (lastDrinkByUid[player.UserId] or 0) + MIN_DRINK_INTERVAL > now then
		return
	end

	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile then return end

	local item = profile.inventory and profile.inventory[itemUuid]
	if type(item) ~= "table" then return end

	local itemId = item.itemId
	local entry, cfg = getChargeEntry(player.UserId, itemId)
	if not entry then return end -- not a known potion

	-- Item must be in the player's hotbar (i.e. they actually had it equipped/selected to drink).
	if not findHotbarSlotForUuid(profile, itemUuid) then
		return
	end

	if entry.count <= 0 then
		return
	end

	local ok = DungeonProfile.ConsumeItemId(player, itemId, 1)
	if not ok then
		return
	end

	lastDrinkByUid[player.UserId] = now

	entry.count -= 1
	if entry.nextReadyAt == nil then
		entry.nextReadyAt = now + cfg.regenInterval
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

	-- Charge regen (chained single-timer-per-tier model, see header comment).
	for uid, t in pairs(chargeState) do
		local changed = false
		for itemId, e in pairs(t) do
			local cfg = POTION_CONFIG[itemId]
			if cfg and e.nextReadyAt and now >= e.nextReadyAt then
				e.count = math.min(cfg.maxCharges, e.count + 1)
				changed = true
				if e.count < cfg.maxCharges then
					e.nextReadyAt = e.nextReadyAt + cfg.regenInterval
				else
					e.nextReadyAt = nil
				end
			end
		end
		if changed then
			local player = Players:GetPlayerByUserId(uid)
			if player then
				pushCharges(player)
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	task.defer(function()
		for itemId in pairs(POTION_CONFIG) do
			getChargeEntry(player.UserId, itemId)
		end
		pushCharges(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	chargeState[player.UserId] = nil
	activeHeals[player.UserId] = nil
	lastDrinkByUid[player.UserId] = nil
end)

print("[PotionService] ready")
