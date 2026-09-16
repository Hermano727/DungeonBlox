--!strict
--[[
	ArmorVisualsService
	Physically equips/unequips the "wear what you have equipped" armor mesh onto a
	player's R15 character, driven by ProfileService.equipped[slot]. Rigid weld only
	(one Motor6D per slot, to whichever single BasePart ArmorEquipVisuals' AttachPart
	says -- UpperTorso by default, Head for Helm, etc.) -- no cage/Layered Clothing
	deformation, so the whole piece can only ever follow ONE bone's motion. That's
	fine for a bone that doesn't bend relative to itself (UpperTorso, Head) and
	genuinely wrong for anything spanning a joint that moves independently of it
	(legs bending at hip+knee, feet swinging separately) -- see the big comment in
	ArmorEquipVisuals.lua over why Legs/Boots are deliberately unregistered rather
	than wired up looking wrong. See ArmorEquipVisuals for the slot -> prefab lookup
	and ServerStorage.ArmorModels for the source assets.

	Every armor MeshPart clone is named "ArmorVisual_<Slot>" and its Motor6D
	"ArmorVisualMotor_<Slot>" -- deliberately DIFFERENT names. An earlier version
	named both the same; since they shared the same parent, FindFirstChild()+Destroy()
	in RemoveVisual only ever cleaned up whichever one it found first, leaking the
	other on every unequip/re-equip. Caught by testing UnequipItem live, not by
	trusting the code read right. RemoveVisual searches the whole character
	(recursive FindFirstChild) rather than assuming a fixed parent, since different
	slots can now be welded to different BaseParts.

	Weld offset: C1 is always identity. C0 defaults to identity too (the prefab's
	own local origin placed exactly at the attach part's origin) UNLESS the entry in
	ArmorEquipVisuals sets WornC0/WornSize -- this relies on each prefab's pivot
	having been set close to its own geometric center at Blender/Studio-import
	time, which was NOT calibrated against a live R15 rig the way character bodies
	are (see the tripo-to-roblox-r15 skill), so identity is rarely the right worn
	position/scale in practice. T1Chestplate's identity C0 buried it inside this
	game's custom-scaled UpperTorso entirely -- invisible despite loading and
	rendering fine (confirmed by comparing against LootDropVisuals' identical
	MeshId/TextureID ground-drop clone, which IS visible). Nudge a new prefab's
	WornC0/WornSize live in Studio with UIDevTool (F6, Model mode) rather than
	guessing values -- Enter there prints a paste-ready snapshot for
	ArmorEquipVisuals.
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmorEquipVisuals = require(ReplicatedStorage:WaitForChild("ArmorEquipVisuals"))

local ArmorVisualsService = {}

-- Feature flag: false shows the bare base model, no armor meshes at all (equip/respawn/
-- profile-sync all no-op silently through ApplyVisual below). Flip to true to re-enable.
local ARMOR_VISUALS_ENABLED = false

local ArmorModelsRoot = ServerStorage:WaitForChild("ArmorModels")

local function partName(slot: string): string
	return "ArmorVisual_" .. slot
end

local function motorName(slot: string): string
	return "ArmorVisualMotor_" .. slot
end

-- Digs through the Model>Model>MeshPart nesting Studio's FBX importer produces
-- and returns the first real BasePart found, wherever it's actually nested.
local function findMeshPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

function ArmorVisualsService.RemoveVisual(character: Model?, slot: string)
	if not character then
		return
	end
	-- Recursive (2nd arg true) rather than looking under one fixed parent -- the
	-- live visual could be welded to UpperTorso, Head, or wherever that slot's
	-- AttachPart pointed at whatever time it was applied.
	local existingPart = character:FindFirstChild(partName(slot), true)
	if existingPart then
		existingPart:Destroy()
	end
	local existingMotor = character:FindFirstChild(motorName(slot), true)
	if existingMotor then
		existingMotor:Destroy()
	end
end

function ArmorVisualsService.ApplyVisual(character: Model?, slot: string, itemId: any)
	if not character then
		return
	end
	ArmorVisualsService.RemoveVisual(character, slot)

	if not ARMOR_VISUALS_ENABLED then
		return -- feature flag off -- stay bare, don't create anything
	end

	local entry = ArmorEquipVisuals.Get(itemId, slot)
	if not entry then
		return -- nothing registered for this slot yet -- silent no-op, not an error
	end

	local slotFolder = ArmorModelsRoot:FindFirstChild(slot)
	local source = slotFolder and slotFolder:FindFirstChild(entry.PrefabName)
	if not source then
		warn(string.format("[ArmorVisualsService] missing prefab ServerStorage.ArmorModels.%s.%s", slot, entry.PrefabName))
		return
	end

	local attachPart = character:FindFirstChild(entry.AttachPart or "UpperTorso")
	if not attachPart or not attachPart:IsA("BasePart") then
		return -- not an R15 rig (e.g. mid-transition character), or a bad AttachPart name
	end

	local sourcePart = findMeshPart(source)
	if not sourcePart then
		warn(string.format("[ArmorVisualsService] prefab %s has no BasePart to clone", entry.PrefabName))
		return
	end

	local clone = sourcePart:Clone()
	clone.Name = partName(slot)
	clone.Anchored = false
	clone.CanCollide = false
	clone.CanTouch = false
	clone.Massless = true
	clone.CFrame = attachPart.CFrame
	clone.Parent = attachPart

	if entry.WornSize then
		clone.Size = entry.WornSize
	end

	local motor = Instance.new("Motor6D")
	motor.Name = motorName(slot)
	motor.Part0 = attachPart
	motor.Part1 = clone
	motor.C0 = entry.WornC0 or CFrame.new()
	motor.C1 = CFrame.new()
	motor.Parent = attachPart
end

-- Reapplies every slot in profile.equipped onto a freshly spawned character --
-- Motor6D welds don't survive a respawn, profile.equipped does.
function ArmorVisualsService.ApplyAllFromProfile(player: Player, profile: any)
	local character = player.Character
	if not character or type(profile) ~= "table" or type(profile.equipped) ~= "table" then
		return
	end
	local inventory = profile.inventory
	for slot, uuid in pairs(profile.equipped) do
		local item = type(inventory) == "table" and inventory[uuid]
		local itemId = type(item) == "table" and item.itemId or nil
		ArmorVisualsService.ApplyVisual(character, slot, itemId)
	end
end

return ArmorVisualsService
