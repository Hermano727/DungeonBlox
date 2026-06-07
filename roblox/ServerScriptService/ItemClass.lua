--[[
    ItemClass
    OOP wrapper for a generated item instance.
    Stores the rolled base stats and provides getFinalStats() which applies
    weapon-type multipliers. Call toGrantTemplate() to get a table that
    DungeonProfileService.GrantItem() will accept.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("ItemConfig"))

local ItemClass = {}
ItemClass.__index = ItemClass

--[[
    ItemClass.new(data)

    data fields:
      name        string    display name
      itemType    string    "Weapon" | "Armor"
      weaponType  string?   "Sword"|"Scythe"|"Axe"|"Mace"|"Bow"
      armorSlot   string?   "Helm"|"Chest"|"Legs"|"Boots"
      rarity      string    "Common" ... "Legendary"
      tier        number    1-5
      level       number    item level used for scaling
      baseStats   table     { dmg=N } for weapons, { hp=N, hps=N } for armor
      substats    table     array of { id, label, value, valueType }
]]
function ItemClass.new(data)
    return setmetatable({
        name       = data.name,
        itemType   = data.itemType,
        weaponType = data.weaponType,
        armorSlot  = data.armorSlot,
        rarity     = data.rarity,
        tier       = data.tier,
        level      = data.level,
        baseStats  = data.baseStats,
        substats   = data.substats,
    }, ItemClass)
end

--[[
    getFinalStats()
    Returns a copy of stats after applying weapon-type multipliers.
    Multipliers hit: base dmg, and any elemDmg substat.
    Everything else (HP, HP/s, other substats) is untouched.
]]
function ItemClass:getFinalStats()
    local stats = {}
    for k, v in pairs(self.baseStats) do
        stats[k] = v
    end

    local mult = (self.weaponType and Config.WEAPON_MULTIPLIERS[self.weaponType]) or 1.0

    if stats.dmgMin then stats.dmgMin = math.floor(stats.dmgMin * mult) end
    if stats.dmgMax then stats.dmgMax = math.floor(stats.dmgMax * mult) end

    local finalSubs = {}
    for _, sub in ipairs(self.substats) do
        local val = sub.value
        -- elemDmg also gets the weapon multiplier per spec
        if sub.id == "elemDmg" then
            val = math.floor(val * mult)
        end
        table.insert(finalSubs, {
            id        = sub.id,
            label     = sub.label,
            value     = val,
            valueType = sub.valueType,
        })
    end
    stats.substats = finalSubs

    return stats
end

--[[
    toGrantTemplate()
    Returns a table compatible with DungeonProfileService.GrantItem(player, template, 1).
    All stats (base + substats) are packed into the subStats dict.
]]
function ItemClass:toGrantTemplate()
    local final = self:getFinalStats()

    local subStatsDict = {}
    if final.dmgMin     then subStatsDict.dmgMin     = final.dmgMin     end
    if final.dmgMax     then subStatsDict.dmgMax     = final.dmgMax     end
    if final.hp         then subStatsDict.hp         = final.hp         end
    if final.hps        then subStatsDict.hps        = final.hps        end
    if final.armor      then subStatsDict.armor      = final.armor      end
    if final.energy     then subStatsDict.energy     = final.energy     end
    if final.dmgRed     then subStatsDict.dmgRed     = final.dmgRed     end
    if final._rawDmgMin then subStatsDict._rawDmgMin = final._rawDmgMin end
    if final._rawDmgMax then subStatsDict._rawDmgMax = final._rawDmgMax end
    if final._rawHp     then subStatsDict._rawHp     = final._rawHp     end
    for _, sub in ipairs(final.substats or {}) do
        subStatsDict[sub.id] = sub.value
    end

    local tags = {}
    if self.weaponType then table.insert(tags, self.weaponType) end
    if self.armorSlot  then table.insert(tags, self.armorSlot)  end

    local toolPrefabName = nil
    if self.itemType == "Weapon" and self.weaponType then
        toolPrefabName = Config.WEAPON_DROP_PREFAB_BY_TYPE[self.weaponType]
    end

    return {
        name         = self.name,
        type         = self.itemType,
        rarity       = self.rarity,
        tier         = self.tier,
        level        = self.level,
        enchantLevel = 0,
        subStats     = subStatsDict,
        -- Armor pieces use their specific slot (Helm/Chest/Legs/Boots), not generic "Armor"
        equipSlot    = self.weaponType and "Weapon" or (self.armorSlot or "Armor"),
        tags         = tags,
        toolPrefabName = toolPrefabName,
    }
end

--[[
    debugPrint()
    Convenience for testing in the output window.
]]
function ItemClass:debugPrint()
    local final = self:getFinalStats()
    print(string.format("[ItemClass] %s | T%d L%d | %s",
        self.name, self.tier, self.level, self.rarity))
    if final.dmgMin then
        local mult = Config.WEAPON_MULTIPLIERS[self.weaponType] or 1
        print(string.format("  DMG: %d-%d  (%.2fx %s)", final.dmgMin, final.dmgMax, mult, self.weaponType or "none"))
    end
    if final.hp then
        print(string.format("  HP: %d   HP/s: %d   Armor: %d   Energy/s: %.2f",
            final.hp, final.hps, final.armor or 0, final.energy or 0))
    end
    for _, sub in ipairs(final.substats) do
        local suffix = sub.valueType == "pct" and "%" or ""
        print(string.format("  %s: %d%s", sub.label, sub.value, suffix))
    end
end

return ItemClass
