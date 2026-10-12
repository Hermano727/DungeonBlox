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

-- Clears every reason (CursorUtils.ForceRelock's partner, used by client/CursorLockButton).
function CursorManager.reset()
	table.clear(reasons)
	UserInputService.MouseBehavior    = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
end

return CursorManager
