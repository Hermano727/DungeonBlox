--[[
	StatusCleanseClient  (client twin of SSS/StatusCleanse)

	When the server wipes a player's debuffs (death, leaving or ending a dungeon, the dev
	Cleanse button) it fires GameEvents/StatusCleansed. Every purely client-side effect
	that could otherwise outlive its cause (a screen tint, an open channel UI, a local
	particle) registers a handler here and is torn down on that signal.

	Prefer driving a visual from a replicated attribute instead (it then clears itself when
	the server clears the attribute); register here for whatever can't be.

		local StatusCleanseClient = require(script.Parent:WaitForChild("StatusCleanseClient"))
		StatusCleanseClient.Register("MiasmaTint", function(reason) ... end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatusCleanseClient = {}

local handlers = {} -- [name] = fn(reason)

function StatusCleanseClient.Register(name, fn)
	handlers[name] = fn
end

-- Runs every handler (also usable locally, e.g. when a client-only effect should reset).
function StatusCleanseClient.Run(reason)
	for name, fn in pairs(handlers) do
		local ok, err = pcall(fn, reason)
		if not ok then warn(("[StatusCleanseClient] %s failed: %s"):format(name, tostring(err))) end
	end
end

task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("StatusCleansed")
	remote.OnClientEvent:Connect(function(payload)
		StatusCleanseClient.Run(type(payload) == "table" and payload.reason or "Cleanse")
	end)
end)

return StatusCleanseClient
