local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local LootDropVisuals = require(
	ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Meshes"):WaitForChild("Loot"):WaitForChild("LootDropVisuals")
)

local DEATH_LOOT_FOLDER = "DeathLootService"
local MOB_LOOT_FOLDER = "DungeonMobLoot"
local LOOT_LIFETIME_SEC = 180 -- death-loot bundles only; mob drops use MOB_LOOT_LIFETIME_SEC below
local PICKUP_RANGE = 6 -- studs from the picking-up player's HumanoidRootPart; "a bit past the
	-- player model" for walk-over auto-pickup. Every pickup check goes through
	-- getPickupRangeForPlayer(player) instead of reading this directly, so a future
	-- per-player upgrade (an item/perk/settings toggle) is a one-function change.
local FLOAT_AMP = 0.28
local FLOAT_FREQ = 1.75
local COIN_AURA_COLOR = Color3.fromRGB(255, 215, 100)

-- Mob-drop physical fall + settle tuning (overworld path only -- see WorldLootService.SpawnMobDrop).
-- Orbs stay Anchored throughout: this is a scripted raycast-to-ground + tween, never real physics,
-- so drops can never be pushed, roll down slopes, or fall through the floor.
local MOB_LOOT_LIFETIME_SEC = 300 -- 5 min TTL, Minecraft-ish despawn timing
local MAX_CONCURRENT_MOB_LOOT = 60 -- oldest-first eviction past this; a full spawner wave adds up fast
local MOB_DROP_SPAWN_LIFT = 3 -- studs above the death position the orb starts its fall from
local MOB_GROUND_CLEARANCE = 0.05 -- gap kept between the orb bottom and the raycast-hit ground
local MOB_GROUND_RAY_UP = 50
local MOB_GROUND_RAY_DOWN = 300
local MOB_FALL_TIME_PER_STUD = 0.05
local MOB_MIN_FALL_TIME = 0.18
local MOB_MAX_FALL_TIME = 0.6
local MOB_BOB_AMP = 0.18 -- unipolar bob once settled -- never dips below the resting position
local MOB_BOB_FREQ = 1.6
local MOB_SPIN_SPEED = 0.8 -- rad/s idle spin once settled (bumped ~33% from 0.6 per request)

local PLAYER_DROP_PICKUP_DELAY = 1.5 -- seconds before ANY player (incl. the thrower) can
	-- pick a player-dropped item back up -- without this, walk-over auto-pickup would
	-- re-grant it to the thrower the instant it lands (Minecraft has the same delay).

local WorldLootService = {}

local activeLoot = {} -- [lootId] = entry

local function getLootFolder(folderName)
	local folder = Workspace:FindFirstChild(folderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = Workspace
	return folder
end

local function ensureItemDropNotify()
	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	if not ge then
		return nil
	end
	local ev = ge:FindFirstChild("ItemDropNotify")
	if ev and ev:IsA("RemoteEvent") then
		return ev
	end
	return nil
end

-- Creates (if needed) the RemoteEvent used to tell a picking-up player's
-- client to play a pickup sound. Unlike ensureItemDropNotify above (which
-- only finds -- LootService.lua owns creating GameEvents + ItemDropNotify),
-- this one also creates on first call: nothing else in the codebase is
-- guaranteed to run before WorldLootService, so it can't assume GameEvents
-- already exists.
local function ensureItemPickupSfxEvent()
	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	if not ge or not ge:IsA("Folder") then
		if ge then
			ge:Destroy()
		end
		ge = Instance.new("Folder")
		ge.Name = "GameEvents"
		ge.Parent = ReplicatedStorage
	end
	local ev = ge:FindFirstChild("ItemPickupSfx")
	if ev and not ev:IsA("RemoteEvent") then
		ev:Destroy()
		ev = nil
	end
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = "ItemPickupSfx"
		ev.Parent = ge
	end
	return ev
end

local ItemPickupSfxEvent = ensureItemPickupSfxEvent()

local function rarityColor(rarity)
	return Types.GetRarityColor(rarity)
end

local function attachAura(anchor, color, applyTint)
	-- applyTint defaults true (every existing call site keeps its exact
	-- behavior); SpawnMobDrop passes false for a drop using a real custom
	-- mesh (see LootDropVisuals) so the aura doesn't flatten its baked
	-- texture -- the light + sparkle particles below still apply either way.
	if applyTint == nil or applyTint then
		anchor.Color = color
	end

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 1.4
	light.Range = 10
	light.Parent = anchor

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "LootAura"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Rate = 16
	pe.Lifetime = NumberRange.new(0.35, 0.8)
	pe.Speed = NumberRange.new(0.2, 1.2)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-90, 90)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 0.85
	pe.Parent = anchor
