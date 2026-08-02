--[[
	DayNightConfig
	Shared day/night cycle timing. Each phase lasts PHASE_DURATION_SEC real seconds.
	Roblox Lighting.ClockTime spans DAY clock hours during day, NIGHT hours during night.
]]

local DayNightConfig = {}

DayNightConfig.PHASE_DURATION_SEC = 20 * 60 -- 20 real minutes per day and per night
DayNightConfig.DAY_CLOCK_START = 6
DayNightConfig.DAY_CLOCK_END = 18
DayNightConfig.NIGHT_CLOCK_START = 18
DayNightConfig.NIGHT_CLOCK_END = 6 -- wraps past midnight

function DayNightConfig.cycleDurationSec()
	return DayNightConfig.PHASE_DURATION_SEC * 2
end

-- phaseProgress: 0..1 within current phase
function DayNightConfig.clockTimeForPhase(isDay, phaseProgress)
	local span = DayNightConfig.DAY_CLOCK_END - DayNightConfig.DAY_CLOCK_START
	if isDay then
		return DayNightConfig.DAY_CLOCK_START + phaseProgress * span
	end
	local nightSpan = (24 - DayNightConfig.NIGHT_CLOCK_START) + DayNightConfig.NIGHT_CLOCK_END
	local t = DayNightConfig.NIGHT_CLOCK_START + phaseProgress * nightSpan
	if t >= 24 then
		t -= 24
	end
	return t
end

function DayNightConfig.formatClockTime(clockTime)
	local h = math.floor(clockTime) % 24
	local m = math.floor((clockTime % 1) * 60 + 0.5)
	if m >= 60 then
		h = (h + 1) % 24
		m = 0
	end
	local suffix = h >= 12 and "PM" or "AM"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%d:%02d %s", h12, m, suffix)
end

function DayNightConfig.formatRemaining(sec)
	sec = math.max(0, math.floor(tonumber(sec) or 0))
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%d:%02d", m, s)
end

function DayNightConfig.clampClockTime(clockTime)
	local t = tonumber(clockTime) or 0
	t = t % 24
	if t < 0 then
		t += 24
	end
	return t
end

function DayNightConfig.clockTimeFromHourMinute(hour, minute)
	local h = math.floor(tonumber(hour) or 0)
	local m = math.floor(tonumber(minute) or 0)
	h = ((h % 24) + 24) % 24
	m = math.clamp(m, 0, 59)
	return h + (m / 60)
end

function DayNightConfig.phaseForClockTime(clockTime)
	local t = DayNightConfig.clampClockTime(clockTime)
	if t >= DayNightConfig.DAY_CLOCK_START and t < DayNightConfig.DAY_CLOCK_END then
		return "Day"
	end
	return "Night"
end

return DayNightConfig
