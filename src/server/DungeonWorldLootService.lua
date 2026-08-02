local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Types = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))

local DEATH_LOOT_FOLDER = "DungeonDeathLoot"
local MOB_LOOT_FOLDER = "DungeonMobLoot"
local LOOT_LIFETIME_SEC = 180
local PICKUP_DISTANCE = 12
local FLOAT_AMP = 0.28
local FLOAT_FREQ = 1.75
local COIN_AURA_COLOR = Color3.fromRGB(255, 215, 100)

local DungeonWorldLootService = {}

local activeLoot = {} -- [lootId] = entry

local function getLootFolder(folderName)
	local folder = Workspace:FindFirstChild(folderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = Workspace
	return folder
end

local function ensureItemDropNotify()
	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	if not ge then
		return nil
	end
	local ev = ge:FindFirstChild("ItemDropNotify")
	if ev and ev:IsA("RemoteEvent") then
		return ev
	end
	return nil
end

local function rarityColor(rarity)
	return Types.GetRarityColor(rarity)
end

local function attachAura(anchor, color)
	anchor.Color = color

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 1.4
	light.Range = 10
	light.Parent = anchor

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "LootAura"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Rate = 16
	pe.Lifetime = NumberRange.new(0.35, 0.8)
	pe.Speed = NumberRange.new(0.2, 1.2)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-90, 90)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 0.85
	pe.Parent = anchor
end

local function attachLabel(anchor, text, textColor)
	local bb = Instance.new("BillboardGui")
	bb.Name = "LootLabel"
	bb.Size = UDim2.fromOffset(120, 36)
	bb.StudsOffset = Vector3.new(0, 1.6, 0)
	bb.AlwaysOnTop = true
	bb.Parent = anchor

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 14
	lbl.TextColor3 = textColor
	lbl.TextStrokeTransparency = 0.35
	lbl.TextWrapped = true
	lbl.Text = text
	lbl.Parent = bb
end

local function scatterOffset(slotIndex)
	local slot = math.max(0, math.floor(tonumber(slotIndex) or 0))
	local angle = slot * 1.35 + (math.random() * 0.6)
	local radius = 1.4 + slot * 0.55
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function startFloat(model, anchor, basePosition)
	local t0 = tick()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not model.Parent or not anchor.Parent then
			if conn then
				conn:Disconnect()
			end
			return
		end
		local bob = math.sin((tick() - t0) * FLOAT_FREQ) * FLOAT_AMP
		anchor.Position = basePosition + Vector3.new(0, bob, 0)
	end)
	return conn
end

local function attachTooltipData(anchor, ownerUserId, template)
	if type(template) ~= "table" then
		return
	end
	local itemType = template.type
	if itemType ~= "Weapon" and itemType ~= "Armor" then
		return
	end
	local payload = {
		name = template.name,
		rarity = template.rarity,
		type = template.type,
		tier = template.tier,
		level = template.level,
		enchantLevel = template.enchantLevel,
		itemId = template.itemId,
		subStats = template.subStats,
		scrollProtected = template.scrollProtected,
	}
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if not ok or type(encoded) ~= "string" then
		return
	end
	anchor:SetAttribute("LootTooltipItem", true)
	anchor:SetAttribute("LootOwnerUserId", ownerUserId)
	anchor:SetAttribute("LootItemJson", encoded)
end

local function createPickupPrompt(anchor, actionText, objectText)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LootPrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PICKUP_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	return prompt
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

local function ensureWeaponDropToolPrefabOnItem(item)
	if type(item) ~= "table" or item.type ~= "Weapon" then
		return
	end
	if item.toolPrefabName == "WoodenSword" and type(item.tags) == "table" then
		for _, tag in ipairs(item.tags) do
			if tag == "Sword" then
				item.toolPrefabName = "TrainingSword"
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

local function disconnectLoot(lootId)
	local entry = activeLoot[lootId]
	if not entry then
		return
	end
	if entry.promptConnection then
		entry.promptConnection:Disconnect()
		entry.promptConnection = nil
	end
	if entry.floatConnection then
		entry.floatConnection:Disconnect()
		entry.floatConnection = nil
	end
	activeLoot[lootId] = nil
end

function DungeonWorldLootService.RemoveLoot(lootId, folderName)
	folderName = folderName or DEATH_LOOT_FOLDER
	local folder = getLootFolder(folderName)
	local model = folder:FindFirstChild(lootId)
	if model then
		model:Destroy()
	end
	disconnectLoot(lootId)
end

local function firePickupBanner(player, payload)
	if not player or not player.Parent or type(payload) ~= "table" then
		return
	end
	local ev = ensureItemDropNotify()
	if ev then
		ev:FireClient(player, payload)
	end
end

local function grantMobDrop(player, entry)
	if entry.kind == "coins" then
		local granted, err = DungeonProfile.GrantItemId(player, "Coins", entry.amount)
		if granted then
			firePickupBanner(player, {
				kind = "Coins",
				amount = entry.amount,
				coinFind = entry.coinFind,
			})
		end
		return granted, err
	elseif entry.kind == "item_template" then
		local granted, err = DungeonProfile.GrantItem(player, entry.template, 1)
		if granted then
			firePickupBanner(player, {
				name = entry.template.name,
				rarity = entry.template.rarity,
				tier = entry.template.tier,
				type = entry.template.type,
			})
		end
		return granted, err
	elseif entry.kind == "item_id" then
		local granted, err = DungeonProfile.GrantItemId(player, entry.itemId, entry.count or 1)
		if granted then
			firePickupBanner(player, entry.notifyPayload or {
				kind = "KeyFragment",
				name = entry.itemId,
			})
		end
		return granted, err
	end
	return false, "unknown_drop"
end

