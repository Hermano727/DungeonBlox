--[[
	FishCatchVisuals
	The catch show (FishingConfig.CATCH_SHOW): when someone nearby lands a fish that has a model,
	it leaps out of the water in an arc to just above their head, hangs there turning in its
	effects, then shrinks into them (into the bag). Your OWN catch is the showcase instead: the
	fish leaps into the middle of your screen (a real 3D fish just in front of the camera, so its
	particles render, which a ViewportFrame can't), lit, spinning in its effects for a second
	longer, then drops off the bottom of the screen. SpearFishHandler fires GameEvents/FishCatchShow
	to everyone within SHOW_RADIUS, the angler included.

	Effects scale with the fish: the golden fish gets a dense sparkle trail, a big burst of glints
	at the top of the leap, a soft halo and a golden light; the swift fish a quick leap, a wind
	ribbon (a swirl as it whirls at the top), streaks off its tail and a burst of speed lines; the
	lucky fish a few green motes.
	All local and cosmetic.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FishingConfig = require(ReplicatedStorage:WaitForChild("FishingConfig"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))

local FishCatchShow = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("FishCatchShow")

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local STREAK = "rbxasset://textures/particles/smoke_main.dds" -- soft blob; squashed into a streak
local LEAP_TIME = 0.75
local INTO_BAG_TIME = 0.35
local ABOVE_HEAD = 3.2 -- studs above the root where the fish hangs (seen by others)
local SHOWCASE_DISTANCE = 2.4 -- your own catch hangs this many fish-lengths (+1) from the camera
local SHOWCASE_EXTRA_HOLD = 1.0 -- seconds longer than the hang others see

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.LightEmission = 1
	e.LightInfluence = 0
	e.ZOffset = 1
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

-- The fish's effects, scaled by its CATCH_SHOW entry. Returns the burst emitter.
local function dress(fish, spec)
	local colors = ColorSequence.new(spec.color, spec.deep)
	local centre = Instance.new("Attachment")
	centre.Parent = fish
	-- A trail of sparkles shed as it flies and hangs.
	emitter(centre, {
		Color = colors, Rate = spec.trailRate,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec.size), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.1, 1), Lifetime = NumberRange.new(0.5, 1.1),
		Speed = NumberRange.new(0.5, 2.5), SpreadAngle = Vector2.new(180, 180), Drag = 2,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
		EmissionDirection = Enum.NormalId.Top,
	})
	-- The burst of glints at the top of the leap (emitted by hand).
	local burstCount = spec.burst
	local burst = emitter(centre, {
		Color = colors, Rate = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec.size * 1.8), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0, 1), Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(180, 180), Drag = 3,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-180, 180),
	})
	if spec.halo then
		-- A big soft glow that sits behind the fish.
		emitter(centre, {
			Color = ColorSequence.new(spec.color), Rate = 6, LockedToPart = true,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.6), NumberSequenceKeypoint.new(1, 3.4) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.86), NumberSequenceKeypoint.new(1, 1) }), -- peak 14% opaque (was 28%: too bright up close)
			Lifetime = NumberRange.new(0.8, 1.0), Speed = NumberRange.new(0), ZOffset = -1,
		})
	end
	if spec.speed then
		-- A pale wind ribbon behind it (a swirl while it spins at the top)...
		local size = fish.Size
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, size.Y * 0.3, size.Z * 0.2)
		top.Parent = fish
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -size.Y * 0.3, size.Z * 0.2)
		bottom.Parent = fish
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = top, bottom
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), spec.color)
		trail.Transparency = NumberSequence.new(0.25, 1)
		trail.Lifetime = 0.35
		trail.LightEmission = 0.7
		trail.FaceCamera = true
		trail.Parent = fish
		-- ...wind streaks streaming off the tail (stretched along their flight)...
		local tail = Instance.new("Attachment")
		tail.Position = Vector3.new(0, 0, size.Z * 0.45)
		tail.Parent = fish
		emitter(tail, {
			Texture = STREAK, Color = ColorSequence.new(Color3.new(1, 1, 1), spec.color), Rate = 70,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.07), NumberSequenceKeypoint.new(1, 0) }),
			Squash = NumberSequence.new(2.6), Transparency = NumberSequence.new(0.2, 1),
			Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(12, 20), SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Back, LightEmission = 0.8,
		})
		-- ...and a burst of speed lines out in every direction at the top of the leap.
		burst = emitter(centre, {
			Texture = STREAK, Color = ColorSequence.new(Color3.new(1, 1, 1), spec.color), Rate = 0,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0) }),
			Squash = NumberSequence.new(3), Transparency = NumberSequence.new(0, 1),
			Lifetime = NumberRange.new(0.25, 0.45), Speed = NumberRange.new(22, 32), SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
		})
		burstCount = 45
	end
	if spec.light > 0 then
		local light = Instance.new("PointLight")
		light.Color = spec.color
		light.Range = spec.light
		light.Brightness = spec.lightBrightness or 3
		light.Shadows = false
		light.Parent = fish
	end
	return burst, burstCount
