local PotionAction = require(game:GetService("ReplicatedStorage"):WaitForChild("PotionAction"))
-- SpearFishHandler
-- Spear-fishing sessions (2026-10-03): approach unseen, one leading throw to spear a fish, the haul,
-- then the next fish, for as long as the player stays at the pool.
-- FishingConfig has the loop and the fish movement this server and FishingClient share. Every
-- throw is judged here against where the fish really was at impact (from the session seed), so
-- a client can only send where and when it threw, never what it hit.
-- Pools are parts tagged FishingPool (Radius attribute) sitting on the water surface. This
-- script also watches for spooking (sprinting or jumping near a pool) and stamps the pool's
-- SpookedUntil attribute, which every client reads to send its fish deep.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local QuestProgress = require(ServerScriptService:WaitForChild("QuestProgressService"))
local CombatStateService = require(ServerScriptService:WaitForChild("CombatStateService"))
local FishingConfig = require(ReplicatedStorage:WaitForChild("FishingConfig"))
local ScriptedRigs = require(ServerScriptService:WaitForChild("ScriptedRigs"))
local ConsumableRequestUtil = require(ReplicatedStorage:WaitForChild("ConsumableRequestUtil"))
local FishingXPEvent = ReplicatedStorage:WaitForChild("FishingXPEvent")

-- The session remotes. (The old tug game's SpearFishHook/Tug/Cancel remotes may still exist in
-- ReplicatedStorage but nothing listens to them any more.)
local gameEvents = ConsumableRequestUtil.EnsureGameEventsFolder()
local SessionStart = ConsumableRequestUtil.EnsureRemoteFunction(gameEvents, "FishingSessionStart")
local Throw = ConsumableRequestUtil.EnsureRemoteFunction(gameEvents, "FishingThrow")
local SessionAction = ConsumableRequestUtil.EnsureRemoteEvent(gameEvents, "FishingSessionAction")
local FishingResult = ConsumableRequestUtil.EnsureRemoteEvent(gameEvents, "FishingResult")
local FishCatchShow = ConsumableRequestUtil.EnsureRemoteEvent(gameEvents, "FishCatchShow")

-- The caught-fish models, shared so every client can play the catch show (FishCatchVisuals).
do
	local visuals = ReplicatedStorage:FindFirstChild(FishingConfig.VISUALS_FOLDER) or Instance.new("Folder")
	visuals.Name = FishingConfig.VISUALS_FOLDER
	local source = game:GetService("ServerStorage"):FindFirstChild("FishModels")
	if source then
		for _, model in ipairs(source:GetChildren()) do
			if not visuals:FindFirstChild(model.Name) then
				model:Clone().Parent = visuals
			end
		end
	else
		warn("[SpearFish] ServerStorage.FishModels is missing; catches have no show")
	end
	visuals.Parent = ReplicatedStorage
end

local THROW = FishingConfig.THROW
local IDLE_TIMEOUT = 120 -- seconds without a throw before the session closes itself
local HAUL_TIMEOUT = 45
local THROW_GAP = 0.35 -- seconds between throws (the spear has to leave the hand)
local LATENCY_SLACK = 0.6 -- how far in the past a reported release may be

local VALID_SPEAR_ITEM_IDS = {
	WoodenSpear = true,
	TrainingSpear = true,
}

local VALID_SPEAR_TOOL_NAMES = {
	WoodenSpear = true,
	Spear = true,
	["Wooden Spear"] = true,
	["Training Spear"] = true,
}

local function isSpearTool(t)
	if not t or not t:IsA("Tool") then
		return false
	end
	local itemId = t:GetAttribute("DungeonItemId")
	if type(itemId) == "string" and VALID_SPEAR_ITEM_IDS[itemId] then
		return true
	end
	if t:GetAttribute("DungeonEquipSlot") == "FishingSpear" then
		return true
	end
	return VALID_SPEAR_TOOL_NAMES[t.Name] == true
end

local function ownsSpear(player)
	local character = player.Character
	if character then
		for _, c in ipairs(character:GetChildren()) do
			if isSpearTool(c) then
				return true
			end
		end
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		for _, c in ipairs(bp:GetChildren()) do
			if isSpearTool(c) then
				return true
			end
		end
	end
	return false
end

