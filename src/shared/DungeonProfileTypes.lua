--[[
  Shared profile defaults + validation helpers for DungeonProfileService and client UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local DungeonProfileTypes = {}

-- Bootstrap / legacy items used display `name` without `itemId`; map to ItemDefinitions catalog keys.
local LEGACY_DISPLAY_NAME_TO_ITEM_ID = {
	["Training Sword"] = "TrainingSword",
	["Training Bow"] = "TrainingBow",
	["Training Helm"] = "TrainingHelm",
	["Training Chest"] = "TrainingChest",
	["Training Legs"] = "TrainingLegs",
	["Training Boots"] = "TrainingBoots",
	["Training Shield"] = "TrainingShield",
	["Training Pickaxe"] = "TrainingPickaxe",
	["Training Spear"] = "TrainingSpear",
}

function DungeonProfileTypes.InferLegacyItemIdFromName(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return LEGACY_DISPLAY_NAME_TO_ITEM_ID[name]
end

DungeonProfileTypes.VERSION = 1
-- Treasure chest grid: 9 columns × 6 rows (54 slots), row-major indices.
-- `chestUnlockedRows` (1..CHEST_GRID_ROWS) controls how many full rows can hold items; extra rows cost coins to unlock (`CHEST_ROW_UNLOCK_COIN_COST` each).
DungeonProfileTypes.CHEST_GRID_COLUMNS = 9
DungeonProfileTypes.CHEST_GRID_ROWS = 6
DungeonProfileTypes.CHEST_SLOT_COUNT = DungeonProfileTypes.CHEST_GRID_COLUMNS * DungeonProfileTypes.CHEST_GRID_ROWS
-- Back-compat alias: one chest row width in slots (same as column count).
DungeonProfileTypes.CHEST_PLAYER_ACCESSIBLE_COUNT = DungeonProfileTypes.CHEST_GRID_COLUMNS
DungeonProfileTypes.CHEST_ROW_UNLOCK_COIN_COST = 1
-- Bag: flat 27-slot array (3 rows x 9), matching DungeonMenuUI's BAG_SLOTS grid. Positional
-- index into profile.inventory, exactly like hotbar[i] -- the dict itself is unchanged.
DungeonProfileTypes.BAG_SLOT_COUNT = 27

function DungeonProfileTypes.DefaultProfile()
	return {
		version = DungeonProfileTypes.VERSION,
		currencies = {
			Coins = 0,
		},

		bank = {
			Coins = 0,
		},

		flags = {
			inRaid = false,
			teleports = {},
			starterPackImported = false,
			trainingGearSeeded = false,
			-- Cuso quest: kill Bandit mobs (MobID "Bandit") while active.
			cusoBanditQuest = {
				active = false,
				completed = false,
				target = 5,
				progress = 0,
				rewardCoins = 10,
				rewardPaid = false,
			},
			-- Miner quest: collect Coal items from mining pickups while active.
			minerCoalQuest = {
				active = false,
				completed = false,
				started = false,
				target = 5,
				progress = 0,
				rewardCoins = 10,
				rewardPaid = false,
			},
			-- First ProximityPrompt open with Miner: grant starter Training Pickaxe if missing.
			minerPickaxeGreetingDone = false,
			-- Fisherman quest: catch Fish with Wooden Spear (SpearFishHandler) while active.
			fisherFishQuest = {
				active = false,
				completed = false,
				started = false,
				target = 5,
				progress = 0,
				rewardCoins = 10,
				rewardPaid = false,
			},
			fisherSpearGreetingDone = false,
			-- One-time HUD tip after the player first reaches 30 T1 Key Fragments (bag inventory).
			t1KeyFragment30NoticeDismissed = false,
		},
		stats = {
			combat = {
				maxHp = 100,
				hpRegen = 0.5,
				energyRegen = 8.0,
				level = 1,
				xp = 0,
			},
			mining = {
				level = 1,
				xp = 0,
				miningLevel = 1,
			},
			fishing = {
				level = 1,
				xp = 0,
				fishingLevel = 1,
			},
		},
		runtime = {
			currentHp = 100,
		},
		inventory = {},
		equipped = {},
		hotbar = {}, -- sparse; slots 1-9 filled by ensureHotbar/Reconcile
		bagSlots = (function()
			local t = {}
			for i = 1, DungeonProfileTypes.BAG_SLOT_COUNT do
				t[i] = nil
			end
			return t
		end)(),

		hearthstone = {
			active        = "cyren",  -- id of the currently bound location
			unlocked      = { "cyren" },  -- ordered list of owned location ids
			cooldownUntil = 0,  -- os.time() when teleport cooldown expires
		},

		-- PvP alignment. Players default to Lawful; changing it triggers a 5-minute cooldown
		-- (enforced server-side in DungeonProfileService.SetAlignment).
		alignment = {
			current       = "Lawful",  -- "Lawful" | "Neutral" | "Chaotic"
			cooldownUntil = 0,         -- os.time() epoch; while now < this, no change allowed
		},

		-- Treasure chest: 9×6 slots; `chestUnlockedRows` rows are usable (rest locked until purchased).
		chestInventory = {},
		chestUnlockedRows = 1,
		chestSlots = (function()
			local t = {}
			for i = 1, DungeonProfileTypes.CHEST_SLOT_COUNT do
				t[i] = nil
			end
			return t
		end)(),
	}
end

local VALID_RARITIES = {
	Common = true,
	Uncommon = true,
	Rare = true,
	Epic = true,
	Legendary = true,
}

local VALID_SLOTS = {
	Weapon      = true,
	Armor       = true,
	Helm        = true,
	Chest       = true,
	Legs        = true,
	Boots       = true,
	Shield      = true,
	Necklace    = true,
	Ring        = true,
	Pickaxe     = true,
	FishingSpear = true,
	Potion      = true,
}

function DungeonProfileTypes.ValidateItemTemplate(t)
	if type(t) ~= "table" then
		return false, "bad_template"
	end
	if type(t.name) ~= "string" or t.name == "" then
		return false, "bad_name"
	end
	if type(t.type) ~= "string" or t.type == "" then
		return false, "bad_type"
	end
	if type(t.rarity) ~= "string" or not VALID_RARITIES[t.rarity] then
		return false, "bad_rarity"
	end
	if type(t.tier) ~= "number" or t.tier < 1 or t.tier > 100 then
		return false, "bad_tier"
	end
	if type(t.enchantLevel) ~= "number" or t.enchantLevel < 0 or t.enchantLevel > 50 then
		return false, "bad_enchant"
	end
	if type(t.subStats) ~= "table" then
		return false, "bad_substats"
	end
	if t.equipSlot ~= nil then
		if type(t.equipSlot) ~= "string" or not VALID_SLOTS[t.equipSlot] then
			return false, "bad_equipslot"
		end
	end
	if t.tags ~= nil and type(t.tags) ~= "table" then
		return false, "bad_tags"
	end
	if t.toolPrefabName ~= nil then
		if type(t.toolPrefabName) ~= "string" or t.toolPrefabName == "" then
			return false, "bad_toolPrefabName"
		end
	end
	if t.itemId ~= nil then
		if type(t.itemId) ~= "string" or t.itemId == "" then
			return false, "bad_itemId"
		end
	end
	return true, nil
end

function DungeonProfileTypes.GetAllowedEquipSlot(item)
	if type(item) ~= "table" then
		return nil
	end
	if type(item.equipSlot) == "string" and VALID_SLOTS[item.equipSlot] then
		return item.equipSlot
	end
	if item.type == "Weapon" then
		return "Weapon"
	end
	if item.type == "Armor" then
		-- Prefer specific slot from tags or equipSlot; fall back to generic Armor
		if item.equipSlot and VALID_SLOTS[item.equipSlot] then
			return item.equipSlot
		end
		if type(item.tags) == "table" then
			for _, tag in ipairs(item.tags) do
				if VALID_SLOTS[tag] then return tag end
			end
		end
		return "Armor"
	end
	if item.type == "Consumable" then
		return "Potion"
	end
	return nil
end

local RARITY_COLORS = {
	Common = Color3.fromRGB(205, 210, 220),
	Uncommon = Color3.fromRGB(70, 205, 105),
	Rare = Color3.fromRGB(80, 170, 255),
	Epic = Color3.fromRGB(200, 120, 255),
	Legendary = Color3.fromRGB(255, 175, 85),
}

function DungeonProfileTypes.GetRarityColor(r)
	if type(r) ~= "string" then
		return Color3.new(1, 1, 1)
	end
	return RARITY_COLORS[r] or Color3.new(1, 1, 1)
end

-- 1 = Common .. 5 = Legendary (used for merchant salvage payout scaling).
function DungeonProfileTypes.GetRarityTierIndex(rarity)
	local order = {
		Common = 1,
		Uncommon = 2,
		Rare = 3,
		Epic = 4,
		Legendary = 5,
	}
	if type(rarity) ~= "string" then
		return 1
	end
	return order[rarity] or 1
end


local function lighten(c: Color3, amt: number): Color3
	return Color3.new(
		c.R + (1 - c.R) * amt,
		c.G + (1 - c.G) * amt,
		c.B + (1 - c.B) * amt
	)
end

local function darken(c: Color3, amt: number): Color3
	return Color3.new(c.R * (1 - amt), c.G * (1 - amt), c.B * (1 - amt))
end

-- GetRarityGradient -- the same per-rarity color as GetRarityColor, but as a ColorSequence with
-- two bright/near-white highlight spots traveling around it (0.32 and 0.82), instead of one
-- flat color -- used by RarityBorder's UIGradient so item borders read as a shiny gradient
-- outline, not a solid-color stroke.
function DungeonProfileTypes.GetRarityGradient(rarity)
	local base = DungeonProfileTypes.GetRarityColor(rarity)
	local dim = darken(base, 0.35)
	local bright = lighten(base, 0.65)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, dim),
		ColorSequenceKeypoint.new(0.18, base),
		ColorSequenceKeypoint.new(0.32, bright),
		ColorSequenceKeypoint.new(0.46, base),
		ColorSequenceKeypoint.new(0.68, dim),
		ColorSequenceKeypoint.new(0.82, bright),
		ColorSequenceKeypoint.new(1.00, dim),
	})
