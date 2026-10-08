-- Each client reconstructs the accepted weapon from replicated Tool metadata.
-- The server secures the hidden physical Tool; these cosmetic parts alone follow
-- a hand bone (CharacterAnimProfiles.GetAttachForTool: swords, pickaxes and spears Hand_R, bows Hand_L).
-- Combat still uses the Tool and camera/root raycasts.
--
-- Bows also get their string (two Beams from the nocks to a point that follows the
-- drawing hand while a draw or aim clip is playing, read off the replicated Animator,
-- so every client sees the same pull) and the nocked arrow along it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ActiveEquipment = require(ReplicatedStorage:WaitForChild("ActiveEquipment"))
local PotionPresentation = require(script.Parent:WaitForChild("PotionPresentation"))
local Profiles = require(ReplicatedStorage:WaitForChild("CharacterAnimProfiles"))
local BowConfig = require(ReplicatedStorage:WaitForChild("BowConfig"))
local BowAnimations = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("BowAnimations"))

local STRING_REST = (BowConfig.NOCK_TOP + BowConfig.NOCK_BOTTOM) / 2

local visuals = Instance.new("Folder")
visuals.Name = "HarukaWeaponVisuals"
visuals.Parent = workspace
local characters, playerConnections = {}, {}

local function setStatus(state, status)
	if state.status == status then return end
	state.status = status
	state.character:SetAttribute("WeaponPresentationStatus", status)
end

local function clearVisual(state)
	if state.model then state.model:Destroy() end
	state.model, state.parts, state.bone, state.offset, state.bow = nil, nil, nil, nil, nil
end

