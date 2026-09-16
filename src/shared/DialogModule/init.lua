local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
local VideoSettings = require(game:GetService("ReplicatedStorage"):WaitForChild("VideoSettings"))
-- Dialog zoom-in FOV sits DIALOG_ZOOM_FOV_DELTA studs below VideoSettings.fov
-- (was a hardcoded 65 vs. a hardcoded 70 default) so the Settings menu's FOV
-- slider keeps this feeling proportional at any base FOV.
local DIALOG_ZOOM_FOV_DELTA = 5
-- DialogModule.lua
local DialogModule = {}
DialogModule.__index = DialogModule

local tweenService = game:GetService("TweenService")
local runService = game:GetService('RunService')
local userInputService = game:GetService('UserInputService')
local collectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local DIALOG_STAND_DISTANCE = 5.75

-- Was Quicksand ("rbxasset://fonts/families/Quicksand.json") -- not a real Roblox bundled
-- font family, so this silently fell back to the default font at render time (this is the
-- "Font family rbxasset://fonts/families/Quicksand.json failed to load" warning seen live
-- during actual NPC dialogue). Routed through UIFonts.Families.Body (Work Sans) instead.
local DIALOG_FONT = Font.new(
	UIFonts.Families.Body,
	Enum.FontWeight.Medium,
	Enum.FontStyle.Normal
)
local DIALOG_TEXT_SIZE_DELTA = 3
local DIALOG_TYPEWRITER_DELAY = 0.014
local SPEECH_MIRROR_NAME = "DialogModule_SpeechMirror"
-- Pixels from screen bottom; clears typical stamina/energy bar HUD.
local SPEECH_MIRROR_BOTTOM_INSET = 130

local function applyTypographyToTextLabel(el)
	if not el or not (el:IsA("TextLabel") or el:IsA("TextButton")) then
		return
	end
	el.FontFace = DIALOG_FONT
	el.TextSize = el.TextSize + DIALOG_TEXT_SIZE_DELTA
end

local function applyNpcBillboardTypography(billboard)
	if typeof(billboard) ~= "Instance" or not billboard:IsA("BillboardGui") then
		return
	end
	for _, childName in ipairs({ "name", "arrow", "dialog" }) do
		applyTypographyToTextLabel(billboard:FindFirstChild(childName))
	end
end

-- Some older/hand-placed NPC Head.gui billboards were built before bootstrap scripts
-- started adding UIStroke to name/arrow/dialog labels. DialogModule indexes .UIStroke
-- directly (not FindFirstChild) in several places, so a missing stroke throws
-- "UIStroke is not a valid member of TextLabel" and DialogModule.new fails outright.
local function ensureNpcBillboardStrokes(billboard)
	if typeof(billboard) ~= "Instance" or not billboard:IsA("BillboardGui") then
		return
	end
	for _, childName in ipairs({ "name", "arrow", "dialog" }) do
		local label = billboard:FindFirstChild(childName)
		if label and label:IsA("GuiObject") and not label:FindFirstChildOfClass("UIStroke") then
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(0, 0, 0)
			stroke.Parent = label
		end
	end
end

local function applyResponseOptionTypography(optionButton)
	if not optionButton then
		return
	end
	local t = optionButton:FindFirstChild("text")
	if t then
		applyTypographyToTextLabel(t)
	end
end

-- Inline MenuMouse (CursorUtils) to avoid capability errors with external ModuleScript require
local _menuMouseRefCount      = 0
local _menuMouseSavedBehavior = Enum.MouseBehavior.Default
local _menuMouseSavedIcon     = true
local _MENU_MOUSE_BIND       = "DialogModule_CursorFree"

local function _menuMouseApplyFree()
    userInputService.MouseBehavior    = Enum.MouseBehavior.Default
    userInputService.MouseIconEnabled = true
end

local MenuMouse = {}

function MenuMouse.acquire()
    if _menuMouseRefCount == 0 then
        _menuMouseSavedBehavior = userInputService.MouseBehavior
        _menuMouseSavedIcon     = userInputService.MouseIconEnabled
        pcall(function() runService:UnbindFromRenderStep(_MENU_MOUSE_BIND) end)
        runService:BindToRenderStep(_MENU_MOUSE_BIND, Enum.RenderPriority.Last.Value, _menuMouseApplyFree)
        _menuMouseApplyFree()
    end
    _menuMouseRefCount += 1
