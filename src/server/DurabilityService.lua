--[[
	DurabilityService
	Central authority for all item durability mutations.
	Nothing else should write item.durability or item.broken directly.
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))

local TIER_MAX_DUR = { 1500, 1750, 2000, 2250, 2500 }

-- Canonical armor-slot list, shared with ItemConfig and LootService, instead
-- of each durability path keeping its own hand-copied { "Helm", "Chest", ... }
-- array. Adding/removing an armor slot now only means editing ItemConfig.
local ARMOR_SLOTS = ItemConfig.ARMOR_SLOTS

local DurabilityService = {}

-- Lazy deps to avoid circular requires
local _dp, _stats
local function dp()
	if not _dp then _dp = require(ServerScriptService:WaitForChild("DungeonProfileService")) end
	return _dp
end
local function stats()
	if not _stats then _stats = require(ServerScriptService:WaitForChild("DungeonStatsService")) end
	return _stats
end

local _brokenEv
local function getBrokenEvent()
	if _brokenEv and _brokenEv.Parent then return _brokenEv end
	local ev = ReplicatedStorage:FindFirstChild("ItemBrokenNotify")
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = "ItemBrokenNotify"
		ev.Parent = ReplicatedStorage
	end
	_brokenEv = ev
	return ev
end

-- strip [+N] suffix from an item name
local function stripPlus(name)
	if type(name) ~= "string" then return "" end
	return (name:gsub("%s*%[%+%d+%]$", ""))
end

-- max durability for a given item tier
function DurabilityService.maxDurForTier(tier)
	return TIER_MAX_DUR[math.clamp(math.floor(tonumber(tier) or 1), 1, 5)]
end

-- Repair cost in Coins: ceil(lost/50), min 1, x3 if broken
function DurabilityService.getRepairCost(item)
	if type(item) ~= "table" then return 0 end
	local dur    = type(item.durability) == "number" and item.durability or (item.maxDurability or 0)
	local maxDur = type(item.maxDurability) == "number" and item.maxDurability or 0
	local lost = maxDur - dur
	if lost <= 0 then return 0 end
	local base = math.max(1, math.ceil(lost / 50))
	if item.broken then base = base * 3 end
	return base
end

-- Mark item broken: set flag, strip 3 enchant levels, unequip
function DurabilityService.breakItem(profile, uuid)
	local item = profile.inventory and profile.inventory[uuid]
	if type(item) ~= "table" then return end
	item.durability = 0
	item.broken     = true
	-- Reduce plusRank by 3 (min 0) and rename
	local newRank = math.max(0, (item.plusRank or 0) - 3)
	item.plusRank = newRank
	local baseName = stripPlus(item.name or "")
	if baseName == "" then baseName = item.name or "Item" end
	if newRank > 0 then
		item.name = string.format("%s [+%d]", baseName, newRank)
	else
		item.name = baseName
	end
	-- Unequip if currently equipped
	if type(profile.equipped) == "table" then
		for slot, u in pairs(profile.equipped) do
			if u == uuid then
				profile.equipped[slot] = nil
				break
			end
		end
		local ok, _ = pcall(stats().RecomputeRuntimeHp, profile)
		if not ok then end
	end
end

-- Internal: reduce an item's durability by delta, break if reaching 0
local function reduceDurability(player, profile, uuid, delta)
	local item = profile.inventory and profile.inventory[uuid]
	if type(item) ~= "table" then return end
	if type(item.durability) ~= "number" then return end
	item.durability = math.max(0, item.durability - delta)
	if item.durability <= 0 and not item.broken then
		DurabilityService.breakItem(profile, uuid)
		pcall(function()
			getBrokenEvent():FireClient(player, item.name or "Item")
		end)
		dp().PushProfile(player)
	end
end

-- Weapons have no equip-panel slot (Minecraft-style hotbar model): the held Tool's
-- DungeonItemUuid attribute is the currently wielded weapon. Loses 1 dur on a confirmed hit.
function DurabilityService.weaponHit(player)
	local profile = dp().Get(player)
	if not profile then return end
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	local uuid = tool and tool:GetAttribute("DungeonItemUuid")
	if type(uuid) ~= "string" or uuid == "" then return end
	reduceDurability(player, profile, uuid, 1)
end

-- All equipped armor pieces lose 1 dur when player is hit by a mob
function DurabilityService.armorHit(player)
	local profile = dp().Get(player)
	if not profile then return end
	for _, slot in ipairs(ARMOR_SLOTS) do
		local uuid = (profile.equipped or {})[slot]
		if uuid then
			reduceDurability(player, profile, uuid, 1)
		end
	end
end

-- 30% durability loss on death: equipped weapons/armor + ALL profession tools
function DurabilityService.applyDeathPenalty(profile, player)
	if not profile then return end
	local inv = profile.inventory
	if type(inv) ~= "table" then return end

	-- Collect UUIDs that take the penalty
	local penaltySet = {}

	-- Equipped armor
	for _, slot in ipairs(ARMOR_SLOTS) do
		local uuid = (profile.equipped or {})[slot]
		if uuid then penaltySet[uuid] = true end
	end

	-- Weapon (hotbar[1] is the only "equipped weapon" location now)
	if type(profile.hotbar) == "table" then
		local wuuid = profile.hotbar[1]
		if type(wuuid) == "string" and wuuid ~= "" then penaltySet[wuuid] = true end
	end

	-- ALL profession tools regardless of equipped state
	for uuid, item in pairs(inv) do
		if type(item) == "table" then
			local slot = item.equipSlot
			if slot == "Pickaxe" or slot == "FishingSpear" then
				penaltySet[uuid] = true
			end
		end
	end

	-- Apply 30% reduction
	for uuid in pairs(penaltySet) do
		local item = inv[uuid]
		if type(item) == "table" and type(item.durability) == "number" and not item.broken then
			local loss = math.floor(item.durability * 0.30)
			item.durability = math.max(0, item.durability - loss)
			if item.durability <= 0 then
				DurabilityService.breakItem(profile, uuid)
				if player then
					pcall(function()
						getBrokenEvent():FireClient(player, item.name or "Item")
					end)
				end
			end
		end
	end
end

-- Restore item to full durability and clear broken flag
function DurabilityService.repairItem(item)
	if type(item) ~= "table" then return end
	local maxDur = type(item.maxDurability) == "number" and item.maxDurability or 0
	if maxDur <= 0 then return end
	item.durability = maxDur
	item.broken     = nil
end

Players.PlayerRemoving:Connect(function() end)  -- keep module alive

return DurabilityService