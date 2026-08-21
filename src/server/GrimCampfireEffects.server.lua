--[[
	GrimCampfireEffects
	Adds a PointLight + ember/smoke ParticleEmitters to the GrimCamp campfire
	for atmospheric fire glow.

	Tuned numbers (color, brightness, range, flicker, particle rates/sizes)
	live in GrimCampConfig.campfireEffects — this script reads them rather
	than hardcoding its own copy, so the config stays the single source of
	truth for "what does the campfire look like" (previously this script and
	GrimCampConfig quietly had two separate, easy-to-drift-apart copies of
	the same tuning, that happened to still agree — this refactor makes that
	guaranteed instead of coincidental). Transparency curves and emission
	direction are purely-visual details GrimCampConfig doesn't model; those
	stay as literals below.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GrimCampConfig = require(ReplicatedStorage:WaitForChild("GrimCampConfig"))
local HexToColor3 = GrimCampConfig.HexToColor3

local grimCamp = game.Workspace.TutorialPathway.Structures:FindFirstChild("GrimCamp")
if not grimCamp then return end

local campfire = grimCamp:FindFirstChild("Campfire")
if not campfire then return end

-- Find a suitable part in the campfire model to attach effects
local function findBestPart(model)
    -- Prefer a part named something fire-related, or just use the first BasePart
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            local nameLower = string.lower(desc.Name)
            if nameLower:find("fire") or nameLower:find("ember") or nameLower:find("log") or nameLower:find("pit") then
                return desc
            end
        end
    end
    -- Fallback: just find any BasePart
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            return desc
        end
    end
    return nil
end

local firePart = findBestPart(campfire)
if not firePart then return end

local lightCfg = GrimCampConfig.campfireEffects.pointLight
local emberCfg = GrimCampConfig.campfireEffects.emberParticles
local smokeCfg = GrimCampConfig.campfireEffects.smokeParticles

-- Create PointLight for warm fire glow
local pointLight = Instance.new("PointLight")
pointLight.Name = "FireLight"
pointLight.Color = HexToColor3(lightCfg.color)
pointLight.Brightness = lightCfg.brightness
pointLight.Range = lightCfg.range
pointLight.Shadows = lightCfg.shadows
pointLight.Parent = firePart

-- Create a subtle flicker effect for the light
local flickerAmpPct = math.floor(lightCfg.flickerAmplitude * 100)
task.spawn(function()
    local baseBrightness = lightCfg.brightness
    while task.wait(lightCfg.flickerInterval) do
        if not pointLight or not pointLight.Parent then break end
        pointLight.Brightness = baseBrightness + math.random(-flickerAmpPct, flickerAmpPct) / 100
    end
end)

-- Create ParticleEmitter for fire sparks/embers
local particles = Instance.new("ParticleEmitter")
particles.Name = "FireEmbers"
particles.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, HexToColor3(emberCfg.colorStart)),
    ColorSequenceKeypoint.new(0.5, HexToColor3(emberCfg.colorMid)),
    ColorSequenceKeypoint.new(1, HexToColor3(emberCfg.colorEnd)),
})
particles.Size = NumberSequence.new({
    NumberSequenceKeypoint.new(0, emberCfg.sizeStart),
    NumberSequenceKeypoint.new(0.5, emberCfg.sizeMid),
    NumberSequenceKeypoint.new(1, emberCfg.sizeEnd),
})
particles.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.3),
    NumberSequenceKeypoint.new(0.7, 0.6),
    NumberSequenceKeypoint.new(1, 1),
})
particles.Lifetime = NumberRange.new(emberCfg.lifetime[1], emberCfg.lifetime[2])
particles.Rate = emberCfg.rate
particles.Speed = NumberRange.new(emberCfg.speed[1], emberCfg.speed[2])
particles.SpreadAngle = Vector2.new(emberCfg.spreadAngle, emberCfg.spreadAngle)
particles.EmissionDirection = Enum.NormalId.Top
particles.LightEmission = 1
particles.LightInfluence = 0
particles.Parent = firePart

-- Create a second ParticleEmitter for smoke
local smoke = Instance.new("ParticleEmitter")
smoke.Name = "Smoke"
smoke.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, HexToColor3(smokeCfg.colorStart)),
    ColorSequenceKeypoint.new(1, HexToColor3(smokeCfg.colorEnd)),
})
smoke.Size = NumberSequence.new({
    NumberSequenceKeypoint.new(0, smokeCfg.sizeStart),
    NumberSequenceKeypoint.new(0.5, smokeCfg.sizeMid),
    NumberSequenceKeypoint.new(1, smokeCfg.sizeEnd),
})
smoke.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.5),
    NumberSequenceKeypoint.new(0.5, 0.7),
    NumberSequenceKeypoint.new(1, 1),
})
smoke.Lifetime = NumberRange.new(smokeCfg.lifetime[1], smokeCfg.lifetime[2])
smoke.Rate = smokeCfg.rate
smoke.Speed = NumberRange.new(smokeCfg.speed[1], smokeCfg.speed[2])
smoke.SpreadAngle = Vector2.new(smokeCfg.spreadAngle, smokeCfg.spreadAngle)
smoke.EmissionDirection = Enum.NormalId.Top
smoke.LightEmission = 0
smoke.LightInfluence = 1
smoke.RotSpeed = NumberRange.new(-30, 30)
smoke.Parent = firePart
