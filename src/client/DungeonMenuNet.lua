--[[
  Client networking for Dungeon profile snapshots + equip/unequip requests.
  All authoritative state arrives via DungeonProfilePush; never mutate locally except cache.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))
local push = ReplicatedStorage:WaitForChild("DungeonProfilePush")
local rfEquip = ReplicatedStorage:WaitForChild("DungeonEquipItem")
local rfUnequip = ReplicatedStorage:WaitForChild("DungeonUnequipItem")
local rfSync = ReplicatedStorage:WaitForChild("DungeonProfileRequestSync")
local rfInventoryAct = ReplicatedStorage:WaitForChild("DungeonInventoryAct")

local DungeonMenuNet = {}

local lastSnapshot = nil
local listener = nil
local snapshotListeners = {}

local equipDedupeKey = nil
local equipDedupeAt = 0
local unequipDedupeKey = nil
local unequipDedupeAt = 0
local RF_DEDUPE = 0.18

local function fireSnapshotListeners(payload)
	for _, fn in ipairs(snapshotListeners) do
		task.defer(fn, payload)
	end
	if listener then
		listener(payload)
	end
end

local function readSeq(snapshot)
	if type(snapshot) ~= "table" then
		return 0
	end
	local s = snapshot._seq
	if type(s) == "number" and s == s and s > 0 then
		return s
	end
	return 0
end

local function snapshotIsStale(incoming)
	if type(incoming) ~= "table" then
		return true
	end
	local inc = readSeq(incoming)
	if inc == 0 then
		return false
	end
	local cur = readSeq(lastSnapshot)
	if cur == 0 then
		return false
	end
	return inc < cur
end

local function applySnapshotPayload(incoming)
	if type(incoming) ~= "table" or incoming.profile == nil then
		return false
	end
	if snapshotIsStale(incoming) then
		return false
	end
	lastSnapshot = incoming
	fireSnapshotListeners(incoming)
	return true
end

local function tryApplyChestUnlockPatch(patch)
	if type(patch) ~= "table" or patch.chestUnlockedRows == nil then
		return false
	end
	if snapshotIsStale(patch) then
		return false
	end
	if type(lastSnapshot) ~= "table" or type(lastSnapshot.profile) ~= "table" then
		DungeonMenuNet.requestSync()
	end
	if type(lastSnapshot) ~= "table" or type(lastSnapshot.profile) ~= "table" then
		return false
	end
	local p = lastSnapshot.profile
	local nUr = math.floor(tonumber(patch.chestUnlockedRows) or 1)
	local curUr = math.floor(tonumber(p.chestUnlockedRows) or 1)
	if curUr >= nUr then
		if type(patch._seq) == "number" and patch._seq == patch._seq and patch._seq > 0 then
			local curSeq = readSeq(lastSnapshot)
			if patch._seq > curSeq then
				lastSnapshot._seq = patch._seq
			end
		end
		fireSnapshotListeners(lastSnapshot)
		return true
	end
	p.chestUnlockedRows = patch.chestUnlockedRows
	if type(patch.currencies) == "table" then
		p.currencies = p.currencies or {}
		for k, v in pairs(patch.currencies) do
			p.currencies[k] = v
		end
	end
	if type(patch._seq) == "number" and patch._seq == patch._seq and patch._seq > 0 then
		lastSnapshot._seq = patch._seq
	end
	fireSnapshotListeners(lastSnapshot)
	return true
end

-- Server already confirmed this row is unlocked; ensure local cache reflects it even if the RF
-- payload or push ordering failed to merge (Bank UI reads only getLastSnapshot()).
local function forceApplyChestUnlockRow(row)
	if type(row) ~= "number" or row ~= math.floor(row) or row < 2 then
		return
	end
	local maxR = Types.CHEST_GRID_ROWS
	if row > maxR then
		return
	end
	if type(lastSnapshot) ~= "table" or type(lastSnapshot.profile) ~= "table" then
		DungeonMenuNet.requestSync()
	end
	if type(lastSnapshot) ~= "table" or type(lastSnapshot.profile) ~= "table" then
		return
	end
	local p = lastSnapshot.profile
	local cur = math.clamp(math.floor(tonumber(p.chestUnlockedRows) or 1), 1, maxR)
	p.chestUnlockedRows = math.clamp(math.max(cur, row), 1, maxR)
	fireSnapshotListeners(lastSnapshot)
end

function DungeonMenuNet.setListener(cb)
	listener = cb
end

function DungeonMenuNet.addSnapshotListener(fn)
	if type(fn) ~= "function" then
		return function() end
	end
	table.insert(snapshotListeners, fn)
	task.defer(fn, lastSnapshot)
	return function()
		for i = #snapshotListeners, 1, -1 do
			if snapshotListeners[i] == fn then
				table.remove(snapshotListeners, i)
			end
		end
	end
end

function DungeonMenuNet.getLastSnapshot()
	return lastSnapshot
end

