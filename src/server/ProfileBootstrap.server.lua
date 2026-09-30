--[[
  ProfileBootstrap
  - Ensures networking instances exist (code-first so Studio setup is optional).
  - Owns RemoteFunction invoke handlers (thin wrappers; all validation in ProfileService).
  - Loads per-player session profiles and pushes initial snapshots.
]]

local Players             = game:GetService("Players")
local HttpService         = game:GetService("HttpService")
local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function ensureRemoteEvent(name)
	local x = ReplicatedStorage:FindFirstChild(name)
	if x and x:IsA("RemoteEvent") then
		return x
	end
	if x then
		x:Destroy()
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = ReplicatedStorage
	return ev
end

local function ensureRemoteFunction(name)
	local x = ReplicatedStorage:FindFirstChild(name)
	if x and x:IsA("RemoteFunction") then
		return x
	end
	if x then
		x:Destroy()
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = ReplicatedStorage
	return rf
end

ensureRemoteEvent("DungeonProfilePush")
ensureRemoteEvent("DungeonAlignmentRequest")
ensureRemoteEvent("DungeonPvPHit")
ensureRemoteEvent("MiningRewardRequest")
ensureRemoteEvent("MiningDebrisRequest")
ensureRemoteEvent("MiningXPEvent")
ensureRemoteEvent("MiningCoalDrop")
ensureRemoteEvent("MiningCoalCollect")
ensureRemoteFunction("MiningExcavationStart")
ensureRemoteFunction("MiningExcavationDig")
ensureRemoteEvent("MiningExcavationCancel")
ensureRemoteEvent("DamageNumberEvent")
local rfSync = ensureRemoteFunction("DungeonProfileRequestSync")
local rfEquip = ensureRemoteFunction("EquipItem")
local rfUnequip = ensureRemoteFunction("UnequipItem")
local rfInventoryAct = ensureRemoteFunction("DungeonInventoryAct")
local rfBankRequest = ensureRemoteFunction("BankRequest")
local rfBankSync = ensureRemoteFunction("BankSync")

local DungeonProfile      = require(ServerScriptService:WaitForChild("ProfileService"))
local ItemIdentity = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemIdentity"))
local Types               = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local HearthstoneConfig   = require(ReplicatedStorage:WaitForChild("HearthstoneConfig"))
local HearthstoneRegistry = require(ServerScriptService:WaitForChild("HearthstoneRegistry"))
local HearthstoneService  = require(ServerScriptService:WaitForChild("HearthstoneService"))
local ArmorVisualsService = require(ServerScriptService:WaitForChild("ArmorVisualsService"))
local WorldLootService    = require(ServerScriptService:WaitForChild("WorldLootService"))
HearthstoneRegistry.Load()
require(ServerScriptService:WaitForChild("LootService")) -- ensures GameEvents + ItemDropNotify exist early for LootClient
do
	local ge = ReplicatedStorage:WaitForChild("GameEvents", 30)
	if ge and ge:IsA("Folder") then
		local function ensureChildRemoteEvent(name)
			local x = ge:FindFirstChild(name)
			if x and x:IsA("RemoteEvent") then
				return x
			end
			if x then
				x:Destroy()
			end
			local ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = ge
			return ev
		end
		ensureChildRemoteEvent("T1KeyFragment30MilestoneShow")
		local dismiss = ensureChildRemoteEvent("T1KeyFragment30MilestoneDismiss")
		if dismiss:GetAttribute("_MilestoneDismissBound") ~= true then
			dismiss:SetAttribute("_MilestoneDismissBound", true)
			dismiss.OnServerEvent:Connect(function(plr)
				if typeof(plr) ~= "Instance" or not plr:IsA("Player") then
					return
				end
				local ok, err = pcall(function()
					local prof = DungeonProfile.Load(plr)
					if type(prof.flags) ~= "table" then
						prof.flags = {}
					end
					prof.flags.t1KeyFragment30NoticeDismissed = true
					DungeonProfile.PushProfile(plr)
				end)
				if not ok then
					warn("[ProfileBootstrap] T1KeyFragment30MilestoneDismiss failed:", err)
				end
			end)
		end
	end
