--[[
	CursorManager
	Reference-counted cursor lock. Any system registers a named reason to keep
	the cursor free; cursor only re-locks when every reason is cleared.
	Works with FirstPersonViewModel's MouseBehavior guard on line 99.
]]

local UserInputService = game:GetService("UserInputService")
local reasons = {}

local CursorManager = {}

function CursorManager.setFree(reason, free)
	if free then
		reasons[reason] = true
	else
		reasons[reason] = nil
	end
	local anyFree = next(reasons) ~= nil
	UserInputService.MouseBehavior    = anyFree and Enum.MouseBehavior.Default or Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = anyFree
end

return CursorManager
