-- Server validates mining reward requests; on roll success tells this client to spawn a local-only Coal pickup.
-- Inventory is granted only when the client reports collecting the drop (validated with a nonce + distance).
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local QuestProgress = require(ServerScriptService:WaitForChild("QuestProgressService"))
local PartyService = require(ServerScriptService:WaitForChild("PartyService"))
local MiningExcavationConfig = require(ReplicatedStorage:WaitForChild("MiningExcavationConfig"))

local GRID_SIZE = MiningExcavationConfig.GRID_SIZE

local DROP_CHANCE = 1
local COOLDOWN = 0.55
local MINE_RANGE = 20
local PICKUP_EXPIRE_SEC = 120
local COLLECT_MAX_DISTANCE = 22
local DEBRIS_PIECES = 8
local DEBRIS_LIFETIME = 2

local lastMine = {}
local pendingCoal = {} -- [nonce] = { userId, position, expires, amount, grantItemId }
local excavationSessions = {} -- [userId] = session

local ev = ReplicatedStorage:WaitForChild("MiningRewardRequest")
local MiningDebrisRequest = ReplicatedStorage:WaitForChild("MiningDebrisRequest")
local MiningXPEvent = ReplicatedStorage:WaitForChild("MiningXPEvent")
local MiningCoalDrop = ReplicatedStorage:WaitForChild("MiningCoalDrop")
local MiningCoalCollect = ReplicatedStorage:WaitForChild("MiningCoalCollect")
local MiningExcavationStart = ReplicatedStorage:WaitForChild("MiningExcavationStart")
local MiningExcavationDig = ReplicatedStorage:WaitForChild("MiningExcavationDig")
local MiningExcavationCancel = ReplicatedStorage:WaitForChild("MiningExcavationCancel")

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

local function getOreTierFromModel(oreModel)
	return MiningExcavationConfig.getTierForOreModel(oreModel)
end

local function isCoalOre(inst)
	local tier, tierCfg = getOreTierFromModel(inst)
	if not tier then
		return nil
	end
	local cur = inst
	while cur do
		if tierCfg.matchName and string.find(cur.Name, tierCfg.matchName, 1, true) then
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

local function playerNearOre(player, oreModel)
	local root = hrp(player)
	if not root then
		return false
	end
	for _, d in ipairs(oreModel:GetDescendants()) do
		if d:IsA("BasePart") then
			if (d.Position - root.Position).Magnitude <= MINE_RANGE then
				return true
			end
		end
	end
	return false
end

local function validateOrePart(player, orePart)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, nil, nil, nil
	end
	if not ownsPickaxe(player) then
		return nil, nil, nil, nil
	end
	if typeof(orePart) ~= "Instance" or not orePart:IsA("BasePart") then
		return nil, nil, nil, nil
	end
	if not orePart:IsDescendantOf(Workspace) then
		return nil, nil, nil, nil
	end
	local oreModel = isCoalOre(orePart)
	if not oreModel or not oreModel:IsDescendantOf(Workspace) then
		return nil, nil, nil, nil
	end
	local oreTier, tierCfg = getOreTierFromModel(oreModel)
	if not oreTier or not tierCfg then
		return nil, nil, nil, nil
	end
	if not oreStillMineable(oreModel) then
		return nil, nil, nil, nil
	end
	if not playerNearOre(player, oreModel) then
		return nil, nil, nil, nil
	end
	return oreModel, orePart, oreTier, tierCfg
end

local function clearExcavationSession(userId)
	excavationSessions[userId] = nil
end

local function generateExcavationGrid(tierCfg)
	local grid = table.create(GRID_SIZE, 0)
	local oreTileCount = math.random(tierCfg.minOreTiles, tierCfg.maxOreTiles)
	local indices = {}
	for i = 1, GRID_SIZE do indices[i] = i end
	for i = GRID_SIZE, 2, -1 do
		local j = math.random(1, i)
		indices[i], indices[j] = indices[j], indices[i]
	end
	for n = 1, oreTileCount do
		grid[indices[n]] = MiningExcavationConfig.rollTileOreAmount(tierCfg)
	end
	return grid
end

local function grantCoalDrop(player, orePart, coalAmount, tierCfg)
	coalAmount = math.max(0, math.floor(tonumber(coalAmount) or 0))
	if coalAmount <= 0 then return end
	local grantItemId = tierCfg and tierCfg.grantItemId or "Coal"
	local xpPerUnit = tierCfg and tierCfg.xpPerUnit or 5
	local basePos = orePart.Position + Vector3.new(0, 2, 0)
	for _ = 1, coalAmount do
		local nonce = HttpService:GenerateGUID(false)
		local spread = Vector3.new(
			(math.random() - 0.5) * 4,
			0,
			(math.random() - 0.5) * 4
		)
		local dropPos = basePos + spread
		pendingCoal[nonce] = {
			userId = player.UserId,
			position = dropPos,
			expires = os.clock() + PICKUP_EXPIRE_SEC,
			amount = 1,
			grantItemId = grantItemId,
		}
		MiningCoalDrop:FireClient(player, { position = dropPos, nonce = nonce, amount = 1, grantItemId = grantItemId })
	end
	local xpGain = math.max(1, math.floor(xpPerUnit * coalAmount))
	DungeonProfile.AddSkillXP(player, "mining", xpGain)
	MiningXPEvent:FireClient(player, xpGain)
