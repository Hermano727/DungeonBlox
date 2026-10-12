--[[
	MobCombatSfx -- ServerScriptService

	Sounds for mobs that fight with a real weapon, decided by the server so they line up with what
	actually happened. Opt-in per mob in MobData (keys from RS/Assets/Sounds/SoundEffects):

		CombatSounds = {
			Swing = "HeavyWeaponSwing",   -- every swing, hit or miss, just before the impact moment
			WeaponHit = "WeaponHitPlayer", -- only when that swing's damage actually landed on a player
		},

	Mobs without CombatSounds stay silent here (slimes, biters: a blade sound would be wrong on them,
	which is why this is not a generic "player got hurt" sound). Both are positional, heard within
	HEAR_RADIUS through DamageService.PlayEffectAt.

	Callers: MobClass:PerformAttack (the ordinary swing), MobMovesetBehaviour (combo impacts),
	FireTornadoCast (the Groundbreaker Slam's downswing).
]]

local ServerScriptService = game:GetService("ServerScriptService")

local DamageService = require(ServerScriptService:WaitForChild("DamageService"))

local MobCombatSfx = {}

local SWING_LEAD = 0.15  -- the whoosh starts this long before the impact moment
local HEAR_RADIUS = 150

local function soundsOf(mob)
	return mob and mob.Stats and mob.Stats.CombatSounds
end

-- A swing whose impact lands `seconds` from now. `stillValid` (optional) is asked at play time,
-- so an interrupted swing stays silent.
-- TEMP (swing-sound diagnosis, 2026-10-09): Studio-only trace, remove once Kane's whoosh is heard.
local TRACE = game:GetService("RunService"):IsStudio()
local function trace(mob, msg)
	if TRACE then
		local stats = mob and mob.Stats
		print(("[MobCombatSfx] %s: %s"):format(tostring(stats and (stats.MobID or stats.Name) or "?"), msg))
	end
end

function MobCombatSfx.SwingIn(mob, seconds, stillValid)
	local sounds = soundsOf(mob)
	if not sounds or not sounds.Swing then return end
	trace(mob, ("swing scheduled, impact in %.2fs"):format(seconds or 0))
	task.delay(math.max(0, (seconds or 0) - SWING_LEAD), function()
		local root = mob.Model and mob.Model.PrimaryPart
		if not root or not mob:IsAlive() then trace(mob, "skipped: no PrimaryPart or dead") return end
		if stillValid and not stillValid() then trace(mob, "skipped: swing no longer valid") return end
		local heard = DamageService.PlayEffectAt(sounds.Swing, root.Position, HEAR_RADIUS)
		trace(mob, ("swing sound fired to %s player(s)"):format(tostring(heard)))
	end)
end

-- `dealt` is DamageService.ApplyToPlayer's result: 0 means blocked or nothing landed (a block
-- already plays its own BlockHit), so no weapon sound.
function MobCombatSfx.WeaponHit(mob, player, dealt)
	local sounds = soundsOf(mob)
	if not sounds or not sounds.WeaponHit or not dealt or dealt <= 0 then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		DamageService.PlayEffectAt(sounds.WeaponHit, root.Position, HEAR_RADIUS)
	end
end

return MobCombatSfx
