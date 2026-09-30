local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local Protocol = require(ReplicatedStorage:WaitForChild("MiasmaEncounterProtocol"))
local Math = require(ReplicatedStorage:WaitForChild("MiasmaEncounterMath"))
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))

local Poison = {}
Poison.__index = Poison

function Poison.new(memberUserIds, event, encounterId)
	local members = {}
	for _, userId in ipairs(memberUserIds or {}) do members[userId] = true end
	local self = setmetatable({ Members = members, Event = event, EncounterId = encounterId, Stacks = {}, TickAllowance = {}, ImmuneUntil = {}, Running = true }, Poison)
	task.spawn(function()
		while self.Running do
			task.wait(Config.Poison.TickInterval)
			if not self.Running then break end
			self:Tick()
		end
	end)
	return self
end

function Poison:IsMember(player)
	return player and self.Members[player.UserId] == true
end

function Poison:Get(player)
	return self.Stacks[player.UserId] or 0
end

function Poison:Set(player, stacks)
	if not self:IsMember(player) then return 0 end
	local value = math.clamp(math.floor(tonumber(stacks) or 0), 0, Config.Poison.MaxStacks)
	self.Stacks[player.UserId] = value
	player:SetAttribute(Protocol.Attributes.PoisonStacks, value)
	if self.Event then self.Event:FireClient(player, self.EncounterId, Protocol.Events.PoisonChanged, { stacks = value }) end
	return value
end

function Poison:Add(player, amount)
	amount = tonumber(amount) or 0
	-- A fresh cleanse grants a short window where no NEW stacks land (see GrantImmunity).
	if amount > 0 and player and os.clock() < (self.ImmuneUntil[player.UserId] or 0) then
		return self:Get(player)
	end
	return self:Set(player, self:Get(player) + amount)
end

-- No new poison stacks for `seconds` (removing/clearing stacks still works). Given after a
-- successful altar cleanse, so the player isn't re-poisoned the instant they step off after
-- standing still through the rite.
function Poison:GrantImmunity(player, seconds)
	if not player then return end
	self.ImmuneUntil[player.UserId] = os.clock() + math.max(0, tonumber(seconds) or 0)
end

function Poison:IsImmune(player)
	return player ~= nil and os.clock() < (self.ImmuneUntil[player.UserId] or 0)
end

function Poison:Clear(player)
	return self:Set(player, 0)
end

function Poison:Tick()
	for userId in pairs(self.Members) do
		local player = Players:GetPlayerByUserId(userId)
		local stacks = player and self:Get(player) or 0
		local character = player and player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and stacks > 0 then
			local amount = Math.PoisonTick(humanoid.MaxHealth, stacks, Config.Poison.MaxHealthFractionPerStack, Config.Poison.TickDamageCap)
			-- Recorded BEFORE applying, so channels (altar rite, valve maze) that break on
			-- damage can tell this tick apart from a real hit (see ExplainDamage).
			local allowance = self.TickAllowance[userId]
			self.TickAllowance[userId] = { amount = (allowance and allowance.amount or 0) + amount, at = os.clock() }
			DamageService.ApplyTrueDamageToPlayer(player, amount, { Kind = "MiasmaPoison", EncounterId = self.EncounterId })
		end
	end
end

--[[
	ExplainDamage(player, drop) -> unexplained
	Channels that break on damage call this with a health drop they observed. Health lost to
	a poison tick in the last half second is absorbed (and used up); whatever is left over is
	a real hit. Poison is the reason to cleanse, so it must never break the cleanse itself.
]]
function Poison:ExplainDamage(player, drop)
	local allowance = player and self.TickAllowance[player.UserId]
	if not allowance or os.clock() - allowance.at > .5 then
		if player then self.TickAllowance[player.UserId] = nil end
		return drop
	end
	local absorbed = math.min(drop, allowance.amount)
	allowance.amount -= absorbed
	if allowance.amount <= 1e-3 then self.TickAllowance[player.UserId] = nil end
	return drop - absorbed
end

function Poison:RemoveMember(player)
	if not player then return end
	self:Clear(player)
	self.Members[player.UserId] = nil
	self.Stacks[player.UserId] = nil
end

function Poison:Destroy()
	if not self.Running then return end
	self.Running = false
	for userId in pairs(self.Members) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			player:SetAttribute(Protocol.Attributes.PoisonStacks, nil)
		end
	end
	table.clear(self.Members)
	table.clear(self.Stacks)
end

return Poison
