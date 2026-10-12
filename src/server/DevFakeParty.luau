--[[
	DevFakeParty -- ServerScriptService. F8 Dungeon tab: stand-in party members for testing the
	dungeon clear show alone. A fake has a name, a list of drops (by rarity) and a Mythic outcome
	(real odds / always win / always lose). When the dev's instance is cleared, DungeonClearSequence
	adds each fake as one more brazier: their score pours in, their kept drops join the Reliquary
	Ring, and they are one more stop on the Mythic relic's hop.

	A fake is theatre only. It has no Player and no profile, so nothing is granted, saved, scrapped
	into anyone's bag, or fed into LootPityService / the Journal; the Mythic broadcast skips it (it
	only announces real Players).

	Why this cannot leak into real play:
	  * Server-only module; the state is local tables keyed by the dev's UserId. Nothing replicates.
	  * Every entry point re-checks DevRoster.IsDev. Collect() only reads the fakes of devs who are
	    members of the instance being cleared, so a fake can never appear in someone else's run.
	  * Drops are limited to Common..Legendary; the party total is capped by DungeonClearSequence.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local DevRoster = require(ReplicatedStorage:WaitForChild("DevRoster"))
local PityConfig = require(ReplicatedStorage:WaitForChild("LootPityConfig"))
local ClearConfig = require(ReplicatedStorage:WaitForChild("DungeonClearConfig"))
local ItemGenerator = require(ServerScriptService:WaitForChild("ItemGenerator"))

local DevFakeParty = {}

local MAX_FAKES = 3
local MAX_DROPS = 30
local MAX_PER_ADD = 20
local FAKE_SCORE = 40      -- what the fake's brazier counts up to
local FAKE_ID_BASE = 4e12  -- fake "userIds" sit far above any real one, unique per dev and slot

local ALLOWED = {}
for _, rarity in ipairs(PityConfig.RARITIES) do ALLOWED[rarity] = true end

local state = {} -- [devUserId] = { { name, mythic, drops = { rarity, ... } }, ... }

local function authorised(player)
	return typeof(player) == "Instance" and player:IsA("Player") and DevRoster.IsDev(player)
end

local function fakesOf(player)
	local list = state[player.UserId]
	if not list then
		list = {}
		state[player.UserId] = list
	end
	return list
end

-- The state as the Dungeon tab shows it.
local function describe(player)
	local out = {}
	for _, fake in ipairs(state[player.UserId] or {}) do
		local counts, rows = {}, {}
		for _, rarity in ipairs(fake.drops) do counts[rarity] = (counts[rarity] or 0) + 1 end
		for _, rarity in ipairs(PityConfig.RARITIES) do
			if counts[rarity] then table.insert(rows, { rarity = rarity, count = counts[rarity] }) end
		end
		table.insert(out, { name = fake.name, mythic = fake.mythic, drops = rows })
	end
	return out
end

-- One entry point for the remote: returns { ok, fakes } or { ok = false, error }.
function DevFakeParty.Act(player, action, index, a, b)
	if not authorised(player) then return { ok = false, error = "unauthorized" } end
	local list = fakesOf(player)
	if action == "add" then
		if #list >= MAX_FAKES then return { ok = false, error = "max_fakes" } end
		-- Lowest free name number, so removing "Dummy 1" and adding again gives "Dummy 1".
		local taken = {}
		for _, fake in ipairs(list) do taken[fake.name] = true end
		local n = 1
		while taken["Dummy " .. n] do n += 1 end
		table.insert(list, { name = "Dummy " .. n, mythic = nil, drops = {} })
	elseif action ~= "get" then
		local fake = type(index) == "number" and list[math.floor(index)] or nil
		if not fake then return { ok = false, error = "bad_fake" } end
		if action == "remove" then
			table.remove(list, math.floor(index))
		elseif action == "clearDrops" then
			table.clear(fake.drops)
		elseif action == "drop" then
			if type(a) ~= "string" or not ALLOWED[a] then return { ok = false, error = "bad_rarity" } end
			local count = math.clamp(math.floor(tonumber(b) or 1), 1, MAX_PER_ADD)
			if #fake.drops + count > MAX_DROPS then return { ok = false, error = "queue_full" } end
			for _ = 1, count do table.insert(fake.drops, a) end
		elseif action == "mythic" then
			fake.mythic = (a == "win" or a == "loss") and a or nil
		else
			return { ok = false, error = "bad_action" }
		end
	end
	return { ok = true, fakes = describe(player) }
end

-- Called by DungeonClearSequence.Play for the instance being cleared. One entry per fake of every
-- DevRoster member of the instance:
--   { userId, name, score, scrap, kept = { drop, ... }, mythic }
-- `kept` is what the Reliquary Ring reveals (the same fields EndRunFor's `granted` list carries);
-- `scrap` is what the real auto-scrap rule would have burned off for this tier.
function DevFakeParty.Collect(instance)
	local out = {}
	local tier = math.clamp(math.floor(tonumber(instance and instance.numericTier) or 1), 1, 5)
	for _, uid in ipairs(instance and instance.memberUserIds or {}) do
		local dev = Players:GetPlayerByUserId(uid)
		if dev and instance.members and instance.members[uid] and authorised(dev) then
			local ProfileService = require(ServerScriptService:WaitForChild("ProfileService"))
			for slot, fake in ipairs(state[uid] or {}) do
				local entry = {
					userId = FAKE_ID_BASE + uid * 10 + slot,
					name = fake.name,
					score = FAKE_SCORE,
					scrap = 0,
					kept = {},
					mythic = fake.mythic,
				}
				for _, rarity in ipairs(fake.drops) do
					local ok, item = pcall(ItemGenerator.generate, { tier = tier, rarity = rarity, level = tier * 5 })
					local okTpl, template = false, nil
					if ok and item then okTpl, template = pcall(function() return item:toGrantTemplate() end) end
					if okTpl and template then
						if ClearConfig.IsAutoScrapped(template.tier or tier, template.rarity) then
							local _, qty = ProfileService.SalvageYield(template)
							entry.scrap += qty
						else
							table.insert(entry.kept, {
								name = template.name, rarity = template.rarity, level = template.level,
								tier = template.tier, type = template.type, itemId = template.itemId,
								equipSlot = template.equipSlot, tags = template.tags,
							})
						end
					else
						warn("[DevFakeParty] generate failed for " .. tostring(rarity))
					end
				end
				table.insert(out, entry)
			end
		end
	end
	return out
end

Players.PlayerRemoving:Connect(function(player)
	state[player.UserId] = nil
end)

return DevFakeParty