local function bindMobPickup(lootId, model, anchor, entry)
	local prompt = createPickupPrompt(anchor, "Pick Up", entry.promptObjectText or "Loot")
	entry.promptConnection = prompt.Triggered:Connect(function(player)
		local live = activeLoot[lootId]
		if not live then
			return
		end
		if live.ownerUserId and player.UserId ~= live.ownerUserId then
			return
		end
		local ok = select(1, grantMobDrop(player, live))
		if ok then
			DungeonWorldLootService.RemoveLoot(lootId, MOB_LOOT_FOLDER)
		end
	end)
end

function DungeonWorldLootService.SpawnMobDrop(originPosition, ownerUserId, dropSpec, scatterIndex)
	if typeof(originPosition) ~= "Vector3" or type(dropSpec) ~= "table" then
		return nil
	end

	local kind = dropSpec.kind
	if kind ~= "coins" and kind ~= "item_template" and kind ~= "item_id" then
		return nil
	end

	local auraColor = COIN_AURA_COLOR
	local labelText = "Loot"
	local promptObjectText = "Loot"
	local orbSize = Vector3.new(1.6, 1.6, 1.6)

	if kind == "coins" then
		local amount = math.max(1, math.floor(tonumber(dropSpec.amount) or 0))
		dropSpec.amount = amount
		labelText = string.format("%d Coins", amount)
		promptObjectText = labelText
	elseif kind == "item_template" then
		local template = dropSpec.template
		if type(template) ~= "table" then
			return nil
		end
		ensureWeaponDropToolPrefabOnItem(template)
		auraColor = rarityColor(template.rarity)
		labelText = tostring(template.name or "Item")
		if template.type == "Weapon" or template.type == "Armor" then
			promptObjectText = ""
		else
			promptObjectText = labelText
		end
		orbSize = Vector3.new(1.8, 1.8, 1.8)
	elseif kind == "item_id" then
		local itemId = dropSpec.itemId
		local def = type(itemId) == "string" and ItemDefinitions.Get(itemId) or nil
		if not def then
			return nil
		end
		dropSpec.count = math.max(1, math.floor(tonumber(dropSpec.count) or 1))
		auraColor = rarityColor(def.Rarity or "Common")
		labelText = def.DisplayName or itemId
		promptObjectText = labelText
	end

	local lootId = "MobLoot_" .. HttpService:GenerateGUID(false)
	local lootFolder = getLootFolder(MOB_LOOT_FOLDER)

	local model = Instance.new("Model")
	model.Name = lootId
	model.Parent = lootFolder

	local basePosition = originPosition + scatterOffset(scatterIndex) + Vector3.new(0, 1.4, 0)

	local anchor = Instance.new("Part")
	anchor.Name = "Pickup"
	anchor.Size = orbSize
	anchor.Shape = Enum.PartType.Ball
	anchor.Material = Enum.Material.Neon
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = true
	anchor.Position = basePosition
	anchor.Parent = model
	model.PrimaryPart = anchor

	attachAura(anchor, auraColor)
	attachLabel(anchor, labelText, auraColor)
	if kind == "item_template" then
		attachTooltipData(anchor, ownerUserId, dropSpec.template)
	end

	local entry = {
		kind = kind,
		ownerUserId = ownerUserId,
		amount = dropSpec.amount,
		coinFind = dropSpec.coinFind,
		template = dropSpec.template,
		itemId = dropSpec.itemId,
		count = dropSpec.count,
		notifyPayload = dropSpec.notifyPayload,
		promptObjectText = promptObjectText,
		floatConnection = startFloat(model, anchor, basePosition),
	}
	activeLoot[lootId] = entry

	bindMobPickup(lootId, model, anchor, entry)

	task.delay(LOOT_LIFETIME_SEC, function()
		DungeonWorldLootService.RemoveLoot(lootId, MOB_LOOT_FOLDER)
	end)

	return lootId
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
			DungeonProfile.PlaceItemInFirstEmptySlot(profile, newUuid)
		end
	end

	DungeonProfile.PushProfile(player)
	return true, nil
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
	local lootFolder = getLootFolder(DEATH_LOOT_FOLDER)

	local model = Instance.new("Model")
	model.Name = lootId
	model.Parent = lootFolder

	local basePosition = originPosition + Vector3.new((math.random() - 0.5) * 4, 1.5, (math.random() - 0.5) * 4)

	local anchor = Instance.new("Part")
	anchor.Name = "Pickup"
	anchor.Size = Vector3.new(2, 2, 2)
	anchor.Shape = Enum.PartType.Ball
	anchor.Material = Enum.Material.Neon
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = true
	anchor.Position = basePosition
	anchor.Parent = model

	model.PrimaryPart = anchor

	attachAura(anchor, Color3.fromRGB(245, 186, 72))
	attachLabel(anchor, "Dropped Loot", Color3.fromRGB(245, 186, 72))

	local prompt = createPickupPrompt(anchor, "Pick Up", "Dropped Loot")

	activeLoot[lootId] = {
		kind = "death_bundle",
		items = droppedItems,
		promptConnection = nil,
		floatConnection = startFloat(model, anchor, basePosition),
	}

	activeLoot[lootId].promptConnection = prompt.Triggered:Connect(function(player)
		local entry = activeLoot[lootId]
		if not entry then
			return
		end
		local ok = DungeonWorldLootService.GrantLootToPlayer(player, entry.items)
		if ok then
			DungeonWorldLootService.RemoveLoot(lootId, DEATH_LOOT_FOLDER)
		end
	end)

	task.delay(LOOT_LIFETIME_SEC, function()
		DungeonWorldLootService.RemoveLoot(lootId, DEATH_LOOT_FOLDER)
	end)

	return lootId
end

return DungeonWorldLootService