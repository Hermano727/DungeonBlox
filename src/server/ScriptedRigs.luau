--[[
	ScriptedRigs (server only)

	One-shot scripted outcomes for the tutorial: a guaranteed crit, a set Orb of Alteration
	result, a set mob drop, a set fish, a set chest reward, a one-time shop price, a set named
	elite drop.

	Security: this is the ONLY way any of those can happen, and it can't be reached from a client.
	  - It lives in ServerScriptService (clients never get the code) and no remote calls it.
	  - Queue() refuses unless the player's SERVER-SIDE profile has an active tutorial
	    (profile.flags.tutorial.done ~= true), and Take() checks that again at the moment of use,
	    so a rig queued in the tutorial can't leak into normal play after it ends.
	  - Values come from server code (TutorialService), never from a remote's arguments.
	  - Each rig is used once; Clear() drops everything (leaving, finishing the tutorial).

	Kinds (and what each consumer expects as the value):
	  crit         true                          DamageService: the next weapon hit crits
	  alteration   { [substatId] = value }       ProfileService.ApplyCraftingOrb: the result of
	                                             the next Alteration (one queued value per use)
	  mobDrop      { itemId = string } or        LootService.onMobDied: the next kill credited to
	               { template = grantTemplate }  this player drops this, and no coins
	  fish         fishId                        SpearFishHandler: the next fish rolled
	  chestReward  { items = { {itemId, count} }, coins = number? }   DropperKeyService
	  price:<itemId>  { price = number, currency = string }          NPCService purchase
	  eliteDrop    { itemId = string, count = number? }               the named elite's kill
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ScriptedRigs = {}

local queues = {} -- [userId] = { [kind] = { value, value, ... } }

local _profiles
-- A queued price is shown in the shop (display only: the server still decides the price), so
-- the front "price:<itemId>" rig is mirrored on the player as RigPrice_<itemId> = "4 T1Scrap".
local PRICE_PREFIX = "price:"
local function mirrorPrice(player: Player, kind: string)
	if kind:sub(1, #PRICE_PREFIX) ~= PRICE_PREFIX then return end
	local itemId = kind:sub(#PRICE_PREFIX + 1)
	local q = queues[player.UserId]
	local front = q and q[kind] and q[kind][1]
	local text = type(front) == "table" and tonumber(front.price) and type(front.currency) == "string"
		and (tostring(math.floor(front.price)) .. " " .. front.currency) or nil
	pcall(player.SetAttribute, player, "RigPrice_" .. itemId, text)
end

local function profiles()
	if not _profiles then _profiles = require(ServerScriptService:WaitForChild("ProfileService")) end
	return _profiles
end

-- Is this player in the tutorial right now? Read from the server's own copy of their profile.
function ScriptedRigs.TutorialActive(player: Player): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
	local ok, profile = pcall(function() return profiles().Get(player) end)
	local tutorial = ok and type(profile) == "table" and type(profile.flags) == "table" and profile.flags.tutorial
	return type(tutorial) == "table" and tutorial.done ~= true
end

-- Queue a scripted outcome. Server code only; refused outside the tutorial.
function ScriptedRigs.Queue(player: Player, kind: string, value: any): boolean
	if type(kind) ~= "string" or value == nil or not ScriptedRigs.TutorialActive(player) then
		return false
	end
	local q = queues[player.UserId]
	if not q then
		q = {}
		queues[player.UserId] = q
	end
	q[kind] = q[kind] or {}
	table.insert(q[kind], value)
	mirrorPrice(player, kind)
	return true
end

-- Use up the next queued outcome of this kind, or nil. Re-checks the tutorial at the moment of use.
function ScriptedRigs.Take(player: Player, kind: string): any
	local q = typeof(player) == "Instance" and queues[player.UserId]
	local list = q and q[kind]
	if not list or #list == 0 then return nil end
	if not ScriptedRigs.TutorialActive(player) then
		ScriptedRigs.Clear(player)
		return nil
	end
	local value = table.remove(list, 1)
	mirrorPrice(player, kind)
	return value
end

-- Look without using it (e.g. to show a price in the shop before buying).
function ScriptedRigs.Peek(player: Player, kind: string): any
	local q = typeof(player) == "Instance" and queues[player.UserId]
	local list = q and q[kind]
	if not list or #list == 0 or not ScriptedRigs.TutorialActive(player) then return nil end
	return list[1]
end

function ScriptedRigs.Clear(player: Player)
	if typeof(player) ~= "Instance" then return end
	local q = queues[player.UserId]
	queues[player.UserId] = nil
	for kind in pairs(q or {}) do mirrorPrice(player, kind) end
end

Players.PlayerRemoving:Connect(ScriptedRigs.Clear)

return ScriptedRigs