end
require(ServerScriptService:WaitForChild("MountService")) -- GameEvents.MountRequest + horse mounts
require(ServerScriptService:WaitForChild("ZoneService")) -- zone registry for party boosts + PvP gate
require(ServerScriptService:WaitForChild("PartyService")) -- party invites + same-zone reward boosts
require(ServerScriptService:WaitForChild("DungeonInstanceService")) -- dungeon portal ready-check + realm instances
local BackpackImport = require(ServerScriptService:WaitForChild("BackpackImport"))
local DeathProtection = require(ServerScriptService:WaitForChild("DeathProtection"))
local BankService = require(ServerScriptService:WaitForChild("BankService"))
local EquippedHotbar = require(ServerScriptService:WaitForChild("EquippedHotbar"))
local DeathLootService = require(ServerScriptService:WaitForChild("DeathLootService"))

local COOLDOWN = 0.15
local lastAction = {}

local function throttle(userId)
	local now = os.clock()
	local t = lastAction[userId] or 0
	if now - t < COOLDOWN then
		return false
	end
	lastAction[userId] = now
	return true
end

--[[
  RemoteFunction: EquipItem (client -> server)
    Args: itemUuid: string, equipOpts: optional table (reserved, unused -- weapons are
      not equip-panel items in the Minecraft-style hotbar model)
    Returns: ok: boolean, err: string?
  Security: UUID must exist in server inventory; slot derived server-side only.
]]
rfEquip.OnServerInvoke = function(player, itemUuid, equipOpts)
	if not throttle(player.UserId) then
		return false, "throttled"
	end
	if type(itemUuid) ~= "string" then
		return false, "bad_arg"
	end
	local flags = (type(equipOpts) == "table") and equipOpts or nil
	return DungeonProfile.EquipItem(player, itemUuid, flags)
end

--[[
  RemoteFunction: UnequipItem (client -> server)
    Args: slot: string (Weapon|Armor|Pickaxe|FishingSpear|Potion)
    Returns: ok: boolean, err: string?
]]
rfUnequip.OnServerInvoke = function(player, slot)
	if not throttle(player.UserId) then
		return false, "throttled"
	end
	if type(slot) ~= "string" then
		return false, "bad_arg"
	end
	return DungeonProfile.UnequipItem(player, slot)
end