end

function MenuMouse.release()
    if _menuMouseRefCount <= 0 then return end
    _menuMouseRefCount -= 1
    if _menuMouseRefCount > 0 then return end
    pcall(function() runService:UnbindFromRenderStep(_MENU_MOUSE_BIND) end)
    userInputService.MouseBehavior    = _menuMouseSavedBehavior
    userInputService.MouseIconEnabled = _menuMouseSavedIcon
end

local function ensureDialogBackdrop(billboard)
	if typeof(billboard) ~= "Instance" or not billboard:IsA("BillboardGui") then
		return
	end
	local backdrop = billboard:FindFirstChild("DialogBackdrop")
	if not backdrop then
		backdrop = Instance.new("Frame")
		backdrop.Name = "DialogBackdrop"
		backdrop.BackgroundColor3 = Color3.fromRGB(18, 14, 12)
		backdrop.BackgroundTransparency = 0.22
		backdrop.BorderSizePixel = 0
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.Position = UDim2.fromScale(0, 0)
		backdrop.ZIndex = 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = backdrop
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Color = Color3.fromRGB(55, 44, 36)
		stroke.Transparency = 0.32
		stroke.Parent = backdrop
		backdrop.Parent = billboard
	end
	backdrop.ZIndex = 1
	backdrop.Visible = false
	for _, childName in ipairs({ "name", "arrow", "dialog" }) do
		local el = billboard:FindFirstChild(childName)
		if el and el:IsA("GuiObject") then
			el.ZIndex = math.max(el.ZIndex, 3)
		end
	end
end

local function beginDialogLocomotionLock(self)
	local player = Players.LocalPlayer
	local char = player and player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if self._savedHumanoidLoco then
		return
	end
	self._savedHumanoidLoco = {
		walk = hum.WalkSpeed,
		jump = hum.JumpPower,
		jumpHeight = hum.JumpHeight,
		autoRotate = hum.AutoRotate,
	}
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	pcall(function()
		hum.JumpHeight = 0
	end)
	hum.AutoRotate = false
end

local function endDialogLocomotionLock(self)
	local saved = self._savedHumanoidLoco
	self._savedHumanoidLoco = nil
	if not saved then
		return
	end
	local player = Players.LocalPlayer
	local char = player and player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	hum.WalkSpeed = saved.walk
	hum.JumpPower = saved.jump
	pcall(function()
		if saved.jumpHeight ~= nil then
			hum.JumpHeight = saved.jumpHeight
		end
	end)
	hum.AutoRotate = saved.autoRotate
end

