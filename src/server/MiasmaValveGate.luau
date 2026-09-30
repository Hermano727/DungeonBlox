--[[
	MiasmaValveGate -- one gate's gameplay: clogs -> read plate -> reserve valve -> maze -> primed.

	Used by BOTH the real encounter (MiasmaEncounterController, four of these) and the
	dev harness (MiasmaValveDevHarness, one), so the dev station exercises the real rules.

	The owner passes a context table:
		encounterId            string sent with every client event
		fire(eventName, payload, player)
		maze                   a MiasmaMazeService shared by the owner's gates
		isEligible(player)     party member / dev check
		canOperate()           e.g. "encounter is in Act2Puzzle"
		spawnClog(position)    -> mob (MobClass) or nil
		onPrimed(gate)
		onProgress(gate, collectedCount)?   optional

	Server authority: the target pattern, reservation, operator validity and completion
	are all decided here and in MiasmaMazeService. The client only renders and reports
	cursor samples.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local Protocol = require(ReplicatedStorage:WaitForChild("MiasmaEncounterProtocol"))
local Station = require(script.Parent:WaitForChild("MiasmaValveStation"))

local VALVE = Config.Gates.Valve
local STATES = Station.States

local Gate = {}
Gate.__index = Gate

local function humanoidAndRoot(player)
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid"), character and character:FindFirstChild("HumanoidRootPart")
end

--[[
	Gate.new({ index, key, displayName, model, context })
	`model` is a built station (MiasmaValveStationBuilder.Build). `key` identifies the gate
	inside the shared maze service (defaults to index).
]]
function Gate.new(options)
	local self = setmetatable({}, Gate)
	self.Index = options.index
	self.Key = options.key or options.index
	self.Context = options.context
	self.Station = Station.new(options.model, { displayName = options.displayName })
	self.Active = false
	self.Primed = false
	self.Clogs = {}
	self.RequiredSymbols = {}
	self.Operator = nil
	self.RevealUntil = 0
	self.Connections = {}
	table.insert(self.Connections, self.Station.Prompt.Triggered:Connect(function(player)
		self:TryReserve(player)
	end))
	return self
end

function Gate:GetPosition()
	return self.Station:GetAnchor("StationCentre")
end

function Gate:GetOperatorSpot()
	return self.Station:GetAnchor("OperatorSpot")
end

function Gate:ClogsRemaining()
	local count = 0
	for _, mob in ipairs(self.Clogs) do
		if mob and mob.IsAlive and mob:IsAlive() then count += 1 end
	end
	return count
end

function Gate:_destroyClogs()
	for _, mob in ipairs(self.Clogs) do
		if mob and mob.Model then
			mob.CurrentHealth = 0
			mob.Model:Destroy()
			mob.Model = nil
		end
	end
	table.clear(self.Clogs)
end

--[[
	Activate(requiredSymbols, clogCount): corrupt the gate for a new cycle. Spawns the clogs
	at the station's Clog1..ClogN anchors and loads the target pattern onto the tablet.
]]
function Gate:Activate(requiredSymbols, clogCount)
	self:Deactivate("CycleReset")
	self.Active = true
	self.Primed = false
	self.RequiredSymbols = table.clone(requiredSymbols)
	self.Station:SetPattern(self.RequiredSymbols)
	for i = 1, clogCount do
		local position = self.Station:GetAnchor("Clog" .. (((i - 1) % 4) + 1))
		local mob = self.Context.spawnClog and self.Context.spawnClog(position + Vector3.new(0, 1.5, 0), self)
		if mob then table.insert(self.Clogs, mob) end
	end
	self.Station:SetState(self:ClogsRemaining() > 0 and STATES.Blocked or STATES.Available)
end

-- Back to dormant: closes the maze for the operator (with `reason`), removes clogs and the
-- pattern. Safe to call repeatedly.
function Gate:Deactivate(reason)
	self:_closeOperator(reason or "CycleReset")
	if self.Context.maze then self.Context.maze:ReleaseGate(self.Key) end
	self:_destroyClogs()
	self.Active = false
	self.Primed = false
	self.RequiredSymbols = {}
	self.RevealUntil = 0
	self.Station:SetRevealed(false)
	self.Station:SetPattern(nil)
	self.Station:SetState(STATES.Dormant)
end

function Gate:_closeOperator(reason)
	local player = self.Operator
	if not player then return end
	self.Operator = nil
	self.OperatorStart = nil
	if self.Context.maze then self.Context.maze:Release(player) end
	if player.Parent then
		self.Context.fire(Protocol.Events.MazeClosed, { reason = reason, gate = self.Index }, player)
	end
	if self.Active and not self.Primed then
		self.Station:SetState(self:ClogsRemaining() > 0 and STATES.Blocked or STATES.Available)
	end
end

function Gate:_fail(player, reason)
	self.Context.fire(Protocol.Events.Presentation, { kind = "ValveDenied", gate = self.Index, reason = reason }, player)
	return false, reason
end

function Gate:TryReserve(player)
	local ctx = self.Context
	if not ctx.isEligible(player) then return false, "NotEligible" end
	if ctx.canOperate and not ctx.canOperate() then return self:_fail(player, "NotNow") end
	if not self.Active or self.Primed then return self:_fail(player, "Inactive") end
	if self:ClogsRemaining() > 0 then return self:_fail(player, "Choked") end
	if self.Operator and self.Operator ~= player then return self:_fail(player, "Reserved") end
	local humanoid, root = humanoidAndRoot(player)
	if not humanoid or not root or humanoid.Health <= 0 then return false, "Dead" end
	local wheel = self.Station:GetAnchor("WheelCentre")
	if (root.Position - wheel).Magnitude > VALVE.MaxOperatorDistance then return self:_fail(player, "TooFar") end

	local payload, reason = ctx.maze:Open(player, self.Key, self.RequiredSymbols)
	if not payload then return self:_fail(player, reason) end
	self.Operator = player
	self.OperatorStart = root.Position
	self.Station:SetState(STATES.Occupied)
	payload.gate = self.Index
	payload.stationName = self.Station.DisplayName
	ctx.fire(Protocol.Events.MazeOpened, payload, player)
	return true
end

-- Cursor batch from the operator.
function Gate:HandleSample(player, payload)
	if player ~= self.Operator then return end
	local result = self.Context.maze:Submit(player, payload)
	if not result then return end
	if result.blob then
		local news = result.blob
		self.Context.fire(Protocol.Events.MazeBlob, { session = result.session, hp = news.hp, popped = news.popped == true }, player)
	end
	if result.kind == "Progress" then
		self.Station:SetProgress(#result.collected)
		self.Context.fire(Protocol.Events.MazeProgress, result, player)
		if self.Context.onProgress then self.Context.onProgress(self, #result.collected) end
	elseif result.kind == "Reset" then
		self.Station:SetProgress(0)
		self.Context.fire(Protocol.Events.MazeReset, result, player)
	elseif result.kind == "Complete" then
		self.Operator = nil
		self.OperatorStart = nil
		self.Context.fire(Protocol.Events.MazeClosed, { reason = "Complete", gate = self.Index, session = result.session }, player)
		self:Prime()
	end
end

function Gate:Prime()
	if not self.Active or self.Primed then return end
	self.Primed = true
	self.Station:SetRevealed(false)
	self.Station:SetState(STATES.Completed)
	if self.Context.onPrimed then self.Context.onPrimed(self) end
end

function Gate:Cancel(player, reason)
	if player ~= self.Operator then return end
	self:_closeOperator(reason or "Cancelled")
end

-- Owner-initiated release (purge, encounter over); leaves the gate's progress alone.
function Gate:ReleaseOperator(reason)
	self:_closeOperator(reason or "Interrupted")
end

function Gate:HasOperator(player)
	return self.Operator ~= nil and self.Operator == player
end

--[[
	Update(livingPlayers): heartbeat work.
		- Blocked -> Available once every clog is dead.
		- Pressure plate: tablet revealed while any eligible living player stands on the
		  plate, and for PlateRevealLinger seconds after the last one steps off.
		- Operator validity: death, damage, displacement, range, leaving -> close + release.
]]
function Gate:Update(livingPlayers)
	if not self.Active then return end
	local now = os.clock()

	if not self.Primed and not self.Operator then
		local wanted = self:ClogsRemaining() > 0 and STATES.Blocked or STATES.Available
		if self.Station.State ~= wanted then self.Station:SetState(wanted) end
	end
	-- The prompt only shows when a reservation could actually succeed right now.
	local operable = not self.Context.canOperate or self.Context.canOperate()
	local promptWanted = operable and self.Station.State == STATES.Available
	if self.Station.Prompt.Enabled ~= promptWanted then self.Station.Prompt.Enabled = promptWanted end

	if not self.Primed then
		for _, player in ipairs(livingPlayers) do
			if player ~= self.Operator then
				local _, root = humanoidAndRoot(player)
				if root and self.Station:IsOnPlate(root.Position) then
					self.RevealUntil = now + VALVE.PlateRevealLinger
					break
				end
			end
		end
		self.Station:SetRevealed(now < self.RevealUntil)
	end

	local operator = self.Operator
	if operator then
		local humanoid, root = humanoidAndRoot(operator)
		local reason
		if not operator.Parent or not self.Context.isEligible(operator) then
			reason = "Left"
		elseif not humanoid or not root or humanoid.Health <= 0 then
			reason = "Died"
		-- Taking hits no longer interrupts (2026-09-29): a strong enough player may simply tank
		-- Miasma while working the valve, and operators are immune to its knockback (the
		-- controller's ShouldSkipKnockback), so only walking off the wheel closes the maze.
		elseif (root.Position - self.Station:GetAnchor("WheelCentre")).Magnitude > VALVE.MaxOperatorDistance then
			reason = "TooFar"
		elseif self.Context.canOperate and not self.Context.canOperate() then
			reason = "CycleReset"
		end
		if reason then
			self:_closeOperator(reason)
		end
	end
end

function Gate:Destroy()
	self:Deactivate("Cleanup")
	for _, connection in ipairs(self.Connections) do connection:Disconnect() end
	table.clear(self.Connections)
	self.Station:Destroy()
end

-- Convenience for owners holding several gates.
function Gate.FindByOperator(gates, player)
	for _, gate in pairs(gates) do
		if gate.Operator == player then return gate end
	end
	return nil
end

return Gate
