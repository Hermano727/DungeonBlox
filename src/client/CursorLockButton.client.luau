--[[
	CursorLockButton -- a "Lock Cursor" button in the quick-nav row under the minimap
	(RS/HudQuickNav, right of the settings gear), added 2026-10-11.

	A generic escape hatch. If some UI frees the cursor and never gives it back (a leaked
	CursorUtils hold re-frees it every frame), the camera can't turn and even Ctrl's FreeLook
	can't take it back. The cursor is free in exactly that state, so this button is clickable:
	it closes any open menu the normal way (InteractionLock.CloseMenu, so that menu releases
	its own hold), then drops every hold that's left and locks the cursor
	(CursorUtils.ForceRelock + CursorManager.reset).

	The row hides while the Tab menu is open, so it can't fight a menu that legitimately owns
	the cursor. Root-cause leaks still get fixed where they are (the party invite, 2026-10-11).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuickNav = require(ReplicatedStorage:WaitForChild("HudQuickNav"))
local CursorUtils = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local CursorManager = require(ReplicatedStorage:WaitForChild("CursorManager"))
local InteractionLock = require(ReplicatedStorage:WaitForChild("InteractionLock"))
local JournalUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("JournalUI"))

-- The shared quick-nav button (plate, hover, tooltip), with the lock art from the journal set.
local lockArt = JournalUI.lock_icon
local button = QuickNav.Button({
	name = "CursorLock",
	order = QuickNav.ORDER.CursorLock,
	tooltip = "Lock Cursor",
	image = (type(lockArt) == "table" and lockArt.Image) or "",
	iconSize = 18,
	tint = Color3.fromRGB(236, 226, 208),
})

button.Activated:Connect(function()
	local leaked = CursorUtils.Holds()
	InteractionLock.CloseMenu()
	-- Let a closing menu run its own release first (CloseMenu spawns its close callback).
	task.defer(function()
		CursorUtils.ForceRelock()
		CursorManager.reset()
		if leaked > 0 then
			warn(("[CursorLockButton] relocked the cursor (%d open hold(s) dropped)"):format(leaked))
		end
	end)
end)
