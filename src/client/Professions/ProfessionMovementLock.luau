--[[
	ProfessionMovementLock
	Holds the character still during a mining or fishing session: the camera is somewhere else, so
	walking would only drag the player out of range (which ends the session). Same key sink the
	wardrobe and the valve maze use. Esc and the mouse stay free.
]]

local ContextActionService = game:GetService("ContextActionService")
local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))

local ACTION = "ProfessionMovementLock"

local ProfessionMovementLock = {}

function ProfessionMovementLock.Set(on: boolean)
	if on then
		ContextActionService:BindActionAtPriority(ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 100,
			table.unpack(Keys.LockKeys())) -- movement + the current dash / sprint / crouch / ... keys
	else
		ContextActionService:UnbindAction(ACTION)
	end
end

return ProfessionMovementLock
