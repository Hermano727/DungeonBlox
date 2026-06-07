--[[
	Server death penalties:
	- Drop unprotected inventory rows into world loot pickups.
	- Keep explicitly protected items.
	- Keep equipped armor.
	- Keep melee weapon currently placed in hotbar.
	- Apply a wallet coin loss.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))
local Hotbar = require(ServerScriptService:WaitForChild("DungeonEquippedHotbar"))
local WorldLoot = require(ServerScriptService:WaitForChild("DungeonWorldLootService"))

local COIN_LOSS_PERCENT = 0.15

local DurabilityService = require(ServerScriptService:WaitForChild("DurabilityService"))

local DungeonDeathLoot = {}

local function isMeleeItem(item)
	if type(item) ~= "table" then
		return false
	end
	if type(item.itemId) == "string" and item.itemId ~= "" then
		return ItemDefinitions.IsMeleeWeapon(item.itemId)
	end
	if item.type ~= "Weapon" then
		return false
	end
	local n = string.lower(tostring(item.name or ""))
	local wt = string.lower(tostring(item.weaponType or ""))
	if string.find(n, "bow", 1, true) or string.find(wt, "bow", 1, true) then
		return false
	end
	return true
end

local function isProfessionItem(item)
	if type(item) ~= "table" then
		return false
	end
	if type(item.itemId) == "string" and item.itemId ~= "" then
		return ItemDefinitions.IsProtectedOnDeath(item.itemId)
	end
	local slot = item.equipSlot
	return slot == "Pickaxe" or slot == "FishingSpear"
end

local function buildUuidSets(profile)
	local hotbarSet = {}
	if type(profile.hotbar) == "table" then
		for i = 1, 9 do
			local u = profile.hotbar[i]
			if type(u) == "string" and u ~= "" then
				hotbarSet[u] = true
			end
		end
	end

	local equippedSet = {}
	if type(profile.equipped) == "table" then
		for slot, u in pairs(profile.equipped) do
			if type(u) == "string" and u ~= "" then
				equippedSet[u] = slot
			end
		end
	end

	return hotbarSet, equippedSet
end

local function shouldKeepItem(item, uuid, hotbarSet, equippedSet)
	if type(item) ~= "table" then
		return true
	end

	if type(item.itemId) == "string" and item.itemId ~= "" and ItemDefinitions.IsProtectedOnDeath(item.itemId) then
		return true
	end

	if isProfessionItem(item) then
		return true
	end

	local eqSlot = equippedSet[uuid]
	if eqSlot and item.type == "Armor" then
		return true
	end

	if hotbarSet[uuid] and isMeleeItem(item) then
		return true
	end

	return false
end

local function stripReferencesToMissing(profile)
	if type(profile.hotbar) == "table" then
		for i = 1, 9 do
			local u = profile.hotbar[i]
			if type(u) == "string" and u ~= "" and (not profile.inventory[u]) then
				profile.hotbar[i] = nil
			end
		end
	end

	if type(profile.equipped) == "table" then
		for slot, u in pairs(profile.equipped) do
			if type(u) == "string" and u ~= "" and (not profile.inventory[u]) then
				profile.equipped[slot] = nil
			end
		end
	end
end

function DungeonDeathLoot.applyToPlayer(player, deathPosition)
	if not player or not player.Parent then
		return
	end
	local profile = DungeonProfile.Load(player)
	if not profile then
		return
	end

	-- Apply durability death penalty before dropping loot
	DurabilityService.applyDeathPenalty(profile, player)

	local droppedItems = {}
	local inv = profile.inventory
	local hotbarSet, equippedSet = buildUuidSets(profile)

	if type(inv) == "table" then
		for uuid, item in pairs(inv) do
			if type(uuid) == "string" and not shouldKeepItem(item, uuid, hotbarSet, equippedSet) then
				table.insert(droppedItems, item)
				inv[uuid] = nil
			end
		end
	end

	stripReferencesToMissing(profile)

	if type(profile.currencies) == "table" and type(profile.currencies.Coins) == "number" then
		local loss = math.floor(profile.currencies.Coins * COIN_LOSS_PERCENT)
		profile.currencies.Coins = math.max(0, profile.currencies.Coins - loss)
	end

	if #droppedItems > 0 then
		WorldLoot.SpawnDeathLoot(deathPosition, droppedItems)
	end

	local StatsService = require(ServerScriptService:WaitForChild("DungeonStatsService"))
	StatsService.RecomputeRuntimeHp(profile)
	DungeonProfile.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
end

local function hookCharacter(player, char)
	local hum = char:WaitForChild("Humanoid", 20)
	if not hum then
		return
	end
	hum.Died:Connect(function()
		local deathPosition = Vector3.new(0, 8, 0)
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			deathPosition = root.Position
		end
		DungeonDeathLoot.applyToPlayer(player, deathPosition)
	end)
end

function DungeonDeathLoot.bindPlayer(player)
	player.CharacterAdded:Connect(function(char)
		hookCharacter(player, char)
	end)
end

function DungeonDeathLoot.start()
	Players.PlayerAdded:Connect(function(player)
		DungeonDeathLoot.bindPlayer(player)
		if player.Character then
			task.defer(function()
				hookCharacter(player, player.Character)
			end)
		end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		DungeonDeathLoot.bindPlayer(p)
		if p.Character then
			task.defer(function()
				hookCharacter(p, p.Character)
			end)
		end
	end
end

return DungeonDeathLoot
