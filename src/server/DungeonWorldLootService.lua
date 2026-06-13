local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))

local LOOT_FOLDER_NAME = "DungeonDeathLoot"
local LOOT_LIFETIME_SEC = 180

local DungeonWorldLootService = {}

local activeLoot = {} -- [lootId] = { items=array, promptConnection=RBXScriptConnection? }

local function getLootFolder()
	local folder = Workspace:FindFirstChild(LOOT_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = LOOT_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function cloneTable(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end
	local out = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			out[k] = cloneTable(v)
		else
			out[k] = v
		end
	end
	return out
end

local function disconnectLoot(lootId)
	local entry = activeLoot[lootId]
	if not entry then
		return
	end
	if entry.promptConnection then
		entry.promptConnection:Disconnect()
		entry.promptConnection = nil
	end
	activeLoot[lootId] = nil
end

function DungeonWorldLootService.RemoveLoot(lootId)
	local folder = getLootFolder()
	local model = folder:FindFirstChild(lootId)
	if model then
		model:Destroy()
	end
	disconnectLoot(lootId)
end

function DungeonWorldLootService.GrantLootToPlayer(player, items)
	if not player or not player.Parent then
		return false, "bad_player"
	end
	if type(items) ~= "table" or #items <= 0 then
		return false, "no_items"
	end

	local profile = DungeonProfile.Load(player)
	if not profile then
		return false, "no_profile"
	end

	for _, item in ipairs(items) do
		if type(item) == "table" then
			local newItem = cloneTable(item)
			local newUuid = HttpService:GenerateGUID(false)
			newItem.uuid = newUuid
			profile.inventory[newUuid] = newItem
		end
	end

	DungeonProfile.PushProfile(player)
	return true, nil
end

local function ensureWeaponDropToolPrefabOnItem(item)
	if type(item) ~= "table" or item.type ~= "Weapon" then
		return
	end
	if item.toolPrefabName == "WoodenSword" and type(item.tags) == "table" then
		for _, tag in ipairs(item.tags) do
			if tag == "Sword" then
				item.toolPrefabName = "Low_tier_sword"
				return
			end
		end
	end
	if type(item.toolPrefabName) == "string" and item.toolPrefabName ~= "" then
		return
	end
	if type(item.tags) ~= "table" then
		return
	end
	local map = ItemConfig.WEAPON_DROP_PREFAB_BY_TYPE
	for _, tag in ipairs(item.tags) do
		local n = map[tag]
		if type(n) == "string" and n ~= "" then
			item.toolPrefabName = n
			return
		end
	end
end

function DungeonWorldLootService.SpawnDeathLoot(originPosition, droppedItems)
	if type(droppedItems) ~= "table" or #droppedItems <= 0 then
		return nil
	end
	for _, it in ipairs(droppedItems) do
		ensureWeaponDropToolPrefabOnItem(it)
	end
	if typeof(originPosition) ~= "Vector3" then
		originPosition = Vector3.new(0, 8, 0)
	end

	local lootId = "DeathLoot_" .. HttpService:GenerateGUID(false)
	local lootFolder = getLootFolder()

	local model = Instance.new("Model")
	model.Name = lootId
	model.Parent = lootFolder

	local anchor = Instance.new("Part")
	anchor.Name = "Pickup"
	anchor.Size = Vector3.new(2, 2, 2)
	anchor.Shape = Enum.PartType.Ball
	anchor.Material = Enum.Material.Neon
	anchor.Color = Color3.fromRGB(245, 186, 72)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = true
	anchor.Position = originPosition + Vector3.new((math.random() - 0.5) * 4, 1.5, (math.random() - 0.5) * 4)
	anchor.Parent = model

	model.PrimaryPart = anchor

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LootPrompt"
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = "Dropped Loot"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	activeLoot[lootId] = {
		items = droppedItems,
		promptConnection = nil,
	}

	activeLoot[lootId].promptConnection = prompt.Triggered:Connect(function(player)
		local entry = activeLoot[lootId]
		if not entry then
			return
		end
		local ok = DungeonWorldLootService.GrantLootToPlayer(player, entry.items)
		if ok then
			DungeonWorldLootService.RemoveLoot(lootId)
		end
	end)

	task.delay(LOOT_LIFETIME_SEC, function()
		DungeonWorldLootService.RemoveLoot(lootId)
	end)

	return lootId
end

return DungeonWorldLootService
