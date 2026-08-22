--[[
	DevRoster
	Single source of truth for who counts as a developer/admin in this game.

	Previously this list was hand-copied into DevService, DayNightService,
	DevClient, and HearthstoneConfig separately. They drifted: DevClient's copy
	was empty (so the F8 panel silently didn't work on a live server for any
	dev), and HearthstoneConfig.ADMIN_IDS only had one of the four IDs. Add or
	remove a dev HERE ONLY; everything else requires this module.

	Note on exposure: this lives in ReplicatedStorage (not ServerStorage)
	because DevClient (a LocalScript) needs to read it client-side to decide
	whether to build its UI at all. That does NOT weaken security — every
	privileged action (placing/deleting zones & spawners, day/night control,
	hearthstone admin actions, item grants) is re-checked server-side against
	this same list independently of whatever the client shows or sends. A
	player who never sees the panel could still fire the remotes directly, and
	they'd be rejected exactly the same way. Client-side checks are UX only.
]]

local RunService = game:GetService("RunService")

local DevRoster = {}

DevRoster.IDS = {
	706604079,
	62963717,
	446429007,
	49263337,
}

-- True for any listed dev, and for anyone in a Studio session (solo or Team
-- Create) so local testing never requires editing this list.
function DevRoster.IsDev(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if table.find(DevRoster.IDS, player.UserId) ~= nil then
		return true
	end
	return RunService:IsStudio()
end

return DevRoster
