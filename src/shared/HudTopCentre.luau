--[[
	HudTopCentre -- who holds space at the top-centre of the screen, so readouts there stack
	instead of overlapping. Client-side only.

	The named-elite pity plate lives at the very top while you're in an elite zone; the combat
	XP bar (XpHud) shows top-centre on every kill. The plate reserves the strip it covers and
	the XP bar reads Bottom() to sit below it.

		HudTopCentre.Reserve(name, bottomPx?)  -- the lowest screen y (px) `name` covers; nil frees it
		HudTopCentre.Bottom()                  -- lowest reserved y, 0 when nothing is reserved
		HudTopCentre.Changed                   -- fires when Bottom() may have changed
]]

local HudTopCentre = {}

local reserved: { [string]: number } = {}
local changed = Instance.new("BindableEvent")
HudTopCentre.Changed = changed.Event

function HudTopCentre.Reserve(name: string, bottomPx: number?)
	if reserved[name] == bottomPx then return end
	reserved[name] = bottomPx
	changed:Fire()
end

function HudTopCentre.Bottom(): number
	local bottom = 0
	for _, y in pairs(reserved) do
		bottom = math.max(bottom, y)
	end
	return bottom
end

return HudTopCentre
