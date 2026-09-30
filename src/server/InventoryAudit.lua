--[[
	InventoryAudit -- detects and records "wipe" events: a player's items vanishing in bulk
	for no sanctioned reason. The Roblox version of "log the incident + page someone".

	What counts as a wipe (checked every CHECK_INTERVAL and right before every save):
	  items_removed   >= BULK_THRESHOLD owned items (and >= BULK_FRACTION of them) gone at once
	  slots_lost      >= BULK_THRESHOLD items still OWNED but no longer in any bag/hotbar/equip
	                  slot (invisible to the player: looks exactly like a wipe from their side)
	  orphans_on_load the saved profile came back with owned items in no slot (ProfileService's
	                  cold load re-homes them; this records that it had to)

	How a death is told apart: DeathLootService calls Sanction(player, "death") right before
	its drop, so a bulk removal inside that window is logged as an expected event, not an
	alert. Anything else that legitimately removes many items at once must Sanction too.

	Breadcrumbs: Note(player, text) keeps the last few things that happened to the player
	(dungeon entered, run cashed out, sent home, died...). Every report carries them, so a
	wipe arrives with the story of how it happened.

	Where a report goes:
	  1. DataStore "InventoryAudit_v1": the full record under its own key, including the
	     complete item tables that went missing (enough to restore them by hand), plus a
	     per-player index "user_<userId>" of that player's recent event keys.
	  2. The server log as "[WIPE-ALERT]" (warn): searchable in the Creator Dashboard logs.
	  3. Every online dev (DevRoster), in every server (MessagingService), as a centre flash.
	Studio sessions without DataStore access still get 2 and 3.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevRoster = require(ReplicatedStorage:WaitForChild("DevRoster"))

local InventoryAudit = {}

local CHECK_INTERVAL = 3
local BULK_THRESHOLD = 5
local BULK_FRACTION = 0.5
local SANCTION_SECONDS = 15
local NOTE_LIMIT = 20
local INDEX_LIMIT = 50
local LOST_ITEM_LIMIT = 80
local STORE_NAME = "InventoryAudit_v1"
local TOPIC = "InventoryWipeAlert"

local store
pcall(function() store = DataStoreService:GetDataStore(STORE_NAME) end)

local observed = {} -- [player] = { owned = {uuid=item}, visible = {uuid=true}, ownedCount, visibleCount }
local sanctions = {} -- [player] = { reason, untilClock }
local notes = {} -- [player] = { "12:03:04 text", ... }

local function slotUuid(slots, i)
	if type(slots) ~= "table" then return nil end
	local v = slots[i]
	if v == nil then v = slots[tostring(i)] end
	if type(v) == "string" and v ~= "" then return v end
	return nil
end

-- What the player can SEE: every uuid a bag / hotbar / equip slot points at.
local function visibleSet(profile)
	local set = {}
	for i = 1, 60 do
		local b = slotUuid(profile.bagSlots, i)
		if b then set[b] = true end
	end
	for i = 1, 9 do
		local h = slotUuid(profile.hotbar, i)
		if h then set[h] = true end
	end
	if type(profile.equipped) == "table" then
		for _, uuid in pairs(profile.equipped) do
			if type(uuid) == "string" and uuid ~= "" then set[uuid] = true end
		end
	end
	return set
end

local function summarize(uuid, item)
	return {
		uuid = uuid,
		itemId = type(item) == "table" and item.itemId or nil,
		name = type(item) == "table" and (item.name or item.itemId) or nil,
		rarity = type(item) == "table" and item.rarity or nil,
		tier = type(item) == "table" and item.tier or nil,
		count = type(item) == "table" and item.count or nil,
	}
end

local function snapshotOf(profile)
	local owned, ownedCount = {}, 0
	if type(profile.inventory) == "table" then
		for uuid, item in pairs(profile.inventory) do
			if type(uuid) == "string" and type(item) == "table" then
				owned[uuid] = item
				ownedCount += 1
			end
		end
	end
	local visible, visibleCount = {}, 0
	for uuid in pairs(visibleSet(profile)) do
		if owned[uuid] then visible[uuid] = true; visibleCount += 1 end
	end
	return { owned = owned, visible = visible, ownedCount = ownedCount, visibleCount = visibleCount }
end

local function sanctionFor(player)
	local s = sanctions[player]
	if s and os.clock() <= s.untilClock then return s.reason end
	return nil
end

local function notifyDevs(text)
	for _, p in ipairs(Players:GetPlayers()) do
		if DevRoster.IsDev(p) then
			local ge = ReplicatedStorage:FindFirstChild("GameEvents")
			local ev = ge and ge:FindFirstChild("CenterFlashNotify")
			if ev then pcall(ev.FireClient, ev, p, text) end
		end
	end
end

local function persist(key, record)
	if not store then return end
	task.spawn(function()
		local ok, err = pcall(store.SetAsync, store, key, record)
		if not ok then warn("[InventoryAudit] could not store " .. key .. ": " .. tostring(err)) end
		pcall(store.UpdateAsync, store, "user_" .. tostring(record.userId), function(old)
			local list = type(old) == "table" and old or {}
			table.insert(list, 1, key)
			while #list > INDEX_LIMIT do table.remove(list) end
			return list
		end)
	end)
end

-- kind: "items_removed" | "slots_lost" | "orphans_on_load" | any other label.
-- details: extra fields merged into the record (counts, lost items, ...).
function InventoryAudit.Report(player, kind, details, severity)
	severity = severity or "SEV2"
	local record = {
		kind = kind,
		severity = severity,
		userId = player.UserId,
		name = player.Name,
		at = os.time(),
		placeId = game.PlaceId,
		jobId = game.JobId,
		sanction = sanctionFor(player),
		notes = table.clone(notes[player] or {}),
	}
	for k, v in pairs(details or {}) do record[k] = v end
	local key = ("%d_%d_%s"):format(player.UserId, record.at, HttpService:GenerateGUID(false):sub(1, 8))
	record.key = key
	persist(key, record)

	local summary = ("[WIPE-ALERT] %s %s: %s (key %s) lost=%s owned %s->%s visible %s->%s"):format(
		severity, kind, player.Name, key, tostring(record.lostCount or "?"),
		tostring(record.ownedBefore or "?"), tostring(record.ownedAfter or "?"),
		tostring(record.visibleBefore or "?"), tostring(record.visibleAfter or "?"))
	warn(summary)
	local flash = ("Wipe alert: %s, %s (%s items)"):format(player.Name, kind, tostring(record.lostCount or "?"))
	notifyDevs(flash)
	task.spawn(function() pcall(MessagingService.PublishAsync, MessagingService, TOPIC, { text = flash, jobId = game.JobId }) end)
	return key
end

-- Compare against the last observation; report bulk losses. `context` is a short label
-- ("tick", "save", "load") stored on the record.
function InventoryAudit.Observe(player, profile, context)
	if typeof(player) ~= "Instance" or type(profile) ~= "table" or profile.IsEphemeral then return end
	local now = snapshotOf(profile)
	local before = observed[player]
	observed[player] = now
	if not before then return end

	local lost, lostItems = {}, {}
	for uuid, item in pairs(before.owned) do
		if not now.owned[uuid] then
			if #lost < LOST_ITEM_LIMIT then
				table.insert(lost, summarize(uuid, item))
				lostItems[uuid] = item
			end
		end
	end
	local hidden = {}
	for uuid in pairs(before.visible) do
		if now.owned[uuid] and not now.visible[uuid] and #hidden < LOST_ITEM_LIMIT then
			table.insert(hidden, summarize(uuid, now.owned[uuid]))
		end
	end

	local base = {
		context = context,
		ownedBefore = before.ownedCount, ownedAfter = now.ownedCount,
		visibleBefore = before.visibleCount, visibleAfter = now.visibleCount,
	}
	local lostCount = before.ownedCount - now.ownedCount
	if #lost >= BULK_THRESHOLD and lostCount >= math.ceil(before.ownedCount * BULK_FRACTION) then
		local sanctioned = sanctionFor(player)
		base.lostCount = #lost
		base.lost = lost
		base.lostItems = lostItems -- full item tables: enough to restore by hand
		if sanctioned then
			-- Expected (a death drop): kept as a low-severity record, no alert.
			base.expected = sanctioned
			local record = table.clone(base)
			InventoryAudit.Note(player, ("lost %d items (%s)"):format(#lost, sanctioned))
			if store then
				record.kind = "expected_removal"; record.severity = "INFO"; record.userId = player.UserId
				record.name = player.Name; record.at = os.time(); record.notes = table.clone(notes[player] or {})
				persist(("%d_%d_%s"):format(player.UserId, record.at, HttpService:GenerateGUID(false):sub(1, 8)), record)
			end
		else
			InventoryAudit.Report(player, "items_removed", base, "SEV1")
		end
	end
	if #hidden >= BULK_THRESHOLD then
		local d = table.clone(base)
		d.lostCount = #hidden
		d.hidden = hidden
		InventoryAudit.Report(player, "slots_lost", d, "SEV2")
	end
end

-- Mark a bulk removal as expected for the next `seconds` (death drop, etc.).
function InventoryAudit.Sanction(player, reason, seconds)
	sanctions[player] = { reason = tostring(reason), untilClock = os.clock() + (seconds or SANCTION_SECONDS) }
	InventoryAudit.Note(player, "expected: " .. tostring(reason))
end

-- A breadcrumb for this player's next report.
function InventoryAudit.Note(player, text)
	if typeof(player) ~= "Instance" then return end
	local list = notes[player]
	if not list then list = {}; notes[player] = list end
	table.insert(list, os.date("!%H:%M:%S") .. " " .. tostring(text))
	while #list > NOTE_LIMIT do table.remove(list, 1) end
end

-- Starts the periodic check. getProfile(player) -> the live session profile or nil.
local started = false
function InventoryAudit.Start(getProfile)
	if started then return end
	started = true
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, profile = pcall(getProfile, player)
				if ok and type(profile) == "table" then
					local okObs, err = pcall(InventoryAudit.Observe, player, profile, "tick")
					if not okObs then warn("[InventoryAudit] observe failed: " .. tostring(err)) end
				end
			end
		end
	end)
	-- Alerts raised on other servers reach the devs here too.
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local data = message and message.Data
			if type(data) == "table" and data.jobId ~= game.JobId and type(data.text) == "string" then
				notifyDevs(data.text)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		task.delay(30, function()
			observed[player] = nil
			sanctions[player] = nil
			notes[player] = nil
		end)
	end)
end

-- Admin reading: the most recent event keys for a user, and one record.
function InventoryAudit.ListFor(userId)
	if not store then return {} end
	local ok, list = pcall(store.GetAsync, store, "user_" .. tostring(userId))
	return ok and type(list) == "table" and list or {}
end

function InventoryAudit.Get(key)
	if not store then return nil end
	local ok, record = pcall(store.GetAsync, store, key)
	return ok and record or nil
end

return InventoryAudit
