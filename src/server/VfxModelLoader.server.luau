--[[
	VfxModelLoader -- ServerScriptService

	Loads every uploaded VFX model (RS/Assets/Meshes/Vfx/VfxMeshes) once at server start and parents
	it to ReplicatedStorage.VfxModels under its registry key, for clients to clone. The assets are
	owned by the experience's creator, which is what lets a live server LoadAsset them.

	LoadAsset wraps the upload in a container Model; the real model is its first child. Parts are
	anchored and non-interactive here, once, so no client has to remember to.
]]

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VfxMeshes = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Meshes"):WaitForChild("Vfx"):WaitForChild("VfxMeshes"))

local folder = Instance.new("Folder")
folder.Name = "VfxModels"
folder.Parent = ReplicatedStorage

local function prepare(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
			if not d:IsA("MeshPart") then
				d.Transparency = 1 -- the importer's RootPart (the rig's anchor) is not art
			end
		end
	end
	if model:IsA("Model") and not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChild("RootPart")
	end
end

for key, assetId in pairs(VfxMeshes) do
	task.spawn(function()
		for attempt = 1, 3 do
			local ok, container = pcall(InsertService.LoadAsset, InsertService, assetId)
			if ok and container then
				local model = container:FindFirstChildWhichIsA("Model") or container:GetChildren()[1]
				if model then
					prepare(model)
					model.Name = key
					model.Parent = folder
				end
				container:Destroy()
				return
			end
			warn(string.format("[VfxModelLoader] %s (%d) load failed, attempt %d: %s", key, assetId, attempt, tostring(container)))
			task.wait(2 * attempt)
		end
	end)
end
