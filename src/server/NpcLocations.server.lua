--[[
	NpcLocations -- publishes where each NPC type stands, for client UI that points at one
	(the Journal's "Show on map", via RS/WorldMapRequest.NpcPosition).

	ReplicatedStorage.NpcLocations gets one Vector3 attribute per NpcType: the first copy found
	(tutorial copies only if nothing else exists). Read from the "NPC" CollectionService tag,
	so both NPC paths (the <Type>Bootstrap scripts and SpawnerService) are covered, and the
	client never has to find the model itself (it may not be streamed in).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:FindFirstChild("NpcLocations")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "NpcLocations"
	folder.Parent = ReplicatedStorage
end

local function isTutorial(model)
	local id = model:GetAttribute("NpcId")
	return type(id) == "string" and string.find(id, "_tutorial", 1, true) ~= nil
end

local function publish()
	local best = {} -- [npcType] = model
	for _, model in ipairs(CollectionService:GetTagged("NPC")) do
		local npcType = model:IsA("Model") and model:IsDescendantOf(workspace) and model:GetAttribute("NpcType")
		if type(npcType) == "string" and npcType ~= "" then
			local current = best[npcType]
			if not current or (isTutorial(current) and not isTutorial(model)) then
				best[npcType] = model
			end
		end
	end
	for npcType in pairs(folder:GetAttributes()) do
		if not best[npcType] then folder:SetAttribute(npcType, nil) end
	end
	for npcType, model in pairs(best) do
		folder:SetAttribute(npcType, model:GetPivot().Position)
	end
end

-- NPCs are tagged by their bootstraps as the server starts; republish as they appear or go.
local pending = false
local function schedule()
	if pending then return end
	pending = true
	task.delay(1, function()
		pending = false
		publish()
	end)
end

CollectionService:GetInstanceAddedSignal("NPC"):Connect(schedule)
CollectionService:GetInstanceRemovedSignal("NPC"):Connect(schedule)
schedule()
