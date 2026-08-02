-- PlayerBootstrap
-- Orchestrates the player join / leave flow. Order matters:
--   1. Load profile (acquires session lock, populates sessionData)
--   2. Derive stats (MaxHP from Vitality, etc.)
--   3. Hook into character spawns
--   4. Equip default kit on fresh profiles
--   5. Replicate inventory + combat snapshot to the client

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerData       = require(ServerScriptService:WaitForChild("PlayerDataManager"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))

local DEFAULT_KIT = {
	{ "TrainingSword", 1 },
	{ "WoodenSword",   1 },
	{ "LeatherHelm",   1 },
	{ "LeatherChest",  1 },
	{ "MinorPotion",    3 },
}

local function deriveStats(profile)
	profile.Combat.MaxHP = 100 + (profile.RPG.Vitality * 5)
	if profile.Combat.HP <= 0 or profile.Combat.HP > profile.Combat.MaxHP then
		profile.Combat.HP = profile.Combat.MaxHP
	end
end

local function onCharacter(player, character)
	local profile = PlayerData.Get(player)
	if not profile then return end

	local hum = character:WaitForChild("Humanoid")
	hum.MaxHealth = profile.Combat.MaxHP
	hum.Health    = profile.Combat.HP

	-- Mirror Humanoid HP onto the profile so any legacy damage source
	-- that bypasses DamageService still leaves the profile in sync.
	hum.HealthChanged:Connect(function(newHp)
		profile.Combat.HP = newHp
	end)

	-- Grant WoodenSword to existing players who don't have one yet
	local hasWoodenSword = false
	for _, slot in pairs(profile.Inventory) do
		if slot.ItemId == "WoodenSword" then
			hasWoodenSword = true
			break
		end
	end
	if not hasWoodenSword then
		InventoryService.AddItem(player, "WoodenSword", 1)
		-- Auto-equip it if player has no weapon equipped
		if not profile.Equipped.Weapon then
			for slotIdx, slot in pairs(profile.Inventory) do
				if slot.ItemId == "WoodenSword" then
					profile.Equipped.Weapon = slotIdx
					break
				end
			end
		end
		InventoryService.Replicate(player)
	end
end

local function equipDefaultKit(player)
	for _, entry in ipairs(DEFAULT_KIT) do
		InventoryService.AddItem(player, entry[1], entry[2])
	end

	local profile = PlayerData.Get(player); if not profile then return end
	for slotIdx, slot in pairs(profile.Inventory) do
		if slot.ItemId == "TrainingSword" or slot.ItemId == "WoodenSword" then
			profile.Equipped.Weapon = slotIdx
		elseif slot.ItemId == "LeatherHelm" then
			profile.Equipped.Helm = slotIdx
		elseif slot.ItemId == "LeatherChest" then
			profile.Equipped.Chest = slotIdx
		end
	end
	InventoryService.RecomputeArmor(player)
end

local function onPlayerAdded(player)
	local profile = PlayerData.Load(player)
	if not profile then
		-- Load() already kicked them if the lock could not be acquired.
		return
	end

	deriveStats(profile)

	player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
	if player.Character then onCharacter(player, player.Character) end

	local hasAnything = next(profile.Inventory) ~= nil
	if not hasAnything then
		equipDefaultKit(player)
	else
		InventoryService.RecomputeArmor(player)
	end

	InventoryService.Replicate(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	PlayerData.Release(player)
end)

for _, plr in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, plr)
end

print("[PlayerBootstrap] ready")
