--[[
	SoundEffects
	Registry of one-shot effect-sound asset ids, keyed by a short logical name
	so callers never hardcode a raw rbxassetid:// string. Played through
	SfxService.PlayEffect(key), which plays it through its sound bucket's
	SoundGroup, so one Settings > Audio slider (Combat, Creatures, Mount, ...)
	controls it. The bucket comes from the key's NAME (RS/AudioCategories:
	KEYS, then PREFIXES such as Horse*/Mine*/Miasma*, else "Other").

	Add a new effect by adding a line here. Name it after its family (MineX,
	HorseX, MiasmaX ...) and it files itself; otherwise add it to
	AudioCategories.KEYS. In Studio the client warns about keys left in Other.

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
	-- Ids from the user, 2026-10-11.
	MiasmaSlam = "rbxassetid://93937600585701",  -- the submerge move's eruption slam (MiasmaEncounterVFX, EruptSlam)
	-- Poison shot out of a mouth: Miasma's lob (MiasmaLobFX, once per volley), its Enrage spew,
	-- and the underling slime's spit (SSS/SlimeSpitCast, PlayEffectAt).
	PoisonSpit = "rbxassetid://71154528089936",
	-- Picked 2026-10-11 from the licensed Pro Sound Effects library by catalogue description, NOT
	-- listened to: audition (ServerStorage.SfxAudition in the place) and swap. Lists = random variation.
	MiasmaBiteChomp = {                          -- the jaws clamping, every bite (MobData CombatSounds.Swing)
		"rbxassetid://9114574156",               -- Giant Bug Chomps 1: crunching thuds, deep rumbles, tearing, mushy
		"rbxassetid://9114574214",               -- Giant Bug Chomps 2
		"rbxassetid://9114574294",               -- Giant Bug Chomps 3
	},
	MiasmaBiteHit = {                            -- the bite landing on you (CombatSounds.WeaponHit)
		"rbxassetid://9125466463",               -- Creature Bite, Pterodactyl, Crunch, Wet Snap
		"rbxassetid://9125466992",
		"rbxassetid://9125466839",
	},
	PoisonSplat = "rbxassetid://9120495639",     -- a poison glob landing (Water Balloon 4: gelatinous splash)
	MiasmaSubmerge = "rbxassetid://9120313398",  -- Miasma sinking into the floor (underwater bubbles, heavy burst)
	PoisonDrip = {                               -- a drop of Miasma's drool hitting the floor (MiasmaAuraFX, throttled)
		"rbxassetid://9126181980",               -- Water Drip, Distant Single Splattering Drops, Very Sharp, Smacking Plops
		"rbxassetid://9126179016",
		"rbxassetid://9126183559",
	},

	-- Armed-mob combat sounds (SSS/MobCombatSfx). A mob opts in through its MobData
	-- `CombatSounds = { Swing = <key>, WeaponHit = <key> }`; reusable by any mob with a real
	-- weapon (not slimes or biters, so this is not a generic "player hurt" sound).
	HeavyWeaponSwing = "rbxassetid://130979950762389", -- a heavy weapon cutting the air, no impact
	WeaponHitPlayer = "rbxassetid://110738467966548",  -- a weapon landing on a player (a stab/cut)

	-- Kane's Fire Tornado (FireTornadoVFX), ids from the user 2026-10-08.
	FireTornadoBurn = "rbxassetid://123746628600206",  -- each tornado damage tick on a player
	KaneGroundSlam = "rbxassetid://124603373703589",  -- the Groundbreaker Slam's axe hitting the ground
	-- Looped on each tornado while it travels. FireTornadoVFX builds this Sound itself (looped,
	-- parented to the tornado so it is positional), PlayEffect is one-shot only.
	FireTornadoWind = "rbxassetid://138959646714932",

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

	-- Miasma's boss-room opening cutscene (client/MiasmaEntranceCutscene). Empty = silent until chosen.
	EntranceRockImpact = "rbxassetid://9118689425", -- the boulder shatters on the pressure plate (rocks tumbling)
	EntranceRune = "",                              -- the tablet's runes light up
	EntranceValve = "",                             -- the valve glows
	EntrancePlop = "",                              -- a slime plops out of a drain
	EntranceAltar = "",                             -- a cleansing altar lights up
	EntranceGateGrind = "",                         -- the gate sliding shut (stone on stone)
	EntranceGateSlam = "rbxassetid://124603373703589", -- the gate slams home (a heavy ground impact)

	-- The dungeon clear sequence (client/DungeonClearSequence, docs/dungeon-clear-sequence.md).
	-- First picks 2026-10-10 from the licensed Pro Sound Effects / APM libraries, chosen by
	-- catalogue description only, NOT listened to: approve or swap (see
	-- docs/dungeon-clear-asset-requests.md). Empty = silent until chosen.
	ClearChoir = "rbxassetid://1846902441",      -- the Benediction's light: choir, two chords (APM Drama Sting 7)
	BrazierRise = "rbxassetid://9125883443",     -- a brazier grinding up out of the floor (huge boulder scrape)
	EmberPour = "",                              -- the score pouring in as embers (soft rising crackle)
	ScrapBurn = "",                              -- the low rolls burning off (a fire puff)
	RelicTick = "rbxassetid://9120288772",       -- each step of a relic's rarity climb, pitched up per step (tuning fork)
	RelicBurn = "",                              -- the shroud catching fire
	RevealCommon = "",
	RevealUncommon = "",
	RevealRare = "rbxassetid://9114530337",      -- fork tine ping
	RevealEpic = "rbxassetid://1846902250",      -- single powerful low orchestral hit (APM)
	RevealLegendary = "rbxassetid://80017579293314", -- APM Cryptic Veil Sting 1
	BossEchoRoar = "rbxassetid://128962677500476", -- the main boss's echo rising (Miasma's own roar for now)
	MiniEchoRise = "",                           -- a miniboss's echo rising
	EchoTear = "rbxassetid://9120703361",        -- the final echo torn apart (huge whoosh with impacts)
	EchoShatter = "",                            -- a miniboss echo shattering
	MythicDescend = "",                          -- the Mythic relic sinking out of the dark
	JudgementTick = "rbxassetid://9114530645",   -- the judgement beam landing on a loser (fork tine pluck)
	MythicWin = "rbxassetid://1846902250",       -- the beam flaring on a winner (APM low hit)
	MythicToll = "rbxassetid://9113804436",      -- nobody won: the relic crumbles (church bell tolling)
	MythicBroadcast = "rbxassetid://87211666649638", -- the server-wide Mythic announcement (APM Cryptic Veil Sting 2)

	-- The horse mount (MountClient via GameEvents/MountFx, MountConfig.Sounds sets the pitch).
	-- Picked 2026-10-11 from Pro Sound Effects by description, NOT listened to: the licensed
	-- library has no real horse calls, so the call is a "sped-up horse" whinny played back at
	-- ~0.6 speed. Audition (ServerStorage.SfxAudition) and swap for real horse sounds if you have them.
	HorseCall = {                                -- called / sent away
		"rbxassetid://9119235014",               -- Small Creature Whinnying 1 (sped-up horse and gibbon)
		"rbxassetid://9119235230",               -- ... 4
		"rbxassetid://9119236501",               -- ... 19
	},
	HorseThrown = {                              -- bolts after combat / an arrow (played a bit higher)
		"rbxassetid://9119235734",               -- Small Creature Whinnying 9
		"rbxassetid://9119235699",               -- ... 10
		"rbxassetid://9119235714",               -- ... 11
	},
	HorseIdle = {                                -- standing: champing the bit, now and then
		"rbxassetid://9114827208",               -- Horse Teeth 5, chomping together
		"rbxassetid://9114827512",               -- ... 8
		"rbxassetid://9114827625",               -- ... 10
		"rbxassetid://9114827711",               -- ... 11
	},
	HorseGallop = "",                            -- looped hoofbeats while it runs: none found yet

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
