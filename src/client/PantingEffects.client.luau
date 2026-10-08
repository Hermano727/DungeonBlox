--[[
	PantingEffects

	What everyone sees and hears at a player who's out of energy (their EnergyPanting attribute,
	set only by the server's EnergyServer when energy hits 0, so it can't be faked or hidden):

	  - a dull crimson drain sinking off the body into the ground (energy bleeding away),
	  - ragged grey breath puffs at the mouth,
	  - a faint dark-red outline that throbs with the breathing,
	  - heavy breathing (SoundEffects.Panting; silent while it's empty).

	Kept modest because it happens often, but readable at fighting range: in a PvP fight, the one
	panting is the one to go for. The hunched, heaving pose is MovementPresentation's.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SoundEffects = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("SoundEffects"))

local VOLUME = 0.5
local HEARD_WITHIN = 45 -- studs
local SEEN_WITHIN = 160 -- studs from the camera
local FADE = 0.4
local BREATH_RATE = 1.6 -- matches MovementPresentation's PANT_RATE

local DRAIN = Color3.fromRGB(120, 24, 30) -- dull crimson
local DRAIN_DARK = Color3.fromRGB(40, 10, 14)
local OUTLINE = Color3.fromRGB(150, 30, 36)
local BREATH = Color3.fromRGB(190, 186, 180)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function soundId(): string?
	local entry = SoundEffects.Panting
	if type(entry) == "table" then entry = entry[1] end
	return (type(entry) == "string" and entry ~= "") and entry or nil
end

local active = {} -- [player] = { emitters, attachments, highlight, sound, breath, lastBreath }

local function stop(player)
	local fx = active[player]
	active[player] = nil
	if not fx then return end
	-- (the attachments carry the emitters; destroyed once the last particles have faded)
	for _, emitter in ipairs(fx.emitters) do
		emitter.Enabled = false
	end
	task.delay(1.5, function() -- let the last particles finish
		for _, attachment in ipairs(fx.attachments) do attachment:Destroy() end
	end)
	if fx.highlight then
		local fade = TweenService:Create(fx.highlight, TweenInfo.new(FADE), { OutlineTransparency = 1, FillTransparency = 1 })
		fade.Completed:Once(function() fx.highlight:Destroy() end)
		fade:Play()
	end
	if fx.sound then
		local fade = TweenService:Create(fx.sound, TweenInfo.new(FADE), { Volume = 0 })
		fade.Completed:Once(function() fx.sound:Destroy() end)
		fade:Play()
	end
end

local function start(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or active[player] then return end
	local fx = { emitters = {}, attachments = {} }

	-- The drain: dark red wisps slipping down off the body and pooling at the feet.
	local body = Instance.new("Attachment")
	body.Name = "PantDrain"
	body.Position = Vector3.new(0, 0.6, 0)
	body.Parent = root
	local drain = Instance.new("ParticleEmitter")
	drain.Texture = SMOKE
	drain.Color = ColorSequence.new(DRAIN, DRAIN_DARK)
	drain.LightEmission = 0.15
	drain.LightInfluence = 0.6
	drain.Rate = 9
	drain.Lifetime = NumberRange.new(0.9, 1.4)
	drain.Speed = NumberRange.new(0.6, 1.4)
	drain.SpreadAngle = Vector2.new(35, 35)
	drain.EmissionDirection = Enum.NormalId.Bottom
	drain.Acceleration = Vector3.new(0, -2.5, 0)
	drain.Drag = 1.5
	drain.Rotation = NumberRange.new(0, 360)
	drain.RotSpeed = NumberRange.new(-30, 30)
	drain.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 2.2) })
	drain.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.72), NumberSequenceKeypoint.new(1, 1),
	})
	drain.Parent = body
	table.insert(fx.emitters, drain)

	-- Breath puffs at the mouth, one per breath (emitted by hand below).
	local head = character:FindFirstChild("Head") or root
	local mouth = Instance.new("Attachment")
	mouth.Name = "PantBreath"
	mouth.Position = head == root and Vector3.new(0, 2.2, -0.6) or Vector3.new(0, -0.25, -0.55)
	mouth.Parent = head
	local breath = Instance.new("ParticleEmitter")
	breath.Texture = SMOKE
	breath.Color = ColorSequence.new(BREATH)
	breath.LightInfluence = 1
	breath.Rate = 0
	breath.Lifetime = NumberRange.new(0.5, 0.8)
	breath.Speed = NumberRange.new(1.5, 2.5)
	breath.SpreadAngle = Vector2.new(15, 15)
	breath.EmissionDirection = Enum.NormalId.Front
	breath.Drag = 3
	breath.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.8) })
	breath.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	breath.Parent = mouth
	table.insert(fx.emitters, breath)

	-- A faint dark-red outline, throbbing with the breathing.
	local highlight = Instance.new("Highlight")
	highlight.Name = "PantOutline"
	highlight.FillColor = OUTLINE
	highlight.OutlineColor = OUTLINE
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = character
	fx.highlight = highlight

	local id = soundId()
	if id then
		local sound = Instance.new("Sound")
		sound.Name = "Panting"
		sound.SoundId = id
		sound.Looped = true
		sound.Volume = 0
		sound.RollOffMaxDistance = HEARD_WITHIN
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.Parent = root
		sound:Play()
		TweenService:Create(sound, TweenInfo.new(FADE), { Volume = VOLUME }):Play()
		fx.sound = sound
	end

	fx.attachments = { body, mouth } -- the emitters go with them
	fx.breath = breath
	fx.lastBreath = 0
	active[player] = fx
end

-- The breathing: outline throb and a puff on each exhale. Skips characters out of view range.
RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local t = os.clock()
	local phase = (t * BREATH_RATE) % 1
	local throb = 0.5 + 0.5 * math.sin(t * math.pi * 2 * BREATH_RATE)
	for player, fx in pairs(active) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local near = root and (root.Position - camera.CFrame.Position).Magnitude <= SEEN_WITHIN
		if fx.highlight then
			fx.highlight.OutlineTransparency = near and (0.55 - throb * 0.25) or 1
			fx.highlight.FillTransparency = near and (0.9 - throb * 0.06) or 1
		end
		-- one puff per breath, on the exhale
		if near and phase < 0.15 and t - fx.lastBreath > 0.4 / BREATH_RATE then
			fx.lastBreath = t
			fx.breath:Emit(2)
		end
	end
end)

local function watch(player)
	local function refresh()
		if player:GetAttribute("EnergyPanting") == true then start(player) else stop(player) end
	end
	player:GetAttributeChangedSignal("EnergyPanting"):Connect(refresh)
	player.CharacterAdded:Connect(function()
		stop(player)
		task.defer(refresh)
	end)
	refresh()
end

for _, player in ipairs(Players:GetPlayers()) do watch(player) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(stop)
