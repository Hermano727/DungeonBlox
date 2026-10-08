--[[
	SoundEffects
	Registry of one-shot effect-sound asset ids, keyed by a short logical name
	so callers never hardcode a raw rbxassetid:// string. Played through
	SfxService.PlayEffect(key), which routes every sound through the shared
	SoundService.Main.Effects SoundGroup -- that's what lets a single settings
	slider ("VFX" in SettingsClient) ramp every effect sound down at once,
	instead of each system managing its own volume.

	Add a new effect by adding a line here; nothing else needs to change
	unless the new effect also needs per-play pitch/volume variance (see
	SfxService.PlayEffect for where that would go).

	A value may be a LIST of ids instead of one string -- variations of the
	same effect. SfxService.PlayEffect picks one at random per call, so a sound
	that fires often (a block proc every few hits) doesn't get grating.
]]

return {
	ItemPickup = "rbxassetid://134602992766192",
	CriticalHit = "rbxassetid://77076686405925",
	CombatXPGain = "rbxassetid://127206748417528",
	-- Source short, soft one-shots: a dry cork pop and a quiet magical absorption puff.
	-- Empty entries intentionally play nothing until approved assets are uploaded.
	PotionCorkPop = "rbxassetid://130642090058188", -- hp pot cork pop.mp3 (uploaded 2026-10-03)
	PotionOrbAbsorb = "",

	-- Enchanting Station (EnchantStationClient / EnchantStationScreen)
	EnchantStationEnter = "rbxassetid://70458889272802",
	EnchantStationExit = "rbxassetid://102474597594958",
	EnchantSuccess = "rbxassetid://101663733274964",
	EnchantFail = "rbxassetid://91534279231521",

	-- Switching destinations in the Tab menu (Inventory -> Journal ...; not Journal pages).
	-- Source: assets/soundtracks/whoosh tab switch.mp3, uploaded via Open Cloud 2026-10-01.
	TabSwitch = "rbxassetid://99277096441013",

	-- Miasma's roar, frames 65-100 of its landing slam (MiasmaRoarFX). Played there directly
	-- rather than through PlayEffect, whose 10s safety cleanup could clip a long roar.
	MiasmaRoar = "rbxassetid://128962677500476",
	-- The drop cutscene's ceiling collapse: rocks falling, then Miasma's slam ~3.0s in. Started so
	-- that mark lands on the impact (MiasmaEncounterVFX, DROP_SOUND_SLAM_AT).
	MiasmaCeilingCollapse = "rbxassetid://116932059282652",

	-- Mining session (MiningClient). First picks (2026-10-03), chosen from Pro Sound Effects'
	-- Creator Store library (licensed for every experience) by catalogue description only,
	-- NOT listened to yet: approve or swap. Empty = silent.
	MineSeam = "rbxassetid://9118609285",    -- the opening strike lands on the seam (rock on rock)
	MineWeak = "rbxassetid://9118630399",    -- a strike too soft / a missed seam (dull hit, dirt)
	MineCharge = "",                         -- starting to charge a strike (short, soft)
	MineBreak = "rbxassetid://9118587493",   -- a fault breaks cleanly, a slab falls away
	MineCrack = "rbxassetid://9118588165",   -- the ore cracks (rock drop, breaks)
	MineShatter = "rbxassetid://9118689425", -- the ore shatters (rocks tumbling together)
	MinePry = "rbxassetid://9118664167",     -- the chunk comes free (rocks moving)

	-- Spear-fishing session (FishingClient). Splash/hit/caught: same source and caveat as the
	-- mining set. Throw and reel-in are ours (assets/soundtracks, uploaded via Open Cloud 2026-10-03).
	SpearThrow = {                           -- the spear leaves the hand: one of three at random
		"rbxassetid://84510941124193",       -- spear throw 1.mp3
		"rbxassetid://94690795337164",       -- spear throw 2.mp3
		"rbxassetid://131121346352938",      -- spear throw 3.mp3
	},
	FishReelIn = "rbxassetid://109735168719814", -- the haul starts: line reeling in (fishing reel in.mp3)
	SpearSplash = "rbxassetid://9117947974", -- it hits the water (short small splash)
	SpearHit = "rbxassetid://9119479412",    -- it strikes a fish (heavy plop)
	FishStunned = "",                        -- third hit: the fish goes still
	FishCaught = "rbxassetid://127584016325176",       -- landed any fish but golden (fish catch noise.mp3)
	GoldenFishCaught = "rbxassetid://98630830536676",  -- landed a golden fish (golden fish catch noise.mp3)
	FishLineSnap = "",                       -- the line snaps, the fish escapes

	-- Cooking (CookingClient) and eating fish (FishQuickEatClient). Silent until chosen: no
	-- fitting sizzle in the Pro Sound Effects library.
	CookSizzle = "",
	FishEat = "",
	Panting = "", -- looped heavy breathing while out of energy (PantingEffects); not chosen yet
	ItemBreak = "", -- your gear broke (ItemBrokenClient); not chosen yet
	LevelUp = "", -- a skill level-up (LevelUpEffect, played at the player for everyone nearby); not chosen yet

	-- Rolled whenever a hit is blocked outright (see DamageService's block
	-- roll and docs/named-elite-loot.md).
	BlockHit = {
		"rbxassetid://133027289075971",
		"rbxassetid://110305446249138",
		"rbxassetid://136703233495722",
		"rbxassetid://94233869283317",
		"rbxassetid://76886690180038",
	},
}
