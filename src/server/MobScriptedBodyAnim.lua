-- MobScriptedBodyAnim
-- Optional, purely-visual squash-and-stretch driver for mobs that have no
-- skeletal rig at all -- just a single "Body" part welded to HumanoidRootPart
-- (the established placeholder-mob shape already used by ForestGoblin,
-- CaveBat, StoneGolem, etc.) -- but still want some life in their hop and
-- attack.
--
-- This does NOT touch MobClass or HoppingMobClass. It reads
-- HoppingMobClass's own per-mob hop-timing fields (_hopStartTime,
-- _hopEndTime, _hopLandedAt) directly off the mob instance every Heartbeat,
-- rather than being told about hop events -- so it works for both chase
-- hops and idle-wander hops automatically, and HoppingMobClass never has to
-- know this module exists.
--
-- Enabled per-mob via MobAnimConfig[<MobID>].ScriptedBody = true. Wired in
-- from MobAnimController.attach / MobAnimController.playAttack.
--
-- IMPORTANT: playAttack's tween sequence runs on its own thread (task.spawn)
-- rather than blocking with :Wait() -- MobAnimController.playAttack is
-- called synchronously from MobClass:PerformAttack, which runs inside the
-- shared per-tick UpdateAI loop over every active mob. A blocking wait here
-- would freeze every other mob's AI for the duration of the swing.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local MobScriptedBodyAnim = {}

-- Hop squash/stretch shape, expressed as fractions of the hop's own
-- duration (self._hopEndTime - self._hopStartTime from HoppingMobClass).
local HOP_LAUNCH_SQUASH_WINDOW = 0.12 -- anticipation squash right at liftoff
local HOP_LAND_SQUASH_WINDOW   = 0.14 -- impact squash right before landing
local LAND_RECOVER_TIME        = 0.18 -- seconds to ease back to rest after landing
local STRETCH_Y                = 1.20 -- mid-air stretch multiplier (tall/thin)
local SQUASH_Y                  = 0.74 -- launch/landing squash multiplier (short/wide)
local WIDEN_SHARE                = 0.6  -- how much of the Y squeeze redistributes into X/Z

-- One-shot attack pulse shape. Bumped up 2026-09-09 (from 0.09/0.16/0.15,
-- totalling 0.4s) per direct request: the swing wasn't reading clearly, and
-- the whole pulse needs to be at least half a second so it has room to play
-- out atomically -- see MobClass:PerformAttack / HandleAttacking, which lock
-- the mob in place against ATTACK_DURATION below rather than a guessed
-- number, so this file stays the single source of truth for how long a
-- ScriptedBody swing actually takes.
local ATTACK_SQUASH_TIME  = 0.10
local ATTACK_POP_TIME     = 0.22
local ATTACK_RECOVER_TIME = 0.20
local ATTACK_SQUASH_Y     = 0.62 -- deeper anticipation squash (was 0.78) -- more obvious wind-up
local ATTACK_POP_Y        = 1.38 -- taller lunge-pop (was 1.18) -- more obvious hit

-- Exposed so MobAnimController.attach can lock a mob's AI in place for
-- exactly as long as this pulse actually plays (see MobClass:PerformAttack /
-- HandleAttacking), instead of a separately hand-kept number that could
-- silently drift out of sync with the tween times above.
MobScriptedBodyAnim.ATTACK_DURATION = ATTACK_SQUASH_TIME + ATTACK_POP_TIME + ATTACK_RECOVER_TIME

local function sizeForYMult(baseSize, yMult)
	local widen = 1 + (1 - yMult) * WIDEN_SHARE
	return Vector3.new(baseSize.X * widen, baseSize.Y * yMult, baseSize.Z * widen)
end

-- Attach: call once per mob at spawn, only when MobAnimConfig[mob.MobID]
-- has ScriptedBody = true. Finds the mob's "Body" part, records its base
-- Size, and starts a per-mob Heartbeat connection that self-disconnects the
-- moment the mob dies (mob.Model goes nil) or the part is destroyed.
function MobScriptedBodyAnim.attach(mob)
	local model = mob.Model
	local body = model and model:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		return
	end

	local baseSize = body.Size
	mob._scriptedBody = body
	mob._scriptedBaseSize = baseSize
	mob._scriptedAttacking = false

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not mob.Model or not body.Parent then
			conn:Disconnect()
			return
		end
		if mob._scriptedAttacking then
			return -- the attack pulse owns Size while it plays
		end

		local now = tick()
		local yMult = 1

		if mob._hopEndTime then
			local dur = mob._hopEndTime - mob._hopStartTime
			if dur > 0.001 then
				local t = math.clamp((now - mob._hopStartTime) / dur, 0, 1)
				if t < HOP_LAUNCH_SQUASH_WINDOW then
					local a = t / HOP_LAUNCH_SQUASH_WINDOW
					yMult = SQUASH_Y + (1 - SQUASH_Y) * a
				elseif t > 1 - HOP_LAND_SQUASH_WINDOW then
					local a = (t - (1 - HOP_LAND_SQUASH_WINDOW)) / HOP_LAND_SQUASH_WINDOW
					yMult = 1 + (SQUASH_Y - 1) * a
				else
					local span = 1 - HOP_LAUNCH_SQUASH_WINDOW - HOP_LAND_SQUASH_WINDOW
					local midT = span > 0.001 and (t - HOP_LAUNCH_SQUASH_WINDOW) / span or 0
					local arc = math.sin(math.pi * math.clamp(midT, 0, 1))
					yMult = 1 + (STRETCH_Y - 1) * arc
				end
			end
		elseif mob._hopLandedAt then
			local a = math.clamp((now - mob._hopLandedAt) / LAND_RECOVER_TIME, 0, 1)
			yMult = SQUASH_Y + (1 - SQUASH_Y) * a
		end

		body.Size = sizeForYMult(baseSize, yMult)
	end)

	mob._scriptedBodyConn = conn
end

-- Called from MobAnimController.playAttack when the mob is ScriptedBody.
-- Runs a quick anticipation-squash -> pop-stretch -> recover sequence on
-- its own thread so it never blocks the caller.
function MobScriptedBodyAnim.playAttack(mob)
	local body = mob._scriptedBody
	local baseSize = mob._scriptedBaseSize
	if not body or not baseSize then
		return
	end
	if mob._scriptedAttacking then
		return -- swing already in progress, don't stack another
	end

	mob._scriptedAttacking = true

	task.spawn(function()
		local squash = TweenService:Create(
			body,
			TweenInfo.new(ATTACK_SQUASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = sizeForYMult(baseSize, ATTACK_SQUASH_Y) }
		)
		local pop = TweenService:Create(
			body,
			TweenInfo.new(ATTACK_POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = sizeForYMult(baseSize, ATTACK_POP_Y) }
		)
		local recover = TweenService:Create(
			body,
			TweenInfo.new(ATTACK_RECOVER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ Size = baseSize }
		)

		if not body.Parent then mob._scriptedAttacking = false return end
		squash:Play()
		squash.Completed:Wait()

		if not body.Parent then mob._scriptedAttacking = false return end
		pop:Play()
		pop.Completed:Wait()

		if not body.Parent then mob._scriptedAttacking = false return end
		recover:Play()
		recover.Completed:Wait()

		mob._scriptedAttacking = false
	end)
end

return MobScriptedBodyAnim
