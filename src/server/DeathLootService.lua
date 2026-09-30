--[[
	Server death penalties (Minecraft-style hotbar model -- no weapon-mirror slot 1):
	- Drop unprotected inventory rows into world loot pickups.
	- What's "protected" is decided entirely by DeathProtection, not inline here --
	  this module only owns the drop loop, coin loss, and world-loot mechanics.
	- Apply a wallet coin loss.

	DUNGEON DEATHS KEEP THE INVENTORY. Dying inside a dungeon run drops nothing:
	the run is cashed out instead (DungeonRunService.EndRunFor(player, "died")),
	which grants whatever the player earned and banks anything that does not fit.
	The other penalties -- durability, the wallet coin loss, hunger -- still apply.

	This module is the ONLY Humanoid.Died hook for player deaths, on purpose.
	DungeonRunService used to have its own, and the two raced on every death:
	whichever ran second decided whether the inventory dropped, since the run
	ends (and "in a run?" flips to false) the moment it is cashed out. Deciding
	"in a run?" once, here, before either thing happens, is what makes it stable.
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local Hotbar = require(ServerScriptService:WaitForChild("EquippedHotbar"))
local WorldLoot = require(ServerScriptService:WaitForChild("WorldLootService"))
local DeathProtection = require(ServerScriptService:WaitForChild("DeathProtection"))
local InventoryAudit = require(ServerScriptService:WaitForChild("InventoryAudit"))

local COIN_LOSS_PERCENT = 0.15

local DurabilityService = require(ServerScriptService:WaitForChild("DurabilityService"))
local HungerData        = require(ServerScriptService:WaitForChild("HungerData"))

local DeathLootService = {}

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

-- Whether `player` is inside a dungeon run right now. Required lazily: it is
-- only needed at the moment of death, and keeps this module free of a
-- load-order dependency on the dungeon services.
local function isInDungeonRun(player)
	local ok, score = pcall(function()
		return require(ServerScriptService:WaitForChild("DungeonScoreService", 5))
	end)
	return ok and score and score.IsInRun and score.IsInRun(player) == true
end

local function cashOutDungeonRun(player)
	local ok, runSvc = pcall(function()
		return require(ServerScriptService:WaitForChild("DungeonRunService", 5))
	end)
	if ok and runSvc and runSvc.EndRunFor then
		local okEnd, err = pcall(runSvc.EndRunFor, player, "died")
		if not okEnd then
			warn("[DeathLootService] dungeon cash-out failed for " .. player.Name .. ": " .. tostring(err))
		end
	end
end

-- `keepInventory` skips the item drop entirely (a dungeon death); every other
-- penalty below still runs.
function DeathLootService.applyToPlayer(player, deathPosition, keepInventory)
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

	-- A death drop is the one EXPECTED bulk removal: tell the wipe audit, or it pages someone.
	if keepInventory then
		InventoryAudit.Note(player, "died in a dungeon run (inventory kept)")
	else
		InventoryAudit.Sanction(player, "death drop")
	end
	if type(inv) == "table" and not keepInventory then
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

	local StatsService = require(ServerScriptService:WaitForChild("StatsService"))
	StatsService.RecomputeRuntimeHp(profile)
	HungerData.addHunger(player, 100)
	DungeonProfile.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
end

-- Dying clears every debuff. Character-bound statuses (enchant bleed/blind/slow) already die
-- with the character model; this clears what's bound to the PLAYER and would otherwise follow
-- them into the next life: Miasma poison stacks (and the valve they were working).
function DeathLootService.cleanse(player)
	-- The encounter's own death handling first (drops them from any valve they held).
	local ok, err = pcall(function()
		local encounters = require(ServerScriptService:WaitForChild("MiasmaEncounterService", 2))
		if encounters and encounters.OnPlayerDied then encounters.OnPlayerDied(player) end
	end)
	if not ok then warn("[DeathLootService] encounter death hook failed for " .. player.Name .. ": " .. tostring(err)) end
	-- Then the full cleanse: every debuff and effect (see SSS/StatusCleanse).
	local okCleanse, cleanseErr = pcall(function()
		require(ServerScriptService:WaitForChild("StatusCleanse", 2)).All(player, "Death")
	end)
	if not okCleanse then warn("[DeathLootService] death cleanse failed for " .. player.Name .. ": " .. tostring(cleanseErr)) end
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
		-- FIRST, and protected: dying is a full cleanse, and a boss-room death hands the player
		-- to spectating. Both used to run after the loot/cash-out below, so anything failing
		-- there silently skipped them (poison survived death, no spectator view).
		DeathLootService.cleanse(player)
		local okInst, instances = pcall(function()
			return require(ServerScriptService:WaitForChild("DungeonInstanceService", 5))
		end)
		if okInst and instances and instances.OnPlayerDied then
			local okDied, err = pcall(instances.OnPlayerDied, player)
			if not okDied then warn("[DeathLootService] spectate hand-off failed for " .. player.Name .. ": " .. tostring(err)) end
		end
		-- Decided ONCE, before anything below can end the run and flip it.
		local inRun = isInDungeonRun(player)
		DeathLootService.applyToPlayer(player, deathPosition, inRun)
		if inRun then
			cashOutDungeonRun(player)
		end
	end)
end

function DeathLootService.bindPlayer(player)
	player.CharacterAdded:Connect(function(char)
		hookCharacter(player, char)
	end)
end

function DeathLootService.start()
	Players.PlayerAdded:Connect(function(player)
		DeathLootService.bindPlayer(player)
		if player.Character then
			task.defer(function()
				hookCharacter(player, player.Character)
			end)
		end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		DeathLootService.bindPlayer(p)
		if p.Character then
			task.defer(function()
				hookCharacter(p, p.Character)
			end)
		end
	end
end

return DeathLootService
