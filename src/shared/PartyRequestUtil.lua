--[[
	PartyRequestUtil
	Thin shared wrapper around the PartyRequest RemoteFunction so every
	client-side party UI talks to the server the same way instead of each
	keeping its own copy-pasted pcall wrapper. Today that's the legacy
	PartyClient popup + HUD and the newer InventoryHud PartyPanel; both used
	to define an identical local `request(action, arg)` function.

	Return shape matches PartyService.onPartyRequest exactly: (ok, err).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartyRequest = ReplicatedStorage:WaitForChild("PartyRequest")

local PartyRequestUtil = {}

-- action: "invite" | "accept" | "decline" | "leave" | "create"
function PartyRequestUtil.Request(action, arg)
	local ok, success, err = pcall(function()
		return PartyRequest:InvokeServer(action, arg)
	end)
	if not ok then
		warn("[PartyRequestUtil] request failed:", success)
		return false, "invoke_failed"
	end
	return success, err
end

return PartyRequestUtil
