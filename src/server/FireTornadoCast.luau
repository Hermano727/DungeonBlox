--[[
	FireTornadoCast -- ServerScriptService

	The server half of Kane's Fire Tornado (timeline and path: RS/FireTornadoConfig, visuals:
	client/FireTornadoVFX). A Moveset CAST handler, driven by MobMovesetBehaviour for an entry with
	`Cast = "FireTornado"`:

		Begin(mob, entry)     -> state   the channel starts: plays the slam clip, tells every client
		Update(mob, state)    -> bool    true once the slam has played out (the special is over)
		Finish(mob, state)               ended early (death, despawn) before the impact: cancel
		Duration(entry)       -> number  seconds the mob is committed (channel + slam recovery)
		Showcase(model, mobId, entry, trackFor) -> seconds   the dev showcase: everything but damage

	The mob stands still for the channel and the slam's recovery. At the impact (WINDUP seconds in):
	  - SLAM: anyone within SLAM_RADIUS of the impact point takes `entry.SlamDamage` once and is
	    knocked back (`entry.SlamKnockback`).
	  - TORNADOES: independent hazards on this module's own Heartbeat; the mob fights on while they
	    travel and they finish their path even if it dies. Every TickInterval seconds, anyone within
	    HIT_RADIUS of any of the cast's tornadoes takes `entry.Damage` (one tick per player per cast,
	    however many tornadoes overlap them).
	All damage goes through DamageService like any mob hit.

	Sounds: the slam's downswing whoosh (MobCombatSfx, Kane's CombatSounds) and TICK_SOUND at a
	player each time a tornado tick lands on them. The drag toward the tornadoes is client-side
	(each player's own character), see FireTornadoVFX.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("FireTornadoConfig"))
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local MobAnimController = require(ServerScriptService:WaitForChild("MobAnimController"))
local MobCombatSfx = require(ServerScriptService:WaitForChild("MobCombatSfx"))
local MobAnimConfig = require(ReplicatedStorage:WaitForChild("MobAnimConfig"))
local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local CastEvent = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("FireTornadoCast")

local FireTornadoCast = {}

local nextId = 0
local hazards = {} -- live released casts
local heartbeat = nil

-- Living players whose root is inside the hit band: within `radius` (flat) of `point`, and between
-- HIT_BELOW under and HIT_ABOVE over the cast's ground height.
local function playersNear(point, groundY, radius)
	local found = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local dy = root.Position.Y - groundY
			local flat = Vector3.new(root.Position.X - point.X, 0, root.Position.Z - point.Z)
			if dy >= -Config.HIT_BELOW and dy <= Config.HIT_ABOVE and flat.Magnitude <= radius then
				table.insert(found, player)
			end
		end
	end
	return found
end

local function stepHazards()
	local now = Workspace:GetServerTimeNow()
	for i = #hazards, 1, -1 do
		local cast = hazards[i]
		local t = now - cast.releaseAt
		if t > Config.TRAVEL then
			table.remove(hazards, i)
		elseif t >= Config.DAMAGE_DELAY then
			local hit = {}
			for index = 0, Config.COUNT - 1 do
				local point = Config.PathPoint(cast.origin, cast.angle, index, t)
				for _, player in ipairs(playersNear(point, cast.origin.Y, Config.HIT_RADIUS)) do
					hit[player] = true
				end
			end
			for player in pairs(hit) do
				if now >= (cast.nextTick[player] or 0) then
					cast.nextTick[player] = now + cast.tickInterval
					local dealt = DamageService.ApplyToPlayer(player, cast.damage, cast.mob)
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if dealt and dealt > 0 and root then
						DamageService.PlayEffectAt(Config.TICK_SOUND, root.Position, 120)
					end
				end
			end
		end
	end
	if #hazards == 0 and heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

local function slam(state)
	local mob = state.mob
	for _, player in ipairs(playersNear(state.impact, state.origin.Y, Config.SLAM_RADIUS)) do
		local character = player.Character
		DamageService.ApplyToPlayer(player, state.slamDamage, mob)
		if character and mob.Model then
			mob:ApplyPlayerHitstun(character, state.slamKnockback)
		end
	end
end

function FireTornadoCast.Duration(_entry)
	return Config.WINDUP + Config.RECOVERY
end

-- Where a cast by `model` happens: the ground under it (the bottom of its bounding box: no raycast,
-- so the hazard and the visuals share one height even on a slope; HIT_BELOW absorbs small
-- differences), the axe's impact point just in front of it, and its facing as an XZ angle.
local function castGeometry(model, root)
	local boxCFrame, boxSize = model:GetBoundingBox()
	local origin = Vector3.new(root.Position.X, boxCFrame.Position.Y - boxSize.Y / 2, root.Position.Z)
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = flatLook.Magnitude > 0.01 and flatLook.Unit or Vector3.new(0, 0, -1)
	return origin, origin + flatLook * Config.IMPACT_FORWARD, math.atan2(look.Z, look.X)
end

-- Tells every client to draw a cast (it all runs off this one message and the server clock).
local function announce(model, origin, impact, angle, now)
	nextId += 1
	CastEvent:FireAllClients("begin", {
		id = nextId,
		caster = model,
		origin = origin,
		impact = impact,
		angle = angle,
		startAt = now,
	})
	return nextId
end

function FireTornadoCast.Begin(mob, entry)
	local model = mob.Model
	local root = model and model.PrimaryPart
	if not root then return nil end
	local origin, impact, angle = castGeometry(model, root)
	local now = Workspace:GetServerTimeNow()

	-- The slam clip, timed so the axe lands on WINDUP. No clip loaded (yet): the cast still runs,
	-- the caster just stands there.
	local track = entry.Animation and MobAnimController.playMoveset(mob, entry.Animation, Config.SLAM_SPEED)

	local state = {
		mob = mob,
		track = track,
		origin = origin,
		impact = impact,
		angle = angle,
		releaseAt = now + Config.WINDUP,
		endAt = now + Config.WINDUP + Config.RECOVERY,
		damage = tonumber(entry.Damage) or mob.Stats.BaseDamage,
		tickInterval = tonumber(entry.TickInterval) or Config.TICK_INTERVAL_DEFAULT,
		slamDamage = tonumber(entry.SlamDamage) or mob.Stats.BaseDamage,
		slamKnockback = tonumber(entry.SlamKnockback) or Config.SLAM_KNOCKBACK_DEFAULT,
		nextTick = {},
		released = false,
	}
	-- the axe's downswing whoosh, ahead of the impact (silent if the cast is cancelled first)
	MobCombatSfx.SwingIn(mob, Config.WINDUP, function()
		return not state.cancelled
	end)
	state.id = announce(model, origin, impact, angle, now)
	return state
end

-- The dev animation showcase (SSS/AnimationShowcase): the whole cast on a display model, visuals,
-- slam clip and sounds, with NO damage and no hazards. `trackFor(assetId)` loads a clip on the
-- display model's Animator. Returns how long to wait before playing it again.
function FireTornadoCast.Showcase(model, mobId, entry, trackFor)
	local root = model.PrimaryPart
	if not root then return 5 end
	local origin, impact, angle = castGeometry(model, root)
	local clips = MobAnimConfig[mobId] and MobAnimConfig[mobId].Moveset
	local animId = entry.Animation and clips and clips[entry.Animation]
	if animId then
		local track = trackFor(animId)
		track:Play(0.1)
		track:AdjustSpeed(Config.SLAM_SPEED)
	end
	-- MobCombatSfx only needs Model, Stats and IsAlive from a mob.
	local display = { Model = model, Stats = MobData.FindMobById(mobId), IsAlive = function() return model.Parent ~= nil end }
	MobCombatSfx.SwingIn(display, Config.WINDUP)
	announce(model, origin, impact, angle, Workspace:GetServerTimeNow())
	return Config.WINDUP + Config.TRAVEL + Config.COLLAPSE + 1.5
end

function FireTornadoCast.Update(_mob, state)
	local now = Workspace:GetServerTimeNow()
	if not state.released and now >= state.releaseAt then
		state.released = true
		slam(state)
		table.insert(hazards, state)
		if not heartbeat then
			heartbeat = RunService.Heartbeat:Connect(stepHazards)
		end
	end
	return state.released and now >= state.endAt
end

function FireTornadoCast.Finish(_mob, state)
	if not state then return end
	if state.track and state.track.IsPlaying then
		state.track:Stop(0.15)
	end
	if not state.released then
		state.cancelled = true
		CastEvent:FireAllClients("cancel", state.id)
	end
end

return FireTornadoCast
