--[[
	HudVitals (client-only; lives in RS so every client script shares one copy)

	Whether the vitals cluster (HP bar, energy bar, hunger/potion row) is shown. By default
	every UI screen hides it: InteractionLock feeds this for every switchable menu (OpenMenu)
	and every blocking overlay (Acquire), so a new menu gets the behaviour for free. A screen
	where your health is crucial opts OUT with { keepVitals = true }:
		InteractionLock.OpenMenu("Inventory", close, { keepVitals = true })
		InteractionLock.Acquire("MiasmaCleanse", { keepVitals = true })
	The Miasma valve maze registers nothing, so it keeps the vitals (it even moves them).

	Screens that aren't InteractionLock users can call SetHidden directly (the Tab menu does,
	per tab: only the Inventory tab keeps the vitals).

		HudVitals.SetHidden(owner, hidden)   -- owner: any unique string
		HudVitals.IsHidden() -> boolean       -- true while ANY owner hides them
		HudVitals.Subscribe(fn) -> unsubscribe  -- fn(hidden) on every change

	Consumers: HealthClient (HP + hunger/potions), EnergyClient (energy).
]]

local HudVitals = {}

local hiders: { [string]: boolean } = {}
local hiddenNow = false
local listeners: { [(boolean) -> ()]: boolean } = {}

local function refresh()
	local hidden = next(hiders) ~= nil
	if hidden == hiddenNow then return end
	hiddenNow = hidden
	for fn in pairs(listeners) do
		task.spawn(fn, hiddenNow)
	end
end

function HudVitals.SetHidden(owner: string, hidden: boolean)
	hiders[owner] = hidden and true or nil
	refresh()
end

function HudVitals.IsHidden(): boolean
	return hiddenNow
end

function HudVitals.Subscribe(fn: (boolean) -> ()): () -> ()
	listeners[fn] = true
	return function()
		listeners[fn] = nil
	end
end

return HudVitals
