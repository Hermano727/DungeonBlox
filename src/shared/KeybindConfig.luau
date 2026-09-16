--  KeybindConfig
--  Single source of truth for every key binding in the game.
--  Require this instead of writing Enum.KeyCode literals inline.
--
--  Usage:
--      local Keys = require(ReplicatedStorage.KeybindConfig)
--      if input.KeyCode == Keys.Dash then ... end
--      local slot = Keys.ToolSlot[input.KeyCode]   -- "Weapon"|"Bow"|"Pickaxe"|"FishingSpear" or nil
--
--  Naming: PascalCase action names describing INTENT, not the key.
--  "Dash" not "Q" - so rebinding is a one-line change here.
--
--  FIXED (2026-08): DevPlacer and HearthstoneDevMenu used to both listen on
--  F8 and fire together. HearthstoneMenu moved to F7.

local K = Enum.KeyCode

local Keybinds = {
	-- Movement / camera
	Dash              = K.Q,
	TogglePerspective = K.R,      -- cycles first-person <-> over-shoulder
	FreeLook          = { K.LeftControl, K.RightControl },

	-- UI
	SkillsTab   = K.Tab,
	PartyMenu   = K.P,
	CloseMenu   = K.Escape,       -- used by every closable panel

	-- Admin / dev tools
	DevPlacer       = K.F8,
	HearthstoneMenu = K.F7,
	ItemGrantMenu   = K.F10,
	UIDevTool = K.F6,  -- dev-gated (DevRoster) live-nudge tool, now covers BOTH registered decorative UI art AND worn-armor Motor6D welds (Slash toggles which one it's tuning) -- see UIDevTuning and ArmorVisualsService (F9 is reserved by Studio's mic/voice panel, F10 is ItemGrantMenu, F11 is the OS/browser fullscreen bind -- don't use either for a dev tool)

	-- DevPlacer sub-controls (only live while DevPlacer is open)
	DevPlaceConfirm = K.Return,
	DevPlaceCorner  = K.E,
	DevPlaceDelete  = K.Backspace,
}

-- Tool-equip slots 1-4 (replaces the old freeform 9-slot hotbar): fixed mapping to the
-- matching profile.equipped slot name. Pressing a key with nothing equipped there is a no-op.
Keybinds.ToolSlot = {
	[K.One]   = "Weapon",
	[K.Two]   = "Bow",
	[K.Three] = "Pickaxe",
	[K.Four]  = "FishingSpear",
}

-- Dialogue option select. ORDERED array - DialogModule uses table.find()
-- to turn a keypress into a 1-based choice index, so order matters here
-- in a way it does not for HotbarSlot above.
Keybinds.DialogChoice = {
	K.One, K.Two, K.Three, K.Four, K.Five, K.Six, K.Seven, K.Eight, K.Nine,
}

--- True if `keyCode` matches a binding that may be a single key or a list.
function Keybinds.Matches(binding, keyCode)
	if typeof(binding) == "EnumItem" then
		return binding == keyCode
	end
	if type(binding) == "table" then
		for _, k in ipairs(binding) do
			if k == keyCode then return true end
		end
	end
	return false
end

return Keybinds
