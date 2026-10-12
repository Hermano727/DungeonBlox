local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
	DashClient (StarterCharacterScripts)
	Keys.Dash (Q): a short burst. Humanoid overwrites velocity each tick, so we ease TranslateBy
	over ~0.12-0.2s. Direction: MoveDirection on XZ when moving; else character forward on XZ.
	Total distance scales with WalkSpeed (so Swiftness carries it further).
	In the air it's an AIR DASH (2026-10-04): once per jump (resets on landing), AIR_DIST_MULT
	further, and the fall is held off while it lasts, so it carries you across a gap.
	It stops short of walls (a ray ahead), on the ground and in the air.
	Server: EnergyServer RequestDash (energy cost + cooldown).
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local player = Players.LocalPlayer

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local RequestDash = ReplicatedStorage:WaitForChild("EnergyEvents"):WaitForChild("RequestDash")
local DIST_BASE = 2.6
local DIST_PER_WALKSPEED = 0.2
local DIST_MIN = 3.0
local DIST_MAX = 14.5
local MOVE_DEADZONE = 0.08

local AIR_DIST_MULT = 1.5 -- an air dash goes this much further than a ground one
local WALL_GAP = 1.2 -- stop this far short of whatever's in the way

local SLIDE_DURATION_MIN = 0.11
local SLIDE_DURATION_MAX = 0.2
local SLIDE_DURATION_BASE = 0.125
local SLIDE_DURATION_PER_SPEED = 0.0042

local lastDashClock = 0
local isDashing = false
local slideConn = nil
local airDashUsed = false -- one air dash per jump

local function airborne()
	return humanoid.FloorMaterial == Enum.Material.Air
end

humanoid.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running
		or new == Enum.HumanoidStateType.RunningNoPhysics or new == Enum.HumanoidStateType.Swimming then
		airDashUsed = false
	end
end)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { character }

-- How far the dash can actually go before it would run into something.
local function clearDistance(dir, studs)
	local hit = workspace:Raycast(root.Position, dir * (studs + WALL_GAP), rayParams)
	if hit and hit.Instance.CanCollide then
		return math.max(0, hit.Distance - WALL_GAP)
	end
	return studs
end

