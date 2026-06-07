local InteractiveGrass = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local function createRunner(opts)
	opts = opts or {}

	--------------------------------------------------------------------
	-- SETTINGS (tweak things here, not below)
	-- if something looks weird in-game, it's probably this section
	--------------------------------------------------------------------

	-- Player and grass folder
	local player = opts.player or Players.LocalPlayer
	-- player the grass reacts to (usually the local player)

	local grassFolder = opts.grassFolder or workspace:WaitForChild("Grass")
	-- folder that contains all grass models / parts


	--------------------------------------------------------------------
	-- DISTANCE / PERFORMANCE
	--------------------------------------------------------------------

	local ACTIVE_RADIUS = opts.ACTIVE_RADIUS or 40
	-- grass farther than this (XZ distance) stops updating

	local CULL_MODE = opts.CULL_MODE or "freeze"
	-- "none"   = always update everything (expensive)
	-- "freeze" = far grass stays frozen (cheap and good enough)
	-- "reset"  = far grass smoothly returns to base pose, then stops

	local SMOOTH_FAR = opts.SMOOTH_FAR or 10
	-- how fast grass returns to base pose when far away (reset mode)


	--------------------------------------------------------------------
	-- PLAYER INTERACTION (walking through grass)
	--------------------------------------------------------------------

	local RADIUS = opts.RADIUS or 8
	-- max distance for player to bend grass

	local MAX_TILT = opts.MAX_TILT or math.rad(28)
	-- maximum bend angle


	--------------------------------------------------------------------
	-- SMOOTHING
	--------------------------------------------------------------------

	local SMOOTH_GROUND = opts.SMOOTH_GROUND or 14
	-- how fast grass reacts when player is on the ground

	local SMOOTH_AIR = opts.SMOOTH_AIR or 28
	-- how fast grass reacts while player is in the air
	-- higher = faster / snappier


	--------------------------------------------------------------------
	-- WIND (just to avoid dead-looking grass)
	--------------------------------------------------------------------

	local WIND_MIN = opts.WIND_MIN or math.rad(1.5)
	local WIND_MAX = opts.WIND_MAX or math.rad(4.0)
	-- minimum and maximum wind strength

	local WIND_SPEED_MIN = opts.WIND_SPEED_MIN or 0.6
	local WIND_SPEED_MAX = opts.WIND_SPEED_MAX or 1.2
	-- wind movement speed


	--------------------------------------------------------------------
	-- LANDING IMPACT (when player hits the ground)
	--------------------------------------------------------------------

	local LAND_RADIUS = opts.LAND_RADIUS or 12
	-- how far the impact reaches

	local LAND_OPEN = opts.LAND_OPEN or math.rad(38)
	-- how much the grass opens on landing

	local LAND_FALLOFF = opts.LAND_FALLOFF or 6
	-- how fast the effect loses strength with distance

	local LAND_DECAY = opts.LAND_DECAY or 8
	-- how fast the effect fades over time

	local MAX_LAND_EVENTS = opts.MAX_LAND_EVENTS or 6
	-- cap stored impacts (prevents spam)


	--------------------------------------------------------------------
	-- CONSTANTS (do not touch)
	--------------------------------------------------------------------

	local UP = Vector3.new(0, 1, 0)
	local DEFAULT_DIR = Vector3.new(1, 0, 0)


	--------------------------------------------------------------------
	-- INTERNAL STATE
	--------------------------------------------------------------------

	local items = {}
	local landEvents = {}


	--------------------------------------------------------------------
	-- HELPER FUNCTIONS
	--------------------------------------------------------------------

	local function isSupported(inst)
		return inst:IsA("Model") or inst:IsA("BasePart")
	end

	local function getBaseCFrame(inst)
		if inst:IsA("Model") then
			return inst:GetPivot()
		else
			return inst.CFrame
		end
	end

	local function getPos3(inst)
		if inst:IsA("Model") then
			return inst:GetPivot().Position
		else
			return inst.Position
		end
	end

	local function applyCFrame(inst, cf)
		if inst:IsA("Model") then
			inst:PivotTo(cf)
		else
			inst.CFrame = cf
		end
	end

	-- prevents registering parts that belong to an already registered model
	local function hasRegisteredModelAncestor(part)
		local m = part:FindFirstAncestorOfClass("Model")
		while m do
			if items[m] then
				return true
			end
			m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model") or nil
		end
		return false
	end


	--------------------------------------------------------------------
	-- GRASS REGISTRATION
	--------------------------------------------------------------------

	local function register(inst)
		if not isSupported(inst) then return end
		if inst:IsA("BasePart") and hasRegisteredModelAncestor(inst) then return end

		local base = getBaseCFrame(inst)
		if not base then return end

		items[inst] = {
			base = base,
			cur = base,

			-- random seeds so everything doesn't move the same
			seedA = math.random() * 1000,
			seedB = math.random() * 1000,

			-- per-instance wind randomness
			windAmpX = WIND_MIN + (WIND_MAX - WIND_MIN) * math.random(),
			windAmpZ = WIND_MIN + (WIND_MAX - WIND_MIN) * math.random(),
			windSpdA = WIND_SPEED_MIN + (WIND_SPEED_MAX - WIND_SPEED_MIN) * math.random(),
			windSpdB = WIND_SPEED_MIN + (WIND_SPEED_MAX - WIND_SPEED_MIN) * math.random(),

			dir = DEFAULT_DIR,
			ang = 0,

			farFrozen = false,
		}
	end

	local function unregister(inst)
		items[inst] = nil
	end

	local function scanAll()
		for _, inst in ipairs(grassFolder:GetDescendants()) do
			if inst:IsA("Model") then
				register(inst)
			end
		end
		for _, inst in ipairs(grassFolder:GetDescendants()) do
			if inst:IsA("BasePart") then
				register(inst)
			end
		end
	end


	--------------------------------------------------------------------
	-- PLAYER
	--------------------------------------------------------------------

	local function getCharBits()
		local char = player.Character
		if not char then return end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum then return end

		return hrp, hum
	end

	local lastOnGround = true


	--------------------------------------------------------------------
	-- LANDING EVENTS
	--------------------------------------------------------------------

	local function addLandEvent(posXZ, intensity)
		table.insert(landEvents, 1, {
			pos = posXZ,
			t = os.clock(),
			k = intensity
		})

		while #landEvents > MAX_LAND_EVENTS do
			table.remove(landEvents)
		end
	end


	--------------------------------------------------------------------
	-- MAIN LOOP
	--------------------------------------------------------------------

	local connStep, connAdded, connRemoving

	local function start()
		if connStep then return end

		scanAll()

		connAdded = grassFolder.DescendantAdded:Connect(register)
		connRemoving = grassFolder.DescendantRemoving:Connect(unregister)

		connStep = RunService.RenderStepped:Connect(function(dt)
			local hrp, hum = getCharBits()
			if not hrp then return end

			local onGround = hum.FloorMaterial ~= Enum.Material.Air
			local landed = (not lastOnGround) and onGround
			lastOnGround = onGround

			local t = os.clock()
			local ppos3 = hrp.Position
			local pposXZ = Vector3.new(ppos3.X, 0, ppos3.Z)

			-- detect landing
			if landed then
				local vY = hrp.AssemblyLinearVelocity.Y
				local intensity = math.clamp((-vY) / 60, 0.35, 1.25)
				addLandEvent(pposXZ, intensity)
			end

			local vel = hrp.AssemblyLinearVelocity
			local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			local activeR2 = ACTIVE_RADIUS * ACTIVE_RADIUS

			for inst, s in pairs(items) do
				if not inst.Parent then
					items[inst] = nil
					continue
				end

				local base = s.base
				local pos = getPos3(inst)

				local dx = pos.X - ppos3.X
				local dz = pos.Z - ppos3.Z
				local dist2 = dx*dx + dz*dz

				-- distance culling
				if dist2 > activeR2 and CULL_MODE ~= "none" then
					if CULL_MODE == "freeze" then
						continue
					end
				end

				-- wind
				local windX = math.sin(t * s.windSpdA + s.seedA) * s.windAmpX
				local windZ = math.sin(t * s.windSpdB + s.seedB) * s.windAmpZ
				local windRot = CFrame.Angles(windX, 0, windZ)

				local targetDir = DEFAULT_DIR
				local targetAng = 0

				-- player interaction
				local gposXZ = Vector3.new(pos.X, 0, pos.Z)
				local toPlayer = gposXZ - pposXZ
				local dist = toPlayer.Magnitude

				if onGround and dist > 0 and dist < RADIUS then
					local strength = 1 - (dist / RADIUS)
					strength *= strength

					local speedBoost = math.clamp(speed / 18, 0, 1)
					targetAng = MAX_TILT * strength + math.rad(10) * speedBoost
					targetDir = toPlayer.Unit
				end

				-- landing impact
				for _, e in ipairs(landEvents) do
					local age = t - e.t
					if age < 1.2 then
						local d = (gposXZ - e.pos).Magnitude
						if d < LAND_RADIUS and d > 0 then
							local k = math.exp(-d / LAND_FALLOFF) * math.exp(-LAND_DECAY * age)
							local open = LAND_OPEN * e.k * k
							targetAng += open
							targetDir = targetDir:Lerp((gposXZ - e.pos).Unit, open / LAND_OPEN)
						end
					end
				end

				local smooth = onGround and SMOOTH_GROUND or SMOOTH_AIR
				local alpha = 1 - math.exp(-smooth * dt)

				s.dir = s.dir:Lerp(targetDir, alpha)
				s.ang += (targetAng - s.ang) * alpha

				local axis = UP:Cross(s.dir)
				local rot = axis.Magnitude > 0 and CFrame.fromAxisAngle(axis.Unit, s.ang) or CFrame.identity

				local pos3 = base.Position
				local rel = base - pos3
				local desired = CFrame.new(pos3) * rot * rel * windRot

				s.cur = s.cur:Lerp(desired, alpha)
				applyCFrame(inst, s.cur)
			end

			-- clean old landing events
			for i = #landEvents, 1, -1 do
				if (t - landEvents[i].t) > 1.5 then
					table.remove(landEvents, i)
				end
			end
		end)
	end


	--------------------------------------------------------------------
	-- CONTROL
	--------------------------------------------------------------------

	local function stop()
		if connStep then connStep:Disconnect() connStep = nil end
		if connAdded then connAdded:Disconnect() connAdded = nil end
		if connRemoving then connRemoving:Disconnect() connRemoving = nil end

		for inst, s in pairs(items) do
			if inst and inst.Parent then
				applyCFrame(inst, s.base)
			end
		end

		table.clear(items)
		table.clear(landEvents)
		lastOnGround = true
	end

	return {
		Start = start,
		Stop = stop,
	}
end

function InteractiveGrass.new(opts)
	return createRunner(opts)
end

return InteractiveGrass
