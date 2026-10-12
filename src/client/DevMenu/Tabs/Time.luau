--[[
	Time -- sets the day/night clock by hour/minute or a preset (Dawn / Noon / Dusk / Midnight).
	Setting a time pauses the auto cycle; Resume Auto Cycle restarts it (DevDayNightControl). The
	readout follows the server's DayNightSync while this tab is open.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DayNightConfig = require(ReplicatedStorage:WaitForChild("DayNightConfig"))

local Tab = { key = "Time", label = "Time", group = "World" }

local ui = {}
local shown = false

local function rf(ctx)
	return ctx.GE and ctx.GE:FindFirstChild("DevDayNightControl")
end

local function showClock(clockTime)
	local t = DayNightConfig.clampClockTime(clockTime)
	local m = math.floor((t % 1) * 60 + 0.5)
	ui.hour.Text = tostring(math.floor(t) % 24)
	ui.minute.Text = tostring(m >= 60 and 0 or m)
	ui.preview.Text = DayNightConfig.formatClockTime(t)
end

local function showState(state)
	if not shown then return end
	if type(state) == "table" then
		showClock(state.clockTime)
		if state.devOverride then
			ui.cycle.Text = "Dev override, cycle paused"
			ui.cycle.TextColor3 = Color3.fromRGB(255, 200, 120)
		else
			ui.cycle.Text = "Auto cycle (20m day / 20m night)"
			ui.cycle.TextColor3 = Color3.fromRGB(180, 170, 140)
		end
	else
		ui.preview.Text = DayNightConfig.formatClockTime(DayNightConfig.clockTimeFromHourMinute(ui.hour.Text, ui.minute.Text))
	end
end

local function call(ctx, request, failPrefix)
	local remote = rf(ctx)
	if not remote then ctx.status("DevDayNightControl missing", true) return nil end
	local ok, result = pcall(function() return remote:InvokeServer(request) end)
	if not ok or type(result) ~= "table" or not result.ok then
		local err = (type(result) == "table" and result.error) or tostring(result)
		ctx.status(failPrefix .. tostring(err), true)
		return nil
	end
	return result
end

local function applyTime(ctx, hour, minute)
	local result = call(ctx, { action = "SetTime", hour = hour, minute = minute }, "Set time failed: ")
	if result then
		showState(result.state)
		ctx.status("Time set: " .. DayNightConfig.formatClockTime(result.state.clockTime))
	end
end

function Tab.Build(ctx)
	local Ui, lbl, mkB, mkI = ctx.Ui, ctx.lbl, ctx.mkB, ctx.mkI
	local sec = Ui.section(ctx, "TimeSection")
	lbl(sec, "TIME OF DAY", 12, 2, 160, 16, 12, ctx.acc, true)
	ui.cycle = lbl(sec, "Auto cycle", 12, 22, ctx.w - 24, 18, 14, Color3.fromRGB(180, 170, 140))
	ui.preview = lbl(sec, "12:00 PM", 12, 42, ctx.w - 24, 30, 24, Ui.Color.Status, true)
	lbl(sec, "HOUR", 12, 84, 60, 16, 12, ctx.acc, true)
	ui.hour = mkI(sec, "12", 12, 102, 70, 30, "12")
	lbl(sec, "MIN", 92, 84, 60, 16, 12, ctx.acc, true)
	ui.minute = mkI(sec, "0", 92, 102, 70, 30, "0")
	lbl(sec, "PRESETS", 12, 146, 120, 16, 12, ctx.acc, true)
	local presets = {
		{ "Dawn", 6, Color3.fromRGB(70, 56, 40) }, { "Noon", 12, Color3.fromRGB(72, 64, 40) },
		{ "Dusk", 18, Color3.fromRGB(64, 48, 70) }, { "Midnight", 0, Color3.fromRGB(42, 42, 70) },
	}
	for i, p in ipairs(presets) do
		mkB(sec, p[1], 12 + (i - 1) * 100, 164, 92, 30, p[3]).Activated:Connect(function() applyTime(ctx, p[2], 0) end)
	end
	mkB(sec, "Resume Auto Cycle", 12, 206, 392, 32, Color3.fromRGB(40, 70, 110)).Activated:Connect(function()
		local result = call(ctx, { action = "Resume" }, "Resume failed: ")
		if result then
			showState(result.state)
			ctx.status("Automatic day/night cycle resumed")
		end
	end)
	ui.hour.FocusLost:Connect(function() showState() end)
	ui.minute.FocusLost:Connect(function() showState() end)

	task.spawn(function()
		local sync = ctx.GE and ctx.GE:WaitForChild("DayNightSync", 30)
		if sync and sync:IsA("RemoteEvent") then
			sync.OnClientEvent:Connect(function(state)
				if type(state) == "table" then showState(state) end
			end)
		end
	end)
	return sec
end

function Tab.OnShow(ctx)
	shown = true
	task.spawn(function()
		local remote = rf(ctx)
		if not remote then return end
		local ok, result = pcall(function() return remote:InvokeServer({ action = "Get" }) end)
		if ok and type(result) == "table" and result.ok then showState(result.state) end
	end)
end

function Tab.OnHide()
	shown = false
end

function Tab.ActionLabel(ctx)
	return "Apply Time", ctx.Ui.Color.Good
end

function Tab.OnAction(ctx)
	applyTime(ctx, ui.hour.Text, ui.minute.Text)
end

return Tab
