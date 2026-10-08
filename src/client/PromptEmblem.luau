--!strict
--[[
	PromptEmblem -- the floating "press E" emblem for world interactions (2026-10-02, FIRST PASS).
	Same idea as the cleansing altar's MiasmaCleanseUI, shared so every interaction looks alike:
	a dark disc in a bronze ring holding an icon, a ring of beads that fills while the key is
	held (or flashes on a tap for a no-hold prompt), the TITLE, the key chip with "hold to open" /
	"to open", and optionally motes rising off the object while you're in range.

		PromptEmblem.Register({
			match = function(prompt) return prompt.Name == "BankPrompt" end,
			title = "BANK", verb = "open", icon = "rbxassetid://...",
			accent = Color3, bright = Color3,   -- bead / glow colours
			motes = true,                       -- particles off the object while in range
		})

	Matching prompts are switched to Style = Custom on this client only; Roblox still owns the
	input (key, hold, gamepad), and the feature's own script still handles Triggered. Touch taps
	the emblem. Users: BankClient (BANK), Wardrobe (WARDROBE).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local HudBarStyle = require(ReplicatedStorage:WaitForChild("HudBarStyle"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

export type Spec = {
	match: (ProximityPrompt) -> boolean,
	title: string,
	verb: string?,
	icon: string?,
	accent: Color3?,
	bright: Color3?,
	motes: boolean?,
}

local PromptEmblem = {}

local BEAD_COUNT = 16
local MOTE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local BRONZE = HudBarStyle.BRONZE
local CORE = HudBarStyle.DISC
local TEXT = HudBarStyle.BONE
local MUTED = Color3.fromRGB(196, 184, 162)
local BEAD_IDLE = Color3.fromRGB(70, 56, 36)
local DEFAULT_ACCENT = Color3.fromRGB(232, 190, 96)
local DEFAULT_BRIGHT = Color3.fromRGB(255, 232, 170)

local specs: { Spec } = {}
local styled: { [ProximityPrompt]: boolean } = {}
local shown: { [ProximityPrompt]: () -> () } = {}

local function specFor(prompt: ProximityPrompt): Spec?
	for _, spec in ipairs(specs) do
		if spec.match(prompt) then return spec end
	end
	return nil
end

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local item = Instance.new(className)
	for key, value in pairs(props) do (item :: any)[key] = value end
	if parent then item.Parent = parent end
	return item
end

local function round(parent: Instance, scale: number?)
	return new("UICorner", { CornerRadius = UDim.new(scale or 0.5, 0) }, parent)
end

local function keyLabel(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "Button", ""))
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	end
	return prompt.KeyboardKeyCode.Name
end

local function build(spec: Spec, prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): () -> ()
	local accent = spec.accent or DEFAULT_ACCENT
	local bright = spec.bright or DEFAULT_BRIGHT
	local host = prompt.Parent
	local adornee = host and host:IsA("BasePart") and host
		or (host and host:IsA("Attachment") and host.Parent and host.Parent:IsA("BasePart") and host.Parent)
		or nil
	local height = adornee and adornee.Size.Y or 3
	local isTouch = inputType == Enum.ProximityPromptInputType.Touch
	local holds = prompt.HoldDuration > 0

	local billboard = new("BillboardGui", {
		Name = "PromptEmblem",
		Adornee = adornee or host,
		Size = UDim2.fromOffset(190, 190),
		StudsOffset = Vector3.new(0, height / 2 + 2.2, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Active = isTouch,
	}, playerGui)
	local root = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, billboard)
	local scale = new("UIScale", { Scale = 0.55 }, root)

	-- Only touch gets a tappable emblem: on keyboard / gamepad a clickable billboard would eat
	-- mouse clicks whenever the player looks at the object.
	local emblem = new(isTouch and "TextButton" or "Frame", {
		Name = "Emblem", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(118, 118), BackgroundTransparency = 1,
	}, root)
	if isTouch then
		emblem.Text = ""
		emblem.AutoButtonColor = false
	end
	local glow = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = accent, BackgroundTransparency = 0.9,
	}, emblem)
	round(glow)
	local glowStroke = new("UIStroke", { Color = accent, Thickness = 2, Transparency = 0.4 }, glow)

	local beadRing = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.86, 0.86),
		BackgroundTransparency = 1,
	}, emblem)
	local beads = {}
	for i = 1, BEAD_COUNT do
		local angle = (i - 1) / BEAD_COUNT * math.pi * 2 - math.pi / 2
		local bead = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.5, 0.5 + math.sin(angle) * 0.5),
			Size = UDim2.fromOffset(7, 7), BackgroundColor3 = BEAD_IDLE,
		}, beadRing)
		round(bead)
		beads[i] = bead
	end

	local disc = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62),
		BackgroundColor3 = CORE, BackgroundTransparency = 0.1,
	}, emblem)
	round(disc)
	local ring = new("UIStroke", { Color = BRONZE, Thickness = 2 }, disc)
	if spec.icon and spec.icon ~= "" then
		new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.66, 0.66),
			BackgroundTransparency = 1, Image = spec.icon, ScaleType = Enum.ScaleType.Fit,
		}, disc)
	end

	new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 124), Size = UDim2.fromOffset(190, 26),
		BackgroundTransparency = 1, FontFace = UIFonts.DisplayBold, Text = spec.title, TextColor3 = TEXT, TextSize = 24,
		TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0.55,
	}, root)
	local hint = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 154), Size = UDim2.fromOffset(170, 26),
		BackgroundTransparency = 1,
	}, root)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6),
	}, hint)
	local keyChip = new("TextLabel", {
		Size = UDim2.fromOffset(26, 22), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = CORE, BackgroundTransparency = 0.15,
		FontFace = UIFonts.BodyBold, Text = keyLabel(prompt, inputType), TextColor3 = bright, TextSize = 15,
	}, hint)
	round(keyChip, 0.25)
	new("UIStroke", { Color = BRONZE, Thickness = 1.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, keyChip)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, keyChip)
	local verb = spec.verb or "open"
	new("TextLabel", {
		Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
		FontFace = UIFonts.BodyBold, Text = (holds and not isTouch) and ("hold to " .. verb) or ("to " .. verb),
		TextColor3 = MUTED, TextSize = 14,
	}, hint)

	local attachment: Attachment? = nil
	if spec.motes and adornee then
		attachment = new("Attachment", { Name = "PromptEmblemMotes", Position = Vector3.new(0, height / 2, 0) }, adornee)
		new("ParticleEmitter", {
			Texture = MOTE_TEXTURE,
			Color = ColorSequence.new(bright, accent),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(1.2, 2),
			Rate = 8,
			Speed = NumberRange.new(0.8, 1.6),
			SpreadAngle = Vector2.new(30, 30),
			EmissionDirection = Enum.NormalId.Top,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-60, 60),
		}, attachment)
	end

	local state = { progress = 0, holding = false, holdStart = 0 }
	TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local connections = {}
	table.insert(connections, prompt.PromptButtonHoldBegan:Connect(function()
		state.holding = true
		state.holdStart = os.clock()
	end))
	table.insert(connections, prompt.PromptButtonHoldEnded:Connect(function()
		state.holding = false
	end))
	table.insert(connections, prompt.Triggered:Connect(function()
		state.holding = false
		state.progress = 1
	end))
	if isTouch then
		table.insert(connections, emblem.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then prompt:InputHoldBegin() end
		end))
		table.insert(connections, emblem.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then prompt:InputHoldEnd() end
		end))
	end
	table.insert(connections, RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		if state.holding and holds then
			state.progress = math.clamp((t - state.holdStart) / prompt.HoldDuration, 0, 1)
		elseif state.progress > 0 then
			state.progress = math.max(0, state.progress - dt * (holds and 4 or 2.5))
		end
		local lit = math.floor(state.progress * BEAD_COUNT + 0.5)
		for i, bead in ipairs(beads) do
			local on = i <= lit
			bead.BackgroundColor3 = on and bright or BEAD_IDLE
			bead.Size = on and UDim2.fromOffset(9, 9) or UDim2.fromOffset(6, 6)
		end
		beadRing.Rotation = state.holding and 0 or (t * 10) % 360
		local pulse = (math.sin(t * 2.4) + 1) / 2
		glowStroke.Transparency = 0.25 + pulse * 0.45
		ring.Color = BRONZE:Lerp(bright, math.max(state.progress, pulse * 0.25))
		billboard.StudsOffset = Vector3.new(0, height / 2 + 2.2 + math.sin(t * 1.8) * 0.1, 0)
	end))

	return function()
		for _, connection in ipairs(connections) do connection:Disconnect() end
		if attachment then attachment:Destroy() end
		local fade = TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 0.5 })
		fade.Completed:Once(function() billboard:Destroy() end)
		fade:Play()
		task.delay(0.3, function() if billboard.Parent then billboard:Destroy() end end)
	end
end

local function style(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or styled[prompt] then return end
	if specFor(prompt) then
		styled[prompt] = true
		prompt.Style = Enum.ProximityPromptStyle.Custom -- drawn here; this client only
	end
end

function PromptEmblem.Register(spec: Spec)
	table.insert(specs, spec)
	for _, desc in ipairs(workspace:GetDescendants()) do style(desc) end
end

workspace.DescendantAdded:Connect(style)
-- A prompt renamed after it appeared (AppearanceService names wardrobe prompts) still gets styled.
workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("ProximityPrompt") then
		desc:GetPropertyChangedSignal("Name"):Connect(function() style(desc) end)
	end
end)

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	local spec = specFor(prompt)
	if not spec then return end
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
		-- Shown before we styled it (it appeared mid-frame): style it now; the default prompt
		-- hides itself and Roblox shows it again as Custom.
		styled[prompt] = true
		prompt.Style = Enum.ProximityPromptStyle.Custom
	end
	if shown[prompt] then shown[prompt]() end
	shown[prompt] = build(spec, prompt, inputType)
end)
ProximityPromptService.PromptHidden:Connect(function(prompt)
	local close = shown[prompt]
	if close then
		shown[prompt] = nil
		close()
	end
end)

return PromptEmblem
