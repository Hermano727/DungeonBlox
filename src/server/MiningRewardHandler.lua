-- Server validates mining reward requests; on roll success tells this client to spawn a local-only Coal pickup.
-- Inventory is granted only when the client reports collecting the drop (validated with a nonce + distance).
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))
local QuestProgress = require(ServerScriptService:WaitForChild("QuestProgressService"))

local DROP_CHANCE = 1
local COOLDOWN = 0.55
local MINE_RANGE = 20
local XP_PER_COAL = 5
local PICKUP_EXPIRE_SEC = 120
local COLLECT_MAX_DISTANCE = 22
local DEBRIS_PIECES = 8
local DEBRIS_LIFETIME = 2
-- Must match StarterPack.WoodenPickaxe.MiningScript ORE_RESPAWN_TIME.
local ORE_RESPAWN_TIME = 10

local lastMine = {}
local pendingCoal = {} -- [nonce] = { userId, position, expires }

local ev = ReplicatedStorage:WaitForChild("MiningRewardRequest")
local MiningDebrisRequest = ReplicatedStorage:WaitForChild("MiningDebrisRequest")
local MiningXPEvent = ReplicatedStorage:WaitForChild("MiningXPEvent")
local MiningCoalDrop = ReplicatedStorage:WaitForChild("MiningCoalDrop")
local MiningCoalCollect = ReplicatedStorage:WaitForChild("MiningCoalCollect")

local function toolIsMiningPickaxe(t)
	if not t or not t:IsA("Tool") then
		return false
	end
	local n = t.Name
	if n == "WoodenPickaxe" or n == "Pickaxe" or n == "Wooden Pickaxe" then
		return true
	end
	if t:GetAttribute("DungeonEquipSlot") == "Pickaxe" then
		return true
	end
	if t:FindFirstChild("MiningScript") then
		return true
	end
	return false
end

local function ownsPickaxe(player)
	local char = player.Character
	if char then
		for _, c in ipairs(char:GetChildren()) do
			if toolIsMiningPickaxe(c) then
				return true
			end
		end
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		for _, c in ipairs(bp:GetChildren()) do
			if toolIsMiningPickaxe(c) then
				return true
			end
		end
	end
	return false
end

local function isCoalOre(inst)
	local cur = inst
	while cur do
		if string.find(cur.Name, "Coal", 1, true) then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

