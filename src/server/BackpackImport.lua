--[[
  Converts StarterPack tools in Backpack into DungeonProfile rows once per session.
  After profile.flags.starterPackImported is true, use stripKnownStarterPackTools on respawn
  to destroy regrown StarterPack Tools without granting duplicate inventory rows.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local EquippedHotbar = require(ServerScriptService:WaitForChild("EquippedHotbar"))

local COAL_TOOL_NAME = "Coal"

local BackpackImport = {}

local function templateForTool(tool)
	local name = tool.Name
	if name == "Pickaxe" then
		return {
			name = "Pickaxe",
			type = "Material",
			rarity = "Common",
			tier = 1,
			enchantLevel = 0,
			subStats = { MiningLevel = 1 },
			equipSlot = "Pickaxe",
		}
	elseif name == "WoodenPickaxe" then
		return {
			name = "Training Pickaxe",
			type = "Material",
			rarity = "Common",
			tier = 1, enchantLevel = 0,
			subStats = { MiningLevel = 1 },
			equipSlot = "Pickaxe",
			durability = 1500, maxDurability = 1500,
		}
	elseif name == "Spear" then
		return {
			name = "Spear",
			type = "Material",
			rarity = "Common",
			tier = 1,
			enchantLevel = 0,
			subStats = { FishingLevel = 1 },
			equipSlot = "FishingSpear",
		}
	elseif name == "WoodenSpear" then
		return {
			name = "Training Spear",
			type = "Material",
			rarity = "Common",
			tier = 1, enchantLevel = 0,
			subStats = { FishingLevel = 1 },
			equipSlot = "FishingSpear",
			durability = 1500, maxDurability = 1500,
		}
	elseif name == "WoodenSword" or name == "TrainingSword" or name == "Training Sword" or name == "Low_tier_sword" then
		return {
			-- Every legacy backpack sword variant (including the old "Low_tier_sword" prefab)
			-- imports as the same display name now -- no more duplicate "Low Tier Sword" vs
			-- "Training Sword" naming for what's functionally the same starter weapon.
			name = "Training Sword",
			type = "Weapon",
			rarity = "Common",
			tier = 1, level = 1, enchantLevel = 0,
			subStats = { dmgMin = 7, dmgMax = 8 },
			durability = 1500, maxDurability = 1500,
			tags = { "Sword" },
		}
	elseif name == "WoodenBow" then
		return {
			name = "Training Bow",
			type = "Weapon",
			rarity = "Common",
			tier = 1, level = 1, enchantLevel = 0,
			subStats = { dmgMin = 9, dmgMax = 10 },
			durability = 1500, maxDurability = 1500,
		}
	end
	-- Speed Coil / Gravity Coil retired from the starter kit -- no longer imported even if a
	-- stray Tool by either name turns up in someone's Backpack (falls through to the "unknown
	-- tool name" warn branch in ImportPlayerBackpack instead of granting an inventory row).
	return nil
end

local function importCoalTool(player, tool)
	if not tool or not tool:IsA("Tool") or tool.Name ~= COAL_TOOL_NAME then
		return
	end
	local stacks = tonumber(tool:GetAttribute("StackCount"))
	if not stacks or stacks ~= stacks or stacks < 1 then
		stacks = 1
	end
	stacks = math.floor(stacks)
	local ok = select(1, DungeonProfile.GrantItemId(player, "Coal", stacks))
	if ok then
		tool:Destroy()
	end
end

local function hookCoalContainer(player, container)
	if not container then
		return
	end
	container.ChildAdded:Connect(function(child)
		importCoalTool(player, child)
	end)
	for _, child in ipairs(container:GetChildren()) do
		importCoalTool(player, child)
	end
end

--[[
	World-dropped Coal (Tool) is picked up into Backpack / Character.
	Convert those instances into dungeon profile stacks and remove the Tool.
]]
function BackpackImport.attachCoalPickupListeners(player)
	if not player or player:GetAttribute("DungeonCoalPickupHooked") then
		return
	end
	player:SetAttribute("DungeonCoalPickupHooked", true)

	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			hookCoalContainer(player, child)
		end
	end)

	local bp = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 60)
	if bp then
		hookCoalContainer(player, bp)
	end

	player.CharacterAdded:Connect(function(character)
		hookCoalContainer(player, character)
	end)
	if player.Character then
		hookCoalContainer(player, player.Character)
	end
end

local function stripContainer(container)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and templateForTool(child) then
			child:Destroy()
		end
	end
end

function BackpackImport.stripKnownStarterPackTools(player)
	stripContainer(player:FindFirstChildOfClass("Backpack"))
	stripContainer(player.Character)
end

function BackpackImport.ImportPlayerBackpack(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
		or player:WaitForChild("Backpack", 8)
	if not backpack then
		return
	end

	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") then
			local template = templateForTool(child)
			if template then
				local archive = EquippedHotbar.ensureArchiveFolder()
				local keyName = child.Name
				local old = archive:FindFirstChild(keyName)
				if old then
					old:Destroy()
				end
				local saved = child:Clone()
				saved.Name = keyName
				saved.Parent = archive
				template.toolPrefabName = keyName

				local grantOk = select(1, DungeonProfile.GrantItem(player, template, 1))
				if grantOk then
					child:Destroy()
				end
			elseif child.Name == COAL_TOOL_NAME then
				importCoalTool(player, child)
			else
				warn("[BackpackImport] Unknown tool name (not imported):", child.Name)
			end
		end
	end
	local profile = DungeonProfile.Load(player)
	profile.flags.starterPackImported = true
end

return BackpackImport
