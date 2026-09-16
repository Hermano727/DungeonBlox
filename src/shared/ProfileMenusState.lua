--[[
	ProfileMenusState
	Tiny open/closed pub-sub for the persistent-header Inventory/Skills/Stats/
	Hearthstone/Party panel (InventoryHud/init.client.lua's gui.Enabled) --
	added 2026-09-13 so other HUD pieces that need to react to it opening
	(Hotbar hiding, HP/Energy/Hunger/Potions relocating) don't each have to
	poll for the ScreenGui themselves.

	Distinct from SkillXPShared's old SetSkillsMenuOpen/IsSkillsMenuOpen
	(removed the same day, see SkillXPShared.lua) -- that one meant "is the
	Skills TAB specifically open"; this one means "is the panel open at all",
	true the moment ANY tab (Inventory included) is showing.

	CarouselAnchor (added same day, second pass): the live bottom-center point
	of QuickNav's rendered icon row, in real screen pixels -- published by
	QuickNav.lua itself (it's the only thing that knows its own current
	scale-to-fit factor and AbsolutePosition) and consumed by HealthClient/
	EnergyClient so the HP/Energy/Hunger/Potion cluster can hang directly
	beneath the carousel instead of the two files independently re-deriving
	the carousel's position from a pile of hand-copied constants (that
	approach was tried first -- top-right corner, fixed math -- and broke the
	moment the carousel's own size/position needed to change again, since it
	required cross-file surface area no differently-sized screen or future nudge
	could survive automatically). Reuses the same listeners/notify() as
	IsOpen() -- both HealthClient/EnergyClient's applyProfileMenusLayout()
	already re-run on every notify() and just read whichever of IsOpen()/
	GetCarouselAnchor() they need, so one Subscribe covers both.
]]

local ProfileMenusState = {}

local listeners = {}
local isOpen = false
local carouselAnchor: Vector2? = nil

function ProfileMenusState.Subscribe(callback)
	listeners[callback] = true
	return function()
		listeners[callback] = nil
	end
end

local function notify()
	for callback in pairs(listeners) do
		task.spawn(callback)
	end
end

function ProfileMenusState.SetOpen(open: boolean)
	open = not not open
	if isOpen == open then
		return
	end
	isOpen = open
	notify()
end

function ProfileMenusState.IsOpen(): boolean
	return isOpen
end

-- pos is the bottom-center of QuickNav's actual rendered icon row, in real screen pixels
-- (AbsolutePosition-space, same coordinate system every ScreenGui's AbsolutePosition already
-- resolves into regardless of that GUI's own IgnoreGuiInset setting). nil means "not known yet"
-- (shouldn't normally happen -- QuickNav publishes on mount -- but subscribers should treat a
-- nil anchor as "don't move" rather than erroring).
function ProfileMenusState.SetCarouselAnchor(pos: Vector2?)
	carouselAnchor = pos
	notify()
end

function ProfileMenusState.GetCarouselAnchor(): Vector2?
	return carouselAnchor
end

return ProfileMenusState