--[[
  RemoteFunction: DungeonInventoryAct (client -> server)
    Args: { kind = "SetBagSlot", slot = 1..BAG_SLOT_COUNT, uuid = string }
        | { kind = "SwapBagSlot", a = number, b = number }
        | { kind = "ChestDeposit", uuid = string, slot = 1..54 }
        | { kind = "ChestWithdraw", slot = 1..54 }
        | { kind = "ChestUnlockRow", row = 2..6 }
        | { kind = "ApplyEnchantScroll", scrollUuid = string, targetUuid = string }
        | { kind = "ApplyProtectionScroll", scrollUuid = string, targetUuid = string }
        | { kind = "ApplyCraftingOrb", scrollUuid = string, targetUuid = string }
        | { kind = "DropItem", uuid = string }
        | { kind = "TrashItem", uuid = string }
]]
rfInventoryAct.OnServerInvoke = function(player, act)
	if type(act) ~= "table" or type(act.kind) ~= "string" then
		return false, "bad_arg"
	end
	if act.kind ~= "ApplyEnchantScroll" and act.kind ~= "ApplyProtectionScroll" and act.kind ~= "ApplyCraftingOrb" and not throttle(player.UserId) then
		return false, "throttled"
	end
	if act.kind == "SelectActiveTool" then
		return EquippedHotbar.selectActiveSlot(player, DungeonProfile.Get(player), act.slot, act.character)
	elseif act.kind == "SetBagSlot" then
		act.slot = math.floor(tonumber(act.slot) or -1); return DungeonProfile.SetBagSlot(player, act.slot, act.uuid)
	elseif act.kind == "SwapBagSlot" then
		act.a = math.floor(tonumber(act.a) or -1); act.b = math.floor(tonumber(act.b) or -1); return DungeonProfile.SwapBagSlot(player, act.a, act.b)
	elseif act.kind == "ChestDeposit" then
		local ok, err = DungeonProfile.ChestDepositToSlot(player, act.uuid, act.slot)
		if ok then
			-- Second value must be the snapshot (no middle `nil`): RF can collapse nils and shift args.
			return true, DungeonProfile.BuildSnapshotPayload(player)
		end
		return false, err
	elseif act.kind == "ChestWithdraw" then
		local ok, err = DungeonProfile.ChestWithdrawSlot(player, act.slot)
		if ok then
			return true, DungeonProfile.BuildSnapshotPayload(player)
		end
		return false, err
	elseif act.kind == "ChestUnlockRow" then
		local ok, err = DungeonProfile.UnlockChestRow(player, act.row)
		if ok then
			-- Small patch replicates reliably over RF and matches `_seq` from the Push inside Unlock
			-- (avoids an extra BuildSnapshotPayload bump vs. the push snapshot).
			local lp = DungeonProfile.GetLastSnapshotPayload(player)
			if type(lp) == "table" and type(lp.profile) == "table" then
				local prof = lp.profile
				local cur = prof.currencies
				return true, {
					_seq = lp._seq,
					chestUnlockedRows = prof.chestUnlockedRows,
					currencies = {
						Coins = cur and cur.Coins or 0,
					},
				}
			end
			return true, DungeonProfile.BuildSnapshotPayload(player)
		end
		return false, err
	elseif act.kind == "ApplyEnchantScroll" then
		return DungeonProfile.ApplyEnchantScroll(player, act.scrollUuid, act.targetUuid)
	elseif act.kind == "ApplyProtectionScroll" then
		return DungeonProfile.ApplyProtectionScroll(player, act.scrollUuid, act.targetUuid)
	elseif act.kind == "ApplyCraftingOrb" then
		return DungeonProfile.ApplyCraftingOrb(player, act.scrollUuid, act.targetUuid)
	elseif act.kind == "DropItem" then
		local ok, err, removedItem = DungeonProfile.DropItem(player, act.uuid)
		if ok then
			WorldLootService.SpawnPlayerDrop(player, removedItem)
			return true, DungeonProfile.BuildSnapshotPayload(player)
		end
		return false, err
	elseif act.kind == "TrashItem" then
		local ok, err = DungeonProfile.TrashItem(player, act.uuid)
		if ok then
			return true, DungeonProfile.BuildSnapshotPayload(player)
		end
		return false, err
	end
	return false, "unknown_action"
end

--[[
  RemoteFunction: DungeonProfileRequestSync
    Client calls after subscribing (or if it missed the initial push) to force a snapshot.
]]
rfSync.OnServerInvoke = function(player)
	DungeonProfile.Load(player)
	local payload = DungeonProfile.PushProfile(player)
	EquippedHotbar.syncFromProfile(player, DungeonProfile.Get(player))
	return payload
end

--[[
  RemoteEvent: DungeonAlignmentRequest (client -> server)
    Client fires the desired alignment string ("Lawful" / "Neutral" / "Chaotic").
    Server validates input + cooldown via ProfileService.SetAlignment.
    On success, PushProfile fires so the client sees the new state.
]]
local evAlignment = ReplicatedStorage:WaitForChild("DungeonAlignmentRequest")
evAlignment.OnServerEvent:Connect(function(player, requested)
	if not throttle(player.UserId) then return end
	if type(requested) ~= "string" then return end
	DungeonProfile.SetAlignment(player, requested)
end)

