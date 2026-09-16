--!strict
-- Dialog: presentation for the tree-based dialog panel, plus the typewriter
-- reveal and portrait box (ported from dialog system (3)'s DialogGui/
-- Typewriter). Branching/session logic still lives entirely in
-- DialogRuntime -- this component only owns the reveal animation, since
-- that's purely a presentation concern tied to how React mounts the host
-- TextLabel (via a ref), not to conversation state.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local DialogConfig = require(ReplicatedStorage.DialogSystem.DialogConfig)

local e = React.createElement

local function ResponseButton(props)
	local ui = DialogConfig.UI
	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = ui.ButtonColor,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		ZIndex = 2,
		Font = Enum.Font.GothamMedium,
		TextSize = ui.ResponseTextSize,
		TextColor3 = ui.TextColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "  " .. tostring(props.index) .. ".  " .. props.text,
		LayoutOrder = props.index,
		[React.Event.Activated] = props.onActivated,
		[React.Event.MouseEnter] = function(inst)
			inst.BackgroundColor3 = ui.ButtonHoverColor
		end,
		[React.Event.MouseLeave] = function(inst)
			inst.BackgroundColor3 = ui.ButtonColor
		end,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Padding = e("UIPadding", { PaddingLeft = UDim.new(0, 4) }),
	})
end

