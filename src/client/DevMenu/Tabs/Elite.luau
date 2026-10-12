--[[
	Elite -- spawns a named elite (or a dungeon boss) right away, through the same server paths a
	real elite roll uses. Lists every MobData entry with IsNamedElite or IsBoss (Lists).

	Named elite: rise-from-ground intro and boss bar, at your aim (MobManager.ForceSpawnNamedElite);
	only one may be alive server-wide, so the server refuses while one is up. Dungeon boss: 45 studs
	ahead, real stats and class, no run or intro (ForceSpawnBoss); a new one replaces the old.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lists = require(script.Parent.Parent:WaitForChild("Lists"))
local MobData = require(ReplicatedStorage:WaitForChild("MobData"))

local Tab = { key = "Elite", label = "Elite", group = "World" }

local eliteIdx = 1

function Tab.Build(ctx)
	local Ui, lbl, mkB = ctx.Ui, ctx.lbl, ctx.mkB
	local W = ctx.w
	local muted = Ui.Color.Muted
	local sec = Ui.section(ctx, "EliteSection")
	lbl(sec, "NAMED ELITE / BOSS", 12, 2, 220, 16, 12, ctx.acc, true)
	local prev = mkB(sec, "<", 12, 22, 30, 30)
	local nxt = mkB(sec, ">", W - 42, 22, 30, 30)
	local disp = lbl(sec, Lists.NAMED_ELITE_IDS[1] or "(none authored)", 48, 22, W - 96, 30, 15, nil, false,
		Enum.TextXAlignment.Center)
	local function step(delta)
		eliteIdx = Lists.step(eliteIdx, delta, #Lists.NAMED_ELITE_IDS)
		disp.Text = Lists.NAMED_ELITE_IDS[eliteIdx] or "(none authored)"
	end
	prev.Activated:Connect(function() step(-1) end)
	nxt.Activated:Connect(function() step(1) end)
	lbl(sec, "Spawns at your aim with the rise intro and boss bar.", 12, 64, W - 24, 18, 14, muted)
	lbl(sec, "Only ONE named elite may be alive at a time: kill or despawn the current one first.", 12, 84, W - 24, 18, 13, muted)
	lbl(sec, "Dungeon bosses (e.g. MiasmaBoss) spawn 45 studs ahead, no run or intro; a new one replaces the old.", 12, 104, W - 24, 18, 13, muted)
	return sec
end

function Tab.ActionLabel()
	return "Spawn Named Elite", Color3.fromRGB(110, 45, 110)
end

function Tab.OnAction(ctx)
	local evPlace = ctx.GE and ctx.GE:FindFirstChild("DevPlaceSpawner")
	if not evPlace then ctx.status("DevPlaceSpawner remote missing", true) return end
	local mobId = Lists.NAMED_ELITE_IDS[eliteIdx]
	if not mobId then ctx.status("No named elites authored in MobData", true) return end
	local stats = MobData.FindMobById(mobId)
	if stats and stats.IsBoss then
		evPlace:FireServer({ SpawnerType = "Boss", MobId = mobId })
		ctx.status("Spawning dungeon boss: " .. mobId .. " (45 studs ahead)")
		return
	end
	evPlace:FireServer({ SpawnerType = "NamedElite", MobId = mobId, Position = ctx.mouse.Hit.Position })
	ctx.status("Spawning named elite: " .. mobId)
end

return Tab
