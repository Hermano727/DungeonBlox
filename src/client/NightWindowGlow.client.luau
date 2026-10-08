--[[
	NightWindowGlow
	Lights up window glass at night. Any BasePart tagged "NightWindow" turns neon warm at dusk and goes back to dark
	glass at dawn; PointLights named "WindowGlow" under it fade in with it (they sit just outside each window).

	The cycle itself belongs to DayNightService (it drives Lighting.ClockTime); this script only reads the clock and
	the phase boundaries from DayNightConfig, so changing the day length or the dusk/dawn hours needs no change here.
	Purely visual and client-side: nothing is replicated.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DayNightConfig = require(ReplicatedStorage:WaitForChild("DayNightConfig"))

local TAG = "NightWindow"
local LIGHT_NAME = "WindowGlow"
local GLOW_COLOR = Color3.fromRGB(255, 190, 120)
local LIGHT_BRIGHTNESS = 1.2
local RAMP_HOURS = 1 -- clock hours the glow takes to fade in at dusk / out at dawn
local STEP_SECONDS = 0.25

-- part -> { color, material } as authored (dark glass), restored when the glow is off
local original = {}

-- 0 by day, 1 at night, fading across RAMP_HOURS centred half an hour before dusk / dawn.
local function nightAmount(clockTime)
	local dusk = DayNightConfig.DAY_CLOCK_END
	local dawn = DayNightConfig.DAY_CLOCK_START
	if clockTime >= dusk - RAMP_HOURS / 2 then
		return math.clamp((clockTime - (dusk - RAMP_HOURS / 2)) / RAMP_HOURS, 0, 1)
	elseif clockTime < dawn + RAMP_HOURS / 2 then
		return math.clamp(1 - (clockTime - (dawn - RAMP_HOURS / 2)) / RAMP_HOURS, 0, 1)
	end
	return 0
end

local function apply(part, amount)
	local saved = original[part]
	if not saved then
		saved = { color = part.Color, material = part.Material }
		original[part] = saved
	end
	if amount > 0.01 then
		part.Material = Enum.Material.Neon
		part.Color = saved.color:Lerp(GLOW_COLOR, amount)
	else
		part.Material = saved.material
		part.Color = saved.color
	end
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("PointLight") and descendant.Name == LIGHT_NAME then
			descendant.Brightness = LIGHT_BRIGHTNESS * amount
			descendant.Enabled = amount > 0.01
		end
	end
end

local function track(part)
	if part:IsA("BasePart") then
		apply(part, nightAmount(Lighting.ClockTime))
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(part)
	original[part] = nil
end)
for _, part in CollectionService:GetTagged(TAG) do
	track(part)
end

local lastAmount = -1
while true do
	local amount = nightAmount(Lighting.ClockTime)
	if math.abs(amount - lastAmount) > 0.005 then
		lastAmount = amount
		for _, part in CollectionService:GetTagged(TAG) do
			if part:IsA("BasePart") then
				apply(part, amount)
			end
		end
	end
	task.wait(STEP_SECONDS)
end