end

local function attachLabel(anchor, text, textColor)
	local bb = Instance.new("BillboardGui")
	bb.Name = "LootLabel"
	bb.Size = UDim2.fromOffset(120, 36)
	bb.StudsOffset = Vector3.new(0, 1.6, 0)
	bb.AlwaysOnTop = true
	bb.Parent = anchor

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 14
	lbl.TextColor3 = textColor
	lbl.TextStrokeTransparency = 0.35
	lbl.TextWrapped = true
	lbl.Text = text
	lbl.Parent = bb
end

-- "Apparent" colored outline, gated to weapon/armor drops only (coins and
-- other stackable materials never get one -- see SpawnMobDrop's call site).
-- Highlight, not SelectionBox: SelectionBox only draws a boxy bounding-box
-- outline around the part, not the model's actual shape. Highlight traces
-- the real silhouette of whatever mesh it's adorning off the geometry
-- that's already there -- no re-export/Blender edit needed, works the same
-- for the default ball or a real custom mesh (e.g. the chestplate). Its
-- outline isn't adjustable-thickness the way SelectionBox's LineThickness
-- was (Highlight has no such property), but it actually outlines the item
-- instead of boxing it, which is the point. FillTransparency = 1 means no
-- color wash over the model, just the edge.
local function attachOutline(anchor, color)
	local hl = Instance.new("Highlight")
	hl.Name = "LootOutline"
	hl.Adornee = anchor
	hl.FillTransparency = 1
	hl.OutlineColor = color
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = anchor
end

local function scatterOffset(slotIndex)
	local slot = math.max(0, math.floor(tonumber(slotIndex) or 0))
	local angle = slot * 1.35 + (math.random() * 0.6)
	local radius = 1.4 + slot * 0.55
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function startFloat(model, anchor, basePosition)
	local t0 = tick()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not model.Parent or not anchor.Parent then
			if conn then
				conn:Disconnect()
			end
			return
		end
		local bob = math.sin((tick() - t0) * FLOAT_FREQ) * FLOAT_AMP
		anchor.Position = basePosition + Vector3.new(0, bob, 0)
	end)
	return conn
end

