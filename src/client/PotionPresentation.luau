-- A local visual for the custom skinned hand, visible independently on every client.
-- No Animator is driven here. Reuses the accepted Tool's metadata and authored meshes.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("PotionDrinkConfig"))
local Potions = require(RS:WaitForChild("PotionConfig"))
local Animations = require(RS:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("PotionAnimations"))
local Presentation = {}
local states, watches = {}, {}
local renderConnection

function Presentation.TrackStarted(character, track)
	local watch = watches[character]
	if watch then
		watch.track = track
		watch.expiresAt = workspace:GetServerTimeNow() + Config.ANIMATION_DURATION + Config.ANIMATION_FADE_OUT
	end
end

function Presentation.IsDrinking(character)
	local watch = watches[character]
	return watch ~= nil and watch.track ~= nil and watch.track.IsPlaying
		and workspace:GetServerTimeNow() < (watch.expiresAt or 0)
end

local function destroy(state)
	state.model:Destroy()
	states[state] = nil
end

local function update(state)
	state.visible = state.tool and state.tool.Parent == state.character or Presentation.IsDrinking(state.character)
	state.model.Parent = state.visible and workspace or nil
	local cf = state.bone.TransformedWorldCFrame * Config.BONE_GRIP
	for _, entry in ipairs(state.parts) do entry.part.CFrame = cf * entry.offset end
end

local function step()
	local now = os.clock()
	for state in pairs(states) do
		local held = state.tool and state.tool.Parent == state.character
		if not state.character.Parent or not state.bone.Parent or state.humanoid.Health <= 0
			or (not held and now >= state.keepUntil) then
			destroy(state)
		else
			update(state)
		end
	end
	if not next(states) and renderConnection then renderConnection:Disconnect(); renderConnection = nil end
end

function Presentation.Get(character, uuid)
	for state in pairs(states) do
		if state.character == character and state.uuid == uuid then
			if not state.bone.Parent or not state.character.Parent then destroy(state); return nil end
			update(state)
			return state
		end
	end
	return nil
end

local function build(character, uuid, itemId, source, tool)
	local existing = Presentation.Get(character, uuid)
	if existing then return existing end
	local mesh = character:FindFirstChild("Hero_Character")
	local bone = mesh and mesh:FindFirstChild("Hand_R", true)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local handle = source and (source:FindFirstChild("Handle") or source:FindFirstChild("Glass"))
	if not bone or not bone:IsA("Bone") or not humanoid or not handle then return nil end
	if tool then
		local count = 0
		for _, part in ipairs(source:GetChildren()) do
			if part:IsA("BasePart") then
				if typeof(part:GetAttribute("PotionVisualOffset")) ~= "CFrame"
					or type(part:GetAttribute("PotionVisualTransparency")) ~= "number" then return nil end
				count += 1
			end
		end
		if count ~= tool:GetAttribute("PotionVisualPartCount") then return nil end
	end
	local model = Instance.new("Model")
	model.Name = "HeldPotion_" .. character.Name
	local state = {character = character, uuid = uuid, tool = tool, model = model,
		bone = bone, humanoid = humanoid, parts = {}, keepUntil = 0}
	for _, sourcePart in ipairs(source:GetChildren()) do
		if sourcePart:IsA("BasePart") then
			local offset = sourcePart:GetAttribute("PotionVisualOffset")
			if typeof(offset) ~= "CFrame" then offset = handle.CFrame:ToObjectSpace(sourcePart.CFrame) end
			local copy = sourcePart:Clone()
			for _, child in ipairs(copy:GetChildren()) do
				if not (child:IsA("DataModelMesh") or child:IsA("SurfaceAppearance") or child:IsA("Decal")) then child:Destroy() end
			end
			copy.Anchored = true
			copy.CanCollide, copy.CanTouch, copy.CanQuery = false, false, false
			copy.LocalTransparencyModifier = 0
			copy.Transparency = sourcePart:GetAttribute("PotionVisualTransparency") or sourcePart.Transparency
			if copy.Name == "Glass" then copy.Name = "Handle" end
			if copy.Name == "Liquid" then copy.Color = Potions.Tiers[itemId].drinkColor end
			copy.Parent = model
			table.insert(state.parts, {part = copy, offset = offset})
		end
	end
	update(state)
	states[state] = true
	if not renderConnection then renderConnection = RunService.RenderStepped:Connect(step) end
	return state
end

