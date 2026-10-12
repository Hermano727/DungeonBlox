--[[
	Mob -- places a mob spawner camp: mob type, count (1-20), respawn delay (1-300 s), activation
	radius (10-500), zone name. Ordinary mobs only (Lists.MOB_IDS); named elites have their own tab.
	The ghost is a red disc the size of the activation radius.
]]

local Lists = require(script.Parent.Parent:WaitForChild("Lists"))

local Tab = { key = "Mob", label = "Mob", group = "World", places = true,
	listType = "Mob", listTitle = "MANAGED MOB SPAWNERS" }

local mobIdx = 1
local boxCount, boxDelay, boxRadius, boxZone

function Tab.Build(ctx)
	local Ui, lbl, mkB, mkI = ctx.Ui, ctx.lbl, ctx.mkB, ctx.mkI
	local W = ctx.w
	local sec = Ui.section(ctx, "MobSection")
	lbl(sec, "MOB TYPE", 12, 2, 120, 16, 12, ctx.acc, true)
	local prev = mkB(sec, "<", 12, 22, 30, 30)
	local nxt = mkB(sec, ">", W - 42, 22, 30, 30)
	local disp = lbl(sec, Lists.MOB_IDS[1] or "-", 48, 22, W - 96, 30, 15, nil, false, Enum.TextXAlignment.Center)
	local function step(delta)
		mobIdx = Lists.step(mobIdx, delta, #Lists.MOB_IDS)
		disp.Text = Lists.MOB_IDS[mobIdx] or "-"
	end
	prev.Activated:Connect(function() step(-1) end)
	nxt.Activated:Connect(function() step(1) end)

	lbl(sec, "COUNT", 12, 66, 80, 16, 12, ctx.acc, true)
	boxCount = mkI(sec, "3", 12, 84, 70, 30, "3")
	lbl(sec, "DELAY (s)", 96, 66, 90, 16, 12, ctx.acc, true)
	boxDelay = mkI(sec, "10", 96, 84, 80, 30, "10")
	lbl(sec, "ACTIVATION RADIUS", 190, 66, 160, 16, 12, ctx.acc, true)
	boxRadius = mkI(sec, "100", 190, 84, 90, 30, "100")
	lbl(sec, "ZONE", 12, 126, 80, 16, 12, ctx.acc, true)
	boxZone = mkI(sec, "Default", 12, 144, math.min(W - 24, 420), 30, "Default")
	lbl(sec, "Click to Place, then click the ground. The red disc is the activation radius.", 12, 186, W - 24, 16, 13, ctx.Ui.Color.Muted)
	return sec
end

function Tab.ActionLabel(ctx)
	if ctx.placing() then
		return "Placing... (click world)", Color3.fromRGB(140, 110, 20)
	end
	return "Click to Place", ctx.Ui.Color.Good
end

function Tab.SetupGhost(ctx)
	local radius = tonumber(boxRadius.Text) or 100
	ctx.Placement.StyleDisc(Color3.fromRGB(220, 60, 60), math.clamp(radius * 2, 4, 200))
end

function Tab.OnWorldClick(ctx)
	local mobId = Lists.MOB_IDS[mobIdx]
	local evPlace = ctx.GE and ctx.GE:FindFirstChild("DevPlaceSpawner")
	if not mobId or not evPlace then return end
	evPlace:FireServer({
		SpawnerType = "Mob",
		MobId = mobId,
		Count = math.clamp(math.floor(tonumber(boxCount.Text) or 3), 1, 20),
		RespawnDelay = math.clamp(math.floor(tonumber(boxDelay.Text) or 10), 1, 300),
		ActivationRadius = math.clamp(math.floor(tonumber(boxRadius.Text) or 100), 10, 500),
		ZoneName = boxZone.Text ~= "" and boxZone.Text or "Default",
		Position = ctx.mouse.Hit.Position,
	})
end

return Tab