end

function DungeonProfileTypes.GetNextRarity(rarity)
	local order = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
	if type(rarity) ~= "string" then
		return nil
	end
	for i, r in ipairs(order) do
		if r == rarity and i < #order then
			return order[i + 1]
		end
	end
	return nil
end

function DungeonProfileTypes.ValidateOwnedItem(item)
	if type(item) ~= "table" then
		return false, "bad_item"
	end
	if type(item.uuid) ~= "string" or item.uuid == "" then
		return false, "bad_uuid"
	end
	if type(item.itemId) ~= "string" or item.itemId == "" then
		return false, "bad_itemId"
	end
	local def = ItemDefinitions.Get(item.itemId)
	if not def then
		return false, "unknown_item"
	end
	if type(item.count) ~= "number" or item.count < 1 or item.count ~= math.floor(item.count) then
		return false, "bad_count"
	end
	if ItemDefinitions.IsStackable(item.itemId) then
		local maxStack = ItemDefinitions.GetMaxStack(item.itemId)
		if item.count > maxStack then
			return false, "overstack"
		end
	else
		if item.count ~= 1 then
			return false, "bad_count"
		end
	end
	return true, nil
end

function DungeonProfileTypes.HotbarSlotUuid(hotbar, i)
	if type(hotbar) ~= "table" then
		return nil
	end
	i = math.floor(tonumber(i) or -1)
	if i < 1 or i > 9 then
		return nil
	end
	local v = hotbar[i]
	if type(v) == "string" and v ~= "" then
		return v
	end
	v = hotbar[tostring(i)]
	if type(v) == "string" and v ~= "" then
		return v
	end
	return nil
