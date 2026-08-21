--[[
	CombatStateService
	Per-player combat timer (5s, refreshed on each mob hit) + two-state HP regen.
	  In combat  : 0.2% of maxHp/s
	  Out of combat: 0.2% of maxHp/s + shield.hps/s
]]

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local COMBAT_TIMEOUT    = 5       -- seconds after last hit before "safe"
local IN_COMBAT_REGEN   = 0.001   -- 0.2% of maxHp per second (always)

local CombatStateService = {}
local timers = {}   -- [userId] = seconds remaining

local function getEvent()
	local ev = ReplicatedStorage:FindFirstChild("CombatStateEvent")
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = "CombatStateEvent"
		ev.Parent = ReplicatedStorage
	end
	return ev
end

function CombatStateService.OnPlayerDamaged(player)
	local uid = player.UserId
	local wasOut = not (timers[uid] and timers[uid] > 0)
	timers[uid] = COMBAT_TIMEOUT
	pcall(getEvent().FireClient, getEvent(), player, "combat", COMBAT_TIMEOUT)
end

local _dp
local function dp()
	if not _dp then _dp = require(ServerScriptService:WaitForChild("DungeonProfileService")) end
	return _dp
end

-- Stateless leaf module (pure functions over a profile table, no other
-- dependencies) -- safe to require eagerly, unlike DungeonProfileService
-- above which needs the lazy/deferred pattern for boot-order reasons.
local DungeonStatsService = require(ServerScriptService:WaitForChild("DungeonStatsService"))

-- Same maxHp formula DungeonStatsService.BuildSnapshot uses for the
-- character-sheet UI (base + summed "hp" subStat across equipped gear) --
-- delegating the equipped-item sum to DungeonStatsService.SumEquippedSubStat
-- keeps this one-tick-per-player-per-heartbeat check as cheap as the old
-- hand-rolled loop while guaranteeing it can't drift from the UI's number.
local function computeMaxHp(profile)
	local base = (profile.stats and profile.stats.combat and profile.stats.combat.maxHp) or 100
	local bonus = DungeonStatsService.SumEquippedSubStat(profile, "hp")
	return math.max(1, base + bonus)
end

local function getShieldHps(profile)
	local sid = (profile.equipped or {})["Shield"]
	if not sid then return 0 end
	local sh = profile.inventory[sid]
	return sh and sh.subStats and tonumber(sh.subStats.hps) or 0
end

function CombatStateService.start()
	getEvent()  -- ensure exists before clients load

	RunService.Heartbeat:Connect(function(dt)
		for _, player in ipairs(Players:GetPlayers()) do
			local uid = player.UserId
			local t = timers[uid]
			local wasIn = t and t > 0

			if wasIn then
				timers[uid] = t - dt
				if timers[uid] <= 0 then
					timers[uid] = 0
					pcall(getEvent().FireClient, getEvent(), player, "safe", 0)
				end
			end

			local isIn = timers[uid] and timers[uid] > 0

			-- Regen only if alive and not full
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 or hum.Health >= hum.MaxHealth then continue end

			local profile = dp().Get(player)
			if not profile then continue end

			local maxHp = computeMaxHp(profile)
			local regen = maxHp * IN_COMBAT_REGEN * dt
			if not isIn then
				regen = regen + getShieldHps(profile) * dt
			end

			hum.Health = math.min(hum.MaxHealth, hum.Health + regen)
		end
	end)
end

Players.PlayerRemoving:Connect(function(p) timers[p.UserId] = nil end)

return CombatStateService