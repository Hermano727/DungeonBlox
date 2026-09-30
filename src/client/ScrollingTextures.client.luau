--[[
	ScrollingTextures -- makes tagged Texture instances flow (client only, visual only).

	Tag a Texture "ScrollingTexture" and give it number attributes:
		ScrollU  studs per second along the texture's U (optional)
		ScrollV  studs per second along V. On a side face V runs downward, so + = falling
	The offset is computed from the clock and wrapped to one tile, so it never drifts or grows.
	Textures more than CULL_DISTANCE from the camera are left alone.

	Users: the Miasma arena poison falls (MiasmaArenaArtAssembler's poisonFall, edit-time).
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TAG = "ScrollingTexture"
local CULL_DISTANCE = 300

local textures = {} -- [Texture] = true

local function add(texture)
	if texture:IsA("Texture") then textures[texture] = true end
end

for _, texture in ipairs(CollectionService:GetTagged(TAG)) do add(texture) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(texture) textures[texture] = nil end)

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera or next(textures) == nil then return end
	local eye = camera.CFrame.Position
	local t = os.clock()
	for texture in pairs(textures) do
		local part = texture.Parent
		if part and part:IsA("BasePart") and (part.Position - eye).Magnitude < CULL_DISTANCE then
			local u = texture:GetAttribute("ScrollU")
			local v = texture:GetAttribute("ScrollV")
			if u then texture.OffsetStudsU = (t * u) % texture.StudsPerTileU end
			if v then texture.OffsetStudsV = (t * v) % texture.StudsPerTileV end
		end
	end
end)
