--[[
	DamageNumberClient
	Server sends post-armor damage via DamageNumberEvent; we show a short floating number above the mob.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageNumberEvent = ReplicatedStorage:WaitForChild("DamageNumberEvent", 60)
if not DamageNumberEvent then
	warn("[DamageNumberClient] DamageNumberEvent missing after 60s")
	return
end

local FLOAT_TIME = 0.65
local RISE_STUDS = 2.8

local DAMAGE_COLOR = Color3.fromRGB(255, 60, 60)  -- red

local moveTween = TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local fadeTween = TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Linear)

DamageNumberEvent.OnClientEvent:Connect(function(damage, mobModel)
	local amt = math.floor(tonumber(damage) or 0)
	if amt <= 0 then
		return
	end
	if typeof(mobModel) ~= "Instance" or not mobModel:IsA("Model") then
		return
	end

	local root = mobModel:FindFirstChild("HumanoidRootPart")
		or mobModel.PrimaryPart
		or mobModel:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end

	local rx = (math.random() - 0.5) * 2.2
	local rz = (math.random() - 0.5) * 2.2
	local startOffset = Vector3.new(rx, 2.2, rz)

	local gui = Instance.new("BillboardGui")
	gui.Name = "DmgNum"
	gui.Size = UDim2.new(0, 220, 0, 90)
	gui.StudsOffset = startOffset
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Adornee = root
	gui.Parent = root

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextColor3 = DAMAGE_COLOR
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.35
	lbl.TextTransparency = 0
	lbl.Text = tostring(amt)
	lbl.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = lbl

	TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.5 }):Play()
	TweenService:Create(gui, moveTween, { StudsOffset = startOffset + Vector3.new(0, RISE_STUDS, 0) }):Play()
	TweenService:Create(lbl, fadeTween, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	task.delay(FLOAT_TIME, function()
		if gui and gui.Parent then
			gui:Destroy()
		end
	end)
end)
