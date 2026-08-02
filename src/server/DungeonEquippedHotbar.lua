--[[
	Spawns Tool instances into Backpack for dungeon hotbar slots 1-9 and legacy equipped slots.
	Uses ServerStorage.DungeonToolPrefabsArchive; prefab name from item.toolPrefabName or ItemDefinitions.ToolPrefabName.
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local EnergyConfig = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local WeaponData = require(ReplicatedStorage:WaitForChild("WeaponData"))

local ARCHIVE_NAME = "DungeonToolPrefabsArchive"

-- Once per server session, replace weapon-drop Tool templates in the archive with fresh
-- clones from StarterPack so edits to e.g. Low_tier_sword propagate without stale meshes.
local sessionWeaponDropPrefabsResynced = false
local sessionPickaxePrefabResynced = false

local DungeonEquippedHotbar = {}

local function hotbarSlotUuid(hb, i)
	if type(hb) ~= "table" then return nil end
	i = math.floor(tonumber(i) or -1)
	if i < 1 or i > 9 then return nil end
	local v = hb[i]
	if type(v) == "string" and v ~= "" then return v end
	v = hb[tostring(i)]
	if type(v) == "string" and v ~= "" then return v end
	return nil
end



local function ensureMountSaddleTemplate(folder)
	if not folder or not folder:IsA("Folder") then
		return
	end
	if folder:FindFirstChild("DungeonMountSaddleTool") then
		return
	end

	local tool = Instance.new("Tool")
	tool.Name = "DungeonMountSaddleTool"
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 0.35, 0.95)
	handle.Color = Color3.fromRGB(160, 120, 80)
	handle.Material = Enum.Material.Fabric
	handle.Parent = tool

	local ls = Instance.new("LocalScript")
	ls.Name = "MountSaddleActivate"
	ls.Parent = tool
	ls.Source = [=[local t = script.Parent
local RS = game:GetService("ReplicatedStorage")
local function go()
	local u = t:GetAttribute("DungeonItemUuid")
	if type(u) ~= "string" or u == "" then return end
	local ge = RS:FindFirstChild("GameEvents")
	if not ge then return end
	local ev = ge:FindFirstChild("MountRequest")
	if ev and ev:IsA("RemoteEvent") then
		ev:FireServer(u)
	end
end
t.Activated:Connect(go)
]=]

	tool.Parent = folder
end

-- Fallback prefab for Food items that don't define their own ToolPrefabName. Single shared template;
-- per-item attributes (DungeonItemUuid, FoodTimeToEat, FoodItemId) are set when cloned.
--
-- Runtime cannot write LocalScript.Source ("lacking capability PluginOrOpenCloud"), so the eat-client
-- LocalScript is authored at edit time as ReplicatedStorage.EatFoodClientTemplate and cloned here.
local function ensureDefaultFoodTool(folder)
	if not folder or not folder:IsA("Folder") then
		return
	end
	if folder:FindFirstChild("DefaultFoodTool") then
		return
	end

	local tmpl = ReplicatedStorage:FindFirstChild("EatFoodClientTemplate")
	if not tmpl or not tmpl:IsA("LocalScript") then
		warn("[DungeonEquippedHotbar] Missing ReplicatedStorage.EatFoodClientTemplate (LocalScript); food eat will not work")
		return
	end

	local tool = Instance.new("Tool")
	tool.Name = "DefaultFoodTool"
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 0.6, 0.9)
	handle.Color = Color3.fromRGB(190, 140, 80)
	handle.Material = Enum.Material.SmoothPlastic
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	local ls = tmpl:Clone()
	ls.Name = "EatFoodClient"
	ls.Disabled = false
	ls.Parent = tool

	tool.Parent = folder
end

-- Fallback prefab for Consumable items (potions) that don't define their own ToolPrefabName.
-- Mirrors ensureDefaultFoodTool: drinking is right-click-while-held, no hold duration.
local function ensureDefaultPotionTool(folder)
	if not folder or not folder:IsA("Folder") then
		return
	end
	if folder:FindFirstChild("DefaultPotionTool") then
		return
	end

	local tmpl = ReplicatedStorage:FindFirstChild("DrinkPotionClientTemplate")
	if not tmpl or not tmpl:IsA("LocalScript") then
		warn("[DungeonEquippedHotbar] Missing ReplicatedStorage.DrinkPotionClientTemplate (LocalScript); potion drinking will not work")
		return
	end

	local tool = Instance.new("Tool")
	tool.Name = "DefaultPotionTool"
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 0.7, 0.5)
	handle.Color = Color3.fromRGB(150, 60, 180)
	handle.Material = Enum.Material.Glass
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	local ls = tmpl:Clone()
	ls.Name = "DrinkPotionClient"
	ls.Disabled = false
	ls.Parent = tool

	tool.Parent = folder
