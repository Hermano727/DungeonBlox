--[[
	NpcLocations -- publishes where each NPC type stands, for client UI that points at one
	(the Journal's "Show on map", via RS/WorldMapRequest.NpcPosition).

	ReplicatedStorage.NpcLocations gets one Vector3 attribute per NpcType: the first copy found
	(tutorial copies only if nothing else exists). Read from the "NPC" CollectionService tag,
	so both NPC paths (the <Type>Bootstrap scripts and SpawnerService) are covered, and the
	client never has to find the model itself (it may not be streamed in).

	ReplicatedStorage.NpcLocations.Markers (2026-10-06): one Folder per NPC whose type has an
	NPCRegistry Nametag entry (every copy, tutorial copies left out), named by its NpcId, with
	attributes NpcType (string) and Position (Vector3). The world map draws them through
	RS/NpcMapMarkers.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))

local folder = ReplicatedStorage:FindFirstChild("NpcLocations")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "NpcLocations"
	folder.Parent = ReplicatedStorage
end

local markers = folder:FindFirstChild("Markers")
if not markers then
	markers = Instance.new("Folder")
	markers.Name = "Markers"
	markers.Parent = folder
end

local function isTutorial(model)
	local id = model:GetAttribute("NpcId")
	return type(id) == "string" and string.find(id, "_tutorial", 1, true) ~= nil
end

-- Every registered NPC on the map, one Folder each (see the header).
local function publishMarkers()
	local wanted = {} -- [name] = { npcType, position }
	for _, model in ipairs(CollectionService:GetTagged("NPC")) do
		local npcType = model:IsA("Model") and model:IsDescendantOf(workspace) and model:GetAttribute("NpcType")
		if type(npcType) == "string" and NPCRegistry.GetNametag(npcType) and not isTutorial(model) then
			local id = model:GetAttribute("NpcId")
			local name = type(id) == "string" and id ~= "" and id or model:GetFullName()
			while wanted[name] do name ..= "_" end
			wanted[name] = { npcType = npcType, position = model:GetPivot().Position }
		end
	end
	for _, child in ipairs(markers:GetChildren()) do
		if not wanted[child.Name] then child:Destroy() end
	end
	for name, entry in pairs(wanted) do
		local marker = markers:FindFirstChild(name)
		if not marker then
			marker = Instance.new("Folder")
			marker.Name = name
			marker:SetAttribute("NpcType", entry.npcType)
			marker:SetAttribute("Position", entry.position)
			marker.Parent = markers
		else
			marker:SetAttribute("NpcType", entry.npcType)
			marker:SetAttribute("Position", entry.position)
		end
	end
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
	publishMarkers()
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
