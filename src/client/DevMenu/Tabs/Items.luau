--[[
	Items -- an icon grid of every ItemDefinitions entry (keys, fragments, materials, consumables...).
	Set a quantity and click an icon to grant it (DevGrantItem). Each icon grants itself: this tab
	deliberately has no footer action (a shared confirm button once spawned random gear here).
	New catalog entries appear with no edit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local Tab = { key = "Items", label = "Items", group = "Items" }

local function grant(ctx, rf, itemId, qty)
	if not rf then ctx.status("DevGrantItem remote missing", true) return end
	qty = math.clamp(math.floor(tonumber(qty) or 1), 1, 9999)
	local pOk, ok, err = pcall(function() return rf:InvokeServer(itemId, qty) end)
	if not pOk then
		ctx.status("Grant failed: " .. tostring(ok), true)
	elseif ok then
		ctx.status("Granted " .. qty .. "x " .. itemId)
	else
		ctx.status("Grant failed: " .. tostring(err), true)
	end
end

function Tab.Build(ctx)
	local Ui = ctx.Ui
	local sec = Ui.section(ctx, "ItemsSection", true)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(96, 128)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = sec
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 4), UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = sec

	local rf = nil
	task.spawn(function()
		rf = ReplicatedStorage:WaitForChild("DevGrantItem", 60)
		if not rf then warn("[DevMenu] DevGrantItem RF not found after 60s") end
	end)

	local ids = {}
	for id in pairs(ItemDefinitions.Items) do table.insert(ids, id) end
	table.sort(ids)
	for i, id in ipairs(ids) do
		local def = ItemDefinitions.Get(id)
		local cell = Instance.new("Frame")
		cell.Name = id
		cell.LayoutOrder = i
		cell.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
		cell.BorderSizePixel = 0
		cell.Parent = sec
		Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 6)
		local rim = Instance.new("UIStroke")
		rim.Color = Ui.Color.Rim
		rim.Transparency = 0.6
		rim.Parent = cell

		local icon = Instance.new("ImageButton")
		icon.Position = UDim2.fromOffset(8, 6)
		icon.Size = UDim2.fromOffset(80, 80)
		icon.BackgroundColor3 = Ui.Color.Field
		icon.BorderSizePixel = 0
		icon.Image = (def and def.Icon) or ""
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = cell
		Instance.new("UICorner", icon).CornerRadius = UDim.new(0, 5)

		local qty = ctx.mkI(cell, "1", 8, 90, 80, 20, "1")
		qty.TextSize = 13
		local name = ctx.lbl(cell, (def and def.DisplayName) or id, 2, 112, 92, 14, 10, Color3.fromRGB(200, 190, 175), false,
			Enum.TextXAlignment.Center)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		icon.Activated:Connect(function() grant(ctx, rf, id, qty.Text) end)
	end
	return sec
end

return Tab
