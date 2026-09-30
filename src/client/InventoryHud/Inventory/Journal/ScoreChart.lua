--!strict
--  Journal/ScoreChart -- score across a time window as ink bars drawn on the page.
--
--    e(ScoreChart, { points = { { t = slotStartUnix, v = score } }, window = "24H", Size, LayoutOrder })
--
--  One bar per slot (12 five-minute bars for 1H, 24 hourly for 24H, 7 / 30 daily). Labels:
--  the peak value on the left, and the first / middle / last slot times underneath, in the
--  player's local time. Both axes are drawn as lines so it always reads as a chart. With no
--  score in the window yet: faint placeholder bars and a note instead of a flat line and a
--  lone "0".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Style = require(script.Parent:WaitForChild("Style"))

local e = React.createElement

local AXIS_W = 40
local LABEL_H = 18

local function timeLabel(t: number, window: string): string
	if window == "1H" or window == "24H" then
		return os.date("%H:%M", t) :: string
	end
	return os.date("%b %d", t) :: string
end

local function ScoreChart(props: { points: { any }, window: string, Size: UDim2?, LayoutOrder: number? })
	local points = props.points or {}
	local peak = 0
	for _, p in ipairs(points) do peak = math.max(peak, tonumber(p.v) or 0) end
	local ink = Style.OnPaper and Style.Text.Muted or Color3.fromRGB(150, 160, 110)
	local empty = peak <= 0

	local bars: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, #points > 20 and 2 or 4),
		}),
	}
	local count = math.max(1, #points)
	local gap = #points > 20 and 2 or 4
	-- Empty window: a faint made-up silhouette so the space still reads as a chart.
	local GHOST = { 0.35, 0.55, 0.4, 0.7, 0.5, 0.8, 0.45, 0.6, 0.3, 0.65, 0.5, 0.75 }
	for i, p in ipairs(points) do
		local h = empty and GHOST[(i - 1) % #GHOST + 1] or ((tonumber(p.v) or 0) / peak)
		bars["b" .. i] = e("Frame", {
			LayoutOrder = i,
			Size = UDim2.new(1 / count, -gap, math.max(h, 0.015), 0),
			BackgroundColor3 = ink,
			BackgroundTransparency = empty and 0.85 or (h > 0 and 0.15 or 0.7),
			BorderSizePixel = 0,
		})
	end

	local labels: { [string]: any } = {}
	if #points > 0 then
		local picks = { 1, math.ceil(#points / 2), #points }
		for n, index in ipairs(picks) do
			local p = points[index]
			labels["x" .. n] = e("TextLabel", {
				AnchorPoint = Vector2.new(n == 1 and 0 or (n == 2 and 0.5 or 1), 0),
				Position = UDim2.new(n == 1 and 0 or (n == 2 and 0.5 or 1), 0, 0, 0),
				Size = UDim2.fromOffset(80, LABEL_H),
				BackgroundTransparency = 1,
				Text = index == #points and "now" or timeLabel(p.t, props.window),
				FontFace = Style.Font.Body,
				TextSize = 13,
				TextColor3 = Style.Text.Muted,
				TextXAlignment = n == 1 and Enum.TextXAlignment.Left
					or (n == 2 and Enum.TextXAlignment.Center or Enum.TextXAlignment.Right),
			})
		end
	end

	return e("Frame", {
		Size = props.Size or UDim2.new(1, 0, 0, 150),
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
	}, {
		Peak = not empty and e("TextLabel", {
			Size = UDim2.fromOffset(AXIS_W - 6, LABEL_H),
			BackgroundTransparency = 1,
			Text = tostring(math.floor(peak)),
			FontFace = Style.Font.Body,
			TextSize = 13,
			TextColor3 = Style.Text.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
		}) or nil,
		Zero = not empty and e("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -LABEL_H),
			Size = UDim2.fromOffset(AXIS_W - 6, LABEL_H),
			BackgroundTransparency = 1,
			Text = "0",
			FontFace = Style.Font.Body,
			TextSize = 13,
			TextColor3 = Style.Text.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
		}) or nil,
		Plot = e("Frame", {
			Position = UDim2.fromOffset(AXIS_W, 6),
			Size = UDim2.new(1, -AXIS_W, 1, -(LABEL_H + 8)),
			BackgroundTransparency = 1,
		}, {
			Bars = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, bars),
			Baseline = e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = Style.Text.Muted,
				BorderSizePixel = 0,
			}),
			YAxis = e("Frame", {
				Position = UDim2.fromOffset(-4, 0),
				Size = UDim2.new(0, 1, 1, 0),
				BackgroundColor3 = Style.Text.Muted,
				BorderSizePixel = 0,
			}),
			Empty = empty and e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -20, 0, 22),
				BackgroundTransparency = 1,
				Text = "Not enough activity to chart yet",
				FontFace = Style.Font.Body,
				TextSize = 15,
				TextColor3 = Style.Text.Muted,
			}) or nil,
		}),
		XLabels = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, AXIS_W, 1, 0),
			Size = UDim2.new(1, -AXIS_W, 0, LABEL_H),
			BackgroundTransparency = 1,
		}, labels),
	})
end

return ScoreChart