local function positionPlayerForDialog(npc, player)
	local char = player and player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	local npcRoot = npc and (npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Torso") or npc.PrimaryPart)
	local npcHead = npc and npc:FindFirstChild("Head")
	if not (hrp and hum and hum.Health > 0 and npcRoot and npcHead) then
		return
	end

	local flatLook = npcRoot.CFrame.LookVector
	flatLook = Vector3.new(flatLook.X, 0, flatLook.Z)
	if flatLook.Magnitude < 0.08 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end

	local standXZ = npcRoot.Position + flatLook * DIALOG_STAND_DISTANCE

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { char, npc }

	local hit = Workspace:Raycast(standXZ + Vector3.new(0, 8, 0), Vector3.new(0, -32, 0), rayParams)
	local baseY = hit and hit.Position.Y or npcRoot.Position.Y
	local targetPos = Vector3.new(standXZ.X, baseY + hum.HipHeight + hrp.Size.Y * 0.5, standXZ.Z)

	local tpos = npcHead.Position
	local flat = Vector3.new(tpos.X - targetPos.X, 0, tpos.Z - targetPos.Z)
	if flat.Magnitude >= 0.08 then
		flat = flat.Unit
		hrp.CFrame = CFrame.new(targetPos, targetPos + flat)
	else
		hrp.CFrame = CFrame.new(targetPos) * (npcRoot.CFrame - npcRoot.CFrame.Position)
	end
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

local TICK_SOUND = script.sounds.tick
local END_TICK_SOUND = script.sounds.tick2
local DIALOG_RESPONSES_UI = game.Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("dialog"):WaitForChild("dialogResponses")

local function getSpeechMirrorHolder()
	local uiParent = DIALOG_RESPONSES_UI.Parent
	if uiParent == nil then
		return nil
	end
	local holder = uiParent:FindFirstChild(SPEECH_MIRROR_NAME)
	if holder then
		return holder
	end
	holder = Instance.new("Frame")
	holder.Name = SPEECH_MIRROR_NAME
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.Position = UDim2.fromScale(0, 0)
	holder.ZIndex = 20
	holder.Visible = false
	holder.Parent = uiParent

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -SPEECH_MIRROR_BOTTOM_INSET)
	panel.Size = UDim2.new(0.82, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(18, 14, 12)
	panel.BackgroundTransparency = 0.18
	panel.BorderSizePixel = 0
	panel.ZIndex = 21
	panel.Parent = holder
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke", panel)
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(55, 44, 36)
	stroke.Transparency = 0.32

	local pad = Instance.new("UIPadding", panel)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.FontFace = DIALOG_FONT
	body.TextSize = 20
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.RichText = true
	body.TextColor3 = Color3.fromRGB(238, 232, 228)
	body.ZIndex = 22
	body.Text = ""
	body.Parent = panel

	return holder
end

local function syncSpeechMirrorFromNpcGui(self)
	if not self._speechMirrorWanted then
		return
	end
	local holder = getSpeechMirrorHolder()
	if not holder or not holder.Visible then
		return
	end
	local panel = holder:FindFirstChild("Panel")
	local body = panel and panel:FindFirstChild("Body")
	if not (panel and body and self.npcGui) then
		return
	end
	local src = self.npcGui:FindFirstChild("dialog")
	if not src then
		return
	end
	body.Text = src.Text
	body.TextSize = src.TextSize
	body.FontFace = DIALOG_FONT
	body.TextColor3 = src.TextColor3
	body.TextTransparency = src.TextTransparency
end

local function setSpeechMirrorVisible(self, visible)
	local holder = getSpeechMirrorHolder()
	if not holder then
		return
	end
	holder.Visible = visible
	if visible then
		syncSpeechMirrorFromNpcGui(self)
	end
end

local function endSpeechMirror(self)
	self._speechMirrorWanted = false
	setSpeechMirrorVisible(self, false)
	local bbDialog = self.npcGui and self.npcGui:FindFirstChild("dialog")
	if bbDialog and bbDialog:IsA("GuiObject") then
		bbDialog.Visible = true
	end
end

-- Constructor
function DialogModule.new(npcName, npc, prompt, animation)
	local self = setmetatable({}, DialogModule)
	self.npcName = npcName
	self.npc = npc
	self.dialogs = {} -- Array to store dialog options
	self.responses = {} -- Array to store response options
	self.dialogOption = 1
	self.npcGui = self.npc:WaitForChild("Head"):WaitForChild("gui")
	ensureDialogBackdrop(self.npcGui)
	ensureNpcBillboardStrokes(self.npcGui)
	applyNpcBillboardTypography(self.npcGui)
	self._inConversation = false
	self._savedHumanoidLoco = nil
	self.active = false
	self.talking = false
	self._freeMouseForDialog = false
	self._speechMirrorWanted = false
	self._dialogTextConn = nil
	self.prompt = prompt
	self._onDialogLinePrinted = nil -- optional function(self, player, dialogNum) after a dialog line finishes typing
	
	local template = DIALOG_RESPONSES_UI:FindFirstChild("template")
	if template then
		for i = 1,9 do
			local newResponseButton = template:Clone()
			newResponseButton.Parent = DIALOG_RESPONSES_UI
			newResponseButton.Name = i
			applyResponseOptionTypography(newResponseButton)
		end
		template:Destroy()
	end
	
	local eventSignal = Instance.new("BindableEvent")
	self.responded = eventSignal.Event -- Expose the event to connect to
	self.fireResponded = eventSignal -- Keep a reference to the BindableEvent
		
	-- tween variables
	self.animNameText = tweenService:Create(self.npcGui.name, TweenInfo.new(.3),{TextTransparency = 1})
	self.animNameStroke = tweenService:Create(self.npcGui.name.UIStroke, TweenInfo.new(.3),{Transparency = 1})
	self.animArrowText = tweenService:Create(self.npcGui.arrow, TweenInfo.new(.3),{TextTransparency = 1})
	self.animArrowStroke = tweenService:Create(self.npcGui.arrow.UIStroke, TweenInfo.new(.3),{Transparency = 1})
	self.animDialogText = tweenService:Create(self.npcGui.dialog, TweenInfo.new(.3),{TextTransparency = 1})
	self.animDialogStroke = tweenService:Create(self.npcGui.dialog.UIStroke, TweenInfo.new(.3),{Transparency = 1})
	
	-- animate
	if animation ~= nil then
		local newAnimation = Instance.new("Animation")
		newAnimation.AnimationId = animation
		local newAnimLoaded = npc:WaitForChild("Humanoid"):LoadAnimation(newAnimation)
		newAnimLoaded:Play()
	end
	
	-- Connections
	local frameCount = 0
	local heartbeatConnection = runService.Heartbeat:Connect(function()
		frameCount += 1
		if self.talking then
			self.npcGui.StudsOffset = Vector3.new(0,1.6,0)
		else
			self.npcGui.StudsOffset = Vector3.new(0,math.sin(frameCount/25)/6 + 1.55,0)
		end
		if self._inConversation and not self.talking then
			local localPlayer = Players.LocalPlayer
			local char = localPlayer and localPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local npcRoot = self.npc and (self.npc:FindFirstChild("HumanoidRootPart") or self.npc:FindFirstChild("Torso") or self.npc.PrimaryPart)
			local charRoot = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
			local shouldClose = not char or not hum or hum.Health <= 0
				or (npcRoot and charRoot and (charRoot.Position - npcRoot.Position).Magnitude > 30)
			if shouldClose then
				self._inConversation = false
				self:hideGui()
			end
		end
	end)
	local shownConnection = prompt.PromptShown:Connect(function()
		self.npcGui.AlwaysOnTop = true
	end)
	local hiddenConnection = prompt.PromptHidden:Connect(function()
		if self._inConversation then
			return
		end
		self.npcGui.AlwaysOnTop = false
		local bd = self.npcGui:FindFirstChild("DialogBackdrop")
		if bd then
			bd.Visible = false
		end
	end)
	self._dialogTextConn = self.npcGui.dialog:GetPropertyChangedSignal("Text"):Connect(function()
		if self._speechMirrorWanted then
			syncSpeechMirrorFromNpcGui(self)
		end
	end)
	self.connections = {heartbeatConnection}--,shownConnection,hiddenConnection}
	
	return self
