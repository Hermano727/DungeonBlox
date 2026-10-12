--[[
	CursorLockButton -- a "Lock Cursor" button in the quick-nav row under the minimap
	(RS/HudQuickNav, right of the crosshair toggle), added 2026-10-11.

	A generic escape hatch. If some UI frees the cursor and never gives it back (a leaked
	CursorUtils hold re-frees it every frame), the camera can't turn and even Ctrl's FreeLook
	can't take it back. The cursor is free in exactly that state, so this button is clickable:
	it closes any open menu the normal way (InteractionLock.CloseMenu, so that menu releases
	its own hold), then drops every hold that's left and locks the cursor
	(CursorUtils.ForceRelock + CursorManager.reset).

	The row hides while the Tab menu is open, so it can't fight a menu that legitimately owns
	the cursor. Root-cause leaks still get fixed where they are (the party invite, 2026-10-11).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local QuickNav = require(ReplicatedStorage:WaitForChild("HudQuickNav"))
local CursorUtils = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local CursorManager = require(ReplicatedStorage:WaitForChild("CursorManager"))
local InteractionLock = require(ReplicatedStorage:WaitForChild("InteractionLock"))
local JournalUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("JournalUI"))

-- Same plate and hover as the crosshair toggle beside it.
local button = Instance.new("TextButton")
button.Name = "CursorLock"
button.Size = UDim2.fromOffset(QuickNav.BUTTON_SIZE, QuickNav.BUTTON_SIZE)
button.BackgroundColor3 = Color3.fromRGB(14, 13, 16)
button.BackgroundTransparency = .25
button.AutoButtonColor = false
button.Text = ""
button.ZIndex = 10
button.Parent = QuickNav.Slot("CursorLock", QuickNav.ORDER.CursorLock)
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5)
QuickNav.Tooltip(button, "Lock Cursor")

local lockArt = JournalUI.lock_icon
local icon = Instance.new("ImageLabel")
icon.Name = "Icon"
icon.AnchorPoint = Vector2.new(.5, .5)
icon.Position = UDim2.fromScale(.5, .5)
icon.Size = UDim2.fromOffset(18, 18)
icon.BackgroundTransparency = 1
icon.ScaleType = Enum.ScaleType.Fit
icon.Image = (type(lockArt) == "table" and lockArt.Image) or ""
icon.ImageColor3 = Color3.fromRGB(236, 226, 208)
icon.ImageTransparency = .1
icon.ZIndex = 11
icon.Parent = button
local iconScale = Instance.new("UIScale")
iconScale.Parent = icon

local hoverIn = TweenInfo.new(.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
button.MouseEnter:Connect(function()
	TweenService:Create(iconScale, hoverIn, { Scale = 1.2 }):Play()
	TweenService:Create(button, hoverIn, { BackgroundTransparency = .05 }):Play()
end)
button.MouseLeave:Connect(function()
	TweenService:Create(iconScale, hoverIn, { Scale = 1 }):Play()
	TweenService:Create(button, hoverIn, { BackgroundTransparency = .25 }):Play()
end)

button.Activated:Connect(function()
	local leaked = CursorUtils.Holds()
	InteractionLock.CloseMenu()
	-- Let a closing menu run its own release first (CloseMenu spawns its close callback).
	task.defer(function()
		CursorUtils.ForceRelock()
		CursorManager.reset()
		if leaked > 0 then
			warn(("[CursorLockButton] relocked the cursor (%d open hold(s) dropped)"):format(leaked))
		end
	end)
end)
