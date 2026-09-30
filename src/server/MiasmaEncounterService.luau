local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteUtils = require(ReplicatedStorage:WaitForChild("RemoteUtils"))
local Protocol = require(ReplicatedStorage:WaitForChild("MiasmaEncounterProtocol"))
local Controller = require(ServerScriptService:WaitForChild("MiasmaEncounterController"))

local gameEvents = RemoteUtils.EnsureFolder(ReplicatedStorage, "GameEvents")
local encounterEvent = RemoteUtils.EnsureRemoteEvent(gameEvents, "MiasmaEncounterEvent")
local encounterRequest = RemoteUtils.EnsureRemoteEvent(gameEvents, "MiasmaEncounterRequest")

local Service = {}
local controllers = {}
local playerToController = {}

function Service.Start(options)
	if not options or not options.instanceId or not options.realm then return nil end
	if controllers[options.instanceId] then return controllers[options.instanceId] end
	local controller
	controller = Controller.new({
		instanceId = options.instanceId,
		realm = options.realm,
		memberUserIds = options.memberUserIds,
		spawnerHandle = options.spawnerHandle,
		runLevel = options.runLevel,
		event = encounterEvent,
		onFinished = options.onFinished,
	})
	controllers[options.instanceId] = controller
	for _, userId in ipairs(options.memberUserIds or {}) do playerToController[userId] = controller end
	controller:Start()
	return controller
end

function Service.RemovePlayer(player)
	local controller = player and playerToController[player.UserId]
	if not controller then return end
	playerToController[player.UserId] = nil
	controller:RemovePlayer(player)
end

-- A member died during the fight: wipe their poison and drop them from any valve they held.
-- They stay a member (they spectate); the controller's living-player checks skip them.
function Service.OnPlayerDied(player)
	local controller = player and playerToController[player.UserId]
	if controller and controller.OnMemberDied then controller:OnMemberDied(player) end
end

-- Poison only (no valve release): the dev cleanse. Returns true if the player is in an encounter.
function Service.Cleanse(player)
	local controller = player and playerToController[player.UserId]
	if controller and controller.Poison then controller.Poison:Clear(player) return true end
	return false
end

-- Dev debuff: add poison stacks (only meaningful inside an encounter).
function Service.AddPoison(player, stacks)
	local controller = player and playerToController[player.UserId]
	if controller and controller.Poison then controller.Poison:Add(player, stacks) return true end
	return false
end

function Service.Destroy(instanceId)
	local controller = controllers[instanceId]
	if not controller then return false end
	for userId, mapped in pairs(playerToController) do if mapped == controller then playerToController[userId] = nil end end
	controllers[instanceId] = nil
	controller:Destroy()
	return true
end

function Service.Get(instanceId) return controllers[instanceId] end

-- Non-encounter request handlers (the dev valve station) share the same remotes and routing.
-- `handler` needs HandleRequest(player, request, payload).
function Service.RegisterExternal(id, handler)
	controllers[id] = handler
end

function Service.UnregisterExternal(id)
	local handler = controllers[id]
	controllers[id] = nil
	for userId, mapped in pairs(playerToController) do
		if mapped == handler then playerToController[userId] = nil end
	end
end

-- Routes `player`'s requests to `handler`. Never steals a player from a live encounter.
function Service.BindPlayer(player, handler)
	local current = playerToController[player.UserId]
	if current and current ~= handler then return false end
	playerToController[player.UserId] = handler
	return true
end

function Service.UnbindPlayer(player, handler)
	if playerToController[player.UserId] == handler then playerToController[player.UserId] = nil end
end

function Service.GetEvent() return encounterEvent end

encounterRequest.OnServerEvent:Connect(function(player, encounterId, request, payload)
	if type(encounterId) ~= "string" or type(request) ~= "string" then return end
	local controller = controllers[encounterId]
	if controller and playerToController[player.UserId] == controller then controller:HandleRequest(player, request, payload) end
end)

return Service
