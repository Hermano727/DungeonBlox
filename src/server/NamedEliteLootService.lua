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
      * real rarities (Rare/Epic/Legendary), OR a Mythic built by MythicItemBuilder when the
        entry names one (`Mythic = <MythicItemDefs key>`, Kane's set): same world-loot delivery,
        the item itself comes from the Mythic factory,
      * a def with `OneDrop` rolls ONCE per kill and drops at most one piece (weighted pick);
        otherwise each entry rolls its own chance.
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config        = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local EliteLootDefs = require(ReplicatedStorage:WaitForChild("NamedEliteLootDefs"))
local Types         = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ItemIdentity  = require(ReplicatedStorage:WaitForChild("ItemIdentity"))
local ItemGenerator = require(ServerScriptService:WaitForChild("ItemGenerator"))
local WorldLoot     = require(ServerScriptService:WaitForChild("WorldLootService"))
local MythicItemBuilder = require(ServerScriptService:WaitForChild("MythicItemBuilder"))

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
    -- A Mythic piece (Kane's set) is built by the Mythic factory from its MythicItemDefs entry.
    if entry.Mythic then
        return MythicItemBuilder.Build(entry.Mythic)
    end
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

-- Builds one entry's piece and drops it on the ground for the killing player. Returns the new
-- scatterIndex (bumped only if something actually spawned).
local function dropEntry(entry, mob, killingBlowPlayer, deathPos, scatterIndex, tier, level, denominator)
    local item = NamedEliteLootService.BuildItem(entry, tier, level)
    if not item then return scatterIndex end
    local okTpl, template = pcall(function() return item:toGrantTemplate() end)
    if not okTpl or type(template) ~= "table" then
        warn("[NamedEliteLootService] toGrantTemplate failed for " .. tostring(entry.Key))
        return scatterIndex
    end
    -- `def` is what lets ItemStatRanges find this piece's AUTHORED substat window instead of
    -- the generic per-tier one; without the def key a rebalance clamp would gut it.
    ItemIdentity.Stamp(template, {
        by = killingBlowPlayer,
        kind = ItemIdentity.SOURCE.NAMED_ELITE,
        src = mob.MobID,
        def = entry.Key,
    })
    local valid, errTpl = Types.ValidateItemTemplate(template)
    if not valid then
        warn("[NamedEliteLootService] invalid template for " .. tostring(entry.Key) .. ": " .. tostring(errTpl))
        return scatterIndex
    end
    local okSpawn, lootId = pcall(function()
        return WorldLoot.SpawnMobDrop(deathPos, killingBlowPlayer.UserId, {
            kind = "item_template", template = template,
        }, scatterIndex)
    end)
    if okSpawn and lootId then
        print(string.format("[NamedEliteLootService] %s dropped %s (%s, 1/%d) for %s",
            tostring(mob.MobID), tostring(template.name),
            entry.Mythic and "Mythic" or (tostring(entry.EquivalentRarity) .. " equivalent"), denominator, killingBlowPlayer.Name))
        -- Every Mythic is announced server-wide, the moment it hits the ground.
        if entry.Mythic then
            local MythicBroadcast = require(ServerScriptService:WaitForChild("MythicBroadcast"))
            MythicBroadcast.Announce(killingBlowPlayer, template, mob.Stats and mob.Stats.Name or mob.MobID)
        end
        return scatterIndex + 1
    end
    return scatterIndex
end

-- One pool entry picked by `Weight` (default 1).
local function pickWeighted(pool)
    local total = 0
    for _, entry in ipairs(pool) do total += (tonumber(entry.Weight) or 1) end
    if total <= 0 then return nil end
    local r = math.random() * total
    for _, entry in ipairs(pool) do
        r -= (tonumber(entry.Weight) or 1)
        if r <= 0 then return entry end
    end
    return pool[#pool]
end

-- Drops the elite's gear on the ground for the killing player. Two modes (see NamedEliteLootDefs):
--   * `OneDrop` set: ONE roll per kill at that chance; a hit drops exactly one piece, picked by
--     Weight. Never more than one piece per kill (Kane's Mythic set).
--   * otherwise every pool entry rolls its own chance independently.
-- Returns the new scatterIndex so the caller can keep spacing pickups apart, same contract as
-- LootService's other drop helpers.
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
    local pool = defs.Pool or {}

    if defs.OneDrop then
        local chance, denominator = EliteLootDefs.DropChance(tier, defs.OneDrop.EquivalentRarity)
        if math.random() < chance then
            local entry = pickWeighted(pool)
            if entry then
                scatterIndex = dropEntry(entry, mob, killingBlowPlayer, deathPos, scatterIndex, tier, level, denominator)
            end
        end
        return scatterIndex
    end

    for _, entry in ipairs(pool) do
        local chance, denominator = EliteLootDefs.DropChance(tier, entry.EquivalentRarity)
        if math.random() < chance then
            scatterIndex = dropEntry(entry, mob, killingBlowPlayer, deathPos, scatterIndex, tier, level, denominator)
        end
    end
    return scatterIndex
end

return NamedEliteLootService
