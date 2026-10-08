--[[
	BowConfig
	The bow, Minecraft style: hold to draw, release to shoot. A fuller draw shoots faster,
	flatter and harder. Gameplay numbers are read by the server (SSS/BowService), the feel
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
BowConfig.DAMAGE_SCALE_MIN = 0.15    -- damage multiplier at MIN_CHARGE, rising to 1 at full draw
BowConfig.AUDIENCE_RADIUS = 300      -- clients this close to the shooter draw the arrow's flight

-- Charge (0..1) -> launch speed and damage multiplier. One curve for both sides.
function BowConfig.Speed(charge)
	local u = math.clamp((charge - BowConfig.MIN_CHARGE) / (1 - BowConfig.MIN_CHARGE), 0, 1)
	return BowConfig.SPEED_MIN + (BowConfig.SPEED_MAX - BowConfig.SPEED_MIN) * u
end

function BowConfig.DamageScale(charge)
	local u = math.clamp((charge - BowConfig.MIN_CHARGE) / (1 - BowConfig.MIN_CHARGE), 0, 1)
	return BowConfig.DAMAGE_SCALE_MIN + (1 - BowConfig.DAMAGE_SCALE_MIN) * u * u
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

return BowConfig
