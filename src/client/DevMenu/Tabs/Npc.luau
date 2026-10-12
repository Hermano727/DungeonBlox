--[[
	Npc -- places an NPC marker: NPC type (Lists.NPC_TYPES), display name, unique id. Blue ghost.
]]

local Lists = require(script.Parent.Parent:WaitForChild("Lists"))

local Tab = { key = "NPC", label = "NPC", group = "World", places = true,
	listType = "NPC", listTitle = "MANAGED NPC MARKERS" }

local npcIdx = 1
local boxName, boxId

function Tab.Build(ctx)
	local Ui, lbl, mkB, mkI = ctx.Ui, ctx.lbl, ctx.mkB, ctx.mkI
	local W = ctx.w
	local sec = Ui.section(ctx, "NpcSection")
	lbl(sec, "NPC TYPE", 12, 2, 120, 16, 12, ctx.acc, true)
	local prev = mkB(sec, "<", 12, 22, 30, 30)
	local nxt = mkB(sec, ">", W - 42, 22, 30, 30)
	local disp = lbl(sec, Lists.NPC_TYPES[1] or "-", 48, 22, W - 96, 30, 15, nil, false, Enum.TextXAlignment.Center)
	local function step(delta)
		npcIdx = Lists.step(npcIdx, delta, #Lists.NPC_TYPES)
		disp.Text = Lists.NPC_TYPES[npcIdx] or "-"
	end
	prev.Activated:Connect(function() step(-1) end)
	nxt.Activated:Connect(function() step(1) end)

	lbl(sec, "DISPLAY NAME", 12, 66, 160, 16, 12, ctx.acc, true)
	boxName = mkI(sec, "e.g. The Merchant", 12, 84, math.min(W - 24, 420), 30)
	lbl(sec, "UNIQUE ID", 12, 126, 160, 16, 12, ctx.acc, true)
	boxId = mkI(sec, "e.g. merchant_01", 12, 144, math.min(W - 24, 420), 30)
	return sec
end

function Tab.ActionLabel(ctx)
	if ctx.placing() then
		return "Placing... (click world)", Color3.fromRGB(140, 110, 20)
	end
	return "Click to Place", ctx.Ui.Color.Good
end

function Tab.SetupGhost(ctx)
	ctx.Placement.StyleDisc(Color3.fromRGB(60, 140, 220), 6)
end

function Tab.OnWorldClick(ctx)
	local name, id = boxName.Text, boxId.Text
	if name == "" or id == "" then
		ctx.status("Fill in the NPC's display name and unique id", true)
		return
	end
	local evPlace = ctx.GE and ctx.GE:FindFirstChild("DevPlaceSpawner")
	if not evPlace then return end
	evPlace:FireServer({ SpawnerType = "NPC", NpcType = Lists.NPC_TYPES[npcIdx], NpcName = name, NpcId = id,
		Position = ctx.mouse.Hit.Position })
end

return Tab
