--[[
	MiasmaArenaResolver -- turns arena-local layout data into world positions for ONE realm
	(the master template or a live clone). All placement comes from RS/MiasmaArenaLayout via
	MiasmaArenaAnchorData; a Studio instance with the same ANCHOR_* name inside the realm's
	arena root overrides a position (that is how a single anchor is nudged by hand).

	Arena-local origin: top-centre of the arena Baseplate.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local AnchorData = require(ReplicatedStorage:WaitForChild("MiasmaArenaAnchorData"))
local Layout = require(ReplicatedStorage:WaitForChild("MiasmaArenaLayout"))
local StationPlacement = require(script.Parent:WaitForChild("MiasmaValveStationPlacement"))

local Resolver = {}
Resolver.__index = Resolver

function Resolver.new(realm)
	local room = realm:FindFirstChild("T1 BOSS ROOM")
	room = room and room:FindFirstChild("miasma") or realm
	local root = room and room:FindFirstChild("T1DungeonTemplate") or room or realm
	local base = root and root:FindFirstChild("Baseplate", true)
	local origin
	if base and base:IsA("BasePart") then
		origin = base.CFrame * CFrame.new(0, base.Size.Y * .5, 0)
	elseif root and root:IsA("Model") then
		origin = root:GetPivot()
	else
		origin = realm:GetPivot()
	end
	return setmetatable({ Realm = realm, Room = room, Root = root, Origin = origin }, Resolver)
end

function Resolver:Find(name)
	return self.Root and self.Root:FindFirstChild(name, true)
end

function Resolver:Position(name, fallback)
	local found = self:Find(name)
	if found then
		if found:IsA("BasePart") then return found.Position end
		if found:IsA("Attachment") then return found.WorldPosition end
		if found:IsA("Model") then return found:GetPivot().Position end
	end
	local localPosition = AnchorData[name] or fallback or Vector3.zero
	return self.Origin:PointToWorldSpace(localPosition)
end

function Resolver:ToWorld(localPosition)
	return self.Origin:PointToWorldSpace(localPosition)
end

--[[
	Valve station frame for gate `index` (1..4). See MiasmaValveStationPlacement for the
	frame convention. The layout builder places ANCHOR_ValveStation_0N parts in the arena;
	without them the layout data is used directly (identical values).
]]
function Resolver:ValveStationFrame(index)
	local anchor = self.Realm and self.Realm:FindFirstChild(StationPlacement.AnchorNamePattern:format(index), true)
	if anchor then
		if anchor:IsA("BasePart") then return anchor.CFrame end
		if anchor:IsA("Attachment") then return anchor.WorldCFrame end
	end
	if not Layout.Stations[index] then return self.Origin end
	return self.Origin * Layout.StationFrame(index)
end

-- Centre of gate `index`'s protected area: station footprint plus its approach.
function Resolver:GatePosition(index)
	return self:ValveStationFrame(index):PointToWorldSpace(Vector3.new(-1, 0, 4))
end

function Resolver:AltarPosition(index)
	local altar = Layout.Altars[index]
	return self:Position(altar and altar.Anchor or "ANCHOR_CleanseAltar_NW")
end

function Resolver:SafeAreaPositions()
	local values = {}
	for i = 1, #Layout.SafeAreas do
		table.insert(values, self:Position(("ANCHOR_PurgeSafe_%02d"):format(i)))
	end
	return values
end

function Resolver:SackPositions()
	local values = {}
	for i = 1, #Layout.SackAngles do
		table.insert(values, self:Position(("ANCHOR_PoisonSack_%02d"):format(i)))
	end
	return values
end

-- Static channel geometry built by MiasmaArenaLayoutBuilder (nil in a realm without it).
function Resolver:ChannelModel(index)
	return self:Find(("MiasmaChannel_%02d"):format(index))
end

function Resolver:CenterBasin()
	return self:Find("MiasmaCenterBasin")
end

-- Every protected centre: altars and valve stations (controls, plates, approaches).
function Resolver:ProtectedCentres()
	local protected = { self:AltarPosition(1), self:AltarPosition(2) }
	for i = 1, #Layout.Stations do table.insert(protected, self:GatePosition(i)) end
	return protected
end

function Resolver:IsProtected(position, extraPositions)
	local protected = self:ProtectedCentres()
	for _, p in ipairs(extraPositions or {}) do table.insert(protected, p) end
	for _, p in ipairs(protected) do
		local flat = Vector3.new(position.X - p.X, 0, position.Z - p.Z)
		if flat.Magnitude <= Config.Arena.ProtectedRadius then return true end
	end
	return false
end

return Resolver
