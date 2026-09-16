-- DataSchema
-- Single source of truth for the player profile shape. PlayerDataManager and
-- anything that touches sessionData should go through Default() or Reconcile()
-- so new fields never blow up old saves.
--
-- ============================================================================
-- SECOND PROFILE SYSTEM -- read this before touching anything in here.
-- ============================================================================
-- DungeonBlox actually runs two parallel player-profile systems side by side:
--   1. ProfileService + ProfileTypes (shared/ProfileTypes.lua)
--      -- the CURRENT system. Owns currencies, equipped gear, the bag/inventory
--      shown in the live UI (InventoryHud -> DungeonMenuUI/DungeonMenuNet), and
--      skills. This is what new features should build on.
--   2. This schema (DataSchema + PlayerDataManager + InventoryService) -- the
--      OLDER system that predates it. It is NOT dead code, so do not delete it:
--        * HP / MaxHP / Armor and the RPG stat block (Vitality etc.) below are
--          the ONLY place those values live. ProfileTypes has no
--          equivalent fields. DamageService.ApplyToPlayer reads Combat.Armor
--          from THIS profile to compute damage mitigation for every hit, both
--          PvE and PvP (see src/server/DamageService.lua).
--        * Progression (Tier1..5 Kills/Score) is written every kill by
--          DamageService but, as of this audit, nothing reads it back anywhere
--          in src/ -- it accumulates in the DataStore unused. Left in place
--          rather than removed since DamageService is outside this audit's
--          scope and the write path is cheap; flag for a real read-side
--          decision (surface it in UI, or retire the write) later.
--        * Inventory (the slot-indexed dict below) is still mutated by
--          InventoryService.AddItem/RemoveItem, which PlayerBootstrap (starter
--          kit) and NPCService (buy/sell -- see its countLegacySlots /
--          removeItemAcrossStores helpers, which deliberately read+write BOTH
--          this Inventory AND ProfileService's inventory so items don't
--          go missing depending which store they happened to land in) still
--          call directly. It is NOT rendered by any current client UI though:
--          grep across src/client finds zero references to the
--          InventoryReplicate/InventoryRequest RemoteEvents outside
--          InventoryService.lua itself -- InventoryHud's UI tree is wired to
--          DungeonMenuNet/ProfileTypes instead. So this Inventory table
--          is a real, mutated, server-authoritative data store with no visible
--          client representation of its own.
--   KNOWN BUG (found during this audit, not fixed here -- fix belongs in
--   DamageService.lua / ProfileBootstrap.server.lua, both out of this
--   aspect's scope): the live equip UI (ProfileBootstrap-owned equip
--   RemoteFunctions, backed by ProfileService.equipped) never calls
--   InventoryService.RecomputeArmor. That function only runs from this legacy
--   path (PlayerBootstrap's starter-kit equip, and InventoryService.UseItem
--   which nothing calls anymore either). So Combat.Armor gets set once from
--   the default starter kit at spawn and then never updates again for the
--   rest of the session, even as the player equips better armor through the
--   real UI -- meaning DamageService's damage mitigation may not reflect a
--   player's actual equipped armor after the first few minutes of a session.
--   See PlayerDataManager.lua / InventoryService.lua for more detail.
-- ============================================================================

local DataSchema = {}

DataSchema.Version = 1
DataSchema.TierCount = 5

function DataSchema.Default()
	local progression = {}
	for tier = 1, DataSchema.TierCount do
		progression["Tier" .. tier .. "Kills"] = 0
		progression["Tier" .. tier .. "Score"] = 0
	end

	-- Per-rarity dry streaks for the score-driven pity system
	-- (see LootPityService). ONE pool per player, shared by overworld kills
	-- and dungeon runs -- resetting one rarity never touches the others.
	-- Without these persisted here, streaks reset every session and pity
	-- never actually accrues.
	progression.DryStreaks = {
		Common    = 0,
		Uncommon  = 0,
		Rare      = 0,
		Epic      = 0,
		Legendary = 0,
	}

	-- Loot buff multiplier feeding the core progression system. 1.0 = one
	-- score per kill. 1.1 = 10% chance of a second point, 2.5 = always two
	-- plus a 50% chance of a third.
	progression.LootBuff = 1.0

	return {
		Version = DataSchema.Version,

		-- Per tier kill counts and score totals (Tier1..Tier5).
		Progression = progression,

		-- RPG stats. Start at 0, players spend points to raise them.
		RPG = {
			Vitality     = 0,
			Strength     = 0,
			Intelligence = 0,
			Dexterity    = 0,
		},

		-- HP gets persisted so death state survives a rejoin.
		-- Armor here is the additive rating, NOT a percentage. DamageService
		-- converts it to a damage multiplier via the curve.
		Combat = {
			HP    = 100,
			MaxHP = 100,
			Armor = 0,
		},

		-- Slot-indexed dictionary. [slotIndex] = { ItemId, Count, UID? }.
		-- Nil keys mean empty slots, sparse iteration is intentional.
		Inventory = {},

		-- Equipped points at slot indices in Inventory, not at items directly.
		-- Lets us swap gear without touching item identity.
		Equipped = {
			Weapon = nil,
			Helm   = nil,
			Chest  = nil,
			Legs   = nil,
			Boots  = nil,
		},

		-- Session lock. PlayerDataManager owns this. Do not write to it from
		-- anywhere else.
		Lock = nil, -- { JobId = "...", UpdatedAt = os.time() }
	}
end

-- Deep merges a loaded profile into a fresh Default() so old saves that
-- predate a new field do not crash at runtime.
local function merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			merge(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

function DataSchema.Reconcile(loaded)
	if type(loaded) ~= "table" then
		return DataSchema.Default()
	end
	merge(loaded, DataSchema.Default())
	return loaded
end

return DataSchema