function Presentation.Prepare(payload, lifetime)
	local character = payload.character
	if not character then return nil end
	-- Rapid drinks from different stacks share one visible vial, not several overlapping props.
	for other in pairs(states) do
		if other.character == character and other.uuid ~= payload.itemUuid and not other.tool then destroy(other) end
	end
	local state = Presentation.Get(character, payload.itemUuid)
	if not state then
		for _, tool in ipairs(character:GetChildren()) do
			if tool:IsA("Tool") and tool:GetAttribute("DungeonItemUuid") == payload.itemUuid
				and tool:GetAttribute("BonePotionVisual") then
				state = build(character, payload.itemUuid, payload.itemId, tool, tool)
				break
			end
		end
	end
	-- The last item is spent before the raise starts, or the drink came straight from the bag
	-- (quick-drink key, nothing in hand). Keep only a cosmetic vial; it cannot be used again
	-- and expires with this confirmed drink.
	if payload.itemGone or payload.fromBag then
		if not state then
			local cfg = Potions.Tiers[payload.itemId]
			local templates = RS:FindFirstChild("PotionDrinkVisuals")
			local source = templates and cfg and templates:FindFirstChild(cfg.visualModel)
			state = build(character, payload.itemUuid, payload.itemId, source, nil)
		end
		if state then
			local age = math.max(0, workspace:GetServerTimeNow() - payload.sentAt)
			state.keepUntil = math.max(state.keepUntil, os.clock() + math.max(0, lifetime - age))
		end
	end
	return state
end

local function watchCharacter(character)
	if watches[character] then return end
	local connections = {tools = {}}; watches[character] = connections
	local function bindAnimator()
		local hum = character:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if not animator or connections.animator == animator then return end
		connections.animator = animator
		local function played(track)
			if Animations.T1_POTION_DRINK ~= "" and track.Animation
				and track.Animation.AnimationId == Animations.T1_POTION_DRINK then
				Presentation.TrackStarted(character, track)
			end
		end
		table.insert(connections, animator.AnimationPlayed:Connect(played))
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do played(track) end
	end
	table.insert(connections, character.DescendantAdded:Connect(function(child)
		if child:IsA("Animator") then bindAnimator() end
	end))
	bindAnimator()
	local function watchTool(tool)
		if not tool:IsA("Tool") or connections.tools[tool] then return end
		local toolConnections = {}
		connections.tools[tool] = toolConnections
		local function refresh()
			local itemId, uuid = tool:GetAttribute("DungeonItemId"), tool:GetAttribute("DungeonItemUuid")
			if tool.Parent == character and Potions.Tiers[itemId] and uuid and tool:GetAttribute("BonePotionVisual") then
				build(character, uuid, itemId, tool, tool)
			end
		end
		toolConnections.refresh = refresh
		local function watchPart(part)
			if part:IsA("BasePart") then table.insert(toolConnections, part.AttributeChanged:Connect(refresh)) end
		end
		for _, part in ipairs(tool:GetDescendants()) do watchPart(part) end
		table.insert(toolConnections, tool.AttributeChanged:Connect(refresh))
		table.insert(toolConnections, tool.DescendantAdded:Connect(function(part) watchPart(part); refresh() end))
		table.insert(toolConnections, tool.AncestryChanged:Connect(function()
			if tool.Parent ~= character then
				for _, connection in ipairs(toolConnections) do connection:Disconnect() end
				connections.tools[tool] = nil
			end
		end))
		refresh()
	end
	table.insert(connections, character.ChildAdded:Connect(watchTool))
	table.insert(connections, character.DescendantAdded:Connect(function(child)
		if child.Name == "Hand_R" then
			for _, toolConnections in pairs(connections.tools) do toolConnections.refresh() end
		end
	end))
	for _, tool in ipairs(character:GetChildren()) do watchTool(tool) end
end

local function unwatchCharacter(character)
	local watch = watches[character]
	for _, connection in ipairs(watch or {}) do connection:Disconnect() end
	for _, connections in pairs(watch and watch.tools or {}) do
		for _, connection in ipairs(connections) do connection:Disconnect() end
	end
	watches[character] = nil
	for state in pairs(states) do if state.character == character then destroy(state) end end
end

local playerConnections = {}
local function watchPlayer(player)
	playerConnections[player] = {
		player.CharacterAdded:Connect(watchCharacter), player.CharacterRemoving:Connect(unwatchCharacter),
	}
	if player.Character then watchCharacter(player.Character) end
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(player)
	if player.Character then unwatchCharacter(player.Character) end
	for _, connection in ipairs(playerConnections[player] or {}) do connection:Disconnect() end
	playerConnections[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end

return Presentation
