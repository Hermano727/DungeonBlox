--!strict
--  UIDevTuning
--  Generic registry of live-tunable numeric "knobs" (scale / offset /
--  rotation) for decorative UI art, so ONE dev tool (UIDevTool, bound to
--  KeybindConfig.UIDevTool) can nudge ANY registered panel's art at
--  runtime instead of every panel needing its own bespoke tuning module +
--  keybind. Started life as XpHudBranchTuning (single-purpose, XP-bar-only);
--  generalized so the next panel that needs this (per-corner icons, banner
--  art, whatever) just calls Register() instead of copy-pasting a module.
--
--  Usage from a UI module (see XpHud.lua for the reference integration):
--      local UIDevTuning = require(ReplicatedStorage.UIDevTuning)
--      local tuning = UIDevTuning.Register("MyPanelName", {
--          SomeImage = { Scale = 1, OffsetX = 0, OffsetY = 0, Rotation = 0 },
--          -- ^ "target" name is yours to choose; register as many as you
--          --   have independently-tunable images. Values are just numbers
--          --   -- YOUR component decides what they mean (which edge they
--          --   anchor to, whether Scale is relative to some parent size,
--          --   etc.) via its own geometry function, same as XpHud's
--          --   branchGeometry(). This module only stores + broadcasts them.
--      })
--      -- in your component:
--      local state, setState = React.useState(tuning:Get())
--      React.useEffect(function()
--          return tuning:Subscribe(function() setState(tuning:Get()) end)
--      end, {})
--
--  Registered state is a runtime scratchpad, not the source of truth: once
--  a look is dialed in via UIDevTool, print a snapshot (Enter key in the
--  tool) and hand-copy the constants back into the owning UI module's
--  Register() call, so the tuned look survives a server restart.
--
--  Not wired into the release build UI -- nothing reaches into a panel's
--  GUI instances directly. Every value flows through the owning panel's own
--  React state, per the "a panel's ScreenGui belongs to that panel alone"
--  rule (see XpHud LocalScript).

local UIDevTuning = {}

export type TuneableValue = {
	Scale: number,
	OffsetX: number,
	OffsetY: number,
	Rotation: number,
}
export type TargetTable = { [string]: TuneableValue }

export type Handle = {
	Get: (self: Handle) -> TargetTable,
	Set: (self: Handle, target: string, patch: { [string]: any }) -> (),
	Reset: (self: Handle, target: string?) -> (),
	Subscribe: (self: Handle, callback: () -> ()) -> (() -> ()),
	Snapshot: (self: Handle) -> string,
	TargetNames: (self: Handle) -> { string },
}

local registry: { [string]: Handle } = {}
local registrationOrder: { string } = {}

local function cloneTargets(targets: TargetTable): TargetTable
	local out = {}
	for name, value in pairs(targets) do
		out[name] = table.clone(value)
	end
	return out
end

--- Register a new tunable UI, or fetch the existing handle if `id` was
--- already registered (safe to call every time your module loads/re-runs).
function UIDevTuning.Register(id: string, defaults: TargetTable): Handle
	if registry[id] then
		return registry[id]
	end

	local targetNames = {}
	for name in pairs(defaults) do
		table.insert(targetNames, name)
	end
	table.sort(targetNames) -- deterministic Tab-cycling order in the dev tool

	local state = cloneTargets(defaults)
	local listeners: { () -> () } = {}

	local function notify()
		for _, cb in ipairs(listeners) do
			task.defer(cb)
		end
	end

	local handle = {} :: Handle

	function handle:Get()
		return state
	end

	-- Merges `patch` into the named target and notifies. Replaces the whole
	-- state table with a fresh one (never mutates in place) so
	-- React.useState sees a new reference and actually re-renders.
	function handle:Set(target, patch)
		if state[target] == nil then
			return
		end
		local nextState = cloneTargets(state)
		for k, v in pairs(patch) do
			nextState[target][k] = v
		end
		state = nextState
		notify()
	end

	function handle:Reset(target)
		if target == nil then
			state = cloneTargets(defaults)
		else
			local nextState = cloneTargets(state)
			nextState[target] = table.clone(defaults[target])
			state = nextState
		end
		notify()
	end

	function handle:Subscribe(callback)
		table.insert(listeners, callback)
		return function()
			for i = #listeners, 1, -1 do
				if listeners[i] == callback then
					table.remove(listeners, i)
				end
			end
		end
	end

	-- Ready-to-paste block for the owning module's Register() defaults.
	function handle:Snapshot()
		local lines = {}
		for _, name in ipairs(targetNames) do
			local t = state[name]
			table.insert(lines, string.format(
				"-- %s: Scale=%.3f  OffsetX=%d  OffsetY=%d  Rotation=%d",
				name, t.Scale, t.OffsetX, t.OffsetY, t.Rotation
			))
		end
		return table.concat(lines, "\n")
	end

	function handle:TargetNames()
		return targetNames
	end

	registry[id] = handle
	table.insert(registrationOrder, id)
	return handle
end

--- IDs in registration order, for UIDevTool to cycle through.
function UIDevTuning.List(): { string }
	return registrationOrder
end

function UIDevTuning.GetHandle(id: string): Handle?
	return registry[id]
end

return UIDevTuning
