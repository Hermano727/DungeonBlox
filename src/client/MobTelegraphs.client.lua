--[[
	MobTelegraphs

	Draws the ground shape a mob is about to hit, during its windup.

	Two layers, because a single element does not read as both "the danger zone"
	and "it lands NOW":

	  OUTLINE  the full hit area, dim, held for the whole windup. Answers
	           "where do I need to not be standing".
	  SWEEP    a brighter arc that expands from the mob out to the outline,
	           arriving exactly on the impact. Answers "when". It replays once
	           per impact, so Kane's three-hit combo reads as three distinct
	           beats rather than one long fill.

	Plus a one-frame flash on impact so a connecting hit and a whiffed one still
	feel different even when the damage number is off-screen.

	Driven entirely by the CollectionService tag MobTelegraph writes on the
	server, so it needs no remote and cannot outlive the attack. The timing comes
	from a synced server timestamp plus the same hit offsets the damage uses,
	which means a client that joins mid-windup renders the correct REMAINING time
	instead of restarting the sweep.

	Procedural neon parts rather than particles or a decal, matching
	EnchantHitEffects/EnchantSlowMarkers. A flat projected decal was the obvious
	alternative and was rejected: this game is played on rolling terrain, where a
	large flat projection visibly clips through hillsides.

	Segments sit on a single flat plane at the mob's feet, so they do NOT follow
	ground contour. That is why the style is a low raised BAND (Height/Lift in
	MobTelegraphConfig) instead of a floor marking -- it stands proud of about a
	stud of terrain rise before any of it is buried. The first version was 0.08
	studs tall on the foot plane exactly, and on T1's rolling ground it was
	invisible: drawing correctly, just underneath the hill. If steeper terrain
	ever eats it again, the real fix is raycasting each segment down individually
	rather than growing the band further.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("MobTelegraphConfig"))

local ATTR = Config.ATTR
local MAX_DISTANCE = 160 -- studs; a little past EnchantSlowMarkers' 120, since a
                         -- telegraph you cannot see is a telegraph you cannot dodge
local FLASH_TIME = 0.12
local MIN_SWEEP_RADIUS = 0.6 -- keeps the sweep from collapsing into z-fighting at t=0
-- At full progress the sweep lands on the outline's own radius, and two neon
-- parts sharing a plane flicker. A fixed hair of separation, NOT a fraction of
-- the band height -- the band is over a stud tall now, so offsetting by its
-- height would float the sweep clean off the outline instead of just nudging it.
local SWEEP_Z_OFFSET = 0.06

local active = {}    -- model -> render state
local watchers = {}  -- model -> TelegraphStart listener
local connection
local folder
local update -- forward-declared: build() starts the render loop with it

local function markerRoot(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

-- Ground level under the model. Same derivation EnchantSlowMarkers uses.
local function footPlane(model, root)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local drop = root.Size.Y * 0.5 + (humanoid and humanoid.HipHeight or 0)
	return root.Position - Vector3.new(0, drop - 0.05, 0)
end

local function newSegment(parent, style)
	local part = Instance.new("Part")
	part.Name = "TelegraphSegment"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = style.Color
	part.Transparency = 1
	part.Size = Vector3.new(style.Thickness, style.Height, 1)
	part.Parent = parent
	return part
end

local function readState(model)
	local hits = Config.DecodeHits(model:GetAttribute(ATTR.Hits))
	if #hits == 0 then return nil end
	return {
		kind = model:GetAttribute(ATTR.Kind),
		style = Config.Get(model:GetAttribute(ATTR.Kind)),
		start = tonumber(model:GetAttribute(ATTR.Start)) or Workspace:GetServerTimeNow(),
		hits = hits,
		radius = math.max(0.5, tonumber(model:GetAttribute(ATTR.Radius)) or 0),
		halfAngle = math.rad(math.clamp(tonumber(model:GetAttribute(ATTR.HalfAngle)) or 0, 0, 180)),
	}
end

local function clearVisual(model)
	local entry = active[model]
	if not entry then return end
	active[model] = nil
	entry.group:Destroy()
	if not next(active) and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function detach(model)
	clearVisual(model)
	local watcher = watchers[model]
	if watcher then
		watcher:Disconnect()
		watchers[model] = nil
	end
end

local function build(model)
	local state = readState(model)
	if not state then
		clearVisual(model)
		return
	end

	-- One Begin writes several attributes, so the watcher above can fire more
	-- than once for the same telegraph. Same kind at the same timestamp means
	-- nothing actually changed -- bail rather than tearing down and rebuilding
	-- ~44 parts a second time in the same frame.
	local existing = active[model]
	if existing and existing.start == state.start and existing.kind == state.kind then
		return
	end

	-- Otherwise always rebuild rather than reusing: segment COUNT is
	-- style-dependent and Kane's two attacks differ, so a combo starting over a
	-- lingering ordinary swing would render with the wrong segment count.
	clearVisual(model)

	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "LocalMobTelegraphs"
		folder.Parent = Workspace
	end

	local group = Instance.new("Model")
	group.Name = "MobTelegraph"
	group.Parent = folder

	local outline, sweep = {}, {}
	for i = 1, state.style.Segments do
		outline[i] = newSegment(group, state.style)
		sweep[i] = newSegment(group, state.style)
		sweep[i].Color = state.style.Accent
	end

	state.group = group
	state.outline = outline
	state.sweep = sweep
	active[model] = state

	if Config.DEBUG then
		print(string.format("[MobTelegraphs] built %s on %s -- radius %.1f, half-angle %.0f, %d hit(s)",
			tostring(state.kind), model.Name, state.radius, math.deg(state.halfAngle), #state.hits))
	end

	if not connection then
		connection = RunService.RenderStepped:Connect(update)
	end
end

-- Two separate reasons this watches attributes rather than trusting the tag:
--
--  1. CollectionService:AddTag on an ALREADY-tagged instance does not re-fire
--     GetInstanceAddedSignal, so a second attack starting while the previous
--     mark still lingers would keep rendering the old timing.
--  2. The tag and the attributes replicate INDEPENDENTLY. GetInstanceAddedSignal
--     can land before the attributes do, and the attributes can land in any
--     order among themselves -- so a build attempt can legitimately find Hits
--     missing and has to be retried when it arrives, not written off.
--
-- Hence AttributeChanged (any attribute) rather than a signal on one name:
-- whichever of Start/Hits arrives last is what triggers the real build.
local REBUILD_ON = { [ATTR.Start] = true, [ATTR.Hits] = true }

local function attach(model)
	if not model:IsA("Model") or watchers[model] then return end
	watchers[model] = model.AttributeChanged:Connect(function(name)
		if REBUILD_ON[name] then
			build(model)
		end
	end)
	build(model)
end

--[[
	The BOUNDARY of the attack's real hit test, as an ordered world-space
	polyline. This is what makes the mark an outline of the hitbox rather than a
	decorative ring.

	Both server-side tests are centred on the mob's ROOT and are horizontal-only:

	  ordinary swing  IsTargetWithinMeleeReach -- a plain distance check, so the
	                  hit area is a full DISC and its boundary is a circle.
	  a moveset entry IsTargetWithinMovesetReach -- the same disc, intersected
	                  with a frontal cone, so the hit area is a pie SECTOR and its
	                  boundary is apex -> straight edge -> arc -> straight edge.

	Drawing only the far arc for the sector was wrong: it read as a band floating
	in front of the mob with no stated relationship to him, and said nothing about
	where the dangerous region begins. The two straight edges are the part that
	actually communicates "step outside these and the swing misses".
]]
local ARC_STEPS = 26 -- polyline resolution of the curved part

local function boundaryPoints(centre, forward, radius, halfAngle)
	local base = math.atan2(forward.X, forward.Z)
	local points = {}
	local function at(angle)
		return centre + Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
	end

	if halfAngle <= 0 then
		-- Closed circle: the last point repeats the first so the loop joins up.
		for i = 0, ARC_STEPS do
			table.insert(points, at(base + (math.pi * 2) * (i / ARC_STEPS)))
		end
		return points
	end

	table.insert(points, centre) -- apex, where both straight edges meet
	for i = 0, ARC_STEPS do
		table.insert(points, at(base - halfAngle + (halfAngle * 2) * (i / ARC_STEPS)))
	end
	table.insert(points, centre)
	return points
end

-- Resamples a polyline into `n + 1` points spaced evenly by ARC LENGTH, so a
-- sector's straight edges and its arc get segment density in proportion to how
-- long they actually are -- rather than the edges being drawn with the same
-- number of pieces as a curve several times their length.
local function samplePath(points, n)
	local lengths, total = {}, 0
	for i = 1, #points - 1 do
		lengths[i] = (points[i + 1] - points[i]).Magnitude
		total += lengths[i]
	end
	if total <= 1e-4 then return nil end

	local out = { points[1] }
	local step = total / n
	local index, consumed = 1, 0
	for k = 1, n do
		local target = step * k
		while index < #points - 1 and consumed + lengths[index] < target do
			consumed += lengths[index]
			index += 1
		end
		local span = lengths[index]
		local t = (span > 1e-6) and math.clamp((target - consumed) / span, 0, 1) or 0
		out[k + 1] = points[index]:Lerp(points[index + 1], t)
	end
	return out
end

-- Lays the segment pool end-to-end along a boundary polyline.
local function placeBoundary(segments, centre, forward, radius, halfAngle, alpha, style)
	local samples = samplePath(boundaryPoints(centre, forward, radius, halfAngle), #segments)
	if not samples then
		for _, part in ipairs(segments) do part.Transparency = 1 end
		return
	end
	for i, part in ipairs(segments) do
		local a, b = samples[i], samples[i + 1]
		local delta = b - a
		local length = delta.Magnitude
		if length < 1e-3 then
			part.Transparency = 1
		else
			local mid = a + delta * 0.5
			part.Size = Vector3.new(style.Thickness, style.Height, length)
			part.CFrame = CFrame.lookAt(mid, mid + delta.Unit)
			part.Transparency = alpha
		end
	end
end

local function hideArc(segments)
	for _, part in ipairs(segments) do
		part.Transparency = 1
	end
end

update = function()
	local camera = Workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	local now = Workspace:GetServerTimeNow()

	for model, state in pairs(active) do
		local root = model.Parent and markerRoot(model)
		if not root then
			-- clearVisual, not detach: the root can go missing transiently, and
			-- dropping the TelegraphStart watcher here would leave this mob
			-- permanently unable to render another telegraph. A destroyed model
			-- fires the tag-removed signal, which is what really detaches.
			clearVisual(model)
			continue
		end

		local style = state.style
		local elapsed = now - state.start
		local hits = state.hits
		local last = hits[#hits]

		-- Self-expire rather than relying on the server's clear landing. A
		-- dropped tag removal should never leave a mark painted on the world.
		if elapsed > last + style.Tail then
			hideArc(state.outline)
			hideArc(state.sweep)
			continue
		end

		-- Lift raises the whole mark off the foot plane. Zero for the shipped
		-- look; DEBUG floats it to chest height so terrain cannot bury it.
		local centre = footPlane(model, root) + Vector3.new(0, style.Lift or 0, 0)
		if eye and (eye - centre).Magnitude > MAX_DISTANCE then
			hideArc(state.outline)
			hideArc(state.sweep)
			continue
		end

		local look = root.CFrame.LookVector
		local forward = Vector3.new(look.X, 0, look.Z)
		forward = (forward.Magnitude > 0.01) and forward.Unit or Vector3.new(0, 0, 1)

		-- Which impact is the sweep currently counting down to, and how far
		-- through that beat are we? Each impact restarts the expansion from the
		-- previous one, so N impacts read as N separate sweeps.
		local index, windowStart = #hits, hits[#hits - 1] or 0
		for i = 1, #hits do
			if elapsed < hits[i] then
				index = i
				windowStart = hits[i - 1] or 0
				break
			end
		end
		local target = hits[index]
		local span = math.max(0.05, target - windowStart)
		local progress = math.clamp((elapsed - windowStart) / span, 0, 1)

		-- Impact flash: how recently did ANY hit land.
		local flash = 0
		for _, hitTime in ipairs(hits) do
			local since = elapsed - hitTime
			if since >= 0 and since < FLASH_TIME then
				flash = math.max(flash, 1 - since / FLASH_TIME)
			end
		end

		-- Past the last impact the mark fades across its Tail instead of simply
		-- vanishing. Matters most on a SHORT telegraph: Kane's ordinary swing is
		-- only ~0.4s of windup, and popping out of existence the instant it
		-- connects made it read as a glitch rather than as a swing resolving.
		local overrun = elapsed - last
		local tailFade = (overrun > 0) and math.clamp(overrun / math.max(0.01, style.Tail), 0, 1) or 0
		local function faded(alpha)
			return math.clamp(alpha + (1 - alpha) * tailFade, 0, 1)
		end

		-- Outline tightens up as the impact nears rather than sitting flat, so
		-- the danger zone itself reads as "charging".
		local outlineAlpha = style.OutlineAlpha * (1 - 0.55 * progress)
		placeBoundary(state.outline, centre, forward, state.radius, state.halfAngle,
			faded(math.clamp(outlineAlpha - flash * 0.5, 0, 1)), style)

		if elapsed >= 0 then
			local sweepRadius = MIN_SWEEP_RADIUS + (state.radius - MIN_SWEEP_RADIUS) * progress
			-- Same shape, smaller: a growing sector rather than a growing ring, so
			-- the fill and the boundary always agree on what the hit area is.
			placeBoundary(state.sweep, centre + Vector3.new(0, SWEEP_Z_OFFSET, 0), forward, sweepRadius,
				state.halfAngle, faded(math.clamp(style.SweepAlpha - flash * 0.15, 0, 1)), style)
			for _, part in ipairs(state.sweep) do
				part.Color = (flash > 0) and style.Flash or style.Accent
			end
		else
			hideArc(state.sweep)
		end
	end
end

for _, model in ipairs(CollectionService:GetTagged(Config.TAG)) do
	attach(model)
end
CollectionService:GetInstanceAddedSignal(Config.TAG):Connect(attach)
CollectionService:GetInstanceRemovedSignal(Config.TAG):Connect(detach)

print("[MobTelegraphs] ready")
