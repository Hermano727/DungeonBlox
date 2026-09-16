--!strict
--  PanelShell -- shared chrome for the inventory's sub-panels (Skills,
--  Stats, Hearthstone, Party): a title bar over a content area, with an
--  optional close (X) button.
--
--  The close button only renders when `onClose` is actually passed (2026-09-13,
--  per the persistent-header QuickNav redesign -- see Inventory/init.lua's header
--  comment): navigating between panels is now QuickNav's job, always visible above
--  whatever's showing, so the sub-panels that use this shell (Stats/Hearthstone/
--  Party) no longer pass onClose at all. Left optional rather than deleted outright
--  in case a future panel still wants its own explicit close affordance.
--
--  Header treatment: a centered title flanked by thin gold rule lines (a plain
--  Roblox-primitives placeholder for a proper flourish/scrollwork banner -- the
--  real ornamental version of this, like PlayerPreview's GOLD_FRAME_IMAGE
--  corner art, needs actual vector art authored in Figma and brought in via
--  FigBloxUI, not something proceduralized here), plus a small diamond
--  ornament straddling the header/content seam, reusing the same gem motif
--  QuickNav's nav icons use so the chrome reads as one consistent visual
--  language instead of a flat, undecorated bar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local e = React.createElement

local THEME = {
	PanelBg  = Color3.fromRGB(26, 18, 11),
	HeaderBg = Color3.fromRGB(34, 24, 15),
	Border   = UITheme.Gold,
	Title    = Color3.fromRGB(240, 230, 210),
	CloseBg  = Color3.fromRGB(48, 28, 28),
	OrnamentFill = Color3.fromRGB(20, 14, 9),
}

local HEADER_HEIGHT = 52
local ORNAMENT_SIZE = 16

export type PanelShellProps = {
	title: string,
	onClose: (() -> ())?,
	children: any,
}

local function PanelShell(props: PanelShellProps)
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.PanelBg,
		BorderSizePixel = 0,
	}, {
		Stroke = e("UIStroke", { Color = THEME.Border, Thickness = 2 }),

		Header = e("Frame", {
			Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
			BackgroundColor3 = THEME.HeaderBg,
			BorderSizePixel = 0,
		}, {
			-- Rule lines flank the centered title instead of it sitting flush-left --
			-- a plain stand-in for a proper flourish banner (see file header comment).
			RuleLeft = e("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 20, 0.5, 0),
				Size = UDim2.new(0.5, -160, 0, 1),
				BackgroundColor3 = THEME.Border,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
			}),
			RuleRight = e("Frame", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -56, 0.5, 0),
				Size = UDim2.new(0.5, -160, 0, 1),
				BackgroundColor3 = THEME.Border,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
			}),
			Title = e("TextLabel", {
				-- True dead-center on the header (was nudged -18px as an eyeballed, wrong
				-- attempt to compensate for the Close button eating space on the right).
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.fromOffset(280, 26),
				BackgroundTransparency = 1,
				Text = string.upper(props.title),
				FontFace = UIFonts.DisplayBold,
				TextSize = 20,
				TextColor3 = THEME.Title,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
			Close = props.onClose and e("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(28, 28),
				BackgroundColor3 = THEME.CloseBg,
				BorderSizePixel = 0,
				FontFace = UIFonts.BodyBold,
				TextSize = 16,
				TextColor3 = Color3.fromRGB(230, 180, 180),
				Text = "X",
				AutoButtonColor = true,
				[React.Event.Activated] = props.onClose,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			}) or nil,
		}),

		-- Thin seam line + a small diamond "rivet" straddling it -- marks the
		-- header/content boundary instead of leaving it as a plain color change.
		SeamDivider = e("Frame", {
			Position = UDim2.new(0, 0, 0, HEADER_HEIGHT - 1),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = THEME.Border,
			BorderSizePixel = 0,
			ZIndex = 2,
		}),
		SeamOrnament = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, HEADER_HEIGHT),
			Size = UDim2.fromOffset(ORNAMENT_SIZE, ORNAMENT_SIZE),
			Rotation = 45,
			BackgroundColor3 = THEME.OrnamentFill,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, {
			Stroke = e("UIStroke", { Color = THEME.Border, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		}),

		Content = e("Frame", {
			Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT),
			Position = UDim2.fromOffset(0, HEADER_HEIGHT),
			BackgroundTransparency = 1,
		}, props.children),
	})
end

return PanelShell
