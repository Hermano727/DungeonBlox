--  KeybindConfig
--  Single source of truth for every key binding in the game.
--  Require this instead of writing Enum.KeyCode literals inline.
--
--  Usage:
--      local Keys = require(ReplicatedStorage.KeybindConfig)
--      if input.KeyCode == Keys.Dash then ... end
--      local slot = Keys.HotbarSlot[input.KeyCode]   -- 1..9 or nil
--
--  Naming: PascalCase action names describing INTENT, not the key.
--  "Dash" not "Q" - so rebinding is a one-line change here.
--
--  KNOWN CONFLICT (2026-07): DevPlacer and HearthstoneDevMenu both listen
--  on F8. Both are admin-only tools so it has not surfaced in play, but
--  they will fire together. Reassign one when convenient.

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
	HearthstoneMenu = K.F8,       -- see KNOWN CONFLICT above
	ItemGrantMenu   = K.F10,

	-- DevPlacer sub-controls (only live while DevPlacer is open)
	DevPlaceConfirm = K.Return,
	DevPlaceCorner  = K.E,
	DevPlaceDelete  = K.Backspace,
}

-- Hotbar slots 1-9. Defined once here; DungeonHotbarHud and
-- InventoryDragController previously each had their own copy.
Keybinds.HotbarSlot = {
	[K.One]   = 1,
	[K.Two]   = 2,
	[K.Three] = 3,
	[K.Four]  = 4,
	[K.Five]  = 5,
	[K.Six]   = 6,
	[K.Seven] = 7,
	[K.Eight] = 8,
	[K.Nine]  = 9,
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