--[[
  RemoteEvent: DungeonPvPHit (client -> server)
    Args: targetPlayer: Player, weaponId: string?, hitPos: Vector3?
    Behavior:
      Client reports it hit `targetPlayer` with its currently held weapon.
      Server is fully authoritative: it re-validates alignment (Lawful is
      non-PvP), distance, energy, and weapon, then applies armor-curve damage
      via MobCombat.ApplyPvPDamage. No client-supplied damage values are read.
      Rate is naturally limited by the energy/swing system, so we deliberately
      do NOT use the menu-action throttle here (would cap swings at 6.6/sec
      AND fight with inventory actions).
]]
local evPvP = ReplicatedStorage:WaitForChild("DungeonPvPHit")
local _mobCombatForPvP
local function getMobCombat()
	if not _mobCombatForPvP then
		_mobCombatForPvP = require(ServerScriptService:WaitForChild("MobCombat"))
	end
	return _mobCombatForPvP
end
evPvP.OnServerEvent:Connect(function(attacker, targetPlayer, weaponId, hitPos)
	if typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") then return end
	if attacker == targetPlayer then return end
	if weaponId ~= nil and type(weaponId) ~= "string" then weaponId = nil end
	if hitPos ~= nil and typeof(hitPos) ~= "Vector3" then hitPos = nil end
	getMobCombat().ApplyPvPDamage(attacker, targetPlayer, weaponId, hitPos)
end)

--[[
  RemoteFunction: BankRequest (client -> server)
    Args: { action = "DepositAll"|"Withdraw"|"WithdrawAll", amount?: number }
    Returns: { ok, err?, wallet, inventoryCoins, amount? }
]]
rfBankRequest.OnServerInvoke = function(player, request)
	if not throttle(player.UserId) then
		return { ok = false, err = "throttled", wallet = 0, inventoryCoins = 0 }
	end
	if type(request) ~= "table" or type(request.action) ~= "string" then
		return { ok = false, err = "bad_request", wallet = 0, inventoryCoins = 0 }
	end

	local ok, err, amount
	if request.action == "DepositAll" then
		ok, err, amount = BankService.DepositAll(player)
	elseif request.action == "Withdraw" then
		if type(request.amount) ~= "number" then
			return { ok = false, err = "bad_request", wallet = 0, inventoryCoins = 0 }
		end
		ok, err, amount = BankService.Withdraw(player, request.amount)
	elseif request.action == "WithdrawAll" then
		ok, err, amount = BankService.WithdrawAll(player)
	else
		return { ok = false, err = "unknown_action", wallet = 0, inventoryCoins = 0 }
	end

	local balances = BankService.GetBalances(player)
	return {
		ok = ok,
		err = err,
		amount = amount,
		wallet = balances.wallet,
		inventoryCoins = balances.inventoryCoins,
	}
end

--[[
  RemoteFunction: BankSync (client -> server)
    Returns current wallet + inventory coin balances.
]]
rfBankSync.OnServerInvoke = function(player)
	local balances = BankService.GetBalances(player)
	return { wallet = balances.wallet, inventoryCoins = balances.inventoryCoins }
end

local seedStarterIfEmpty

local function grantAdminTestWeaponIfMissing(player)
	if not RunService:IsStudio()
		and table.find(HearthstoneConfig.ADMIN_IDS, player.UserId) == nil then
		return
	end
	local profile = DungeonProfile.Get(player)
	if not profile or type(profile.inventory) ~= "table" then
		return
	end
	for _, it in pairs(profile.inventory) do
		if type(it) == "table" and it.itemId == "AdminSword" then
			return
		end
	end
	DungeonProfile.GrantItemId(player, "AdminSword", 1, { by = player, kind = ItemIdentity.SOURCE.DEV_TOOL, src = "AdminSword" })
end

local function syncDungeonBackpackAfterCharacter(player)
	if not player or not player.Parent then
		return
	end
	player:WaitForChild("Backpack", 30)
	DungeonProfile.Load(player)
	local profile = DungeonProfile.Get(player)
	if not profile then
		return
	end
	if profile.flags.starterPackImported then
		BackpackImport.stripKnownStarterPackTools(player)
	else
		BackpackImport.ImportPlayerBackpack(player)
	end
	seedStarterIfEmpty(player)
	grantAdminTestWeaponIfMissing(player)
	DungeonProfile.PushProfile(player)
	EquippedHotbar.syncFromProfile(player, DungeonProfile.Get(player))
	-- Motor6D armor welds die with the old character on respawn; profile.equipped
	-- doesn't, so re-apply every worn slot onto the fresh character here.
	ArmorVisualsService.ApplyAllFromProfile(player, DungeonProfile.Get(player))
