-- GrimCamp Campfire Ambient Effects
-- Adds PointLight and ParticleEmitter to the campfire for atmospheric fire glow

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

-- Create PointLight for warm fire glow
local pointLight = Instance.new("PointLight")
pointLight.Name = "FireLight"
pointLight.Color = Color3.fromRGB(255, 120, 30)
pointLight.Brightness = 2.5
pointLight.Range = 25
pointLight.Shadows = true
pointLight.Parent = firePart

-- Create a subtle flicker effect for the light
local flickerLoop = task.spawn(function()
    local baseBrightness = 2.5
    while task.wait(0.1) do
        if not pointLight or not pointLight.Parent then break end
        pointLight.Brightness = baseBrightness + math.random(-30, 30) / 100
    end
end)

-- Create ParticleEmitter for fire sparks/embers
local particles = Instance.new("ParticleEmitter")
particles.Name = "FireEmbers"
particles.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 0)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 180, 50)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 50, 0)),
})
particles.Size = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.15),
    NumberSequenceKeypoint.new(0.5, 0.1),
    NumberSequenceKeypoint.new(1, 0),
})
particles.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.3),
    NumberSequenceKeypoint.new(0.7, 0.6),
    NumberSequenceKeypoint.new(1, 1),
})
particles.Lifetime = NumberRange.new(1, 3)
particles.Rate = 30
particles.Speed = NumberRange.new(2, 5)
particles.SpreadAngle = Vector2.new(30, 30)
particles.EmissionDirection = Enum.NormalId.Top
particles.LightEmission = 1
particles.LightInfluence = 0
particles.Parent = firePart

-- Create a second ParticleEmitter for smoke
local smoke = Instance.new("ParticleEmitter")
smoke.Name = "Smoke"
smoke.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 60, 60)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30)),
})
smoke.Size = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.5),
    NumberSequenceKeypoint.new(0.5, 2),
    NumberSequenceKeypoint.new(1, 4),
})
smoke.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.5),
    NumberSequenceKeypoint.new(0.5, 0.7),
    NumberSequenceKeypoint.new(1, 1),
})
smoke.Lifetime = NumberRange.new(3, 6)
smoke.Rate = 8
smoke.Speed = NumberRange.new(1, 3)
smoke.SpreadAngle = Vector2.new(15, 15)
smoke.EmissionDirection = Enum.NormalId.Top
smoke.LightEmission = 0
smoke.LightInfluence = 1
smoke.RotSpeed = NumberRange.new(-30, 30)
smoke.Parent = firePart
