--[[
	MenuShortcuts

	Inventory, Journal and Hearthstone as buttons in the quick-nav row under the minimap
	(RS/HudQuickNav), so touch players (no Tab key) can open the menu, and anyone can jump
	straight to a tab. Tapping the tab that's already open closes the menu
	(ProfileMenusState.RequestOpen).

	The Hearthstone button only appears once it's unlocked (profile.flags.hearthstoneUnlocked;
	the tutorial's totem), like its tab. Each button carries a TutorialTarget attribute
	("shortcut_<id>") so the tutorial can point at it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local QuickNav = require(ReplicatedStorage:WaitForChild("HudQuickNav"))
local ProfileMenusState = require(ReplicatedStorage:WaitForChild("ProfileMenusState"))
local JournalUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("JournalUI"))
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))

local _ = Players.LocalPlayer

local SHORTCUTS = {
	{ id = "inventory", order = QuickNav.ORDER.Inventory, label = "Inventory", glyph = "nav_glyph_inventory", key = "Tab" },
	{ id = "journal", order = QuickNav.ORDER.Journal, label = "Journal", glyph = "nav_glyph_journal" },
	{ id = "hearthstone", order = QuickNav.ORDER.Hearthstone, label = "Hearthstone", glyph = "nav_glyph_hearthstone", unlockFlag = "hearthstoneUnlocked" },
}

local hoverIn = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local buttons = {}

for _, spec in ipairs(SHORTCUTS) do
	local slot = QuickNav.Slot("Menu_" .. spec.id, spec.order)
	local button = Instance.new("TextButton")
	button.Name = spec.label
	button.Size = UDim2.fromOffset(QuickNav.BUTTON_SIZE, QuickNav.BUTTON_SIZE)
	button.BackgroundColor3 = Color3.fromRGB(14, 13, 16)
	button.BackgroundTransparency = 0.25
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = 10
	button:SetAttribute("TutorialTarget", "shortcut_" .. spec.id)
	button.Parent = slot
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5)
	QuickNav.Tooltip(button, spec.label)

	local art = JournalUI[spec.glyph]
	local icon = Instance.new("ImageLabel")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.72, 0.72)
	icon.BackgroundTransparency = 1
	icon.Image = art and art.Image or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 11
	icon.Parent = button
	local scale = Instance.new("UIScale")
	scale.Parent = icon

	-- The keyboard key under it, for players who'd rather press it (Tab opens the menu).
	if spec.key then
		local keyLabel = Instance.new("TextLabel")
		keyLabel.AnchorPoint = Vector2.new(0.5, 0)
		keyLabel.Position = UDim2.new(0.5, 0, 1, 2)
		keyLabel.Size = UDim2.fromOffset(QuickNav.BUTTON_SIZE + 8, 14)
		keyLabel.BackgroundTransparency = 1
		keyLabel.Text = spec.key
		keyLabel.FontFace = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
		keyLabel.TextSize = 12
		keyLabel.TextColor3 = Color3.fromRGB(246, 230, 190)
		keyLabel.TextStrokeTransparency = 0.4
		keyLabel.ZIndex = 11
		keyLabel.Parent = button
	end

	button.Activated:Connect(function()
		ProfileMenusState.RequestOpen(spec.id)
	end)
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, hoverIn, { Scale = 1.15 }):Play()
		TweenService:Create(button, hoverIn, { BackgroundTransparency = 0.05 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, hoverIn, { Scale = 1 }):Play()
		TweenService:Create(button, hoverIn, { BackgroundTransparency = 0.25 }):Play()
	end)
	buttons[spec] = slot
end

-- Locked destinations stay hidden until the profile unlocks them.
local function refresh(snapshot)
	local flags = snapshot and snapshot.profile and snapshot.profile.flags
	for spec, slot in pairs(buttons) do
		slot.Visible = not spec.unlockFlag or (type(flags) == "table" and flags[spec.unlockFlag] == true)
	end
end
DungeonMenuNet.addSnapshotListener(refresh)
refresh(DungeonMenuNet.getLastSnapshot())