end

local function inferWeaponDropToolPrefabFromTags(item)
	if type(item) ~= "table" or item.type ~= "Weapon" then
		return nil
	end
	if type(item.tags) ~= "table" then
		return nil
	end
	local map = ItemConfig.WEAPON_DROP_PREFAB_BY_TYPE
	for _, tag in ipairs(item.tags) do
		local n = map[tag]
		if type(n) == "string" and n ~= "" then
			return n
		end
	end
	return nil
end

local function ensureStarterWeaponDropPrefabs(folder)
	if not folder or not folder:IsA("Folder") then
		return
	end
	local sp = game:GetService("StarterPack")
	local seen = {}
	local map = ItemConfig.WEAPON_DROP_PREFAB_BY_TYPE
	local resync = not sessionWeaponDropPrefabsResynced
	for _, prefabName in pairs(map) do
		if type(prefabName) == "string" and prefabName ~= "" and not seen[prefabName] then
			seen[prefabName] = true
			local existing = folder:FindFirstChild(prefabName)
			local src = sp:FindFirstChild(prefabName)
			if src and src:IsA("Tool") then
				if resync and existing then
					existing:Destroy()
					existing = nil
				end
				if not existing then
					local c = src:Clone()
					c.Name = prefabName
					c.CanBeDropped = false
					c.Parent = folder
				end
			elseif not existing then
				warn("[DungeonEquippedHotbar] StarterPack missing Tool for weapon drop prefab:", prefabName)
			end
		end
	end
	sessionWeaponDropPrefabsResynced = true
end

local function ensureStarterPickaxePrefab(folder)
	if not folder or not folder:IsA("Folder") then
		return
	end
	local sp = game:GetService("StarterPack")
	local src = sp:FindFirstChild("WoodenPickaxe")
	if not src or not src:IsA("Tool") then
		return
	end
	local existing = folder:FindFirstChild("WoodenPickaxe")
	local resync = not sessionPickaxePrefabResynced
	if resync and existing then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		local c = src:Clone()
		c.Name = "WoodenPickaxe"
		c.CanBeDropped = false
		c.Parent = folder
	end
	sessionPickaxePrefabResynced = true
end



-- pcall the template builders: a single template failure (e.g. Roblox's runtime LocalScript.Source
-- capability restriction) must NOT prevent the archive folder from being returned, or callers like
-- DungeonBackpackImport.ImportPlayerBackpack abort and the starter pack never loads.
function DungeonEquippedHotbar.ensureArchiveFolder()
	local folder = ServerStorage:FindFirstChild(ARCHIVE_NAME)
	if folder and folder:IsA("Folder") then
		pcall(ensureMountSaddleTemplate, folder)
		pcall(ensureDefaultFoodTool, folder)
		pcall(ensureDefaultPotionTool, folder)
		pcall(ensureStarterWeaponDropPrefabs, folder)
		return folder
	end
	if folder then
		folder:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = ARCHIVE_NAME
	f.Parent = ServerStorage
	pcall(ensureMountSaddleTemplate, f)
	pcall(ensureDefaultFoodTool, f)
	pcall(ensureDefaultPotionTool, f)
	pcall(ensureStarterWeaponDropPrefabs, f)
	return f
end

local function clearTaggedTools(container)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("DungeonEquipped") == true then
			child:Destroy()
		end
	end
end

function DungeonEquippedHotbar.clearDungeonTools(player)
	if not player then
		return
	end
	clearTaggedTools(player:FindFirstChildOfClass("Backpack"))
	local char = player.Character
	if char then
		clearTaggedTools(char)
	end
end

