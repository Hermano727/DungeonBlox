local PotionAction = require(game:GetService("ReplicatedStorage"):WaitForChild("PotionAction"))
-- Mining sessions (2026-10-03): strike the seam, fracture strikes, collection. MiningConfig has
-- the loop and the judging functions this server and MiningClient share; the server judges every
-- report from the session seed, so a client can only send inputs, never results.
-- Collection is unchanged: one local-only pickup per coal, granted when the client reports
-- collecting it (validated with a nonce + distance).
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
local MiningConfig = require(ReplicatedStorage:WaitForChild("MiningConfig"))

local DROP_CHANCE = 1
local COOLDOWN = 0.55
local MINE_RANGE = 20
local PICKUP_EXPIRE_SEC = 120
local COLLECT_MAX_DISTANCE = 22
local DEBRIS_PIECES = 8
local DEBRIS_LIFETIME = 2

local lastMine = {}
local pendingCoal = {} -- [nonce] = { userId, position, expires, amount, grantItemId }

local MiningDebrisRequest = ReplicatedStorage:WaitForChild("MiningDebrisRequest")
local MiningXPEvent = ReplicatedStorage:WaitForChild("MiningXPEvent")
local MiningCoalDrop = ReplicatedStorage:WaitForChild("MiningCoalDrop")
local MiningCoalCollect = ReplicatedStorage:WaitForChild("MiningCoalCollect")
-- The session remotes. (The old grid's MiningExcavation* and one-click MiningRewardRequest remotes
-- still exist in ReplicatedStorage but nothing listens to them any more.)
local ConsumableRequestUtil = require(ReplicatedStorage:WaitForChild("ConsumableRequestUtil"))
local gameEvents = ConsumableRequestUtil.EnsureGameEventsFolder()
local MiningSessionStart = ConsumableRequestUtil.EnsureRemoteFunction(gameEvents, "MiningSessionStart")
local MiningSessionAction = ConsumableRequestUtil.EnsureRemoteEvent(gameEvents, "MiningSessionAction")
local MiningResult = ConsumableRequestUtil.EnsureRemoteEvent(gameEvents, "MiningResult")

-- The mined-coal drop model (procedural: assets/models/environment/ores, T1_CoalShard), shared
-- so MiningCoalDropClient can drop it instead of the old black block.
do
	local visuals = ReplicatedStorage:FindFirstChild("MiningVisuals") or Instance.new("Folder")
	visuals.Name = "MiningVisuals"
	local models = game:GetService("ServerStorage"):FindFirstChild("OreModels")
	local shard = models and models:FindFirstChild("T1_CoalShard")
	if shard and not visuals:FindFirstChild(shard.Name) then
		shard:Clone().Parent = visuals
	elseif not shard then
		warn("[Mining] ServerStorage.OreModels.T1_CoalShard is missing; coal drops use the old block")
	end
	visuals.Parent = ReplicatedStorage
end

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

-- Collection: one nonce pickup per coal, collected by walking over it (MiningCoalDropClient).
local function grantCoalDrop(player, orePart, coalAmount, tierCfg, xpGain)
	coalAmount = math.max(0, math.floor(tonumber(coalAmount) or 0))
	if coalAmount <= 0 then return end
	local grantItemId = tierCfg and tierCfg.grantItemId or "Coal"
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
	xpGain = math.max(1, math.floor(tonumber(xpGain) or coalAmount * MiningConfig.XP_PER_COAL))
	local _, _, totals = DungeonProfile.AddSkillXP(player, "mining", xpGain)
	MiningXPEvent:FireClient(player, xpGain, totals)
end

---------------------------------------------------------------------------
-- Sessions (MiningConfig has the loop and the shared judging functions)
---------------------------------------------------------------------------

local sessions = {} -- [userId] = session
local oreInUse = {} -- [oreModel] = userId, one miner per rock

local function endSession(player, session, how)
	if session.ended then return end
	session.ended = true
	sessions[player.UserId] = nil
	if oreInUse[session.oreModel] == player.UserId then
		oreInUse[session.oreModel] = nil
	end
	if how == "cancel" then
		MiningResult:FireClient(player, { ended = "cancel" })
		return
	end
	local outcome = MiningConfig.Outcome({
		broken = session.broken, total = #session.layout.faults,
		cracks = session.cracks, seam = session.seam or "miss",
	})
	beginCoalOreRespawnCycle(session.oreModel, session.tierCfg.respawnSeconds)
	spawnStoneDebris(session.orePart.Position)
	grantCoalDrop(player, session.orePart, outcome.coal, session.tierCfg, outcome.xp)
	MiningResult:FireClient(player, {
		ended = how, grade = outcome.grade, coal = outcome.coal, xp = outcome.xp,
		broken = session.broken, total = #session.layout.faults, cracks = session.cracks,
	})
end

