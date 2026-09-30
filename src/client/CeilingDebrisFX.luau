--[[
	CeilingDebrisFX -- rock chunks shaken loose from the ceiling (client only, visual only).

		CeilingDebris.Rain(centre, radius, duration, perSecond, parent) -- steady fall over time
		CeilingDebris.Burst(centre, radius, count, parent, sizeScale)  -- everything at once

	Each rock breaks out OF the roof directly above its own spot (a raycast up per rock, so it
	fits whatever roof the arena has): it starts half buried in the ceiling with a burst of dust
	and a trickle of grit shooting down from the crack, hangs there for a split second, then
	drops under gravity, bounces once off the floor with a dust puff, rests a moment, and
	crumbles away. Rocks are
	anchored parts moved by one shared RenderStepped loop (BulkMoveTo), capped at MAX_ROCKS
	alive, so a heavy rain can't tank the frame rate.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Debris = {}

local MAX_ROCKS = 120
local GRAVITY = 120
local BOUNCE = .28           -- fraction of impact speed kept on the single bounce
local REST_SECONDS = 1.1
local CRUMBLE_SECONDS = .45
local SIZE_MIN, SIZE_MAX = .35, 1.6
local ROCK_COLORS = {
	Color3.fromRGB(88, 84, 80), Color3.fromRGB(70, 67, 64), Color3.fromRGB(104, 98, 90), Color3.fromRGB(60, 58, 60),
}
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local EMBED = .45            -- how much of a rock starts inside the roof (fraction of its height)
local HANG_MIN, HANG_MAX = .06, .2 -- it clings to the crack this long before it drops

local rocks = {}
local folder
local puffAttachment, puffEmitter
local crackAttachment, crackDust, crackGrit
local loop

local function ensureFolder(parent)
	if folder and folder.Parent then return folder end
	folder = Instance.new("Folder")
	folder.Name = "CeilingDebris"
	folder.Parent = parent or Workspace
	local anchor = Instance.new("Part")
	anchor.Name = "PuffAnchor"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(.2, .2, .2)
	anchor.Parent = folder
	puffAttachment = Instance.new("Attachment")
	puffAttachment.Parent = anchor
	puffEmitter = Instance.new("ParticleEmitter")
	puffEmitter.Texture = SMOKE
	puffEmitter.Color = ColorSequence.new(Color3.fromRGB(125, 118, 110))
	puffEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .8), NumberSequenceKeypoint.new(1, 3) })
	puffEmitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .45), NumberSequenceKeypoint.new(1, 1) })
	puffEmitter.Lifetime = NumberRange.new(.5, .9)
	puffEmitter.Speed = NumberRange.new(2, 5)
	puffEmitter.SpreadAngle = Vector2.new(80, 80)
	puffEmitter.EmissionDirection = Enum.NormalId.Top
	puffEmitter.Rate = 0
	puffEmitter.LightInfluence = .6
	puffEmitter.Parent = puffAttachment

	-- The crack in the roof a rock breaks out of: dust blasting DOWN, plus grit that falls.
	local crackAnchor = anchor:Clone()
	crackAnchor.Name = "CrackAnchor"
	crackAnchor.Parent = folder
	crackAttachment = Instance.new("Attachment")
	crackAttachment.Parent = crackAnchor
	crackDust = Instance.new("ParticleEmitter")
	crackDust.Texture = SMOKE
	crackDust.Color = ColorSequence.new(Color3.fromRGB(140, 132, 122))
	crackDust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.5) })
	crackDust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .25), NumberSequenceKeypoint.new(1, 1) })
	crackDust.Lifetime = NumberRange.new(.8, 1.3)
	crackDust.Speed = NumberRange.new(6, 12)
	crackDust.SpreadAngle = Vector2.new(35, 35)
	crackDust.EmissionDirection = Enum.NormalId.Bottom
	crackDust.Acceleration = Vector3.new(0, -8, 0)
	crackDust.Drag = 2
	crackDust.Rate = 0
	crackDust.LightInfluence = .6
	crackDust.Parent = crackAttachment
	crackGrit = Instance.new("ParticleEmitter")
	crackGrit.Texture = SMOKE
	crackGrit.Color = ColorSequence.new(Color3.fromRGB(70, 66, 62))
	crackGrit.Size = NumberSequence.new(.25, .15)
	crackGrit.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(.8, .2), NumberSequenceKeypoint.new(1, 1) })
	crackGrit.Lifetime = NumberRange.new(1, 1.6)
	crackGrit.Speed = NumberRange.new(2, 6)
	crackGrit.SpreadAngle = Vector2.new(25, 25)
	crackGrit.EmissionDirection = Enum.NormalId.Bottom
	crackGrit.Acceleration = Vector3.new(0, -GRAVITY * .6, 0)
	crackGrit.Rate = 0
	crackGrit.LightInfluence = .8
	crackGrit.Parent = crackAttachment
	return folder
end

local function crack(position, s)
	if not crackAttachment then return end
	crackAttachment.WorldPosition = position
	crackDust:Emit(math.clamp(math.floor(2 + s * 2), 2, 6))
	crackGrit:Emit(math.clamp(math.floor(4 + s * 4), 4, 12))
end

local function rayParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local vfx = Workspace:FindFirstChild("MiasmaEncounterVFX")
	if vfx then table.insert(ignore, vfx) end
	params.FilterDescendantsInstances = ignore
	return params
