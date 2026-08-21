--!strict
--  TitleBanner -- mounts the hand-built "inventory title" FigBloxUI banner
--  (StarterGui["inventory title"].Container -- Border Overlay, Left Border,
--  Right Border, Title) at the top of the main Inventory layout.
--
--  This used to be a fully procedural React re-implementation (every corner
--  image/dot/title positioned via hardcoded pixel math). That made simple
--  resize/reposition tweaks mean editing Luau constants instead of just
--  dragging things in Studio, which wasn't worth it for what's ultimately
--  static decorative chrome -- so this is the opposite now: Container is a
--  REAL, hand-editable Frame tree (drag it, resize it, move the dot, retint
--  the stroke -- all in Studio's Properties panel/viewport like any other
--  GUI), and this component's only job is to clone it into the live tree
--  once and keep it scaled to the row's width.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local React = require(ReplicatedStorage.Packages.React)
local UIDevTuning = require(ReplicatedStorage:WaitForChild("UIDevTuning"))

-- Matches Container's own FigBloxUIData bounds -- if you resize Container in Studio, update
-- this to match (only used to compute the width-driven scale factor + report the resulting
-- height back up to the caller so it can reserve the right amount of vertical space).
local DESIGN_W, DESIGN_H = 3997, 332

-- Live-tunable via UIDevTool (KeybindConfig.UIDevTool -- F6, NOT F9/F10, those are the mic
-- panel and the Item Grant dev menu respectively). Scale multiplies on top of the automatic
-- width-driven fit below, OffsetX/OffsetY nudge the clone from its default top-center
-- position, Rotation spins the whole banner. Press F6 in Play/Studio testing, use
-- ,/. to select "InventoryTitleBanner", arrows to nudge, -/= to scale, Enter to print a
-- paste-ready snapshot to Output, then hand-copy those numbers into the defaults below so
-- the dialed-in look survives a restart (see UIDevTuning's header comment).
-- Dialed in via F6 on 2026-08-20 -- see the printed snapshot in this session's Output.
local BannerTuning = UIDevTuning.Register("InventoryTitleBanner", {
	Banner = { Scale = 0.930, OffsetX = 0, OffsetY = -11, Rotation = 0 },
})

local function TitleBanner(props: { onMeasured: ((number) -> ())? })
	local rootRef = React.useRef(nil :: Frame?)
	local cloneRef = React.useRef(nil :: Frame?)
	local uiScaleRef = React.useRef(nil :: UIScale?)
	local baseScaleRef = React.useRef(0) -- auto width-driven fit factor, before BannerTuning.Scale is applied on top

	React.useEffect(function()
		local root = rootRef.current
		if not root then
			return
		end

		local player = Players.LocalPlayer
		local sourceGui = (player and player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("inventory title"))
			or game:GetService("StarterGui"):FindFirstChild("inventory title")
		local sourceContainer = sourceGui and sourceGui:FindFirstChild("Container")
		if not sourceContainer then
			warn('TitleBanner: could not find StarterGui["inventory title"].Container to clone')
			return
		end

		local clone = sourceContainer:Clone()
		clone.Name = "BannerArt"
		-- Pin to the top of our slot instead of Container's own authored center-anchor, and drop
		-- the tiny floating-point scale term FigBloxUI leaves on Size.Y (it's ~0, but it makes
		-- Size depend on our parent's height, which depends on Container's own rendered height --
		-- a circular reference once `root` is AutomaticSize.Y).
		clone.AnchorPoint = Vector2.new(0.5, 0)
		clone.Position = UDim2.fromScale(0.5, 0)
		clone.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
		clone.Parent = root
		cloneRef.current = clone

		-- Reuse Container's own FigBloxUIViewportScale instead of adding a second UIScale --
		-- two stacked UIScales would multiply and double-shrink everything.
		local uiScale = clone:FindFirstChildOfClass("UIScale")
		if not uiScale then
			uiScale = Instance.new("UIScale")
			uiScale.Parent = clone
		end
		uiScaleRef.current = uiScale

		-- Re-applies both the automatic fit AND whatever's currently dialed in via UIDevTool --
		-- called on every AbsoluteSize change (row resize) and every tuning change (F6 nudge).
		local function applyTuning()
			local tuning = BannerTuning:Get().Banner
			local finalScale = baseScaleRef.current * tuning.Scale
			uiScale.Scale = finalScale
			clone.Position = UDim2.new(0.5, tuning.OffsetX, 0, tuning.OffsetY)
			clone.Rotation = tuning.Rotation
			if props.onMeasured then
				props.onMeasured(tuning.OffsetY + finalScale * DESIGN_H)
			end
		end

		local function recompute()
			local w = root.AbsoluteSize.X
			if w <= 0 then
				return
			end
			baseScaleRef.current = w / DESIGN_W
			applyTuning()
		end

		recompute()
		local sizeConn = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(recompute)
		local tuningUnsub = BannerTuning:Subscribe(applyTuning)

		return function()
			sizeConn:Disconnect()
			tuningUnsub()
			clone:Destroy()
			cloneRef.current = nil
			uiScaleRef.current = nil
		end
	end, {})

	return React.createElement("Frame", {
		ref = rootRef,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})
end

return TitleBanner
