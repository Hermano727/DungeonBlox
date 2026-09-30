--[[
	MiasmaCleanseAltar -- one cleansing altar: availability, the 2-second channel, optional cooldown,
	and the altar's own lighting (server-side, so every player sees the same state).

	Rules (docs/miasma-boss-encounter.md, "Cleansing altars"):
		- solo play activates altar 1 only; parties of two or more activate both;
		- no cooldown (Config.Altars.BaseCooldown = 0, 2026-09-30: a cooldown on the only way to
		  shed poison was a bad mechanic). Any value > 0 brings back a per-altar cooldown of
		  BaseCooldown / startingPartySize seconds;
		- a 2-second channel; damage, death, forced movement, leaving range, manual cancel or
		  encounter teardown interrupts it, and an interrupted channel costs no cooldown;
		- success removes every poison stack from that player.

	The ProximityPrompt uses Style = Custom: MiasmaCleanseUI (client) draws the cleanse
	signifier and the channel's camera presentation. Roblox still owns the key/hold input.

	Altar looks (layout geometry `CleanseAltar_<index>`: CleanseWater, RuneRing):
		Dormant   encounter not started / party sealed out: dark still water
		Inactive  not used at this party size: dark, ring unlit
		Ready     bright holy water, ring lit
		Channel   flaring while someone cleanses
		Cooling   dimmed, refilling to Ready over the cooldown
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local Math = require(ReplicatedStorage:WaitForChild("MiasmaEncounterMath"))
local Protocol = require(ReplicatedStorage:WaitForChild("MiasmaEncounterProtocol"))

local Altar = {}
Altar.__index = Altar

Altar.PromptName = "MiasmaCleansePrompt"

local LOOKS = {
	Dormant = { water = Color3.fromRGB(26, 40, 40), light = 0, ring = 1 },
	Inactive = { water = Color3.fromRGB(24, 32, 32), light = 0, ring = 1 },
	Ready = { water = Color3.fromRGB(120, 235, 220), light = 1.1, ring = .45 },
	Channel = { water = Color3.fromRGB(215, 255, 250), light = 2.4, ring = .1 },
	Cooling = { water = Color3.fromRGB(38, 92, 88), light = .25, ring = .85 },
}

local function humanoidAndRoot(player)
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid"), character and character:FindFirstChild("HumanoidRootPart")
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

--[[
	Altar.new({ index, resolver, parent, context })
	context: fire(eventName, payload, player?), isEligible(player), poison (MiasmaPoisonService),
	         startingPartySize
]]
function Altar.new(options)
	local self = setmetatable({}, Altar)
	self.Index = options.index
	self.Context = options.context
	self.Active = self.Index == 1 or self.Context.startingPartySize > 1
	self.Enabled = false
	self.CooldownEndsAt = 0
	self.Channel = nil
	self.Serial = 0

	local resolver = options.resolver
	self.Position = resolver:AltarPosition(self.Index)
	self.Model = resolver:Find("CleanseAltar_" .. self.Index)
	local water = self.Model and self.Model:FindFirstChild("CleanseWater")
	self.Water = water
	self.WaterLight = water and water:FindFirstChildOfClass("PointLight")
	self.Ring = self.Model and self.Model:FindFirstChild("RuneRing")
	self.Focus = water and water.Position or (self.Position + Vector3.new(0, 4.7, 0))
	local toCentre = flat(resolver:Position("ANCHOR_Miasma") - self.Position)
	self.TowardCentre = toCentre.Magnitude > .01 and toCentre.Unit or Vector3.new(0, 0, 1)

	local anchor = Instance.new("Part")
	anchor.Name = "CleanseAltarPrompt" .. self.Index
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = self.Focus + Vector3.new(0, .6, 0)
	anchor.Parent = options.parent
	self.Anchor = anchor
	-- Clients mark every altar while their player is poisoned (client/PoisonIndicators).
	game:GetService("CollectionService"):AddTag(anchor, "MiasmaCleanseAltar")

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Altar.PromptName
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = "Cleanse"
	prompt.ObjectText = "Purification Altar"
	prompt.HoldDuration = Config.Altars.PromptHoldDuration
	prompt.MaxActivationDistance = Config.Altars.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt:SetAttribute("AltarIndex", self.Index)
	prompt.Parent = anchor
	self.Prompt = prompt
	self.TriggerConnection = prompt.Triggered:Connect(function(player) self:Begin(player) end)

	self:_look("Dormant", 0)
	return self
end

function Altar:_look(name, seconds, colorSeconds)
	local look = LOOKS[name]
	if not look then return end
	self.LookName = name
	if self.Water then
		TweenService:Create(self.Water, TweenInfo.new(colorSeconds or seconds or .3, Enum.EasingStyle.Sine), { Color = look.water }):Play()
	end
	if self.WaterLight then
		TweenService:Create(self.WaterLight, TweenInfo.new(seconds or .3), { Brightness = look.light }):Play()
		self.WaterLight.Color = look.water
	end
	if self.Ring then
		TweenService:Create(self.Ring, TweenInfo.new(seconds or .3), { Transparency = look.ring }):Play()
	end
end

function Altar:IsReady()
	return self.Enabled and self.Active and self.Channel == nil and workspace:GetServerTimeNow() >= self.CooldownEndsAt
end

function Altar:_refresh()
	self.Prompt.Enabled = self:IsReady()
	if not self.Active then
		self:_look("Inactive")
	elseif not self.Enabled then
		self:_look("Dormant")
	elseif self.Channel then
		self:_look("Channel", .2)
	elseif workspace:GetServerTimeNow() < self.CooldownEndsAt then
		-- Cooling look is set (and its refill tween started) by the success path.
		if self.LookName ~= "Cooling" then self:_look("Cooling") end
	else
		self:_look("Ready", .6)
	end
end

function Altar:SetEnabled(enabled)
	self.Enabled = enabled == true
	if not self.Enabled and self.Channel then self:_finish(false, "Cancelled") end
	self:_refresh()
end

function Altar:Begin(player)
	local ctx = self.Context
	if not self:IsReady() or not ctx.isEligible(player) then return end
	local humanoid, root = humanoidAndRoot(player)
	if not humanoid or not root or humanoid.Health <= 0 then return end
	if flat(root.Position - self.Position).Magnitude > Config.Altars.InteractionRange then return end

	self.Serial += 1
	local serial = self.Serial
	self.Channel = {
		player = player,
		serial = serial,
		humanoid = humanoid,
		startPosition = root.Position,
		lastHealth = humanoid.Health,
	}
	self:_refresh()
	ctx.fire(Protocol.Events.Presentation, {
		kind = "AltarChannel",
		altar = self.Index,
		duration = Config.Altars.ChannelDuration,
		focus = self.Focus,
		towardCentre = self.TowardCentre,
	}, player)
	task.delay(Config.Altars.ChannelDuration, function()
		if self.Channel and self.Channel.serial == serial then self:_finish(true) end
	end)
end

function Altar:Cancel(player)
	if self.Channel and self.Channel.player == player then self:_finish(false, "Cancelled") end
end

-- Heartbeat check: interrupt the moment the rules are broken, not at the end.
function Altar:Update()
	local channel = self.Channel
	if not channel then return end
	local humanoid, root = humanoidAndRoot(channel.player)
	local reason
	if not channel.player.Parent or humanoid ~= channel.humanoid or not root then
		reason = "Left"
	elseif humanoid.Health <= 0 then
		reason = "Died"
	elseif humanoid.Health < channel.lastHealth
		and self.Context.poison:ExplainDamage(channel.player, channel.lastHealth - humanoid.Health) > .01 then
		-- Poison ticks are expected (they are why you are here); only real hits break the rite.
		reason = "Damaged"
	elseif (root.Position - channel.startPosition).Magnitude > 1.5 then
		reason = "Moved"
	elseif flat(root.Position - self.Position).Magnitude > Config.Altars.InteractionRange then
		reason = "TooFar"
	end
	if reason then
		self:_finish(false, reason)
	else
		channel.lastHealth = humanoid.Health
	end
end

function Altar:_finish(success, reason)
	local channel = self.Channel
	if not channel then return end
	self.Channel = nil
	local ctx = self.Context
	local player = channel.player
	if success then
		local cleared = ctx.poison:Get(player) or 0
		ctx.poison:Clear(player)
		-- Grace period: no new stacks right after the rite (standing still for it shouldn't be
		-- punished by getting re-stacked the moment it ends).
		ctx.poison:GrantImmunity(player, Config.Altars.PostCleanseImmunity or 3)
		local cooldown = (Config.Altars.BaseCooldown or 0) > 0
			and Math.AltarCooldown(ctx.startingPartySize, Config.Altars.BaseCooldown) or 0
		self.CooldownEndsAt = workspace:GetServerTimeNow() + cooldown
		-- Clients show a countdown over the altar (client/PoisonIndicators); none without one.
		if self.Anchor then self.Anchor:SetAttribute("CooldownEndsAt", cooldown > 0 and self.CooldownEndsAt or nil) end
		ctx.fire(Protocol.Events.Presentation, {
			kind = "AltarSuccess",
			altar = self.Index,
			userId = player.UserId,
			cleared = cleared,
			cooldownEndsAt = self.CooldownEndsAt,
			focus = self.Focus,
		})
		-- Flare, drop to the cooled look, then visibly refill over the cooldown. Without a
		-- cooldown: flare, then straight back to Ready.
		self:_look("Channel", .1)
		self.Prompt.Enabled = false
		if cooldown <= 0 then
			local serial = self.Serial
			task.delay(.35, function()
				if self.Serial == serial and self.Channel == nil then self:_refresh() end
			end)
			return
		end
		task.delay(.35, function()
			if self.LookName ~= "Channel" then return end
			self:_look("Cooling", .4, .4)
			task.delay(.45, function()
				if self.LookName == "Cooling" and self.Water then
					TweenService:Create(self.Water, TweenInfo.new(math.max(.1, cooldown - .8), Enum.EasingStyle.Linear), { Color = LOOKS.Ready.water }):Play()
				end
			end)
		end)
		local serial = self.Serial
		task.delay(cooldown, function()
			if self.Serial == serial then self:_refresh() end
		end)
		self.Prompt.Enabled = false
	else
		if player.Parent then
			ctx.fire(Protocol.Events.Presentation, { kind = "AltarInterrupted", altar = self.Index, reason = reason }, player)
		end
		self:_refresh()
	end
end

function Altar:HasChannel(player)
	return self.Channel ~= nil and self.Channel.player == player
end

function Altar:Destroy()
	if self.Channel then self:_finish(false, "Cancelled") end
	if self.TriggerConnection then self.TriggerConnection:Disconnect() end
	if self.Anchor then self.Anchor:Destroy() end
	self:_look("Dormant", 0)
end

return Altar