end

local function fillMissing(dst, defaults)
	for k, v in pairs(defaults) do
		if v == nil then
			continue
		end
		if dst[k] == nil then
			dst[k] = v
		elseif type(v) == "table" and type(dst[k]) == "table" then
			fillMissing(dst[k], v)
		end
	end
end

local function evacuateInaccessibleChestSlots(loaded)
	local rows = math.clamp(math.floor(tonumber(loaded.chestUnlockedRows) or 1), 1, DungeonProfileTypes.CHEST_GRID_ROWS)
	loaded.chestUnlockedRows = rows
	local maxSlot = rows * DungeonProfileTypes.CHEST_GRID_COLUMNS
	local slots = loaded.chestSlots
	local chestInv = loaded.chestInventory
	if type(slots) ~= "table" or type(chestInv) ~= "table" then
		return
	end
	if type(loaded.inventory) ~= "table" then
		loaded.inventory = {}
	end
	for i = maxSlot + 1, DungeonProfileTypes.CHEST_SLOT_COUNT do
		local uuid = slots[i]
		if type(uuid) == "string" and uuid ~= "" then
			slots[i] = nil
			local it = chestInv[uuid]
			if type(it) == "table" then
				chestInv[uuid] = nil
				loaded.inventory[uuid] = it
			end
		end
	end
end

