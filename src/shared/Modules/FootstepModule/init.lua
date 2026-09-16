export type SoundTable = {string}
export type SoundIds = {[string]: SoundTable}

-- Main Module
local main = {}

local FootstepSetsFolder = script:WaitForChild("Footsteps")
local LandingSetsFolder = script:WaitForChild("Landing")
local JumpingSetsFolder = script:WaitForChild("Jumping")

local Sets = {}

main.MaterialMap = {
	[Enum.Material.Slate] = 		"Concrete",
	[Enum.Material.Concrete] = 		"Concrete",
	[Enum.Material.Brick] = 		"Concrete",
	[Enum.Material.Cobblestone] = 	"Concrete",
	[Enum.Material.Sandstone] =		"Concrete",
	[Enum.Material.Rock] = 			"Concrete",
	[Enum.Material.Basalt] = 		"Concrete",
	[Enum.Material.CrackedLava] = 	"Concrete",
	[Enum.Material.Asphalt] = 		"Concrete",
	[Enum.Material.Limestone] = 	"Concrete",
	[Enum.Material.Pavement] = 		"Concrete",

	[Enum.Material.Plastic] = 		"Tile",
	[Enum.Material.Marble] = 		"Tile",
	[Enum.Material.Neon] = 			"Tile",
	[Enum.Material.Granite] = 		"Tile",

	[Enum.Material.Wood] = 			"Wood",
	[Enum.Material.WoodPlanks] = 	"Wood",

	[Enum.Material.Water] = 		"Slosh",

	[Enum.Material.CorrodedMetal] = "Metal_Solid",
	[Enum.Material.DiamondPlate] = 	"Metal_Solid",
	[Enum.Material.Metal] = 		"Metal_Solid",

	[Enum.Material.Foil] = 			"Metal_Grate",

	[Enum.Material.Ground] = 		"Dirt",

	[Enum.Material.Grass] = 		"Grass",
	[Enum.Material.LeafyGrass] = 	"Grass",

	[Enum.Material.Fabric] = 		"Carpet",

	[Enum.Material.Pebble] = 		"Gravel",

	[Enum.Material.Snow] = 			"Snow",

	[Enum.Material.Sand] = 			"Sand",
	[Enum.Material.Salt] = 			"Sand",

	[Enum.Material.Ice] = 			"Glass",
	[Enum.Material.Glacier] = 		"Glass",
	[Enum.Material.Glass] = 		"Glass",

	[Enum.Material.SmoothPlastic] = "Rubber",
	[Enum.Material.ForceField] = 	"Rubber",

	[Enum.Material.Mud] = 			"Mud",
}

Sets[FootstepSetsFolder.Name] = {}
for _,v in pairs(FootstepSetsFolder:GetChildren()) do
	Sets[FootstepSetsFolder.Name][v.Name] = require(v)
end

Sets[LandingSetsFolder.Name] = {}
for _,v in pairs(LandingSetsFolder:GetChildren()) do
	Sets[LandingSetsFolder.Name][v.Name] = require(v)
end

Sets[JumpingSetsFolder.Name] = {}
for _,v in pairs(JumpingSetsFolder:GetChildren()) do
	Sets[JumpingSetsFolder.Name][v.Name] = require(v)
end

