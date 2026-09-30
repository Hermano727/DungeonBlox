--[[
	PartyRequestUtil
	Thin shared wrapper around the PartyRequest RemoteFunction so every
	client-side party UI talks to the server the same way instead of each
	keeping its own copy-pasted pcall wrapper. Today that's the legacy
	PartyClient popup + HUD and the newer InventoryHud PartyPanel; both used
	to define an identical local `request(action, arg)` function.

	Return shape matches PartyService.onPartyRequest exactly: (ok, err).

	Also the client's one cache of the latest PartyStateSync payload. A UI that mounts
	later (the React Party tab re-mounts every time it opens) reads GetMyParty() and
	listens on Changed, instead of starting empty and waiting for the next change -- which
	showed "No Party" with Leave greyed out while you were in a party.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PartyRequest = ReplicatedStorage:WaitForChild("PartyRequest")

local PartyRequestUtil = {}

local latest = nil -- last PartyStateSync payload
local changed = Instance.new("BindableEvent")
-- Fires with the new payload whenever the cached party state changes.
PartyRequestUtil.Changed = changed.Event

local function store(payload)
	if type(payload) ~= "table" then return end
	latest = payload
	changed:Fire(payload)
end

if RunService:IsClient() then
	ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("PartyStateSync").OnClientEvent:Connect(store)
end

-- The whole last payload ({ myParty, partyUserIds, ... }), or nil before the first one.
function PartyRequestUtil.GetState()
	return latest
end

-- Your party ({ leaderUserId, members }), or nil when not in one.
function PartyRequestUtil.GetMyParty()
	return latest and latest.myParty or nil
end

-- Pulls the current state from the server into the cache (fires Changed).
function PartyRequestUtil.Refresh()
	local ok, success, payload = pcall(function()
		return PartyRequest:InvokeServer("sync")
	end)
	if ok and success then store(payload) end
	return latest
end

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
