local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
	DashClient (StarterCharacterScripts)
	V: short ground slide. Humanoid overwrites velocity each tick, so we ease TranslateBy over ~0.12–0.2s.
	Direction: MoveDirection on XZ when moving; else character forward on XZ.
	Total distance scales with WalkSpeed.
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

local SLIDE_DURATION_MIN = 0.11
local SLIDE_DURATION_MAX = 0.2
local SLIDE_DURATION_BASE = 0.125
local SLIDE_DURATION_PER_SPEED = 0.0042

local lastDashClock = 0
local isDashing = false
local slideConn = nil

-- Dash cooldown label (parented to BarBackground in EnergyBarGui)
local DASH_LABEL_OFFSET_Y = -8 -- negative = above the energy bar; more negative = higher
local dashLabel = nil
local dashLabelConn = nil

local function getDashLabel()
	if dashLabel and dashLabel.Parent then return dashLabel end
	local gui = player.PlayerGui:FindFirstChild("EnergyBarGui")
	if not gui then return nil end
	local bg = gui:FindFirstChild("BarBackground")
	if not bg then return nil end
	local lbl = bg:FindFirstChild("DashCooldownLabel")
	if not lbl then
		lbl = Instance.new("TextLabel")
		lbl.Name = "DashCooldownLabel"
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 14
		lbl.TextColor3 = Color3.fromRGB(255, 200, 50)
		lbl.TextStrokeTransparency = 0.4
		lbl.Text = ""
		lbl.Visible = false
		lbl.Parent = bg
	end
	lbl.AnchorPoint = Vector2.new(0.5, 1)
	lbl.Size = UDim2.new(0, 160, 0, 20)
	lbl.Position = UDim2.new(0.5, 0, 0, DASH_LABEL_OFFSET_Y)
	dashLabel = lbl
	return dashLabel
end

local function startDashCooldownUI()
	local lbl = getDashLabel()
	if not lbl then return end
	lbl.Visible = true
	if dashLabelConn then dashLabelConn:Disconnect() end
	dashLabelConn = RunService.Heartbeat:Connect(function()
		local remaining = Config.DASH_COOLDOWN - (os.clock() - lastDashClock)
		if remaining <= 0 then
			lbl.Visible = false
			dashLabelConn:Disconnect()
			dashLabelConn = nil
		else
			lbl.Text = string.format("DASH: %.1fs", remaining)
		end
	end)
end

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
	if humanoid.SeatPart then
		return
	end
	if root.Anchored then
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