-- Resolves a LootDropVisuals entry's PrefabName to the actual ServerStorage
-- instance, or nil if the entry/prefab doesn't exist -- a missing or
-- misconfigured prefab is a silent fallback to the default ball, never an
-- error (see LootDropVisuals's own header comment).
local function findVisualPrefab(prefabName)
	if type(prefabName) ~= "string" or prefabName == "" then
		return nil
	end
	local root = ServerStorage:FindFirstChild("LootDropVisuals")
	if not root then
		return nil
	end
	local prefab = root:FindFirstChild(prefabName)
	if not prefab or not prefab:IsA("BasePart") then
		return nil
	end
	return prefab
end

-- Looks up whether this drop has a registered custom visual, matching it to
-- the SAME identity WorldLootService.SpawnMobDrop already uses per kind.
local function resolveVisualEntry(kind, dropSpec)
	if kind == "coins" then
		return LootDropVisuals.GetForCoins()
	elseif kind == "item_id" then
		return LootDropVisuals.GetForItemId(dropSpec.itemId)
	elseif kind == "item_template" then
		return LootDropVisuals.GetForGearTemplate(dropSpec.template)
	end
	return nil
end

-- Both mob drops and death-loot bundles are "an anchor part, parented under
-- a Model named by lootId, inside a per-kind Workspace folder". Factoring
-- that shared construction out here means the orb's physical flags
-- (collision, anchoring, etc.) only need to be right in one place. Most
-- drops still get the default floating Neon ball; a drop with a resolvable
-- visualEntry (see LootDropVisuals) instead clones that real, pre-scaled
-- mesh from ServerStorage.LootDropVisuals and uses IT as the anchor --
-- everything downstream (aura, label, tooltip attrs, the fall tween, idle
-- spin/bob, walk-over pickup) works on "anchor" as a plain BasePart either way.
local function createLootOrb(folderName, lootId, position, size, visualEntry)
	local lootFolder = getLootFolder(folderName)

	local model = Instance.new("Model")
	model.Name = lootId
	model.Parent = lootFolder

	local prefab = visualEntry and findVisualPrefab(visualEntry.PrefabName)
	local anchor
	if prefab then
		-- Pre-scaled once, by hand, in Studio at import time (MeshPart.MeshId
		-- can't be assigned from a script) -- never resized here, so its
		-- authored proportions survive.
		anchor = prefab:Clone()
		anchor.Name = "Pickup"
	else
		anchor = Instance.new("Part")
		anchor.Name = "Pickup"
		anchor.Size = size
		anchor.Shape = Enum.PartType.Ball
		anchor.Material = Enum.Material.Neon
	end
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = true
	anchor.Position = position
	anchor.Parent = model
	model.PrimaryPart = anchor

	return model, anchor, prefab ~= nil
end

local function cloneTable(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end
	local out = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			out[k] = cloneTable(v)
		else
			out[k] = v
		end
	end
	return out
end

local function ensureWeaponDropToolPrefabOnItem(item)
	if type(item) ~= "table" or item.type ~= "Weapon" then
		return
	end
	if item.toolPrefabName == "WoodenSword" and type(item.tags) == "table" then
		for _, tag in ipairs(item.tags) do
			if tag == "Sword" then
				item.toolPrefabName = "TrainingSword"
				return
			end
		end
	end
	if type(item.toolPrefabName) == "string" and item.toolPrefabName ~= "" then
		return
	end
	if type(item.tags) ~= "table" then
		return
	end
	local map = ItemConfig.WEAPON_DROP_PREFAB_BY_TYPE
	for _, tag in ipairs(item.tags) do
		local n = map[tag]
		if type(n) == "string" and n ~= "" then
			item.toolPrefabName = n
			return
		end
	end
end

local function disconnectLoot(lootId)
	local entry = activeLoot[lootId]
	if not entry then
		return
	end
	if entry.floatConnection then
		entry.floatConnection:Disconnect()
		entry.floatConnection = nil
	end
	if entry.fallTween then
		entry.fallTween:Cancel()
		entry.fallTween = nil
	end
	activeLoot[lootId] = nil
end

-- folderName is optional: every entry now remembers which folder it was
-- spawned into, so callers that forget to pass it (or a future third loot
-- kind that lands in a new folder) still resolve to the right place instead
-- of silently leaving an orphaned model behind. An explicit folderName
-- argument still wins when given, preserving today's call sites exactly.
function WorldLootService.RemoveLoot(lootId, folderName)
	local entry = activeLoot[lootId]
	folderName = folderName or (entry and entry.folderName) or DEATH_LOOT_FOLDER
	local folder = getLootFolder(folderName)
	local model = folder:FindFirstChild(lootId)
	if model then
		model:Destroy()
	end
	disconnectLoot(lootId)
end

local function firePickupBanner(player, payload)
	if not player or not player.Parent or type(payload) ~= "table" then
		return
	end
	local ev = ensureItemDropNotify()
	if ev then
		ev:FireClient(player, payload)
	end
end

-- Fired on EVERY successful pickup, mob-drop or death-loot alike, with no
-- throttling/dedup: picking up several items in quick succession is meant
-- to layer their pickup sounds (see the "satisfying if you pick up many
-- items" ask), not swallow the 2nd/3rd/... one. key names an entry in the
-- shared SoundEffects registry (see src/shared/Assets/Sounds/SoundEffects.luau);
-- the client resolves it to an actual sound via SfxService.
local function firePickupSfx(player, key)
	if not player or not player.Parent then
		return
	end
	if ItemPickupSfxEvent then
		ItemPickupSfxEvent:FireClient(player, key)
	end
end

local INVENTORY_FULL_WARN_COOLDOWN = 10 -- seconds; standing on/near loot you can't hold
	-- would otherwise refire this every Heartbeat via stepAutoPickup.
local lastInventoryFullWarnAt = {} -- [userId] = os.clock()

local function ensureCenterFlashEvent()
	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	local ev = ge and ge:FindFirstChild("CenterFlashNotify")
	if ev and ev:IsA("RemoteEvent") then
		return ev
	end
	return nil
end

local function notifyInventoryFull(player)
	if not player or not player.Parent then
		return
	end
	local now = os.clock()
	local last = lastInventoryFullWarnAt[player.UserId]
	if last and now - last < INVENTORY_FULL_WARN_COOLDOWN then
		return
	end
	lastInventoryFullWarnAt[player.UserId] = now
	local ev = ensureCenterFlashEvent()
	if ev then
		ev:FireClient(player, "Inventory is full!")
	end
end

Players.PlayerRemoving:Connect(function(plr)
	lastInventoryFullWarnAt[plr.UserId] = nil
end)

-- Whether `player` currently has a home for `entry`'s payload -- checked before ever
-- granting it, so a full inventory denies the pickup instead of silently eating the
-- item (see DungeonProfile.HasRoomFor* -- these mirror the same bag/equip-box
-- capacity rules the actual grant will use). Coins are currency, never inventory-
-- space-limited, so they always pass.
local function hasRoomForEntry(player, entry)
	local profile = DungeonProfile.Load(player)
	if not profile then
		return false
	end
	if entry.kind == "coins" then
		return true
	elseif entry.kind == "item_template" then
		return DungeonProfile.HasRoomForItem(profile, entry.template)
	elseif entry.kind == "item_id" then
		if ItemDefinitions.IsStackable(entry.itemId) then
			return DungeonProfile.HasRoomForStackable(profile, entry.itemId, entry.count or 1)
		end
		return DungeonProfile.HasRoomForItemId(profile, entry.itemId)
	elseif entry.kind == "death_bundle" then
		return DungeonProfile.HasRoomForItems(profile, entry.items)
	end
	return true
end

local function grantMobDrop(player, entry)
	if entry.kind == "coins" then
		local granted, err = DungeonProfile.GrantItemId(player, "Coins", entry.amount)
		if granted then
			firePickupBanner(player, {
				kind = "Coins",
				amount = entry.amount,
				coinFind = entry.coinFind,
			})
		end
		return granted, err
	elseif entry.kind == "item_template" then
		local granted, err = DungeonProfile.GrantItem(player, entry.template, 1)
		if granted then
			firePickupBanner(player, {
				name = entry.template.name,
				rarity = entry.template.rarity,
				tier = entry.template.tier,
				type = entry.template.type,
			})
		end
		return granted, err
	elseif entry.kind == "item_id" then
		local granted, err = DungeonProfile.GrantItemId(player, entry.itemId, entry.count or 1)
		if granted then
			-- Clone (never mutate the caller's notifyPayload table) and stamp
			-- count on unconditionally, so the pickup banner shows quantity for
			-- ANY stackable item_id drop without every caller having to
			-- remember to add it themselves.
			local payload = entry.notifyPayload and cloneTable(entry.notifyPayload) or {
				kind = "KeyFragment",
				name = entry.itemId,
			}
			payload.count = entry.count
			firePickupBanner(player, payload)
		end
		return granted, err
	end
	return false, "unknown_drop"
end

-- Extension point for a future pickup-range upgrade (an item, a perk, a
-- settings toggle...): every pickup check calls this instead of reading
-- PICKUP_RANGE directly, so wiring in a per-player bonus later is a
-- one-function change with no call sites to touch.
local function getPickupRangeForPlayer(_player)
	return PICKUP_RANGE
end

local function getCharacterRoot(player)
	local character = player and player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

-- Attempts to grant lootId's entry to player if they're in walk-over range,
-- firing the pickup banner/sound and removing the loot on success. Shared by
-- both mob drops and death-loot bundles -- the only branching is which grant
-- call to make and which folder to remove from.
local function tryPickupFor(lootId, entry, player)
	local root = getCharacterRoot(player)
	if not root then
		return false
	end
	local range = getPickupRangeForPlayer(player)
	if (root.Position - entry.anchor.Position).Magnitude > range then
		return false
	end
	if entry.pickupReadyAt and tick() < entry.pickupReadyAt then
		return false
	end

	if entry.kind == "death_bundle" then
		-- One-liner early exit: don't grant (and don't remove the drop) when the
		-- player has nowhere to put it -- Minecraft-style "inventory full" denial
		-- instead of silently eating the item.
		if not hasRoomForEntry(player, entry) then
			notifyInventoryFull(player)
			return false
		end
		local ok = WorldLootService.GrantLootToPlayer(player, entry.items)
		if not ok then
			return false
		end
		firePickupSfx(player, "ItemPickup")
		WorldLootService.RemoveLoot(lootId, DEATH_LOOT_FOLDER)
		return true
	end

	if entry.ownerUserId and player.UserId ~= entry.ownerUserId then
		return false
	end
	if not hasRoomForEntry(player, entry) then
		notifyInventoryFull(player)
		return false
	end
	local ok = select(1, grantMobDrop(player, entry))
	if not ok then
		return false
	end
	firePickupSfx(player, "ItemPickup")
	WorldLootService.RemoveLoot(lootId, MOB_LOOT_FOLDER)
	return true
end

-- Walk-over auto-pickup: replaces the old ProximityPrompt "E to pick up"
-- entirely. Runs once per Heartbeat over every live drop. Mob-drop entries
-- with an ownerUserId stay owner-scoped exactly like the prompt used to be
-- (only the killing player can trigger their own drop) -- and since only
-- that one player could ever pass the check, we just fetch them directly
-- instead of scanning every player. Death-loot bundles (and, preserving the
-- old prompt's behavior, any mob drop with no ownerUserId) stay unscoped:
-- any nearby player can grab them, first one in range wins.
--
-- Iterating activeLoot while tryPickupFor removes the current key via
-- WorldLootService.RemoveLoot is safe: the Lua reference manual explicitly
-- permits setting an existing key to nil during a pairs() traversal.
local function stepAutoPickup()
	for lootId, entry in pairs(activeLoot) do
		if entry.anchor and entry.anchor.Parent then
			if entry.kind ~= "death_bundle" and entry.ownerUserId then
				local owner = Players:GetPlayerByUserId(entry.ownerUserId)
				if owner then
					tryPickupFor(lootId, entry, owner)
				end
			else
				for _, plr in ipairs(Players:GetPlayers()) do
					if tryPickupFor(lootId, entry, plr) then
						break
					end
				end
			end
		end
	end
end

RunService.Heartbeat:Connect(stepAutoPickup)

-- Raycast straight down to find the ground under a mob-drop orb, same
-- Exclude-filter convention as MobGroundUtils. Excludes both loot folders
-- so a falling/resting orb never raycasts against another pickup orb.
local function resolveMobLootGroundY(x, z, fallbackY)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {
		getLootFolder(MOB_LOOT_FOLDER),
		getLootFolder(DEATH_LOOT_FOLDER),
	}

	local hit = Workspace:Raycast(
		Vector3.new(x, fallbackY + MOB_GROUND_RAY_UP, z),
		Vector3.new(0, -MOB_GROUND_RAY_DOWN, 0),
		rayParams
	)
	if hit then
		return hit.Position.Y
	end
	return fallbackY -- void/no-hit safety net -- never let a missed raycast strand the orb
end

-- Idle spin + slight bob once a drop has settled on the ground. Bob is
-- unipolar (0..MOB_BOB_AMP) so the orb only ever lifts off its resting
-- point, never dips back below the ground it just landed on.
local function startIdleSettle(model, anchor, restPosition)
	local t0 = tick()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not model.Parent or not anchor.Parent then
			if conn then
				conn:Disconnect()
			end
			return
		end
		local dt = tick() - t0
		local bob = MOB_BOB_AMP * (1 + math.sin(dt * MOB_BOB_FREQ)) / 2
		local spin = dt * MOB_SPIN_SPEED
		anchor.CFrame = CFrame.new(restPosition + Vector3.new(0, bob, 0)) * CFrame.Angles(0, spin, 0)
	end)
	return conn
end

-- Scripted fall: tween the (still Anchored) orb from its spawn height down
-- to the raycast-resolved ground position. Bounce/Out gives the drop a
-- couple of decaying little bounces before it comes to rest exactly on
-- restPosition -- no physics, no velocity, nothing pushable. Idle spin/bob
-- only starts once the tween actually completes (not cancelled early by a
-- pickup or a cap eviction), guarded by re-checking activeLoot[lootId].
local function dropAndSettle(lootId, model, anchor, restPosition)
	local dropHeight = math.max(0, anchor.Position.Y - restPosition.Y)
	local duration = math.clamp(dropHeight * MOB_FALL_TIME_PER_STUD, MOB_MIN_FALL_TIME, MOB_MAX_FALL_TIME)
	local tween = TweenService:Create(
		anchor,
		TweenInfo.new(duration, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
		{ Position = restPosition }
	)
	tween.Completed:Connect(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed then
			return -- cancelled (picked up / evicted) mid-fall -- don't start idle settle
		end
		local entry = activeLoot[lootId]
		if not entry or not model.Parent or not anchor.Parent then
			return
		end
		entry.fallTween = nil
		entry.floatConnection = startIdleSettle(model, anchor, restPosition)
	end)
	tween:Play()
	return tween
end

local mobLootSeq = 0

-- Cap concurrent mob-drop orbs, evicting the single oldest survivor whenever
-- the count is over budget. Looping (not a one-shot if) means a burst that
-- pushes the count several past the cap in one go (e.g. a multi-drop kill)
-- still converges back to the cap within this one call.
local function enforceMobLootCap()
	while true do
		local count, oldestId, oldestSeq = 0, nil, nil
		for id, entry in pairs(activeLoot) do
			if entry.folderName == MOB_LOOT_FOLDER then
				count = count + 1
				if not oldestSeq or (entry.spawnSeq and entry.spawnSeq < oldestSeq) then
					oldestSeq = entry.spawnSeq
					oldestId = id
				end
			end
		end
		if count <= MAX_CONCURRENT_MOB_LOOT or not oldestId then
			break
		end
		WorldLootService.RemoveLoot(oldestId, MOB_LOOT_FOLDER)
	end
end

function WorldLootService.SpawnMobDrop(originPosition, ownerUserId, dropSpec, scatterIndex)
	if typeof(originPosition) ~= "Vector3" or type(dropSpec) ~= "table" then
		return nil
	end

	local kind = dropSpec.kind
	if kind ~= "coins" and kind ~= "item_template" and kind ~= "item_id" then
		return nil
	end

	local auraColor = COIN_AURA_COLOR
	local orbSize = Vector3.new(1.6, 1.6, 1.6)

	if kind == "coins" then
		local amount = math.max(1, math.floor(tonumber(dropSpec.amount) or 0))
		dropSpec.amount = amount
	elseif kind == "item_template" then
		local template = dropSpec.template
		if type(template) ~= "table" then
			return nil
		end
		ensureWeaponDropToolPrefabOnItem(template)
		auraColor = rarityColor(template.rarity)
		orbSize = Vector3.new(1.8, 1.8, 1.8)
	elseif kind == "item_id" then
		local itemId = dropSpec.itemId
		local def = type(itemId) == "string" and ItemDefinitions.Get(itemId) or nil
		if not def then
			return nil
		end
		dropSpec.count = math.max(1, math.floor(tonumber(dropSpec.count) or 1))
		auraColor = rarityColor(def.Rarity or "Common")
	end

	local lootId = "MobLoot_" .. HttpService:GenerateGUID(false)
	local scatterVec = scatterOffset(scatterIndex)
	local groundXZOrigin = originPosition + scatterVec
	local spawnPosition = groundXZOrigin + Vector3.new(0, MOB_DROP_SPAWN_LIFT, 0)
	local groundY = resolveMobLootGroundY(groundXZOrigin.X, groundXZOrigin.Z, originPosition.Y)

	local visualEntry = resolveVisualEntry(kind, dropSpec)
	local model, anchor, usingCustomVisual = createLootOrb(MOB_LOOT_FOLDER, lootId, spawnPosition, orbSize, visualEntry)
	-- Ground clearance uses the ANCHOR's real size, not the nominal orbSize --
	-- a custom mesh's authored proportions (a thin coin, not a cube) rarely
	-- match the default ball's size, so resting height must read it back off
	-- whatever actually got created.
	local restPosition = Vector3.new(groundXZOrigin.X, groundY + (anchor.Size.Y / 2) + MOB_GROUND_CLEARANCE, groundXZOrigin.Z)

	attachAura(anchor, auraColor, not usingCustomVisual)
	-- No floating name/quantity label above drops anymore -- the pickup
	-- banner already names the item, and the outline below (weapon/armor
	-- only) plus the aura color carry rarity at a glance without text.
	if kind == "item_template" then
		attachOutline(anchor, auraColor)
	end

	mobLootSeq = mobLootSeq + 1
	local entry = {
		kind = kind,
		folderName = MOB_LOOT_FOLDER,
		ownerUserId = ownerUserId,
		anchor = anchor,
		amount = dropSpec.amount,
		coinFind = dropSpec.coinFind,
		template = dropSpec.template,
		itemId = dropSpec.itemId,
		count = dropSpec.count,
		notifyPayload = dropSpec.notifyPayload,
		spawnSeq = mobLootSeq,
	}
	if type(dropSpec.pickupDelay) == "number" and dropSpec.pickupDelay > 0 then
		-- Player-thrown drops (see SpawnPlayerDrop) land at the thrower's own feet --
		-- without this, walk-over auto-pickup would grab it back the very next
		-- Heartbeat. Ordinary mob drops never set this, so they keep instant pickup.
		entry.pickupReadyAt = tick() + dropSpec.pickupDelay
	end
	activeLoot[lootId] = entry
	entry.fallTween = dropAndSettle(lootId, model, anchor, restPosition)

	enforceMobLootCap()

	task.delay(MOB_LOOT_LIFETIME_SEC, function()
		WorldLootService.RemoveLoot(lootId, MOB_LOOT_FOLDER)
	end)

	return lootId
end

-- Player-initiated drop (see ProfileService.DropItem / the "TrashItem"-adjacent
-- DropItem action in ProfileBootstrap.server.lua): spawns the item on the ground at
-- the dropping player's feet using the exact same orb/fall/settle/aura visuals as a
-- mob drop, so other players see it exactly like a mob's loot. Unowned (ownerUserId =
-- nil) so any nearby player -- not just the thrower -- can pick it up, same rule
-- death-loot bundles already use.
function WorldLootService.SpawnPlayerDrop(player, item)
	if type(item) ~= "table" then
		return nil
	end
	local root = getCharacterRoot(player)
	if not root then
		return nil
	end

	local dropSpec
	if type(item.itemId) == "string" and item.itemId ~= "" and ItemDefinitions.IsStackable(item.itemId) then
		-- Stackable items (materials, potions, currency, ...) round-trip through
		-- GrantItemId on pickup so the dropped count survives. kind="item_template"
		-- would silently reset it to 1 -- GrantItem always mints fresh single units
		-- and never reads template.count.
		dropSpec = {
			kind = "item_id",
			itemId = item.itemId,
			count = math.max(1, math.floor(tonumber(item.count) or 1)),
			pickupDelay = PLAYER_DROP_PICKUP_DELAY,
		}
	else
		local template = cloneTable(item)
		template.uuid = nil -- a fresh uuid is minted on pickup (GrantItem); never reuse the dropped one
		dropSpec = {
			kind = "item_template",
			template = template,
			pickupDelay = PLAYER_DROP_PICKUP_DELAY,
		}
	end

	return WorldLootService.SpawnMobDrop(root.Position, nil, dropSpec, 0)
end

function WorldLootService.GrantLootToPlayer(player, items)
	if not player or not player.Parent then
		return false, "bad_player"
	end
	if type(items) ~= "table" or #items <= 0 then
		return false, "no_items"
	end

	local profile = DungeonProfile.Load(player)
	if not profile then
		return false, "no_profile"
	end

	for _, item in ipairs(items) do
		if type(item) == "table" then
			local newItem = cloneTable(item)
			local newUuid = HttpService:GenerateGUID(false)
			newItem.uuid = newUuid
			profile.inventory[newUuid] = newItem
			DungeonProfile.PlaceItemInFirstEmptySlot(profile, newUuid, player)
		end
	end

	DungeonProfile.PushProfile(player)
	return true, nil
end

function WorldLootService.SpawnDeathLoot(originPosition, droppedItems)
	if type(droppedItems) ~= "table" or #droppedItems <= 0 then
		return nil
	end
	for _, it in ipairs(droppedItems) do
		ensureWeaponDropToolPrefabOnItem(it)
	end
	if typeof(originPosition) ~= "Vector3" then
		originPosition = Vector3.new(0, 8, 0)
	end

	local lootId = "DeathLoot_" .. HttpService:GenerateGUID(false)
	local basePosition = originPosition + Vector3.new((math.random() - 0.5) * 4, 1.5, (math.random() - 0.5) * 4)
	local model, anchor = createLootOrb(DEATH_LOOT_FOLDER, lootId, basePosition, Vector3.new(2, 2, 2))

	attachAura(anchor, Color3.fromRGB(245, 186, 72))
	attachLabel(anchor, "Dropped Loot", Color3.fromRGB(245, 186, 72))

	activeLoot[lootId] = {
		kind = "death_bundle",
		folderName = DEATH_LOOT_FOLDER,
		anchor = anchor,
		items = droppedItems,
		floatConnection = startFloat(model, anchor, basePosition),
	}

	task.delay(LOOT_LIFETIME_SEC, function()
		WorldLootService.RemoveLoot(lootId, DEATH_LOOT_FOLDER)
	end)

	return lootId
end

return WorldLootService