local function toolPrefabNameForItem(item)
	if type(item) ~= "table" then
		return nil
	end
	local name = nil
	if type(item.toolPrefabName) == "string" and item.toolPrefabName ~= "" then
		name = item.toolPrefabName
	end
	if not name then
		name = inferWeaponDropToolPrefabFromTags(item)
	end
	if not name and type(item.itemId) == "string" then
		local def = ItemDefinitions.Get(item.itemId)
		if def then
			if type(def.ToolPrefabName) == "string" and def.ToolPrefabName ~= "" then
				name = def.ToolPrefabName
			end
			if not name and def.Kind == "Food" then
				name = "DefaultFoodTool"
			end
			if not name and def.Kind == "Consumable" then
				name = "DefaultPotionTool"
			end
		end
	end
	-- Legacy: sword loot used WoodenSword as the mesh prefab; all swords use Low_tier_sword now.
	if name == "WoodenSword" and item.type == "Weapon" and type(item.tags) == "table" then
		for _, tag in ipairs(item.tags) do
			if tag == "Sword" then
				return "TrainingSword"
			end
		end
	end
	return name
end

function DungeonEquippedHotbar.syncFromProfile(player, profile)
	if not player or not profile or player.Parent == nil then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 3)
	if not backpack then
		return
	end

	DungeonEquippedHotbar.clearDungeonTools(player)

	local archive = DungeonEquippedHotbar.ensureArchiveFolder()
	if not archive then
		return
	end

	local inv = profile.inventory
	if type(inv) ~= "table" then
		return
	end

	local spawned = {}
	local function trySpawn(metaSlot, uuid)
		if type(uuid) ~= "string" or uuid == "" or spawned[uuid] then
			return
		end
		local item = inv[uuid]
		local prefabName = toolPrefabNameForItem(item)
		if not prefabName then
			return
		end
		local prefab = archive:FindFirstChild(prefabName)
		if not prefab or not prefab:IsA("Tool") then
			warn("[DungeonEquippedHotbar] Missing prefab Tool for:", prefabName)
			return
		end
		local tool = prefab:Clone()
		tool:SetAttribute("DungeonEquipped", true)
		tool:SetAttribute("DungeonEquipSlot", metaSlot)
		tool:SetAttribute("DungeonItemUuid", uuid)
		tool.CanBeDropped = false

		if item and type(item.itemId) == "string" and item.itemId ~= "" then
			tool:SetAttribute("DungeonItemId", item.itemId)
		end

		if item then
			local wpnId = nil
			local def = (type(item.itemId) == "string" and item.itemId ~= "") and ItemDefinitions.Get(item.itemId) or nil
			if def then
				if type(def.DisplayName) == "string" and def.DisplayName ~= "" then
					tool.Name = def.DisplayName
				end
				if def.Kind == "Weapon" and type(def.WeaponId) == "string" and def.WeaponId ~= "" then
					wpnId = def.WeaponId
				end
				local ms = tonumber(def.MountSpeed)
				if ms and ms > 0 then
					tool:SetAttribute("MountSpeed", ms)
					tool:SetAttribute("MountItemId", item.itemId)
				end
				-- Food: surface TimeToEat to the embedded EatFoodClient LocalScript via attribute.
				if def.Kind == "Food" then
					tool:SetAttribute("FoodTimeToEat", math.max(0, tonumber(def.TimeToEat) or 0))
					tool:SetAttribute("FoodItemId", item.itemId)
					if def.SubKind == "Fish" then
						tool:SetAttribute("FoodIsFish", true)
					end
				end
			end
			if not wpnId and item.type == "Weapon" then
				local pid = (type(item.toolPrefabName) == "string" and item.toolPrefabName ~= "" and item.toolPrefabName)
					or inferWeaponDropToolPrefabFromTags(item)
				if pid and WeaponData.IsCombatWeapon(pid) then
					wpnId = pid
				end
			end
			if wpnId then
				tool:SetAttribute("WeaponId", wpnId)
			end
			-- Stamp swing cost multiplier so CombatClient can gate correctly
			if item.type == "Weapon" and type(item.tags) == "table" then
				local swingMults = EnergyConfig.WEAPON_SWING_MULT or {}
				for _, tag in ipairs(item.tags) do
					if swingMults[tag] then
						tool:SetAttribute("WeaponSwingMult", swingMults[tag])
						break
					end
				end
			end
		end

		tool.Parent = backpack
		spawned[uuid] = true
	end

	local hotbar = profile.hotbar
	if type(hotbar) == "table" then
		for i = 1, 9 do
			trySpawn("HB" .. tostring(i), hotbarSlotUuid(hotbar, i))
		end
	end

	local equipped = profile.equipped
	if type(equipped) == "table" then
		for slot, uuid in pairs(equipped) do
			trySpawn(slot, uuid)
		end
	end
end

return DungeonEquippedHotbar
