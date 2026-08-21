--[[
	Server death penalties (Minecraft-style hotbar model -- no weapon-mirror slot 1):
	- Drop unprotected inventory rows into world loot pickups.
	- What's "protected" is decided entirely by DungeonDeathProtection, not inline here --
	  this module only owns the drop loop, coin loss, and world-loot mechanics.
	- Apply a wallet coin loss.
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))
local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))
local Hotbar = require(ServerScriptService:WaitForChild("DungeonEquippedHotbar"))
local WorldLoot = require(ServerScriptService:WaitForChild("DungeonWorldLootService"))
local DeathProtection = require(ServerScriptService:WaitForChild("DungeonDeathProtection"))

local COIN_LOSS_PERCENT = 0.15

local DurabilityService = require(ServerScriptService:WaitForChild("DurabilityService"))
local HungerData        = require(ServerScriptService:WaitForChild("HungerData"))

local DungeonDeathLoot = {}

local function stripReferencesToMissing(profile)
	if type(profile.bagSlots) == "table" then
		for i = 1, Types.BAG_SLOT_COUNT do
			local u = profile.bagSlots[i]
			if type(u) == "string" and u ~= "" and (not profile.inventory[u]) then
				profile.bagSlots[i] = nil
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
	local equippedSlotByUuid = DeathProtection.BuildEquippedSlotByUuid(profile)

	if type(inv) == "table" then
		for uuid, item in pairs(inv) do
			if type(uuid) == "string" and not DeathProtection.ShouldKeepOnDeath(uuid, item, equippedSlotByUuid) then
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
	HungerData.addHunger(player, 100)
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
