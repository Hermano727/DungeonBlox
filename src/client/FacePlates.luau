--[[
	FacePlates -- draws faces (eyes / nose / mouth) on the skinned player characters (client).

		local detach = FacePlates.Attach(model)   -- any Hero_Character rig (players, wardrobe clone)
		FacePlates.Start()                        -- auto-attach every player's character

	The head is part of ONE skinned mesh (Hero_Character), so a face can't be a Decal on the
	body (a Decal covers the whole part's box) or welded to it (the head moves by bone, not by
	part). Instead each client keeps a thin FacePlate (a shell cut from the head's front,
	assets/models/main character/face/FacePlate.fbx, template in ReplicatedFirst) on every rig
	and moves it to the Head bone's ANIMATED transform every frame -- the same approach
	WeaponAttachClient uses for the sword in the hand. The plate part itself is invisible;
	three Decals on its front draw the chosen features (AppearanceOptions Decal ids), picked by
	the model's "Appearance_<Feature>" attributes (RS/AppearanceApply sets them; server-set ones
	replicate). Your own face is hidden in first person (the camera sits inside the head).

	HAIR rides the same head bone: the chosen Hair option's Model (a MeshPart template in
	ReplicatedFirst.CharacterParts, built from the head's own scalp, assets/models/main
	character/hair/) sits at its Offset from the body mesh, coloured by HairColor. It is hidden
	under a helmet (ArmorVisualsService's "ArmorVisual_Helm") and in your own first person.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AppearanceOptions = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Appearance"):WaitForChild("AppearanceOptions"))
local AppearanceApply = require(ReplicatedStorage:WaitForChild("AppearanceApply"))

local FacePlates = {}

local TEMPLATE_NAME = "FacePlate"
local HEAD_BONE = "Head"
-- Where the plate's centre sits on the body mesh in its rest pose, in the body part's own
-- space (studs). Measured in Blender (face_plate_build: plate centre minus body box centre),
-- converted to Roblox axes (x, y, z) = (-x, z, y) of Blender's.
local PLATE_FROM_BODY = CFrame.new(0.0099, 2.1673, -0.1202)

local HELM_PART = "ArmorVisual_Helm"
local HELM_CHECK_EVERY = 0.4

local folder
local active = {} -- [model] = state
local loop

local function template()
	return ReplicatedFirst:FindFirstChild(TEMPLATE_NAME, true)
end

local function isLocalFirstPerson(model)
	local player = Players.LocalPlayer
	return model == player.Character and player:GetAttribute("FirstPersonView") == true
end

local function refreshDecals(state)
	local hidden = isLocalFirstPerson(state.model)
	for _, id in ipairs(AppearanceOptions.FaceLayers) do
		local decal = state.decals[id]
		local optionId = state.model:GetAttribute(AppearanceApply.ATTRIBUTE_PREFIX .. id)
		local option = AppearanceOptions.GetOption(id, optionId)
			or AppearanceOptions.GetOption(id, AppearanceOptions.GetCategory(id).Default)
		local texture = option and option.Decal or ""
		decal.Texture = texture
		decal.Transparency = (hidden or texture == "") and 1 or 0
	end
	local eyes = AppearanceOptions.GetOption("Eyes", state.model:GetAttribute(AppearanceApply.ATTRIBUTE_PREFIX .. "Eyes"))
		or AppearanceOptions.GetOption("Eyes", AppearanceOptions.GetCategory("Eyes").Default)
	local irisTexture = eyes and eyes.IrisDecal or ""
	local iris = state.decals.Iris
	iris.Texture = irisTexture
	iris.Color3 = AppearanceOptions.RampColor("EyeColor", state.model:GetAttribute(AppearanceApply.ATTRIBUTE_PREFIX .. "EyeColor"))
	iris.Transparency = (hidden or irisTexture == "") and 1 or 0
	state.hidden = hidden
end

local function hairOption(state)
	local id = state.model:GetAttribute(AppearanceApply.ATTRIBUTE_PREFIX .. "Hair")
	return AppearanceOptions.GetOption("Hair", id) or AppearanceOptions.GetOption("Hair", AppearanceOptions.GetCategory("Hair").Default)
end

-- Builds / swaps / recolours / shows-hides the hair piece for the model's current choice.
local function refreshHair(state)
	local option = hairOption(state)
	local modelName = option and option.Model or ""
	if modelName ~= state.hairName then
		if state.hair then state.hair:Destroy(); state.hair = nil end
		state.hairName = modelName
		local parts = ReplicatedFirst:FindFirstChild("CharacterParts")
		local source = modelName ~= "" and parts and parts:FindFirstChild(modelName)
		if source and source:IsA("BasePart") then
			local hair = source:Clone()
			hair.Name = "Hair_" .. state.model.Name
			hair.Anchored, hair.CanCollide, hair.CanQuery, hair.CanTouch = true, false, false, false
			hair.Massless = true
			state.hairOffset = state.bone.WorldCFrame:Inverse() * (state.body.CFrame * CFrame.new(option.Offset or Vector3.zero))
			hair.CFrame = state.bone.TransformedWorldCFrame * state.hairOffset
			hair.Parent = folder
			state.hair = hair
		end
	end
	if state.hair then
		state.hair.Color = AppearanceOptions.RampColor("HairColor", state.model:GetAttribute(AppearanceApply.ATTRIBUTE_PREFIX .. "HairColor"))
		local hidden = state.helmet or isLocalFirstPerson(state.model)
		state.hair.Transparency = hidden and 1 or 0
	end
end

local function step()
	local parts, cframes = {}, {}
	local now = os.clock()
	for model, state in pairs(active) do
		if not model.Parent or not state.bone.Parent then
			FacePlates.Detach(model)
		else
			local head = state.bone.TransformedWorldCFrame
			table.insert(parts, state.plate)
			table.insert(cframes, head * state.offset)
			if state.hair then
				table.insert(parts, state.hair)
				table.insert(cframes, head * state.hairOffset)
			end
			local firstPerson = isLocalFirstPerson(model)
			if now >= (state.nextHelmCheck or 0) then
				state.nextHelmCheck = now + HELM_CHECK_EVERY
				local helmet = model:FindFirstChild(HELM_PART, true) ~= nil
				if helmet ~= state.helmet then state.helmet = helmet; refreshHair(state) end
			end
			if state.hidden ~= firstPerson then refreshDecals(state); refreshHair(state) end
		end
	end
	if #parts > 0 then Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged) end
end

function FacePlates.Attach(model)
	if typeof(model) ~= "Instance" or active[model] then return function() FacePlates.Detach(model) end end
	local source = template()
	local body = model:FindFirstChild("Hero_Character")
	local bone = body and body:FindFirstChild(HEAD_BONE, true)
	if not source or not body or not bone or not bone:IsA("Bone") then return nil end

	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "FacePlates"
		folder.Parent = Workspace
	end
	local plate = source:Clone()
	plate.Name = "FacePlate_" .. model.Name
	plate.Anchored, plate.CanCollide, plate.CanQuery, plate.CanTouch = true, false, false, false
	plate.CastShadow = false
	plate.Transparency = 1 -- only the decals draw
	for _, d in ipairs(plate:GetChildren()) do
		if d:IsA("Decal") then d:Destroy() end
	end
	local decals = {}
	for i, id in ipairs(AppearanceOptions.FaceLayers) do
		local decal = Instance.new("Decal")
		decal.Name = id
		decal.Face = Enum.NormalId.Front
		decal.ZIndex = i * 2
		decal.Parent = plate
		decals[id] = decal
	end
	-- The iris sits just under the eyes and is tinted by EyeColor (only when the chosen eyes
	-- have a separate iris image; see AppearanceOptions IrisDecal).
	local iris = Instance.new("Decal")
	iris.Name = "Iris"
	iris.Face = Enum.NormalId.Front
	iris.ZIndex = decals.Eyes.ZIndex - 1
	iris.Parent = plate
	decals.Iris = iris
	-- Rest-pose placement relative to the head bone (Bone.WorldCFrame is the un-animated pose).
	local offset = bone.WorldCFrame:Inverse() * (body.CFrame * PLATE_FROM_BODY)
	plate.CFrame = bone.TransformedWorldCFrame * offset
	plate.Parent = folder

	local state = { model = model, body = body, plate = plate, bone = bone, offset = offset, decals = decals }
	state.helmet = model:FindFirstChild(HELM_PART, true) ~= nil
	state.attrConn = model.AttributeChanged:Connect(function(name)
		if name:sub(1, #AppearanceApply.ATTRIBUTE_PREFIX) == AppearanceApply.ATTRIBUTE_PREFIX then
			refreshDecals(state)
			refreshHair(state)
		end
	end)
	active[model] = state
	refreshDecals(state)
	refreshHair(state)
	if not loop then loop = RunService:BindToRenderStep("FacePlates", Enum.RenderPriority.Camera.Value - 1, step) or true end
	return function() FacePlates.Detach(model) end
end

function FacePlates.Detach(model)
	local state = active[model]
	if not state then return end
	active[model] = nil
	state.attrConn:Disconnect()
	state.plate:Destroy()
	if state.hair then state.hair:Destroy() end
end

-- Download every face image up front. A Decal whose Texture changes to an image the client
-- hasn't fetched yet draws BLANK until the download finishes (seconds, the first time), which
-- is what swapping mouths/eyes in the wardrobe looked like. Fetched once, every swap is instant.
local preloaded = false
function FacePlates.Preload()
	if preloaded then return end
	preloaded = true
	local ids = {}
	for _, id in ipairs(AppearanceOptions.FaceLayers) do
		for _, option in ipairs(AppearanceOptions.GetCategory(id).Options or {}) do
			for _, texture in ipairs({ option.Decal, option.IrisDecal }) do
				if type(texture) == "string" and texture ~= "" then table.insert(ids, texture) end
			end
		end
	end
	task.spawn(function() pcall(ContentProvider.PreloadAsync, ContentProvider, ids) end)
end

-- Every player's character, as it spawns (the body mesh streams in with it).
function FacePlates.Start()
	FacePlates.Preload()
	local function watch(player)
		local function onCharacter(character)
			task.spawn(function()
				local body = character:WaitForChild("Hero_Character", 20)
				if not body then return end
				for _ = 1, 40 do -- the template (ReplicatedFirst) and bones can arrive a moment later
					if FacePlates.Attach(character) then return end
					task.wait(.25)
				end
			end)
		end
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then onCharacter(player.Character) end
	end
	for _, player in ipairs(Players:GetPlayers()) do watch(player) end
	Players.PlayerAdded:Connect(watch)
end

return FacePlates
