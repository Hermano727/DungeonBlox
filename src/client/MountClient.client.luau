--[[
	MountClient -- the horse mount, client side (2026-10-11). Rules: RS/MountConfig; server:
	SSS/MountService.

	  - Keys.Mount (H) calls your horse / sends it away (GameEvents/MountToggle). A refusal (in
	    combat, no saddle, cooldown, a dungeon) shakes the slot and flashes why.
	  - The HUD slot, in HealthClient's MountIconsMount at the end of the vitals row, the same
	    shape as the dash (Q) slot: key chip, the horse icon, a fixed-width countdown. It only
	    shows once you own a saddle. Riding: the icon glows gold. Cooldown after the horse leaves
	    (MountReadyAt): dim, the key chip fills back up, the seconds count down. In combat: dim
	    with a red edge, since it can't be called.
	  - Effects for every nearby horse (GameEvents/MountFx): a dust burst and the horse's call
	    when it arrives / leaves / bolts, its idle sounds; and hoof dust while any horse gallops.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local MountConfig = require(ReplicatedStorage:WaitForChild("MountConfig"))
local HudBarStyle = require(ReplicatedStorage:WaitForChild("HudBarStyle"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local WorldVfx = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("WorldVfx"))
local JournalUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("JournalUI"))
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))
local CenterFlashUI = require(script.Parent:WaitForChild("CenterFlashUI"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local MountToggle = gameEvents:WaitForChild("MountToggle")
local MountFx = gameEvents:WaitForChild("MountFx")

local ICON_SIZE = 24
local KEY_SIZE = 16
local READY_GOLD = Color3.fromRGB(255, 214, 120)
local REFUSE_COLOR = Color3.fromRGB(220, 60, 50)
local DUST = Color3.fromRGB(150, 128, 100)

local hasHorse = false
local inCombat = false
local busy = false
local render -- built with the slot below
local shake

---------------------------------------------------------------------------
-- The key

local function toggle()
	if busy then return end
	busy = true
	task.spawn(function()
		local ok, okToggle, reason = pcall(MountToggle.InvokeServer, MountToggle)
		busy = false
		if ok and not okToggle and reason ~= "busy" then
			if shake then shake() end
			CenterFlashUI.Show(MountConfig.REFUSALS[reason] or "You can't call your horse right now")
		end
		if render then render() end
	end)
end

ContextActionService:BindActionAtPriority("MountToggle", function(_, state)
	if UserInputService:GetFocusedTextBox() ~= nil or GuiService.MenuIsOpen then return Enum.ContextActionResult.Pass end
	if state == Enum.UserInputState.Begin and hasHorse then
		toggle()
	end
	return hasHorse and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
end, false, Enum.ContextActionPriority.High.Value, Keys.Mount)
script.Destroying:Connect(function() ContextActionService:UnbindAction("MountToggle") end)

---------------------------------------------------------------------------
-- The slot (HealthClient's MountIconsMount)

local mount
repeat
	mount = playerGui:FindFirstChild("MountIconsMount", true)
	if not mount then task.wait(0.5) end
until mount

local function label(parent, text, size)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = UIFonts.HUDLabel
	t.TextSize = size
	t.TextColor3 = HudBarStyle.BONE
	t.TextStrokeTransparency = 0.35
	t.Text = text
	t.Parent = parent
	return t
end

local keyChip = Instance.new("Frame")
keyChip.Name = "MountKey"
keyChip.LayoutOrder = 1
keyChip.Size = UDim2.fromOffset(KEY_SIZE, KEY_SIZE)
keyChip.BackgroundColor3 = HudBarStyle.TROUGH
keyChip.BackgroundTransparency = HudBarStyle.TROUGH_TRANSPARENCY
keyChip.Parent = mount
Instance.new("UICorner", keyChip).CornerRadius = UDim.new(0, 3)
local keyStroke = Instance.new("UIStroke")
keyStroke.Color = HudBarStyle.BRONZE
keyStroke.Transparency = 0.2
keyStroke.Parent = keyChip
local fill = Instance.new("Frame")
fill.AnchorPoint = Vector2.new(0, 1)
fill.Position = UDim2.fromScale(0, 1)
fill.Size = UDim2.fromScale(1, 0)
fill.BackgroundColor3 = HudBarStyle.BRONZE
fill.BackgroundTransparency = 0.25
fill.BorderSizePixel = 0
fill.Parent = keyChip
Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)
local keyText = label(keyChip, Keys.Mount.Name, 11)
keyText.Size = UDim2.fromScale(1, 1)
keyText.ZIndex = 2

local icon = Instance.new("ImageLabel")
icon.Name = "HorseIcon"
icon.LayoutOrder = 2
icon.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
icon.BackgroundTransparency = 1
icon.Image = (JournalUI.icon_cat_mount and JournalUI.icon_cat_mount.Image) or ""
icon.ScaleType = Enum.ScaleType.Fit
icon.Parent = mount
local iconRest = icon.Position
local scale = Instance.new("UIScale")
scale.Parent = icon

-- Fixed width, empty when idle: the vitals row stays centred (docs/ui-and-networking.md).
local countdown = label(mount, "", 12)
countdown.LayoutOrder = 3
countdown.Size = UDim2.fromOffset(24, ICON_SIZE)
countdown.TextXAlignment = Enum.TextXAlignment.Left

local wasMounted = false
render = function()
	mount.Visible = hasHorse
	local mounted = player:GetAttribute("Mounted") == true
	local readyAt = tonumber(player:GetAttribute("MountReadyAt")) or 0
	local remaining = readyAt - Workspace:GetServerTimeNow()
	local cooling = not mounted and remaining > 0
	if mounted then
		icon.ImageColor3 = READY_GOLD
		icon.ImageTransparency = 0
		keyStroke.Color = READY_GOLD
	else
		icon.ImageColor3 = HudBarStyle.BONE
		icon.ImageTransparency = (cooling or inCombat) and 0.6 or 0
		keyStroke.Color = inCombat and REFUSE_COLOR or HudBarStyle.BRONZE
	end
	local span = math.max(0.1, tonumber(player:GetAttribute("MountCooldown")) or MountConfig.SUMMON_COOLDOWN)
	fill.Size = UDim2.fromScale(1, cooling and (1 - math.clamp(remaining / span, 0, 1)) or 0)
	countdown.Text = cooling and string.format("%.1f", remaining) or ""
	if mounted and not wasMounted then
		scale.Scale = 1.3
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	wasMounted = mounted
end

shake = function()
	keyStroke.Color = REFUSE_COLOR
	task.delay(0.35, function() if render then render() end end)
	local nudge = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
	icon.Position = iconRest
	TweenService:Create(icon, nudge, { Position = iconRest + UDim2.fromOffset(3, 0) }):Play()
end

-- The countdown ticks while there is one; otherwise the slot only redraws on changes.
RunService.RenderStepped:Connect(function()
	if countdown.Text ~= "" or ((tonumber(player:GetAttribute("MountReadyAt")) or 0) > Workspace:GetServerTimeNow()) then
		render()
	end
end)
player:GetAttributeChangedSignal("Mounted"):Connect(render)
player:GetAttributeChangedSignal("MountReadyAt"):Connect(render)

local combatEvent = ReplicatedStorage:WaitForChild("CombatStateEvent", 30)
if combatEvent then
	combatEvent.OnClientEvent:Connect(function(state)
		inCombat = state == "combat"
		render()
	end)
end

DungeonMenuNet.addSnapshotListener(function(snapshot)
	hasHorse = MountConfig.BestSaddle(snapshot and snapshot.profile) ~= nil
	render()
end)
DungeonMenuNet.start()
render()

---------------------------------------------------------------------------
-- Effects: arrivals, departures, the horse's sounds, hoof dust

local fxFolder = Instance.new("Folder")
fxFolder.Name = "MountFx"
fxFolder.Parent = Workspace

local function dustBurst(position, amount, speed)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.Size = Vector3.new(6, 1, 8)
	p.CFrame = CFrame.new(position - Vector3.new(0, MountConfig.HORSE_CENTRE_ABOVE_FLOOR - 0.5, 0))
	p.Parent = fxFolder
	local e = Instance.new("ParticleEmitter")
	e.Texture = WorldVfx.SMOKE_PUFF_4X4
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.Random
	e.Color = ColorSequence.new(DUST)
	e.LightInfluence = 0.8
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4.5) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Drag = 2
	e.Acceleration = Vector3.new(0, 2, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Enabled = false
	e.Parent = p
	e:Emit(amount)
	task.delay(2, function() p:Destroy() end)
end

local function sound(spec, position)
	if not spec then return end
	local speed = spec.speed and (spec.speed.Min + math.random() * (spec.speed.Max - spec.speed.Min)) or 1
	SfxService.PlayEffect(spec.key, { Position = position, PlaybackSpeed = speed, RollOffMinDistance = 15, RollOffMaxDistance = 160 })
end

MountFx.OnClientEvent:Connect(function(kind, position)
	if typeof(position) ~= "Vector3" then return end
	if kind == "summon" then
		dustBurst(position, 18, 8)
		sound(MountConfig.Sounds.Summon, position)
	elseif kind == "dismiss" then
		dustBurst(position, 14, 6)
		sound(MountConfig.Sounds.Dismiss, position)
	elseif kind == "thrown" then
		dustBurst(position, 26, 12)
		sound(MountConfig.Sounds.Thrown, position)
	elseif kind == "idle" then
		sound(MountConfig.Sounds.Idle, position)
	end
end)

-- Hoof dust: a small emitter on each hoof bone of every live horse, puffing while it gallops.
local HOOVES = { "Hoof.L", "Hoof.R", "HindHoof.L", "HindHoof.R" }
local hoofDust = setmetatable({}, { __mode = "k" }) -- [horse Model] = { emitters }
local function emittersFor(horse)
	local list = hoofDust[horse]
	if list then return list end
	list = {}
	for _, name in ipairs(HOOVES) do
		local bone = horse:FindFirstChild(name, true)
		if bone and bone:IsA("Bone") then
			local e = Instance.new("ParticleEmitter")
			e.Name = "HoofDust"
			e.Texture = WorldVfx.SMOKE_PUFF_4X4
			e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
			e.FlipbookMode = Enum.ParticleFlipbookMode.Random
			e.Color = ColorSequence.new(DUST)
			e.LightInfluence = 0.8
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(0.5, 0.9)
			e.Speed = NumberRange.new(1, 3)
			e.SpreadAngle = Vector2.new(60, 60)
			e.Drag = 3
			e.EmissionDirection = Enum.NormalId.Top
			e.Rate = 0
			e.Parent = bone
			table.insert(list, e)
		end
	end
	hoofDust[horse] = list
	return list
end

local nextDustCheck = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextDustCheck then return end
	nextDustCheck = now + 0.2
	local folder = Workspace:FindFirstChild(MountConfig.FOLDER_NAME)
	if not folder then return end
	for _, horse in ipairs(folder:GetChildren()) do
		local root = horse:IsA("Model") and horse.PrimaryPart
		if root then
			local v = root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			local rate = speed > 8 and math.clamp(speed * 0.35, 4, 16) or 0
			for _, e in ipairs(emittersFor(horse)) do e.Rate = rate end
		end
	end
end)
