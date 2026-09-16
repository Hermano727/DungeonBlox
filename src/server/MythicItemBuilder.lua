--[[
    MythicItemBuilder  -- ServerScriptService
    Generates at BaseStatsAs (Legendary lvl 21 for Miasma), overwrites
    substats with the def's fixed list, then stamps rarity = "Mythic".
    Mythics never roll a random substat count.
]]
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config        = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local MythicDefs    = require(ReplicatedStorage:WaitForChild("MythicItemDefs"))
local ItemGenerator = require(ServerScriptService:WaitForChild("ItemGenerator"))

local MythicItemBuilder = {}

local function findEffect(id)
    for _, tbl in ipairs({ Config.WEAPON_EFFECTS, Config.ARMOR_EFFECTS, Config.ARMOR_BONUS_EFFECTS }) do
        for _, e in ipairs(tbl or {}) do
            if e.id == id then return e end
        end
    end
    return nil
end

local function standardRoll(id, tier, rarity)
    local eff = findEffect(id)
    if not eff then return nil end
    if not eff.ranges then
        local mult = Config.RARITY_SUBSTAT_MULT[rarity] or 1.45
        local sr = Config.ARMOR_SUBSTAT_RANGE and Config.ARMOR_SUBSTAT_RANGE[math.clamp(tier,1,5)]
        if sr then
            local lo, hi = sr[1], sr[2]
            return math.floor((lo + math.random() * (hi - lo)) * mult + 0.5)
        end
        return nil
    end
    local r = eff.ranges[math.clamp(tier, 1, 5)]
    if not r then return nil end
    return math.floor((r[1] + math.random() * (r[2] - r[1])) + 0.5)
end

function MythicItemBuilder.Build(itemKey)
    local def = MythicDefs.GetItem(itemKey)
    if not def then warn("[MythicItemBuilder] unknown key:", itemKey) return nil end

    local base = def.BaseStatsAs or { tier = 1, rarity = "Legendary", level = 21 }
    local opts = { tier = base.tier, rarity = base.rarity, level = base.level, substatCount = 0 }
    if def.Kind == "Weapon" then opts.weaponType = def.WeaponType else opts.armorSlot = def.ArmorSlot end

    local ok, item = pcall(function() return ItemGenerator.generate(opts) end)
    if not ok or not item then warn("[MythicItemBuilder] generate failed:", item) return nil end

    local subs = {}
    for _, s in ipairs(def.SubStats or {}) do
        local value
        if s.useStandardRoll then value = standardRoll(s.id, base.tier, base.rarity)
        elseif s.min and s.max then value = math.floor(s.min + math.random() * (s.max - s.min) + 0.5) end
        if value then subs[s.id] = value end
    end

    if type(item) == "table" then
        item.subStats  = subs
        item.rarity    = MythicDefs.RARITY_NAME
        item.isMythic  = true
        item.mythicKey = itemKey
        if def.DisplayName then item.name = def.DisplayName end
    end
    return item
end

function MythicItemBuilder.TryRollForMob(mobId)
    local spec = MythicDefs.GetDropSpec(mobId)
    if not spec then return nil end
    if math.random() >= (spec.Chance or 0) then return nil end
    local key = MythicDefs.PickFromPool(mobId)
    if not key then return nil end
    return MythicItemBuilder.Build(key)
end

return MythicItemBuilder
