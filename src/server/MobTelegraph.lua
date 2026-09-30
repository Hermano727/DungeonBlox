--[[
	MobTelegraph -- ServerScriptService

	Publishes "this mob is winding up, here is what it is about to hit" as a
	CollectionService tag plus attributes on the mob model. Draws nothing itself
	-- client/MobTelegraphs.client.lua does that.

	Why a tag and not a remote: tags and attributes replicate on their own, so
	every client sees every telegraph with no per-player fan-out, and the marker
	can never outlive the state because it is written and cleared in the same
	places the attack starts and ends. Same reasoning as CombatEnchantStatus's
	slow tag.

	Why a server TIMESTAMP rather than a duration: `Start` is
	Workspace:GetServerTimeNow(), which is clock-synced across server and
	clients, and the hit offsets are relative to it. A client that joins or
	un-freezes mid-windup therefore renders the correct remaining time instead of
	restarting the sweep, and no further traffic is needed after the initial
	attribute write.

	The caller passes the hit offsets it is ALREADY using to deal damage, so the
	sweep cannot drift out of sync with the swing. See MobTelegraphConfig.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("MobTelegraphConfig"))

local MobTelegraph = {}

local ATTR = Config.ATTR

--[[
	Begin(mob, kind, hitOffsets, radius, halfAngleDegrees)

	  kind         style key in MobTelegraphConfig.Styles; nil = no telegraph
	  hitOffsets   array of REAL seconds from now, one per impact
	  radius       studs, should be the same reach the damage test uses
	  halfAngle    degrees, or nil for a full ring

	A no-op unless the attack actually opted in, which is what keeps every
	non-telegraphing mob untouched.
]]
function MobTelegraph.Begin(mob, kind, hitOffsets, radius, halfAngleDegrees)
	if type(kind) ~= "string" or kind == "" then return end
	local model = mob and mob.Model
	if not model or not model.Parent then return end
	if type(hitOffsets) ~= "table" or #hitOffsets == 0 then return end

	radius = tonumber(radius) or 0
	if radius <= 0 then return end

	model:SetAttribute(ATTR.Kind, kind)
	model:SetAttribute(ATTR.Hits, Config.EncodeHits(hitOffsets))
	model:SetAttribute(ATTR.Radius, radius)
	model:SetAttribute(ATTR.HalfAngle, tonumber(halfAngleDegrees) or 0)
	-- Written LAST: the client keys its render loop off Start changing, so every
	-- other attribute is already in place by the time it reacts.
	model:SetAttribute(ATTR.Start, Workspace:GetServerTimeNow())
	CollectionService:AddTag(model, Config.TAG)

	if Config.DEBUG then
		print(string.format("[MobTelegraph] Begin %s on %s -- radius %.1f, half-angle %s, hits %s",
			kind, model.Name, radius, tostring(halfAngleDegrees or 0), Config.EncodeHits(hitOffsets)))
	end
end

-- Safe to call when no telegraph is active, and on a destroyed model.
function MobTelegraph.Clear(mob)
	local model = mob and mob.Model
	if not model or not model.Parent then return end
	if not CollectionService:HasTag(model, Config.TAG) then return end
	CollectionService:RemoveTag(model, Config.TAG)
	model:SetAttribute(ATTR.Kind, nil)
	model:SetAttribute(ATTR.Start, nil)
	model:SetAttribute(ATTR.Hits, nil)
	model:SetAttribute(ATTR.Radius, nil)
	model:SetAttribute(ATTR.HalfAngle, nil)
end

-- Clears after `seconds`, unless a NEWER telegraph has started in the meantime.
-- The Start timestamp is the generation token: a second attack that begins
-- before this fires moves it, and the stale timer then leaves the new mark
-- alone rather than wiping it early.
function MobTelegraph.ClearAfter(mob, seconds)
	local model = mob and mob.Model
	if not model then return end
	local startedAt = model:GetAttribute(ATTR.Start)
	task.delay(math.max(0, seconds), function()
		if not mob.Model or mob.Model ~= model then return end
		if model:GetAttribute(ATTR.Start) ~= startedAt then return end
		MobTelegraph.Clear(mob)
	end)
end

-- The reach the melee test will actually use, so the drawn shape is the real
-- hitbox rather than a decorative ring. Mirrors MobClass:IsTargetWithinMeleeReach.
function MobTelegraph.ReachFor(mob, rangeMultiplier)
	local stats = mob and mob.Stats
	if not stats then return 0 end
	local base = (tonumber(stats.AttackRange) or 0) + (mob.GetHitRadius and mob:GetHitRadius() or 0)
	return base * (tonumber(rangeMultiplier) or 1)
end

return MobTelegraph
