--[[
	BuffService
	Server-authoritative timed player buffs (e.g. Food/Fish on-eat effects).

	Buff format:
		{ type = "WalkSpeedPct" | "LuckPct" | <other>, amount = number, duration = seconds }

	Consumers:
	  - EnergyServer reads getSpeedBonusPct() each tick to multiply Humanoid.WalkSpeed.
	  - LootService reads getLuckBonusPct() at gear-drop roll time.
	Unknown buff types are stored (visible to anything that polls list()) but otherwise inert.

	Buffs of the same type stack additively. There is no per-type cap.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuffService = {}

-- [userId] = array of { type=string, amount=number, expiresAt=clock }
local active = {}

local ActiveBuffsSync = nil
local RequestActiveBuffs = nil
local buffInvokeBound = false

local function ensureBuffUiRemotes()
	if ActiveBuffsSync and RequestActiveBuffs then
		return ActiveBuffsSync
	end
	local folder = ReplicatedStorage:FindFirstChild("GameEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "GameEvents"
		folder.Parent = ReplicatedStorage
	elseif not folder:IsA("Folder") then
		warn("[BuffService] ReplicatedStorage.GameEvents is not a Folder; cannot create buff UI remotes")
		return nil
	end
	local ev = folder:FindFirstChild("ActiveBuffsSync")
	if not ev or not ev:IsA("RemoteEvent") then
		if ev then
			ev:Destroy()
		end
		ev = Instance.new("RemoteEvent")
		ev.Name = "ActiveBuffsSync"
		ev.Parent = folder
	end
	ActiveBuffsSync = ev

	local rf = folder:FindFirstChild("RequestActiveBuffs")
	if not rf or not rf:IsA("RemoteFunction") then
		if rf then
			rf:Destroy()
		end
		rf = Instance.new("RemoteFunction")
		rf.Name = "RequestActiveBuffs"
		rf.Parent = folder
	end
	RequestActiveBuffs = rf
	if not buffInvokeBound then
		buffInvokeBound = true
		rf.OnServerInvoke = function(p)
			return BuffService.GetActiveBuffs(p)
		end
	end

	return ActiveBuffsSync
end

local function pushActiveBuffs(player)
	if not player or not player.Parent then
		return
	end
	local ev = ensureBuffUiRemotes()
	if not ev then
		return
	end
	ev:FireClient(player, BuffService.GetActiveBuffs(player))
end

local function getList(userId)
	local list = active[userId]
	if not list then
		list = {}
		active[userId] = list
	end
	return list
end

local function sumOfType(userId, btype)
	local list = active[userId]
	if not list then
		return 0
	end
	local now = os.clock()
	local total = 0
	for _, b in ipairs(list) do
		if b.type == btype and b.expiresAt > now then
			total = total + b.amount
		end
	end
	return total
end

function BuffService.ApplyBuffs(player, buffs)
	if not player or type(buffs) ~= "table" then
		return
	end
	local list = getList(player.UserId)
	local now = os.clock()
	for _, b in ipairs(buffs) do
		if type(b) == "table" and type(b.type) == "string" then
			local dur = math.max(0, tonumber(b.duration) or 0)
			if dur > 0 then
				table.insert(list, {
					type = b.type,
					amount = tonumber(b.amount) or 0,
					expiresAt = now + dur,
				})
			end
		end
	end
	pushActiveBuffs(player)
end

function BuffService.GetSpeedBonusPct(player)
	if not player then return 0 end
	return sumOfType(player.UserId, "WalkSpeedPct")
end

function BuffService.GetLuckBonusPct(player)
	if not player then return 0 end
	return sumOfType(player.UserId, "LuckPct")
end

function BuffService.GetActiveBuffs(player)
	if not player then return {} end
	local list = active[player.UserId]
	if not list then return {} end
	local now = os.clock()
	local out = {}
	for _, b in ipairs(list) do
		if b.expiresAt > now then
			table.insert(out, {
				type = b.type,
				amount = b.amount,
				remaining = b.expiresAt - now,
			})
		end
	end
	return out
end

function BuffService.ClearAll(player)
	if not player then return end
	active[player.UserId] = nil
	pushActiveBuffs(player)
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local dirty = {}
	for uid, list in pairs(active) do
		local before = #list
		for i = #list, 1, -1 do
			if list[i].expiresAt <= now then
				table.remove(list, i)
			end
		end
		if before ~= #list then
			dirty[uid] = true
		end
		if #list == 0 then
			active[uid] = nil
		end
	end
	for uid in pairs(dirty) do
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			pushActiveBuffs(plr)
		end
	end
end)

Players.PlayerAdded:Connect(function(p)
	task.defer(function()
		pushActiveBuffs(p)
	end)
end)

for _, p in ipairs(Players:GetPlayers()) do
	task.defer(function()
		pushActiveBuffs(p)
	end)
end

Players.PlayerRemoving:Connect(function(p)
	active[p.UserId] = nil
end)

return BuffService
