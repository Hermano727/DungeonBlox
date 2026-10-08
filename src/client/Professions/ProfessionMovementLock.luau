--[[
	ProfessionMovementLock
	Holds the character still during a mining or fishing session: the camera is somewhere else, so
	walking would only drag the player out of range (which ends the session). Same key sink the
	wardrobe and the valve maze use. Esc and the mouse stay free.
]]

local ContextActionService = game:GetService("ContextActionService")

local ACTION = "ProfessionMovementLock"

local ProfessionMovementLock = {}

function ProfessionMovementLock.Set(on: boolean)
	if on then
		ContextActionService:BindActionAtPriority(ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 100,
			Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down,
			Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.LeftControl,
			Enum.KeyCode.C, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.F, Enum.KeyCode.R, Enum.KeyCode.Tab,
			Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
			Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine)
	else
		ContextActionService:UnbindAction(ACTION)
	end
end

return ProfessionMovementLock