end

local function refreshDungeonFromBackpack(player)
	syncDungeonBackpackAfterCharacter(player)
end

-- Slot -> Training item catalog id. Every one of these already exists in ItemDefinitions
-- (Training* items, Untradeable, tool ones ProtectedOnDeath), reused as-is via GrantItemId.
local TRAINING_GEAR_FOR_SLOT = {
	Weapon       = "TrainingSword",
	Bow          = "TrainingBow",
	Pickaxe      = "TrainingPickaxe",
	FishingSpear = "TrainingSpear",
	Helm         = "TrainingHelm",
	Chest        = "TrainingChest",
	Legs         = "TrainingLegs",
	Boots        = "TrainingBoots",
	Shield       = "TrainingShield",
}

-- Tops up any EMPTY equip slot every respawn (not just once ever, unlike the old
-- trainingGearSeeded-gated version). Since DeathProtection now protects anything
-- currently equipped, dying never actually clears an equipped slot -- so the only way a
-- slot is empty here is "never equipped anything yet" (first spawn) or "player unequipped
-- it themselves". Either way, hand back a training-tier item so nobody respawns bare.
-- Prefers an already-owned unequipped item of the right kind over minting a duplicate.
function seedStarterIfEmpty(player)
	local profile = DungeonProfile.Load(player)
	if type(profile.equipped) ~= "table" then
		profile.equipped = {}
	end

	for slot, trainingItemId in pairs(TRAINING_GEAR_FOR_SLOT) do
		if profile.equipped[slot] == nil then
			local existingUuid = nil
			for uuid, item in pairs(profile.inventory) do
				if type(item) == "table" and Types.GetAllowedEquipSlot(item) == slot then
					existingUuid = uuid
					break
				end
			end
			if existingUuid then
				DungeonProfile.EquipItem(player, existingUuid)
			else
				local ok = DungeonProfile.GrantItemId(player, trainingItemId, 1, {
					by = player, kind = ItemIdentity.SOURCE.STARTER_SEED, src = trainingItemId,
				})
				if ok then
					profile = DungeonProfile.Load(player)
					for uuid, item in pairs(profile.inventory) do
						if type(item) == "table" and item.itemId == trainingItemId and profile.equipped[slot] ~= uuid then
							DungeonProfile.EquipItem(player, uuid)
							break
						end
					end
				end
			end
			profile = DungeonProfile.Load(player)
		end
	end

	-- Recompute currentHp so a freshly re-geared player starts at full HP
	local newMaxHp = profile.stats.combat.maxHp
	for _, uuid in pairs(profile.equipped) do
		local it = profile.inventory[uuid]
		if it and type(it.subStats) == "table" and type(it.subStats.hp) == "number" then
			newMaxHp = newMaxHp + it.subStats.hp
		end
	end
	profile.runtime.currentHp = newMaxHp
end

local function onPlayerAdded(player)
	DungeonProfile.Load(player)
	player:WaitForChild("Backpack", 60)
	BackpackImport.attachCoalPickupListeners(player)

	local function schedule()
		task.delay(0.22, function()
			if player.Parent then
				syncDungeonBackpackAfterCharacter(player)
			end
		end)
	end

	player.CharacterAdded:Connect(function()
		schedule()
	end)

	if player.Character then
		schedule()
	end
end

local function onPlayerRemoving(player)
	DungeonProfile.SaveProfile(player)
	DungeonProfile.Unload(player)
	lastAction[player.UserId] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

DeathLootService.start()
require(ServerScriptService:WaitForChild("MiningRewardHandler"))
require(ServerScriptService:WaitForChild("CombatStateService")).start()

