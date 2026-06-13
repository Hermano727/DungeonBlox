-- DataSchema
-- Single source of truth for the player profile shape. PlayerDataManager and
-- anything that touches sessionData should go through Default() or Reconcile()
-- so new fields never blow up old saves.

local DataSchema = {}

DataSchema.Version = 1
DataSchema.TierCount = 5

function DataSchema.Default()
	local progression = {}
	for tier = 1, DataSchema.TierCount do
		progression["Tier" .. tier .. "Kills"] = 0
		progression["Tier" .. tier .. "Score"] = 0
	end

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
