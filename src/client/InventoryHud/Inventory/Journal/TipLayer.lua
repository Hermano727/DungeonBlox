--[[
	TipLayer
	Hover tips drawn above everything: one ScreenGui of their own (DisplayOrder TIP_ORDER, above
	every menu), filled through a React portal and placed at the hovered element's screen rect.

	A tip used to be a child of the element it explains. ZIndex only orders siblings, so page
	titles and blocks in other branches of the page drew over it, and clipping frames cut it off
	(2026-10-03). Every Journal tip now goes through here: StatsPage's stat/gear tips and
	Parts.HelpIcon's "(?)".

		e(TipLayer.Floating, { anchor = guiObject, width = 280, height = 120, above = false,
			align = "center" | "right" }, { Card = ... })

	The card is clamped to the screen and flips above / below when it would run off an edge.
	It is not under the menu's UIScale, so it keeps its pixel size on small windows.
]]
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local e = React.createElement

local TIP_ORDER = 400 -- the Tab menu is 120, the vitals 110: tips sit above them all
local MARGIN = 8 -- px kept clear of the screen edges
local GAP = 8 -- px between the element and its tip

local TipLayer = {}

local layer: ScreenGui? = nil
local function container(ignoreInset: boolean): ScreenGui
	if not layer or not layer.Parent then
		local gui = Instance.new("ScreenGui")
		gui.Name = "JournalTipLayer"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = TIP_ORDER
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		-- Full-screen menus hide every ScreenGui not tagged as an overlay (HudHider).
		CollectionService:AddTag(gui, "OverMenus")
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		layer = gui
	end
	-- Match the hovered element's own ScreenGui, so its AbsolutePosition means the same here.
	layer.IgnoreGuiInset = ignoreInset
	return layer
end

local function viewSize(ignoreInset: boolean): Vector2
	local camera = workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	if not ignoreInset then
		size -= Vector2.new(0, GuiService:GetGuiInset().Y)
	end
	return size
end

function TipLayer.Floating(props: { anchor: GuiObject?, width: number, height: number, above: boolean?, align: string?, children: any })
	local anchor = props.anchor
	if not anchor or not anchor.Parent then
		return nil
	end
	local screen = anchor:FindFirstAncestorOfClass("ScreenGui")
	local ignoreInset = screen ~= nil and screen.IgnoreGuiInset
	local gui = container(ignoreInset)
	local view = viewSize(ignoreInset)
	local pos, size = anchor.AbsolutePosition, anchor.AbsoluteSize
	local w, h = props.width, props.height

	local x = props.align == "right" and (pos.X + size.X - w) or (pos.X + size.X / 2 - w / 2)
	x = math.clamp(x, MARGIN, math.max(MARGIN, view.X - w - MARGIN))
	local below = pos.Y + size.Y + GAP
	local aboveY = pos.Y - GAP - h
	local y
	if props.above then
		y = aboveY >= MARGIN and aboveY or below
	else
		y = below + h <= view.Y - MARGIN and below or aboveY
	end
	y = math.clamp(y, MARGIN, math.max(MARGIN, view.Y - h - MARGIN))

	return ReactRoblox.createPortal(e("Frame", {
		Position = UDim2.fromOffset(math.floor(x), math.floor(y)),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1,
	}, props.children), gui)
end

return TipLayer
