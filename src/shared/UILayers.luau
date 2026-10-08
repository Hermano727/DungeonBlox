--[[
	UILayers -- named ScreenGui DisplayOrders, so "what draws over what" is decided in one place.

	Higher draws on top. Existing screens still set their own numbers (listed here for
	reference); new ones should take a layer from this table instead of inventing a number.

		HUD           5..110    crosshair 5, vitals 110 (HealthBarGui)
		MENUS         120       the Tab menu (ProfileMenusReact)
		QUICK_NAV     251       the button row under the minimap (HudQuickNav)
		SETTINGS      250..260  settings screen and its pages
		TIPS          400       hover tooltips (Journal TipLayer)
		TUTORIAL      500       the tutorial's objective, path pointer, focus and spotlights:
		                        above every menu and HUD row, so it can point at them
		OVERLAYS      900..1000 cutscenes, dialog, centre flashes
		TRAVEL        9000      the hearthstone travel screen
		LOADING       10000     the loading screen (ReplicatedFirst; can't require this module)
]]

return table.freeze({
	MENUS = 120,
	QUICK_NAV = 251,
	TIPS = 400,
	TUTORIAL = 500,
	TRAVEL = 9000,
	LOADING = 10000,
})