end

-- Add dialog to the NPC
function DialogModule:addDialog(dialogText, responseOptions)
	table.insert(self.dialogs, {text = dialogText, responses = responseOptions})
end

-- Sort dialogs alphabetically or by custom function
function DialogModule:sortDialogs(sortFunc)
	table.sort(self.dialogs, sortFunc or function(a, b) return a.text < b.text end)
end

-- Display the dialog when proximity prompt is triggered
function DialogModule:triggerDialog(player, questionNumber)
	if #self.dialogs == 0 then
		warn("No dialogs available for NPC: " .. self.npcName)
		return
	end

	self._inConversation = true
	beginDialogLocomotionLock(self)
	positionPlayerForDialog(self.npc, player)
	self:showGui()

	local dialogNum = questionNumber or self.dialogOption
	local dialog = self.dialogs[dialogNum] -- Show the first dialog (can be updated for other logic)
	
	tweenService:Create(game.Workspace.CurrentCamera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FieldOfView = VideoSettings.fov - DIALOG_ZOOM_FOV_DELTA}):Play()
	
	task.spawn(function()
		task.wait(0.05)
		self.talking = true
		local dialogObject = self.npcGui.dialog
		dialogObject.Visible = false
		dialogObject.Text = ""
		local currenttext = ""
		local skip = false
		local arrow = 0
		for i, letter in string.split(dialog.text,"") do
			currenttext = currenttext .. letter
			if letter == "<" then skip = true end
			if letter == ">" then skip = false arrow += 1 continue end
			if arrow == 2 then arrow = 0 end
			if skip then continue end
			dialogObject.Text = currenttext .. if arrow == 1 then "</font>" else ""
			TICK_SOUND:Play()
			task.wait(0.02)
		end
		dialogObject.Text = dialog.text
		self.talking = false

		local lineHook = self._onDialogLinePrinted
		if typeof(lineHook) == "function" then
			task.defer(lineHook, self, player, dialogNum)
		end

		-- inputs
		local keyboardInputs = {
			table.unpack(Keys.DialogChoice),
		}

		-- Show responses
		local uiResponses = DIALOG_RESPONSES_UI
		local responseNum = nil
		for i, response in ipairs(dialog.responses) do
			local option = uiResponses[i]
			if not option then
				warn("[DialogModule] Missing response button #" .. tostring(i) .. " for " .. self.npcName)
				break
			end
			-- Escape quotes/tags so apostrophes (e.g. "I'll ...") do not break RichText.
			local esc = tostring(response)
				:gsub("&", "&amp;")
				:gsub("<", "&lt;")
				:gsub(">", "&gt;")
				:gsub("'", "&apos;")
			option.text.Text = "<font color='rgb(255,220,127)'>" .. i .. ".)</font> [''" .. esc .. "'']"
			
			-- calculate x size
			local plaintext = i..".) [''"..response:gsub("%b<>", "").."'']"
			
			option.Size = UDim2.fromScale(option.Size.X.Scale,.4)
			
			option.text.Position = UDim2.new(0.02,0,0.5,0)
			option.Visible = true
			tweenService:Create(option,TweenInfo.new(0.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size = UDim2.new(option.Size.X.Scale,0,0.35,0)}):Play()

			local enterCon = option.MouseEnter:Connect(function()
				tweenService:Create(option,TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size = UDim2.new(option.Size.X.Scale + (option.Size.X.Scale * .05), 0,0.4,0)}):Play()
				tweenService:Create(option.text,TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position = UDim2.new(0.06,0,0.5,0)}):Play()
				END_TICK_SOUND:Play()
			end)

			local leaveCon = option.MouseLeave:Connect(function()
				tweenService:Create(option,TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size = UDim2.new(option.Size.X.Scale, 0,0.35,0)}):Play()
				tweenService:Create(option.text,TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position = UDim2.new(0.02,0,0.5,0)}):Play()
			end)

			local chooseCon = option.MouseButton1Down:Connect(function() -- Return response
				if not self.active then return end
				self.active = false
				responseNum = i
				self.fireResponded:Fire(i, dialogNum)
				TICK_SOUND:Play()
			end)
			
			local numberpressCon = userInputService.InputBegan:Connect(function(input, gameprocessed)
				if gameprocessed then return end
				if input.UserInputType == Enum.UserInputType.Keyboard then
					local numberinput = table.find(keyboardInputs, input.KeyCode)
					if (numberinput ~= nil and numberinput == i) then
						if not self.active then return end
						self.active = false
						responseNum = i
						self.fireResponded:Fire(i, dialogNum)
						TICK_SOUND:Play()
					end
				end
			end)

			coroutine.wrap(function()
				-- unconnectAllConnections
				repeat task.wait() until responseNum ~= nil
				enterCon:Disconnect()
				leaveCon:Disconnect()
				chooseCon:Disconnect()
				numberpressCon:Disconnect()
				option.Visible = false
			end)()

			END_TICK_SOUND:Play()

			task.wait(0.2)
		end

		-- Free cursor only when choosing options so mouse-look camera works during the line.
		if not self._freeMouseForDialog then
			MenuMouse.acquire()
			self._freeMouseForDialog = true
		end

		self.active = true

		while self.active do
			local npcRoot = self.npc:FindFirstChild("HumanoidRootPart") or self.npc:FindFirstChild("Torso") or self.npc.PrimaryPart
			local char = player.Character
			local charRoot = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
			local distance = (npcRoot and charRoot) and (charRoot.Position - npcRoot.Position).Magnitude or 0
			if distance > 30 then
				self:hideGui()
				responseNum = 0
				break
			end
			syncSpeechMirrorFromNpcGui(self)
			task.wait()
		end
	end)
