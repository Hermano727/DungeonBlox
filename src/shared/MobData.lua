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
        MoveSpeed = 2,
        JumpHeight = 3
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
    KnockbackMultiplier = 0.5
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