--[[
	TutorialCompanion (server, tutorial only)

	A temporary NPC ally for the tutorial's party lesson: a copy of the player's own character
	that joins their party (PartyService.AddCompanion: counts toward the loot boost and shows in
	the Party tab), follows them, and fights the nearest mob, then walks off and disappears.

	Deliberately simple (no pathfinding beyond Humanoid:MoveTo, no abilities). Its hits are
	credited to its owner, so loot and XP land on the player. Everything is refused unless the
	owner's server-side tutorial is active.

		local companion = TutorialCompanion.Spawn(player, spawnCFrame, "Wanderer")
		companion:Leave(walkToPosition)   -- walks there, leaves the party, despawns
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ScriptedRigs = require(ServerScriptService:WaitForChild("ScriptedRigs"))
local PartyService = require(ServerScriptService:WaitForChild("PartyService"))
local CombatAnimConfig = require(ReplicatedStorage:WaitForChild("CombatAnimConfig"))

local THINK_EVERY = 0.2
local FOLLOW_DISTANCE = 6 -- stays about this far from the owner when there's nothing to fight
local AGGRO_RANGE = 28 -- fights mobs within this far of the OWNER
local REACH = 5.5
local SWING_EVERY = 0.9
local HIT_DAMAGE = 6 -- per swing, before the mob's armor

local TutorialCompanion = {}
TutorialCompanion.__index = TutorialCompanion

local function activeMobs()
	local system = rawget(_G, "MobSystem")
	return system and system.GetActiveMobs and system.GetActiveMobs() or {}
end

local function nearestMob(origin, range)
	local best, bestDist
	for _, mob in pairs(activeMobs()) do
		if mob.IsAlive and mob:IsAlive() and mob.GetPosition then
			local pos = mob:GetPosition()
			local dist = typeof(pos) == "Vector3" and (pos - origin).Magnitude or math.huge
			if dist <= range and (not bestDist or dist < bestDist) then
				best, bestDist = mob, dist
			end
		end
	end
	return best
end

-- A plain copy of the player's character: scripts and tools stripped, its own name.
local function cloneCharacter(player, name)
	local character = player.Character
	if not character then return nil end
	local was = character.Archivable
	character.Archivable = true
	local copy = character:Clone()
	character.Archivable = was
	if not copy then return nil end
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("Tool") or d:IsA("ForceField") then d:Destroy() end
	end
	copy.Name = name
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = name
		humanoid.Health = humanoid.MaxHealth
	end
	return copy
end

function TutorialCompanion.Spawn(player, at: CFrame, name: string?)
	if not ScriptedRigs.TutorialActive(player) then return nil end
	name = name or "Wanderer"
	local model = cloneCharacter(player, name)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		if model then model:Destroy() end
		return nil
	end
	model:PivotTo(at)
	model.Parent = workspace
	pcall(function() root:SetNetworkOwner(nil) end) -- the server drives it

	local self = setmetatable({
		owner = player, model = model, humanoid = humanoid, root = root,
		partyId = PartyService.AddCompanion(player, name),
		lastSwing = 0, alive = true,
	}, TutorialCompanion)

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local anim = Instance.new("Animation")
	anim.AnimationId = CombatAnimConfig.SWING_ANIM_ID
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	self.swingTrack = ok and track or nil

	task.spawn(function() self:_think() end)
	return self
end

function TutorialCompanion:_think()
	while self.alive and self.model.Parent and self.owner.Parent do
		local ownerRoot = self.owner.Character and self.owner.Character:FindFirstChild("HumanoidRootPart")
		if not ScriptedRigs.TutorialActive(self.owner) then
			self:Despawn()
			return
		end
		if ownerRoot and not self.leaving then
			local mob = nearestMob(ownerRoot.Position, AGGRO_RANGE)
			if mob then
				local pos = mob:GetPosition()
				local dist = (pos - self.root.Position).Magnitude
				if dist > REACH then
					self.humanoid:MoveTo(pos)
				else
					self.humanoid:MoveTo(self.root.Position)
					self.root.CFrame = CFrame.lookAt(self.root.Position, Vector3.new(pos.X, self.root.Position.Y, pos.Z))
					if os.clock() - self.lastSwing >= SWING_EVERY then
						self.lastSwing = os.clock()
						if self.swingTrack then self.swingTrack:Play() end
						-- Credited to the owner: the kill's loot and XP are theirs.
						pcall(function() mob:TakeDamage(self.owner, HIT_DAMAGE, nil) end)
					end
				end
			elseif (ownerRoot.Position - self.root.Position).Magnitude > FOLLOW_DISTANCE then
				local back = (self.root.Position - ownerRoot.Position)
				back = back.Magnitude > 0.1 and back.Unit or Vector3.new(1, 0, 0)
				self.humanoid:MoveTo(ownerRoot.Position + back * (FOLLOW_DISTANCE - 1))
			end
		end
		task.wait(THINK_EVERY)
	end
	self:Despawn()
end

-- Walks to `position`, leaves the party and disappears.
function TutorialCompanion:Leave(position: Vector3)
	if not self.alive then return end
	self.leaving = true
	if self.partyId then
		PartyService.RemoveCompanion(self.owner, self.partyId)
		self.partyId = nil
	end
	self.humanoid:MoveTo(position)
	task.spawn(function()
		local deadline = os.clock() + 12
		while self.alive and os.clock() < deadline and (self.root.Position - position).Magnitude > 4 do
			task.wait(0.25)
		end
		self:Despawn()
	end)
end

function TutorialCompanion:Despawn()
	if not self.alive then return end
	self.alive = false
	if self.partyId and self.owner.Parent then
		PartyService.RemoveCompanion(self.owner, self.partyId)
		self.partyId = nil
	end
	if self.model then self.model:Destroy() end
end

return TutorialCompanion
