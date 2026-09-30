--[[
	EnchantSlowMarkers

	A ring of short white dashes on the ground under anything currently slowed,
	for as long as it stays slowed. Deliberately NOT a trail: a trail reads as
	"this thing is moving fast", which is the opposite of what a slow means.

	Driven entirely by the CollectionService tag CombatEnchantStatus writes on
	the server (the same place the attribute is set/cleared, so the marker can
	never outlive the status). Tags replicate, so this needs no remote of its
	own and every client sees every slowed target.

	Separate from EnchantHitEffects because that module is one-shot: a hit plays
	a 0.25-0.85s clip and disposes itself. These live exactly as long as a status
	that has no fixed duration from the client's point of view.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SLOW_TAG = "EnchantSlowed"
local DASH_COUNT = 5
local DASH_COLOR = Color3.fromRGB(236, 246, 255)
local MAX_DISTANCE = 120 -- studs; matches EnchantHitEffectConfig's cull
local SPIN_SPEED = 0.55  -- radians/sec, slow enough to read as "dragging"

local marked = {}
local connection
local folder
local update -- forward-declared: attach() starts the render loop with it

local function markerRoot(model)
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

-- Ground level under the model, and a radius that fits its footprint.
local function footPlane(model, root)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local drop = root.Size.Y * 0.5 + (humanoid and humanoid.HipHeight or 0)
	local _, size = model:GetBoundingBox()
	local radius = math.clamp(math.max(size.X, size.Z) * 0.55, 1.1, 4)
	return root.Position - Vector3.new(0, drop - 0.05, 0), radius
end

local function attach(model)
	if marked[model] or not model:IsA("Model") then return end
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "LocalEnchantSlowMarkers"
		folder.Parent = Workspace
	end

	local group = Instance.new("Model")
	group.Name = "SlowMarker"
	group.Parent = folder

	local dashes = {}
	for i = 1, DASH_COUNT do
		local dash = Instance.new("Part")
		dash.Name = "SlowDash"
		dash.Anchored = true
		dash.CanCollide = false
		dash.CanTouch = false
		dash.CanQuery = false
		dash.CastShadow = false
		dash.Material = Enum.Material.Neon
		dash.Color = DASH_COLOR
		dash.Transparency = 1
		dash.Parent = group
		dashes[i] = dash
	end

	marked[model] = { group = group, dashes = dashes, started = os.clock() }
	if not connection then
		connection = RunService.RenderStepped:Connect(update)
	end
end

local function detach(model)
	local entry = marked[model]
	if not entry then return end
	marked[model] = nil
	entry.group:Destroy()
	if not next(marked) and connection then
		connection:Disconnect()
		connection = nil
	end
end

update = function()
	local camera = Workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	local now = os.clock()
	for model, entry in pairs(marked) do
		local root = model.Parent and markerRoot(model)
		if not root then
			detach(model)
			continue
		end
		local centre, radius = footPlane(model, root)
		-- Fade in over the first fifth of a second rather than popping, and cull
		-- by distance so a fight across the map costs nothing to draw.
		local visible = not eye or (eye - centre).Magnitude <= MAX_DISTANCE
		local alpha = visible and (0.25 + 0.12 * math.sin(now * 3)) or 1
		alpha = math.max(alpha, 1 - math.clamp((now - entry.started) / 0.2, 0, 1))
		local spin = now * SPIN_SPEED
		for i, dash in ipairs(entry.dashes) do
			local angle = spin + (i - 1) * (math.pi * 2 / DASH_COUNT)
			local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			-- Flat on the ground, pointing along the ring (tangential), so the
			-- dashes read as marks scraped into the floor rather than spokes.
			dash.Size = Vector3.new(0.12, 0.06, radius * 0.55)
			dash.CFrame = CFrame.lookAt(centre + offset, centre + offset + Vector3.new(-math.sin(angle), 0, math.cos(angle)))
			dash.Transparency = alpha
		end
	end
end

for _, model in ipairs(CollectionService:GetTagged(SLOW_TAG)) do
	attach(model)
end
CollectionService:GetInstanceAddedSignal(SLOW_TAG):Connect(attach)
CollectionService:GetInstanceRemovedSignal(SLOW_TAG):Connect(detach)

print("[EnchantSlowMarkers] ready")
