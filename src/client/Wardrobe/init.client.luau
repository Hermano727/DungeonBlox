--[[
	Wardrobe -- character customization, opened from any wardrobe's "Customize" prompt
	(AppearanceService names those prompts "WardrobePrompt"; wardrobes only exist in safe zones).

	Open:  fade to black -> fetch the saved appearance -> hide every other UI (HudHider), free
	       the cursor (CursorUtils), freeze movement -> build the grass-field stage
	       (WardrobeStage) with your character on it -> show the menu (WardrobeMenu) -> fade in.
	Confirm saves through GameEvents/AppearanceRequest (the server validates, saves and applies
	it to your real character, so everyone sees it) and closes. Cancel / Esc closes without
	saving. Close runs the same steps in reverse, behind the same fade.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AppearanceOptions = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Appearance"):WaitForChild("AppearanceOptions"))
local CursorUtils = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local HudHider = require(script.Parent:WaitForChild("HudHider"))
local WardrobeStage = require(script:WaitForChild("WardrobeStage"))
local WardrobeMenu = require(script:WaitForChild("WardrobeMenu"))

local player = Players.LocalPlayer
local PROMPT_NAME = "WardrobePrompt"
local FREEZE_ACTION = "WardrobeFreeze"
local FADE_IN, FADE_OUT = .3, .45

local request -- GameEvents/AppearanceRequest, found lazily (the server creates it)
local function getRequest()
	if request then return request end
	local ge = ReplicatedStorage:WaitForChild("GameEvents", 10)
	request = ge and ge:WaitForChild("AppearanceRequest", 10)
	return request
end

local state -- the open session, or nil

local function fade(frame, to, seconds)
	local t = TweenService:Create(frame, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { BackgroundTransparency = to })
	t:Play()
	t.Completed:Wait()
end

local function freezeMovement(on)
	if on then
		ContextActionService:BindActionAtPriority(FREEZE_ACTION, function() return Enum.ContextActionResult.Sink end, false,
			Enum.ContextActionPriority.High.Value + 100,
			Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down,
			Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.LeftControl,
			Enum.KeyCode.C, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.F, Enum.KeyCode.R, Enum.KeyCode.Tab,
			Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
			Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine)
	else
		ContextActionService:UnbindAction(FREEZE_ACTION)
	end
end

local function setPrompts(enabled)
	pcall(function() ProximityPromptService.Enabled = enabled end)
end

local close

local function open()
	if state then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "Wardrobe"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 900
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local black = Instance.new("Frame")
	black.Name = "Fade"
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.ZIndex = 100
	black.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	state = { gui = gui, black = black, busy = true }
	local session = state
	freezeMovement(true)
	setPrompts(false)

	-- Fetch while the screen goes dark.
	local saved = AppearanceOptions.Default()
	local fetched = false
	task.spawn(function()
		local rf = getRequest()
		if rf then
			local ok, result = pcall(rf.InvokeServer, rf, "get")
			if ok and type(result) == "table" then saved = result end
		end
		fetched = true
	end)
	fade(black, 0, FADE_IN)
	local waitStart = os.clock()
	while not fetched and os.clock() - waitStart < 5 do task.wait() end
	if state ~= session then return end

	session.releaseHud = HudHider.Acquire(gui)
	CursorUtils.acquire()
	session.cursor = true
	session.stage = WardrobeStage.Open(character)
	if not session.stage then close(true) return end
	session.stage:ApplyAppearance(saved)

	session.menu = WardrobeMenu.new(gui, saved, {
		onPreview = function(draft) if session.stage then session.stage:ApplyAppearance(draft) end end,
		onRotate = function(degrees) if session.stage then session.stage:Rotate(degrees) end end,
		onCategory = function(category) if session.stage then session.stage:SetFocus(category and category.Focus) end end,
		onConfirm = function(draft)
			local rf = getRequest()
			if not rf then return false, "Could not reach the server." end
			local ok, success, result = pcall(rf.InvokeServer, rf, "set", draft)
			if not ok or not success then
				return false, (result == "slow_down") and "One moment." or "Could not save. Try again."
			end
			task.defer(close)
			return true
		end,
		onCancel = function() close() end,
	})

	-- Dying / respawning mid-wardrobe: drop straight out.
	session.diedConn = humanoid.Died:Connect(function() close(true) end)
	session.removedConn = player.CharacterRemoving:Connect(function() close(true) end)

	fade(black, 1, FADE_OUT)
	session.busy = false
end

close = function(instant)
	local session = state
	if not session or session.closing then return end
	session.closing = true
	if not instant then fade(session.black, 0, FADE_IN) end
	if session.diedConn then session.diedConn:Disconnect() end
	if session.removedConn then session.removedConn:Disconnect() end
	if session.menu then session.menu:Destroy() end
	if session.stage then session.stage:Close() end
	if session.cursor then CursorUtils.release() end
	if session.releaseHud then session.releaseHud() end
	freezeMovement(false)
	setPrompts(true)
	state = nil
	if instant then
		session.gui:Destroy()
	else
		fade(session.black, 1, FADE_OUT)
		session.gui:Destroy()
	end
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player or prompt.Name ~= PROMPT_NAME then return end
	task.spawn(open)
end)
