-- Server-owned exclusive drinking action, followed by ten independent healing ticks.
-- Three shared charges regenerate sequentially, one every forty seconds.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local ConsumableRequestUtil = require(ReplicatedStorage:WaitForChild("ConsumableRequestUtil"))
local PotionConfig = require(ReplicatedStorage:WaitForChild("PotionConfig"))
local PotionAction = require(ReplicatedStorage:WaitForChild("PotionAction"))
local DrinkFX = require(ReplicatedStorage:WaitForChild("PotionDrinkConfig"))
local PotionAnimations = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("PotionAnimations"))


-- itemId -> total healAmount, visual metadata and displayName. Lives in
-- shared/PotionConfig now (see that file's header) -- charge count/regen no longer live per
-- tier here, see SHARED_CHARGES below.
local POTION_CONFIG = PotionConfig.Tiers
local SHARED_CHARGES = PotionConfig.SharedCharges

-- [userId] = { count = n, nextReadyAt = clockOrNil } -- ONE shared pool per player (2026-09-10),
-- not one per potion tier -- see PotionConfig.SharedCharges header comment.
local chargeState = {}
-- Each heal has its own nextTickAt and remaining tick count.
local activeHeals = {}
local drinking = {}

local gameEventsFolder = ConsumableRequestUtil.EnsureGameEventsFolder()

local DrinkPotionRequest = ConsumableRequestUtil.EnsureRemoteEvent(gameEventsFolder, "DrinkPotionRequest")
local PotionChargesSync = ConsumableRequestUtil.EnsureRemoteEvent(gameEventsFolder, "PotionChargesSync")
local PotionDrunk = ConsumableRequestUtil.EnsureRemoteEvent(gameEventsFolder, "PotionDrunk")
local RequestPotionCharges = ConsumableRequestUtil.EnsureRemoteFunction(gameEventsFolder, "RequestPotionCharges")
-- The quick-drink key (KeybindConfig.QuickDrink, PotionClient): no arguments, the server picks.
local QuickDrinkPotion = ConsumableRequestUtil.EnsureRemoteEvent(gameEventsFolder, "QuickDrinkPotion")
local PotionDrinkRejected = ConsumableRequestUtil.EnsureRemoteEvent(gameEventsFolder, "PotionDrinkRejected")

-- One visual-only vial per model, also available after consuming the last item destroys
-- its Tool. No mesh asset ids in scripts and no replicated moving effect instances.
local visuals = Instance.new("Folder")
visuals.Name = "PotionDrinkVisuals"
local models = game:GetService("ServerStorage"):FindFirstChild("PotionModels")
for _, cfg in pairs(POTION_CONFIG) do
	local model = models and models:FindFirstChild(cfg.visualModel)
	if model and not visuals:FindFirstChild(cfg.visualModel) then
		local copy = model:Clone()
		copy.Name = cfg.visualModel
		for _, part in ipairs(copy:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
			elseif part:IsA("LuaSourceContainer") or part:IsA("JointInstance") or part:IsA("WeldConstraint") then
				part:Destroy()
			end
		end
		copy.Parent = visuals
	end
end
visuals.Parent = ReplicatedStorage

local function getChargeEntry(userId)
	local e = chargeState[userId]
	if not e then
		e = { count = SHARED_CHARGES.maxCharges, nextReadyAt = nil }
		chargeState[userId] = e
	end
	return e
end

local function snapshotCharges(userId)
	local e = chargeState[userId]
	local now = os.clock()
	return {
		count = e and e.count or SHARED_CHARGES.maxCharges,
		maxCharges = SHARED_CHARGES.maxCharges,
		secondsUntilNext = (e and e.nextReadyAt) and math.max(0, e.nextReadyAt - now) or nil,
		nextChargeAt = (e and e.nextReadyAt) and workspace:GetServerTimeNow() + math.max(0, e.nextReadyAt - now) or nil,
	}
end

local function pushCharges(player)
	if not player or not player.Parent then
		return
	end
	PotionChargesSync:FireClient(player, snapshotCharges(player.UserId))
end

RequestPotionCharges.OnServerInvoke = function(player)
	return snapshotCharges(player.UserId)
end

-- Only one drink action at a time. Refusal feedback has its own spam throttle.
local refusalLimiter = ConsumableRequestUtil.NewRateLimiter(0.5)
local nextDrinkId = 0

local function reject(player, reason)
	if refusalLimiter:Check(player.UserId) then
		PotionDrinkRejected:FireClient(player, reason, snapshotCharges(player.UserId))
	end
end

local function notifyNearby(player, origin, payload)
	for _, observer in ipairs(Players:GetPlayers()) do
		local observerRoot = observer.Character and observer.Character:FindFirstChild("HumanoidRootPart")
		if observer == player or (observerRoot and (observerRoot.Position - origin).Magnitude <= DrinkFX.AUDIENCE_RADIUS) then
			PotionDrunk:FireClient(observer, payload)
		end
	end
end

local function updateDrink(uid)
	local action = drinking[uid]
	if not action then return end
	local serverNow = workspace:GetServerTimeNow()
	local player = Players:GetPlayerByUserId(uid)
	local hum = action.character:FindFirstChildOfClass("Humanoid")
	if not player or player.Character ~= action.character or not hum or hum.Health <= 0 then
		action.character:SetAttribute(PotionAction.ATTRIBUTE, nil)
		drinking[uid] = nil
	elseif action.finishAt and serverNow >= action.finishAt then
		action.character:SetAttribute(PotionAction.ATTRIBUTE, nil)
		drinking[uid] = nil
		activeHeals[uid] = activeHeals[uid] or {}
		table.insert(activeHeals[uid], {character = action.character, amount = action.healPerTick,
			nextTickAt = action.finishAt + PotionConfig.HealTickInterval, remaining = PotionConfig.HealTicks})
	end
end

-- Carried = owned and not sitting in the bank (bank slots point into the same inventory).
local function carriedPotionUuid(profile)
	local inventory = profile.inventory
	if type(inventory) ~= "table" then return nil end
	local banked = {}
	if type(profile.chestSlots) == "table" then
		for _, uuid in pairs(profile.chestSlots) do
			if type(uuid) == "string" then banked[uuid] = true end
		end
	end
	-- Strongest first: charges, not potions, are the scarce part.
	for i = #PotionConfig.Order, 1, -1 do
		local itemId = PotionConfig.Order[i]
		for uuid, item in pairs(inventory) do
			if type(item) == "table" and item.itemId == itemId and not banked[uuid] then
				return uuid
			end
		end
	end
	return nil
end

-- One drink for both ways in: holding the potion and right-clicking (quick = false), or the
-- quick-drink key straight from the bag (quick = true, no tool in hand, weapon stays held).
local function drink(player, itemUuid, quick)
	if not player or not player.Parent then return end
	updateDrink(player.UserId)
	if PotionAction.IsLocked(player.Character) or PotionAction.IsCoolingDown(player.Character) or drinking[player.UserId] then return reject(player, "drinking") end
	if type(itemUuid) ~= "string" or itemUuid == "" then return reject(player, "no_potions") end
	local now = os.clock()

	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile then return reject(player, "not_ready") end

	local item = profile.inventory and profile.inventory[itemUuid]
	if type(item) ~= "table" then return reject(player, "no_potions") end

	local itemId = item.itemId
	local cfg = POTION_CONFIG[itemId]
	if not cfg then return reject(player, "no_potions") end

	-- A held drink needs the potion on the hotbar (it was selected to drink); a quick drink
	-- picked a carried stack itself.
	if not quick and not ConsumableRequestUtil.FindHotbarSlotForUuid(profile, itemUuid) then
		return reject(player, "not_held")
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then return reject(player, "not_ready") end
	local tool
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("DungeonItemUuid") == itemUuid then
			tool = child
			break
		end
	end
	local handle = tool and tool:FindFirstChild("Handle")
	local cork = tool and tool:FindFirstChild("Cork")
	if quick then -- Nothing in hand: measure the vial from its template; every client shows a cosmetic
		-- copy in Hand_R for the length of the drink (PotionPresentation, payload.fromBag).
		local template = visuals:FindFirstChild(cfg.visualModel)
		handle = template and template:FindFirstChild("Glass")
		cork = template and template:FindFirstChild("Cork")
	end
	if handle and not handle:IsA("BasePart") then handle = nil end
	-- Missing cosmetic art must never prevent a quick drink from healing.
	if not quick and not handle then return reject(player, "not_held") end

	-- Shared pool: whichever tier is drunk, it draws from the same count (see
	-- PotionConfig.SharedCharges).
	local entry = getChargeEntry(player.UserId)
	if entry.count <= 0 then
		return reject(player, "no_charges")
	end

	-- Snapshot before ConsumeFromStack can remove the last item's tool. Root-relative
	-- coordinates let clients follow a moving drinker even if the tool is gone.
	if cork and not cork:IsA("BasePart") then cork = nil end
	local handleFrame = handle and handle.CFrame or root.CFrame
	local mesh = character:FindFirstChild("Hero_Character")
	local hand = mesh and mesh:FindFirstChild("Hand_R", true)
	if hand and hand:IsA("Bone") then handleFrame = hand.TransformedWorldCFrame * DrinkFX.BONE_GRIP end
	local corkLocal = cork and handle and (cork:GetAttribute("PotionVisualOffset") or handle.CFrame:ToObjectSpace(cork.CFrame))
	local payload = {
		character = character,
		itemUuid = itemUuid,
		itemId = itemId,
		mouthOffset = root.CFrame:ToObjectSpace(handleFrame * CFrame.new(0, handle and handle.Size.Y * 0.5 or 0, 0)),
		corkOffset = corkLocal and root.CFrame:ToObjectSpace(handleFrame * corkLocal) or nil,
		corkSize = cork and cork.Size or nil,
	}
	-- This exact stack: ConsumeItemId takes whichever stack it meets first, banked ones too.
	-- Reserve before inventory notification/equipment reconciliation can yield.
	entry.count -= 1
	local reservation = {character = character}
	drinking[player.UserId] = reservation
	character:SetAttribute(PotionAction.ATTRIBUTE, workspace:GetServerTimeNow() + DrinkFX.ANIMATION_DURATION)
	character:SetAttribute(PotionAction.READY_ATTRIBUTE, workspace:GetServerTimeNow() + DrinkFX.DRINK_COOLDOWN)
	local called, ok = pcall(DungeonProfile.ConsumeFromStack, player, itemUuid, 1)
	if not called or not ok then
		if not called then warn("[PotionService] Inventory consumption failed:", ok) end
		entry.count += 1
		if drinking[player.UserId] == reservation then drinking[player.UserId] = nil end
		character:SetAttribute(PotionAction.ATTRIBUTE, nil)
		character:SetAttribute(PotionAction.READY_ATTRIBUTE, nil) -- nothing was drunk: no cooldown
		return reject(player, "no_potions")
	end

	if entry.nextReadyAt == nil then
		entry.nextReadyAt = now + SHARED_CHARGES.regenInterval
	end
	-- Consumption can notify/reconcile inventory. Never revive an action from an old body.
	if drinking[player.UserId] ~= reservation or player.Character ~= character or humanoid.Health <= 0 then
		character:SetAttribute(PotionAction.ATTRIBUTE, nil)
		if drinking[player.UserId] == reservation then drinking[player.UserId] = nil end
		pushCharges(player)
		return
	end

	nextDrinkId += 1
	payload.drinkId = nextDrinkId
	payload.itemGone = profile.inventory[itemUuid] == nil
	payload.fromBag = quick or nil
	payload.animated = PotionAnimations.T1_POTION_DRINK ~= ""
	payload.sentAt = workspace:GetServerTimeNow()
	payload.finishAt = payload.sentAt + DrinkFX.ANIMATION_DURATION
	character:SetAttribute(PotionAction.ATTRIBUTE, payload.finishAt)
	drinking[player.UserId] = {character = character, finishAt = payload.finishAt,
		healPerTick = cfg.healAmount / PotionConfig.HealTicks}
	local origin = root.Position
	notifyNearby(player, origin, payload)
	pushCharges(player)
end

DrinkPotionRequest.OnServerEvent:Connect(function(player, itemUuid)
	drink(player, itemUuid, false)
end)

QuickDrinkPotion.OnServerEvent:Connect(function(player)
	updateDrink(player.UserId)
	if PotionAction.IsLocked(player.Character) or PotionAction.IsCoolingDown(player.Character) or drinking[player.UserId] then return reject(player, "drinking") end
	if getChargeEntry(player.UserId).count <= 0 then return reject(player, "no_charges") end
	local profile = DungeonProfile.Get(player)
	if not profile then return reject(player, "not_ready") end
	local uuid = profile and carriedPotionUuid(profile)
	if uuid then drink(player, uuid, true) else reject(player, "no_potions") end
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for uid in pairs(drinking) do updateDrink(uid) end
	-- Each completed potion contributes exactly ten ticks. Catch up missed ticks
	-- on a slow frame; retain independent deadlines so overlapping heals stack.
	for uid, list in pairs(activeHeals) do
		local player = Players:GetPlayerByUserId(uid)
		for i = #list, 1, -1 do
			local heal = list[i]
			local hum = heal.character:FindFirstChildOfClass("Humanoid")
			if not player or player.Character ~= heal.character or not hum or hum.Health <= 0 then
				table.remove(list, i)
			else
				while heal.remaining > 0 and serverNow >= heal.nextTickAt do
					hum.Health = math.min(hum.MaxHealth, hum.Health + heal.amount)
					heal.remaining -= 1
					heal.nextTickAt += PotionConfig.HealTickInterval
				end
				if heal.remaining == 0 then table.remove(list, i) end
			end
		end
		if #list == 0 then activeHeals[uid] = nil end
	end

	-- Charge regen (chained single-timer model, see header comment) -- one shared pool per
	-- player now, not one per tier.
	for uid, e in pairs(chargeState) do
		if e.nextReadyAt and now >= e.nextReadyAt then
			e.count = math.min(SHARED_CHARGES.maxCharges, e.count + 1)
			if e.count < SHARED_CHARGES.maxCharges then
				e.nextReadyAt = e.nextReadyAt + SHARED_CHARGES.regenInterval
			else
				e.nextReadyAt = nil
			end
			local player = Players:GetPlayerByUserId(uid)
			if player then
				pushCharges(player)
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	task.defer(function()
		getChargeEntry(player.UserId)
		pushCharges(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	chargeState[player.UserId] = nil
	activeHeals[player.UserId] = nil
	drinking[player.UserId] = nil
	refusalLimiter:Clear(player.UserId)
end)

print("[PotionService] ready")