-- This function produces a folder under a specified parent. --this function IS NOT USED
-- "soundProperties" is a table determining what the default properties of these audios will be.
function main:CreateSoundGroup(parent:Instance?, name:string?, soundProperties:{string:any}?, isFolder:boolean?) : SoundGroup|Folder
	if not parent then warn("Parent not specified, Footstep folder parented to workspace") end
	isFolder = isFolder or false
	soundProperties = soundProperties or {}
	parent = parent or workspace
	-- Create folder
	local SoundGroup = nil
	if not isFolder then
		SoundGroup = Instance.new("SoundGroup"); SoundGroup.Volume = 1; SoundGroup.Name = name or "Footsteps"
	else
		SoundGroup = Instance.new("Folder"); SoundGroup.Name = name or "Footsteps"
	end
	local index = 0
	for soundMaterial,soundList in pairs(main.SoundIds) do
		index = 0
		local sectionGroup = nil
		if not isFolder then
			sectionGroup = Instance.new("SoundGroup"); sectionGroup.Volume = 1; sectionGroup.Name = soundMaterial
		else
			sectionGroup = Instance.new("Folder"); sectionGroup.Name = soundMaterial
		end
		for _,soundId in pairs(soundList) do
			index += 1 -- Increment index
			local soundEffect = Instance.new("Sound")
			soundEffect.Name = string.format("%s_%02i",soundMaterial:lower(),index)
			-- Set optional sound group
			if not isFolder then
				soundEffect.SoundGroup = sectionGroup
			end
			for property,value in pairs(soundProperties) do
				soundEffect[property] = value
			end
			soundEffect.SoundId = soundId
			soundEffect.Parent = sectionGroup
		end
		sectionGroup.Parent = SoundGroup
	end

	SoundGroup.Parent = parent
	return SoundGroup
end

-- This function returns a table from the MaterialMap given the material.
function main:GetTableFromMaterial(EnumItem : Enum.Material|string) : { [string]: {string}}
	if typeof(EnumItem) == "string" then -- CONVERSION
		EnumItem = Enum.Material[EnumItem]
	end
	return main.MaterialMap[EnumItem]
end

-- This function is a primitive "pick randomly from table" function.
function main:GetRandomSound(SoundTable:{string}) : string
	return SoundTable[math.random(#SoundTable)]
end

function main:ConstructSound(Parent,ID,SoundGroup,Set)
	local Name = Parent.Name
	local sound = Instance.new("Sound")
	sound.SoundId = ID
	sound.Name = ID

	sound:SetAttribute("IsBass",Name == "Bass")
	sound:SetAttribute("DefaultVolume",Name == "Bass" and Set.DefaultBassVolume or Set.DefaultVolume)
	sound:SetAttribute("DefaultPitch", Set.DefaultPitch)
	sound:SetAttribute("DefaultRolloff", Set.DefaultRolloff)

	sound.Volume = sound:GetAttribute("DefaultVolume")
	sound.PlaybackSpeed = sound:GetAttribute("DefaultPitch")
	sound.RollOffMinDistance = sound:GetAttribute("DefaultRolloff")
	sound.RollOffMaxDistance = 250
	sound.RollOffMode = Enum.RollOffMode.InverseTapered

	sound.Parent = Parent
	if SoundGroup then
		sound.SoundGroup = SoundGroup
	elseif Parent:IsA("SoundGroup") then
		sound.SoundGroup = Parent
	end
	return sound
end

function main:GetCached(SoundGroup:SoundGroup, Type)
	local CachedSounds = {}

	do
		local function newdirectory(parent:Instance,name:string,instancetype:string)
			local directory = parent:FindFirstChild(name)
			if not directory then
				directory = Instance.new(instancetype or "Folder")
				if directory:IsA("SoundGroup") then
					directory.Volume = 1
				end
				directory.Name = name
				directory.Parent = parent
			end
			return directory
		end

		local function constructsound(id,name,set)
			if not SoundGroup:FindFirstChild(set) then
				-- FIX: this call was missing the instancetype argument, so it
				-- silently fell back to `Instance.new("Folder")` instead of a
				-- SoundGroup. Nested SoundGroup volume compounding only walks
				-- up through SoundGroup ancestors -- a plain Folder here (e.g.
				-- "Grass") breaks that chain, so everything below it (every
				-- actual footstep Sound) became deaf to Main.Character's
				-- Volume and, by extension, the Settings menu's SFX slider.
				newdirectory(SoundGroup,set,"SoundGroup")
			end

			local parent = newdirectory(SoundGroup[set],name,"SoundGroup")
			local sound = main:ConstructSound(parent,id, nil, Sets[Type][set])
			return sound
		end

		for setname,set in pairs(Sets[Type]) do
			CachedSounds[setname] = {}
			for Name, IDs in set.SoundIds do
				local result = {}
				for _, id in IDs do
					table.insert(result,constructsound(id,Name,setname))
				end
				CachedSounds[setname][Name] = result
			end
		end
	end

	return CachedSounds
end

return main