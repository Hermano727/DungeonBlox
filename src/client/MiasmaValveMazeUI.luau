--[[
	MiasmaValveMazeUI -- the valve maze screen: rendering, local cursor, and sample batching.

	Rules live on the server (MiasmaMazeService). This module only:
		- draws what MazeOpened sent (walls, drain, eight runes, progress slots);
		- turns the traced token into the pointer: the OS cursor is hidden and locked in place
		  while the maze is open, and the token moves by the mouse's movement, so it can never
		  drift out of line with the hand (and snaps back to the drain on a reset);
		- runs the SAME wall check as the server (MiasmaMazeGeometry) so a wall hit resets
		  instantly on screen, and reports it by bumping the attempt epoch;
		- latches the token onto any rune it touches and waits for the server's verdict
		  (the client never knows which runes are the target, by design);
		- sends the traced path to the server ~15 times a second.

	It never shows the target pattern. Progress slots show only runes already collected.

	Input: movement is locked through the PlayerModule controls; the mouse is held with
	MouseBehavior.LockCurrentPosition (re-applied every frame at RenderPriority.Last so no
	camera script can take it back). The first-person camera only turns under LockCenter,
	so the view stays still. Everything is restored on close.

	Styling: the STYLE table below. Layout scales from the viewport; coordinate mapping uses
	the board's real AbsolutePosition/AbsoluteSize, so it holds at any window size.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local Geometry = require(ReplicatedStorage:WaitForChild("MiasmaMazeGeometry"))
local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local RuneArt = require(ReplicatedStorage:WaitForChild("MiasmaRuneArt"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local player = Players.LocalPlayer
local VALVE = Config.Gates.Valve
local SEND_INTERVAL = 1 / Config.Gates.MazeSampleRate
local MAX_POINTS_PER_BATCH = math.min(24, VALVE.MaxPointsPerBatch)
local MIN_STEP = .002
local LOCK_ACTION = "MiasmaValveMovementLock"
local RELEASE_ACTION = "MiasmaValveRelease"
local STEP_NAME = "MiasmaValveMazeStep"
local POINTER_BIND = "MiasmaValvePointerLock"
-- Board-widths the token travels per board-width of mouse movement (1 = one-to-one).
local POINTER_GAIN = 1
-- Token speed cap, kept under the server's MaxCursorSpeed so a flick never "slips".
local POINTER_MAX_SPEED = VALVE.MaxCursorSpeed * .8

local STYLE = {
	Backdrop = Color3.fromRGB(4, 6, 5),
	BackdropTransparency = .42,
	Panel = Color3.fromRGB(24, 25, 22),
	PanelEdge = Color3.fromRGB(104, 70, 44),
	PanelEdgeDanger = Color3.fromRGB(200, 60, 48),
	Board = Color3.fromRGB(13, 19, 16),
	BoardEdge = Color3.fromRGB(62, 56, 46),
	Wall = Color3.fromRGB(96, 86, 70),
	Title = Color3.fromRGB(216, 204, 176),
	Body = Color3.fromRGB(160, 150, 130),
	RuneIdle = Color3.fromRGB(196, 184, 156),
	RunePending = Color3.fromRGB(250, 206, 110),
	RuneTaken = Color3.fromRGB(140, 236, 190),
	RuneTakenGlow = Color3.fromRGB(70, 200, 140),
	Token = Color3.fromRGB(226, 244, 230),
	TokenRing = Color3.fromRGB(140, 236, 190),
	Trail = Color3.fromRGB(110, 210, 160),
	Guide = Color3.fromRGB(250, 206, 110),
	Drain = Color3.fromRGB(34, 40, 36),
	Fail = Color3.fromRGB(190, 50, 60),
	Blob = Color3.fromRGB(96, 34, 128),      -- Miasma's poison blob (a lob that hit a valve operator)
	BlobEdge = Color3.fromRGB(170, 90, 220),
	BlobCrack = Color3.fromRGB(20, 8, 26),
	Success = Color3.fromRGB(150, 230, 255),
	SlotEmpty = Color3.fromRGB(34, 34, 30),
	Button = Color3.fromRGB(58, 40, 30),
	ButtonText = Color3.fromRGB(224, 200, 170),
}

local MESSAGES = {
	Idle = "Your mouse moves the line. Trace to the runes you read on the plate.",
	Tracing = "Trace to the runes you read on the plate.",
	Pending = "The rune is being read...",
	Taken = "The rune takes. Find the next.",
	Wall = "Wall struck. The line returns to the drain.",
	WrongSymbol = "Wrong rune. The line returns to the drain.",
	Slipped = "The valve slipped. The line returns to the drain.",
	TooFast = "Too hasty. The line returns to the drain.",
	Complete = "THE VALVE TURNS",
	Danger = "Danger below. Release with X.",
}

local UI = {}
local state = nil

local function new(className, props, parent)
	local item = Instance.new(className)
	for key, value in pairs(props) do item[key] = value end
	if parent then item.Parent = parent end
	return item
end

local function corner(parent, scale, offset)
	return new("UICorner", { CornerRadius = UDim.new(scale or 0, offset or 0) }, parent)
end

local function tween(instance, seconds, goal, style, direction)
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- Input lock -----------------------------------------------------------------------------

local function getControls()
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then return nil end
	local ok, playerModule = pcall(require, module)
	return ok and playerModule and playerModule:GetControls() or nil
end

local function lockInput()
	local controls = getControls()
	if controls then controls:Disable() end
	ContextActionService:BindActionAtPriority(LOCK_ACTION, function() return Enum.ContextActionResult.Sink end, false, 3000,
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down,
		Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.C,
		Keys.Dash, Keys.TogglePerspective, Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl)
end

local pointerSaved = nil

local function holdPointer()
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	UserInputService.MouseIconEnabled = false
end

-- Hides and parks the OS cursor; the token becomes the pointer.
local function lockPointer()
	if not pointerSaved then
		pointerSaved = { behavior = UserInputService.MouseBehavior, icon = UserInputService.MouseIconEnabled }
	end
	pcall(function() RunService:UnbindFromRenderStep(POINTER_BIND) end)
	RunService:BindToRenderStep(POINTER_BIND, Enum.RenderPriority.Last.Value, holdPointer)
	holdPointer()
end

local function unlockPointer()
	pcall(function() RunService:UnbindFromRenderStep(POINTER_BIND) end)
	local saved = pointerSaved
	pointerSaved = nil
	if not saved then return end
	UserInputService.MouseBehavior = saved.behavior
	UserInputService.MouseIconEnabled = saved.icon
	-- Same re-assert CursorUtils does: first person only turns under LockCenter.
	if saved.behavior == Enum.MouseBehavior.LockCenter then
		task.defer(function()
			if not pointerSaved then UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter end
		end)
	end
end

local function unlockInput()
	ContextActionService:UnbindAction(LOCK_ACTION)
	ContextActionService:UnbindAction(RELEASE_ACTION)
	unlockPointer()
	local controls = getControls()
	if controls then controls:Enable() end
end

-- Rendering ------------------------------------------------------------------------------

local function layoutSizes()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local board = math.floor(math.clamp(math.min(viewport.Y * .6, viewport.X * .84 - 40, 620), 220, 620))
	-- No header and no text anywhere (2026-09-27: the puzzle is meant to be immersive -- no
	-- title, hints, status line or button labels). The footer only holds the rune progress.
	local header = 0
	local footer = math.floor(math.clamp(board * .12, 40, 72))
	local pad = math.floor(math.clamp(board * .035, 10, 22))
	return board, header, footer, pad
end

local function applyLayout()
	if not state then return end
	local board, header, footer, pad = layoutSizes()
	state.panel.Size = UDim2.fromOffset(board + pad * 2, header + board + footer + pad * 2)
	state.header.Size = UDim2.new(1, -pad * 2, 0, header)
	state.header.Position = UDim2.fromOffset(pad, pad)
	state.board.Size = UDim2.fromOffset(board, board)
	state.board.Position = UDim2.fromOffset(pad, pad + header)
	state.footer.Size = UDim2.new(1, -pad * 2, 0, footer)
	state.footer.Position = UDim2.fromOffset(pad, pad + header + board)
end

local function segmentFrame(parent, a, b, thickness, color, transparency, zIndex)
	local delta = b - a
	local frame = new("Frame", {
		AnchorPoint = Vector2.new(.5, .5),
		Position = UDim2.fromScale((a.X + b.X) / 2, (a.Y + b.Y) / 2),
		Size = UDim2.fromScale(delta.Magnitude + thickness, thickness),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = zIndex or 2,
	}, parent)
	corner(frame, .5)
	return frame
end

local function circle(parent, name, centre, radius, color, transparency, zIndex)
	local frame = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(.5, .5),
		Position = UDim2.fromScale(centre.X, centre.Y),
		Size = UDim2.fromScale(radius * 2, radius * 2),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = zIndex or 2,
	}, parent)
	corner(frame, .5)
	return frame
end

local function setStatus(key, color)
	if not state or not state.status then return end -- no status line any more (no text)
	state.status.Text = MESSAGES[key] or key
	state.status.TextColor3 = color or STYLE.Body
end

local function renderProgress()
	if not state then return end
	for _, child in ipairs(state.progress:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local taken = {}
	for _, placement in ipairs(state.placements) do
		if state.collected[placement.id] then table.insert(taken, placement.id) end
	end
	for index = 1, state.requiredCount do
		local slot = new("Frame", {
			Name = "Slot" .. index,
			LayoutOrder = index,
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = STYLE.SlotEmpty,
			BorderSizePixel = 0,
		}, state.progress)
		new("UIAspectRatioConstraint", { AspectRatio = 1 }, slot)
		corner(slot, .15)
		new("UIStroke", { Color = taken[index] and STYLE.RuneTakenGlow or STYLE.BoardEdge, Thickness = 2 }, slot)
		if taken[index] then
			local inner = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromScale(.74, .74) }, slot)
			RuneArt.Render(inner, taken[index], { Color = STYLE.RuneTaken, GlowColor = STYLE.RuneTakenGlow, GlowTransparency = .65, ZIndex = 3 })
		end
	end
end

local function paintRunes()
	if not state then return end
	for index, placement in ipairs(state.placements) do
		local rune = state.runeFrames[index]
		if state.collected[placement.id] then
			RuneArt.SetColor(rune, STYLE.RuneTaken, 0, STYLE.RuneTakenGlow, .55)
		elseif state.latched == index then
			RuneArt.SetColor(rune, STYLE.RunePending, 0, STYLE.RunePending, .6)
		else
			RuneArt.SetColor(rune, STYLE.RuneIdle, 0, STYLE.RuneIdle, 1)
		end
	end
end

local function clearTrail()
	if not state then return end
	for _, frame in ipairs(state.trailFrames) do frame:Destroy() end
	table.clear(state.trailFrames)
	state.trailFrom = state.token
end

local function moveToken(point)
	state.token = point
	state.tokenFrame.Position = UDim2.fromScale(point.X, point.Y)
	state.tokenRing.Position = state.tokenFrame.Position
	if (point - state.trailFrom).Magnitude >= state.metrics.cursorRadius * .6 then
		if #state.trailFrames < 400 then
			table.insert(state.trailFrames, segmentFrame(state.trailLayer, state.trailFrom, point, state.metrics.cursorRadius * .7, STYLE.Trail, .4, 3))
		end
		state.trailFrom = point
	end
end

local function flash(color)
	if not state then return end
	state.flashFrame.BackgroundColor3 = color
	state.flashFrame.BackgroundTransparency = .55
	tween(state.flashFrame, .45, { BackgroundTransparency = 1 })
end

local function shake()
	if not state then return end
	local panel = state.panel
	task.spawn(function()
		for i = 1, 6 do
			if not state or state.panel ~= panel then return end
			panel.Position = UDim2.new(.5, (i % 2 == 0 and 1 or -1) * (7 - i), .5, 0)
			task.wait(.03)
		end
		if state and state.panel == panel then panel.Position = UDim2.fromScale(.5, .5) end
	end)
end

-- Networking -----------------------------------------------------------------------------

local function flush()
	if not state then return end
	state.lastSend = os.clock()
	if #state.pending == 0 then return end
	local points = state.pending
	state.pending = {}
	state.send({ session = state.session, epoch = state.epoch, points = points })
end

local function queuePoint(point)
	state.lastQueued = point
	table.insert(state.pending, point.X)
	table.insert(state.pending, point.Y)
	if #state.pending >= MAX_POINTS_PER_BATCH * 2 then flush() end
end

-- Resets the attempt on screen. `bumpEpoch` = we detected it locally and must tell the server.
local function applyReset(reason, newEpoch)
	if not state then return end
	state.pending = {}
	if newEpoch then
		state.epoch = newEpoch
	else
		state.epoch += 1
		-- Empty batch with the new epoch = "I restarted"; the server follows immediately.
		state.send({ session = state.session, epoch = state.epoch, points = {} })
		state.lastSend = os.clock()
	end
	table.clear(state.collected)
	state.latched = nil
	state.pointerDelta = Vector2.zero
	state.token = state.start
	state.lastQueued = state.start
	state.tokenFrame.Position = UDim2.fromScale(state.start.X, state.start.Y)
	state.tokenRing.Position = state.tokenFrame.Position
	clearTrail()
	paintRunes()
	renderProgress()
	flash(STYLE.Fail)
	shake()
	setStatus(reason, STYLE.Fail)
end

-- Frame step -----------------------------------------------------------------------------

local function isCollected(index)
	return state.collected[state.placements[index].id] == true
end

local function step(dt)
	if not state or state.closing then return end
	local now = os.clock()
	local metrics = state.metrics
	local boardSize = state.board.AbsoluteSize.X
	local pixels = state.pointerDelta
	state.pointerDelta = Vector2.zero

	if state.latched then
		-- Waiting for the server's verdict on a rune: the token stays on it.
		if now - state.latchedAt > VALVE.LatchTimeout then applyReset("Slipped") end
	elseif boardSize > 0 and pixels.Magnitude > 0 then
		local move = pixels / boardSize * POINTER_GAIN
		local maxStep = POINTER_MAX_SPEED * math.max(dt or 0, 1 / 240)
		if move.Magnitude > maxStep then move = move.Unit * maxStep end
		local from = state.token
		local target = from + move
		local blob = state.blob
		-- Never trap the token: if it's already inside (shouldn't happen, see UI.Blob), let it go.
		if blob and not blob.popping and (from - blob.position).Magnitude >= blob.block then
			-- Solid: the token stops at the edge (binary search along the move). Touching is fine.
			local block = blob.block
			if (target - blob.position).Magnitude < block or (Geometry.PointSegment(blob.position, from, target)) < block then
				local lo, hi = 0, 1
				for _ = 1, 8 do
					local mid = (lo + hi) / 2
					if (from:Lerp(target, mid) - blob.position).Magnitude < block * 1.001 then hi = mid else lo = mid end
				end
				target = from:Lerp(target, lo)
				if not blob.touching then
					blob.touching = true
					-- Local thud now; the server's ram count arrives with MazeBlob.
					tween(blob.frame, .06, { Size = UDim2.fromScale(blob.radius * 1.8, blob.radius * 1.8) })
					task.delay(.07, function()
						if blob.frame.Parent then tween(blob.frame, .12, { Size = UDim2.fromScale(blob.radius * 2, blob.radius * 2) }) end
					end)
				end
			elseif (target - blob.position).Magnitude > block * 1.3 then
				blob.touching = false
			end
		end
		if Geometry.SegmentHitsWall(from, target, state.walls, metrics.wallMargin) then
			applyReset("Wall")
		else
			local contact = Geometry.FirstSlotContact(from, target, state.slots, metrics.symbolRadius, isCollected)
			if contact then
				local centre = state.slots[contact]
				if Geometry.SegmentHitsWall(from, centre, state.walls, metrics.wallMargin) then
					applyReset("Wall")
				else
					moveToken(centre)
					queuePoint(centre)
					state.latched = contact
					state.latchedAt = now
					paintRunes()
					setStatus("Pending", STYLE.RunePending)
					flush()
				end
			else
				moveToken(target)
				if (target - state.lastQueued).Magnitude >= MIN_STEP then
					queuePoint(target)
				end
			end
		end
	end

	if state and #state.pending > 0 and now - state.lastSend >= SEND_INTERVAL then flush() end
