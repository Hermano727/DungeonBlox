--[[
	SlimeSpitCast -- ServerScriptService

	A slime's ranged spit (first user: Miasma's underling, MobData MiasmaUnderling). A Moveset CAST
	handler driven by MobMovesetBehaviour for an entry with `Cast = "SlimeSpit"`; with `Ranged = true`
	the mob opens it from range while chasing (MinRange..MaxRange), not only in melee reach.

		Begin(mob, entry)   -> state   faces the target, plays the spit clip (entry.Animation)
		Update(mob, state)  -> bool    releases the glob at ReleaseTime; true once the clip is over
		Finish(mob, state)             ended early: a glob not yet released is never thrown
		Duration(entry)     -> number  seconds the mob is committed (the clip)
		Showcase(model, mobId, entry, trackFor) -> seconds   the F8 animation showcase (no damage)

	The glob is aimed where the target stands at RELEASE, arcs over and splashes there, so it can
	be stepped out of: a ring marks the landing spot for the whole flight. Anyone living within
	entry.SplashRadius of the splash takes entry.Damage once (DamageService, like any mob hit).

	Poison belongs to whoever owns it (the Miasma encounter's MiasmaPoisonService instance), so this
	module only reports hits: SlimeSpitCast.SetHitHandler(function(mob, player, entry) ... end)
	runs for every player the splash hits (entry.PoisonStacks rides along on the entry).

	Entry fields: Damage, SplashRadius (4), FlightSpeed (40 studs/s; flight 0.35..1.2 s),
	ArcHeight (default 3 + 12% of the distance), ReleaseTime (s into the clip), SourceDuration,
	Speed (playback rate), MouthOffset (Vector3 from the mob's root, default (0, -0.6, -2.3)).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local MobAnimController = require(ServerScriptService:WaitForChild("MobAnimController"))
local MobAnimConfig = require(ReplicatedStorage:WaitForChild("MobAnimConfig"))

local GLOB_COLOR = Color3.fromRGB(96, 214, 84)       -- toxic green: reads as poison against the purple body
local GLOB_EDGE = Color3.fromRGB(150, 60, 190)
local DEFAULT_MOUTH = Vector3.new(0, -0.6, -2.3)    -- from the root (body centre) to the mouth at the snap

local SlimeSpitCast = {}

local hitHandler = nil
function SlimeSpitCast.SetHitHandler(fn)
	hitHandler = fn
end

local function speedOf(entry)
	local speed = tonumber(entry.Speed) or 1
	return speed > 0 and speed or 1
end

function SlimeSpitCast.Duration(entry)
	return (tonumber(entry.SourceDuration) or 1.25) / speedOf(entry)
end

local function rootOf(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then return root end
	return nil
end

local function groundBelow(position, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position or (position - Vector3.new(0, 3, 0))
end

local function part(name, shape, size, colour, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = colour
	p.Transparency = transparency
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- The glob: arcs from `origin` to `landing` over `flight` seconds, then splashes. `onSplash(point)`
-- runs at the landing (nil for the showcase: visuals only).
local function throw(origin, landing, entry, onSplash)
	local radius = tonumber(entry.SplashRadius) or 4
	local distance = (Vector3.new(landing.X, 0, landing.Z) - Vector3.new(origin.X, 0, origin.Z)).Magnitude
	local flight = math.clamp(distance / (tonumber(entry.FlightSpeed) or 40), 0.35, 1.2)
	local arc = tonumber(entry.ArcHeight) or (3 + distance * 0.12)

	local marker = part("SpitMarker", Enum.PartType.Cylinder, Vector3.new(0.15, radius * 2, radius * 2), GLOB_COLOR, 0.75)
	marker.CFrame = CFrame.new(landing + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	marker.Parent = Workspace

	local glob = part("SpitGlob", Enum.PartType.Ball, Vector3.new(1.3, 1.3, 1.3), GLOB_COLOR, 0.05)
	glob.Position = origin
	local light = Instance.new("PointLight")
	light.Color = GLOB_COLOR
	light.Range = 8
	light.Brightness = 1.2
	light.Parent = glob
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = Vector3.new(0, 0.45, 0), Vector3.new(0, -0.45, 0)
	a0.Parent, a1.Parent = glob, glob
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(GLOB_COLOR, GLOB_EDGE)
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Lifetime = 0.25
	trail.Parent = glob
	glob.Parent = Workspace

	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local u = math.min(1, (os.clock() - started) / flight)
		glob.Position = origin:Lerp(landing, u) + Vector3.new(0, 4 * arc * u * (1 - u), 0)
		marker.Transparency = 0.75 - 0.35 * u -- firms up as it comes down
		if u < 1 then return end
		connection:Disconnect()
		glob:Destroy()
		marker:Destroy()
		DamageService.PlayEffectAt("PoisonSplat", landing, 120)
		-- the splat: a flat puddle that fades
		local splat = part("SpitSplat", Enum.PartType.Cylinder, Vector3.new(0.2, radius * 1.6, radius * 1.6), GLOB_COLOR, 0.2)
		splat.CFrame = CFrame.new(landing + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		splat.Parent = Workspace
		task.spawn(function()
			for i = 1, 10 do
				task.wait(0.08)
				if not splat.Parent then return end
				splat.Transparency = 0.2 + i * 0.08
			end
		end)
		Debris:AddItem(splat, 1)
		if onSplash then onSplash(landing, radius) end
	end)
end

function SlimeSpitCast.Begin(mob, entry)
	local model = mob.Model
	local root = model and model.PrimaryPart
	local targetRoot = rootOf(mob.TargetPlayer)
	if not root or not targetRoot then return nil end
	mob:FaceToward(targetRoot.Position)
	local speed = speedOf(entry)
	if entry.Animation then MobAnimController.playMoveset(mob, entry.Animation, speed) end
	local now = tick()
	return {
		entry = entry,
		target = mob.TargetPlayer,
		started = now,
		releaseAt = now + (tonumber(entry.ReleaseTime) or 0.58) / speed,
		endsAt = now + SlimeSpitCast.Duration(entry),
		released = false,
	}
end

local function release(mob, state)
	local model = mob.Model
	local root = model and model.PrimaryPart
	local targetRoot = rootOf(state.target)
	if not root or not targetRoot then return end
	local entry = state.entry
	local origin = (root.CFrame * CFrame.new(entry.MouthOffset or DEFAULT_MOUTH)).Position
	local ignore = { model }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local landing = groundBelow(targetRoot.Position, ignore)
	DamageService.PlayEffectAt("PoisonSpit", origin, 150) -- SoundEffects key, heard nearby
	throw(origin, landing, entry, function(point, radius)
		-- (a glob already in the air still lands if the slime dies meanwhile)
		for _, player in ipairs(Players:GetPlayers()) do
			local r = rootOf(player)
			if r then
				local flat = Vector3.new(r.Position.X - point.X, 0, r.Position.Z - point.Z).Magnitude
				local dy = r.Position.Y - point.Y
				if flat <= radius and dy > -2 and dy < 7 then
					DamageService.ApplyToPlayer(player, tonumber(entry.Damage) or mob.Stats.BaseDamage, mob)
					if hitHandler then
						local ok, err = pcall(hitHandler, mob, player, entry)
						if not ok then warn("[SlimeSpitCast] hit handler: " .. tostring(err)) end
					end
				end
			end
		end
	end)
end

function SlimeSpitCast.Update(mob, state)
	local now = tick()
	if not state.released and now >= state.releaseAt then
		state.released = true
		release(mob, state)
	end
	return now >= state.endsAt
end

function SlimeSpitCast.Finish(_mob, state)
	-- Ended early (death, despawn): a glob not yet released is never thrown. One already in the
	-- air lands as normal.
	if state then state.released = true end
end

-- The F8 animation showcase: the clip, and a harmless glob 14 studs in front.
function SlimeSpitCast.Showcase(model, mobId, entry, trackFor)
	local root = model and model.PrimaryPart
	if not root then return 1 end
	local clips = MobAnimConfig[mobId] and MobAnimConfig[mobId].Moveset
	local animId = entry.Animation and clips and clips[entry.Animation]
	if animId then
		local track = trackFor(animId)
		track:Play(0.1)
		track:AdjustSpeed(speedOf(entry))
	end
	task.delay((tonumber(entry.ReleaseTime) or 0.58) / speedOf(entry), function()
		if not root.Parent then return end
		local origin = (root.CFrame * CFrame.new(entry.MouthOffset or DEFAULT_MOUTH)).Position
		local ahead = (root.CFrame * CFrame.new(0, 0, -14)).Position
		throw(origin, groundBelow(ahead, { model }), entry, nil)
	end)
	return SlimeSpitCast.Duration(entry) + 0.5
end

return SlimeSpitCast