MiningSessionStart.OnServerInvoke = function(player, orePart)
	if PotionAction.IsLocked(player.Character) then return { ok = false, reason = "drinking" } end
	local uid = player.UserId
	local now = os.clock()
	if (lastMine[uid] or 0) + COOLDOWN > now then
		return { ok = false, reason = "cooldown" }
	end
	if sessions[uid] then
		return { ok = false, reason = "busy" }
	end
	local oreModel, validatedPart, oreTier, tierCfg = validateOrePart(player, orePart)
	if not oreModel then
		return { ok = false, reason = "bad_ore" }
	end
	if oreInUse[oreModel] and oreInUse[oreModel] ~= uid then
		return { ok = false, reason = "taken" }
	end
	lastMine[uid] = now
	local seed = math.random(1, 2 ^ 30)
	local session = {
		oreModel = oreModel, orePart = validatedPart, oreTier = oreTier, tierCfg = tierCfg,
		character = player.Character, seed = seed, layout = MiningConfig.Layout(seed),
		phase = "seam", startedAt = now, lastAction = now,
		broken = 0, brokenSet = {}, cracks = 0, seam = nil,
	}
	sessions[uid] = session
	oreInUse[oreModel] = uid
	return {
		ok = true, seed = seed, oreTier = oreTier,
		displayNameTitle = tierCfg.displayNameTitle,
		iconImage = MiningExcavationConfig.getIconImage(tierCfg),
	}
end

MiningSessionAction.OnServerEvent:Connect(function(player, action)
	local session = sessions[player.UserId]
	if not session or session.ended or type(action) ~= "table" then return end
	local now = os.clock()
	local kind = action.kind
	if kind == "cancel" then
		endSession(player, session, "cancel")
		return
	end
	if session.phase == "seam" and kind == "seam" then
		-- The ring takes SEAM.RING_TIME to close; a strike before it could close is a forgery.
		if now - session.startedAt < 0.15 then return end
		session.seam = MiningConfig.JudgeSeam(action.accuracy)
		if session.seam == "miss" then
			session.cracks += 1
		end
		session.phase = "extract"
		session.extractAt = now
		session.lastAction = now
	elseif session.phase == "extract" and kind == "strike" then
		local index = tonumber(action.point)
		local fault = index and session.layout.faults[math.floor(index)]
		if not fault or session.brokenSet[fault] then return end
		-- Power comes from the hold time, which can't exceed the time since the last action.
		local hold = math.clamp(tonumber(action.hold) or 0, 0, now - session.lastAction + 0.2)
		if hold < MiningConfig.MIN_HOLD then return end
		session.lastAction = now
		local result = MiningConfig.JudgeStrike(fault, MiningConfig.PowerFromHold(hold))
		if result ~= "weak" then
			session.brokenSet[fault] = true
			session.broken += 1
		end
		if result == "crack" then
			session.cracks += 1
		end
		if session.cracks >= MiningConfig.MAX_CRACKS then
			endSession(player, session, "shatter")
		elseif session.broken >= #session.layout.faults then
			endSession(player, session, "pry")
		end
	elseif session.phase == "extract" and kind == "pry" then
		endSession(player, session, "pry")
	end
end)

-- Leaving, dying, swapping tools or taking a hit ends the session. A hit pries out what's
-- already free (whatever was earned is kept); walking away or dropping the pickaxe cancels.
local CombatStateService = require(ServerScriptService:WaitForChild("CombatStateService"))
CombatStateService.OnHit(function(player)
	local session = sessions[player.UserId]
	if session and not session.ended then
		if session.phase == "extract" then
			endSession(player, session, "hit")
		else
			endSession(player, session, "cancel")
		end
	end
end)

local watchClock = 0
game:GetService("RunService").Heartbeat:Connect(function(dt)
	watchClock += dt
	if watchClock < 0.25 then return end
	watchClock = 0
	local now = os.clock()
	for uid, session in pairs(sessions) do
		local player = Players:GetPlayerByUserId(uid)
		local humanoid = session.character and session.character:FindFirstChildOfClass("Humanoid")
		if not player or player.Character ~= session.character or not humanoid or humanoid.Health <= 0
			or not session.oreModel.Parent or not ownsPickaxe(player) then
			if player then endSession(player, session, "cancel") else sessions[uid] = nil end
		elseif not playerNearOre(player, session.oreModel) then
			endSession(player, session, "cancel")
		elseif session.phase == "seam" and now - session.startedAt > MiningConfig.SEAM.RING_TIME + 2 then
			-- The client never reported the seam: treat it as a miss and move on.
			session.seam = "miss"
			session.cracks += 1
			session.phase = "extract"
			session.extractAt = now
			session.lastAction = now
		elseif session.phase == "extract" and now - session.extractAt > MiningConfig.TIME_LIMIT + 1 then
			endSession(player, session, "time")
		end
	end
end)

MiningDebrisRequest.OnServerEvent:Connect(function(player, orePart)
	if PotionAction.IsLocked(player.Character) then return end
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
	-- Fires for every ore, not just coal -- OnOreCollected tracks the lifetime totals
	-- and forwards to the coal quest itself only when the ore actually is coal.
	QuestProgress.OnOreCollected(player, grantItemId, amount)
end)

Players.PlayerRemoving:Connect(function(player)
	lastMine[player.UserId] = nil
	local session = sessions[player.UserId]
	if session then
		sessions[player.UserId] = nil
		if oreInUse[session.oreModel] == player.UserId then oreInUse[session.oreModel] = nil end
	end
	for n, d in pairs(pendingCoal) do
		if d.userId == player.UserId then
			pendingCoal[n] = nil
		end
	end
end)

return {}
