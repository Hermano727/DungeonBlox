--[[
	PlayerKnockback -- the small hop + push a player gets when something hits them (server).

		PlayerKnockback.Push(character, fromPosition, multiplier?)

	Used by every mob hit (MobClass:ApplyPlayerHitstun, multiplier = MobData
	PlayerKnockbackMultiplier) and by PvP hits (MobCombat.ApplyPvPDamage,
	AlignmentConfig.PVP_KNOCKBACK_MULTIPLIER), so a sword from a player and a swing
	from a mob feel the same, just scaled.

	A one-time AssemblyLinearVelocity add does NOT work here: confirmed by direct testing
	that Roblox's player Humanoid controller zeroes it out the very next physics step. A
	BodyVelocity re-asserts the push every step for a short duration, which wins against
	that correction. Self-destructs via Debris so it never lingers.
]]

local Debris = game:GetService("Debris")

local PlayerKnockback = {}

PlayerKnockback.HORIZONTAL = 4 -- studs/s away from the hitter: the baseline (multiplier 1)
PlayerKnockback.VERTICAL = 8   -- studs/s upward: a small hop, just enough to interrupt movement
local DURATION = 0.15

function PlayerKnockback.Push(character, fromPosition, multiplier)
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or typeof(fromPosition) ~= "Vector3" then return end
	local mult = tonumber(multiplier) or 1
	if mult <= 0 then return end

	local horizontal = Vector3.new(hrp.Position.X - fromPosition.X, 0, hrp.Position.Z - fromPosition.Z)
	local dir = horizontal.Magnitude > 0.1 and horizontal.Unit or Vector3.new(0, 0, 1)

	-- HORIZONTAL ONLY. The vertical hop stays at the baseline however hard the hit:
	-- scaling it too launched the player high enough to read as floaty, and a big pop can
	-- lift them past the melee vertical reach so the later impacts of a combo whiff
	-- entirely. A heavy hit should send you further back, not further up.
	local bv = Instance.new("BodyVelocity")
	bv.Velocity = Vector3.new(
		dir.X * PlayerKnockback.HORIZONTAL * mult,
		PlayerKnockback.VERTICAL,
		dir.Z * PlayerKnockback.HORIZONTAL * mult
	)
	-- Only the horizontal budget scales with it, for the same reason. (The vertical 4000
	-- is mostly spent holding the character's weight against gravity anyway, which is why
	-- the baseline hop is as small as it is.)
	local force = 4000 * math.max(1, mult)
	bv.MaxForce = Vector3.new(force, 4000, force)
	bv.P = 1250
	bv.Parent = hrp
	Debris:AddItem(bv, DURATION)
end

return PlayerKnockback
