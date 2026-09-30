--[[
	CursorIcon -- the one rule for the OS/Roblox arrow: a LOCKED mouse never shows it.

	Why this exists: the first-person camera locks the mouse (MouseBehavior LockCenter) but
	nothing ever hid the arrow, so every session started with Roblox's black arrow sitting on
	top of our crosshair until Ctrl (FreeLookClient / CursorManager) happened to set
	MouseIconEnabled = false on release.

	How it works: every frame, AFTER every other cursor writer (CursorUtils and the valve maze
	run at RenderPriority.Last, the dev panel at Last + 1, the spectator at Last + 10), if the
	final behaviour is LockCenter the icon is hidden. Free-cursor systems (menus through
	CursorUtils, Ctrl freelook, spectating) still show the arrow exactly as before; this only
	ever hides it while locked.

	Engine bug workaround (DevForum, "MouseIconEnabled = false state ignored whenever the cursor
	(re)enters the window"): after the window regains focus Roblox can draw the arrow even
	though MouseIconEnabled is still false. The documented fix is to flip it true for a frame
	and back to false, so that is done once at startup and on every WindowFocused (not on every
	menu close: that would flash the arrow for a frame each time, and isn't where the bug is).
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BIND = "CursorIconRule"

local kickPending = true -- flip true -> false over two frames to re-assert the hidden state

RunService:BindToRenderStep(BIND, Enum.RenderPriority.Last.Value + 20, function()
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then return end
	if kickPending then
		kickPending = false
		UserInputService.MouseIconEnabled = true -- shown for this one frame; hidden again next frame
		return
	end
	if UserInputService.MouseIconEnabled then UserInputService.MouseIconEnabled = false end
end)

UserInputService.WindowFocused:Connect(function()
	kickPending = true
end)
