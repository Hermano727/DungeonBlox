--[[
	DrinkPotionClientTemplate
	Not run from ReplicatedStorage (LocalScripts don't run there). EquippedHotbar
	clones this script into the DefaultPotionTool prefab at runtime so the LocalScript only
	executes once parented under the player's Backpack/Character.

	Reads Tool attribute DungeonItemUuid (required). Right-click while the potion is the
	equipped/held tool fires ReplicatedStorage.GameEvents.DrinkPotionRequest with the uuid.
	No hold duration — drinking is instant on right-click, unlike Food's hold-to-eat.
]]

local tool = script.Parent
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local conns = {}

local function getEvent()
	local ge = RS:FindFirstChild("GameEvents")
	if not ge then return nil end
	local ev = ge:FindFirstChild("DrinkPotionRequest")
	if ev and ev:IsA("RemoteEvent") then return ev end
	return nil
end

local function fireDrink()
	local uuid = tool:GetAttribute("DungeonItemUuid")
	if type(uuid) ~= "string" or uuid == "" then return end
	local ev = getEvent()
	if ev then ev:FireServer(uuid) end
end

tool.Equipped:Connect(function()
	table.insert(conns, UIS.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			fireDrink()
		end
	end))
end)

tool.Unequipped:Connect(function()
	for _, c in ipairs(conns) do
		pcall(function() c:Disconnect() end)
	end
	conns = {}
end)

tool.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		for _, c in ipairs(conns) do
			pcall(function() c:Disconnect() end)
		end
		conns = {}
	end
end)
