--!strict
-- DerivedStatsView
-- Pure function that turns a DungeonMenuNet snapshot (profile + server-
-- derived stats) into the flat, pre-formatted string map the character-sheet
-- UIs render. StatsOverlayClient (the imperative Character-tab overlay) and
-- StatsPanel (the React InventoryHud panel) each computed this exact same
-- set of rows independently -- same fields, same formatting, same attribute
-- sum over equipped gear. This is the single source of truth for that
-- computation so the two views can't quietly drift out of sync (e.g. one
-- rounding HP Regen differently than the other after a balance tweak).
--
-- Returns a table keyed by row id ("hp", "armor", "hpReg", ...), or an empty
-- table if the snapshot isn't ready yet. Callers should fall back to "-" /
-- "--" for any missing key (both existing callers already do this).

local DerivedStatsView = {}

-- Equip slots that contribute the four core attributes (STR/INT/DEX/VIT).
local ATTRIBUTE_SLOTS = { "Helm", "Chest", "Legs", "Boots" }
local ATTRIBUTE_KEYS = { "str", "int", "dex", "vit" }

function DerivedStatsView.Compute(snap: any): { [string]: string }
	local values: { [string]: string } = {}
	if not snap then
		return values
	end
	local profile, derived = snap.profile, snap.derived
	if not (profile and derived) then
		return values
	end

	local dc = derived.combat or {}
	values.hp = string.format("%d / %d", math.floor(dc.hp or 0), math.floor(dc.maxHp or 0))
	values.armor = tostring(math.floor(dc.armor or 0))
	values.hpReg = string.format("%.1f / s", dc.hpRegen or 0)
	values.enReg = string.format("%.1f / s", dc.energyRegen or 0)

	local inv, eq = profile.inventory or {}, profile.equipped or {}
	local tot = { str = 0, int = 0, dex = 0, vit = 0 }
	for _, slot in ipairs(ATTRIBUTE_SLOTS) do
		local uuid = eq[slot]
		if type(uuid) == "string" and uuid ~= "" then
			local it = inv[uuid]
			if type(it) == "table" and type(it.subStats) == "table" then
				for _, k in ipairs(ATTRIBUTE_KEYS) do
					tot[k] = tot[k] + (tonumber(it.subStats[k]) or 0)
				end
			end
		end
	end
	values.str, values.int, values.dex, values.vit =
		tostring(tot.str), tostring(tot.int), tostring(tot.dex), tostring(tot.vit)

	local sc = (profile.stats and profile.stats.combat) or {}
	local dm, df = derived.mining or {}, derived.fishing or {}
	values.combat = "Lv. " .. tostring(sc.level or 1)
	values.mining = "Lv. " .. tostring(dm.miningLevel or 1)
	values.fishing = "Lv. " .. tostring(df.fishingLevel or 1)
	values.coins = tostring(math.floor(tonumber(profile.currencies and profile.currencies.Coins) or 0))

	-- Extra row StatsOverlayClient's larger character sheet shows beyond
	-- StatsPanel's row set; harmless for callers (StatsPanel) that ignore it.
	values.inRaid = (profile.flags and profile.flags.inRaid) and "Yes" or "No"

	return values
end

return DerivedStatsView
