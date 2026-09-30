local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Protocol = require(ReplicatedStorage:WaitForChild("MiasmaEncounterProtocol"))
local EncounterVFX = require(script.Parent:WaitForChild("MiasmaEncounterVFX"))
local MazeUI = require(script.Parent:WaitForChild("MiasmaValveMazeUI"))
local CleanseUI = require(script.Parent:WaitForChild("MiasmaCleanseUI"))
local CenterFlashUI = require(script.Parent:WaitForChild("CenterFlashUI"))
local StatusCleanseClient = require(script.Parent:WaitForChild("StatusCleanseClient"))
local gameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local event = gameEvents:WaitForChild("MiasmaEncounterEvent")
local request = gameEvents:WaitForChild("MiasmaEncounterRequest")

-- Why a valve would not take you (Presentation "ValveDenied"), and why it let go of you
-- (MazeClosed). Reasons with no entry are silent (you pressed Release, you died, ...).
local DENIED_TEXT = {
	Choked = "The valve is choked with growth",
	Reserved = "Someone is already at this valve",
	TooFar = "Step closer to the valve",
	NotNow = "The valve will not turn now",
	Inactive = "This channel is not needed",
}
local CLOSED_TEXT = {
	Damaged = "Your grip breaks",
	Interrupted = "Your grip breaks",
	Moved = "Knocked from the valve",
	TooFar = "Too far from the valve",
	Purge = "The valve seizes",
	BossRecovered = "Miasma recovers",
	CycleReset = "The valve seizes",
}

local currentEncounterId
local gui = Instance.new("ScreenGui")
gui.Name = "MiasmaEncounterGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

local warning = Instance.new("Frame")
warning.Name = "WarningVignette"
warning.Size = UDim2.fromScale(1, 1)
warning.BackgroundColor3 = Color3.fromRGB(80, 10, 95)
warning.BackgroundTransparency = 1
warning.BorderSizePixel = 0
warning.Parent = gui

local function nearLocalPlayer(payload)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	if payload.target == player then return true end -- the poison lob marked us
	if typeof(payload.position) == "Vector3" then
		local flat = Vector3.new(root.Position.X - payload.position.X, 0, root.Position.Z - payload.position.Z)
		return flat.Magnitude <= (tonumber(payload.radius) or 5) + 3
	end
	if typeof(payload.from) == "Vector3" and typeof(payload.to) == "Vector3" then
		local a, b = payload.from, payload.to
		local ab = b - a
		local t = math.clamp((root.Position - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
		return (root.Position - (a + ab * t)).Magnitude <= 5
	end
	return false
end

-- The purple poison tint follows the replicated stack count (Protocol.Attributes.PoisonStacks),
-- not only the PoisonChanged event: the encounter being torn down clears the attribute without
-- an event, and the tint used to stay up after the dungeon ended.
local poisonTint = 1
local function applyPoisonTint()
	local stacks = tonumber(player:GetAttribute(Protocol.Attributes.PoisonStacks)) or 0
	poisonTint = stacks > 0 and math.clamp(.97 - stacks * .025, .82, .95) or 1
	warning.BackgroundTransparency = poisonTint
end
player:GetAttributeChangedSignal(Protocol.Attributes.PoisonStacks):Connect(applyPoisonTint)

local function pulseWarning(duration)
	warning.BackgroundTransparency = .82
	task.delay(duration or .35, function() if warning.Parent then warning.BackgroundTransparency = poisonTint end end)
end

event.OnClientEvent:Connect(function(encounterId, eventName, payload)
	currentEncounterId = encounterId
	payload = payload or {}
	if eventName == Protocol.Events.MazeOpened then
		MazeUI.Open(payload, function(batch)
			request:FireServer(encounterId, Protocol.Requests.MazeSample, batch)
		end, function()
			request:FireServer(encounterId, Protocol.Requests.CancelValve)
		end)
	elseif eventName == Protocol.Events.MazeProgress then
		MazeUI.Progress(payload)
	elseif eventName == Protocol.Events.MazeReset then
		MazeUI.Reset(payload)
	elseif eventName == Protocol.Events.MazeBlob then
		MazeUI.Blob(payload)
	elseif eventName == Protocol.Events.MazeClosed then
		local wasOpen = MazeUI.IsOpen()
		local success = MazeUI.Close(payload)
		if wasOpen and not success and CLOSED_TEXT[payload.reason] then CenterFlashUI.Show(CLOSED_TEXT[payload.reason]) end
	elseif eventName == Protocol.Events.Telegraph then
		EncounterVFX.Telegraph(payload)
		if MazeUI.IsOpen() and nearLocalPlayer(payload) then MazeUI.Warn() end
	elseif eventName == Protocol.Events.Presentation then
		EncounterVFX.Presentation(payload)
		if payload.kind == "ValveDenied" and DENIED_TEXT[payload.reason] then CenterFlashUI.Show(DENIED_TEXT[payload.reason]) end
		if payload.kind == "GatesAwaken" and type(payload.names) == "table" and #payload.names > 0 then
			local list = table.concat(payload.names, ", ")
			CenterFlashUI.Show(#payload.names == 1 and ("The " .. list .. " valve awakens") or ("Valves awaken: " .. list))
		end
		if payload.kind == "Staggered" then
			CenterFlashUI.Show("Miasma reels. Reach the valve!")
		elseif payload.kind == "StaggerRecovered" and not MazeUI.IsOpen() then
			CenterFlashUI.Show("Miasma recovers")
		end
		if payload.kind == "AltarChannel" then
			CleanseUI.BeginChannel(payload, function()
				request:FireServer(encounterId, Protocol.Requests.CancelAltar)
			end)
		elseif payload.kind == "AltarSuccess" then
			CleanseUI.Succeed(payload)
		elseif payload.kind == "AltarInterrupted" then
			CleanseUI.Interrupt(payload)
		end
		if payload.kind == "Failed" or payload.kind == "Defeated" then MazeUI.ForceClose(); CleanseUI.ForceClose() end
		-- The final valve's cutscene takes every camera: nobody is left staring at a finished maze.
		if payload.kind == "PureWaterCutscene" then MazeUI.ForceClose() end
		if payload.kind == "PurgeWarning" or payload.kind == "Enrage" then pulseWarning(.45) end
		if payload.kind == "CycleFinalWarning" then
			local encounterAtStart = currentEncounterId
			task.spawn(function()
				local pulses = math.max(1, math.floor((tonumber(payload.duration) or 15) / 3))
				for _ = 1, pulses do
					if currentEncounterId ~= encounterAtStart then return end
					pulseWarning(.18)
					task.wait(3)
				end
			end)
		end
	elseif eventName == Protocol.Events.PoisonChanged then
		local stacks = tonumber(payload.stacks) or 0
		poisonTint = stacks > 0 and math.clamp(.97 - stacks * .025, .82, .95) or 1
		warning.BackgroundTransparency = poisonTint
	end
end)

player.CharacterRemoving:Connect(function() MazeUI.ForceClose(); CleanseUI.ForceClose() end)

-- Full cleanse: your own effects always go (tint, valve/cleanse UIs). Leaving or ending the
-- dungeon also stops the whole fight's visuals (shroud grade, auras, cutscenes); a death
-- doesn't, since a dead member keeps watching the fight as a spectator.
StatusCleanseClient.Register("MiasmaEncounter", function(reason)
	poisonTint = 1
	warning.BackgroundTransparency = 1
	MazeUI.ForceClose()
	CleanseUI.ForceClose()
	if reason == "DungeonLeft" or reason == "DungeonEnded" then
		currentEncounterId = nil
		EncounterVFX.StopAll()
	end
end)
