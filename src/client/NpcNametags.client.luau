--[[
	NpcNametags -- the floating tag over every NPC whose type has an NPCRegistry Nametag entry
	(client only, one kit for all of them):

	        ( ICON )        crest: bronze ring + the type's role icon (Nametag.Icon)
	     <>===(  )===<>     name plaque, 9-sliced, as wide as the name
	     ||  Merchant  ||
	     <>==========<>
	           v            talk marker: dim, lit and bobbing while the NPC's prompt is shown

	  Distance: the whole tag within NEAR_DISTANCE studs of the camera, then the crest alone
	  (it drops to where the marker was) up to FAR_DISTANCE, then nothing. A type without an
	  icon has no crest, so it simply ends at NEAR_DISTANCE. Not drawn through walls.

	  Height: the tag's bottom sits GAP studs above the NPC's top (its highest visible part that
	  starts at or below its Head's top, so hats count and a roof doesn't; measured when the
	  model streams in or changes), plus Nametag.HeightOffset, so a short NPC (the capybara Animal Trainer)
	  gets a lower tag without a per-NPC number.

	Art: RS/Assets/Images/NpcNametagArt (flat stand-ins while an Image is empty). Font:
	UIFonts.GetNPCFont(npcType, "Tag"). These types get no Head.gui any more (NPCBootstrapKit /
	SpawnerService skip it); a Head.gui saved on a model in Studio is hidden here.

	Like Nametags, each tag is its own BillboardGui in PlayerGui (ResetOnSpawn off) pointed at
	the model through Adornee, and a light watcher re-points it when streaming swaps parts.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local Images = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images")
local Art = require(Images:WaitForChild("NpcNametagArt"))
local HudArt = require(Images:WaitForChild("HudArt"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local NEAR_DISTANCE = 40 -- studs: full tag
local FAR_DISTANCE = 120 -- studs: crest only, beyond it nothing
local NEAR_HYSTERESIS = 2
local GAP = .25 -- studs between the model's top and the tag's bottom
local LOD_INTERVAL = .2
local WATCH_INTERVAL = .5

-- Layout, in screen pixels (constant at any distance), measured from the top of the gui.
local CREST = 50
local CREST_OVERLAP = 7 -- how far the crest's bottom sinks into the plaque (its rim only, clear of the name)
local PLAQUE_H = 26
local PLAQUE_CAP = math.ceil(Art.PLAQUE.SliceCenter.Min.X * PLAQUE_H / Art.PLAQUE.Height)
local NAME_SIZE = 15
local MARKER_H = 14
local MARKER_GAP = 1
local BOB = 3 -- px the lit marker dips toward the head
local WIDTH = 280

local PLAQUE_Y = CREST - CREST_OVERLAP
local MARKER_Y = PLAQUE_Y + PLAQUE_H + MARKER_GAP
local HEIGHT = MARKER_Y + MARKER_H + BOB
local CREST_FAR_Y = HEIGHT - CREST -- crest alone drops to the bottom, over the head

local INK = Color3.fromHex("120C08")
local LEATHER = Color3.fromHex("2C2116")
local BRONZE = Color3.fromHex("AC966C")
local GREEN = Color3.fromHex("28462C")
local BONE = Color3.fromHex("EEE6CE")
local MARKER_DIM = Color3.fromRGB(165, 160, 150)
local MARKER_DIM_TRANSPARENCY = .3

local FADE = TweenInfo.new(.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BOB_TWEEN = TweenInfo.new(.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local tags = {} -- [Model] = tag

local function hasArt(piece)
	return type(piece) == "table" and type(piece.Image) == "string" and piece.Image ~= ""
end

local function make(className, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

-- An art piece, or its flat stand-in. Returns the instance and the property that fades it.
local function piece(art, props, standIn)
	props.BackgroundTransparency = 1
	local label = make("ImageLabel", props)
	if hasArt(art) then
		label.Image = art.Image
		return label, "ImageTransparency"
	end
	label.BackgroundTransparency = 0
	standIn(label)
	return label, "BackgroundTransparency"
end

local function tween(inst, prop, value, instant)
	if instant then
		inst[prop] = value
	else
		TweenService:Create(inst, FADE, { [prop] = value }):Play()
	end
end

-- Fades a piece; a stand-in's outline (UIStroke) goes with it.
local function fadePiece(inst, prop, value, instant)
	tween(inst, prop, value, instant)
	for _, child in ipairs(inst:GetChildren()) do
		if child:IsA("UIStroke") then
			tween(child, "Transparency", value, instant)
		end
	end
end

local function build(model, npcType, nametag)
	local gui = make("BillboardGui", {
		Name = "NpcNametag_" .. model.Name,
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		SizeOffset = Vector2.new(0, .5), -- the gui's bottom edge sits on the anchor point
		AlwaysOnTop = false,
		LightInfluence = 0,
		MaxDistance = FAR_DISTANCE,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	local tag = { model = model, gui = gui, nametag = nametag, near = nil, lit = false, shown = {}, fades = {} }

	local plaque, plaqueProp = piece(Art.PLAQUE, {
		Name = "Plaque",
		AnchorPoint = Vector2.new(.5, 0),
		Position = UDim2.fromOffset(WIDTH / 2, PLAQUE_Y),
		Size = UDim2.fromOffset(0, PLAQUE_H),
		AutomaticSize = Enum.AutomaticSize.X,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Art.PLAQUE.SliceCenter,
		SliceScale = PLAQUE_H / Art.PLAQUE.Height,
		ZIndex = 1,
	}, function(label)
		label.BackgroundColor3 = LEATHER
		make("UICorner", { CornerRadius = UDim.new(0, 4), Parent = label })
		make("UIStroke", { Color = BRONZE, Thickness = 2, Parent = label })
	end)
	make("UIPadding", { PaddingLeft = UDim.new(0, PLAQUE_CAP + 10), PaddingRight = UDim.new(0, PLAQUE_CAP + 10), Parent = plaque })
	make("UISizeConstraint", { MinSize = Vector2.new(CREST + 2 * PLAQUE_CAP, PLAQUE_H), Parent = plaque })
	plaque.Parent = gui
	table.insert(tag.fades, { plaque, plaqueProp, 0, true })

	local name = make("TextLabel", {
		Name = "NameLabel",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = UIFonts.GetNPCFont(npcType, "Tag"),
		TextSize = NAME_SIZE,
		TextColor3 = BONE,
		ZIndex = 2,
		Parent = plaque,
	})
	local nameStroke = make("UIStroke", { Color = INK, Thickness = 1, Transparency = .3, Parent = name })
	tag.name = name
	table.insert(tag.fades, { name, "TextTransparency", 0 })
	table.insert(tag.fades, { nameStroke, "Transparency", .3 })

	local marker, markerProp = piece(Art.MARKER, {
		Name = "Marker",
		AnchorPoint = Vector2.new(.5, 0),
		Position = UDim2.fromOffset(WIDTH / 2, MARKER_Y),
		Size = UDim2.fromOffset(math.round(MARKER_H * Art.MARKER.Aspect), MARKER_H),
		ZIndex = 1,
	}, function(label)
		-- a bronze diamond
		label.Size = UDim2.fromOffset(MARKER_H * .65, MARKER_H * .65)
		label.Rotation = 45
		label.BackgroundColor3 = BRONZE
		make("UIStroke", { Color = INK, Thickness = 1, Parent = label })
	end)
	marker.Parent = gui
	tag.marker, tag.markerProp = marker, markerProp

	local icon = nametag.Icon and Art.ICONS[nametag.Icon]
	if nametag.Icon then
		-- The holder moves (near / far); the glow sits behind the crest inside it.
		local holder = make("Frame", {
			Name = "CrestHolder",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(.5, 0),
			Position = UDim2.fromOffset(WIDTH / 2, 0),
			Size = UDim2.fromOffset(CREST, math.round(CREST / Art.CREST.Aspect)),
			ZIndex = 3,
			Parent = gui,
		})
		tag.crest = holder

		local crest = piece(Art.CREST, {
			Name = "Crest",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
		}, function(label)
			label.BackgroundColor3 = GREEN
			make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = label })
			make("UIStroke", { Color = BRONZE, Thickness = 4, Parent = label })
		end)
		crest.Parent = holder

		local hole = Art.CREST.HOLE
		if hasArt(icon) then
			make("ImageLabel", {
				Name = "Icon",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(.5, .5),
				Position = UDim2.fromScale(hole.X, hole.Y),
				Size = UDim2.fromScale(hole.D * .9, hole.D * .9 * Art.CREST.Aspect),
				Image = icon.Image,
				ImageRectOffset = icon.Offset,
				ImageRectSize = icon.Size,
				ZIndex = 4,
				Parent = crest,
			})
		end

		if typeof(nametag.Accent) == "Color3" and HudArt.GLOW_SOFT ~= "" then
			make("ImageLabel", {
				Name = "AccentGlow",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(.5, .5),
				Position = UDim2.fromScale(.5, .5),
				Size = UDim2.fromScale(1.7, 1.7),
				Image = HudArt.GLOW_SOFT,
				ImageColor3 = nametag.Accent,
				ImageTransparency = .45,
				ZIndex = 1,
				Parent = holder,
			})
		end
	else
		-- No crest: nothing to show past NEAR_DISTANCE.
		gui.MaxDistance = NEAR_DISTANCE + NEAR_HYSTERESIS
	end

	gui.Parent = playerGui
	return tag
end

-- The marker: hidden when far, dim out of talk range, lit and bobbing in it.
local function applyMarker(tag, instant)
	local marker = tag.marker
	if tag.bob then
		tag.bob:Cancel()
		tag.bob = nil
		marker.Position = UDim2.fromOffset(WIDTH / 2, MARKER_Y)
	end
	local lit = tag.lit and tag.near
	if tag.markerProp == "ImageTransparency" then
		marker.ImageColor3 = lit and Color3.new(1, 1, 1) or MARKER_DIM
	end
	fadePiece(marker, tag.markerProp, not tag.near and 1 or lit and 0 or MARKER_DIM_TRANSPARENCY, instant)
	if lit then
		tag.bob = TweenService:Create(marker, BOB_TWEEN, { Position = UDim2.fromOffset(WIDTH / 2, MARKER_Y + BOB) })
		tag.bob:Play()
	end
end

local function setNear(tag, near, instant)
	if tag.near == near then return end
	tag.near = near
	for _, fade in ipairs(tag.fades) do
		(fade[4] and fadePiece or tween)(fade[1], fade[2], near and fade[3] or 1, instant)
	end
	if tag.crest then
		local y = near and 0 or CREST_FAR_Y
		if instant then
			tag.crest.Position = UDim2.fromOffset(WIDTH / 2, y)
		else
			TweenService:Create(tag.crest, FADE, { Position = UDim2.fromOffset(WIDTH / 2, y) }):Play()
		end
	end
	applyMarker(tag, instant)
end

local function partExtentY(part)
	local cf, half = part.CFrame, part.Size / 2
	return math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z
end

-- The top of the NPC: the highest visible part that starts at or below its Head's top (the
-- body mesh, a hat painted on it, anything worn), so a roof or prop above the NPC can't lift
-- the tag; the (often invisible) Head itself counts too. Without a Head, the highest visible
-- part. Invisible root parts and hitboxes never count.
local function modelTop(model)
	local head = model:FindFirstChild("Head")
	local headTop = head and head:IsA("BasePart") and head.Position.Y + partExtentY(head) or nil
	local top = headTop
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < .99 then
			local extent = partExtentY(part)
			if not headTop or part.Position.Y - extent <= headTop then
				local y = part.Position.Y + extent
				if not top or y > top then
					top = y
				end
			end
		end
	end
	return top
end

local function findAdornee(model)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head end
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

-- Re-point the tag at the model's current parts and re-measure its height.
local function attach(tag)
	local model = tag.model
	local adornee = findAdornee(model)
	tag.gui.Adornee = adornee
	tag.adornee = adornee
	tag.dirty = false
	if not adornee then return end
	local top = modelTop(model) or (adornee.Position.Y + adornee.Size.Y / 2)
	tag.gui.StudsOffsetWorldSpace = Vector3.new(0, top - adornee.Position.Y + GAP + (tag.nametag.HeightOffset or 0), 0)

	-- An old text tag saved on the model in Studio would double up with this one.
	local head = model:FindFirstChild("Head")
	local legacy = head and head:FindFirstChild("gui")
	if legacy and legacy:IsA("BillboardGui") then
		legacy.Enabled = false
	end
end

local function refreshName(tag, npcType)
	local entry = NPCRegistry.Get(npcType)
	local text = tag.model:GetAttribute("NpcName")
	tag.name.Text = type(text) == "string" and text ~= "" and text or (entry and entry.DisplayName) or npcType
end

local function remove(model)
	local tag = tags[model]
	if not tag then return end
	tags[model] = nil
	if tag.bob then tag.bob:Cancel() end
	for _, conn in ipairs(tag.conns) do conn:Disconnect() end
	tag.gui:Destroy()
end

local function add(model)
	if not model:IsA("Model") or tags[model] then return end
	-- Attributes can land a moment after the tag (and after streaming).
	local npcType
	for _ = 1, 20 do
		npcType = model:GetAttribute("NpcType")
		if npcType or not model:IsDescendantOf(workspace) then break end
		task.wait(.25)
	end
	local nametag = NPCRegistry.GetNametag(npcType)
	if not nametag or tags[model] or not CollectionService:HasTag(model, "NPC") then return end

	local tag = build(model, npcType, nametag)
	tag.conns = {
		model:GetAttributeChangedSignal("NpcName"):Connect(function() refreshName(tag, npcType) end),
		model.DescendantAdded:Connect(function() tag.dirty = true end),
		model.DescendantRemoving:Connect(function() tag.dirty = true end),
	}
	tags[model] = tag
	refreshName(tag, npcType)
	attach(tag)
	setNear(tag, false, true)
end

for _, model in ipairs(CollectionService:GetTagged("NPC")) do
	task.spawn(add, model)
end
CollectionService:GetInstanceAddedSignal("NPC"):Connect(function(model) task.spawn(add, model) end)
CollectionService:GetInstanceRemovedSignal("NPC"):Connect(remove)

-- Talk range = any of the NPC's prompts showing.
local function tagForPrompt(prompt)
	local node = prompt.Parent
	while node and node ~= workspace do
		if tags[node] then return tags[node] end
		node = node.Parent
	end
	return nil
end

local function setPromptShown(prompt, shown)
	local tag = tagForPrompt(prompt)
	if not tag then return end
	tag.shown[prompt] = shown or nil
	local lit = next(tag.shown) ~= nil
	if lit ~= tag.lit then
		tag.lit = lit
		applyMarker(tag)
	end
end

ProximityPromptService.PromptShown:Connect(function(prompt) setPromptShown(prompt, true) end)
ProximityPromptService.PromptHidden:Connect(function(prompt) setPromptShown(prompt, false) end)

-- Distance: full tag near, crest alone further out.
task.spawn(function()
	while true do
		task.wait(LOD_INTERVAL)
		local camera = workspace.CurrentCamera
		if camera then
			local eye = camera.CFrame.Position
			for _, tag in pairs(tags) do
				if tag.adornee then
					local distance = (tag.adornee.Position - eye).Magnitude
					local limit = tag.near and NEAR_DISTANCE + NEAR_HYSTERESIS or NEAR_DISTANCE - NEAR_HYSTERESIS
					setNear(tag, distance <= limit)
				end
			end
		end
	end
end)

-- The watcher: re-attach a tag whose parts streamed in, changed or went away.
task.spawn(function()
	while true do
		task.wait(WATCH_INTERVAL)
		for _, tag in pairs(tags) do
			local adornee = tag.adornee
			if tag.dirty or not adornee or not adornee:IsDescendantOf(tag.model) then
				attach(tag)
			end
		end
	end
end)
