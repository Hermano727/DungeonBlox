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
	Mount             = K.H,      -- calls / sends away your horse (MountClient; needs a saddle, out of combat)
	TogglePerspective = K.R,      -- cycles first-person <-> over-shoulder
	FreeLook          = { K.LeftControl, K.RightControl },

	-- Combat
	QuickDrink        = K.Z,      -- drinks a potion from the bag without swapping the held weapon. Was O: no O press
	                              -- ever reached the scripts in testing (O is one of Roblox's own camera zoom keys, I/O)
	QuickEat          = K.V,      -- eats one cooked fish from the bag (FishQuickEatClient)

	-- UI
	SkillsTab   = K.Tab,
	PartyMenu   = K.P,
	CloseMenu   = K.Escape,       -- used by every closable panel
	ReleaseValve = K.X,           -- lets go of a Miasma valve maze (Esc also tries, but Roblox's menu may eat it)
	ToggleMap   = K.M,            -- expands / collapses the world map (Minimap)
	MapZoomIn   = { K.Equals, K.KeypadPlus },  -- only while the map is expanded
	MapZoomOut  = { K.Minus, K.KeypadMinus },
	MapRecentre = K.C,            -- expanded map: back to following you
	MapDeleteMarker = K.Delete,   -- expanded map: removes the pin under the cursor
	SpectatePrev = K.Left,        -- while spectating the boss fight: previous / next teammate
	SpectateNext = K.Right,

	-- Admin / dev tools
	DevPlacer       = K.F8,
	HearthstoneMenu = K.F7,
	ItemGrantMenu   = K.F10,
	UIDevTool = K.F6,  -- dev-gated (DevRoster) live-nudge tool, now covers BOTH registered decorative UI art AND worn-armor Motor6D welds (Slash toggles which one it's tuning) -- see UIDevTuning and ArmorVisualsService (F9 is reserved by Studio's mic/voice panel, F10 is ItemGrantMenu, F11 is the OS/browser fullscreen bind -- don't use either for a dev tool)

	-- DevPlacer sub-controls (only live while DevPlacer is open)
	DevPlaceConfirm = K.Return,
	DevPlaceCorner  = K.E,
	DevPlaceDelete  = K.Backspace,
	DevToggleFly    = K.F,          -- DevPlacer fly on/off, independent of zone drawing
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

-------------------------------------------------------------------------------------------------
-- Rebinding (2026-10-11). The player changes keys on Settings > Controls; every script reads
-- Keys.<Action> at input time, so a change takes effect at once. The few that bind a key ONCE
-- (ContextActionService binds, HUD key labels) re-bind / re-label on Keybinds.Changed.
--
--   Keybinds.Actions                 the catalogue the Controls page draws, in order (below)
--   Keybinds.Set(id, keyCode)        rebind (one key; a default list like {LeftControl,
--                                    RightControl} becomes that single key)
--   Keybinds.Reset(id) / ResetAll()  back to the default
--   Keybinds.IsDefault(id)
--   Keybinds.Changed                 RBXScriptSignal(actionId or nil = many changed)
--   Keybinds.Check(id, keyCode)      -> ok, problem, otherActionEntry  (problem: "reserved",
--                                    "not_allowed", "locked_conflict", "conflict")
--   Keybinds.ApplySaved(map)         { [actionId] = "KeyCodeName" } from the settings store
--   Keybinds.DisplayName(binding)    "Esc", "Del", "+", "Ctrl" ... for a key or a list
--   Keybinds.LockKeys()              every key a movement lock should sink (current binds)
-- Saved as settings category "keys" (SettingsDataService validates with IsRebindable +
-- IsAllowedKey). Dev binds (F6..F10, DevPlacer sub-keys) are not in the catalogue.

-- The equip keys are actions of their own; ToolSlot (keyed by KeyCode) is rebuilt from them in
-- place, so scripts holding a reference to the table (HotbarHud) see the change.
Keybinds.EquipWeapon = K.One
Keybinds.EquipBow = K.Two
Keybinds.EquipPickaxe = K.Three
Keybinds.EquipSpear = K.Four
Keybinds.Sprint = { K.LeftShift, K.RightShift } -- Animate2 (also a gamepad L2, not rebindable)
Keybinds.Crouch = K.C                           -- Crouching

local EQUIP_SLOTS = {
	{ id = "EquipWeapon", slot = "Weapon" },
	{ id = "EquipBow", slot = "Bow" },
	{ id = "EquipPickaxe", slot = "Pickaxe" },
	{ id = "EquipSpear", slot = "FishingSpear" },
}
Keybinds.EQUIP_SLOTS = EQUIP_SLOTS

local function rebuildToolSlots()
	table.clear(Keybinds.ToolSlot)
	for _, entry in ipairs(EQUIP_SLOTS) do
		Keybinds.ToolSlot[Keybinds[entry.id]] = entry.slot
	end
end
rebuildToolSlots()

-- The Controls page, top to bottom. `id` = a rebindable field above. `fixed` = shown but locked
-- (engine / ProximityPrompt / reserved keys), `keys` its KeyCodes for conflict checks, `show`
-- the caps it displays. `context`: two actions only clash if their contexts match, or either is
-- "global" (live everywhere). The map's keys only work while the map is open ("map"), so C can
-- both crouch and recentre the map.
Keybinds.Actions = {
	{ section = "Movement" },
	{ label = "Move", fixed = true, keys = { K.W, K.A, K.S, K.D }, show = { "W", "A", "S", "D" }, context = "game" },
	{ label = "Jump", fixed = true, keys = { K.Space }, show = { "Space" }, context = "game" },
	{ id = "Sprint", label = "Sprint", context = "game" },
	{ id = "Crouch", label = "Crouch", context = "game" },
	{ id = "Dash", label = "Dash", context = "game" },
	{ id = "TogglePerspective", label = "Swap view", context = "game" },
	{ id = "FreeLook", label = "Free the cursor (hold)", context = "game" },
	{ id = "Mount", label = "Call horse", context = "game" },

	{ section = "Combat & Items" },
	{ label = "Attack", fixed = true, keys = {}, show = { "Click" }, context = "game" },
	{ label = "Draw bow (hold)", fixed = true, keys = {}, show = { "Click" }, context = "game" },
	{ id = "EquipWeapon", label = "Weapon", context = "game" },
	{ id = "EquipBow", label = "Bow", context = "game" },
	{ id = "EquipPickaxe", label = "Pickaxe", context = "game" },
	{ id = "EquipSpear", label = "Fishing spear", context = "game" },
	{ id = "QuickDrink", label = "Drink potion", context = "game" },
	{ id = "QuickEat", label = "Eat fish (hold: choose)", context = "game" },

	{ section = "Interaction" },
	{ label = "Interact", fixed = true, keys = { K.E }, show = { "E" }, context = "game" },
	{ label = "Dialogue choice", fixed = true, keys = {}, show = { "1-9" }, context = "dialog" },
	{ id = "ReleaseValve", label = "Let go of a valve", context = "valve" },
	{ id = "SpectatePrev", label = "Spectate: previous", context = "spectate" },
	{ id = "SpectateNext", label = "Spectate: next", context = "spectate" },

	{ section = "Menus" },
	{ id = "SkillsTab", label = "Character menu", context = "global" },
	{ id = "ToggleMap", label = "World map", context = "global" },
	{ id = "PartyMenu", label = "Party", context = "game" },
	{ label = "Close / back", fixed = true, keys = { K.Escape }, show = { "Esc" }, context = "global" },

	{ section = "World Map" },
	{ label = "Zoom", fixed = true, keys = {}, show = { "Scroll" }, context = "map" },
	{ id = "MapZoomIn", label = "Zoom in", context = "map" },
	{ id = "MapZoomOut", label = "Zoom out", context = "map" },
	{ label = "Place marker", fixed = true, keys = {}, show = { "Right click" }, context = "map" },
	{ id = "MapDeleteMarker", label = "Remove marker", context = "map" },
	{ id = "MapRecentre", label = "Centre on me", context = "map" },
}

local byId = {}
for _, entry in ipairs(Keybinds.Actions) do
	if entry.id then byId[entry.id] = entry end
end
function Keybinds.Action(id)
	return byId[id]
end
function Keybinds.IsRebindable(id)
	return type(id) == "string" and byId[id] ~= nil
end

-- Keys that may be bound. Everything else is refused: Escape (closes menus), Slash (chat),
-- Backquote (Roblox dev console), F9 (console) / F11 (fullscreen) / F12 (recording), I / O
-- (Roblox camera zoom), the dev F-keys, mouse buttons.
local RESERVED = {
	[K.Escape] = "closes menus", [K.Slash] = "opens chat", [K.Backquote] = "is Roblox's console",
	[K.F9] = "is Roblox's console", [K.F11] = "is fullscreen", [K.F12] = "is Roblox's recorder",
	[K.I] = "is Roblox's camera zoom", [K.O] = "is Roblox's camera zoom",
	[K.F6] = "is a dev tool", [K.F7] = "is a dev tool", [K.F8] = "is a dev tool", [K.F10] = "is a dev tool",
	[K.Print] = "takes screenshots",
}
local ALLOWED = {}
for _, name in ipairs({
	"A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "P", "Q", "R", "S", "T", "U",
	"V", "W", "X", "Y", "Z",
	"Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
	"Tab", "CapsLock", "LeftShift", "RightShift", "LeftControl", "RightControl", "LeftAlt", "RightAlt",
	"Space", "Return", "Backspace", "Delete", "Insert", "Home", "End", "PageUp", "PageDown",
	"Up", "Down", "Left", "Right",
	"Minus", "Equals", "LeftBracket", "RightBracket", "Semicolon", "Quote", "Comma", "Period", "BackSlash",
	"KeypadZero", "KeypadOne", "KeypadTwo", "KeypadThree", "KeypadFour", "KeypadFive", "KeypadSix",
	"KeypadSeven", "KeypadEight", "KeypadNine", "KeypadPeriod", "KeypadDivide", "KeypadMultiply",
	"KeypadMinus", "KeypadPlus", "KeypadEnter",
	"F1", "F2", "F3", "F4", "F5",
}) do
	ALLOWED[name] = true
end
function Keybinds.IsAllowedKey(keyName)
	return type(keyName) == "string" and ALLOWED[keyName] == true
end
function Keybinds.ReservedReason(keyCode)
	return RESERVED[keyCode]
end

-- Short names for keys whose Enum name reads badly on a key cap.
local SHORT_NAMES = {
	Escape = "Esc", Equals = "=", Minus = "-", KeypadPlus = "Num +", KeypadMinus = "Num -",
	KeypadMultiply = "Num *", KeypadDivide = "Num /", KeypadPeriod = "Num .", KeypadEnter = "Num Enter",
	Delete = "Del", Insert = "Ins", PageUp = "PgUp", PageDown = "PgDn", Backspace = "Back",
	LeftControl = "Ctrl", RightControl = "Ctrl", LeftShift = "Shift", RightShift = "Shift",
	LeftAlt = "Alt", RightAlt = "Alt", Return = "Enter", CapsLock = "Caps", BackSlash = "\\",
	LeftBracket = "[", RightBracket = "]", Semicolon = ";", Quote = "'", Comma = ",", Period = ".",
	Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7",
	Eight = "8", Nine = "9",
}
for i, word in ipairs({ "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }) do
	SHORT_NAMES["Keypad" .. word] = "Num " .. tostring(i - 1)
end
local function keyName(keyCode)
	return SHORT_NAMES[keyCode.Name] or keyCode.Name
end

-- Display names for a binding, one per distinct name ({LeftControl, RightControl} -> {"Ctrl"}).
function Keybinds.DisplayNames(binding)
	local list = typeof(binding) == "EnumItem" and { binding } or (type(binding) == "table" and binding or {})
	local seen, out = {}, {}
	for _, key in ipairs(list) do
		if typeof(key) == "EnumItem" then
			local name = keyName(key)
			if not seen[name] then
				seen[name] = true
				table.insert(out, name)
			end
		end
	end
	return out
end
function Keybinds.DisplayName(binding)
	return Keybinds.DisplayNames(binding)[1] or "?"
end

-- The defaults, captured before anything can change them.
local defaults = {}
for id in pairs(byId) do
	local v = Keybinds[id]
	defaults[id] = type(v) == "table" and table.clone(v) or v
end

local function keysOf(binding)
	if typeof(binding) == "EnumItem" then return { binding } end
	return type(binding) == "table" and binding or {}
end

local function sameBinding(a, b)
	local ka, kb = keysOf(a), keysOf(b)
	if #ka ~= #kb then return false end
	for i, key in ipairs(ka) do
		if kb[i] ~= key then return false end
	end
	return true
end

function Keybinds.Default(id)
	return defaults[id]
end
function Keybinds.IsDefault(id)
	return sameBinding(Keybinds[id], defaults[id])
end

local function contextsClash(a, b)
	return a == b or a == "global" or b == "global"
end

-- Can `id` take `keyCode`? Returns true, or false + the problem + the entry it clashes with.
function Keybinds.Check(id, keyCode)
	local entry = byId[id]
	if not entry or typeof(keyCode) ~= "EnumItem" then return false, "not_allowed" end
	if RESERVED[keyCode] then return false, "reserved" end
	if not ALLOWED[keyCode.Name] then return false, "not_allowed" end
	for _, other in ipairs(Keybinds.Actions) do
		if other ~= entry and other.label and contextsClash(entry.context, other.context) then
			local keys = other.fixed and other.keys or keysOf(Keybinds[other.id])
			if table.find(keys, keyCode) then
				return false, other.fixed and "locked_conflict" or "conflict", other
			end
		end
	end
	return true
end

-- Changed: a BindableEvent made on first use (this module is required on the server too).
local changedEvent
local function fire(id)
	if changedEvent then changedEvent:Fire(id) end
end
setmetatable(Keybinds, {
	__index = function(_, key)
		if key == "Changed" then
			changedEvent = changedEvent or Instance.new("BindableEvent")
			return changedEvent.Event
		end
		return nil
	end,
})

local function assign(id, value)
	Keybinds[id] = value
	if id:sub(1, 5) == "Equip" then rebuildToolSlots() end
end

function Keybinds.Set(id, keyCode)
	if not byId[id] or typeof(keyCode) ~= "EnumItem" then return false end
	assign(id, keyCode)
	fire(id)
	return true
end

function Keybinds.Reset(id)
	if not byId[id] then return end
	local d = defaults[id]
	assign(id, type(d) == "table" and table.clone(d) or d)
	fire(id)
end

function Keybinds.ResetAll()
	for id in pairs(byId) do
		local d = defaults[id]
		assign(id, type(d) == "table" and table.clone(d) or d)
	end
	fire(nil)
end

-- The saved bindings ({ [id] = "KeyCodeName" }) on top of the defaults. All are applied first
-- (so a saved swap, Dash <-> Mount, lands whole), then any saved one that still clashes or is
-- invalid goes back to its default.
function Keybinds.ApplySaved(saved)
	if type(saved) ~= "table" then return end
	local applied = {}
	for id, name in pairs(saved) do
		if byId[id] and Keybinds.IsAllowedKey(name) then
			local ok, keyCode = pcall(function() return K[name] end)
			if ok and keyCode and not RESERVED[keyCode] then
				assign(id, keyCode)
				table.insert(applied, id)
			end
		end
	end
	for _, id in ipairs(applied) do
		if not Keybinds.Check(id, Keybinds[id]) then
			local d = defaults[id]
			assign(id, type(d) == "table" and table.clone(d) or d)
		end
	end
	fire(nil)
end

-- Every key a "you can't move right now" lock should sink: movement and the current binds of
-- the actions that move you or open things.
function Keybinds.LockKeys()
	local list = {
		K.W, K.A, K.S, K.D, K.Up, K.Down, K.Left, K.Right, K.Space, K.E, K.F, K.LeftControl, K.RightControl,
		K.One, K.Two, K.Three, K.Four, K.Five, K.Six, K.Seven, K.Eight, K.Nine,
	}
	for _, id in ipairs({ "Sprint", "Crouch", "Dash", "TogglePerspective", "SkillsTab",
		"EquipWeapon", "EquipBow", "EquipPickaxe", "EquipSpear" }) do
		for _, key in ipairs(keysOf(Keybinds[id])) do
			if not table.find(list, key) then table.insert(list, key) end
		end
	end
	return list
end

return Keybinds
