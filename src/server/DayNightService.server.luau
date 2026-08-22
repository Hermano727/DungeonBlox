--[[
	DayNightService
	Authoritative day/night cycle: 20 real minutes day, 20 real minutes night.
	Drives Lighting.ClockTime and broadcasts state for the Character menu clock.

	Devs can pause the cycle and set a fixed ClockTime via DevDayNightControl.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DayNightConfig = require(ReplicatedStorage:WaitForChild("DayNightConfig"))
local DevRoster = require(ReplicatedStorage:WaitForChild("DevRoster"))
local isDev = DevRoster.IsDev

local PHASE_SEC = DayNightConfig.PHASE_DURATION_SEC
local CYCLE_SEC = DayNightConfig.cycleDurationSec()

local function ensureGameEvents()
	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	if not ge then
		ge = Instance.new("Folder")
		ge.Name = "GameEvents"
		ge.Parent = ReplicatedStorage
	end
	return ge
end

local function ensureRemote(name)
	local ge = ensureGameEvents()
	local ev = ge:FindFirstChild(name)
	if ev and ev:IsA("RemoteEvent") then
		return ev
	end
	if ev then
		ev:Destroy()
	end
	ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = ge
	return ev
end

local function ensureRemoteFunction(name)
	local ge = ensureGameEvents()
	local rf = ge:FindFirstChild(name)
	if rf and rf:IsA("RemoteFunction") then
		return rf
	end
	if rf then
		rf:Destroy()
	end
	rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = ge
	return rf
end

local syncEv = ensureRemote("DayNightSync")
local rfDevTime = ensureRemoteFunction("DevDayNightControl")

local cycleStart = workspace:GetAttribute("DayNightCycleStart")
if type(cycleStart) ~= "number" then
	-- Default start at noon (12:00 PM): midpoint of the day phase.
	cycleStart = workspace:GetServerTimeNow() - (PHASE_SEC * 0.5)
	workspace:SetAttribute("DayNightCycleStart", cycleStart)
end

local devOverrideClock = nil
local lastPayload = nil
local lastBroadcastClock = 0

local function stateFromClockTime(clockTime, opts)
	opts = opts or {}
	local t = DayNightConfig.clampClockTime(clockTime)
	return {
		phase = DayNightConfig.phaseForClockTime(t),
		clockTime = t,
		phaseRemaining = opts.phaseRemaining or 0,
		phaseDuration = PHASE_SEC,
		cycleStart = cycleStart,
		devOverride = opts.devOverride == true,
	}
end

local function getCycleState(now)
	now = now or workspace:GetServerTimeNow()
	local elapsed = (now - cycleStart) % CYCLE_SEC
	local isDay = elapsed < PHASE_SEC
	local phaseElapsed = isDay and elapsed or (elapsed - PHASE_SEC)
	local phaseProgress = math.clamp(phaseElapsed / PHASE_SEC, 0, 1)
	local clockTime = DayNightConfig.clockTimeForPhase(isDay, phaseProgress)
	local phaseRemaining = math.max(0, PHASE_SEC - phaseElapsed)
	return stateFromClockTime(clockTime, {
		phaseRemaining = phaseRemaining,
		devOverride = false,
	})
end

local function getState(now)
	if devOverrideClock ~= nil then
		return stateFromClockTime(devOverrideClock, { devOverride = true })
	end
	return getCycleState(now)
end

local function payloadsEqual(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	return a.phase == b.phase
		and math.abs((a.clockTime or 0) - (b.clockTime or 0)) < 0.02
		and (a.devOverride == b.devOverride)
		and math.abs((a.phaseRemaining or 0) - (b.phaseRemaining or 0)) <= 1
end

local function broadcast(state, force)
	if not force and lastPayload and payloadsEqual(lastPayload, state) then
		return
	end
	lastPayload = state
	for _, plr in ipairs(Players:GetPlayers()) do
		syncEv:FireClient(plr, state)
	end
end

local function applyAndBroadcast()
	local state = getState()
	Lighting.ClockTime = state.clockTime
	broadcast(state, true)
	return state
end

rfDevTime.OnServerInvoke = function(player, data)
	if not isDev(player) then
		return { ok = false, error = "not_dev" }
	end
	if type(data) ~= "table" or type(data.action) ~= "string" then
		return { ok = false, error = "bad_request" }
	end

	if data.action == "Get" then
		local state = getState()
		return { ok = true, state = state }
	end

	if data.action == "SetTime" then
		local clockTime = DayNightConfig.clampClockTime(data.clockTime)
		if data.hour ~= nil or data.minute ~= nil then
			clockTime = DayNightConfig.clockTimeFromHourMinute(data.hour, data.minute)
		end
		devOverrideClock = clockTime
		workspace:SetAttribute("DayNightDevOverride", true)
		local state = applyAndBroadcast()
		print(string.format("[DayNightService] %s set dev time to %.2f (%s)",
			player.Name, state.clockTime, DayNightConfig.formatClockTime(state.clockTime)))
		return { ok = true, state = state }
	end

	if data.action == "Resume" then
		devOverrideClock = nil
		workspace:SetAttribute("DayNightDevOverride", false)
		cycleStart = workspace:GetServerTimeNow()
		workspace:SetAttribute("DayNightCycleStart", cycleStart)
		local state = applyAndBroadcast()
		print(string.format("[DayNightService] %s resumed automatic day/night cycle", player.Name))
		return { ok = true, state = state }
	end

	return { ok = false, error = "unknown_action" }
end

Players.PlayerAdded:Connect(function(plr)
	task.defer(function()
		syncEv:FireClient(plr, getState())
	end)
end)

RunService.Heartbeat:Connect(function()
	local state = getState()
	Lighting.ClockTime = state.clockTime
	local now = os.clock()
	if now - lastBroadcastClock >= 1
		or not lastPayload
		or lastPayload.phase ~= state.phase
		or lastPayload.devOverride ~= state.devOverride
	then
		lastBroadcastClock = now
		broadcast(state)
	end
end)

print(string.format("[DayNightService] ready — %d min day / %d min night (DevDayNightControl enabled)", PHASE_SEC / 60, PHASE_SEC / 60))
