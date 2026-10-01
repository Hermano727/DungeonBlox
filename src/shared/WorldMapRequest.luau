--[[
	WorldMapRequest -- lets any client UI open the world map (M) on a spot with a pin.

	The expanded map is owned by src/client/Minimap (its open state and pan live there), so
	other screens ask through here instead of reaching into it:

	    WorldMapRequest.ShowAt(position: Vector3, label: string)   -- e.g. the Journal's
	        "Show on map" for the Animal Trainer

	The Minimap opens (closing whatever menu was up: the map is a blocking overlay), centres on
	`position` and pins it with `label`. The pin clears when the map closes.

	NPC positions: SSS/NpcLocations publishes the first copy of each NpcType as a Vector3
	attribute on ReplicatedStorage.NpcLocations; NpcPosition(npcType) reads it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldMapRequest = {}

local listener: ((Vector3, string) -> ())? = nil

-- The Minimap registers itself here (one listener: there is one world map).
function WorldMapRequest.Listen(fn: (Vector3, string) -> ())
	listener = fn
end

function WorldMapRequest.ShowAt(position: Vector3, label: string): boolean
	if not listener then return false end
	listener(position, label)
	return true
end

function WorldMapRequest.NpcPosition(npcType: string): Vector3?
	local folder = ReplicatedStorage:FindFirstChild("NpcLocations")
	local value = folder and folder:GetAttribute(npcType)
	return typeof(value) == "Vector3" and value or nil
end

return WorldMapRequest
