--[[
	ArenaShake -- camera shake for big world events (client only).

	ArenaShake.Shake({ ... }) adds one shake; any number can run at once and they SUM, so a
	slam jolt landing during a roar rumble stacks naturally. Mostly vertical (the ground
	heaving), with a little sideways sway and roll so it doesn't read as a mechanical bob.

		Shake {
			amplitude = studs of vertical travel at full strength (default .8)
			rotation  = degrees of pitch/roll at full strength (default .8)
			duration  = seconds at full strength (after ramp-in)       (default .5)
			rampIn    = seconds to reach full strength                  (default .05)
			decay     = seconds to fade out after `duration`            (default .6)
			frequency = shakes per second                               (default 16)
			focus     = Vector3? -- if set, strength falls off with the camera's distance
			fullRadius, farRadius, farStrength -- that falloff (defaults 60 / 170 / .35)
		}

	Applied at RenderPriority.Camera + 1: after whoever owns the camera this frame (the
	first-person camera, or a cutscene) has set it, so it never accumulates or drifts.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ArenaShake = {}

local BIND = "ArenaShake"
local active = {}
local bound = false

local function strengthAt(shake, t, cameraPos)
	local envelope
	if t < shake.rampIn then
		envelope = t / math.max(shake.rampIn, 1e-3)
	elseif t < shake.rampIn + shake.duration then
		envelope = 1
	else
		envelope = 1 - (t - shake.rampIn - shake.duration) / math.max(shake.decay, 1e-3)
	end
	envelope = math.clamp(envelope, 0, 1)
	if shake.focus then
		local d = (cameraPos - shake.focus).Magnitude
		if d > shake.fullRadius then
			local u = math.clamp((d - shake.fullRadius) / math.max(shake.farRadius - shake.fullRadius, 1), 0, 1)
			envelope *= 1 - u * (1 - shake.farStrength)
		end
	end
	return envelope * envelope -- eases the tail so the fade reads as settling, not cutting off
end

local function step()
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local now = os.clock()
	local ty, tx, pitch, roll = 0, 0, 0, 0
	for i = #active, 1, -1 do
		local shake = active[i]
		local t = now - shake.started
		if t > shake.rampIn + shake.duration + shake.decay then
			table.remove(active, i)
		else
			local a = strengthAt(shake, t, camera.CFrame.Position)
			local f = t * shake.frequency
			-- math.noise is ~[-.5,.5]; x2 makes amplitude the real peak.
			ty += math.noise(f, shake.seed) * 2 * shake.amplitude * a
			tx += math.noise(f, shake.seed + 17) * 2 * shake.amplitude * .3 * a
			pitch += math.noise(f, shake.seed + 31) * 2 * shake.rotation * a
			roll += math.noise(f, shake.seed + 47) * 2 * shake.rotation * .6 * a
		end
	end
	if #active == 0 then
		RunService:UnbindFromRenderStep(BIND)
		bound = false
		return
	end
	camera.CFrame = camera.CFrame * CFrame.new(tx, ty, 0) * CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
end

function ArenaShake.Shake(opts)
	opts = opts or {}
	table.insert(active, {
		started = os.clock(),
		seed = math.random() * 1000,
		amplitude = tonumber(opts.amplitude) or .8,
		rotation = tonumber(opts.rotation) or .8,
		duration = math.max(0, tonumber(opts.duration) or .5),
		rampIn = math.max(0, tonumber(opts.rampIn) or .05),
		decay = math.max(.05, tonumber(opts.decay) or .6),
		frequency = tonumber(opts.frequency) or 16,
		focus = typeof(opts.focus) == "Vector3" and opts.focus or nil,
		fullRadius = tonumber(opts.fullRadius) or 60,
		farRadius = tonumber(opts.farRadius) or 170,
		farStrength = tonumber(opts.farStrength) or .35,
	})
	if not bound then
		bound = true
		RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, step)
	end
end

function ArenaShake.StopAll()
	table.clear(active)
end

return ArenaShake