end

local function play(data)
	if type(data) ~= "table" then return end
	local spec = FishingConfig.CATCH_SHOW[data.fishId]
	local visuals = ReplicatedStorage:FindFirstChild(FishingConfig.VISUALS_FOLDER)
	local template = spec and visuals and visuals:FindFirstChild(spec.model)
	local angler = Players:GetPlayerByUserId(tonumber(data.userId) or 0)
	local character = angler and angler.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not template or not root or typeof(data.from) ~= "Vector3" then return end

	local fish = template:Clone()
	fish.Anchored = true
	fish.CanCollide, fish.CanTouch, fish.CanQuery = false, false, false
	local baseSize = fish.Size
	fish.CFrame = CFrame.new(data.from)
	fish.Parent = workspace
	local burst, burstCount = dress(fish, spec)
	local leapTime = spec.leap or LEAP_TIME
	SfxService.PlayEffect("SpearSplash", { Position = data.from })

	local start = os.clock()
	local hold = spec.hold
	local spin = spec.speed and 9 or 2.2 -- radians per second while it hangs
	-- Your own catch is shown off in the middle of your screen instead of over your head: the
	-- fish hangs in front of the camera, lit, spinning in its effects (the showcase).
	local mine = angler == Players.LocalPlayer
	local dist = baseSize.Z * SHOWCASE_DISTANCE + 1
	if mine then
		hold += SHOWCASE_EXTRA_HOLD
		spin = spec.speed and 7 or 2.6
		local light = Instance.new("PointLight")
		light.Name = "ShowcaseLight"
		light.Color = Color3.fromRGB(255, 246, 230)
		light.Brightness = 2
		light.Range = dist + 4
		light.Shadows = false
		light.Parent = fish
	end
	-- Where it hangs, and which way it faces there.
	local function hangPoint()
		if mine then
			local cam = workspace.CurrentCamera.CFrame
			return (cam * CFrame.new(0, 0, -dist)).Position
		end
		return root.Position + Vector3.new(0, ABOVE_HEAD, 0)
	end
	local function hangFrame(p, angle)
		if mine then
			-- Side-on to the camera (its profile), turned about the screen's up axis, tipped a
			-- little so the back shows.
			local cam = workspace.CurrentCamera.CFrame
			return CFrame.lookAt(p, p + cam.RightVector, cam.UpVector) * CFrame.Angles(0, angle, 0) * CFrame.Angles(0.2, 0, 0)
		end
		return CFrame.new(p) * CFrame.Angles(0, angle, 0)
	end
	local burstDone = false
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not fish.Parent or not root.Parent then
			conn:Disconnect()
			fish:Destroy()
			return
		end
		local t = os.clock() - start
		local top = hangPoint()
		if t < leapTime then
			-- The leap: an arc out of the water, nose along the way it's going, tail wagging.
			local u = t / leapTime
			local arc = mine and 1.5 or 3 + (top - data.from).Magnitude * 0.15
			local function at(k) return data.from:Lerp(top, k) + Vector3.new(0, arc * 4 * k * (1 - k), 0) end
			local p, ahead = at(u), at(math.min(1, u + 0.03))
			local dir = ahead - p
			if dir.Magnitude < 1e-3 then dir = Vector3.new(0, 1, 0) end
			fish.CFrame = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, math.sin(t * 30) * 0.35, 0)
		elseif t < leapTime + hold then
			if not burstDone then
				burstDone = true
				if burstCount > 0 then burst:Emit(burstCount) end
			end
			-- The hang: a turn and a gentle bob above the angler's head (the swift fish whirls).
			local h = t - leapTime
			local p = top + Vector3.new(0, math.sin(h * 3) * 0.15, 0)
			fish.CFrame = hangFrame(p, h * spin) * CFrame.Angles(0, 0, math.sin(h * 9) * 0.12)
		elseif t < leapTime + hold + INTO_BAG_TIME then
			-- Into the bag: shrink down into the angler (your own: down off the bottom of the screen).
			local u = (t - leapTime - hold) / INTO_BAG_TIME
			local bag = mine and (workspace.CurrentCamera.CFrame * CFrame.new(0, -dist * 0.55, -dist)).Position or root.Position
			local p = top:Lerp(bag, u)
			fish.Size = baseSize * math.max(0.05, 1 - u)
			fish.CFrame = hangFrame(p, (t - leapTime) * spin)
		else
			conn:Disconnect()
			-- Let the sparkles already shed fade out before the part (and its emitters) go.
			fish.Transparency = 1
			for _, d in ipairs(fish:GetDescendants()) do
				if d:IsA("ParticleEmitter") then d.Enabled = false end
				if d:IsA("PointLight") then TweenService:Create(d, TweenInfo.new(0.4), { Brightness = 0 }):Play() end
			end
			game:GetService("Debris"):AddItem(fish, 1.5)
		end
	end)
end

FishCatchShow.OnClientEvent:Connect(play)
