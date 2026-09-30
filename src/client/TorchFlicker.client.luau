--[[
	TorchFlicker -- makes torch lights flicker like real flame (client only, purely visual).

	Any PointLight tagged "MiasmaTorchLight" (MiasmaArenaArtAssembler tags the arena torches) gets
	its Brightness and Range nudged every frame by two layers of noise around the base values in
	its BaseBrightness / BaseRange attributes. Only lights near the camera are updated.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TAG = "MiasmaTorchLight"
local MAX_DISTANCE = 180
local BRIGHTNESS_SWING = .22
local RANGE_SWING = .06

local lights = {}

local function add(light)
	if not light:IsA("PointLight") then return end
	lights[light] = {
		brightness = light:GetAttribute("BaseBrightness") or light.Brightness,
		range = light:GetAttribute("BaseRange") or light.Range,
		seed = math.random() * 1000,
	}
end

for _, light in ipairs(CollectionService:GetTagged(TAG)) do add(light) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(light) lights[light] = nil end)

local function positionOf(light)
	local parent = light.Parent
	if not parent then return nil end
	if parent:IsA("Attachment") then return parent.WorldPosition end
	if parent:IsA("BasePart") then return parent.Position end
	return nil
end

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local eye = camera.CFrame.Position
	local t = os.clock()
	for light, base in pairs(lights) do
		local position = positionOf(light)
		if position and (position - eye).Magnitude < MAX_DISTANCE then
			local n = math.noise(t * 3.3, base.seed) * .65 + math.noise(t * 11.7, base.seed + 31) * .35
			light.Brightness = base.brightness * (1 + BRIGHTNESS_SWING * n)
			light.Range = base.range * (1 + RANGE_SWING * n)
		end
	end
end)