local function getHrp(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function poolRadius(pool)
	return tonumber(pool:GetAttribute("Radius")) or 8
end

-- Horizontal distance from the pool's edge (0 inside it).
local function distanceFromPool(pool, position)
	local flat = (position - pool.Position) * Vector3.new(1, 0, 1)
	return math.max(0, flat.Magnitude - poolRadius(pool))
end

local function isPool(inst)
	return typeof(inst) == "Instance" and inst:IsA("BasePart") and CollectionService:HasTag(inst, FishingConfig.POOL_TAG)
end

local function serverNow()
	return workspace:GetServerTimeNow()
end

-- Every pool gets a seed for its ambient fish, so all clients draw the same ones.
local function preparePool(pool)
	if not pool:IsA("BasePart") then return end
	if not pool:GetAttribute("FishSeed") then
		pool:SetAttribute("FishSeed", math.random(1, 2 ^ 24))
	end
end
for _, pool in ipairs(CollectionService:GetTagged(FishingConfig.POOL_TAG)) do
	preparePool(pool)
end
CollectionService:GetInstanceAddedSignal(FishingConfig.POOL_TAG):Connect(preparePool)

---------------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------------

local function giveXP(player, xpGain)
	xpGain = math.floor(xpGain)
	if xpGain <= 0 then return 0 end
	local _, _, totals = DungeonProfile.AddSkillXP(player, "fishing", xpGain)
	FishingXPEvent:FireClient(player, xpGain, totals)
	return xpGain
end

local function grantFish(player, fishId)
	local ok, err = DungeonProfile.GrantItemId(player, fishId, 1)
	if not ok then
		warn("[SpearFish] GrantItemId failed for", player.Name, fishId, err)
		return false
	end
	QuestProgress.OnSpearFishCaught(player, 1)
	return true
end

---------------------------------------------------------------------------
-- Sessions
-- A session is continuous: each catch or snapped line ends a ROUND and the next round's fish
-- swim in straight away. The session itself only ends on Esc, walking off, a hit or idling.
---------------------------------------------------------------------------

local sessions = {} -- [userId] = session
local poolInUse = {} -- [pool] = userId, one fisher per pool

-- A fresh set of fish. Returns what the client needs to draw the same ones.
-- A tutorial-scripted round (ScriptedRigs "fish": { fishId, count }) swims exactly `count` of
-- that fish instead of a random set. Server-queued, tutorial-only.
local function scriptedEntry(fishId)
	for _, e in ipairs(FishingConfig.FishDropTable) do
		if e.id == fishId then return e end
	end
	return nil
end

local function newRound(session, now)
	local seed = math.random(1, 2 ^ 24)
	local count = math.random(FishingConfig.SESSION_FISH.MIN, FishingConfig.SESSION_FISH.MAX)
	local rig = session.player and ScriptedRigs.Take(session.player, "fish")
	local rigEntry = type(rig) == "table" and scriptedEntry(rig.fishId) or nil
	if rigEntry then
		count = math.clamp(math.floor(tonumber(rig.count) or 1), 1, FishingConfig.SESSION_FISH.MAX)
	end
	local fish, ids = {}, {}
	for i = 1, count do
		local entry = rigEntry or FishingConfig.RollFishEntry()
		fish[i] = {
			entry = entry,
			behaviour = FishingConfig.BehaviourFor(entry.id),
			params = FishingConfig.FishParams(seed, i),
			hits = {},
		}
		ids[i] = entry.id
	end
	session.seed, session.fish, session.startedAt = seed, fish, now
	session.phase, session.throwsUsed, session.target = "stun", 0, nil
	session.haulAt, session.throwsAtStun = nil, nil
	return { seed = seed, fish = ids, startedAt = now }
end

-- The catch show for everyone nearby: the fish leaps from the water on the angler's side of the
-- pool up to them (FishCatchVisuals). Only fish with a FishingConfig.CATCH_SHOW entry.
local function showCatch(player, session, fishId)
	if not FishingConfig.CATCH_SHOW[fishId] then return end
	local hrp = getHrp(player)
	if not hrp then return end
	local centre = session.pool.Position
	local flat = (hrp.Position - centre) * Vector3.new(1, 0, 1)
	local side = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
	local from = centre + side * session.radius * 0.7
	for _, other in ipairs(Players:GetPlayers()) do
		local root = getHrp(other)
		if root and (root.Position - from).Magnitude <= FishingConfig.SHOW_RADIUS then
			FishCatchShow:FireClient(other, { fishId = fishId, from = from, userId = player.UserId })
		end
	end
end

-- The round's rewards: a catch (graded by the spears it took) or a fish that got off the line.
local function roundRewards(player, session, how)
	local target = session.target and session.fish[session.target]
	local hits = target and #target.hits or 0
	local result = { ended = how, hits = hits }
	if how == "caught" and target then
		local entry = target.entry
		local grade = FishingConfig.Grade(session.throwsAtStun or session.throwsUsed)
		local xp = FishingConfig.XP.CATCH + FishingConfig.XP.TIER * math.max(0, (entry.tier or 1) - 1)
			+ (FishingConfig.GRADE_XP_BONUS[grade] or 0)
		result.fishId = entry.id
		result.grade = grade
		result.granted = grantFish(player, entry.id)
		result.xp = giveXP(player, xp)
		showCatch(player, session, entry.id)
	else
		-- A snapped line, or knocked out of it mid-haul: the fish gets away, the hit still taught something.
		result.grade = "Escaped"
		result.fishId = target and target.entry.id
		result.xp = giveXP(player, hits > 0 and FishingConfig.XP.SNAP + FishingConfig.XP.ESCAPE_PER_HIT * hits or 0)
	end
	return result
end

-- End the round and start the next one in the same session.
local function finishRound(player, session, how)
	local result = roundRewards(player, session, how)
	result.next = newRound(session, serverNow())
	session.lastActivity = os.clock()
	FishingResult:FireClient(player, result)
end

local function endSession(player, session, how)
	if session.ended then return end
	session.ended = true
	sessions[player.UserId] = nil
	if poolInUse[session.pool] == player.UserId then
		poolInUse[session.pool] = nil
		session.pool:SetAttribute("FishingUserId", nil)
	end
	if how == "hit" and session.phase == "haul" then
		FishingResult:FireClient(player, roundRewards(player, session, "hit"))
	else
		FishingResult:FireClient(player, { ended = how })
	end
end

SessionStart.OnServerInvoke = function(player, pool)
	if PotionAction.IsLocked(player.Character) then return { ok = false, reason = "drinking" } end
	local uid = player.UserId
	if sessions[uid] then return { ok = false, reason = "busy" } end
	if not isPool(pool) then return { ok = false, reason = "bad_pool" } end
	if not ownsSpear(player) then return { ok = false, reason = "no_spear" } end
	local hrp = getHrp(player)
	if not hrp then return { ok = false, reason = "no_char" } end
	if distanceFromPool(pool, hrp.Position) > FishingConfig.START_RANGE then
		return { ok = false, reason = "too_far" }
	end
	local now = serverNow()
	if (pool:GetAttribute("SpookedUntil") or 0) > now then
		return { ok = false, reason = "spooked" }
	end
	if poolInUse[pool] and poolInUse[pool] ~= uid then
		return { ok = false, reason = "taken" }
	end

	local session = {
		player = player, pool = pool, character = player.Character, radius = poolRadius(pool),
		lastRelease = -math.huge, lastActivity = os.clock(),
	}
	local round = newRound(session, now)
	sessions[uid] = session
	poolInUse[pool] = uid
	pool:SetAttribute("FishingUserId", uid)
	round.ok = true
	round.radius = session.radius
	return round
end

-- A throw: where on the water (pool-local x, z) and when it left the hand (server clock).
-- Returns what it hit, judged at release + FLIGHT. Spears are unlimited.
Throw.OnServerInvoke = function(player, aimX, aimZ, releaseT)
	local session = sessions[player.UserId]
	if not session or session.ended or session.phase ~= "stun" then return { ok = false } end
	aimX, aimZ, releaseT = tonumber(aimX), tonumber(aimZ), tonumber(releaseT)
	if not aimX or not aimZ or not releaseT or aimX ~= aimX or aimZ ~= aimZ or releaseT ~= releaseT then
		return { ok = false }
	end
	local now = serverNow()
	-- A release can't be from the future, older than the latency slack, or from before this round.
	releaseT = math.clamp(releaseT, math.max(now - LATENCY_SLACK, session.startedAt), now)
	if releaseT - session.lastRelease < THROW_GAP then return { ok = false, reason = "too_fast" } end
	session.lastRelease = releaseT
	session.lastActivity = os.clock()
	session.throwsUsed += 1

	local aim = Vector2.new(aimX, aimZ)
	local impact = releaseT + THROW.FLIGHT - session.startedAt
	local hitIndex, best = nil, math.huge
	for i, f in ipairs(session.fish) do
		if not session.target or session.target == i then
			local tau = FishingConfig.PathTime(impact, f.hits)
			local pos = FishingConfig.FishPosition(f.params, f.behaviour, tau, session.radius)
			local d = (pos - aim).Magnitude
			if d <= THROW.HIT_RADIUS * f.behaviour.size and d < best then
				hitIndex, best = i, d
			end
		end
	end

	local result = { ok = true, throwsUsed = session.throwsUsed, impact = impact }
	if hitIndex then
		local f = session.fish[hitIndex]
		session.target = hitIndex
		table.insert(f.hits, impact)
		result.hit = hitIndex
		result.hits = #f.hits
		if #f.hits >= THROW.HITS_TO_STUN then
			session.phase = "haul"
			session.throwsAtStun = session.throwsUsed
			-- The haul starts once the spear lands, not at release.
			session.haulAt = session.startedAt + impact
			result.stunned = true
		end
	end
	return result
end

SessionAction.OnServerEvent:Connect(function(player, action)
	local session = sessions[player.UserId]
	if not session or session.ended or type(action) ~= "table" then return end
	local kind = action.kind
	if kind == "cancel" then
		endSession(player, session, "cancel")
	elseif kind == "caught" and session.phase == "haul" then
		-- The haul bar can't be proven, only made plausible: no faster than a flawless haul.
		if serverNow() - session.haulAt < FishingConfig.HAUL.MIN_TIME then
			finishRound(player, session, "snap")
		else
			finishRound(player, session, "caught")
		end
	elseif kind == "snap" and session.phase == "haul" then
		finishRound(player, session, "snap")
	end
end)

-- Taking a hit ends the session: a fish on the line gets away (its hit still gives XP).
CombatStateService.OnHit(function(player)
	local session = sessions[player.UserId]
	if session and not session.ended then
		endSession(player, session, "hit")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local session = sessions[player.UserId]
	if session then
		session.ended = true
		sessions[player.UserId] = nil
		if poolInUse[session.pool] == player.UserId then
			poolInUse[session.pool] = nil
			session.pool:SetAttribute("FishingUserId", nil)
		end
	end
end)

---------------------------------------------------------------------------
-- Watchdog + spooking
---------------------------------------------------------------------------

local SPOOK_JUMP_SPEED = 6 -- upward studs/s that counts as a jump

local watchClock = 0
RunService.Heartbeat:Connect(function(dt)
	watchClock += dt
	if watchClock < 0.2 then return end
	watchClock = 0
	local now = serverNow()

	for uid, session in pairs(sessions) do
		local player = Players:GetPlayerByUserId(uid)
		local hrp = player and getHrp(player)
		local humanoid = session.character and session.character:FindFirstChildOfClass("Humanoid")
		if not player then
			sessions[uid] = nil
		elseif player.Character ~= session.character or not hrp or not humanoid or humanoid.Health <= 0
			or not session.pool.Parent or not ownsSpear(player)
			or distanceFromPool(session.pool, hrp.Position) > FishingConfig.SESSION_RANGE then
			endSession(player, session, "cancel")
		elseif session.phase == "stun" and os.clock() - session.lastActivity > IDLE_TIMEOUT then
			endSession(player, session, "cancel")
		elseif session.phase == "haul" and now - session.haulAt > HAUL_TIMEOUT then
			finishRound(player, session, "snap")
		end
	end

	-- Sprinting or jumping near a pool sends its fish deep. A pool with a session running is
	-- left alone: those fish are already on the hook.
	local pools = CollectionService:GetTagged(FishingConfig.POOL_TAG)
	if #pools == 0 then return end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local velocity = hrp.AssemblyLinearVelocity
			local loud = (character:GetAttribute("IsSprinting") == true and (velocity * Vector3.new(1, 0, 1)).Magnitude > 4)
				or velocity.Y > SPOOK_JUMP_SPEED
			if loud then
				for _, pool in ipairs(pools) do
					if pool:IsA("BasePart") and not poolInUse[pool]
						and distanceFromPool(pool, hrp.Position) <= FishingConfig.SPOOK.RADIUS then
						pool:SetAttribute("SpookedUntil", now + FishingConfig.SPOOK.TIME)
					end
				end
			end
		end
	end
end)
