--[[
    HearthstoneRegistry  (server-only)
    Merges static seed locations from HearthstoneConfig with dynamic entries
    persisted in DataStore. Call Load() once at server startup.
]]

local DataStoreService  = game:GetService("DataStoreService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HearthstoneConfig = require(ReplicatedStorage:WaitForChild("HearthstoneConfig"))

local HearthstoneRegistry = {}
local cache = {}  -- { [id] = { id, name, cost, position: Vector3 } }
local ds

local function getDS()
    if not ds then
        ds = DataStoreService:GetDataStore(HearthstoneConfig.DATASTORE_KEY)
    end
    return ds
end

function HearthstoneRegistry.Load()
    -- Seed first so seeds always exist even if DataStore is empty or errors.
    for _, loc in ipairs(HearthstoneConfig.SEED_LOCATIONS) do
        cache[loc.id] = {
            id       = loc.id,
            name     = loc.name,
            cost     = loc.cost,
            position = loc.position,
            icon     = loc.icon or "",
        }
    end
    local ok, saved = pcall(function()
        return getDS():GetAsync("locations")
    end)
    if ok and type(saved) == "table" then
        for id, loc in pairs(saved) do
            if type(id) == "string" and type(loc) == "table" then
                cache[id] = {
                    id       = id,
                    name     = tostring(loc.name or id),
                    cost     = tonumber(loc.cost) or 0,
                    position = Vector3.new(
                        tonumber(loc.px) or 0,
                        tonumber(loc.py) or 4,
                        tonumber(loc.pz) or 0
                    ),
                }
            end
        end
    elseif not ok then
        warn("[HearthstoneRegistry] DataStore load failed: " .. tostring(saved))
    end
end

-- Returns a serializable array of all locations (positions as px/py/pz numbers).
function HearthstoneRegistry.GetAllLocations()
    local arr = {}
    for _, loc in pairs(cache) do
        table.insert(arr, {
            id   = loc.id,
            name = loc.name,
            cost = loc.cost,
            icon = loc.icon or "",
            px   = loc.position.X,
            py   = loc.position.Y,
            pz   = loc.position.Z,
        })
    end
    return arr
end

function HearthstoneRegistry.GetLocation(id)
    return cache[id]
end

-- Adds a new location, persists non-seed entries to DataStore.
function HearthstoneRegistry.AddLocation(id, name, cost, position)
    if type(id) ~= "string" or id == "" then return false, "bad_id" end
    if type(name) ~= "string" or name == "" then return false, "bad_name" end
    cost = tonumber(cost) or 0
    if typeof(position) ~= "Vector3" then return false, "bad_position" end

    cache[id] = { id = id, name = name, cost = cost, position = position }

    -- Build the save table from non-seed entries only.
    local seedIds = {}
    for _, seed in ipairs(HearthstoneConfig.SEED_LOCATIONS) do
        seedIds[seed.id] = true
    end
    local toSave = {}
    for lid, loc in pairs(cache) do
        if not seedIds[lid] then
            toSave[lid] = {
                name = loc.name,
                cost = loc.cost,
                px   = loc.position.X,
                py   = loc.position.Y,
                pz   = loc.position.Z,
            }
        end
    end

    local ok, err = pcall(function()
        getDS():SetAsync("locations", toSave)
    end)
    if not ok then
        warn("[HearthstoneRegistry] DataStore write failed: " .. tostring(err))
        return false, "datastore_error"
    end
    return true
end

-- Removes a location from the cache and DataStore. Seed locations are protected.
function HearthstoneRegistry.RemoveLocation(id)
    if type(id) ~= "string" or id == "" then return false, "bad_id" end

    local seedIds = {}
    for _, seed in ipairs(HearthstoneConfig.SEED_LOCATIONS) do
        seedIds[seed.id] = true
    end
    if seedIds[id] then return false, "cannot_delete_seed" end
    if not cache[id] then return false, "not_found" end

    cache[id] = nil

    local toSave = {}
    for lid, loc in pairs(cache) do
        if not seedIds[lid] then
            toSave[lid] = {
                name = loc.name,
                cost = loc.cost,
                px   = loc.position.X,
                py   = loc.position.Y,
                pz   = loc.position.Z,
            }
        end
    end
    local ok, err = pcall(function()
        getDS():SetAsync("locations", toSave)
    end)
    if not ok then
        warn("[HearthstoneRegistry] DataStore delete failed: " .. tostring(err))
        return false, "datastore_error"
    end
    return true
end

-- Generates a slug-style id from a display name.
function HearthstoneRegistry.SlugId(name)
    local slug = name:lower():gsub("%s+", "_"):gsub("[^%a%d_]", ""):sub(1, 16)
    local uid  = HttpService:GenerateGUID(false):sub(1, 4):lower()
    return slug .. "_" .. uid
end

return HearthstoneRegistry