function DungeonProfileTypes.Reconcile(loaded)
	if type(loaded) ~= "table" then
		loaded = {}
	end
	fillMissing(loaded, DungeonProfileTypes.DefaultProfile())
	if type(loaded.currencies) == "table" then
		loaded.currencies.Scrap = nil
	end
	if type(loaded.inventory) ~= "table" then
		loaded.inventory = {}
	end
	if type(loaded.equipped) ~= "table" then
		loaded.equipped = {}
	end
	if type(loaded.hotbar) ~= "table" then
		loaded.hotbar = {}
	else
		local hb = {}
		for i = 1, 9 do
			hb[i] = DungeonProfileTypes.HotbarSlotUuid(loaded.hotbar, i)
		end
		loaded.hotbar = hb
	end
	if type(loaded.bagSlots) ~= "table" then
		local d = {}
		for i = 1, DungeonProfileTypes.BAG_SLOT_COUNT do
			d[i] = nil
		end
		loaded.bagSlots = d
	else
		local bs = {}
		for i = 1, DungeonProfileTypes.BAG_SLOT_COUNT do
			local v = loaded.bagSlots[i]
			if v == nil then
				v = loaded.bagSlots[tostring(i)]
			end
			bs[i] = v
		end
		loaded.bagSlots = bs
	end

	if type(loaded.chestInventory) ~= "table" then
		loaded.chestInventory = {}
	end
	if type(loaded.chestSlots) ~= "table" then
		local d = {}
		for i = 1, DungeonProfileTypes.CHEST_SLOT_COUNT do
			d[i] = nil
		end
		loaded.chestSlots = d
	else
		local cs = {}
		for i = 1, DungeonProfileTypes.CHEST_SLOT_COUNT do
			local v = loaded.chestSlots[i]
			if v == nil then
				v = loaded.chestSlots[tostring(i)]
			end
			cs[i] = v
		end
		loaded.chestSlots = cs
	end
	loaded.chestUnlockedRows = math.clamp(math.floor(tonumber(loaded.chestUnlockedRows) or 1), 1, DungeonProfileTypes.CHEST_GRID_ROWS)
	evacuateInaccessibleChestSlots(loaded)

	local function grantStackableCountToInv(inv, itemId, totalToAdd)
		if type(inv) ~= "table" or type(itemId) ~= "string" or itemId == "" then
			return
		end
		local maxStack = ItemDefinitions.GetMaxStack(itemId)
		if maxStack < 1 then
			return
		end
		local remaining = math.floor(tonumber(totalToAdd) or 0)
		if remaining < 1 then
			return
		end
		while remaining > 0 do
			local mergedAny = false
			for _, jt in pairs(inv) do
				if type(jt) == "table" and jt.itemId == itemId then
					local cur = math.floor(tonumber(jt.count) or 1)
					local room = maxStack - cur
					if room > 0 then
						local take = math.min(room, remaining)
						jt.count = cur + take
						remaining = remaining - take
						mergedAny = true
						break
					end
				end
			end
			if remaining < 1 then
				break
			end
			if not mergedAny then
				local chunk = math.min(maxStack, remaining)
				inv[HttpService:GenerateGUID(false)] = { itemId = itemId, count = chunk }
				remaining = remaining - chunk
			end
		end
	end

	local function migrateLegacyT1ScrollStacks(inv)
		if type(inv) ~= "table" then
			return
		end
		local armorAdd = 0
		for _, it in pairs(inv) do
			if type(it) == "table" and it.itemId == "T1Scroll" then
				armorAdd = armorAdd + math.floor(tonumber(it.count) or 1)
				it.itemId = "T1WeaponScroll"
			end
		end
		if armorAdd > 0 then
			grantStackableCountToInv(inv, "T1ArmorScroll", armorAdd)
		end
	end

	migrateLegacyT1ScrollStacks(loaded.inventory)
	migrateLegacyT1ScrollStacks(loaded.chestInventory)

	local function migrateLegacyT1ProtectionScrollStacks(inv)
		if type(inv) ~= "table" then
			return
		end
		local armorAdd = 0
		for _, it in pairs(inv) do
			if type(it) == "table" and it.itemId == "T1ProtectionScroll" then
				armorAdd = armorAdd + math.floor(tonumber(it.count) or 1)
				it.itemId = "T1WeaponProtectionScroll"
			end
		end
		if armorAdd > 0 then
			grantStackableCountToInv(inv, "T1ArmorProtectionScroll", armorAdd)
		end
	end

	migrateLegacyT1ProtectionScrollStacks(loaded.inventory)
	migrateLegacyT1ProtectionScrollStacks(loaded.chestInventory)

	local function normalizeOwnedItems(inv)
		if type(inv) ~= "table" then
			return
		end
		for _, it in pairs(inv) do
			if type(it) == "table" then
				if (type(it.itemId) ~= "string" or it.itemId == "") and type(it.name) == "string" then
					local inferred = LEGACY_DISPLAY_NAME_TO_ITEM_ID[it.name]
					if type(inferred) == "string" and inferred ~= "" then
						it.itemId = inferred
					end
				end
				if type(it.count) ~= "number" or it.count < 1 or it.count ~= math.floor(it.count) then
					it.count = 1
				end
			end
		end
	end

	normalizeOwnedItems(loaded.inventory)
	normalizeOwnedItems(loaded.chestInventory)
	return loaded
end

return DungeonProfileTypes
