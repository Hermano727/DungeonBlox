--[[
	Spawns Tool instances into Backpack for dungeon hotbar slots 1-9 and legacy equipped slots.
	Uses ServerStorage.DungeonToolPrefabsArchive; prefab name from item.toolPrefabName or ItemDefinitions.ToolPrefabName.
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local EnergyConfig = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local WeaponData = require(ReplicatedStorage:WaitForChild("WeaponData"))
local ActiveEquipment = require(ReplicatedStorage:WaitForChild("ActiveEquipment"))
local CharacterAnimProfiles = require(ReplicatedStorage:WaitForChild("CharacterAnimProfiles"))

local ARCHIVE_NAME = "DungeonToolPrefabsArchive"

-- Once per server session, replace weapon-drop Tool templates in the archive with fresh
-- clones from StarterPack so edits to e.g. Low_tier_sword propagate without stale meshes.
local sessionWeaponDropPrefabsResynced = false
local sessionPickaxePrefabResynced = false

local EquippedHotbar = {}
local activeCleanups = {}

local function clearActive(player)
	local cleanup = activeCleanups[player]
	if cleanup then cleanup() end
	local character = player.Character
	if character then character:SetAttribute(ActiveEquipment.ATTRIBUTE, nil) end
end

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
		warn("[EquippedHotbar] Missing ReplicatedStorage.EatFoodClientTemplate (LocalScript); food eat will not work")
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
		warn("[EquippedHotbar] Missing ReplicatedStorage.DrinkPotionClientTemplate (LocalScript); potion drinking will not work")
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
				warn("[EquippedHotbar] StarterPack missing Tool for weapon drop prefab:", prefabName)
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
-- BackpackImport.ImportPlayerBackpack abort and the starter pack never loads.
function EquippedHotbar.ensureArchiveFolder()
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

-- Only used for a hard reset (player leaving, or an explicit request to nuke
-- everything) -- syncFromProfile itself now reconciles instead of calling
-- this, see the note above `reconcile` below.
function EquippedHotbar.clearDungeonTools(player)
	if not player then
		return
	end
	clearActive(player)
	local function destroyAll(container)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("DungeonEquipped") == true then
				child:Destroy()
			end
		end
	end
	destroyAll(player:FindFirstChildOfClass("Backpack"))
	destroyAll(player.Character)
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

function EquippedHotbar.syncFromProfile(player, profile)
	if not player or not profile or player.Parent == nil then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 3)
	if not backpack then
		return
	end

	local archive = EquippedHotbar.ensureArchiveFolder()
	if not archive then
		return
	end

	local inv = profile.inventory
	if type(inv) ~= "table" then
		return
	end

	local equipped = profile.equipped
	local desiredUuids = {}
	if type(equipped) == "table" then
		for _, uuid in pairs(equipped) do
			if type(uuid) == "string" and uuid ~= "" and inv[uuid] then
				desiredUuids[uuid] = true
			end
		end
	end

	-- Reconcile instead of blind destroy-then-rebuild. syncFromProfile is
	-- called from a LOT of unrelated places (spawn, every menu/shop/bank/
	-- dialog action's requestSync(), several of them firing back-to-back at
	-- spawn) -- destroying every tagged tool up front used to also destroy
	-- whatever was actively EQUIPPED in the player's hand, since Character
	-- tools carry the same DungeonEquipped tag as Backpack ones. A player
	-- pressing a hotbar key to equip a weapon, followed moments later by
	-- any unrelated script's routine resync, would silently get their
	-- weapon yanked back into Backpack -- looked exactly like "pressing 1
	-- doesn't equip it" (found 2026-09-14). A tool whose uuid is still a
	-- valid equip-slot value is left exactly where it is now (Backpack OR
	-- Character); only genuinely stale tools (no longer equipped anywhere)
	-- get destroyed.
	local spawned = {}
	local function reconcile(container)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("DungeonEquipped") == true then
				local uuid = child:GetAttribute("DungeonItemUuid")
				if type(uuid) == "string" and uuid ~= "" and desiredUuids[uuid] and not spawned[uuid] then
					spawned[uuid] = true
				else
					child:Destroy()
				end
			end
		end
	end
	reconcile(player.Character)
	reconcile(backpack)

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
			warn("[EquippedHotbar] Missing prefab Tool for:", prefabName)
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

	-- No more freeform hotbar -- every spawnable Tool now comes from a fixed equip slot
	-- (Helm/Chest/Legs/Boots/Shield armor + Weapon/Bow/Pickaxe/FishingSpear tools).
	if type(equipped) == "table" then
		for slot, uuid in pairs(equipped) do
			trySpawn(slot, uuid)
		end
	end
	local character = player.Character
	if character and character:GetAttribute(ActiveEquipment.ATTRIBUTE)
		and not ActiveEquipment.GetTool(character) then
		clearActive(player)
	end
end

-- Select an already-owned, assigned item; this never changes inventory records.
-- Explicit slot/empty selection is idempotent. Toggle semantics live in input.
function EquippedHotbar.selectActiveSlot(player, profile, slot, character)
	if not character or character ~= player.Character or not character.Parent then
		return false, "character_changed"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not humanoid or humanoid.Health <= 0 or not root or not backpack then
		return false, "character_not_ready"
	end
	if slot == "" then
		clearActive(player)
		humanoid:UnequipTools()
		return true
	end
	if not table.find(ActiveEquipment.Slots, slot) then return false, "bad_slot" end
	local uuid = profile and profile.equipped and profile.equipped[slot]
	local item = profile and profile.inventory and profile.inventory[uuid]
	if not item or Types.GetAllowedEquipSlot(item) ~= slot then return false, "slot_empty" end
	EquippedHotbar.syncFromProfile(player, profile)
	if character ~= player.Character then return false, "character_changed" end
	local tool
	for _, container in ipairs({ character, backpack }) do
		for _, candidate in ipairs(container:GetChildren()) do
			if candidate:IsA("Tool") and candidate:GetAttribute("DungeonEquipped") == true
				and candidate:GetAttribute("DungeonItemUuid") == uuid then
				tool = candidate
				break
			end
		end
		if tool then break end
	end
	if not tool then return false, "tool_missing" end
	if ActiveEquipment.GetTool(character) == tool then return true end
	local boneSword = character:FindFirstChild("Hero_Character") ~= nil
		and CharacterAnimProfiles.GetProfileForTool(tool) == "Sword"
	local handle = tool:FindFirstChild("Handle")
	if (boneSword or tool.RequiresHandle) and (not handle or not handle:IsA("BasePart")) then
		return false, "handle_missing"
	end
	clearActive(player)
	humanoid:UnequipTools()

	local connections, savedParts, welds = {}, {}, {}
	local requiresHandle = tool.RequiresHandle
	local cleaned = false
	local function cleanup()
		if cleaned then return end
		cleaned = true
		activeCleanups[player] = nil
		for _, connection in ipairs(connections) do connection:Disconnect() end
		if character:GetAttribute(ActiveEquipment.ATTRIBUTE) == uuid then
			character:SetAttribute(ActiveEquipment.ATTRIBUTE, nil)
		end
		for _, weld in ipairs(welds) do weld:Destroy() end
		for part, properties in pairs(savedParts) do
			if part.Parent then
				for property, value in pairs(properties) do part[property] = value end
				part:SetAttribute("DungeonVisualTransparency", nil)
				part:SetAttribute("DungeonVisualOffset", nil)
			end
		end
		if tool.Parent then
			tool.RequiresHandle = requiresHandle
			tool:SetAttribute("BoneWeaponVisual", nil)
			tool:SetAttribute("BoneWeaponPartCount", nil)
		end
	end
	activeCleanups[player] = cleanup
	if boneSword then
		-- Keep the real Tool for combat and inventory. Its hidden physical parts
		-- stay secured on the SERVER; only client-created visuals follow bones.
		local origin = handle.CFrame
		for _, part in ipairs(tool:GetDescendants()) do
			if part:IsA("BasePart") then
				local offset = origin:ToObjectSpace(part.CFrame)
				savedParts[part] = { Anchored = part.Anchored, CanCollide = part.CanCollide,
					CanTouch = part.CanTouch, CanQuery = part.CanQuery, Massless = part.Massless,
					Transparency = part.Transparency }
				part:SetAttribute("DungeonVisualTransparency", part.Transparency)
				part:SetAttribute("DungeonVisualOffset", offset)
				part.Transparency = 1
				part.Anchored = false
				part.CanCollide, part.CanTouch, part.CanQuery, part.Massless = false, false, false, true
				part.CFrame = root.CFrame * offset
				local weld = Instance.new("WeldConstraint")
				weld.Name = "BoneWeaponStorageWeld"
				weld.Part0, weld.Part1 = root, part
				weld.Parent = part
				table.insert(welds, weld)
			end
		end
		tool.RequiresHandle = false
		tool:SetAttribute("BoneWeaponPartCount", #welds)
		tool:SetAttribute("BoneWeaponVisual", true)
		tool.Parent = character
	else
		humanoid:EquipTool(tool)
	end
	if tool.Parent ~= character then
		cleanup()
		return false, "equip_failed"
	end
	character:SetAttribute(ActiveEquipment.ATTRIBUTE, uuid)
	table.insert(connections, tool.AncestryChanged:Connect(function()
		if tool.Parent ~= character then cleanup() end
	end))
	table.insert(connections, humanoid.Died:Connect(function()
		cleanup()
		if tool.Parent == character and backpack.Parent == player then tool.Parent = backpack end
	end))
	table.insert(connections, player.CharacterRemoving:Connect(function(oldCharacter)
		if oldCharacter == character then cleanup() end
	end))
	return true
end

return EquippedHotbar
