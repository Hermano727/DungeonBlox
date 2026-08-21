--[[
	WoodenGateScript
	Two-lever gate puzzle: pulling both levers swings the doors open; releasing
	either one closes them again.

	setupGate() wires ONE gate folder (structure: Levers/{Lever1,Lever2} +
	LeftDoor/RightDoor [+ optional *DoorFrame / *Band parts]). All animation
	state (lever flags, gateOpen, animating) lives inside the closure so two
	gates never share state and one gate mid-animation never blocks another.

	Scaling to more than one gate: this used to hard-require a single folder
	named exactly "WoodenGate" in Workspace. It still finds that one by name
	(unchanged behavior for the existing gate), but ALSO wires up any folder
	tagged "WoodenGate" via CollectionService — the same tagging convention
	the NPC/spawner bootstrap scripts already use elsewhere in this codebase.
	So adding a second gate puzzle is just: duplicate the folder, give it the
	CollectionService "WoodenGate" tag, done — no script changes needed.
]]

local CollectionService = game:GetService("CollectionService")

local GATE_TAG = "WoodenGate"

-- Wires levers + doors for a single gate folder. Returns true on success.
local function setupGate(gateFolder)
	local leverFolder = gateFolder:FindFirstChild("Levers")
	local leftDoor = gateFolder:FindFirstChild("LeftDoor")
	local rightDoor = gateFolder:FindFirstChild("RightDoor")
	local leftDoorFrame = gateFolder:FindFirstChild("LeftDoorFrame")
	local rightDoorFrame = gateFolder:FindFirstChild("RightDoorFrame")

	-- Validate all parts exist
	if not leverFolder or not leftDoor or not rightDoor then
		warn(string.format("[WoodenGate] '%s' is missing gate components (Levers/LeftDoor/RightDoor) — skipping", gateFolder:GetFullName()))
		return false
	end

	-- Find lever parts early so we can store their CFrames
	local lever1Handle = leverFolder:FindFirstChild("Lever1Handle")
	local lever1Pole = leverFolder:FindFirstChild("Lever1Pole")
	local lever2Handle = leverFolder:FindFirstChild("Lever2Handle")
	local lever2Pole = leverFolder:FindFirstChild("Lever2Pole")

	-- State tracking (per-gate — this is a closure-local, not a script-level
	-- global, so multiple gates driven by this same script never interfere)
	local lever1Active = false
	local lever2Active = false
	local gateOpen = false
	local animating = false

	-- Collect all door-related parts (doors, frames, and bands)
	local leftDoorParts = {leftDoor}
	local rightDoorParts = {rightDoor}

	if leftDoorFrame then table.insert(leftDoorParts, leftDoorFrame) end
	if rightDoorFrame then table.insert(rightDoorParts, rightDoorFrame) end

	-- Find and add bands to their respective door groups
	for _, child in gateFolder:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name:find("LeftBand") then
				table.insert(leftDoorParts, child)
			elseif child.Name:find("RightBand") then
				table.insert(rightDoorParts, child)
			end
		end
	end

	-- Store original CFrames for all door parts
	local leftDoorClosedCFrames = {}
	for i, part in leftDoorParts do
		leftDoorClosedCFrames[part] = part.CFrame
	end

	local rightDoorClosedCFrames = {}
	for i, part in rightDoorParts do
		rightDoorClosedCFrames[part] = part.CFrame
	end

	-- Calculate open CFrames (doors swing inward around their inner edges, hinged to the door frames)
	-- Left door swings around its right edge (inner edge, toward center/door frame)
	local leftPivotOffset = CFrame.new(0, 0, -leftDoor.Size.Z / 2)
	local leftRotation = CFrame.Angles(0, math.rad(-60), 0)

	-- Right door swings around its left edge (inner edge, toward center/door frame)
	local rightPivotOffset = CFrame.new(0, 0, -rightDoor.Size.Z / 2)
	local rightRotation = CFrame.Angles(0, math.rad(60), 0)

	-- Calculate open CFrames for all left door parts
	local leftDoorOpenCFrames = {}
	for part, closedCF in leftDoorClosedCFrames do
		leftDoorOpenCFrames[part] = closedCF * leftPivotOffset * leftRotation * leftPivotOffset:Inverse()
	end

	-- Calculate open CFrames for all right door parts
	local rightDoorOpenCFrames = {}
	for part, closedCF in rightDoorClosedCFrames do
		rightDoorOpenCFrames[part] = closedCF * rightPivotOffset * rightRotation * rightPivotOffset:Inverse()
	end

	-- Store original lever CFrames for animation
	local lever1PoleClosedCFrame = lever1Pole and lever1Pole.CFrame or nil
	local lever1HandleClosedCFrame = lever1Handle and lever1Handle.CFrame or nil
	local lever2PoleClosedCFrame = lever2Pole and lever2Pole.CFrame or nil
	local lever2HandleClosedCFrame = lever2Handle and lever2Handle.CFrame or nil

	-- Calculate pulled (open) CFrames for levers
	local function getLeverOpenCFrames(pole, handle, poleClosedCF, handleClosedCF)
		if not pole or not handle or not poleClosedCF or not handleClosedCF then return nil, nil end
		local pivotOffset = CFrame.new(0, -pole.Size.Y / 2, 0)
		local openPoleCF = poleClosedCF * pivotOffset * CFrame.Angles(math.rad(-45), 0, 0) * pivotOffset:Inverse()
		local openHandleCF = openPoleCF * CFrame.new(0, pole.Size.Y / 2 + handle.Size.Y / 2, 0)
		return openPoleCF, openHandleCF
	end

	local lever1PoleOpenCFrame, lever1HandleOpenCFrame = getLeverOpenCFrames(lever1Pole, lever1Handle, lever1PoleClosedCFrame, lever1HandleClosedCFrame)
	local lever2PoleOpenCFrame, lever2HandleOpenCFrame = getLeverOpenCFrames(lever2Pole, lever2Handle, lever2PoleClosedCFrame, lever2HandleClosedCFrame)

	-- Animate a group of parts smoothly from one set of CFrames to another
	local function animateDoorGroup(parts, fromCFrames, toCFrames, duration)
		local startTime = tick()
		while true do
			local elapsed = tick() - startTime
			local alpha = math.min(elapsed / duration, 1)
			-- Smooth easing (ease-in-out)
			local easedAlpha = alpha < 0.5
				and 2 * alpha * alpha
				or 1 - ((-2 * alpha + 2) ^ 2) / 2
			for _, part in parts do
				local fromCF = fromCFrames[part]
				local toCF = toCFrames[part]
				if fromCF and toCF then
					part.CFrame = fromCF:Lerp(toCF, easedAlpha)
				end
			end
			if alpha >= 1 then break end
			task.wait()
		end
	end

	-- Open or close the gate
	local function setGateOpen(open)
		if animating then return end
		animating = true

		if open then
			-- Open both door groups (doors + bands, frames stay fixed)
			task.spawn(animateDoorGroup, leftDoorParts, leftDoorClosedCFrames, leftDoorOpenCFrames, 1.5)
			task.spawn(animateDoorGroup, rightDoorParts, rightDoorClosedCFrames, rightDoorOpenCFrames, 1.5)
			task.wait(1.5)
			-- Disable collision on doors so players can walk through
			leftDoor.CanCollide = false
			rightDoor.CanCollide = false
		else
			-- Re-enable collision before closing
			leftDoor.CanCollide = true
			rightDoor.CanCollide = true
			-- Close both door groups
			task.spawn(animateDoorGroup, leftDoorParts, leftDoorOpenCFrames, leftDoorClosedCFrames, 1.5)
			task.spawn(animateDoorGroup, rightDoorParts, rightDoorOpenCFrames, rightDoorClosedCFrames, 1.5)
			task.wait(1.5)
		end

		gateOpen = open
		animating = false
	end

	-- Animate lever pull (rotate the pole and handle)
	local function animateLever(leverHandle, leverPole, active, poleClosedCF, handleClosedCF, poleOpenCF, handleOpenCF)
		if not leverHandle or not leverPole then return end
		if not poleClosedCF or not handleClosedCF or not poleOpenCF or not handleOpenCF then return end

		local fromPoleCF = active and poleClosedCF or poleOpenCF
		local toPoleCF = active and poleOpenCF or poleClosedCF
		local fromHandleCF = active and handleClosedCF or handleOpenCF
		local toHandleCF = active and handleOpenCF or handleClosedCF

		-- Quick animation
		local duration = 0.4
		local startTime = tick()
		while true do
			local elapsed = tick() - startTime
			local alpha = math.min(elapsed / duration, 1)
			leverPole.CFrame = fromPoleCF:Lerp(toPoleCF, alpha)
			leverHandle.CFrame = fromHandleCF:Lerp(toHandleCF, alpha)
			if alpha >= 1 then break end
			task.wait()
		end
	end

	-- Update lever prompt text and style
	local function updateLeverPrompt(prompt, active)
		if not prompt then return end
		if active then
			prompt.ObjectText = "Lever (Pulled)"
			prompt.ActionText = "Reset"
		else
			prompt.ObjectText = "Lever"
			prompt.ActionText = "Pull"
		end
	end

	-- Check if both levers are active and open/close the gate
	local function checkLevers()
		if lever1Active and lever2Active and not gateOpen then
			setGateOpen(true)
		elseif (not lever1Active or not lever2Active) and gateOpen then
			setGateOpen(false)
		end
	end

	-- Setup Lever 1
	local prompt1 = lever1Handle and lever1Handle:FindFirstChild("LeverPrompt")

	if prompt1 then
		prompt1.Triggered:Connect(function(player)
			lever1Active = not lever1Active
			updateLeverPrompt(prompt1, lever1Active)
			animateLever(lever1Handle, lever1Pole, lever1Active, lever1PoleClosedCFrame, lever1HandleClosedCFrame, lever1PoleOpenCFrame, lever1HandleOpenCFrame)
			checkLevers()
		end)
	end

	-- Setup Lever 2
	local prompt2 = lever2Handle and lever2Handle:FindFirstChild("LeverPrompt")

	if prompt2 then
		prompt2.Triggered:Connect(function(player)
			lever2Active = not lever2Active
			updateLeverPrompt(prompt2, lever2Active)
			animateLever(lever2Handle, lever2Pole, lever2Active, lever2PoleClosedCFrame, lever2HandleClosedCFrame, lever2PoleOpenCFrame, lever2HandleOpenCFrame)
			checkLevers()
		end)
	end

	print(string.format("[WoodenGate] '%s' initialized - pull both levers to open!", gateFolder:GetFullName()))
	return true
end

----------------------------------------------------------------------
-- Bootstrap: wire the legacy named folder plus any tagged gate folders.
----------------------------------------------------------------------

local wired = {} -- dedupe: a folder found both by name and by tag only gets wired once

local function tryWire(gateFolder)
	if not gateFolder or wired[gateFolder] then return end
	wired[gateFolder] = true
	setupGate(gateFolder)
end

-- Original single-gate lookup, kept as-is so the existing "WoodenGate"
-- folder keeps working with zero setup changes.
local legacyGate = game.Workspace:FindFirstChild("WoodenGate")
if legacyGate then
	tryWire(legacyGate)
elseif #CollectionService:GetTagged(GATE_TAG) == 0 then
	-- Only warn about the missing legacy folder if there's no tag-based gate
	-- either — otherwise this is just an old, no-longer-used lookup.
	warn("WoodenGate folder not found in Workspace")
end

-- Opt-in scaling path: any folder tagged "WoodenGate" (Studio > Tag Editor)
-- gets wired the same way, present at boot or added later.
for _, gateFolder in ipairs(CollectionService:GetTagged(GATE_TAG)) do
	tryWire(gateFolder)
end
CollectionService:GetInstanceAddedSignal(GATE_TAG):Connect(tryWire)