end

local function ceilingY(centre, params)
	local hit = Workspace:Raycast(centre + Vector3.new(0, 4, 0), Vector3.new(0, 250, 0), params)
	return hit and hit.Position.Y or (centre.Y + 50)
end

local function puff(position)
	if not puffAttachment then return end
	puffAttachment.WorldPosition = position
	puffEmitter:Emit(3)
end

local function stepRocks(dt)
	local now = os.clock()
	local parts, cframes = {}, {}
	for i = #rocks, 1, -1 do
		local r = rocks[i]
		if not r.part.Parent then
			table.remove(rocks, i)
		elseif r.phase == "hang" then
			if now >= r.dropAt then r.phase = "fall" end
		elseif r.phase == "fall" then
			r.vel -= GRAVITY * dt
			r.pos += Vector3.new(0, r.vel * dt, 0)
			r.rot *= CFrame.Angles(r.spin.X * dt, r.spin.Y * dt, r.spin.Z * dt)
			if r.pos.Y - r.half <= r.floorY then
				r.pos = Vector3.new(r.pos.X, r.floorY + r.half, r.pos.Z)
				if not r.bounced then
					r.bounced = true
					r.vel = -r.vel * BOUNCE
					r.spin *= .4
					puff(r.pos)
				else
					r.phase = "rest"
					r.restUntil = now + REST_SECONDS * (.7 + math.random() * .6)
				end
			end
			table.insert(parts, r.part)
			table.insert(cframes, CFrame.new(r.pos) * r.rot)
		elseif r.phase == "rest" and now >= r.restUntil then
			r.phase = "crumble"
			TweenService:Create(r.part, TweenInfo.new(CRUMBLE_SECONDS), { Size = r.part.Size * .2, Transparency = 1 }):Play()
			task.delay(CRUMBLE_SECONDS + .05, function() r.part:Destroy() end)
		end
	end
	if #parts > 0 then Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged) end
	if #rocks == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function spawnRock(centre, radius, params, roofY, sizeScale)
	if #rocks >= MAX_ROCKS then return end
	local angle, dist = math.random() * math.pi * 2, math.sqrt(math.random()) * radius
	local x, z = centre.X + math.cos(angle) * dist, centre.Z + math.sin(angle) * dist
	-- The roof right above THIS spot (it isn't flat everywhere); the arena-wide one is the fallback.
	local roofHit = Workspace:Raycast(Vector3.new(x, centre.Y + 4, z), Vector3.new(0, 250, 0), params)
	if roofHit then roofY = roofHit.Position.Y end
	local floorHit = Workspace:Raycast(Vector3.new(x, roofY - 1, z), Vector3.new(0, -300, 0), params)
	if not floorHit then return end
	local s = (SIZE_MIN + (SIZE_MAX - SIZE_MIN) * math.random() ^ 2) * (sizeScale or 1) -- mostly small, a few big
	local size = Vector3.new(s * (.7 + math.random() * .6), s * (.6 + math.random() * .5), s * (.7 + math.random() * .6))
	local p = Instance.new("Part")
	p.Name = "Rock"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = s > 1
	p.Material = Enum.Material.Slate
	p.Color = ROCK_COLORS[math.random(1, #ROCK_COLORS)]
	p.Size = size
	local rot = CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
	-- Half buried in the roof, so it visibly tears out of it.
	local pos = Vector3.new(x, roofY + size.Y * (EMBED - .5), z)
	p.CFrame = CFrame.new(pos) * rot
	p.Parent = folder
	table.insert(rocks, {
		part = p, pos = pos, rot = rot, vel = -math.random() * 3, half = size.Y * .5,
		floorY = floorHit.Position.Y, phase = "hang", bounced = false,
		dropAt = os.clock() + HANG_MIN + (HANG_MAX - HANG_MIN) * math.random(),
		spin = Vector3.new(math.random() * 8 - 4, math.random() * 8 - 4, math.random() * 8 - 4),
	})
	crack(Vector3.new(x, roofY - .3, z), s)
	if not loop then loop = RunService.RenderStepped:Connect(stepRocks) end
end

function Debris.Burst(centre, radius, count, parent, sizeScale)
	if typeof(centre) ~= "Vector3" then return end
	ensureFolder(parent)
	local params = rayParams()
	local roofY = ceilingY(centre, params)
	sizeScale = tonumber(sizeScale) or 1
	for _ = 1, math.max(0, math.floor(tonumber(count) or 20)) do
		spawnRock(centre, radius or 60, params, roofY, sizeScale)
	end
end

function Debris.Rain(centre, radius, duration, perSecond, parent)
	if typeof(centre) ~= "Vector3" then return end
	ensureFolder(parent)
	local params = rayParams()
	local roofY = ceilingY(centre, params)
	duration = math.max(0, tonumber(duration) or 2)
	perSecond = math.max(0, tonumber(perSecond) or 8)
	task.spawn(function()
		local started, owed = os.clock(), 0
		local last = started
		while os.clock() - started < duration do
			local now = os.clock()
			owed += (now - last) * perSecond
			last = now
			while owed >= 1 do
				owed -= 1
				spawnRock(centre, radius or 60, params, roofY)
			end
			task.wait(.05)
		end
	end)
end

return Debris
