--[[
	MountService
	Authoritative mount spawn/despawn for Mount Saddle tools.
	Clients fire GameEvents.MountRequest with the dungeon item UUID from the equipped tool.
	Clones the Horse model (Workspace "Horse", else ReplicatedStorage/ServerStorage) and applies tier speed via that horse Humanoid.WalkSpeed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local RemoteUtils = require(ReplicatedStorage:WaitForChild("RemoteUtils"))
local MountRiderGuiCleanup = require(ReplicatedStorage:WaitForChild("MountRiderGuiCleanup"))
local ServerStorage = game:GetService("ServerStorage")

local MOUNT_FOLDER_NAME = "DungeonHorseMounts"
local activeMounts = {} -- [userId] = Model
local lastRequest = {} -- [userId] = os.clock()
local riderCleanupRemote -- set at bottom when GameEvents remotes are created
local RATE = 0.25

-- Folder ensuring now lives in shared RemoteUtils (see that module's header).
local function ensureGameEventsFolder()
	return RemoteUtils.EnsureFolder(ReplicatedStorage, "GameEvents")
end

local function getMountFolder()
	return RemoteUtils.EnsureFolder(Workspace, MOUNT_FOLDER_NAME)
end

local function destroyMountForPlayer(player)
	local uid = player.UserId
	local m = activeMounts[uid]

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function()
			hum.Sit = false
		end)
	end

	-- Remove cloned horse ride UI/script before destroying the mount so the ride loop cannot error mid-frame.
	local pg = player:FindFirstChildOfClass("PlayerGui")
	MountRiderGuiCleanup.Clean(pg)

	if m and m.Parent then
		m:Destroy()
	end
	activeMounts[uid] = nil

	char = player.Character
	hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Parent then
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end

	if riderCleanupRemote then
		pcall(function()
			riderCleanupRemote:FireClient(player)
		end)
	end
end

local function getMountSpeed(itemId)
	local def = ItemDefinitions.Get(itemId)
	if not def then
		return nil
	end
	local s = tonumber(def.MountSpeed)
	if not s or s <= 0 then
		return nil
	end
	return s
end

local function findHorseTemplate()
	local h = Workspace:FindFirstChild("Horse")
	if h and h:IsA("Model") then
		return h
	end
	h = Workspace:FindFirstChild("Horse", true)
	if h and h:IsA("Model") then
		return h
	end
	h = ReplicatedStorage:FindFirstChild("Horse")
	if h and h:IsA("Model") then
		return h
	end
	h = ServerStorage:FindFirstChild("Horse")
	if h and h:IsA("Model") then
		return h
	end
	return nil
end

local function cloneHorseModel(player, maxSpeed)
	local template = findHorseTemplate()
	if not template then
		warn("[MountService] Horse template Model not found (Workspace 'Horse', or ReplicatedStorage/ServerStorage 'Horse').")
		return nil, nil
	end

	local mount = template:Clone()
	mount.Name = "HorseMount_" .. tostring(player.UserId)
	mount:SetAttribute("DungeonHorseMount", true)
	mount:SetAttribute("OwnerUserId", player.UserId)
	mount:SetAttribute("MountMaxSpeed", maxSpeed)

	local hum = mount:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = maxSpeed
	end

	local hrp = mount:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		mount.PrimaryPart = hrp
	end

	mount.Parent = getMountFolder()

	local seat = mount:FindFirstChild("Seat")
	if not (seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat"))) then
		seat = mount:FindFirstChildWhichIsA("Seat", true)
		if not seat then
			seat = mount:FindFirstChildWhichIsA("VehicleSeat", true)
		end
	end
	return mount, seat
end

local function trySit(player, seat)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or not seat then
		return false
	end
	local ok = pcall(function()
		seat:Sit(hum)
	end)
	return ok
end

local function findToolByUuid(player, uuid)
	if type(uuid) ~= "string" or uuid == "" then
		return nil
	end
	local function scan(parent)
		if not parent then
			return nil
		end
		for _, c in ipairs(parent:GetChildren()) do
			if c:IsA("Tool") and c:GetAttribute("DungeonItemUuid") == uuid then
				return c
			end
		end
		return nil
	end
	local char = player.Character
	local bp = player:FindFirstChildOfClass("Backpack")
	return scan(char) or scan(bp)
end

-- Sitting often moves the saddle Tool back to Backpack; re-equip so a second click can fire Activated again (dismount).
local function tryReequipSaddle(player, saddleUuid)
	local function attempt()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or not hum.SeatPart then
			return
		end
		local tool = findToolByUuid(player, saddleUuid)
		if not tool then
			return
		end
		if tool.Parent == char then
			return
		end
		pcall(function()
			hum:EquipTool(tool)
		end)
	end
	task.defer(attempt)
	task.delay(0.12, attempt)
	task.delay(0.35, attempt)
end

local function setNetworkOwnerForMount(player, mount)
	for _, d in ipairs(mount:GetDescendants()) do
		if d:IsA("BasePart") then
			pcall(function()
				d:SetNetworkOwner(player)
			end)
		end
	end
end

local function spawnMount(player, maxSpeed, saddleUuid)
	destroyMountForPlayer(player)

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false, "no_character"
	end

	local mount, seat = cloneHorseModel(player, maxSpeed)
	if not mount then
		return false, "no_horse_template"
	end
	if not mount.PrimaryPart then
		warn("[MountService] Cloned Horse has no PrimaryPart; set HumanoidRootPart on the Horse model.")
		mount:Destroy()
		return false, "no_primary_part"
	end
	local spawnCf = hrp.CFrame * CFrame.new(0, -0.5, -7)
	mount:SetPrimaryPartCFrame(spawnCf)
	activeMounts[player.UserId] = mount

	setNetworkOwnerForMount(player, mount)
	task.defer(function()
		if not mount.Parent then
			return
		end
		setNetworkOwnerForMount(player, mount)
		if seat then
			if not trySit(player, seat) then
				warn("[MountService] Failed to seat player on Horse; ensure Seat supports :Sit or adjust rig.")
			else
				tryReequipSaddle(player, saddleUuid)
			end
		elseif type(saddleUuid) == "string" and saddleUuid ~= "" then
			tryReequipSaddle(player, saddleUuid)
		end
	end)

	-- E to remount after dismounting. ControlScript re-clones LocalControlScript
	-- automatically whenever Seat.Occupant changes, so just re-sitting is enough.
	if seat then
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "RemountPrompt"
		pp.ActionText = "Mount"
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.MaxActivationDistance = 8
		pp.RequiresLineOfSight = false
		pp.Parent = seat
		pp.Triggered:Connect(function(trigPlayer)
			if trigPlayer.UserId == player.UserId and not seat.Occupant then
				trySit(trigPlayer, seat)
			end
		end)
	end

	return true
end

local function onMountRequest(player, itemUuid)
	if not player:IsA("Player") then
		return
	end
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return
	end

	-- Dismount on a second saddle use: must run before spawn throttle so rapid double-clicks are not dropped.
	local existing = activeMounts[player.UserId]
	if existing and existing.Parent then
		destroyMountForPlayer(player)
		lastRequest[player.UserId] = 0
		return
	end

	local now = os.clock()
	if (now - (lastRequest[player.UserId] or 0)) < RATE then
		return
	end
	lastRequest[player.UserId] = now

	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile or type(profile.inventory) ~= "table" then
		return
	end
	local item = profile.inventory[itemUuid]
	if type(item) ~= "table" or type(item.itemId) ~= "string" then
		return
	end

	local spd = getMountSpeed(item.itemId)
	if not spd then
		return
	end

	spawnMount(player, spd, itemUuid)
end

local function hookPlayer(player)
	player.CharacterRemoving:Connect(function()
		destroyMountForPlayer(player)
	end)
	player.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			destroyMountForPlayer(player)
		end
	end)
end

local gameEvents = ensureGameEventsFolder()
local mountRequest = RemoteUtils.EnsureRemoteEvent(gameEvents, "MountRequest")
riderCleanupRemote = RemoteUtils.EnsureRemoteEvent(gameEvents, "MountRiderCleanup")

mountRequest.OnServerEvent:Connect(onMountRequest)

Players.PlayerAdded:Connect(hookPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(hookPlayer, p)
end

Players.PlayerRemoving:Connect(function(p)
	destroyMountForPlayer(p)
	lastRequest[p.UserId] = nil
end)

print("[MountService] ready")

local MountService = {}

-- Unseat only (horse stays spawned). Prefer MountService.dismount from combat paths
-- so the mount model is destroyed.
function MountService.unseat(player)
	local uid = player.UserId
	local mount = activeMounts[uid]
	if not mount or not mount.Parent then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		hum.Sit = false
	end
end

-- Full destroy — used on explicit toggle-dismount and character removal.
function MountService.dismount(player)
	destroyMountForPlayer(player)
end

return MountService