local function Dialog(props)
	local ui = DialogConfig.UI

	local textRef = React.useRef(nil)
	local skipRef = React.useRef(nil)
	local imagePictureRef = React.useRef(nil)
	local isTyping, setIsTyping = React.useState(false)

	-- Typewriter: re-runs whenever the node's text changes (new node, or a
	-- fresh conversation). Reveals graphemes over time via
	-- TextLabel.MaxVisibleGraphemes, same mechanism dialog system (3)'s
	-- Typewriter module used -- just driven from an effect + ref instead of
	-- an imperative module, since React owns the TextLabel instance here.
	React.useEffect(function()
		local label = textRef.current
		if not label or not props.text or props.text == "" then
			return
		end

		local cancelled = false
		skipRef.current = function()
			cancelled = true
			label.MaxVisibleGraphemes = -1
			setIsTyping(false)
		end

		label.MaxVisibleGraphemes = 0
		setIsTyping(true)

		local totalGraphemes = utf8.len(label.ContentText) or #label.ContentText
		if totalGraphemes <= 0 then
			setIsTyping(false)
			return
		end

		local charsPerSecond = math.max(1, DialogConfig.TextSpeed or 35)
		local interval = 1 / charsPerSecond

		task.spawn(function()
			local accumulator = 0
			local revealed = 0
			while revealed < totalGraphemes and not cancelled do
				local dt = RunService.RenderStepped:Wait()
				if cancelled then
					return
				end
				accumulator += dt
				while accumulator >= interval and revealed < totalGraphemes do
					revealed += 1
					accumulator -= interval
				end
				label.MaxVisibleGraphemes = revealed
			end
			if not cancelled then
				setIsTyping(false)
			end
		end)

		return function()
			cancelled = true
		end
	end, { props.text })

	-- Bounce: the portrait picture (not its background frame) hops upward
	-- by ~10% of the screen height and settles back down whenever a new
	-- node is shown -- runs on every text change, i.e. every node
	-- transition (including the very first node when a conversation
	-- starts), independent of whether the image asset itself changed from
	-- the previous node's. Only the inner Picture ImageLabel moves; the
	-- static ImageFrame behind it never animates.
	React.useEffect(function()
		local picture = imagePictureRef.current
		local hasImg = type(props.image) == "string" and props.image ~= ""
		if not picture or not hasImg then
			return
		end

		local camera = workspace.CurrentCamera
		local screenHeight = (camera and camera.ViewportSize.Y) or 900
		local bounceOffset = screenHeight * 0.10

		picture.Position = UDim2.fromScale(0, 0)

		local downTween
		local upTween = TweenService:Create(
			picture,
			TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0, 0, 0, -bounceOffset) }
		)
		local upConn
		upConn = upTween.Completed:Connect(function()
			downTween = TweenService:Create(
				picture,
				TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.fromScale(0, 0) }
			)
			downTween:Play()
		end)
		upTween:Play()

		return function()
			if upConn then
				upConn:Disconnect()
			end
			upTween:Cancel()
			if downTween then
				downTween:Cancel()
			end
			picture.Position = UDim2.fromScale(0, 0)
		end
	end, { props.text })

	if not props.text then
		return nil
	end

	-- Text/name are pushed right of the portrait's footprint so they never
	-- sit underneath it; responses start below the portrait's bottom edge.
	local hasImage = type(props.image) == "string" and props.image ~= ""
	local imageRight = ui.ImageSize.X.Offset - ui.ImageOverflowLeft + 14
	local textInsetX = hasImage and imageRight or 0
	local responsesTop = hasImage and (ui.ImageSize.Y.Offset - ui.ImageOverflowTop + 15) or 34

	local responseChildren = {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	}
	if not isTyping then
		for i, resp in ipairs(props.responses or {}) do
			responseChildren["Option" .. i] = e(ResponseButton, {
				index = i,
				text = resp.text,
				onActivated = function()
					props.onChoose(resp)
				end,
			})
		end
	end

	return e("ScreenGui", {
		Name = "DialogPanelRoot",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 140,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Panel = e("Frame", {
			Name = "Panel",
			Size = ui.PanelSize,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -40),
			BackgroundColor3 = ui.BackgroundColor,
			BackgroundTransparency = ui.BackgroundTransparency,
			BorderSizePixel = 0,
			-- Let the portrait spill past the panel's own edges.
			ClipsDescendants = false,
		}, {
			Corner = e("UICorner", { CornerRadius = ui.CornerRadius }),
			Stroke = e("UIStroke", { Color = ui.AccentColor, Thickness = 1.5, Transparency = 0.4 }),

			-- Full-panel click-to-skip surface, behind everything else
			-- (ZIndex 1, below the responses' ZIndex 2). Only matters while
			-- typing, since responses aren't rendered until it finishes.
			SkipCatcher = e("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 1,
				[React.Event.Activated] = function()
					if isTyping and skipRef.current then
						skipRef.current()
					end
				end,
			}),

			-- Center-anchored (rather than the top-left default) static
			-- background frame -- this never animates, so the bounce effect
			-- above only moves the inner Picture ImageLabel, not this box.
			ImageFrame = hasImage and e("Frame", {
				Size = ui.ImageSize,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(
					0, -ui.ImageOverflowLeft + ui.ImageSize.X.Offset / 2,
					0, -ui.ImageOverflowTop + ui.ImageSize.Y.Offset / 2
				),
				BackgroundColor3 = ui.ButtonColor,
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				ZIndex = 2,
				ClipsDescendants = false,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 10) }),
				Picture = e("ImageLabel", {
					ref = imagePictureRef,
					Size = UDim2.fromScale(1, 1),
					Position = UDim2.fromScale(0, 0),
					BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = 3,
					Image = props.image,
				}),
			}) or nil,

			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 14),
				PaddingBottom = UDim.new(0, 14),
				PaddingLeft = UDim.new(0, 18),
				PaddingRight = UDim.new(0, 18),
			}),
			NpcName = e("TextLabel", {
				Position = UDim2.new(0, textInsetX, 0, 0),
				Size = UDim2.new(1, -textInsetX, 0, 24),
				BackgroundTransparency = 1,
				ZIndex = 2,
				Font = Enum.Font.GothamBold,
				TextSize = 16,
				TextColor3 = ui.AccentColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = props.npcName or "",
			}),
			Text = e("TextLabel", {
				ref = textRef,
				Position = UDim2.new(0, textInsetX, 0, 26),
				Size = UDim2.new(1, -textInsetX, 0, 90),
				BackgroundTransparency = 1,
				ZIndex = 2,
				Font = Enum.Font.Gotham,
				TextSize = ui.TextSize,
				TextColor3 = ui.TextColor,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				RichText = true,
				Text = props.text,
			}),
			Status = props.statusText and e("TextLabel", {
				Position = UDim2.new(0, textInsetX, 0, 118),
				Size = UDim2.new(1, -textInsetX, 0, 18),
				BackgroundTransparency = 1,
				ZIndex = 2,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = Color3.fromRGB(255, 180, 120),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = props.statusText,
			}) or nil,
			-- Max ~3 responses visible without scrolling at the current
			-- PanelSize -- fine for now; swap this Frame for a
			-- ScrollingFrame if a tree ever needs more than that.
			Responses = e("Frame", {
				Position = UDim2.new(0, 0, 0, responsesTop),
				Size = UDim2.new(1, 0, 1, -responsesTop),
				BackgroundTransparency = 1,
				ZIndex = 2,
			}, responseChildren),
		}),
	})
end

return Dialog
