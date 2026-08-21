--!strict
--  XpHud mount point.
--
--  First React-lua panel in the codebase. Pattern to copy for later panels:
--    1. own a ScreenGui that NOTHING imperative touches
--    2. createRoot once, render once
--    3. all updates come from component state, never from mutating instances
--
--  Rule that keeps this safe: React and imperative code must never both own the
--  same instance. This ScreenGui is React's alone.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local React       = require(ReplicatedStorage.Packages.React)
local XpHud       = require(script:WaitForChild("XpHud"))

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "XpHudReact"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local root = ReactRoblox.createRoot(gui)
root:render(React.createElement(XpHud))

print("[XpHud] React root mounted")
