--[[
	Gear -- rolls procedural gear through ItemGenerator (the engine mob drops use): kind (Random /
	Weapon / Armor), subtype, level, rarity, substat count, count (1-20).

	Force Substat pins a substat to an exact value (critical @ 100 = a guaranteed-crit test weapon);
	+ stacks it onto a list to pin several at once. The picker reflects
	ItemConfig.GetSubstatEffects(kind, weaponType), the shared "what can sit on this item" pool
	(bonus-only stats like block included), so it never needs an edit when ItemConfig changes.
	Weapon and armor substats are disjoint, so switching kind clears the list. T1 only: the server
	rejects levels above 21.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local Lists = require(script.Parent.Parent:WaitForChild("Lists"))

local Tab = { key = "Gear", label = "Gear", group = "Items" }

local TIER1_MAX_LEVEL = 21 -- mirrors DevService; only drives the tier preview, the server re-validates
local KINDS = { "Random", "Weapon", "Armor" }
local WEAPON_POOL = ItemConfig.WEAPON_TYPES_BY_TIER[1] or ItemConfig.WEAPON_TYPES
local ARMOR_POOL = ItemConfig.ARMOR_SLOTS_BY_TIER[1] or ItemConfig.ARMOR_SLOTS
local RARITIES = { "Random" }
for _, r in ipairs(ItemConfig.RARITY_ORDER) do table.insert(RARITIES, r) end

local sel = { kind = 1, weapon = 1, armor = 1, rarity = 1, forceSub = 1 }
local forcePool = { "None" }
local forced = {} -- { { id =, value = } }
local lastKind = nil
local ui = {}

-- A "< value >" picker row; returns the label and the two buttons.
local function picker(ctx, sec, title, y, width)
	ctx.lbl(sec, title, 12, y, 260, 16, 12, ctx.acc, true)
	local prev = ctx.mkB(sec, "<", 12, y + 18, 30, 28)
	local nxt = ctx.mkB(sec, ">", width - 30, y + 18, 30, 28)
	local disp = ctx.lbl(sec, "", 48, y + 18, width - 96, 28, 15, nil, false, Enum.TextXAlignment.Center)
	return disp, prev, nxt
end

local function spawn(ctx)
	local rf = ctx.GE and ctx.GE:FindFirstChild("DevSpawnItem")
	if not rf then ctx.status("DevSpawnItem remote missing", true) return end
	local kind = KINDS[sel.kind]
	local data = {
		Level = math.floor(tonumber(ui.level.Text) or 1),
		Kind = kind,
		Count = math.clamp(math.floor(tonumber(ui.count.Text) or 1), 1, 20),
	}
	if RARITIES[sel.rarity] ~= "Random" then data.Rarity = RARITIES[sel.rarity] end
	if ui.substats.Text ~= "" then data.SubstatCount = tonumber(ui.substats.Text) end
	if #forced > 0 then
		data.ForceSubstats = {}
		for _, entry in ipairs(forced) do
			table.insert(data.ForceSubstats, { Id = entry.id, Value = entry.value })
		end
	else
		-- Nothing stacked with +: force whatever the picker shows, if it has a value.
		local id = forcePool[sel.forceSub]
		local v = tonumber(ui.forceValue.Text)
		if id and id ~= "None" and v ~= nil then
			data.ForceSubstatId, data.ForceSubstatValue = id, v
		end
	end
	if kind == "Weapon" then data.WeaponType = WEAPON_POOL[sel.weapon]
	elseif kind == "Armor" then data.ArmorSlot = ARMOR_POOL[sel.armor] end
	local ok, result = pcall(function() return rf:InvokeServer(data) end)
	if not ok or type(result) ~= "table" or not result.ok then
		ctx.status("Spawn failed: " .. tostring((type(result) == "table" and result.error) or result), true)
		return
	end
	local it = result.item or {}
	ctx.status(string.format("Spawned %s (%s, L%d)", tostring(it.name), tostring(it.rarity), tonumber(it.level) or 0))
end

function Tab.Build(ctx)
	local Ui, lbl, mkB, mkI = ctx.Ui, ctx.lbl, ctx.mkB, ctx.mkI
	local W = math.min(ctx.w, 640)
	local sec = Ui.section(ctx, "GearSection", true)

	local kindDisp, kindPrev, kindNext = picker(ctx, sec, "ITEM KIND", 2, W)
	local subDisp, subPrev, subNext = picker(ctx, sec, "SUBTYPE", 54, W)
	lbl(sec, "LEVEL (1-21 = T1)", 12, 106, 200, 16, 12, ctx.acc, true)
	ui.level = mkI(sec, "1", 12, 124, 70, 28, "1")
	local tierDisp = lbl(sec, "Tier: T1", 94, 124, 240, 28, 14, Color3.fromRGB(180, 220, 180), true)
	local rarityDisp, rarityPrev, rarityNext = picker(ctx, sec, "RARITY", 160, W)
	lbl(sec, "SUBSTATS (blank = default roll)", 12, 212, 230, 16, 12, ctx.acc, true)
	ui.substats = mkI(sec, "e.g. 2", 12, 230, 90, 28, "")
	lbl(sec, "COUNT", 250, 212, 80, 16, 12, ctx.acc, true)
	ui.count = mkI(sec, "1", 250, 230, 70, 28, "1")

	lbl(sec, "FORCE SUBSTAT (optional, e.g. critical @ 100 = guaranteed crit)", 12, 268, W, 16, 12, ctx.acc, true)
	local forcePrev = mkB(sec, "<", 12, 286, 30, 28)
	local forceDisp = lbl(sec, "None", 48, 286, 260, 28, 15, nil, false, Enum.TextXAlignment.Center)
	local forceNext = mkB(sec, ">", 314, 286, 30, 28)
	lbl(sec, "VALUE", 356, 268, 90, 16, 12, ctx.acc, true)
	ui.forceValue = mkI(sec, "e.g. 100", 356, 286, 90, 28, "")
	local add = mkB(sec, "+", 454, 286, 36, 28, Ui.Color.Good)
	add.TextSize = 20

	lbl(sec, "FORCED SUBSTATS (empty = just the one above)", 12, 324, 380, 16, 12, ctx.acc, true)
	local clear = mkB(sec, "Clear", W - 80, 320, 70, 24, Ui.Color.Bad)
	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Position = UDim2.fromOffset(12, 346)
	listFrame.Size = UDim2.fromOffset(W - 22, 90)
	listFrame.BackgroundColor3 = Ui.Color.Field
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 4
	listFrame.CanvasSize = UDim2.new()
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.ZIndex = 4
	listFrame.Parent = sec
	Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 5)
	Instance.new("UIListLayout", listFrame).Padding = UDim.new(0, 2)
	mkB(sec, "Spawn Item", 12, 446, W - 22, 34, Ui.Color.Good).Activated:Connect(function() spawn(ctx) end)

	local function refreshForced()
		for _, c in ipairs(listFrame:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for index, entry in ipairs(forced) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 22)
			row.BackgroundTransparency = 1
			row.LayoutOrder = index
			row.Parent = listFrame
			lbl(row, entry.id .. " @ " .. tostring(entry.value), 6, 0, W - 90, 22, 13, Color3.fromRGB(230, 220, 190)).ZIndex = 6
			local x = mkB(row, "x", 0, 2, 22, 18, Ui.Color.Bad)
			x.AnchorPoint = Vector2.new(1, 0)
			x.Position = UDim2.new(1, -4, 0, 2)
			x.TextSize = 12
			x.ZIndex = 6
			x.Activated:Connect(function()
				table.remove(forced, index)
				refreshForced()
			end)
		end
	end

	local function refreshForcePool()
		local kind = KINDS[sel.kind]
		forcePool = { "None" }
		for _, e in ipairs(ItemConfig.GetSubstatEffects(kind, WEAPON_POOL[sel.weapon])) do
			table.insert(forcePool, e.id)
		end
		if sel.forceSub > #forcePool then sel.forceSub = 1 end
		forceDisp.Text = forcePool[sel.forceSub]
		if lastKind ~= nil and lastKind ~= kind and #forced > 0 then
			table.clear(forced)
			refreshForced()
			ctx.status("Forced substats cleared (item kind changed)")
		end
		lastKind = kind
	end

	local function refreshKind()
		local kind = KINDS[sel.kind]
		kindDisp.Text = kind
		local hasSub = kind ~= "Random"
		subPrev.Visible, subNext.Visible = hasSub, hasSub
		subDisp.Text = kind == "Weapon" and (WEAPON_POOL[sel.weapon] or "-")
			or kind == "Armor" and (ARMOR_POOL[sel.armor] or "-") or "Any"
		refreshForcePool()
	end

	local function stepSub(delta)
		local kind = KINDS[sel.kind]
		if kind == "Weapon" then sel.weapon = Lists.step(sel.weapon, delta, #WEAPON_POOL)
		elseif kind == "Armor" then sel.armor = Lists.step(sel.armor, delta, #ARMOR_POOL) end
		refreshKind()
	end

	local function refreshTier()
		local level = math.floor(tonumber(ui.level.Text) or 0)
		if level < 1 then
			tierDisp.Text, tierDisp.TextColor3 = "Tier: ?", Color3.fromRGB(220, 160, 120)
		elseif level <= TIER1_MAX_LEVEL then
			tierDisp.Text, tierDisp.TextColor3 = "Tier: T1", Color3.fromRGB(180, 220, 180)
		else
			tierDisp.Text, tierDisp.TextColor3 = "T2+ not implemented", Color3.fromRGB(255, 140, 140)
		end
	end

	kindPrev.Activated:Connect(function() sel.kind = Lists.step(sel.kind, -1, #KINDS) refreshKind() end)
	kindNext.Activated:Connect(function() sel.kind = Lists.step(sel.kind, 1, #KINDS) refreshKind() end)
	subPrev.Activated:Connect(function() stepSub(-1) end)
	subNext.Activated:Connect(function() stepSub(1) end)
	rarityPrev.Activated:Connect(function() sel.rarity = Lists.step(sel.rarity, -1, #RARITIES) rarityDisp.Text = RARITIES[sel.rarity] end)
	rarityNext.Activated:Connect(function() sel.rarity = Lists.step(sel.rarity, 1, #RARITIES) rarityDisp.Text = RARITIES[sel.rarity] end)
	forcePrev.Activated:Connect(function() sel.forceSub = Lists.step(sel.forceSub, -1, #forcePool) forceDisp.Text = forcePool[sel.forceSub] end)
	forceNext.Activated:Connect(function() sel.forceSub = Lists.step(sel.forceSub, 1, #forcePool) forceDisp.Text = forcePool[sel.forceSub] end)
	ui.level.FocusLost:Connect(refreshTier)

	add.Activated:Connect(function()
		local id = forcePool[sel.forceSub]
		if not id or id == "None" then ctx.status("Pick a substat first", true) return end
		local v = tonumber(ui.forceValue.Text)
		if v == nil then ctx.status("Enter a VALUE first", true) return end
		for _, entry in ipairs(forced) do
			if entry.id == id then
				-- Re-adding retunes it: the generator only grants one slot per id anyway.
				entry.value = v
				refreshForced()
				ctx.status("Updated " .. id .. " @ " .. tostring(v))
				return
			end
		end
		table.insert(forced, { id = id, value = v })
		refreshForced()
		ctx.status("Added " .. id .. " @ " .. tostring(v) .. "  (" .. #forced .. " forced)")
	end)
	clear.Activated:Connect(function()
		table.clear(forced)
		refreshForced()
		ctx.status("Cleared forced substats")
	end)

	rarityDisp.Text = RARITIES[sel.rarity]
	refreshKind()
	refreshTier()
	return sec
end

function Tab.ActionLabel(ctx)
	return "Spawn Item", ctx.Ui.Color.Good
end

function Tab.OnAction(ctx)
	spawn(ctx)
end

return Tab
