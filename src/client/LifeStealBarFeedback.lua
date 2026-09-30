-- A receipt-driven overlay; never changes HP, bar fill, or the bar's transform.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local Feedback = {}

function Feedback.new(background)
	local segment = Instance.new("Frame")
	segment.Name = "LifeStealRecoveredHP"
	segment.BorderSizePixel = 0
	segment.BackgroundColor3 = Color3.fromRGB(180, 245, 169)
	segment.BackgroundTransparency = 1
	segment.ZIndex = 4
	segment.Parent = background

	local glow = Instance.new("Frame")
	glow.Name = "LifeStealPulse"
	glow.Size = UDim2.fromScale(1, 1)
	glow.BackgroundTransparency = 1
	glow.ZIndex = 4
	glow.Parent = background
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(128, 210, 137)
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = glow

	local label = Instance.new("TextLabel")
	label.Name = "LifeStealAmount"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(1, 1)
	label.Position = UDim2.new(1, -4, 0, -5)
	label.Size = UDim2.fromOffset(160, 18)
	label.FontFace = UIFonts.HUDLabel
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextColor3 = Color3.fromRGB(177, 240, 171)
	label.TextStrokeColor3 = Color3.fromRGB(15, 28, 18)
	label.TextStrokeTransparency = 0.3
	label.TextTransparency = 1
	label.ZIndex = 8
	label.Parent = background

	local tweens, total, last = {}, 0, -math.huge
	local controller = {}
	local function cancel()
		for _, tween in ipairs(tweens) do tween:Cancel() end
		table.clear(tweens)
	end
	local function fade(object, property, duration)
		local tween = TweenService:Create(object, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { [property] = 1 })
		table.insert(tweens, tween)
		tween:Play()
	end
	function controller:Reset()
		cancel()
		total, last = 0, -math.huge
		segment.BackgroundTransparency, stroke.Transparency, label.TextTransparency, label.TextStrokeTransparency = 1, 1, 1, 1
	end
	function controller:Play(receipt)
		if type(receipt) ~= "table" or (tonumber(receipt.amount) or 0) <= 0 or (tonumber(receipt.maxHealth) or 0) <= 0 then return end
		local before = math.clamp(tonumber(receipt.before) or 0, 0, receipt.maxHealth)
		local after = math.clamp(tonumber(receipt.after) or before, before, receipt.maxHealth)
		if after <= before then return end
		cancel()
		local time = os.clock()
		total = (time - last <= 0.4 and total or 0) + receipt.amount
		last = time
		segment.Position = UDim2.fromScale(before / receipt.maxHealth, 0)
		segment.Size = UDim2.fromScale((after - before) / receipt.maxHealth, 1)
		segment.BackgroundTransparency, stroke.Transparency = 0.15, 0.15
		label.Text = string.format("+%.1f LIFE STEAL", total)
		label.TextTransparency, label.TextStrokeTransparency = 0, 0.3
		fade(segment, "BackgroundTransparency", 0.6)
		fade(stroke, "Transparency", 0.7)
		fade(label, "TextTransparency", 0.85)
		fade(label, "TextStrokeTransparency", 0.85)
	end
	function controller:Destroy()
		self:Reset()
		segment:Destroy(); glow:Destroy(); label:Destroy()
	end
	return controller
end

return Feedback
