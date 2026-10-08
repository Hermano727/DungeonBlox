--[[
	DurabilityService
	Central authority for all item durability mutations.
	Nothing else should write item.durability or item.broken directly (the one shared rule,
	EnchantScrollApply.BreakItem, is what breaking does to the item itself; it lives in
	ReplicatedStorage because a failed enchant breaks items too).

	Rules (2026-10-04):
	  - Every weapon and armor piece has durability / maxDurability (ItemConfig.MAX_DURABILITY_BY_TIER),
	    given on grant and filled in on load for older saves (EnsureDurability).
	  - Wear: -1 to the held weapon per confirmed hit, -1 to each equipped armor piece per hit taken.
	  - Death: every EQUIPPED piece loses 30% of its MAX durability. Bag items and profession tools
	    (Pickaxe, FishingSpear) lose nothing.
	  - At 0 the item breaks: -3 enchant levels (min +0), comes off, can't be re-equipped until a
	    Blacksmith repairs it (3x the normal cost while broken).
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local EnchantScrollApply = require(ReplicatedStorage:WaitForChild("EnchantScrollApply"))

local TIER_MAX_DUR = ItemConfig.MAX_DURABILITY_BY_TIER
local DEATH_LOSS = 0.30 -- of max durability, per equipped piece
-- Equip-panel slots that wear on death (armor + the two weapon slots; never profession tools).
local DEATH_WEAR_SLOTS = table.clone(ItemConfig.ARMOR_SLOTS)
table.insert(DEATH_WEAR_SLOTS, "Weapon")
table.insert(DEATH_WEAR_SLOTS, "Bow")

-- Canonical armor-slot list, shared with ItemConfig and LootService, instead
-- of each durability path keeping its own hand-copied { "Helm", "Chest", ... }
-- array. Adding/removing an armor slot now only means editing ItemConfig.
local ARMOR_SLOTS = ItemConfig.ARMOR_SLOTS

local DurabilityService = {}

-- Lazy deps to avoid circular requires
local _dp, _stats
local function dp()
	if not _dp then _dp = require(ServerScriptService:WaitForChild("ProfileService")) end
	return _dp
end
local function stats()
	if not _stats then _stats = require(ServerScriptService:WaitForChild("StatsService")) end
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

-- Gives a weapon / armor piece its durability if it has none (new grants, older saves).
-- Returns true if it changed the item.
function DurabilityService.EnsureDurability(item)
	if type(item) ~= "table" or (item.type ~= "Weapon" and item.type ~= "Armor") then return false end
	local changed = false
	if type(item.maxDurability) ~= "number" or item.maxDurability <= 0 then
		item.maxDurability = DurabilityService.maxDurForTier(item.tier)
		changed = true
	end
	if type(item.durability) ~= "number" then
		item.durability = item.broken and 0 or item.maxDurability
		changed = true
	end
	return changed
end

-- The server side of a break that already happened to the item (EnchantScrollApply.BreakItem):
-- take it off if it's worn (UnequipItem puts it in the bag and drops the held tool), recompute
-- HP and tell the player. Safe to call for an item that isn't equipped.
function DurabilityService.OnBroken(player, profile, uuid)
	local item = profile and profile.inventory and profile.inventory[uuid]
	if type(item) ~= "table" then return end
	local slot
	if type(profile.equipped) == "table" then
		for s, u in pairs(profile.equipped) do
			if u == uuid then slot = s; break end
		end
	end
	if slot and player then
		dp().UnequipItem(player, slot)
	elseif slot then
		profile.equipped[slot] = nil
	end
	pcall(stats().RecomputeRuntimeHp, profile)
	if player then
		pcall(function()
			getBrokenEvent():FireClient(player, stripPlus(item.name or "Item"))
		end)
	end
end

-- Breaks an owned item outright (item rule + the server side above).
function DurabilityService.breakItem(profile, uuid, player)
	local item = profile.inventory and profile.inventory[uuid]
	if type(item) ~= "table" then return end
	EnchantScrollApply.BreakItem(item)
	DurabilityService.OnBroken(player, profile, uuid)
end

-- Internal: reduce an item's durability by delta, break if reaching 0
local function reduceDurability(player, profile, uuid, delta)
	local item = profile.inventory and profile.inventory[uuid]
	if type(item) ~= "table" then return end
	if type(item.durability) ~= "number" then return end
	item.durability = math.max(0, item.durability - delta)
	if item.durability <= 0 and not item.broken then
		DurabilityService.breakItem(profile, uuid, player)
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

-- Death: every equipped piece (armor, Weapon, Bow) loses 30% of its MAX durability; bag items
-- and profession tools are untouched. Several deaths in the same gear break it.
-- Returns the uuids that broke. They're left EQUIPPED here on purpose: the death drop runs next
-- and drops bag items, so the caller takes them off (OnBroken) only after the drop.
function DurabilityService.applyDeathPenalty(profile, player)
	local broke = {}
	if not profile then return broke end
	local inv = profile.inventory
	if type(inv) ~= "table" or type(profile.equipped) ~= "table" then return broke end
	for _, slot in ipairs(DEATH_WEAR_SLOTS) do
		local uuid = profile.equipped[slot]
		local item = uuid and inv[uuid]
		if type(item) == "table" and not item.broken then
			DurabilityService.EnsureDurability(item)
			local loss = math.ceil(item.maxDurability * DEATH_LOSS)
			item.durability = math.max(0, item.durability - loss)
			if item.durability <= 0 then
				EnchantScrollApply.BreakItem(item)
				table.insert(broke, uuid)
			end
		end
	end
	return broke
end

-- Restore item to full durability and clear broken flag
function DurabilityService.repairItem(item)
	if type(item) ~= "table" then return end
	local maxDur = type(item.maxDurability) == "number" and item.maxDurability or 0
	if maxDur <= 0 then return end
	item.durability = maxDur
	item.broken     = nil
end

getBrokenEvent() -- exists from the start, so clients can listen before the first break

Players.PlayerRemoving:Connect(function() end)  -- keep module alive

return DurabilityService