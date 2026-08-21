--!strict
--  InventoryHud mount point.
--
--  Combines three FigBloxUI Figma exports (StarterGui["Player Preview"],
--  StarterGui["Inv Slots"], StarterGui["quick nav"]) into one React-lua panel,
--  opened/closed with Tab -- the same key the old "Character" panel used.
--  SkillsTabClient no longer responds to Tab (see the comment left there);
--  this script owns it now.
--
--  Same pattern as XpHud/PlayerPreview: own a ScreenGui nothing imperative
--  touches, createRoot once, render once. Panel-stack state (which sub-panel
--  is showing) lives inside the Inventory component; this script only
--  flips Enabled and drives the background blur, since those are real
--  side effects outside the GUI tree that React shouldn't own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local MenuMouse = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local React = require(ReplicatedStorage.Packages.React)
local Inventory = require(script:WaitForChild("Inventory"))

-- The three FigBloxUI-imported copies stay as design references but must
-- never render themselves -- this new ScreenGui is what players see.
for _, guiName in ipairs({ "Player Preview", "Inv Slots", "quick nav" }) do
	local template = StarterGui:FindFirstChild(guiName)
	if template and template:IsA("ScreenGui") then
		template.Enabled = false
	end
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Disabling the StarterGui template alone isn't enough -- PlayerGui already
-- cloned these by the time this LocalScript runs, so the already-cloned
-- copies have to be disabled directly too (same gotcha as PlayerPreviewHud
-- originally hit).
for _, guiName in ipairs({ "Player Preview", "Inv Slots", "quick nav" }) do
	local clone = playerGui:FindFirstChild(guiName)
	if clone and clone:IsA("ScreenGui") then
		clone.Enabled = false
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "InventoryReact"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 120 -- same tier as the old SkillsPopupUI it replaces
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

local root = ReactRoblox.createRoot(gui)

-- Bumped every time the panel fully closes, and passed down as a prop so
-- Inventory.lua's useEffect resets its nav stack back to the main screen --
-- otherwise reopening would resume wherever you last left it (e.g. still on
-- the Skills sub-panel), which reads as a bug more than a feature here.
local closeGeneration = 0
local function render()
	root:render(React.createElement(Inventory, { resetKey = closeGeneration }))
end
render()

----------------------------------------------------------------
-- Background blur -- 40% of Roblox's BlurEffect.Size range (0-56)
----------------------------------------------------------------
local blur = Lighting:FindFirstChild("InventoryBlur") :: BlurEffect?
if not blur then
	blur = Instance.new("BlurEffect")
	blur.Name = "InventoryBlur"
	blur.Size = 0
	blur.Parent = Lighting
end

local BLUR_SIZE = 56 * 0.4
local BLUR_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

----------------------------------------------------------------
-- Open / close
----------------------------------------------------------------
local open = false

local function setOpen(v: boolean)
	if v == open then
		return
	end
	open = v
	if not v then
		closeGeneration += 1
		render()
	end
	gui.Enabled = v
	TweenService:Create(blur :: BlurEffect, BLUR_TWEEN, { Size = v and BLUR_SIZE or 0 }):Play()
	if v then
		MenuMouse.acquire()
	else
		MenuMouse.release()
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Keys.SkillsTab then
		setOpen(not open)
		return
	end
	if gameProcessed then
		return
	end
	if input.KeyCode == Keys.CloseMenu and open then
		setOpen(false)
	end
end)

player.CharacterAdded:Connect(function()
	setOpen(false)
end)

print("[InventoryHud] React root mounted")
