--[[
	Dungeon -- test tools for the dungeon clear.

	  * Boss Mythic roll: Normal / Force win / Force loss for YOUR next boss kills (shared with the
	    Mythic tab, DevMenu/MythicForce).
	  * Extra clear drops: queue items of a chosen rarity, added to YOUR next dungeon CLEAR so the
	    Pyres / Reliquary Ring can be watched without waiting on real odds. They go through the same
	    auto-scrap as real drops (T1/T2 scrap Common and Uncommon, so queue Rare or better to see
	    the ring), are stamped as dev items, and never touch the real rolls or the pity streaks.
	  * Fake party members: up to 3 stand-ins (no Player, no profile, nothing granted) that join the
	    clear show as extra braziers, so the show can be tested alone. Each has its own drops (the
	    rarity and count chosen above, "Add to selected fake") and its own Mythic outcome.

	The state lives on the server (SSS/DevRunDrops, SSS/DevFakeParty; DevDungeonDrops and
	DevFakeParty remotes); this tab only shows what the server reports back.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PityConfig = require(ReplicatedStorage:WaitForChild("LootPityConfig"))
local MythicForce = require(script.Parent.Parent:WaitForChild("MythicForce"))
local Lists = require(script.Parent.Parent:WaitForChild("Lists"))

local Tab = { key = "Dungeon", label = "Dungeon", group = "Dungeon" }

local RARITIES = PityConfig.RARITIES -- Common .. Legendary; Mythic has its own control
local FAKE_MODES = { { nil, "Real odds" }, { "win", "Always wins" }, { "loss", "Always loses" } }
local sel = { rarity = 3, fake = 1 } -- Rare: the lowest rarity the ring reveals at T1/T2
local fakes = {}                     -- the server's report, { { name, mythic, drops = { { rarity, count } } } }

local function dropsText(rows)
	if type(rows) ~= "table" or #rows == 0 then return "No drops" end
	local parts = {}
	for _, row in ipairs(rows) do table.insert(parts, string.format("%d x %s", row.count, row.rarity)) end
	return table.concat(parts, "   ")
end

function Tab.Build(ctx)
	local Ui, lbl, mkB, mkI = ctx.Ui, ctx.lbl, ctx.mkB, ctx.mkI
	local W = math.min(ctx.w, 640)
	local sec = Ui.section(ctx, "DungeonSection", true)
	local muted = Color3.fromRGB(180, 175, 185)

	MythicForce.Build(ctx, sec, 12, 2, 240)

	-- Extra drops for YOU.
	lbl(sec, "EXTRA CLEAR DROPS", 12, 66, W - 24, 16, 12, ctx.acc, true)
	lbl(sec, "RARITY", 12, 88, 200, 16, 12, ctx.acc, true)
	local prev = mkB(sec, "<", 12, 106, 30, 28)
	local nxt = mkB(sec, ">", 250, 106, 30, 28)
	local disp = lbl(sec, "", 48, 106, 196, 28, 15, nil, false, Enum.TextXAlignment.Center)
	lbl(sec, "COUNT", 300, 88, 80, 16, 12, ctx.acc, true)
	local boxCount = mkI(sec, "1", 300, 106, 70, 28, "1")
	local addMine = mkB(sec, "Add to my next clear", 386, 106, 190, 28, Ui.Color.Good)
	local addFake = mkB(sec, "Add to selected fake", 386, 140, 190, 28, Ui.Color.Good)

	lbl(sec, "MY QUEUE (used up by my next clear)", 12, 144, 340, 16, 12, ctx.acc, true)
	local queued = lbl(sec, "Nothing queued", 12, 164, 360, 24, 14, Color3.fromRGB(230, 220, 190))
	local clear = mkB(sec, "Clear my queue", 12, 194, 150, 28, Ui.Color.Bad)
	local note = lbl(sec, "T1/T2 auto-scrap Common and Uncommon like real drops, so queue Rare or better to see the Reliquary Ring.",
		12, 228, W - 24, 34, 12, muted)
	note.TextWrapped = true
	note.TextYAlignment = Enum.TextYAlignment.Top

	-- Fake party members.
	lbl(sec, "FAKE PARTY MEMBERS (stand-ins for the next clear; nothing is granted to them)", 12, 276, W - 24, 16, 12, ctx.acc, true)
	local fakePrev = mkB(sec, "<", 12, 296, 30, 28)
	local fakeNext = mkB(sec, ">", 220, 296, 30, 28)
	local fakeDisp = lbl(sec, "No fakes", 48, 296, 166, 28, 15, nil, false, Enum.TextXAlignment.Center)
	local fakeAdd = mkB(sec, "Add fake", 270, 296, 110, 28, Ui.Color.Good)
	local fakeRemove = mkB(sec, "Remove", 390, 296, 100, 28, Ui.Color.Bad)
	lbl(sec, "THEIR MYTHIC ROLL", 12, 334, 220, 16, 12, ctx.acc, true)
	local fakeMythic = mkB(sec, "", 12, 352, 220, 28)
	lbl(sec, "THEIR DROPS", 250, 334, 200, 16, 12, ctx.acc, true)
	local fakeClear = mkB(sec, "Clear their drops", 250, 352, 150, 28, Ui.Color.Bad)
	local fakeDrops = lbl(sec, "", 12, 388, W - 24, 24, 14, Color3.fromRGB(230, 220, 190))

	local function showMine(list)
		queued.Text = (type(list) ~= "table" or #list == 0) and "Nothing queued" or dropsText(list)
	end

	local function showFakes()
		if sel.fake > #fakes then sel.fake = math.max(1, #fakes) end
		local fake = fakes[sel.fake]
		fakeDisp.Text = fake and fake.name or "No fakes"
		for _, control in ipairs({ fakeRemove, fakeMythic, fakeClear, addFake }) do
			control.Visible = fake ~= nil
		end
		fakePrev.Visible, fakeNext.Visible = #fakes > 1, #fakes > 1
		fakeAdd.Visible = #fakes < 3
		if not fake then fakeDrops.Text = "" return end
		for _, mode in ipairs(FAKE_MODES) do
			if mode[1] == fake.mythic then fakeMythic.Text = mode[2] end
		end
		fakeDrops.Text = dropsText(fake.drops)
	end

	local function callMine(action, rarity, count)
		local rf = ctx.GE and ctx.GE:FindFirstChild("DevDungeonDrops")
		if not rf then ctx.status("DevDungeonDrops remote missing", true) return nil end
		local ok, result = pcall(function() return rf:InvokeServer(action, rarity, count) end)
		if not ok or type(result) ~= "table" or not result.ok then
			ctx.status("Dungeon drops failed: " .. tostring((type(result) == "table" and result.error) or result), true)
			return nil
		end
		showMine(result.queued)
		return result
	end

	local function callFake(action, index, a, b)
		local rf = ctx.GE and ctx.GE:FindFirstChild("DevFakeParty")
		if not rf then ctx.status("DevFakeParty remote missing", true) return nil end
		local ok, result = pcall(function() return rf:InvokeServer(action, index, a, b) end)
		if not ok or type(result) ~= "table" or not result.ok then
			ctx.status("Fake party failed: " .. tostring((type(result) == "table" and result.error) or result), true)
			return nil
		end
		fakes = result.fakes or {}
		showFakes()
		return result
	end

	local function count()
		return math.clamp(math.floor(tonumber(boxCount.Text) or 1), 1, 20)
	end

	local function showRarity() disp.Text = RARITIES[sel.rarity] end
	prev.Activated:Connect(function() sel.rarity = Lists.step(sel.rarity, -1, #RARITIES) showRarity() end)
	nxt.Activated:Connect(function() sel.rarity = Lists.step(sel.rarity, 1, #RARITIES) showRarity() end)
	addMine.Activated:Connect(function()
		if callMine("add", RARITIES[sel.rarity], count()) then
			ctx.status(string.format("Queued %d x %s for your next clear", count(), RARITIES[sel.rarity]))
		end
	end)
	clear.Activated:Connect(function()
		if callMine("clear") then ctx.status("Your drop queue is emptied") end
	end)

	fakePrev.Activated:Connect(function() sel.fake = Lists.step(sel.fake, -1, math.max(1, #fakes)) showFakes() end)
	fakeNext.Activated:Connect(function() sel.fake = Lists.step(sel.fake, 1, math.max(1, #fakes)) showFakes() end)
	fakeAdd.Activated:Connect(function()
		if callFake("add") then
			sel.fake = #fakes
			showFakes()
			ctx.status("Added " .. (fakes[sel.fake] and fakes[sel.fake].name or "a fake") .. " (joins your next clear)")
		end
	end)
	fakeRemove.Activated:Connect(function()
		if fakes[sel.fake] and callFake("remove", sel.fake) then ctx.status("Fake removed") end
	end)
	addFake.Activated:Connect(function()
		if not fakes[sel.fake] then return end
		if callFake("drop", sel.fake, RARITIES[sel.rarity], count()) then
			ctx.status(string.format("Gave %s %d x %s", fakes[sel.fake].name, count(), RARITIES[sel.rarity]))
		end
	end)
	fakeClear.Activated:Connect(function()
		if fakes[sel.fake] and callFake("clearDrops", sel.fake) then ctx.status("Their drops are cleared") end
	end)
	fakeMythic.Activated:Connect(function()
		local fake = fakes[sel.fake]
		if not fake then return end
		local nextIndex = 1
		for i, mode in ipairs(FAKE_MODES) do
			if mode[1] == fake.mythic then nextIndex = i % #FAKE_MODES + 1 end
		end
		callFake("mythic", sel.fake, FAKE_MODES[nextIndex][1])
	end)

	showRarity()
	showFakes()
	-- Both lists live on the server and outlast the menu: show what it holds.
	task.spawn(callMine, "get")
	task.spawn(callFake, "get")
	return sec
end

return Tab