function DungeonMenuNet.requestSync()
	if not rfSync or not rfSync:IsA("RemoteFunction") then
		return false, false
	end
	local ok, res = pcall(function()
		return rfSync:InvokeServer()
	end)
	if not ok then
		warn("[DungeonMenuNet] requestSync InvokeServer failed:", res)
		return false, false
	end
	local applied = applySnapshotPayload(res)
	return true, applied
end

local started = false

function DungeonMenuNet.start()
	if started then
		return
	end
	started = true
	push.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		applySnapshotPayload(payload)
	end)

	-- If we subscribed after the server's first PushProfile, ask for a fresh snapshot.
	task.defer(function()
		DungeonMenuNet.requestSync()
	end)
end

function DungeonMenuNet.requestEquip(itemUuid, equipOpts)
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return
	end
	local sec = (type(equipOpts) == "table" and equipOpts.weaponBagSecondary == true) and 1 or 0
	local dk = itemUuid .. "\0" .. tostring(sec)
	local now = os.clock()
	if equipDedupeKey == dk and now - equipDedupeAt < RF_DEDUPE then
		return
	end
	equipDedupeKey = dk
	equipDedupeAt = now
	if rfEquip and rfEquip:IsA("RemoteFunction") then
		local ok, a, b = pcall(function()
			return rfEquip:InvokeServer(itemUuid, equipOpts)
		end)
		if not ok then
			warn("[DungeonMenuNet] requestEquip InvokeServer failed:", a)
		elseif a == false and b then
			warn("[DungeonMenuNet] requestEquip failed:", b)
		end
	elseif rfEquip and rfEquip:IsA("RemoteEvent") then
		rfEquip:FireServer(itemUuid)
	end
end

function DungeonMenuNet.requestUnequip(slot)
	if type(slot) ~= "string" or slot == "" then
		return
	end
	local now = os.clock()
	if unequipDedupeKey == slot and now - unequipDedupeAt < RF_DEDUPE then
		return
	end
	unequipDedupeKey = slot
	unequipDedupeAt = now
	if rfUnequip and rfUnequip:IsA("RemoteFunction") then
		local ok, a, b = pcall(function()
			return rfUnequip:InvokeServer(slot)
		end)
		if not ok then
			warn("[DungeonMenuNet] requestUnequip InvokeServer failed:", a)
		elseif a == false and b then
			warn("[DungeonMenuNet] requestUnequip failed:", b)
		end
	elseif rfUnequip and rfUnequip:IsA("RemoteEvent") then
		rfUnequip:FireServer(slot)
	end
end

function DungeonMenuNet.requestInventoryAct(act)
	if not rfInventoryAct or not rfInventoryAct:IsA("RemoteFunction") then
		return false, "no_rf"
	end
	local ok, a, b, c = pcall(function()
		return rfInventoryAct:InvokeServer(act)
	end)
	if not ok then
		warn("[DungeonMenuNet] requestInventoryAct InvokeServer failed:", a)
		return false, "invoke_failed"
	end
	local err = nil
	if a == true then
		local applied = false
		if type(act) == "table" and (act.kind == "ApplyEnchantScroll" or act.kind == "ApplyProtectionScroll" or act.kind == "ApplyCraftingOrb") then
			-- RF return can race DungeonProfilePush on the client (yielding InvokeServer still processes pushes).
			-- Stale _seq then drops the RF payload; always pull one authoritative snapshot after scroll.
			local syncOk, syncApplied = DungeonMenuNet.requestSync()
			applied = syncApplied
			if syncOk and syncApplied and type(act.targetUuid) == "string" then
				local p = lastSnapshot and lastSnapshot.profile
				local it = p and p.inventory and p.inventory[act.targetUuid]
				if type(it) == "table" then
					print(("[EnchantTrace] CLT merged target=%s enchant=%d snap_seq=%s"):format(
						act.targetUuid,
						math.floor(tonumber(it.enchantLevel) or 0),
						tostring(lastSnapshot and lastSnapshot._seq)
					))
				end
			end
			if not syncOk then
				warn("[DungeonMenuNet][EnchantTrace] scroll ok but requestSync failed")
			elseif not syncApplied then
				warn("[DungeonMenuNet][EnchantTrace] scroll sync merge rejected; local _seq=", readSeq(lastSnapshot))
				task.defer(function()
					DungeonMenuNet.requestSync()
				end)
			end
		else
			if type(b) == "table" and b.profile ~= nil then
				applied = applySnapshotPayload(b)
			elseif type(c) == "table" and c.profile ~= nil then
				applied = applySnapshotPayload(c)
			end
			if not applied then
				if tryApplyChestUnlockPatch(b) then
					applied = true
				elseif tryApplyChestUnlockPatch(c) then
					applied = true
				end
			end
		end
		if type(act) == "table" and act.kind == "ChestUnlockRow" and type(act.row) == "number" then
			forceApplyChestUnlockRow(act.row)
		end
	elseif a == false then
		err = b
	end
	return a, err
end

return DungeonMenuNet