local function oreStillMineable(oreModel)
	for _, d in ipairs(oreModel:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			return true
		end
	end
	return false
end

local function hrp(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function sweepExpiredPickups(now)
	for nonce, data in pairs(pendingCoal) do
		if now > data.expires then
			pendingCoal[nonce] = nil
		end
	end
end

local function spawnStoneDebris(origin)
	for _ = 1, DEBRIS_PIECES do
		local piece = Instance.new("Part")
		piece.Name = "OreDebris"
		piece.Size = Vector3.new(
			math.random(10, 12) / 10,
			math.random(10, 12) / 10,
			math.random(10, 12) / 10
		)
		piece.Shape = Enum.PartType.Block
		piece.Material = Enum.Material.Slate
		piece.Color = Color3.fromRGB(90, 90, 90)
		piece.Anchored = false
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		local dir = Vector3.new(
			(math.random() - 0.5) * 2,
			(math.random() - 0.5) * 2,
			(math.random() - 0.5) * 2
		)
		if dir.Magnitude < 0.05 then
			dir = Vector3.new(0, 1, 0)
		else
			dir = dir.Unit
		end

		piece.Position = origin + (dir * 1.8)
		piece.Parent = Workspace
		piece.AssemblyLinearVelocity = dir * 22
		piece.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 24,
			(math.random() - 0.5) * 24,
			(math.random() - 0.5) * 24
		)

		task.spawn(function()
			local steps = 8
			for i = 1, steps do
				task.wait(DEBRIS_LIFETIME / steps)
				if not piece.Parent then
					return
				end
				piece.Transparency = i / steps
			end
		end)
		Debris:AddItem(piece, DEBRIS_LIFETIME + 0.2)
	end
end

local function beginCoalOreRespawnCycle(oreModel, respawnSeconds)
	if typeof(oreModel) ~= "Instance" then
		return
	end
	local snapshots = {}
	for _, d in ipairs(oreModel:GetDescendants()) do
		if d:IsA("BasePart") then
			local cq = nil
			pcall(function()
				cq = d.CanQuery
			end)
			table.insert(snapshots, {
				part = d,
				transparency = d.Transparency,
				canCollide = d.CanCollide,
				canQuery = cq,
			})
			d.Transparency = 1
			d.CanCollide = false
			pcall(function()
				d.CanQuery = false
			end)
		end
	end

	task.delay(respawnSeconds, function()
		if typeof(oreModel) ~= "Instance" or not oreModel.Parent then
			return
		end
		for _, snap in ipairs(snapshots) do
			local p = snap.part
			if p and p.Parent then
				p.Transparency = snap.transparency
				p.CanCollide = snap.canCollide
				pcall(function()
					if snap.canQuery ~= nil then
						p.CanQuery = snap.canQuery
					end
				end)
			end
		end
	end)
end

ev.OnServerEvent:Connect(function(player, orePart)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local uid = player.UserId
	local now = os.clock()
	if (lastMine[uid] or 0) + COOLDOWN > now then
		return
	end
	if not ownsPickaxe(player) then
		return
	end
	local root = hrp(player)
	if not root then
		return
	end
	if typeof(orePart) ~= "Instance" or not orePart:IsA("BasePart") then
		return
	end
	if not orePart:IsDescendantOf(Workspace) then
		return
	end
	local oreModel = isCoalOre(orePart)
	if not oreModel or not oreModel:IsDescendantOf(Workspace) then
		return
	end
	if not oreStillMineable(oreModel) then
		return
	end

	local distOk = false
	for _, d in ipairs(oreModel:GetDescendants()) do
		if d:IsA("BasePart") then
			if (d.Position - root.Position).Magnitude <= MINE_RANGE then
				distOk = true
				break
			end
		end
	end
	if not distOk then
		return
	end

	lastMine[uid] = now

	beginCoalOreRespawnCycle(oreModel, ORE_RESPAWN_TIME)

	if math.random() < DROP_CHANCE then
		local nonce = HttpService:GenerateGUID(false)
		local basePos = orePart.Position + Vector3.new(0, 2, 0)
		pendingCoal[nonce] = {
			userId = uid,
			position = basePos,
			expires = os.clock() + PICKUP_EXPIRE_SEC,
		}
		MiningCoalDrop:FireClient(player, { position = basePos, nonce = nonce })
		DungeonProfile.AddSkillXP(player, "mining", XP_PER_COAL)
		MiningXPEvent:FireClient(player, XP_PER_COAL)
	end
end)

MiningDebrisRequest.OnServerEvent:Connect(function(player, orePart)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if not ownsPickaxe(player) then
		return
	end
	local root = hrp(player)
	if not root then
		return
	end
	if typeof(orePart) ~= "Instance" or not orePart:IsA("BasePart") then
		return
	end
	if not orePart:IsDescendantOf(Workspace) then
		return
	end
	local oreModel = isCoalOre(orePart)
	if not oreModel or not oreModel:IsDescendantOf(Workspace) then
		return
	end
	if not oreStillMineable(oreModel) then
		return
	end
	if (orePart.Position - root.Position).Magnitude > MINE_RANGE then
		return
	end
	spawnStoneDebris(orePart.Position)
end)

MiningCoalCollect.OnServerEvent:Connect(function(player, nonce)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if type(nonce) ~= "string" or nonce == "" then
		return
	end

	local now = os.clock()
	sweepExpiredPickups(now)

	local data = pendingCoal[nonce]
	if not data then
		return
	end
	if data.userId ~= player.UserId then
		return
	end

	local root = hrp(player)
	if not root then
		return
	end
	if (root.Position - data.position).Magnitude > COLLECT_MAX_DISTANCE then
		return
	end

	pendingCoal[nonce] = nil
	local ok = select(1, DungeonProfile.GrantItemId(player, "Coal", 1))
	if not ok then
		warn("[MiningReward] GrantItemId failed for coal collect", player.Name)
		return
	end
	QuestProgress.OnCoalCollected(player, 1)
end)

Players.PlayerRemoving:Connect(function(player)
	lastMine[player.UserId] = nil
	for n, d in pairs(pendingCoal) do
		if d.userId == player.UserId then
			pendingCoal[n] = nil
		end
	end
end)

return {}
