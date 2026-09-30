--[[
	InteractionLock
	Marks that the player is inside a modal world interaction (the Enchanting
	Station today; banks, shops, crafting stations, etc. later) so global
	hotkeys that would open a competing menu on top of it -- Tab/inventory
	being the first -- can ask "is something modal open?" and stand down.

	Each interaction registers itself under a unique owner name and releases
	that same name when it closes. Owners are a set, not a counter, so a double
	Acquire or double Release from one owner can never leave the lock stuck or
	free it while another interaction still holds it.

	What stays available INSIDE an interaction is that interaction's own
	decision (the Enchanting Station embeds the real bag grid itself); this
	module only answers "should the global hotkeys be suppressed?".

	Usage:
		InteractionLock.Acquire("EnchantStation")   -- on open
		InteractionLock.Release("EnchantStation")   -- on close
		if InteractionLock.IsLocked() then return end  -- in a global hotkey handler
		InteractionLock.Subscribe(fn)  -- fn(locked: boolean), e.g. to close an already-open menu
		InteractionLock.IsHeldByOther("WorldMap")   -- a lock owner asking "is someone ELSE modal?"

	Two kinds of screen (2026-09-29, one UI stack for the whole game):
	  BLOCKING overlays -- the world map (M), the Enchanting Station, the cleanse channel --
	    Acquire the lock. While one is up, MENU hotkeys (Tab, P, the settings gear) do nothing;
	    gameplay binds (dash, movement, combat) are untouched. Opening one closes any open menu
	    (the menus Subscribe and close themselves when the lock turns on).
	  SWITCHABLE menus -- inventory, party panel, settings -- replace each other: OpenMenu()
	    closes whichever other menu was open (runs its close callback), and they refuse to open
	    while a blocking overlay holds the lock.
		InteractionLock.OpenMenu("Inventory", function() setOpen(false) end)  -- on open
		InteractionLock.MenuClosed("Inventory")                                 -- on close

	Vitals (2026-09-30): every menu and overlay here hides the HP/energy/hunger cluster
	(RS/HudVitals) while it's up, unless it passes { keepVitals = true } -- the inventory and
	the cleanse channel do, since health matters there.
		InteractionLock.OpenMenu(name, close, { keepVitals = true })
		InteractionLock.Acquire(owner, { keepVitals = true })
]]

local HudVitals = require(script.Parent:WaitForChild("HudVitals"))

local InteractionLock = {}

local owners: { [string]: boolean } = {}
local lockedNow = false
local listeners: { [(boolean) -> ()]: boolean } = {}

local function refresh()
	local anyOwner = next(owners) ~= nil
	if anyOwner == lockedNow then
		return
	end
	lockedNow = anyOwner
	for fn in pairs(listeners) do
		task.spawn(fn, lockedNow)
	end
end

function InteractionLock.Acquire(owner: string, opts: { keepVitals: boolean? }?)
	owners[owner] = true
	HudVitals.SetHidden("lock:" .. owner, not (opts and opts.keepVitals))
	refresh()
end

function InteractionLock.Release(owner: string)
	owners[owner] = nil
	HudVitals.SetHidden("lock:" .. owner, false)
	refresh()
end

function InteractionLock.IsLocked(): boolean
	return lockedNow
end

-- True when some owner OTHER than `owner` holds the lock (for owners that must not block themselves).
function InteractionLock.IsHeldByOther(owner: string): boolean
	for name in pairs(owners) do
		if name ~= owner then return true end
	end
	return false
end

-- Switchable menus: at most one open. Opening one closes the previous one.
local currentMenu: string? = nil
local currentClose: (() -> ())? = nil

function InteractionLock.OpenMenu(name: string, close: () -> (), opts: { keepVitals: boolean? }?)
	if currentMenu and currentMenu ~= name and currentClose then
		local previousClose = currentClose
		HudVitals.SetHidden("menu:" .. currentMenu, false)
		currentMenu, currentClose = nil, nil
		task.spawn(previousClose)
	end
	currentMenu, currentClose = name, close
	HudVitals.SetHidden("menu:" .. name, not (opts and opts.keepVitals))
end

function InteractionLock.MenuClosed(name: string)
	HudVitals.SetHidden("menu:" .. name, false)
	if currentMenu == name then
		currentMenu, currentClose = nil, nil
	end
end

function InteractionLock.Subscribe(fn: (boolean) -> ()): () -> ()
	listeners[fn] = true
	return function()
		listeners[fn] = nil
	end
end

return InteractionLock