end

local function completeExcavation(player, session)
	if session.completed then return end
	session.completed = true
	local oreModel = session.oreModel
	local orePart = session.orePart
	local totalOre = session.totalOreWon or 0
	local tierCfg = session.tierCfg
	clearExcavationSession(player.UserId)
	beginCoalOreRespawnCycle(oreModel, tierCfg.respawnSeconds)
	local dropChance = tierCfg.dropChance or DROP_CHANCE
	if totalOre > 0 and math.random() < dropChance then
		grantCoalDrop(player, orePart, totalOre, tierCfg)
	end
end

MiningExcavationStart.OnServerInvoke = function(player, orePart)
	local uid = player.UserId
	local now = os.clock()
	if (lastMine[uid] or 0) + COOLDOWN > now then
		return { ok = false, reason = "cooldown" }
	end
	if excavationSessions[uid] then
		return { ok = false, reason = "busy" }
	end
	local oreModel, validatedPart, oreTier, tierCfg = validateOrePart(player, orePart)
	if not oreModel then
		return { ok = false, reason = "bad_ore" }
	end
	lastMine[uid] = now
	local grid = generateExcavationGrid(tierCfg)
	local maxAttempts = tierCfg.maxDigAttempts
	excavationSessions[uid] = {
		oreModel = oreModel,
		orePart = validatedPart,
		grid = grid,
		dug = {},
		attemptsLeft = maxAttempts,
		totalOreWon = 0,
		completed = false,
		oreTier = oreTier,
		tierCfg = tierCfg,
	}
	spawnStoneDebris(validatedPart.Position)
	return {
		ok = true,
		rows = MiningExcavationConfig.GRID_ROWS,
		cols = MiningExcavationConfig.GRID_COLS,
		attemptsLeft = maxAttempts,
		maxAttempts = maxAttempts,
		totalOreWon = 0,
		oreTier = oreTier,
		oreId = tierCfg.oreId,
		displayNameTitle = tierCfg.displayNameTitle,
		displayName = tierCfg.displayName,
		iconImage = MiningExcavationConfig.getIconImage(tierCfg),
	}
end

MiningExcavationDig.OnServerInvoke = function(player, tileIndex)
	local session = excavationSessions[player.UserId]
	if not session or session.completed then
		return { ok = false, reason = "no_session" }
	end
	if not ownsPickaxe(player) then
		clearExcavationSession(player.UserId)
		return { ok = false, reason = "no_pickaxe" }
	end
	if not playerNearOre(player, session.oreModel) then
		clearExcavationSession(player.UserId)
		return { ok = false, reason = "too_far" }
	end
	if type(tileIndex) ~= "number" then
		return { ok = false, reason = "bad_tile" }
	end
	tileIndex = math.floor(tileIndex)
	if tileIndex < 1 or tileIndex > GRID_SIZE then
		return { ok = false, reason = "bad_tile" }
	end
	if session.dug[tileIndex] then
		return { ok = false, reason = "already_dug" }
	end
	if session.attemptsLeft <= 0 then
		return { ok = false, reason = "no_attempts" }
	end
	session.dug[tileIndex] = true
	session.attemptsLeft = session.attemptsLeft - 1
	local oreAmount = session.grid[tileIndex] or 0
	if oreAmount > 0 then
		session.totalOreWon = session.totalOreWon + oreAmount
	end
	local completed = session.attemptsLeft <= 0
	if completed then
		completeExcavation(player, session)
	end
	return {
		ok = true,
		revealed = true,
		oreAmount = oreAmount,
		attemptsLeft = session.attemptsLeft,
		totalOreWon = session.totalOreWon,
		completed = completed,
	}
end

MiningExcavationCancel.OnServerEvent:Connect(function(player)
	clearExcavationSession(player.UserId)
end)

ev.OnServerEvent:Connect(function(player, orePart)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local uid = player.UserId
	local now = os.clock()
	if (lastMine[uid] or 0) + COOLDOWN > now then
		return
	end
	local oreModel, validatedPart, oreTier, tierCfg = validateOrePart(player, orePart)
	if not oreModel then
		return
	end
	lastMine[uid] = now
	beginCoalOreRespawnCycle(oreModel, tierCfg.respawnSeconds)
	local dropChance = tierCfg.dropChance or DROP_CHANCE
	if math.random() < dropChance then
		grantCoalDrop(player, validatedPart, 1, tierCfg)
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
	local amount = math.max(1, math.floor(tonumber(data.amount) or 1))
	local grantItemId = data.grantItemId or "Coal"
	local ok = select(1, DungeonProfile.GrantItemId(player, grantItemId, amount))
	if not ok then
		warn("[MiningReward] GrantItemId failed for collect", player.Name, grantItemId)
		return
	end
	if grantItemId == "Coal" then
		QuestProgress.OnCoalCollected(player, amount)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastMine[player.UserId] = nil
	clearExcavationSession(player.UserId)
	for n, d in pairs(pendingCoal) do
		if d.userId == player.UserId then
			pendingCoal[n] = nil
		end
	end
end)

return {}
