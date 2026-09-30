--[[
	PartyService
	Server-authoritative party invites, membership, and loot-buff system.

	Boost rule: +5% loot (coins) per total party member (incl. self). Requires
	at least 2 members. Capped at MAX_PARTY_SIZE (8). Zone overlap not required.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PartyConfig = require(ReplicatedStorage:WaitForChild("PartyConfig"))
local RemoteUtils = require(ReplicatedStorage:WaitForChild("RemoteUtils"))

local PartyService = {}

-- parties[partyId] = { id, leaderUserId, members = { [userId]=true } }
local parties = {}
local playerParty = {} -- [userId] = partyId
local pendingInvites = {} -- [toUserId] = { fromUserId, fromName, expiresAt }
local lastAction = {}

local _zoneSvc
local function zoneSvc()
	if not _zoneSvc then
		_zoneSvc = require(ServerScriptService:WaitForChild("ZoneService"))
	end
	return _zoneSvc
end

local PartyRequest
local PartyInviteReceived
local PartyStateSync

-- Folder/remote ensuring now lives in shared RemoteUtils (see that module's
-- header) so this is no longer its own copy of the pattern.
local ensureFolder = RemoteUtils.EnsureFolder
local ensureRemoteEvent = RemoteUtils.EnsureRemoteEvent
local ensureRemoteFunction = RemoteUtils.EnsureRemoteFunction

local function throttle(userId)
	local now = os.clock()
	local t = lastAction[userId] or 0
	if now - t < PartyConfig.ACTION_COOLDOWN_SEC then
		return false
	end
	lastAction[userId] = now
	return true
end

local function getParty(partyId)
	return parties[partyId]
end

local function getPlayerPartyId(userId)
	return playerParty[userId]
end

local function getPartyForPlayer(player)
	local pid = getPlayerPartyId(player.UserId)
	if not pid then
		return nil
	end
	return getParty(pid)
end

local function memberCount(party)
	local n = 0
	for _ in pairs(party.members) do
		n += 1
	end
	return n
end

local function allPartyUserIds()
	local out = {}
	for _, party in pairs(parties) do
		for uid in pairs(party.members) do
			out[uid] = true
		end
	end
	return out
end

local function zoneIdSetForPlayer(player)
	local set = {}
	local zones = zoneSvc().GetZonesAtPlayer(player)
	for _, z in ipairs(zones) do
		set[z.id] = true
	end
	return set
end

local function playersShareZone(a, b)
	local za = zoneIdSetForPlayer(a)
	local zb = zoneIdSetForPlayer(b)
	for zid in pairs(za) do
		if zb[zid] then
			return true
		end
	end
	return false
end

local function countSameZonePartyMembers(player, party)
	if not party then
		return 0
	end
	local count = 0
	for uid in pairs(party.members) do
		local other = Players:GetPlayerByUserId(uid)
		if other and other ~= player then
			if playersShareZone(player, other) then
				count += 1
			end
		elseif other == player then
			count += 1
		end
	end
	return count
end

function PartyService.GetSameZoneMemberCount(player)
	local party = getPartyForPlayer(player)
	if not party then
		return 0
	end
	return countSameZonePartyMembers(player, party)
end

-- Returns the UserId of player's party leader, or nil if they aren't in a party.
function PartyService.GetLeaderUserId(player)
	local party = getPartyForPlayer(player)
	if not party then
		return nil
	end
	return party.leaderUserId
end

-- True if player is currently the leader of their own party (false if solo/not in a party).
function PartyService.IsPartyLeader(player)
	local party = getPartyForPlayer(player)
	return party ~= nil and party.leaderUserId == player.UserId
end

function PartyService.GetRewardMultiplier(player)
	local party = getPartyForPlayer(player)
	if not party then return 1 end
	local count = memberCount(party)
	if count < 2 then return 1 end
	return 1 + (PartyConfig.BOOST_PER_MEMBER * count)
end

function PartyService.GetLootBoostPct(player)
	local party = getPartyForPlayer(player)
	if not party then return 0 end
	local count = memberCount(party)
	if count < 2 then return 0 end
	return math.floor(PartyConfig.BOOST_PER_MEMBER * count * 100 + 0.5)
end

local function buildMemberRows(party)
	local rows = {}
	for uid in pairs(party.members) do
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			table.insert(rows, {
				userId = uid,
				name = plr.DisplayName ~= "" and plr.DisplayName or plr.Name,
			})
		end
	end
	table.sort(rows, function(a, b)
		return a.name < b.name
	end)
	return rows
end

-- Returns the array of { userId, name } rows for player's current party (same shape
-- buildMemberRows already produces for the network payload), or nil if they aren't in a
-- party. Exposed for callers outside this module -- e.g. the dungeon system building its
-- ready-check roster with real display names -- instead of reaching into PartyService's
-- private `parties`/`playerParty` tables directly.
function PartyService.GetPartyMembers(player)
	local party = getPartyForPlayer(player)
	if not party then
		return nil
	end
	return buildMemberRows(party)
end

local function buildPayloadFor(player)
	local tagged = {}
	for uid in pairs(allPartyUserIds()) do
		table.insert(tagged, uid)
	end
	table.sort(tagged)

	local party = getPartyForPlayer(player)
	local myParty = nil
	if party then
		myParty = {
			leaderUserId = party.leaderUserId,
			members = buildMemberRows(party),
			lootBoostPct = PartyService.GetLootBoostPct(player),
		}
	end

	return {
		partyUserIds = tagged,
		myParty = myParty,
	}
end

local function broadcastState()
	for _, plr in ipairs(Players:GetPlayers()) do
		PartyStateSync:FireClient(plr, buildPayloadFor(plr))
	end
end

local function disbandParty(partyId)
	local party = parties[partyId]
	if not party then
		return
	end
	for uid in pairs(party.members) do
		playerParty[uid] = nil
	end
	parties[partyId] = nil
end

local function removeFromParty(userId)
	local partyId = playerParty[userId]
	if not partyId then
		return
	end
	local party = parties[partyId]
	if not party then
		playerParty[userId] = nil
		return
	end
	party.members[userId] = nil
	playerParty[userId] = nil

	local remaining = memberCount(party)
	if remaining <= 0 then
		disbandParty(partyId)
		return
	end

	if party.leaderUserId == userId then
		local newLeader
		for uid in pairs(party.members) do
			newLeader = uid
			break
		end
		party.leaderUserId = newLeader
	end
end

local function addToParty(partyId, userId)
	local party = parties[partyId]
	if not party then
		return false, "no_party"
	end
	if memberCount(party) >= PartyConfig.MAX_PARTY_SIZE then
		return false, "party_full"
	end
	if playerParty[userId] then
		return false, "already_in_party"
	end
	party.members[userId] = true
	playerParty[userId] = partyId
	return true
end

local function createParty(leaderUserId)
	local partyId = HttpService:GenerateGUID(false)
	parties[partyId] = {
		id = partyId,
		leaderUserId = leaderUserId,
		members = { [leaderUserId] = true },
	}
	playerParty[leaderUserId] = partyId
	return partyId
end

local function clearInviteFor(userId)
	pendingInvites[userId] = nil
end

local function sweepExpiredInvites()
	local now = os.clock()
	for uid, inv in pairs(pendingInvites) do
		if inv.expiresAt <= now then
			pendingInvites[uid] = nil
		end
	end
end

local function handleInvite(player, targetUserId)
	if type(targetUserId) ~= "number" then
		return false, "bad_target"
	end
	if targetUserId == player.UserId then
		return false, "self_invite"
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then
		return false, "player_gone"
	end
	if playerParty[targetUserId] then
		return false, "target_in_party"
	end

	local inviterParty = getPartyForPlayer(player)
	if inviterParty and memberCount(inviterParty) >= PartyConfig.MAX_PARTY_SIZE then
		return false, "party_full"
	end

	sweepExpiredInvites()
	pendingInvites[targetUserId] = {
		fromUserId = player.UserId,
		fromName = player.DisplayName ~= "" and player.DisplayName or player.Name,
		expiresAt = os.clock() + PartyConfig.INVITE_TIMEOUT_SEC,
	}

	PartyInviteReceived:FireClient(target, {
		inviterUserId = player.UserId,
		inviterName = pendingInvites[targetUserId].fromName,
	})
	return true
end

local function handleAccept(player, inviterUserId)
	if type(inviterUserId) ~= "number" then
		return false, "bad_inviter"
	end
	if playerParty[player.UserId] then
		return false, "already_in_party"
	end

	sweepExpiredInvites()
	local invite = pendingInvites[player.UserId]
	if not invite or invite.fromUserId ~= inviterUserId then
		return false, "no_invite"
	end
	if invite.expiresAt <= os.clock() then
		clearInviteFor(player.UserId)
		return false, "invite_expired"
	end

	local inviter = Players:GetPlayerByUserId(inviterUserId)
	if not inviter then
		clearInviteFor(player.UserId)
		return false, "inviter_gone"
	end

	local partyId = getPlayerPartyId(inviterUserId)
	if not partyId then
		partyId = createParty(inviterUserId)
	end

	local ok, err = addToParty(partyId, player.UserId)
	if not ok then
		return false, err
	end

	clearInviteFor(player.UserId)
	return true
end

local function handleDecline(player, inviterUserId)
	if type(inviterUserId) ~= "number" then
		return false, "bad_inviter"
	end
	local invite = pendingInvites[player.UserId]
	if invite and invite.fromUserId == inviterUserId then
		clearInviteFor(player.UserId)
	end
	return true
end

local function handleCreate(player)
	if playerParty[player.UserId] then
		return false, "already_in_party"
	end
	createParty(player.UserId)
	return true
end

local function handleLeave(player)
	if not playerParty[player.UserId] then
		return false, "not_in_party"
	end
	removeFromParty(player.UserId)
	return true
end

local function onPartyRequest(player, action, arg)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "bad_player"
	end
	if type(action) ~= "string" then
		return false, "bad_action"
	end
	-- Read-only: the caller's current party state (a UI opening needs it now, not at the next
	-- change). Not throttled; it changes nothing.
	if action == "sync" then
		return true, buildPayloadFor(player)
	end
	if not throttle(player.UserId) then
		return false, "throttled"
	end

	local ok, err
	if action == "invite" then
		ok, err = handleInvite(player, arg)
	elseif action == "accept" then
		ok, err = handleAccept(player, arg)
	elseif action == "decline" then
		ok, err = handleDecline(player, arg)
	elseif action == "leave" then
		ok, err = handleLeave(player)
	elseif action == "create" then
		ok, err = handleCreate(player)
	else
		return false, "unknown_action"
	end

	if ok then
		broadcastState()
	end
	return ok, err
end

local function initRemotes()
	local ge = ensureFolder(ReplicatedStorage, "GameEvents")
	PartyInviteReceived = ensureRemoteEvent(ge, "PartyInviteReceived")
	PartyStateSync = ensureRemoteEvent(ge, "PartyStateSync")
	PartyRequest = ensureRemoteFunction(ReplicatedStorage, "PartyRequest")
	PartyRequest.OnServerInvoke = onPartyRequest
end

initRemotes()

Players.PlayerAdded:Connect(function(plr)
	task.defer(function()
		if plr.Parent then
			PartyStateSync:FireClient(plr, buildPayloadFor(plr))
		end
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	local uid = plr.UserId
	lastAction[uid] = nil
	clearInviteFor(uid)
	if playerParty[uid] then
		removeFromParty(uid)
		broadcastState()
	end
end)

for _, plr in ipairs(Players:GetPlayers()) do
	task.defer(function()
		PartyStateSync:FireClient(plr, buildPayloadFor(plr))
	end)
end

print("[PartyService] ready")

return PartyService
