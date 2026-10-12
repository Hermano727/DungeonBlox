--[[
	Showcase -- the animation showcase (server: SSS/AnimationShowcase).

	Every MobData mob with a model stands on its own pedestal on a platform far off the map
	(Workspace.AnimationShowcase, built by the server the first time a dev opens this tab), idling.
	Pick a mob to see what it can play: every clip registered for it in MobAnimConfig (Idle, Walk,
	Attack, each Moveset clip...) and every Cast special in its MobData Moveset (Kane's Fire Tornado,
	with all its effects). Play loops it until Stop or another Play. The server plays everything, so
	anyone standing there sees the same thing.

	Choosing a mob: click it in the list to be taken to its pedestal; while you're on the platform
	the tab also follows you, selecting whichever pedestal you stand nearest. "Return" puts you back
	where you were before your first jump to the showcase.
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local Tab = { key = "Showcase", label = "Showcase", group = "Media" }

local catalog = nil   -- { mobs = { { id, name, tier, pedestal, anims = { {key,label} }, playing } }, origin }
local selectedId = nil
local shown = false
local ui = {}

local function remote(ctx)
	return ctx.GE and ctx.GE:FindFirstChild("DevShowcase")
end

local function call(ctx, action, ...)
	local rf = remote(ctx)
	if not rf then ctx.status("DevShowcase remote missing", true) return nil end
	local args = table.pack(...)
	local ok, result = pcall(function() return rf:InvokeServer(action, table.unpack(args, 1, args.n)) end)
	if not ok or type(result) ~= "table" or not result.ok then
		ctx.status("Showcase: " .. tostring((type(result) == "table" and result.error) or result), true)
		return nil
	end
	return result
end

local function findMob(id)
	for _, mob in ipairs(catalog and catalog.mobs or {}) do
		if mob.id == id then return mob end
	end
	return nil
end

local renderDetail

local function renderList(ctx)
	for _, child in ipairs(ui.list:GetChildren()) do
		if child:IsA("GuiButton") then child:Destroy() end
	end
	for i, mob in ipairs(catalog and catalog.mobs or {}) do
		local b = ctx.mkB(ui.list, string.format("%s   T%d", mob.name, mob.tier), 0, 0, 0, 30,
			mob.id == selectedId and ctx.Ui.Color.Good or nil)
		b.Size = UDim2.new(1, -8, 0, 30)
		b.LayoutOrder = i
		b.TextXAlignment = Enum.TextXAlignment.Left
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.Parent = b
		b.Activated:Connect(function()
			selectedId = mob.id
			renderList(ctx)
			renderDetail(ctx)
			if call(ctx, "goto", mob.id) then ctx.status("At " .. mob.name .. "'s pedestal") end
		end)
	end
end

renderDetail = function(ctx)
	for _, child in ipairs(ui.anims:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	local mob = findMob(selectedId)
	if not mob then
		ui.title.Text = "Pick a mob"
		ui.sub.Text = "Click one in the list, or walk up to a pedestal on the platform."
		return
	end
	ui.title.Text = mob.name
	ui.sub.Text = string.format("%s   tier %d   %d animation%s", mob.id, mob.tier, #mob.anims, #mob.anims == 1 and "" or "s")
	if #mob.anims == 0 then
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 30)
		row.BackgroundTransparency = 1
		row.Parent = ui.anims
		ctx.lbl(row, "No animations registered in MobAnimConfig for this mob.", 4, 0, 600, 30, 14, ctx.Ui.Color.Muted)
		return
	end
	for i, anim in ipairs(mob.anims) do
		local playing = mob.playing == anim.key
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 36)
		row.BackgroundColor3 = playing and Color3.fromRGB(40, 64, 40) or Color3.fromRGB(44, 32, 24)
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = ui.anims
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
		ctx.lbl(row, anim.label, 12, 0, 500, 36, 15, playing and ctx.Ui.Color.Status or ctx.Ui.Color.Text)
		local play = ctx.mkB(row, playing and "Playing" or "Play", 0, 4, 110, 28, playing and ctx.Ui.Color.Good or nil)
		play.AnchorPoint = Vector2.new(1, 0)
		play.Position = UDim2.new(1, -8, 0, 4)
		play.Activated:Connect(function()
			if call(ctx, "play", mob.id, anim.key) then
				mob.playing = anim.key
				renderDetail(ctx)
				ctx.status("Playing " .. anim.label .. " on " .. mob.name .. " (loops)")
			end
		end)
	end
end

local function loadCatalog(ctx)
	ctx.status("Building the showcase (first time only)...")
	local result = call(ctx, "catalog")
	if not result then return end
	catalog = result
	ctx.status(#catalog.mobs .. " mobs on the showcase")
	if not selectedId and catalog.mobs[1] then selectedId = catalog.mobs[1].id end
	renderList(ctx)
	renderDetail(ctx)
end

function Tab.Build(ctx)
	local Ui, lbl, mkB = ctx.Ui, ctx.lbl, ctx.mkB
	local sec = Ui.section(ctx, "ShowcaseSection")
	local LEFT_W = 280

	mkB(sec, "Go to showcase", 12, 2, LEFT_W, 32, Color3.fromRGB(50, 70, 110)).Activated:Connect(function()
		if call(ctx, "goto", selectedId) then ctx.status("At the animation showcase") end
	end)
	mkB(sec, "Return to where I was", 12, 40, LEFT_W, 32).Activated:Connect(function()
		if call(ctx, "return") then ctx.status("Back") end
	end)
	lbl(sec, "MOBS", 12, 84, 120, 16, 12, ctx.acc, true)
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(12, 104)
	list.Size = UDim2.new(0, LEFT_W, 1, -114)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = Ui.Color.Rim
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = sec
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
	ui.list = list

	local x = LEFT_W + 36
	local right = ctx.w - x - 12
	ui.title = lbl(sec, "Pick a mob", x, 2, right, 32, 24, Ui.Color.Gold, true)
	pcall(function() ui.title.FontFace = Ui.Font.Heading end)
	ui.sub = lbl(sec, "", x, 36, right, 20, 14, Ui.Color.Muted)
	mkB(sec, "Stop", x, 62, 120, 30, Ui.Color.Bad).Activated:Connect(function()
		local mob = findMob(selectedId)
		if mob and call(ctx, "stop", mob.id) then
			mob.playing = nil
			renderDetail(ctx)
			ctx.status("Stopped " .. mob.name)
		end
	end)
	mkB(sec, "Stand in front", x + 128, 62, 160, 30).Activated:Connect(function()
		if selectedId and call(ctx, "goto", selectedId) then ctx.status("At the pedestal") end
	end)
	lbl(sec, "ANIMATIONS (Play loops it until Stop)", x, 104, right, 16, 12, ctx.acc, true)
	local anims = Instance.new("ScrollingFrame")
	anims.Position = UDim2.fromOffset(x, 124)
	anims.Size = UDim2.new(0, right, 1, -134)
	anims.BackgroundTransparency = 1
	anims.BorderSizePixel = 0
	anims.ScrollBarThickness = 5
	anims.ScrollBarImageColor3 = Ui.Color.Rim
	anims.AutomaticCanvasSize = Enum.AutomaticSize.Y
	anims.CanvasSize = UDim2.new()
	anims.Parent = sec
	local animLayout = Instance.new("UIListLayout")
	animLayout.Padding = UDim.new(0, 4)
	animLayout.SortOrder = Enum.SortOrder.LayoutOrder
	animLayout.Parent = anims
	ui.anims = anims

	-- Follow the player on the platform: the nearest pedestal becomes the selection.
	task.spawn(function()
		while true do
			task.wait(0.5)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if shown and catalog and root and (root.Position - catalog.origin).Magnitude < catalog.span then
				local best, bestDist = nil, math.huge
				for _, mob in ipairs(catalog.mobs) do
					local d = (Vector3.new(mob.pedestal.X, 0, mob.pedestal.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
					if d < bestDist then best, bestDist = mob, d end
				end
				if best and best.id ~= selectedId then
					selectedId = best.id
					renderList(ctx)
					renderDetail(ctx)
				end
			end
		end
	end)
	return sec
end

function Tab.OnShow(ctx)
	shown = true
	if not catalog then task.spawn(loadCatalog, ctx) end
end

function Tab.OnHide()
	shown = false
end

return Tab
