-- MobData ModuleScript
-- Static database holding blueprint stats for every enemy
-- Accessible by both Server and Client

local MobData = {}

-- Tier 1 Mobs (Starter Zone)
MobData[1] = {
    ["PlainsSlime"] = {
        Name = "Plains Slime",
        Level = 1,
        BaseHP = 40,
        BaseDamage = 20,
        BaseScore = 10,
        LootPool = "CommonDrop",
        MobID = "PlainsSlime",
        Armor = 3,
        AggroRange = 30,
        ReturnDistance = 50,
        AttackRange = 5,
        AttackCooldown = 0.5,
        -- Doubled 2026-09-09 per direct request ("move 2x faster, hop ~33%
        -- faster, like the Genshin slimes"). HoppingMobClass derives both
        -- from this one number: actual translation speed always equals
        -- MoveSpeed exactly (hopDist/duration cancels out to MoveSpeed by
        -- construction), and hop duration = hopDist/MoveSpeed, so 2 -> 4
        -- takes hopDist from the 3-stud floor up to 4 (no longer clamped),
        -- shortening each hop's cycle from 1.5s to 1.0s -- exactly the 33%
        -- faster cadence asked for, alongside the exact 2x speed.
        MoveSpeed = 4,
        JumpHeight = 3,
        -- MobClassRegistry opt-in: routes to SlimeMobClass, which still hops
        -- (inherits HoppingMobClass's Move()) but plays a random squelch
        -- hit sound instead of the shared default glass sfx. Set as
        -- MovementClass (not SoundClass) so it's picked ahead of the
        -- JumpHeight > 0 heuristic that would otherwise send this to plain
        -- HoppingMobClass.
        MovementClass = "Slime"
    },
    ["ForestGoblin"] = {
        Name = "Forest Goblin",
        Level = 3,
        BaseHP = 75,
        BaseDamage = 8,
        BaseScore = 15,
        LootPool = "CommonDrop",
        MobID = "ForestGoblin",
        Armor = 5,
        AggroRange = 35,
        ReturnDistance = 55,
        AttackRange = 6,
        AttackCooldown = 0.7,
        MoveSpeed = 10,
        JumpHeight = 2
    },
    ["Bandit"] = {
        Name = "Bandit",
        Level = 2,
        BaseHP = 65,
        BaseDamage = 20,
        BaseScore = 12,
        LootPool = "CommonDrop",
        MobID = "Bandit",
        Armor = 6,
        AggroRange = 38,
        ReturnDistance = 55,
        AttackRange = 6,
        AttackCooldown = 0.7,
        MoveSpeed = 10,
        JumpHeight = 0
    },
    ["MiasmaBoss"] = {
        Name = "Miasma",
        Title = "the Scourge",       -- epithet, shown after the name on the boss bar ("MIASMA THE SCOURGE");
                                     -- Name stays bare for loot banners, kill credit, etc.
        Level = 21,
        -- 1500 HP solo (2026-09-29, direct request; was ~5000). HP only is fixed, not
        -- level-scaled (HPScaleWithLevel), so the dungeon's run level can't inflate it; damage
        -- still scales with level as before. The run's party scaling (DungeonRunConfig HPMult:
        -- 0.8 solo .. 2.9 for 8) still applies on top, so BaseHP = 1500 / 0.8 = 1875 lands a
        -- solo run on exactly 1500.
        BaseHP = 1875,
        HPScaleWithLevel = false,
        BaseDamage = 26,             -- its ordinary swing; was 5 (hugging it cost nothing)
        BaseScore = 500,
        LootPool = "CommonDrop",     -- trash loot; the Mythic is rolled separately
        MobID = "MiasmaBoss",
        Telegraph = "MiasmaMaul",    -- purple ring during the windup (MobTelegraphConfig)
        PlayerKnockbackMultiplier = 11, -- x MobClass's base shove (4 studs/s for 0.15s): a real knock back
        Armor = 20,
        AggroRange = 90,             -- big room, big boss
        ReturnDistance = 250,        -- must not leash out of the arena
        AttackRange = 6,             -- effective reach = this + GetHitRadius (~16 at ModelScale 0.45),
                                     -- so ~22 studs: just past the model's own edge
        AttackCooldown = 2.0,
        MoveSpeed = 8 * 1.33,        -- +33% (2026-09-29): was 8
        JumpHeight = 0,              -- MUST stay 0 or MobClassRegistry sends it to HoppingMobClass
        MovementClass = "DungeonBoss",
        KnockbackMultiplier = 0,     -- immovable
        IsBoss = true,
        NeverDeaggro = true,         -- no leash, however far players run (encounter + dev spawns)
        -- 2026-09-27: the eye-weighted rig (same bone names + 157 eye bones, so every existing
        -- clip still drives it). The previous rig stays in MobModels as "MiasmaBoss" (fallback).
        ModelName = "MiasmaBossEyeRig",
        ModelScale = 0.45, -- 0.67 x 0.67 (two 33% cuts) of the authored model; also scales the latch + defeat models
        CeilingLatchModelName = "MiasmaCeilingLatch", -- separate model for the spawn-intro ceiling hang
        DefeatFlatModelName = "MiasmaCeilingLatch",   -- flat puddle rig the defeat sequence swaps to
        InterruptAttackOnHit = false,
    },
    ["MiasmaSlime"] = {
        Name = "Miasma Slime",
        Level = 3,
        BaseHP = 150,
        BaseDamage = 24,
        BaseScore = 18,
        LootPool = "CommonDrop",
        MobID = "MiasmaSlime",
        ModelName = "PlainsSlime",
        Armor = 5,
        AggroRange = 90,
        ReturnDistance = 180,
        AttackRange = 7,
        AttackCooldown = 1.1,
        MoveSpeed = 5,
        JumpHeight = 3,
        MovementClass = "Slime",
    },
    ["MiasmaClog"] = {
        Name = "Slime Growth",
        Level = 3,
        BaseHP = 90,
        BaseDamage = 0,
        BaseScore = 0,
        LootPool = "",
        MobID = "MiasmaClog",
        ModelName = "PlainsSlime",
        Armor = 0,
        AggroRange = 0,
        ReturnDistance = 0,
        AttackRange = 0,
        AttackCooldown = 99,
        MoveSpeed = 0,
        JumpHeight = 0,
        ScaleWithLevel = false,
    },
    ["MiasmaSack"] = {
        Name = "Floating Poison Sack",
        Level = 3,
        BaseHP = 180,
        BaseDamage = 0,
        BaseScore = 0,
        LootPool = "",
        MobID = "MiasmaSack",
        ModelName = "PlainsSlime",
        Armor = 0,
        AggroRange = 0,
        ReturnDistance = 0,
        AttackRange = 0,
        AttackCooldown = 99,
        MoveSpeed = 0,
        JumpHeight = 0,
        ScaleWithLevel = false,
    }
}

-- Tier 2 Mobs (Intermediate Zone)
MobData[2] = {
    ["CaveBat"] = {
        Name = "Cave Bat",
        Level = 5,
        BaseHP = 100,
        BaseDamage = 12,
        BaseScore = 25,
        LootPool = "UncommonDrop",
        MobID = "CaveBat",
        Armor = 8,
        AggroRange = 40,
        ReturnDistance = 60,
        AttackRange = 4,
        AttackCooldown = 0.5,
        MoveSpeed = 14,
        JumpHeight = 4
    },
    ["StoneGolem"] = {
        Name = "Stone Golem",
        Level = 8,
        BaseHP = 200,
        BaseDamage = 20,
        BaseScore = 50,
        LootPool = "UncommonDrop",
        MobID = "StoneGolem",
        Armor = 35,
        AggroRange = 25,
        ReturnDistance = 45,
        AttackRange = 7,
        AttackCooldown = 2.5,
        MoveSpeed = 6,
        JumpHeight = 1
    }
}

-- Tier 3 Mobs (Advanced Zone)
MobData[3] = {
    ["ShadowWolf"] = {
        Name = "Shadow Wolf",
        Level = 12,
        BaseHP = 300,
        BaseDamage = 35,
        BaseScore = 100,
        LootPool = "RareDrop",
        MobID = "ShadowWolf",
        Armor = 25,
        AggroRange = 50,
        ReturnDistance = 70,
        AttackRange = 5,
        AttackCooldown = 0.6,
        MoveSpeed = 16,
        JumpHeight = 4
    },
    ["FlameImp"] = {
        Name = "Flame Imp",
        Level = 15,
        BaseHP = 250,
        BaseDamage = 45,
        BaseScore = 120,
        LootPool = "RareDrop",
        MobID = "FlameImp",
        Armor = 18,
        AggroRange = 45,
        ReturnDistance = 65,
        AttackRange = 8,
        AttackCooldown = 0.7,
        MoveSpeed = 12,
        JumpHeight = 3
    }
}

-- Tier 4 Mobs (Expert Zone)
MobData[4] = {
    ["FrostGiant"] = {
        Name = "Frost Giant",
        Level = 20,
        BaseHP = 600,
        BaseDamage = 60,
        BaseScore = 250,
        LootPool = "EpicDrop",
        MobID = "FrostGiant",
        Armor = 70,
        AggroRange = 40,
        ReturnDistance = 60,
        AttackRange = 10,
        AttackCooldown = 2.0,
        MoveSpeed = 8,
        JumpHeight = 2
    },
    ["VoidSerpent"] = {
        Name = "Void Serpent",
        Level = 25,
        BaseHP = 500,
        BaseDamage = 80,
        BaseScore = 300,
        LootPool = "EpicDrop",
        MobID = "VoidSerpent",
        Armor = 45,
        AggroRange = 55,
        ReturnDistance = 75,
        AttackRange = 6,
        AttackCooldown = 0.6,
        MoveSpeed = 18,
        JumpHeight = 2
    }
}

-- Tier 5 Mobs (Boss Zone)
MobData[5] = {
    ["DragonWhelp"] = {
        Name = "Dragon Whelp",
        Level = 35,
        BaseHP = 1200,
        BaseDamage = 120,
        BaseScore = 600,
        LootPool = "LegendaryDrop",
        MobID = "DragonWhelp",
        Armor = 110,
        AggroRange = 60,
        ReturnDistance = 80,
        AttackRange = 12,
        AttackCooldown = 1.0,
        MoveSpeed = 14,
        JumpHeight = 4
    },
    ["AncientGuardian"] = {
        Name = "Ancient Guardian",
        Level = 40,
        BaseHP = 2000,
        BaseDamage = 150,
        BaseScore = 1000,
        LootPool = "LegendaryDrop",
        MobID = "AncientGuardian",
        Armor = 180,
        AggroRange = 50,
        ReturnDistance = 70,
        AttackRange = 15,
        AttackCooldown = 2.5,
        MoveSpeed = 6,
        JumpHeight = 1
    }
}

-- Tier 1 additional mobs
MobData[1]["SmallSkeleton"] = {
	Name = "Small Skeleton",
	Level = 2,
	BaseHP = 55,
	BaseDamage = 14,
	BaseScore = 13,
	LootPool = "CommonDrop",
	MobID = "SmallSkeleton",
	Armor = 4,
	AggroRange = 32,
	ReturnDistance = 52,
	AttackRange = 5,
	AttackCooldown = 0.9,
	MoveSpeed = 9,
	JumpHeight = 0,
	KnockbackMultiplier = 1.0,
	SoundClass = "Skeleton", -- MobClassRegistry opt-in: cycles 4 bone-rattle hit
		-- sounds via SkeletonMobClass:GetHitSoundId() instead of the shared
		-- default glass sfx (MobClass:GetHitSoundId).
}

-- Named Elite variants (separate MobID entries)
MobData[1]["PlainsSlimeElite"] = {
    Name = "Plains Slime Elite",
    Level = 5,
    BaseHP = 200,
    BaseDamage = 15,
    BaseScore = 100,
    LootPool = "EliteDrop",
    MobID = "PlainsSlimeElite",
    Armor = 12,
    AggroRange = 35,
    ReturnDistance = 55,
    AttackRange = 6,
    AttackCooldown = 0.5,
    MoveSpeed = 10,
    JumpHeight = 3,
    KnockbackMultiplier = 0.5,
    MovementClass = "Slime" -- see PlainsSlime's MovementClass comment above
}

-- First "named elite" boss-type mob (2026-09-14, direct request): a
-- distinct character (skinned-mesh import, own name/lore) rather than a
-- stat-buffed reskin of an existing mob like PlainsSlimeElite/CaveBatElite
-- above. Spawns through the SAME elite-zone pity/chance machinery in
-- MobManager.server.lua (set this MobID as a zone's EliteMobId via the F8
-- dev tool's Elite Mob Zone picker) or on demand via the F8 dev tool's
-- "Force Spawn Elite" button. Stats are a first-pass placeholder tuned to
-- roughly slot between the existing T1 named elites and MiasmaBoss (T1
-- dungeon boss, 1500 HP solo) -- adjust once playtested.
-- Deliberately NOT IsBoss=true: that flag ends the current DUNGEON RUN on
-- death (see LootService.lua), which is wrong for an open-world elite.
--
-- Playtest pass (2026-09-14, direct request: "nerf the speed ... by 20%,
-- add a de-agro range as well, right now it infinitely chases"):
--   * MoveSpeed 10 -> 8 (-20%).
--   * ReturnDistance is the de-aggro/leash range -- MobClass.lua's
--     HandleWalking already gives up and returns to Idle once the mob has
--     wandered past ReturnDistance from its own spawn point AND is no
--     longer within LEASH_GRACE_PROXIMITY (12 studs) of its target for
--     LEASH_GRACE_DURATION (1s) -- this is the exact same shared leash
--     every regular mob uses, just tuned per-mob via this one field. It was
--     already set (150) but read as "infinite" in practice because Kane's
--     old speed let it stay glued to the player (well within the 12-stud
--     grace radius) indefinitely, so the countdown never started -- the
--     speed nerf above is what actually lets a fleeing player pull ahead
--     far enough to trigger it. Tightened 150 -> 90 (AggroRange + 30,
--     matching the ratio regular T1 mobs use) on top of that so it also
--     gives up sooner once a player genuinely disengages.
MobData[1]["Kane"] = {
    Name = "Kane the Enraged",
    Level = 21,
    BaseHP = 500,
    BaseDamage = 50, -- ordinary swing (MobAnimConfig.Kane.Attack), before player armor
    ScaleWithLevel = false, -- these are final stats, not multiplied by level 21
    CombatClass = "Moveset",
    InterruptAttackOnHit = false, -- ordinary hits still damage/push Kane during his combo
    -- Authored specials layered over the ordinary attack state machine -- see
    -- MobMovesetBehaviour. Between combos Kane swings like any other mob
    -- (BaseDamage above), which is what replaced his old proximity/"thorns"
    -- damage: no more taking a hit just for standing next to him.
    Moveset = {
        {
            Id = "AxeCombo3Hit", -- MobAnimConfig.Kane.Moveset key
            Damage = 100, -- per connecting swing, before player armor
            SourceDuration = 4, -- approved frames 1-97 at 24 FPS
            HitTimes = { 17 / 24, 39 / 24, 66 / 24 }, -- impacts at frames 18, 40, 67
            -- Gap between combos, measured from the end of the clip. This is
            -- what leaves room for ordinary swings: at AttackCooldown = 1.2
            -- below, a 5s gap is about three normal swings between combos.
            -- Set it to AttackCooldown or lower and he chains combos forever
            -- and never swings normally.
            Cooldown = 5,
            RangeMultiplier = 1.25, -- 6.25 studs against Kane's 5-stud AttackRange
            HalfAngleDegrees = 70, -- simple 140-degree frontal sweep
            HitWindow = 0.2, -- skip stale strikes after a long server stall
            Speed = 2, -- playback rate: the 4s combo now runs in 2s
            -- Ground telegraph style (RS/MobTelegraphConfig). Drawn as this
            -- entry's REAL hitbox -- RangeMultiplier and HalfAngleDegrees above
            -- are what the client renders -- so the 140-degree cone visibly
            -- teaches that you can step behind him during the combo.
            Telegraph = "KaneCombo",
        },
    },
    BaseScore = 500,
    LootPool = "EliteDrop",
    MobID = "Kane",
    Armor = 20,
    AggroRange = 60,
    ReturnDistance = 90,
    -- Was 8, which read as an oversized "thorns" bubble next to the 5 every
    -- ordinary T1 mob uses (the test is root-to-root, so 8 left ~5 studs of
    -- air between bodies). Matched to the Plains Slime 2026-09-17.
    AttackRange = 5,
    AttackCooldown = 1.2,
    -- Ground telegraph for the ORDINARY swing (RS/MobTelegraphConfig). Its
    -- length is the windup itself -- AttackHitDelay 19/24 over AttackSpeed 2,
    -- so about 0.40s of warning. No cone: IsTargetWithinMeleeReach applies none
    -- to the base attack, so this correctly draws a full ring.
    Telegraph = "KaneSlash",
    MoveSpeed = 10.4, -- was 8; +30% 2026-09-17 so he can actually close distance
    JumpHeight = 0,
    -- Was 0 ("immovable", copied from the MiasmaBoss pattern) -- but Kane is
    -- an open-world named elite, not a dungeon boss, and per direct request
    -- ("kane isnt taking any knockback... should just be a slight push")
    -- should react like every other mob. Matched to the existing named-elite
    -- convention (PlainsSlimeElite/CaveBatElite both use 0.5) rather than
    -- the plain-mob default of 1.0, so Kane's bulk still reads as sturdier
    -- than a common mob while clearly no longer immovable. ApplyKnockback in
    -- MobClass.lua already only nudges position via PivotTo between AI
    -- ticks -- it never touches the Animator/AnimationTrack, so this can't
    -- interrupt Kane's walk animation.
    KnockbackMultiplier = 0.5,
    -- How hard KANE SHOVES YOU -- the opposite direction from
    -- KnockbackMultiplier above, which is how hard he is shoved. Scales
    -- MobClass's baseline player hitstun impulse (4 studs/s out, 8 up), so a
    -- hit from him throws you about three times as far as an ordinary mob's.
    -- Applies to his ordinary swing AND to every impact of the axe combo --
    -- both land through ApplyPlayerHitstun, and the Moveset entry sets no
    -- override of its own.
    PlayerKnockbackMultiplier = 3,
    -- Marks this as a distinct named-elite CHARACTER (own model/lore), not a
    -- stat-reskin like PlainsSlimeElite. Read by MobClass.lua to (a) skip
    -- the normal floating nameplate/HP-bar billboard (MobHPBarUI) in favor
    -- of the dedicated top-middle BossHealthBar.client.lua UI, and (b)
    -- attach the orange "named elite" outline Highlight to the model.
    IsNamedElite = true,
}

MobData[2]["CaveBatElite"] = {
    Name = "Cave Bat Elite",
    Level = 10,
    BaseHP = 400,
    BaseDamage = 25,
    BaseScore = 200,
    LootPool = "EliteDrop",
    MobID = "CaveBatElite",
    Armor = 22,
    AggroRange = 50,
    ReturnDistance = 70,
    AttackRange = 5,
    AttackCooldown = 0.5,
    MoveSpeed = 16,
    JumpHeight = 4,
    KnockbackMultiplier = 0.5
}

-- Helper function to retrieve mob stats
function MobData.GetMobStats(tier, mobId)
    if not MobData[tier] then
        return nil
    end
    return MobData[tier][mobId]
end

-- Helper function to get all mobs in a tier
function MobData.GetTierMobs(tier)
    return MobData[tier]
end

-- Helper function to find a mob by MobID across all tiers
function MobData.FindMobById(mobId)
    for tier = 1, 5 do
        local mobData = MobData.GetMobStats(tier, mobId)
        if mobData then
            return mobData, tier
        end
    end
    return nil
end

-- Sanity-check every mob entry at load time so a hand-authored copy/paste
-- error (a MobID field that doesn't match its own table key, or a missing
-- required stat) surfaces immediately in the output window instead of
-- silently producing a broken mob later. Purely diagnostic -- never mutates
-- or removes an entry, so it's safe to leave running as the table grows.
local REQUIRED_FIELDS = {
    "Name", "Level", "BaseHP", "BaseDamage", "BaseScore", "LootPool", "MobID",
    "Armor", "AggroRange", "ReturnDistance", "AttackRange", "AttackCooldown", "MoveSpeed",
}

local function validateMobEntry(tier, key, entry)
    if entry.MobID ~= key then
        warn(string.format(
            "[MobData] Tier %d entry %q has MobID %q (does not match its table key -- likely a copy/paste mistake)",
            tier, key, tostring(entry.MobID)
        ))
    end
    for _, field in ipairs(REQUIRED_FIELDS) do
        if entry[field] == nil then
            warn(string.format("[MobData] Tier %d %q is missing required field %q", tier, key, field))
        end
    end
end

for tier = 1, 5 do
    for key, entry in pairs(MobData[tier]) do
        validateMobEntry(tier, key, entry)
    end
end

return MobData
