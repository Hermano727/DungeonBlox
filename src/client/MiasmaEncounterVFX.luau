--[[
	MiasmaEncounterVFX -- client-side encounter warnings and pulses.

	Ground warnings (poison drops, slime landings, the boss drop, submerge pools, purge safe
	areas) use RS/MiasmaTelegraphArt: particle/beam/light recipes per kind plus a thin crisp
	edge ring, with a shockwave ring that collapses to the centre exactly when the hit lands.

	The fast poison shot gets a ground LANE (its true hit width, extended past the aim point
	because the shot keeps flying), poison particles streaming toward the target, a fill that
	races down the lane over the warning, and a flowing textured air beam from Miasma to the
	aim point so it still reads in first person.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local TelegraphArt = require(ReplicatedStorage:WaitForChild("MiasmaTelegraphArt"))
local LandingSlamFX = require(script.Parent:WaitForChild("MiasmaLandingSlamFX"))
local StunFX = require(script.Parent:WaitForChild("MiasmaStunFX"))
local RoarFX = require(script.Parent:WaitForChild("MiasmaRoarFX"))
local DropCutscene = require(script.Parent:WaitForChild("MiasmaDropCutscene"))
local LobFX = require(script.Parent:WaitForChild("MiasmaLobFX"))
local ArenaShake = require(script.Parent:WaitForChild("ArenaShake"))
local CeilingDebris = require(script.Parent:WaitForChild("CeilingDebrisFX"))
local ShroudFX = require(script.Parent:WaitForChild("MiasmaShroudFX"))
local AuraFX = require(script.Parent:WaitForChild("MiasmaAuraFX"))
local ValveArrows = require(script.Parent:WaitForChild("MiasmaValveArrows"))
local PureWaterCutscene = require(script.Parent:WaitForChild("MiasmaPureWaterCutscene"))
local SoundEffects = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("SoundEffects"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))

-- Big world moments: the drop cutscene's rock rain + fall rumble, and the slam's jolt + burst.
-- The ceiling collapse (sound, rumble, rock rain) starts DROP_SOUND_SLAM_AT before the impact,
-- so the slam inside the sound lands on it; that's while the camera is still on the ceiling blob.
local DROP_SOUND_SLAM_AT = 3.0 -- where the slam sits in SoundEffects.MiasmaCeilingCollapse
local CUTSCENE_ROCKS_PER_SECOND = 5
local ROCK_RADIUS = 75
local SLAM_ROCKS = 68          -- 45 before the 1.5x pass
local SLAM_ROCK_SCALE = 1.25   -- the slam's rocks are chunkier than the rain's
local SLAM_SHAKE = { amplitude = 2.2, rotation = 2.5, duration = .12, rampIn = 0, decay = 1.1, frequency = 20, fullRadius = 80 }
local CEILING_RUMBLE = { amplitude = .2, rotation = .25, rampIn = .8, decay = .15, frequency = 9 } -- collapse start -> impact
local FALL_RUMBLE = { amplitude = .35, rotation = .4, rampIn = .3, decay = .15, frequency = 10 }  -- stacks on top while it falls
-- Enrage: the rear-up rumbles, then the poison spew (RoarFX poison style, with its own shake).
local ENRAGE_RUMBLE = { amplitude = .45, rotation = .55, rampIn = .35, decay = .2, frequency = 11 }
local ENRAGE_ROCKS_PER_SECOND = 7
local ENRAGE_ROAR_SOUND_LEAD = .4

-- Presentation kinds that end whatever stun visual is up.
local STUN_END_KINDS = {
	StunEnded = true, StaggerRecovered = true, Recorrupt = true, Enrage = true,
	PurgeWarning = true, Failed = true, Defeated = true,
}

local VFX = {}

local folder = Instance.new("Folder")
folder.Name = "MiasmaEncounterVFX"
folder.Parent = Workspace

local collapseSound

local function stopCollapseSound()
	if collapseSound then collapseSound:Destroy(); collapseSound = nil end
end

-- The ceiling collapse sound, `delay` seconds from now. A negative delay (joined late) starts it
-- that far in, so its slam still lands on the impact.
local function playCollapseSound(delay)
	stopCollapseSound()
	local id = SoundEffects.MiasmaCeilingCollapse
	if type(id) ~= "string" or id == "" then return end
	local sound = Instance.new("Sound")
	sound.Name = "MiasmaCeilingCollapse"
	sound.SoundId = id
	sound.SoundGroup = SfxService.GetEffectsGroup() -- Master x Effects sliders
	sound.Parent = SoundService
	collapseSound = sound
	sound.Ended:Connect(function()
		if collapseSound == sound then collapseSound = nil end
		sound:Destroy()
	end)
	Debris:AddItem(sound, 30)
	task.delay(math.max(0, delay), function()
		if not sound.Parent then return end
		if delay < 0 then sound.TimePosition = -delay end
		sound:Play()
	end)
end

function VFX.Telegraph(payload)
	local kind = payload.kind
	-- Poison lob: mark (reticle tracks the target) -> launch (lock + arc) -> impact (splash).
	if kind == "LobTarget" then LobFX.Target(payload, folder) return end
	if kind == "LobLaunch" then LobFX.Launch(payload, folder) return end
	if kind == "LobImpact" then LobFX.Impact(payload, folder) return end
	if typeof(payload.position) ~= "Vector3" then return end
	local duration = math.max(.1, tonumber(payload.duration) or 1)
	local radius = math.max(.5, tonumber(payload.radius) or 5)
	local handle = TelegraphArt.Build(folder, payload.position, radius, kind, { ignore = { folder }, duration = duration })
	TelegraphArt.Animate(handle, duration)
end

-- Presentations that end the valve cycle: the guide arrows come down.
local ARROWS_CLEAR_KINDS = {
	PureWaterCutscene = true, PureWater = true, Recorrupt = true, PurgeWarning = true,
	Failed = true, Defeated = true, Enrage = true,
}

-- Presentations that carry the boss model once it's standing in the arena.
local AURA_KINDS = { BossLanding = true, BossRoar = true, Staggered = true, PureWater = true, EnrageCutscene = true }

function VFX.Presentation(payload)
	local kind = payload.kind
	-- Miasma's aura + base ooze, from its landing on (or from any later presentation that carries
	-- the boss, so a late joiner still gets it). Start() ignores the same boss twice.
	if AURA_KINDS[kind] and typeof(payload.boss) == "Instance" then AuraFX.Start(payload.boss, folder) end
	-- Valve guide arrows: up when valves wake, each down when primed, all down when the cycle ends.
	if kind == "GatesAwaken" then
		ValveArrows.Show(payload.gates, payload.positions, folder)
	elseif kind == "GatePrimed" then
		ValveArrows.Hide(tonumber(payload.gate))
	elseif ARROWS_CLEAR_KINDS[kind] then
		ValveArrows.Clear()
	end
	-- The final valve's cutscene; the holy water quenches Miasma's aura from impact to stun end.
	if kind == "PureWaterCutscene" then
		PureWaterCutscene.Play(payload, folder)
		local elapsed = Workspace:GetServerTimeNow() - (tonumber(payload.startsAt) or Workspace:GetServerTimeNow())
		task.delay(math.max(0, (tonumber(payload.impactAt) or 0) - elapsed), function()
			AuraFX.Quench(tonumber(payload.stunSeconds) or 12)
		end)
		return
	elseif kind == "StunEnded" or kind == "Recorrupt" then
		AuraFX.Restore()
	end
	-- Phase 1 -> 2 drop: every member's camera runs the cutscene; ends early if the fight does.
	if kind == "BossDropCutscene" then
		DropCutscene.Play(payload)
		-- The ceiling collapse starts DROP_SOUND_SLAM_AT before the impact: the sound, a low
		-- rumble and the rock rain (which carries on to the end). A heavier rumble stacks on top
		-- while Miasma actually falls (let go -> impact). Times are seconds from the server's startsAt.
		local elapsed = Workspace:GetServerTimeNow() - (tonumber(payload.startsAt) or Workspace:GetServerTimeNow())
		local impact = tonumber(payload.impact) or 0
		local collapseAt = math.max(0, impact - DROP_SOUND_SLAM_AT)
		playCollapseSound(impact - DROP_SOUND_SLAM_AT - elapsed)
		local rainFrom = math.max(collapseAt, elapsed)
		local rainFor = (tonumber(payload.endsAt) or 0) - rainFrom
		if typeof(payload.landing) == "Vector3" and rainFor > 0 then
			task.delay(rainFrom - elapsed, function()
				CeilingDebris.Rain(payload.landing, ROCK_RADIUS, rainFor, CUTSCENE_ROCKS_PER_SECOND, folder)
			end)
		end
		local rumbleFor = impact - rainFrom - CEILING_RUMBLE.rampIn
		if impact > rainFrom then
			task.delay(rainFrom - elapsed, function()
				ArenaShake.Shake({
					amplitude = CEILING_RUMBLE.amplitude, rotation = CEILING_RUMBLE.rotation, duration = math.max(0, rumbleFor),
					rampIn = CEILING_RUMBLE.rampIn, decay = CEILING_RUMBLE.decay, frequency = CEILING_RUMBLE.frequency,
				})
			end)
		end
		local fallAt = (tonumber(payload.bridgeStart) or 0) - elapsed
		local fallFor = (tonumber(payload.impact) or 0) - (tonumber(payload.bridgeStart) or 0)
		if fallFor > 0 then
			task.delay(math.max(0, fallAt), function()
				ArenaShake.Shake({
					amplitude = FALL_RUMBLE.amplitude, rotation = FALL_RUMBLE.rotation, duration = fallFor,
					rampIn = FALL_RUMBLE.rampIn, decay = FALL_RUMBLE.decay, frequency = FALL_RUMBLE.frequency,
				})
			end)
		end
		return
	elseif kind == "Failed" or kind == "Defeated" then
		DropCutscene.Stop()
		ShroudFX.Stop()
		AuraFX.Stop()
		PureWaterCutscene.Stop()
		stopCollapseSound()
	end
	-- Enrage: same cutscene machinery on the boss where it stands, rocks + rumble, then the
	-- poison spew at the jaw thrust. Times are seconds from the server's startsAt.
	if kind == "EnrageCutscene" then
		local startsAt = tonumber(payload.startsAt) or Workspace:GetServerTimeNow()
		local elapsed = Workspace:GetServerTimeNow() - startsAt
		local spewStart = tonumber(payload.spewStart) or 1.9
		local spewEnd = tonumber(payload.spewEnd) or 2.95
		local endsAt = tonumber(payload.endsAt) or 3.6
		local landing = typeof(payload.landing) == "Vector3" and payload.landing or nil
		if landing then
			DropCutscene.Play({
				mode = "enrage", startsAt = startsAt, endsAt = endsAt, spewStart = spewStart, spewEnd = spewEnd,
				boss = payload.boss, landing = landing, ceiling = landing, facing = payload.facing,
			})
			if endsAt - elapsed > 0 then
				CeilingDebris.Rain(landing, ROCK_RADIUS, endsAt - elapsed, ENRAGE_ROCKS_PER_SECOND, folder)
			end
		end
		ArenaShake.Shake({
			amplitude = ENRAGE_RUMBLE.amplitude, rotation = ENRAGE_RUMBLE.rotation, duration = math.max(0, spewStart - elapsed - .3),
			rampIn = ENRAGE_RUMBLE.rampIn, decay = ENRAGE_RUMBLE.decay, frequency = ENRAGE_RUMBLE.frequency,
		})
		task.delay(math.max(0, spewStart - ENRAGE_ROAR_SOUND_LEAD - elapsed), RoarFX.PlaySound)
		task.delay(math.max(0, spewStart - elapsed), function()
			local boss = typeof(payload.boss) == "Instance" and payload.boss or nil
			RoarFX.Play(boss, spewEnd - spewStart, landing, folder, { style = "poison" })
		end)
		return
	end
	if kind == "Shroud" then
		ShroudFX.Start(payload, folder)
		return
	end
	if kind == "BossLanding" and typeof(payload.position) == "Vector3" then
		local boss = typeof(payload.boss) == "Instance" and payload.boss or nil
		LandingSlamFX.Play(payload.position, payload.radius, boss, folder)
		-- The hit: a hard jolt (mostly vertical) and a burst of rock from the ceiling.
		ArenaShake.Shake({
			amplitude = SLAM_SHAKE.amplitude, rotation = SLAM_SHAKE.rotation, duration = SLAM_SHAKE.duration,
			rampIn = SLAM_SHAKE.rampIn, decay = SLAM_SHAKE.decay, frequency = SLAM_SHAKE.frequency,
			focus = payload.position, fullRadius = SLAM_SHAKE.fullRadius,
		})
		CeilingDebris.Burst(payload.position, ROCK_RADIUS, SLAM_ROCKS, folder, SLAM_ROCK_SCALE)
		return
	end
	-- Stun visuals on the boss itself. Stagger: the dazed star ring. Pure water: the ring plus
	-- the vulnerable outline (the server shrinks the boss; the ring follows its size).
	if kind == "Staggered" or kind == "PureWater" then
		StunFX.Start(payload.boss, { duration = tonumber(payload.duration), vulnerable = kind == "PureWater" })
	elseif STUN_END_KINDS[kind] then
		StunFX.Stop()
	end
	-- The party frozen by the landing slam gets the same dazed ring, over their own heads.
	if kind == "PlayersStunned" then
		StunFX.StartPlayers(payload.players, tonumber(payload.duration))
	elseif kind == "Failed" or kind == "Defeated" then
		StunFX.StopPlayers()
	end
	if kind == "BossRoarSound" then
		RoarFX.PlaySound(tonumber(payload.duration))
		return
	end
	if kind == "BossRoar" then
		local boss = typeof(payload.boss) == "Instance" and payload.boss or nil
		RoarFX.Play(boss, tonumber(payload.duration), payload.position, folder)
		return
	end
	if typeof(payload.position) ~= "Vector3" then return end
	if kind == "PureWater" then
		TelegraphArt.Shockwave(folder, payload.position, 23, "PureWater", 1.6) -- 34 / 26 before the boss went 0.67 -> 0.45
	elseif kind == "Staggered" then
		TelegraphArt.Shockwave(folder, payload.position, 17, "PureWater", 1.1)
	elseif kind == "BossGrowth" or kind == "Enrage" then
		TelegraphArt.Shockwave(folder, payload.position, 24, "Shockwave", math.min(2.5, tonumber(payload.duration) or 1.5))
	end
end

-- Stops every running effect (the shroud's purple grade on Lighting included) and clears the
-- ground warnings, but keeps the module usable for the next fight. Used when the player leaves
-- or the dungeon ends (StatusCleanseClient), where no Failed/Defeated presentation arrives.
function VFX.StopAll()
	ShroudFX.Stop()
	AuraFX.Stop()
	ValveArrows.Clear()
	PureWaterCutscene.Stop()
	LobFX.StopAll()
	ArenaShake.StopAll()
	stopCollapseSound()
	DropCutscene.Stop()
	StunFX.Stop()
	StunFX.StopPlayers()
	if folder then folder:ClearAllChildren() end
end

function VFX.Destroy()
	ShroudFX.Stop()
	AuraFX.Stop()
	ValveArrows.Clear()
	PureWaterCutscene.Stop()
	LobFX.StopAll()
	ArenaShake.StopAll()
	stopCollapseSound()
	DropCutscene.Stop()
	StunFX.Stop()
	StunFX.StopPlayers()
	if folder then folder:Destroy() end
end

return VFX
