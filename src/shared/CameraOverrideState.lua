--[[
	CameraOverrideState
	Tiny flag letting a client system (e.g. EnchantStationClient's altar-view
	camera pan) temporarily take ownership of workspace.CurrentCamera away
	from FirstPersonViewModel.client.lua, which otherwise reasserts
	CameraType/CFrame every single RenderStep frame and would instantly
	stomp anything else trying to drive the camera.

	FirstPersonViewModel checks IsActive() at the top of its per-frame
	updateCamera and returns early while true, leaving CameraType as the
	Scriptable it already set and NOT touching CFrame -- the override owner
	is free to Tween/set camera.CFrame itself. Setting this back to false
	hands control back next frame; FirstPersonViewModel recomputes from the
	live head position, so control returns with a snap, not a tween -- fine
	for a menu-camera handoff, not meant for anything that needs a smooth
	return transition.

	RequestLook(direction) (2026-09-27): an override owner can ask for the player's
	own camera to come back LOOKING somewhere (e.g. the boss drop cutscene hands back
	facing the boss). FirstPersonViewModel consumes it once, on its first frame after
	the override ends, and turns its own yaw/pitch to match.
]]

local CameraOverrideState = {}

local active = false

function CameraOverrideState.SetActive(v: boolean)
	active = not not v
end

function CameraOverrideState.IsActive(): boolean
	return active
end

local requestedLook: Vector3? = nil

function CameraOverrideState.RequestLook(direction: Vector3)
	if typeof(direction) == "Vector3" and direction.Magnitude > 1e-3 then
		requestedLook = direction.Unit
	end
end

-- Returns the pending look direction once (then clears it), or nil.
function CameraOverrideState.ConsumeLook(): Vector3?
	local look = requestedLook
	requestedLook = nil
	return look
end

return CameraOverrideState
