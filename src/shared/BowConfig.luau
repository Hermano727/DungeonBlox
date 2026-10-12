--[[
	BowConfig
	The bow, Minecraft style: hold to draw, release to shoot. A fuller draw shoots faster and
	flatter; damage is the same at any draw. Gameplay numbers are read by the server (SSS/BowService), the feel
	numbers by the shooter's client (BowController), the geometry by every client
	(WeaponAttachClient draws the bow in the left hand, its string and the nocked arrow).

	Geometry comes from Blender (assets/models/armor weapons equipment/T1_Bow, T1_Bow.json and
	animation/T1_Bow.anim.json); re-run author_bow.py and copy the numbers if the clips change.
]]

local BowConfig = {}

-- Tool WeaponIds that are bows. The tool's Handle is the bow mesh.
BowConfig.WEAPON_IDS = { WoodenBow = true }

function BowConfig.IsBow(tool)
	return tool ~= nil and BowConfig.WEAPON_IDS[tool:GetAttribute("WeaponId")] == true
end

---------------------------------------------------------------------------
-- Gameplay (server)
---------------------------------------------------------------------------
BowConfig.CHARGE_TIME = 1.0          -- seconds from draw start to full draw
BowConfig.MIN_CHARGE = 0.12          -- below this the release is a cancel, not a shot
BowConfig.REFIRE_DELAY = 0.2         -- after a shot, before the next draw may start
BowConfig.SPEED_MIN = 55             -- studs/s at MIN_CHARGE
BowConfig.SPEED_MAX = 190            -- studs/s at full draw
BowConfig.GRAVITY = 30               -- studs/s^2 of arrow drop
-- The server times the draw between two packet arrivals, so network jitter can shave a
-- little off a draw the shooter held to full. This much extra hold time is credited.
BowConfig.RELEASE_GRACE = 0.08
BowConfig.AUDIENCE_RADIUS = 300      -- clients this close to the shooter draw the arrow's flight
-- Arrows hit a mob or player this close to their line (studs). Walls and ground still use
-- the thin line, so arrows don't snag on corners.
BowConfig.HIT_RADIUS = 0.7

-- Charge (0..1) -> launch speed. Damage is the bow's full roll at any draw.
function BowConfig.Speed(charge)
	local u = math.clamp((charge - BowConfig.MIN_CHARGE) / (1 - BowConfig.MIN_CHARGE), 0, 1)
	return BowConfig.SPEED_MIN + (BowConfig.SPEED_MAX - BowConfig.SPEED_MIN) * u
end

---------------------------------------------------------------------------
-- Arrow hits (server and every client fly the same arrow)
---------------------------------------------------------------------------
local function isCreature(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") or model:GetAttribute("MobUID") then return true end
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
	return false
end

-- One flight step: a thin ray for the world, a HIT_RADIUS sphere for creatures, nearest wins.
function BowConfig.CastArrow(origin, step, params)
	local ray = workspace:Raycast(origin, step, params)
	if step.Magnitude <= 0 then return ray end
	local sphere = workspace:Spherecast(origin, BowConfig.HIT_RADIUS, step, params)
	if sphere and isCreature(sphere.Instance) and (not ray or sphere.Distance < ray.Distance) then
		return sphere
	end
	return ray
end

---------------------------------------------------------------------------
-- Feel (shooter's client)
---------------------------------------------------------------------------
BowConfig.FULL_DRAW_FOV_DELTA = -9   -- camera zooms in by this much at full draw
BowConfig.FOV_RETURN_TIME = 0.15
BowConfig.ANIMATION_FADE = 0.12

---------------------------------------------------------------------------
-- Geometry (every client)
---------------------------------------------------------------------------
-- The bow Handle's CFrame relative to Hand_L (bone.TransformedWorldCFrame * BOW_GRIP).
BowConfig.BOW_GRIP = CFrame.new(-0.021893, 0.296303, 0.166666,
	0.665272, -0.745212, 0.04551,
	0.602627, 0.5, -0.621964,
	0.440741, 0.441201, 0.781721)
-- Where the string sits in the hooked right fingers, Hand_R space.
BowConfig.NOCK_HAND = Vector3.new(-0.037708, 0.41916, 0.115431)
-- Handle space (+Y up, +Z toward the string): the string's ends, and the point the nocked
-- arrow passes over. Roblox imports the mesh as Blender (-x, z, y); see build_bow.py.
BowConfig.NOCK_TOP = Vector3.new(-0.0028, 1.5129, 0.2669)
BowConfig.NOCK_BOTTOM = Vector3.new(-0.0028, -1.4871, 0.2669)
BowConfig.ARROW_REST = Vector3.new(-0.0528, 0.032, -0.0794)
BowConfig.ARROW_LENGTH = 2.4
-- Draw clip time (seconds of clip, at speed 1) when the right hand takes the string.
BowConfig.NOCK_TIME = 0.22

BowConfig.STRING_COLOR = Color3.fromRGB(226, 216, 196)
BowConfig.STRING_WIDTH = 0.025

-- Shared folder the server fills with the arrow template (ServerStorage.WeaponModels.Bow.T1_Arrow).
BowConfig.VISUALS_FOLDER = "BowVisuals"
BowConfig.ARROW_TEMPLATE = "T1_Arrow"

-- Arrows in flight (BowController): drawn this much bigger than the nocked one, with a
-- pale gold glow and streak (Minecraft's spectral arrow) so everyone sees where they go.
BowConfig.FLIGHT_ARROW_SCALE = 2
BowConfig.ARROW_GLOW_COLOR = Color3.fromRGB(255, 240, 190)
BowConfig.ARROW_GLOW_OUTLINE = Color3.fromRGB(255, 252, 235)
BowConfig.ARROW_GLOW_FILL_TRANSPARENCY = 0.45
BowConfig.ARROW_TRAIL_LIFETIME = 0.18
BowConfig.ARROW_TRAIL_WIDTH = 0.18

return BowConfig
