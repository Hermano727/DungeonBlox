--!strict
--  InventoryBackdrop -- the painted courtyard behind the Inventory tab, full screen.
--
--    e(InventoryBackdrop, { visible = boolean })
--
--  It lives in its OWN ScreenGui (portal), DisplayOrder BACKDROP_ORDER, not in the menu's:
--  the menu GUI (ProfileMenusReact, 120) draws above the HP/energy cluster (110) and the
--  hotbar (35), so a full-screen painting inside it would hide both. At 32 it sits above the
--  corner minimap (30) and below everything that should stay readable over it.
--
--  The painting follows the game clock (Lighting.ClockTime, driven by SSS/DayNightService):
--    dawn       5:00 - 10:00
--    afternoon 10:00 - 17:00
--    dusk      the rest, darkened further through the night (NIGHT_DARKNESS)
--  Each is two halves (RS/Assets/Images/JournalUI inv_bg_<time>_l / _r, 16:9 together), drawn
--  to COVER the screen. A time of day whose art isn't uploaded yet falls back to the afternoon
--  painting tinted towards that time (FALLBACK_TINT).
--  Edges are shaded (top behind the nav, bottom behind the hotbar, right behind the bag) so
--  the UI on top reads.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local Style = require(script.Parent:WaitForChild("Journal"):WaitForChild("Style"))

local e = React.createElement

local BACKDROP_ORDER = 32
local ASPECT = 1448 / 814 -- the two halves together
local NIGHT_DARKNESS = 0.5 -- how dark the deepest night gets (0 = none, 1 = black)
local FALLBACK_TINT = {
	dawn = Color3.fromRGB(255, 214, 204),
	dusk = Color3.fromRGB(236, 168, 132),
}

-- Which painting, and how much night darkening on top, for a ClockTime (0-24).
local function timeOfDay(t: number): (string, number)
	t %= 24
	if t >= 5 and t < 10 then
		return "dawn", 0
	elseif t >= 10 and t < 17 then
		return "afternoon", 0
	end
	-- Dusk: clear at 17:00, full night from 19:00, easing off again 4:00 - 5:00.
	local darkness
	if t >= 17 and t < 19 then
		darkness = (t - 17) / 2
	elseif t >= 4 and t < 5 then
		darkness = 1 - (t - 4)
	else
		darkness = 1
	end
	-- Steps of 5% so a running clock re-renders a handful of times a night, not every frame.
	return "dusk", math.floor(darkness * NIGHT_DARKNESS * 20 + 0.5) / 20
end

local function useTimeOfDay(): (string, number)
	local state, setState = React.useState(function()
		local key, dark = timeOfDay(Lighting.ClockTime)
		return { key = key, dark = dark }
	end)
	React.useEffect(function()
		local conn = Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
			local key, dark = timeOfDay(Lighting.ClockTime)
			setState(function(prev)
				if prev.key == key and prev.dark == dark then return prev end
				return { key = key, dark = dark }
			end)
		end)
		return function() conn:Disconnect() end
	end, {})
	return state.key, state.dark
end

local function shade(props: { anchor: Vector2, pos: UDim2, size: UDim2, rotation: number, from: number, to: number })
	return e("Frame", {
		AnchorPoint = props.anchor,
		Position = props.pos,
		Size = props.size,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, {
		Fade = e("UIGradient", {
			Rotation = props.rotation,
			Transparency = NumberSequence.new(props.from, props.to),
		}),
	})
end

local function InventoryBackdrop(props: { visible: boolean })
	local gui = React.useMemo(function()
		local screen = Instance.new("ScreenGui")
		screen.Name = "InventoryBackdrop"
		screen.IgnoreGuiInset = true
		screen.ResetOnSpawn = false
		screen.DisplayOrder = BACKDROP_ORDER
		screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screen.Enabled = false
		screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		return screen
	end, {})
	React.useEffect(function()
		return function() gui:Destroy() end
	end, {})
	React.useEffect(function()
		gui.Enabled = props.visible
	end, { props.visible })

	-- Cover the screen: whichever of width / height runs out first decides the scale.
	local screenSize, setScreenSize = React.useState(gui.AbsoluteSize)
	React.useEffect(function()
		local conn = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			setScreenSize(gui.AbsoluteSize)
		end)
		setScreenSize(gui.AbsoluteSize)
		return function() conn:Disconnect() end
	end, {})
	local w, h = screenSize.X, screenSize.Y
	if w <= 0 or h <= 0 then
		w, h = 1920, 1080
	end
	if w / h > ASPECT then
		h = w / ASPECT
	else
		w = h * ASPECT
	end

	local key, dark = useTimeOfDay()
	local left, right = Style.Art("inv_bg_" .. key .. "_l"), Style.Art("inv_bg_" .. key .. "_r")
	local tint = Color3.new(1, 1, 1)
	if not (left and right) then
		left, right = Style.Art("inv_bg_afternoon_l"), Style.Art("inv_bg_afternoon_r")
		tint = FALLBACK_TINT[key] or tint
	end

	local function half(art: any, x: number)
		return e("ImageLabel", {
			Position = UDim2.fromScale(x, 0),
			-- 1 px overlap so the seam between the halves never shows.
			Size = UDim2.new(0.5, 1, 1, 0),
			BackgroundTransparency = 1,
			Image = art and art.Image or "",
			ImageColor3 = tint,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = 1,
		})
	end

	return ReactRoblox.createPortal(e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 14, 12),
		BorderSizePixel = 0,
	}, {
		Painting = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(math.ceil(w), math.ceil(h)),
			BackgroundTransparency = 1,
		}, {
			Left = half(left, 0),
			Right = half(right, 0.5),
		}),
		Night = dark > 0 and e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(4, 6, 16),
			BackgroundTransparency = 1 - dark,
			BorderSizePixel = 0,
			ZIndex = 2,
		}) or nil,
		Top = shade({ anchor = Vector2.new(0, 0), pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 0.34), rotation = 90, from = 0.3, to = 1 }),
		Bottom = shade({ anchor = Vector2.new(0, 1), pos = UDim2.fromScale(0, 1), size = UDim2.fromScale(1, 0.24), rotation = 270, from = 0.35, to = 1 }),
		Right = shade({ anchor = Vector2.new(1, 0), pos = UDim2.fromScale(1, 0), size = UDim2.fromScale(0.5, 1), rotation = 180, from = 0.4, to = 1 }),
		Left = shade({ anchor = Vector2.new(0, 0), pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(0.16, 1), rotation = 0, from = 0.5, to = 1 }),
	}), gui)
end

return InventoryBackdrop
