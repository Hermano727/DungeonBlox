--[[
	MythicBroadcast -- ServerScriptService

	Every Mythic drop is announced to every player on the server: "<Player> has claimed <Item>",
	drawn by client/MythicBroadcastClient as an ornate top-centre line (Mythic orange, a sting)
	plus a system line in chat.

	ONE entry point for every Mythic source:
		dungeon bosses   DungeonClearSequence, delayed to the moment that player's Judgement
		                 beam flares, so the server hears it in step with the party seeing it
		                 and it never spoils the party's own show
		named elites     NamedEliteLootService, immediately (the drop hits the ground)
		other bosses     LootService.tryDropMythic outside any instance, immediately

	FUTURE (not built): numbered copies ("Miasma, the Devouring Tide #2"). Needs a global
	per-Mythic counter (DataStore UpdateAsync at grant time, saved on the item next to
	ItemIdentity's origin stamp); Announce already takes the item, so it becomes one more field.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteUtils = require(ReplicatedStorage:WaitForChild("RemoteUtils"))

local MythicBroadcast = {}

local remote = RemoteUtils.EnsureRemoteEvent(RemoteUtils.EnsureFolder(ReplicatedStorage, "GameEvents"), "MythicBroadcast")

local function displayName(player)
	return (player.DisplayName ~= "" and player.DisplayName) or player.Name
end

-- `item`: a grant template or owned item (needs .name). `source`: what dropped it, display text.
-- `delaySeconds` (optional): hold the announcement this long. The payload is plain strings, so
-- a delayed one still fires correctly if the player has left by then.
function MythicBroadcast.Announce(player, item, source, delaySeconds)
	if not (player and type(item) == "table") then return end
	local payload = {
		userId = player.UserId,
		playerName = displayName(player),
		itemName = tostring(item.name or "a Mythic"),
		rarity = "Mythic",
		source = source and tostring(source) or nil,
	}
	local function fire()
		remote:FireAllClients(payload)
	end
	if type(delaySeconds) == "number" and delaySeconds > 0 then
		task.delay(delaySeconds, fire)
	else
		fire()
	end
end

return MythicBroadcast
