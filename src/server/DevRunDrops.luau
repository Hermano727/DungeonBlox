--[[
	DevRunDrops -- ServerScriptService. F8 Dungeon tab: extra drops of a chosen rarity for YOUR
	next dungeon clear, so the clear show (Pyres, Reliquary Ring) can be tested without waiting on
	real odds.

	Why this cannot leak into real play:
	  * Server-only module. The queue is a local table; no remote, attribute or profile field holds
	    or reveals it, and nothing replicates it.
	  * Every entry point (Add / Clear / List / Take) re-checks DevRoster.IsDev on the server, so a
	    non-dev who somehow reached the remote, or whose roster entry was removed, gets nothing.
	  * Take is called from DungeonRunService.EndRunFor only, for the player being cashed out, and
	    only on a "cleared" run. It never touches LootPityService (no dry streaks move), the run's
	    rolled rarities (summary.rarities, which feed the Journal's luck stats) or the score.
	  * The items are granted with the DEV_TOOL origin, so they are stamped as dev items in the
	    durable item serial and can be audited out (docs/item-identity-and-ranges.md).
	  * Limited to Common..Legendary: Mythic has its own path (MythicItemBuilder / force win).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local DevRoster = require(ReplicatedStorage:WaitForChild("DevRoster"))
local PityConfig = require(ReplicatedStorage:WaitForChild("LootPityConfig"))
local ItemGenerator = require(ServerScriptService:WaitForChild("ItemGenerator"))

local DevRunDrops = {}

local MAX_QUEUED = 30   -- items waiting for the next clear
local MAX_PER_ADD = 20

local ALLOWED = {}
for _, rarity in ipairs(PityConfig.RARITIES) do ALLOWED[rarity] = true end

local queues = {} -- [userId] = { "Rare", "Rare", "Epic", ... }

local function authorised(player)
	return typeof(player) == "Instance" and player:IsA("Player") and DevRoster.IsDev(player)
end

-- Counts per rarity, in the ladder's order: { { rarity = "Rare", count = 2 }, ... }
function DevRunDrops.List(player)
	if not authorised(player) then return {} end
	local counts = {}
	for _, rarity in ipairs(queues[player.UserId] or {}) do counts[rarity] = (counts[rarity] or 0) + 1 end
	local out = {}
	for _, rarity in ipairs(PityConfig.RARITIES) do
		if counts[rarity] then table.insert(out, { rarity = rarity, count = counts[rarity] }) end
	end
	return out
end

-- Returns ok, errorCode.
function DevRunDrops.Add(player, rarity, count)
	if not authorised(player) then return false, "unauthorized" end
	if type(rarity) ~= "string" or not ALLOWED[rarity] then return false, "bad_rarity" end
	count = math.clamp(math.floor(tonumber(count) or 1), 1, MAX_PER_ADD)
	local queue = queues[player.UserId] or {}
	if #queue + count > MAX_QUEUED then return false, "queue_full" end
	for _ = 1, count do table.insert(queue, rarity) end
	queues[player.UserId] = queue
	return true
end

function DevRunDrops.Clear(player)
	if not authorised(player) then return false, "unauthorized" end
	queues[player.UserId] = nil
	return true
end

-- Called by DungeonRunService.EndRunFor for a CLEARED run: empties the player's queue and returns
-- the generated items (ItemClass objects, like LootPityService.GenerateItems makes). Empty for
-- anyone who is not a dev or has nothing queued.
function DevRunDrops.Take(player, tier, level)
	if not authorised(player) then
		queues[player and player.UserId or 0] = nil -- a non-dev never keeps a queue
		return {}
	end
	local queue = queues[player.UserId]
	queues[player.UserId] = nil
	local items = {}
	for _, rarity in ipairs(queue or {}) do
		local ok, item = pcall(ItemGenerator.generate, { tier = tier, rarity = rarity, level = level })
		if ok and item then
			table.insert(items, item)
		else
			warn("[DevRunDrops] generate failed for " .. rarity .. ": " .. tostring(item))
		end
	end
	if #items > 0 then
		print(("[DevRunDrops] %s: %d dev drop(s) added to this clear"):format(player.Name, #items))
	end
	return items
end

Players.PlayerRemoving:Connect(function(player)
	queues[player.UserId] = nil
end)

return DevRunDrops