-- Dash slot (2026-10-04): in the vitals row beside the fish (V) and potion (Z) slots, the same
-- shape: key chip, dash icon, and a countdown. While the dash recharges the icon dims, the key
-- chip fills back up from the bottom and the seconds left count down beside it; when it's ready
-- the icon brightens with a small pop. Built into HealthClient's DashIconsMount (rebuilt each
-- life, since this script is per character).
local HudIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))
local HudBarStyle = require(ReplicatedStorage:WaitForChild("HudBarStyle"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local TweenService = game:GetService("TweenService")
local ICON_SIZE = 24
local KEY_SIZE = 16
local READY_GOLD = Color3.fromRGB(255, 214, 120)

local dashUi = nil
local dashUiConn = nil

local function slotLabel(parent, text, size)
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

local function getDashUi()
	if dashUi and dashUi.icon.Parent then return dashUi end
	local mount = player.PlayerGui:FindFirstChild("DashIconsMount", true)
	if not mount then return nil end
	for _, old in ipairs(mount:GetChildren()) do
		if old:IsA("GuiObject") then old:Destroy() end -- last life's slot
	end
	local keyChip = Instance.new("Frame")
	keyChip.Name = "DashKey"
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
	-- Refills from the bottom as the dash recharges (empty right after dashing, gone when ready).
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = HudBarStyle.BRONZE
	fill.BackgroundTransparency = 0.25
	fill.BorderSizePixel = 0
	fill.Parent = keyChip
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)
	local keyText = slotLabel(keyChip, Keys.Dash.Name, 11)
	keyText.Size = UDim2.fromScale(1, 1)
	keyText.ZIndex = 2

	local icon = Instance.new("ImageLabel")
	icon.Name = "DashIcon"
	icon.LayoutOrder = 2
	icon.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	icon.BackgroundTransparency = 1
	icon.Image = HudIcons.DASH or ""
	icon.ImageColor3 = HudBarStyle.BONE
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = mount
	local scale = Instance.new("UIScale")
	scale.Parent = icon
	-- The seconds left, beside the icon. Fixed width (always there, empty when ready) so the
	-- whole vitals row stays centred as one group.
	local countdown = slotLabel(mount, "", 12)
	countdown.LayoutOrder = 3
	countdown.Size = UDim2.fromOffset(24, ICON_SIZE)
	countdown.TextXAlignment = Enum.TextXAlignment.Left
	dashUi = { icon = icon, scale = scale, fill = fill, countdown = countdown, keyStroke = keyStroke }
	return dashUi
end

local function startDashCooldownUI()
	local ui = getDashUi()
	if not ui then return end
	if dashUiConn then dashUiConn:Disconnect() end
	ui.icon.ImageTransparency = 0.6
	ui.icon.ImageColor3 = HudBarStyle.BONE
	dashUiConn = RunService.RenderStepped:Connect(function()
		local remaining = Config.DASH_COOLDOWN - (os.clock() - lastDashClock)
		if remaining > 0 and ui.icon.Parent then
			ui.fill.Size = UDim2.fromScale(1, 1 - math.clamp(remaining / Config.DASH_COOLDOWN, 0, 1))
			ui.countdown.Text = string.format("%.1f", remaining)
			return
		end
		dashUiConn:Disconnect()
		dashUiConn = nil
		-- Ready: icon back to full, a gold flash and a small pop.
		ui.fill.Size = UDim2.fromScale(1, 0)
		ui.countdown.Text = ""
		ui.icon.ImageTransparency = 0
		ui.icon.ImageColor3 = READY_GOLD
		ui.scale.Scale = 1.3
		TweenService:Create(ui.scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		TweenService:Create(ui.icon, TweenInfo.new(0.5), { ImageColor3 = HudBarStyle.BONE }):Play()
	end)
end

-- Build the slot as soon as the HUD row exists, so it's there before the first dash.
task.spawn(function()
	for _ = 1, 40 do
		if getDashUi() then return end
		task.wait(0.25)
	end
end)

local function flatOnXZ(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function easeOutQuad(t)
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) * (1 - t)
end

local function dashDirectionUnit()
	local md = flatOnXZ(humanoid.MoveDirection)
	if md.Magnitude >= MOVE_DEADZONE then
		return md.Unit
	end
	local look = flatOnXZ(root.CFrame.LookVector)
	if look.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return look.Unit
end

local function tryDash()
	if isDashing then
		return
	end
	if (os.clock() - lastDashClock) < Config.DASH_COOLDOWN then
		return
	end
	if UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	if humanoid.Health <= 0 then
		return
	end
	if humanoid.SeatPart or player:GetAttribute("Mounted") then
		return -- seated, or riding the horse (SSS/MountService)
	end
	if root.Anchored then
		return
	end
	local inAir = airborne()
	if inAir and airDashUsed then
		return
	end

	local dashOk = false
	local invokeOk, invokeResult = pcall(function()
		return RequestDash:InvokeServer()
	end)
	if invokeOk and invokeResult == true then
		dashOk = true
	end
	if not dashOk then
		return
	end

	local dir = dashDirectionUnit()
	local walk = math.max(1, humanoid.WalkSpeed)
	local studs = math.clamp(DIST_BASE + walk * DIST_PER_WALKSPEED, DIST_MIN, DIST_MAX)
	if inAir then
		airDashUsed = true
		studs *= AIR_DIST_MULT
	end
	studs = clearDistance(dir, studs)
	local slideDuration = math.clamp(
		SLIDE_DURATION_BASE + walk * SLIDE_DURATION_PER_SPEED,
		SLIDE_DURATION_MIN,
		SLIDE_DURATION_MAX
	)

	isDashing = true
	lastDashClock = os.clock()
	startDashCooldownUI()

	local easedPrev = 0
	local t0 = os.clock()

	if slideConn then
		slideConn:Disconnect()
		slideConn = nil
	end

	slideConn = RunService.Heartbeat:Connect(function()
		if not character.Parent or humanoid.Health <= 0 or humanoid.SeatPart or root.Anchored then
			if slideConn then
				slideConn:Disconnect()
				slideConn = nil
			end
			isDashing = false
			return
		end

		local u = math.min(1, (os.clock() - t0) / slideDuration)
		local eased = easeOutQuad(u)
		local frac = eased - easedPrev
		easedPrev = eased

		if inAir then
			-- Hold the fall off while the air dash lasts, so it reads as a burst across.
			local v = root.AssemblyLinearVelocity
			if v.Y < 0 then root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z) end
		end
		if frac > 0 then
			if character:IsA("Model") then
				character:TranslateBy(dir * studs * frac)
			else
				root.CFrame = root.CFrame + dir * studs * frac
			end
		end

		if u >= 1 then
			if slideConn then
				slideConn:Disconnect()
				slideConn = nil
			end
			isDashing = false
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, _gameProcessed)
	if input.KeyCode ~= Keys.Dash then
		return
	end
	tryDash()
end)