end

-- Public API -----------------------------------------------------------------------------

function UI.IsOpen()
	return state ~= nil
end

local function teardown()
	if not state then return end
	local closing = state
	state = nil
	for _, connection in ipairs(closing.connections) do connection:Disconnect() end
	RunService:UnbindFromRenderStep(STEP_NAME)
	if closing.gui then closing.gui:Destroy() end
	player:SetAttribute("MiasmaMazeOpen", nil)
	unlockInput()
end

--[[
	Open(payload, send, cancel)
		payload  MazeOpened from the server
		send     function(batchTable) -> fires MazeSample
		cancel   function() -> fires CancelValve
]]
function UI.Open(payload, send, cancel)
	teardown()
	if type(payload) ~= "table" or typeof(payload.start) ~= "Vector2" then return end

	local slots, placements = {}, {}
	for index, symbol in ipairs(payload.symbols or {}) do
		slots[index] = symbol.position
		placements[index] = { id = symbol.id, position = symbol.position }
	end
	local geometry = { cell = tonumber(payload.cell) or (1 / 7), walls = payload.walls or {}, start = payload.start, slots = slots }
	local metrics = Geometry.Metrics(geometry, false)

	local gui = new("ScreenGui", {
		Name = "MiasmaValveMaze",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	-- Full-screen button: swallows clicks so combat/tool input never fires under the maze.
	local backdrop = new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = STYLE.Backdrop,
		BackgroundTransparency = STYLE.BackdropTransparency,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
	}, gui)
	-- Top-right: how to let go of the valve (the maze itself stays text-free).
	do
		local okFont, hintFont = pcall(Font.fromName, "Oswald", Enum.FontWeight.SemiBold)
		hintFont = okFont and hintFont or Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
		local hint = new("Frame", {
			Name = "CloseHint",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -28, 0, 28),
			Size = UDim2.fromOffset(176, 58),
			BackgroundColor3 = Color3.fromRGB(10, 12, 16),
			BackgroundTransparency = .2,
			BorderSizePixel = 0,
			ZIndex = 20,
		}, gui)
		corner(hint, 0, 8)
		new("UIStroke", { Color = Color3.fromRGB(96, 214, 255), Thickness = 2, Transparency = .35 }, hint)
		new("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(18, 0),
			Size = UDim2.new(1, -86, 1, 0),
			FontFace = hintFont,
			Text = "CLOSE",
			TextSize = 30,
			TextColor3 = Color3.fromRGB(236, 239, 244),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 21,
		}, hint)
		local key = new("TextLabel", {
			Name = "Key",
			AnchorPoint = Vector2.new(1, .5),
			Position = UDim2.new(1, -12, .5, 0),
			Size = UDim2.fromOffset(46, 40),
			BackgroundColor3 = Color3.fromRGB(96, 214, 255),
			BorderSizePixel = 0,
			FontFace = hintFont,
			Text = Keys.ReleaseValve and Keys.ReleaseValve.Name or "X",
			TextSize = 28,
			TextColor3 = Color3.fromRGB(10, 12, 16),
			ZIndex = 21,
		}, hint)
		corner(key, 0, 6)
	end

	local panel = new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(.5, .5),
		Position = UDim2.fromScale(.5, .5),
		BackgroundColor3 = STYLE.Panel,
		BorderSizePixel = 0,
	}, backdrop)
	corner(panel, 0, 8)
	local panelStroke = new("UIStroke", { Color = STYLE.PanelEdge, Thickness = 3 }, panel)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 165)),
	}, panel)

	-- Kept as an empty, zero-height frame so applyLayout's stacking stays as it was.
	local header = new("Frame", { Name = "Header", BackgroundTransparency = 1 }, panel)

	local board = new("Frame", {
		Name = "Board",
		BackgroundColor3 = STYLE.Board,
		BorderSizePixel = 0,
		ClipsDescendants = false,
	}, panel)
	new("UIStroke", { Color = STYLE.BoardEdge, Thickness = 2 }, board)
	local trailLayer = new("Frame", { Name = "Trail", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, board)
	local wallLayer = new("Frame", { Name = "Walls", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4 }, board)
	local runeLayer = new("Frame", { Name = "Runes", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, board)
	local tokenLayer = new("Frame", { Name = "Token", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6 }, board)
	local flashFrame = new("Frame", { Name = "Flash", BackgroundTransparency = 1, BackgroundColor3 = STYLE.Fail, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 8 }, board)

	-- Walls: drawn with the same half-thickness the collision uses.
	for _, wall in ipairs(geometry.walls) do
		segmentFrame(wallLayer, wall[1], wall[2], metrics.wallHalfThickness * 2, STYLE.Wall, 0, 4)
	end

	-- Drain (start).
	local drain = circle(runeLayer, "Drain", payload.start, geometry.cell * .36, STYLE.Drain, 0, 2)
	new("UIStroke", { Color = STYLE.BoardEdge, Thickness = 2 }, drain)
	for i = -1, 1 do
		new("Frame", {
			AnchorPoint = Vector2.new(.5, .5),
			Position = UDim2.fromScale(.5 + i * .24, .5),
			Size = UDim2.fromScale(.09, .62),
			BackgroundColor3 = STYLE.BoardEdge,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, drain)
	end

	-- Runes.
	local runeFrames = {}
	for index, placement in ipairs(placements) do
		local holder = new("Frame", {
			Name = "Slot" .. index,
			AnchorPoint = Vector2.new(.5, .5),
			Position = UDim2.fromScale(placement.position.X, placement.position.Y),
			Size = UDim2.fromScale(geometry.cell * .72, geometry.cell * .72),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, runeLayer)
		runeFrames[index] = RuneArt.Render(holder, placement.id, { Color = STYLE.RuneIdle, GlowColor = STYLE.RuneIdle, GlowTransparency = 1, Thickness = .1, ZIndex = 2 })
	end

	local tokenRing = circle(tokenLayer, "Ring", payload.start, metrics.cursorRadius * 2, STYLE.TokenRing, .72, 6)
	local tokenFrame = circle(tokenLayer, "Core", payload.start, metrics.cursorRadius, STYLE.Token, 0, 7)
	new("UIStroke", { Color = STYLE.TokenRing, Thickness = 2 }, tokenFrame)

	local footer = new("Frame", { Name = "Footer", BackgroundTransparency = 1 }, panel)
	local progress = new("Frame", {
		Name = "Progress",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, .15),
		Size = UDim2.fromScale(1, .7),
	}, footer)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, progress)
	-- No status line and no Release button: releasing is the X / close key (bound below).

	state = {
		gui = gui,
		panel = panel,
		panelStroke = panelStroke,
		header = header,
		board = board,
		footer = footer,
		progress = progress,
		status = nil,
		trailLayer = trailLayer,
		flashFrame = flashFrame,
		tokenFrame = tokenFrame,
		tokenRing = tokenRing,
		runeFrames = runeFrames,
		trailFrames = {},
		session = payload.session,
		epoch = tonumber(payload.epoch) or 0,
		requiredCount = tonumber(payload.requiredCount) or 3,
		walls = geometry.walls,
		slots = slots,
		placements = placements,
		start = payload.start,
		token = payload.start,
		trailFrom = payload.start,
		metrics = metrics,
		collected = {},
		pending = {},
		lastSend = 0,
		pointerDelta = Vector2.zero,
		lastQueued = payload.start,
		latched = nil,
		latchedAt = 0,
		closing = false,
		send = send,
		connections = {},
	}

	applyLayout()
	renderProgress()
	setStatus("Idle")
	gui.Parent = player:WaitForChild("PlayerGui")
	-- HealthClient / EnergyClient move their bars out of the maze's way while this is set.
	player:SetAttribute("MiasmaMazeOpen", true)
	lockInput()
	lockPointer()

	local function requestRelease()
		if state and not state.closing then
			cancel()
			teardown()
		end
	end
	ContextActionService:BindActionAtPriority(RELEASE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then requestRelease() end
		return Enum.ContextActionResult.Sink
	end, false, 3001, Keys.ReleaseValve, Keys.CloseMenu)
	local camera = Workspace.CurrentCamera
	if camera then
		table.insert(state.connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout))
	end
	-- Mouse movement arrives as deltas while the pointer is locked in place.
	table.insert(state.connections, UserInputService.InputChanged:Connect(function(input)
		if state and input.UserInputType == Enum.UserInputType.MouseMovement then
			state.pointerDelta += Vector2.new(input.Delta.X, input.Delta.Y)
		end
	end))
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Input.Value + 1, step)
end

