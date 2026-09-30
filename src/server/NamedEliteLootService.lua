--[[
    NamedEliteLootService  -- ServerScriptService

    Rolls and builds a named elite's signature gear on death. Data lives in
    RS/NamedEliteLootDefs; the term "high roll <rarity> equivalent" is defined
    in docs/named-elite-loot.md.

    Deliberately NOT the dungeon-boss Mythic path (DungeonBossLootService):
      * per-KILLING-PLAYER, not every player in the server,
      * drops on the ground as world loot like any other overworld gear, rather
        than granting straight to inventory (dungeon rewards surface in the run
        summary; an overworld elite's don't),
      * real rarities (Rare/Epic/Legendary), not the above-Legendary Mythic tier.
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config        = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local EliteLootDefs = require(ReplicatedStorage:WaitForChild("NamedEliteLootDefs"))
local Types         = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ItemIdentity  = require(ReplicatedStorage:WaitForChild("ItemIdentity"))
local ItemGenerator = require(ServerScriptService:WaitForChild("ItemGenerator"))
local WorldLoot     = require(ServerScriptService:WaitForChild("WorldLootService"))

local NamedEliteLootService = {}

-- Top of a substat's own STANDARD roll for this tier/rarity, for substats whose
-- value doesn't come from a hand-written range. str/vit/int/dex read
-- ARMOR_SUBSTAT_RANGE and take the rarity multiplier; everything else has its
-- own per-tier `ranges`.
local function highRollStandardValue(id, tier, rarity)
    local effect = Config.FindSubstatEffect(id)
    if not effect then return nil end
    local t = math.clamp(tier, 1, 5)
    if effect.ranges then
        local range = effect.ranges[t]
        return range and math.floor(range[2]) or nil
    end
    local range = Config.ARMOR_SUBSTAT_RANGE and Config.ARMOR_SUBSTAT_RANGE[t]
    if not range then return nil end
    local mult = Config.RARITY_SUBSTAT_MULT[rarity] or 1.0
    return math.floor(range[2] * mult)
end

-- Returns the ARRAY-OF-RECORDS shape ItemClass expects on `.substats`
-- ({ id, label, value, valueType }), not a flat dict. ItemClass:toGrantTemplate
-- flattens it into the template's `subStats` dict itself -- writing a dict here
-- and assigning it to `item.subStats` silently dropped every authored substat,
-- because toGrantTemplate only ever reads the lowercase `.substats` array.
-- `label`/`valueType` come from ItemConfig.FindSubstatEffect so nothing is
-- hand-duplicated when a substat definition changes.
local function rollAuthoredSubStats(entry, tier, rarity)
    local subs = {}
    for _, spec in ipairs(entry.SubStats or {}) do
        local value
        if spec.highRollStandard then
            value = highRollStandardValue(spec.id, tier, rarity)
        elseif spec.min ~= nil and spec.max ~= nil then
            -- Authored range: rolled normally between the two, since the author
            -- already picked the window they want (6-9% crit, etc). "High roll"
            -- applies to the BASE stats, not to these.
            value = math.floor(spec.min + math.random() * (spec.max - spec.min) + 0.5)
        end
        if value ~= nil then
            local effect = Config.FindSubstatEffect(spec.id)
            table.insert(subs, {
                id        = spec.id,
                label     = effect and effect.label or spec.id,
                value     = value,
                valueType = effect and effect.valueType or "flat",
            })
        end
    end
    return subs
end

-- Builds one pool entry's item, or nil if generation failed.
function NamedEliteLootService.BuildItem(entry, tier, level)
    local rarity = entry.EquivalentRarity or "Rare"
    local options = {
        tier         = tier,
        rarity       = rarity,
        level        = level,
        substatCount = 0,  -- authored below; never roll random ones on top
        highRoll     = true, -- top of the base-stat range: see docs/named-elite-loot.md
    }
    if entry.Kind == "Weapon" then
        options.weaponType = entry.WeaponType
    else
        options.armorSlot = entry.ArmorSlot
    end

    local ok, item = pcall(ItemGenerator.generate, options)
    if not ok or type(item) ~= "table" then
        warn("[NamedEliteLootService] generate failed for " .. tostring(entry.Key) .. ": " .. tostring(item))
        return nil
    end

    -- `.substats` (lowercase) is ItemClass's real field; `.subStats` is the flat
    -- dict that only exists on the granted TEMPLATE, produced by toGrantTemplate.
    item.substats = rollAuthoredSubStats(entry, tier, rarity)
    if type(entry.DisplayName) == "string" and entry.DisplayName ~= "" then
        item.name = entry.DisplayName
    end
    return item
end

-- Rolls every pool entry independently and drops what hits on the ground for
-- the killing player. Returns the new scatterIndex so the caller can keep
-- spacing pickups apart, same contract as LootService's other drop helpers.
function NamedEliteLootService.OnNamedEliteKilled(mob, killingBlowPlayer, deathPos, scatterIndex)
    scatterIndex = scatterIndex or 0
    if not mob or not killingBlowPlayer or not killingBlowPlayer.Parent then
        return scatterIndex
    end
    local defs = EliteLootDefs.GetDrops(mob.MobID)
    if not defs then return scatterIndex end
    if typeof(deathPos) ~= "Vector3" then return scatterIndex end

    local tier = tonumber(defs.Tier) or mob.Tier or 1
    local level = tonumber(defs.Level) or (mob.Stats and mob.Stats.Level) or 1

    for _, entry in ipairs(defs.Pool or {}) do
        local chance, denominator = EliteLootDefs.DropChance(tier, entry.EquivalentRarity)
        if math.random() < chance then
            local item = NamedEliteLootService.BuildItem(entry, tier, level)
            if item then
                local okTpl, template = pcall(function() return item:toGrantTemplate() end)
                if type(template) == "table" then
                    -- `def` is what lets ItemStatRanges find this piece's AUTHORED
                    -- substat window instead of the generic per-tier one. Kane's
                    -- Axe rolls 6-9% critical where the generic T1 window is 2-3;
                    -- without the def key a rebalance clamp would gut it.
                    ItemIdentity.Stamp(template, {
                        by = killingBlowPlayer,
                        kind = ItemIdentity.SOURCE.NAMED_ELITE,
                        src = mob.MobID,
                        def = entry.Key,
                    })
                end
                if not okTpl or type(template) ~= "table" then
                    warn("[NamedEliteLootService] toGrantTemplate failed for " .. tostring(entry.Key))
                else
                    local valid, errTpl = Types.ValidateItemTemplate(template)
                    if not valid then
                        warn("[NamedEliteLootService] invalid template for " .. tostring(entry.Key) .. ": " .. tostring(errTpl))
                    else
                        local okSpawn, lootId = pcall(function()
                            return WorldLoot.SpawnMobDrop(deathPos, killingBlowPlayer.UserId, {
                                kind = "item_template", template = template,
                            }, scatterIndex)
                        end)
                        if okSpawn and lootId then
                            scatterIndex += 1
                            print(string.format("[NamedEliteLootService] %s dropped %s (%s equivalent, 1/%d) for %s",
                                tostring(mob.MobID), tostring(template.name),
                                tostring(entry.EquivalentRarity), denominator, killingBlowPlayer.Name))
                        end
                    end
                end
            end
        end
    end
    return scatterIndex
end

return NamedEliteLootService
