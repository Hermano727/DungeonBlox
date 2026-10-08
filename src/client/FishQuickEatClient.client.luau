--[[
	FishQuickEatClient
	The cooked-fish slot on the HUD (left of the hunger pips, in HealthClient's FishIconsMount)
	and the quick-eat key (2026-10-03). Same shape as the potion slot: key chip, icon, count.

	  - The slot shows the SELECTED cooked-fish kind and how many you carry (bag, hotbar, equip
	    boxes; not the bank), read from the profile snapshot. The plain fish is the default.
	  - Tap Keys.QuickEat (V) to eat one of the selected kind (GameEvents/QuickEatFish).
	  - Hold it HOLD_TIME to switch to the next kind you carry (CookingConfig.QUICK_EAT_ITEMS
	    order). One switch per hold: let go and hold again for the next. The key chip fills up
	    while you hold, so you can see when it'll switch.
	  - A refusal (full, none) shakes the slot and flashes why.
	Until the fish icon is uploaded (ConsumableIcons.T1_COOKED_FISH) the slot shows a plain
	placeholder disc instead of a picture.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local CookingConfig = require(ReplicatedStorage:WaitForChild("CookingConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local HudBarStyle = require(ReplicatedStorage:WaitForChild("HudBarStyle"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))
local CenterFlashUI = require(script.Parent:WaitForChild("CenterFlashUI"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local QuickEatFish = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("QuickEatFish")

local ICON_SIZE = 24
local KEY_SIZE = 16
local PLACEHOLDER = Color3.fromRGB(150, 112, 70) -- a cooked-brown disc until the icon exists
local REFUSE_COLOR = Color3.fromRGB(220, 60, 50)

local HOLD_TIME = 0.8 -- held this long, the key switches kind instead of eating

local carried = 0
local eating = false
local selected = CookingConfig.QUICK_EAT_ITEM -- the kind V eats
local kinds = {} -- carried kinds, { itemId, count }, from the last snapshot
local render -- forward-declared: built with the UI below
local showName -- forward-declared: a brief name tag over the slot while stepping
local setHoldFill -- forward-declared: the key chip's hold-progress fill (0..1)

---------------------------------------------------------------------------
-- The key
---------------------------------------------------------------------------

local shake -- forward-declared: built with the UI below

local function quickEat()
	if eating then return end
	eating = true
	task.spawn(function()
		local ok, okEat, reason = pcall(QuickEatFish.InvokeServer, QuickEatFish, selected)
		eating = false
		if ok and okEat then
			SfxService.PlayEffect("FishEat")
			DungeonMenuNet.requestSync()
		elseif ok then
			if shake then shake() end
			CenterFlashUI.Show(CookingConfig.EAT_REFUSALS[reason] or "You can't eat right now")
		end
	end)
end

-- One step to the next carried kind after `selected` (wrapping). False if there's nothing else.
local function stepSelection(): boolean
	if #kinds < 2 then return false end
	local at = 0
	for i, k in ipairs(kinds) do
		if k.itemId == selected then at = i end
	end
	local nextKind = kinds[at % #kinds + 1]
	selected = nextKind.itemId
	carried = nextKind.count
	SfxService.PlayEffect("TabSwitch")
	if render then render() end
	if showName then showName() end
	return true
end

local pressId = 0
local stepped = false
ContextActionService:BindActionAtPriority("FishQuickEat", function(_, state)
	if UserInputService:GetFocusedTextBox() ~= nil or GuiService.MenuIsOpen then return Enum.ContextActionResult.Pass end
	if state == Enum.UserInputState.Begin then
		pressId += 1
		local myPress = pressId
		stepped = false
		-- Only worth showing the fill when there's something to switch to.
		if #kinds < 2 then return Enum.ContextActionResult.Sink end
		task.spawn(function()
			local started = os.clock()
			while pressId == myPress do
				local u = (os.clock() - started) / HOLD_TIME
				if setHoldFill then setHoldFill(math.min(u, 1)) end
				if u >= 1 then
					stepped = stepSelection()
					break -- one switch per hold
				end
				task.wait()
			end
			if setHoldFill then setHoldFill(0) end
		end)
	elseif state == Enum.UserInputState.End then
		pressId += 1 -- ends the hold
		if setHoldFill then setHoldFill(0) end
		if not stepped then quickEat() end
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value, Keys.QuickEat)
script.Destroying:Connect(function() ContextActionService:UnbindAction("FishQuickEat") end)

---------------------------------------------------------------------------
-- The slot, built into HealthClient's mount once it exists
---------------------------------------------------------------------------

local mount
repeat
	mount = playerGui:FindFirstChild("FishIconsMount", true)
	if not mount then task.wait(0.5) end
until mount

local function label(parent, text, size)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = UIFonts.HUDLabel
	t.TextSize = size
	t.TextColor3 = HudBarStyle.BONE
	t.TextStrokeTransparency = 0.35
	t.Text = text
	t.Parent = parent
	return t
end

local keyChip = Instance.new("Frame")
keyChip.Name = "FishKey"
keyChip.LayoutOrder = 1
keyChip.Size = UDim2.fromOffset(KEY_SIZE, KEY_SIZE)
keyChip.BackgroundColor3 = HudBarStyle.TROUGH
keyChip.BackgroundTransparency = HudBarStyle.TROUGH_TRANSPARENCY
keyChip.Parent = mount
Instance.new("UICorner", keyChip).CornerRadius = UDim.new(0, 3)
local keyStroke = Instance.new("UIStroke")
keyStroke.Color = HudBarStyle.BRONZE
keyStroke.Transparency = 0.2
keyStroke.Parent = keyChip
-- Fills up from the bottom while V is held (the switch happens when it's full).
local holdFill = Instance.new("Frame")
holdFill.Name = "HoldFill"
holdFill.AnchorPoint = Vector2.new(0, 1)
holdFill.Position = UDim2.fromScale(0, 1)
holdFill.Size = UDim2.fromScale(1, 0)
holdFill.BackgroundColor3 = HudBarStyle.BRONZE
holdFill.BackgroundTransparency = 0.25
holdFill.BorderSizePixel = 0
holdFill.Parent = keyChip
Instance.new("UICorner", holdFill).CornerRadius = UDim.new(0, 3)
setHoldFill = function(u)
	holdFill.Size = UDim2.fromScale(1, u)
end
local keyText = label(keyChip, Keys.QuickEat.Name, 11)
keyText.Size = UDim2.fromScale(1, 1)
keyText.ZIndex = 2

local icon = Instance.new("ImageLabel")
icon.Name = "FishCarried"
icon.LayoutOrder = 2
icon.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
icon.BackgroundTransparency = 1
icon.ScaleType = Enum.ScaleType.Fit
icon.Parent = mount
local iconRest = icon.Position

-- Placeholder while there is no icon art: a small cooked-brown disc in a bronze ring.
local placeholder = Instance.new("Frame")
placeholder.AnchorPoint = Vector2.new(0.5, 0.5)
placeholder.Position = UDim2.fromScale(0.5, 0.5)
placeholder.Size = UDim2.fromScale(0.7, 0.7)
placeholder.BackgroundColor3 = PLACEHOLDER
placeholder.Parent = icon
Instance.new("UICorner", placeholder).CornerRadius = UDim.new(1, 0)
local placeholderStroke = Instance.new("UIStroke")
placeholderStroke.Color = HudBarStyle.BRONZE
placeholderStroke.Parent = placeholder

local countText = label(icon, "", 12)
countText.AnchorPoint = Vector2.new(1, 1)
countText.Position = UDim2.new(1, 4, 1, 3)
countText.Size = UDim2.fromOffset(16, 12)
countText.TextXAlignment = Enum.TextXAlignment.Right
countText.ZIndex = 2

-- The selected kind's name, shown briefly above the slot while stepping.
local nameTag = label(icon, "", 12)
nameTag.AnchorPoint = Vector2.new(0.5, 1)
nameTag.Position = UDim2.new(0.5, 0, 0, -4)
nameTag.Size = UDim2.fromOffset(0, 14)
nameTag.AutomaticSize = Enum.AutomaticSize.X
nameTag.ZIndex = 3
nameTag.TextTransparency = 1
nameTag.TextStrokeTransparency = 1
local nameToken = 0
showName = function()
	local def = ItemDefinitions.Get(selected)
	nameTag.Text = (def and def.DisplayName) or selected
	nameTag.TextTransparency = 0
	nameTag.TextStrokeTransparency = 0.35
	nameToken += 1
	local mine = nameToken
	task.delay(1.2, function()
		if nameToken ~= mine then return end
		TweenService:Create(nameTag, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

render = function()
	local image = ItemDefinitions.GetIcon(selected)
	icon.Image = image
	placeholder.Visible = image == ""
	local faded = carried == 0
	icon.ImageTransparency = faded and 0.65 or 0
	placeholder.BackgroundTransparency = faded and 0.65 or 0
	placeholderStroke.Transparency = faded and 0.6 or 0
	countText.Text = carried > 0 and tostring(carried) or ""
	keyChip.BackgroundTransparency = faded and 0.6 or HudBarStyle.TROUGH_TRANSPARENCY
	keyText.TextTransparency = faded and 0.55 or 0
end

shake = function()
	keyStroke.Color = REFUSE_COLOR
	task.delay(0.35, function() keyStroke.Color = HudBarStyle.BRONZE end)
	local nudge = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
	icon.Position = iconRest
	TweenService:Create(icon, nudge, { Position = iconRest + UDim2.fromOffset(3, 0) }):Play()
end

DungeonMenuNet.addSnapshotListener(function(snapshot)
	local profile = snapshot and snapshot.profile
	kinds = CookingConfig.CarriedQuickEatKinds(profile)
	-- Ran out of the selected kind: fall back to the plain fish, else the first kind carried.
	if CookingConfig.CountQuickEat(profile, selected) == 0 and #kinds > 0 then
		local plain = CookingConfig.CountQuickEat(profile, CookingConfig.QUICK_EAT_ITEM) > 0
		selected = plain and CookingConfig.QUICK_EAT_ITEM or kinds[1].itemId
	end
	carried = CookingConfig.CountQuickEat(profile, selected)
	render()
end)
DungeonMenuNet.start()
render()