-- ============================================================
-- Hearthstone RemoteFunctions
-- ============================================================
local rfHSTele     = ensureRemoteFunction("HearthstoneTeleport")
local rfHSSwap     = ensureRemoteFunction("HearthstoneSwap")
local rfHSSync     = ensureRemoteFunction("HearthstoneSync")
local rfHSPurchase = ensureRemoteFunction("HearthstonePurchase")
local rfHSAdmin    = ensureRemoteFunction("HearthstoneAdminAdd")

--[[
  HearthstoneTeleport: teleport player to their active hearthstone (5-min cooldown).
  Returns: ok, cooldownUntil? | ok=false, err, remainingSecs?
]]
rfHSTele.OnServerInvoke = function(player)
	if not throttle(player.UserId) then return false, "throttled" end
	return HearthstoneService.Teleport(player)
end

--[[
  HearthstoneSwap: change the player's active location to one they own.
  Args: locationId: string
]]
rfHSSwap.OnServerInvoke = function(player, locationId)
	if not throttle(player.UserId) then return false, "throttled" end
	if type(locationId) ~= "string" then return false, "bad_arg" end
	return HearthstoneService.SwapLocation(player, locationId)
end

--[[
  HearthstoneSync: return the full location catalog (no throttle, read-only).
  Returns: array of { id, name, cost, px, py, pz }
]]
rfHSSync.OnServerInvoke = function(_player)
	return HearthstoneRegistry.GetAllLocations()
end

--[[
  HearthstonePurchase: buy a location from the Innkeeper (proximity-checked server-side).
  Args: locationId: string
  Returns: ok, newCoinBalance? | ok=false, err
]]
rfHSPurchase.OnServerInvoke = function(player, locationId)
	if not throttle(player.UserId) then return false, "throttled" end
	if type(locationId) ~= "string" then return false, "bad_arg" end
	return HearthstoneService.PurchaseLocation(player, locationId)
end

--[[
  HearthstoneAdminAdd: add a new hearthstone location to the DataStore registry.
  Requires player.UserId in HearthstoneConfig.ADMIN_IDS.
  Args: name, cost, px, py, pz
]]
rfHSAdmin.OnServerInvoke = function(player, name, cost, px, py, pz)
	local isAdmin = RunService:IsStudio()
		or table.find(HearthstoneConfig.ADMIN_IDS, player.UserId) ~= nil
	if not isAdmin then return false, "unauthorized" end
	if type(name) ~= "string" or name == "" then return false, "bad_name" end
	local id = HearthstoneRegistry.SlugId(name)
	return HearthstoneRegistry.AddLocation(
		id,
		name,
		tonumber(cost) or 0,
		Vector3.new(tonumber(px) or 0, tonumber(py) or 4, tonumber(pz) or 0)
	)
end

--[[
  HearthstoneAdminDelete: remove a location from the DataStore registry.
  Seed locations are protected and cannot be deleted.
]]
local rfHSAdminDel = ensureRemoteFunction("HearthstoneAdminDelete")
rfHSAdminDel.OnServerInvoke = function(player, locationId)
	local isAdmin = RunService:IsStudio()
		or table.find(HearthstoneConfig.ADMIN_IDS, player.UserId) ~= nil
	if not isAdmin then return false, "unauthorized" end
	if type(locationId) ~= "string" or locationId == "" then return false, "bad_arg" end
	return HearthstoneRegistry.RemoveLocation(locationId)
end

--[[
  DevGrantItem: grant any item (by itemId) or Coins directly to a player.
  Admin-only (Studio always allowed; live server requires ADMIN_IDS match).
  Special itemIds: "Coins" add directly to profile.currencies.
  Legacy alias: "Scrap" grants T1Scrap stacks (wallet scrap currency removed).
]]
local rfDevGrant = ensureRemoteFunction("DevGrantItem")
rfDevGrant.OnServerInvoke = function(player, itemId, qty)
	local isAdmin = RunService:IsStudio()
		or table.find(HearthstoneConfig.ADMIN_IDS, player.UserId) ~= nil
	if not isAdmin then return false, "unauthorized" end
	if type(itemId) ~= "string" or itemId == "" then return false, "bad_item" end
	qty = math.clamp(math.floor(tonumber(qty) or 1), 1, 9999)
	if itemId == "Coins" then
		local profile = DungeonProfile.Load(player)
		if not profile then return false, "no_profile" end
		profile.currencies.Coins = (profile.currencies.Coins or 0) + qty
		DungeonProfile.PushProfile(player)
		return true
	elseif itemId == "Scrap" then
		return DungeonProfile.GrantItemId(player, "T1Scrap", qty)
	end
	local ok, err = DungeonProfile.GrantItemId(player, itemId, qty)
	return ok, err