function UI.Progress(payload)
	if not state or type(payload) ~= "table" or payload.session ~= state.session then return end
	if tonumber(payload.epoch) ~= state.epoch then return end
	table.clear(state.collected)
	for _, id in ipairs(payload.collected or {}) do state.collected[id] = true end
	if state.latched and state.collected[state.placements[state.latched].id] then
		state.latched = nil -- keep holding: tracing continues from the rune
		setStatus("Taken", STYLE.RuneTaken)
	end
	paintRunes()
	renderProgress()
end

-- Miasma's lob landed on the valve: a poison blob blocks the path until rammed away.
--   spawn   { session, position, radius, hits }
--   ram     { session, hp }       (server-counted; shows cracks, shrinks a little)
--   pop     { session, popped = true }
function UI.Blob(payload)
	if not state or type(payload) ~= "table" or payload.session ~= state.session then return end
	local blob = state.blob
	if typeof(payload.position) == "Vector2" then
		local radius = tonumber(payload.radius) or (state.metrics.cursorRadius * 2.8)
		-- Landed on (or right next to) the token: refuse it and tell the server to drop it too.
		-- (The server places it 2-3 cells out, but its view of the token lags ours.)
		if (state.token - payload.position).Magnitude < Geometry.BlobBlockRadius(state.metrics, radius) * 1.5 then
			state.send({ session = state.session, epoch = state.epoch, points = {}, blobCancel = true })
			return
		end
		-- One blob at a time.
		if blob and blob.frame then blob.frame:Destroy() end
		local layer = state.tokenFrame.Parent
		local frame = circle(layer, "PoisonBlob", payload.position, radius, STYLE.Blob, 0, 5)
		new("UIStroke", { Color = STYLE.BlobEdge, Thickness = 3 }, frame)
		frame.Size = UDim2.fromScale(0, 0)
		tween(frame, .25, { Size = UDim2.fromScale(radius * 2, radius * 2) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		state.blob = {
			position = payload.position,
			radius = radius,
			block = Geometry.BlobBlockRadius(state.metrics, radius),
			hits = tonumber(payload.hits) or 5,
			hp = tonumber(payload.hits) or 5,
			frame = frame,
			cracks = {},
		}
		UI.Warn()
		return
	end
	if not blob then return end
	if payload.popped then
		blob.popping = true
		state.blob = nil
		tween(blob.frame, .18, { Size = UDim2.fromScale(blob.radius * 2.8, blob.radius * 2.8), BackgroundTransparency = 1 })
		local stroke = blob.frame:FindFirstChildOfClass("UIStroke")
		if stroke then tween(stroke, .18, { Transparency = 1 }) end
		for _, crack in ipairs(blob.cracks) do tween(crack, .12, { BackgroundTransparency = 1 }) end
		task.delay(.25, function() blob.frame:Destroy() end)
		flash(STYLE.RuneTaken)
		return
	end
	local hp = tonumber(payload.hp)
	if not hp then return end
	blob.hp = hp
	-- One more crack per ram, and a little smaller each time.
	local crack = new("Frame", {
		AnchorPoint = Vector2.new(.5, .5),
		Position = UDim2.fromScale(.5 + (math.random() - .5) * .3, .5 + (math.random() - .5) * .3),
		Size = UDim2.fromScale(.75, .07),
		Rotation = math.random(0, 179),
		BackgroundColor3 = STYLE.BlobCrack,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, blob.frame)
	table.insert(blob.cracks, crack)
	blob.radius *= .94
	tween(blob.frame, .1, { Size = UDim2.fromScale(blob.radius * 2, blob.radius * 2) })
	shake()
end

function UI.Reset(payload)
	if not state or type(payload) ~= "table" or payload.session ~= state.session then return end
	local epoch = tonumber(payload.epoch)
	if not epoch or epoch <= state.epoch then return end -- we already restarted locally
	applyReset(payload.reason or "Wall", epoch)
end

-- Server closed the maze. Returns true when it was a success (caller may celebrate).
function UI.Close(payload)
	if not state then return false end
	payload = payload or {}
	if payload.reason == "Complete" then
		state.closing = true
		for _, placement in ipairs(state.placements) do
			if state.latched and placement == state.placements[state.latched] then state.collected[placement.id] = true end
		end
		state.latched = nil
		paintRunes()
		renderProgress()
		setStatus("Complete", STYLE.Success)
		flash(STYLE.Success)
		tween(state.panelStroke, .3, { Color = STYLE.Success })
		local closing = state
		task.delay(VALVE.CompleteHold, function()
			if state == closing then teardown() end
		end)
		return true
	end
	teardown()
	return false
end

-- Local teardown with no server message (character removed, encounter gone).
function UI.ForceClose()
	teardown()
end

-- A hazard is about to land on the operator: make it impossible to miss.
function UI.Warn()
	if not state or state.closing then return end
	setStatus("Danger", STYLE.PanelEdgeDanger)
	state.panelStroke.Color = STYLE.PanelEdgeDanger
	flash(STYLE.PanelEdgeDanger)
	local current = state
	task.delay(1.2, function()
		if state == current and not state.closing then state.panelStroke.Color = STYLE.PanelEdge end
	end)
end

return UI
