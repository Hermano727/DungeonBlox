local PotionAction = require(game:GetService("ReplicatedStorage"):WaitForChild("PotionAction"))
--[[
	BowService
	Server side of the bow (BowConfig has the numbers): hold to draw, release to shoot.

	  GameEvents/BowDraw      C->S  (no args)      the draw started. The server keeps its own
	                                               clock, so a client can't claim a full charge.
	  GameEvents/BowRelease   C->S  (aimPosition)  loose. Charge = server time since BowDraw.
	  GameEvents/BowShot      S->C  shot payload    every client nearby draws the arrow's flight
	                                               (BowController). The shooter's own client
	                                               already drew its copy on release.

	Arrows fly with gravity on one Heartbeat for every arrow in flight, raycasting each step
	(no parts on the server). A hit goes through MobCombat with the charge's damage multiplier,
	so armor, crits, enchants, PvP gates and range checks are the same as every other weapon.
	A shot costs energy like a swing (EnergyData.trySwing); panting can't draw or shoot.

	The old per-tool BowServer/BowClient scripts were removed from the WoodenBow prefabs
	(2026-10-02); this service and src/client/BowController replace them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local ActiveEquipment = require(ReplicatedStorage:WaitForChild("ActiveEquipment"))
local BowConfig = require(ReplicatedStorage:WaitForChild("BowConfig"))
local ConsumableRequestUtil = require(ReplicatedStorage:WaitForChild("ConsumableRequestUtil"))
local WeaponData = require(ReplicatedStorage:WaitForChild("WeaponData"))
local MobCombat = require(ServerScriptService:WaitForChild("MobCombat"))
local EnergyData = require(ServerScriptService:WaitForChild("EnergyData"))

local gameEvents = ConsumableRequestUtil.EnsureGameEventsFolder()
local BowDraw = ConsumableRequestUtil.EnsureRemoteEvent(gameEvents, "BowDraw")
local BowRelease = ConsumableRequestUtil.EnsureRemoteEvent(gameEvents, "BowRelease")
local BowShot = ConsumableRequestUtil.EnsureRemoteEvent(gameEvents, "BowShot")

-- The arrow template, shared so every client can draw nocked and flying arrows.
do
	local visuals = ReplicatedStorage:FindFirstChild(BowConfig.VISUALS_FOLDER) or Instance.new("Folder")
	visuals.Name = BowConfig.VISUALS_FOLDER
	local models = ServerStorage:FindFirstChild("WeaponModels")
	local source = models and models:FindFirstChild("Bow") and models.Bow:FindFirstChild(BowConfig.ARROW_TEMPLATE)
	if source and not visuals:FindFirstChild(BowConfig.ARROW_TEMPLATE) then
		local arrow = source:Clone()
		arrow.Anchored = true
		arrow.CanCollide, arrow.CanTouch, arrow.CanQuery = false, false, false
		arrow.Parent = visuals
	elseif not source then
		warn("[BowService] ServerStorage.WeaponModels.Bow." .. BowConfig.ARROW_TEMPLATE .. " is missing; arrows will be invisible")
	end
	visuals.Parent = ReplicatedStorage
end

-- [player] = { drawStart = clock?, nextDrawAt = clock }
local states = {}
-- Arrows in flight: { shooter, character, weaponId, scale, position, velocity, traveled, maxDistance, params }
local flying = {}

local function stateFor(player)
	local state = states[player]
	if not state then
		state = { drawStart = nil, nextDrawAt = 0 }
		states[player] = state
	end
	return state
end

local function heldBow(player)
	if PotionAction.IsLocked(player.Character) then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil end
	local tool = ActiveEquipment.GetTool(character)
	if not BowConfig.IsBow(tool) then return nil end
	return tool, character
end

local function getMobUID(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local uid = model:GetAttribute("MobUID")
		if uid then return uid end
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function getHitPlayer(part)
	local model = part:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model)
end

BowDraw.OnServerEvent:Connect(function(player)
	local state = stateFor(player)
	local now = os.clock()
	if now < state.nextDrawAt or not heldBow(player) or EnergyData.isPanting(player) then
		state.drawStart = nil
		return
	end
	state.drawStart = now
end)

BowRelease.OnServerEvent:Connect(function(player, aimPosition)
	local state = stateFor(player)
	local drawStart = state.drawStart
	state.drawStart = nil
	if not drawStart or typeof(aimPosition) ~= "Vector3" or aimPosition ~= aimPosition then return end
	local tool, character = heldBow(player)
	if not tool then return end
	local now = os.clock()
	local charge = math.clamp((now - drawStart) / BowConfig.CHARGE_TIME, 0, 1)
	if charge < BowConfig.MIN_CHARGE then return end
	if not EnergyData.trySwing(player) then return end
	state.nextDrawAt = now + BowConfig.REFIRE_DELAY

	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not head or not root then return end
	local origin = head.Position
	local toAim = aimPosition - origin
	local direction = toAim.Magnitude > 0.5 and toAim.Unit or root.CFrame.LookVector
	-- Leave the head before the first raycast, so the shot can't clip the shooter's own body.
	origin += direction * 1.0

	local weaponId = tool:GetAttribute("WeaponId")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local speed = BowConfig.Speed(charge)
	table.insert(flying, {
		shooter = player, weaponId = weaponId, scale = BowConfig.DamageScale(charge),
		position = origin, velocity = direction * speed, traveled = 0,
		maxDistance = WeaponData.GetStats(weaponId).MaxRange or 100, params = params,
	})

	local shot = {
		shooter = player, origin = origin, velocity = direction * speed, gravity = BowConfig.GRAVITY,
		maxDistance = WeaponData.GetStats(weaponId).MaxRange or 100, sentAt = workspace:GetServerTimeNow(),
	}
	for _, observer in ipairs(Players:GetPlayers()) do
		local observerRoot = observer ~= player and observer.Character and observer.Character:FindFirstChild("HumanoidRootPart")
		if observerRoot and (observerRoot.Position - origin).Magnitude <= BowConfig.AUDIENCE_RADIUS then
			BowShot:FireClient(observer, shot)
		end
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if #flying == 0 then return end
	local gravity = Vector3.new(0, -BowConfig.GRAVITY, 0)
	for i = #flying, 1, -1 do
		local arrow = flying[i]
		local step = arrow.velocity * dt + gravity * (0.5 * dt * dt)
		local remaining = arrow.maxDistance - arrow.traveled
		local done = false
		if step.Magnitude > remaining then
			step = step.Unit * remaining
			done = true
		end
		local result = arrow.shooter.Parent and workspace:Raycast(arrow.position, step, arrow.params)
		if result then
			local mobUID = getMobUID(result.Instance)
			if mobUID then
				MobCombat.ApplyWeaponDamage(arrow.shooter, mobUID, arrow.weaponId, result.Position, arrow.scale)
			else
				local hitPlayer = getHitPlayer(result.Instance)
				if hitPlayer and hitPlayer ~= arrow.shooter then
					-- PvP gates (alignment, zones, range) live in ApplyPvPDamage. A gated hit
					-- still stops the arrow.
					MobCombat.ApplyPvPDamage(arrow.shooter, hitPlayer, arrow.weaponId, result.Position, arrow.scale)
				end
			end
			done = true
		end
		arrow.position += step
		arrow.velocity += gravity * dt
		arrow.traveled += step.Magnitude
		if done or not arrow.shooter.Parent then
			table.remove(flying, i)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

print("[BowService] ready")
