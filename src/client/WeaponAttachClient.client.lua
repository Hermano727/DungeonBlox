-- Each client reconstructs the accepted weapon from replicated Tool metadata.
-- The server secures the hidden physical Tool; these cosmetic parts alone follow
-- Hand_R. Combat still uses the Tool and camera/root raycasts.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ActiveEquipment = require(ReplicatedStorage:WaitForChild("ActiveEquipment"))
local Profiles = require(ReplicatedStorage:WaitForChild("CharacterAnimProfiles"))

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
	state.model, state.parts, state.bone = nil, nil, nil
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
	if Profiles.GetProfileForTool(tool) ~= "Sword" then setStatus(state, "Unsupported"); return end
	if not character:FindFirstChild("Hero_Character") then setStatus(state, "WaitingForMesh"); return end
	if tool:GetAttribute("BoneWeaponVisual") ~= true then setStatus(state, "WaitingForMetadata"); return end
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then setStatus(state, "WaitingForHandle"); return end
	local mesh = character:FindFirstChild("Hero_Character")
	local bone = mesh:FindFirstChild("Hand_R", true)
	if not bone or not bone:IsA("Bone") then setStatus(state, "WaitingForHand_R"); return end
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
		part.CFrame = bone.TransformedWorldCFrame * Profiles.SWORD_GRIP_OFFSET * offset
		part.Parent = model
		table.insert(parts, { part = part, source = source, offset = offset })
	end
	state.model, state.parts, state.bone = model, parts, bone
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
			local cf = state.bone.TransformedWorldCFrame * Profiles.SWORD_GRIP_OFFSET
			for _, entry in ipairs(state.parts) do entry.part.CFrame = cf * entry.offset end
		elseif state.tool and not state.warned and os.clock() - state.waitStarted > 5
			and Profiles.GetProfileForTool(state.tool) == "Sword" then
			state.warned = true
			warn("[WeaponAttachClient]", character.Name, state.status, state.tool:GetAttribute("DungeonItemUuid"))
		end
	end
end)

print("[WeaponAttachClient] ready")