end

function DialogModule:showGui()
	turnProximityPromptsOn(false)
	self.npcGui.AlwaysOnTop = true
	self._speechMirrorWanted = true
	local backdrop = self.npcGui:FindFirstChild("DialogBackdrop")
	if backdrop then
		backdrop.Visible = false
	end
	local bbDialog = self.npcGui:FindFirstChild("dialog")
	if bbDialog and bbDialog:IsA("GuiObject") then
		bbDialog.Visible = false
	end
	setSpeechMirrorVisible(self, true)
	
	self.animNameText:Play()
	self.animNameStroke:Play()
	self.animArrowText:Play()
	self.animArrowStroke:Play()

	self.animDialogText:Cancel()
	self.animDialogStroke:Cancel()
	
	self.npcGui.dialog.TextTransparency = 0
	self.npcGui.dialog.UIStroke.Transparency = 0
	
	coroutine.wrap(function()
		task.wait(0.3)
		
		if self.npcGui.name.TextTransparency ~= 1 then return end -- check if already chose an opiton
		self.npcGui.name.Visible = false
		self.npcGui.arrow.Visible = false
	end)()
end

function DialogModule:hideGui(exitQuip, notActuallyAnExitQuip)
	self._inConversation = false
	self.active = false
	self.talking = true
	notActuallyAnExitQuip = notActuallyAnExitQuip or false
	if self._freeMouseForDialog then
		MenuMouse.release()
		self._freeMouseForDialog = false
	end
	turnProximityPromptsOn(not notActuallyAnExitQuip)

	self.talking = false

	if not exitQuip then
		endSpeechMirror(self)
	end

	if notActuallyAnExitQuip then
		tweenService:Create(game.Workspace.CurrentCamera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FieldOfView = VideoSettings.fov - DIALOG_ZOOM_FOV_DELTA}):Play()
	else
		tweenService:Create(game.Workspace.CurrentCamera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FieldOfView = VideoSettings.fov}):Play()
	end
	
	-- hide player response options
	local playerReponseOptions = DIALOG_RESPONSES_UI
	for i, option in playerReponseOptions:GetChildren() do
		if not option:IsA("GuiButton") then continue end
		option.Visible = false
	end
	
	local dialogObject = self.npcGui.dialog
	if exitQuip then
		self._speechMirrorWanted = true
		setSpeechMirrorVisible(self, true)
		dialogObject.TextTransparency = 0
		dialogObject.UIStroke.Transparency = 0
		self.npcGui.name.TextTransparency = 1
		self.npcGui.name.UIStroke.Transparency = 1
		self.npcGui.arrow.TextTransparency = 1
		self.npcGui.arrow.UIStroke.Transparency = 1
		local currenttext = ""
		dialogObject.Text = ""
		dialogObject.Visible = false
		local skip = false
		local arrow = 0
		for i, letter in string.split(exitQuip,"") do
			if dialogObject.Text ~= currenttext and skip == 0 then warn("other dialog happening") break end
			currenttext = currenttext .. letter
			if letter == "<" then skip = true end
			if letter == ">" then skip = false arrow += 1 continue end
			if arrow == 2 then arrow = 0 end
			if skip then continue end
			dialogObject.Text = currenttext .. if arrow == 1 then "</font>" else ""
			TICK_SOUND:Play()
			task.wait(0.02)
		end
			
		dialogObject.Text = exitQuip
		if notActuallyAnExitQuip then
			endSpeechMirror(self)
			local bd = self.npcGui:FindFirstChild("DialogBackdrop")
			if bd then
				bd.Visible = false
			end
			endDialogLocomotionLock(self)
			return
		end
	end
	
	task.spawn(function()
		if exitQuip then
			wait(2)
			if dialogObject.Text ~= exitQuip then
				endSpeechMirror(self)
				endDialogLocomotionLock(self)
				turnProximityPromptsOn(true)
				return
			end
		end

		if self.npcGui.name.TextTransparency ~= 1 then
			self.animNameText:Cancel()
			self.animNameStroke:Cancel()
			self.animArrowText:Cancel()
			self.animArrowStroke:Cancel()
		end
		self.npcGui.name.TextTransparency = 0
		self.npcGui.name.UIStroke.Transparency = 0
		self.npcGui.arrow.TextTransparency = 0
		self.npcGui.arrow.UIStroke.Transparency = 0
		self.npcGui.name.Visible = true
		self.npcGui.arrow.Visible = true

		self.animDialogText:Play()
		self.animDialogStroke:Play()
		self.npcGui.AlwaysOnTop = false
		endSpeechMirror(self)
		endDialogLocomotionLock(self)
		turnProximityPromptsOn(true)
	end)
end

function DialogModule:nextOption()
	self.dialogOption += 1
	if #self.dialogs < self.dialogOption then warn("No next dialog option for, " .. self.npcName) self.dialogOption -= 1 end
	return self.dialogOption
end

function turnProximityPromptsOn(yes)
	for i, prompt in collectionService:GetTagged("NPCprompt") do
		if prompt:IsA("ProximityPrompt") then
			prompt.Enabled = yes
		end
	end
end

return DialogModule