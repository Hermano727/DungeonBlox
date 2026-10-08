--[[
	NpcMapMarkers -- turns the server's list of NPCs into world-map markers (client side).

	SSS/NpcLocations publishes every NPC whose type has an NPCRegistry Nametag entry as a Folder
	under ReplicatedStorage.NpcLocations.Markers (attributes NpcType, Position). This module
	maps each one onto what the map draws, from the same registries the floating nametag uses,
	so a new NPC type shows on the map with nothing but its Nametag entry:

	    NpcMapMarkers.List() -> { { id, npcType, position: Vector3, name, icon } }
	        name  NPCRegistry DisplayName (the role, "Merchant", never a personal name)
	        icon  NpcNametagArt.ICONS[Nametag.Icon] ({ Image, Offset, Size }) or nil
	    NpcMapMarkers.Changed:Connect(fn)   -- the list changed (an NPC appeared, went or moved)

	The minimap (src/client/Minimap) decides where they're visible and draws them (MapView).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local Art = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("NpcNametagArt"))

local NpcMapMarkers = {}

local changed = Instance.new("BindableEvent")
NpcMapMarkers.Changed = changed.Event

local markersFolder -- ReplicatedStorage.NpcLocations.Markers, once it exists

local function entryFor(marker)
	local npcType = marker:GetAttribute("NpcType")
	local position = marker:GetAttribute("Position")
	local nametag = NPCRegistry.GetNametag(npcType)
	if not nametag or typeof(position) ~= "Vector3" then return nil end
	local registry = NPCRegistry.Get(npcType)
	return {
		id = marker.Name,
		npcType = npcType,
		position = position,
		name = registry and registry.DisplayName or npcType,
		icon = nametag.Icon and Art.ICONS[nametag.Icon] or nil,
	}
end

function NpcMapMarkers.List()
	local list = {}
	if markersFolder then
		for _, marker in ipairs(markersFolder:GetChildren()) do
			local entry = entryFor(marker)
			if entry then table.insert(list, entry) end
		end
	end
	return list
end

-- Watch the folder (it can stream in after this module loads); batch bursts into one Changed.
local pending = false
local function fire()
	if pending then return end
	pending = true
	task.defer(function()
		pending = false
		changed:Fire()
	end)
end

local function watchMarker(marker)
	marker.AttributeChanged:Connect(fire)
end

task.spawn(function()
	local locations = ReplicatedStorage:WaitForChild("NpcLocations")
	markersFolder = locations:WaitForChild("Markers")
	for _, marker in ipairs(markersFolder:GetChildren()) do watchMarker(marker) end
	markersFolder.ChildAdded:Connect(function(marker)
		watchMarker(marker)
		fire()
	end)
	markersFolder.ChildRemoved:Connect(fire)
	fire()
end)

return NpcMapMarkers