end

--[[
  DevProfileAction (F8 Profile tab): admin-only, same gate as DevGrantItem.
    ("setSkill", { branch = "combat"|"mining"|"fishing", level = n })
    ("refillHp") / ("refillEnergy") / ("refillHunger") / ("refillAll")
  Returns ok, err.
]]
local rfDevProfile = ensureRemoteFunction("DevProfileAction")
rfDevProfile.OnServerInvoke = function(player, action, args)
	local isAdmin = RunService:IsStudio()
		or table.find(HearthstoneConfig.ADMIN_IDS, player.UserId) ~= nil
	if not isAdmin then return false, "unauthorized" end
	args = type(args) == "table" and args or {}
	local function refillHp()
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return false, "no_character" end
		humanoid.Health = humanoid.MaxHealth
		return true
	end
	local function refillEnergy()
		local EnergyData = require(ServerScriptService:WaitForChild("EnergyData"))
		return EnergyData.refill(player) and true or false, "no_energy_state"
	end
	local function refillHunger()
		local HungerData = require(ServerScriptService:WaitForChild("HungerData"))
		return HungerData.refill(player) and true or false, "no_hunger_state"
	end
	-- Debuffs: the same full cleanse death and dungeon exits use (SSS/StatusCleanse).
	local function cleanse()
		require(ServerScriptService:WaitForChild("StatusCleanse")).All(player, "Dev")
		return true
	end
	-- Test debuffs: slow + blind + a bleed, and 2 poison stacks (real ones inside an encounter,
	-- display-only outside one).
	local function debuff()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return false, "no_character" end
		local Status = require(ServerScriptService:WaitForChild("CombatEnchantStatus"))
		local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
		Status.Apply(character, { slowness = 100, blinding = 100, bleeding = 100 }, function(rawTick)
			if player.Character ~= character or humanoid.Health <= 0 then return false end
			return DamageService.ApplyToPlayer(player, rawTick, nil, nil, true) > 0
		end, { hitDamage = 40 })
		local inEncounter = false
		pcall(function()
			inEncounter = require(ServerScriptService:WaitForChild("MiasmaEncounterService", 2)).AddPoison(player, 2)
		end)
		if not inEncounter then
			player:SetAttribute("MiasmaPoisonStacks", math.min(5, (tonumber(player:GetAttribute("MiasmaPoisonStacks")) or 0) + 2))
		end
		return true
	end
	if action == "setSkill" then
		return DungeonProfile.DevSetSkillLevel(player, args.branch, args.level)
	elseif action == "cleanse" then
		return cleanse()
	elseif action == "debuff" then
		return debuff()
	elseif action == "refillHp" then
		return refillHp()
	elseif action == "refillEnergy" then
		return refillEnergy()
	elseif action == "refillHunger" then
		return refillHunger()
	elseif action == "refillAll" then
		local okH = refillHp()
		local okE = refillEnergy()
		local okF = refillHunger()
		cleanse()
		return okH and okE and okF, "partial"
	end
	return false, "bad_action"
end

-- Require DungeonRunService at boot purely so its ensureRemotes() runs now.
-- Otherwise the remotes only appear on the first dungeon launch, and any
-- client that started earlier has already given up waiting for them.
do
	local svc = ServerScriptService:FindFirstChild("DungeonRunService")
	if svc then
		local ok, err = pcall(require, svc)
		if not ok then
			warn("[ProfileBootstrap] DungeonRunService preload failed: ", err)
		end
	end
end

print("[ProfileBootstrap] ready")