-- 0..1: how much a draw (past the nock) or full-draw clip is holding the string back.
local function stringPull(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return 0 end
	local pull = 0
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local id = track.Animation and track.Animation.AnimationId
		if id == BowAnimations.T1_BOW_AIM
			or (id == BowAnimations.T1_BOW_DRAW and track.TimePosition >= BowConfig.NOCK_TIME) then
			pull += track.WeightCurrent
		end
	end
	return pull
end

local function buildBowExtras(state, bowPart)
	local mesh = state.character:FindFirstChild("Hero_Character")
	local hand = mesh and mesh:FindFirstChild("Hand_R", true)
	local function attachment(name, position)
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = position
		a.Parent = bowPart
		return a
	end
	local top = attachment("NockTop", BowConfig.NOCK_TOP)
	local bottom = attachment("NockBottom", BowConfig.NOCK_BOTTOM)
	local nock = attachment("Nock", STRING_REST)
	local beams = {}
	for _, pair in ipairs({ { top, nock }, { nock, bottom } }) do
		local beam = Instance.new("Beam")
		beam.Name = "String"
		beam.Attachment0, beam.Attachment1 = pair[1], pair[2]
		beam.Width0, beam.Width1 = BowConfig.STRING_WIDTH, BowConfig.STRING_WIDTH
		beam.Color = ColorSequence.new(BowConfig.STRING_COLOR)
		beam.Transparency = NumberSequence.new(0)
		beam.FaceCamera = true
		beam.Segments = 1
		beam.LightInfluence = 1
		beam.Parent = bowPart
		table.insert(beams, beam)
	end
	local arrow
	local templates = ReplicatedStorage:FindFirstChild(BowConfig.VISUALS_FOLDER)
	local template = templates and templates:FindFirstChild(BowConfig.ARROW_TEMPLATE)
	if template then
		arrow = template:Clone()
		arrow.Anchored = true
		arrow.CanCollide, arrow.CanTouch, arrow.CanQuery = false, false, false
		arrow.LocalTransparencyModifier = 1
		arrow.Parent = state.model
	end
	state.bow = { part = bowPart, hand = hand and hand:IsA("Bone") and hand or nil, nock = nock, beams = beams, arrow = arrow }
end

local function updateBow(state, hidden)
	local bow = state.bow
	local bowFrame = bow.part.CFrame
	local drawn = not hidden and bow.hand ~= nil and stringPull(state.character) > 0.5
	local nockWorld = drawn and bow.hand.TransformedWorldCFrame * BowConfig.NOCK_HAND or bowFrame * STRING_REST
	bow.nock.Position = bowFrame:PointToObjectSpace(nockWorld)
	for _, beam in ipairs(bow.beams) do beam.Enabled = not hidden end
	if bow.arrow then
		if drawn then
			local along = bowFrame * BowConfig.ARROW_REST - nockWorld
			if along.Magnitude > 0.05 then
				along = along.Unit
				bow.arrow.CFrame = CFrame.lookAt(nockWorld + along * (BowConfig.ARROW_LENGTH / 2), nockWorld + along * BowConfig.ARROW_LENGTH)
			end
		end
		bow.arrow.LocalTransparencyModifier = drawn and 0 or 1
	end
end

local function disconnect(connections)
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
end

local function resolveVisual(state)
	local character, tool = state.character, state.tool
	if not tool then
		setStatus(state, character:GetAttribute(ActiveEquipment.ATTRIBUTE) and "WaitingForTool" or "Unequipped")
		return
	end
	local attach = Profiles.GetAttachForTool(tool)
	if not attach then setStatus(state, "Unsupported"); return end
	if not character:FindFirstChild("Hero_Character") then setStatus(state, "WaitingForMesh"); return end
	if tool:GetAttribute("BoneWeaponVisual") ~= true then setStatus(state, "WaitingForMetadata"); return end
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then setStatus(state, "WaitingForHandle"); return end
	local mesh = character:FindFirstChild("Hero_Character")
	local bone = mesh:FindFirstChild(attach.bone, true)
	if not bone or not bone:IsA("Bone") then setStatus(state, "WaitingFor" .. attach.bone); return end
	local sources = {}
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") then
			if type(part:GetAttribute("DungeonVisualTransparency")) ~= "number"
				or typeof(part:GetAttribute("DungeonVisualOffset")) ~= "CFrame" then
				setStatus(state, "WaitingForMetadata")
				return
			end
			table.insert(sources, part)
		end
	end
	if #sources ~= tool:GetAttribute("BoneWeaponPartCount") then setStatus(state, "WaitingForParts"); return end
	local model = Instance.new("Model")
	model.Name = "Weapon_" .. character.Name
	local parts = {}
	for _, source in ipairs(sources) do
		local part = source:Clone()
		if not part then model:Destroy(); setStatus(state, "MeshNotCloneable"); return end
		-- Copy visual data only, never scripts, joints, effects or nested parts.
		for _, child in ipairs(part:GetChildren()) do
			if not (child:IsA("DataModelMesh") or child:IsA("SurfaceAppearance") or child:IsA("Decal")) then
				child:Destroy()
			end
		end
		part.Anchored = true
		part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
		part.Transparency = source:GetAttribute("DungeonVisualTransparency")
		part.LocalTransparencyModifier = 0
		local offset = source:GetAttribute("DungeonVisualOffset")
		part.CFrame = bone.TransformedWorldCFrame * attach.offset * offset
		part.Parent = model
		table.insert(parts, { part = part, source = source, offset = offset })
	end
	state.model, state.parts, state.bone, state.offset = model, parts, bone, attach.offset
	if attach.kind == "Bow" and parts[1] then
		local handlePart = parts[1].part
		for _, entry in ipairs(parts) do
			if entry.source == handle then handlePart = entry.part end
		end
		buildBowExtras(state, handlePart)
	end
	model.Parent = visuals
	setStatus(state, "Ready")
end

local function unwatchCharacter(character)
	local state = characters[character]
	if not state then return end
	characters[character] = nil
	state.stopObserving()
	disconnect(state.connections)
	disconnect(state.toolConnections)
	clearVisual(state)
end

local function watchCharacter(character)
	if characters[character] then return end
	local state = { character = character, connections = {}, toolConnections = {}, dirty = true }
	characters[character] = state
	local function dirty() state.dirty = true end
	state.stopObserving = ActiveEquipment.Observe(character, function(tool)
		if tool ~= state.tool then
			clearVisual(state)
			disconnect(state.toolConnections)
			state.tool = tool
			state.waitStarted, state.warned = os.clock(), false
			if tool then
				local function watchPart(part)
					if part:IsA("BasePart") then
						table.insert(state.toolConnections, part.AttributeChanged:Connect(dirty))
					end
				end
				for _, part in ipairs(tool:GetDescendants()) do watchPart(part) end
				table.insert(state.toolConnections, tool.DescendantAdded:Connect(function(part)
					watchPart(part)
					dirty()
				end))
			end
		end
		dirty()
	end)
	table.insert(state.connections, character.DescendantAdded:Connect(dirty))
	table.insert(state.connections, character.DescendantRemoving:Connect(dirty))
end

local function watchPlayer(player)
	playerConnections[player] = {
		player.CharacterAdded:Connect(watchCharacter),
		player.CharacterRemoving:Connect(unwatchCharacter),
	}
	if player.Character then watchCharacter(player.Character) end
end

Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(player)
	if player.Character then unwatchCharacter(player.Character) end
	if playerConnections[player] then disconnect(playerConnections[player]); playerConnections[player] = nil end
end)
for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end

-- After the camera's root rotation and character pose work, before rendering.
RunService:BindToRenderStep("HarukaWeaponAttachment", Enum.RenderPriority.Last.Value, function()
	for character, state in pairs(characters) do
		if not character.Parent then unwatchCharacter(character); continue end
		if state.tool ~= ActiveEquipment.GetTool(character) then
			-- Stop displaying immediately; the coalesced observer will rebuild.
			clearVisual(state)
			continue
		end
		if state.dirty then
			state.dirty = false
			clearVisual(state)
			resolveVisual(state)
		end
		if state.model then
			local cf = state.bone.TransformedWorldCFrame * state.offset
			-- Follow the actual replicated track. A failed load never hides the weapon.
			local drinking = PotionPresentation.IsDrinking(character)
			for _, entry in ipairs(state.parts) do
				entry.part.CFrame = cf * entry.offset
				entry.part.LocalTransparencyModifier = drinking and 1 or 0
			end
			if state.bow then updateBow(state, drinking) end
		elseif state.tool and not state.warned and os.clock() - state.waitStarted > 5
			and Profiles.GetAttachForTool(state.tool) ~= nil then
			state.warned = true
			warn("[WeaponAttachClient]", character.Name, state.status, state.tool:GetAttribute("DungeonItemUuid"))
		end
	end
end)

print("[WeaponAttachClient] ready")
