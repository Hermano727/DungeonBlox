--[[
	AltarService
	Bootstraps altar world models (ProximityPrompt) and handles AltarRequest upgrades.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))

local ALTAR_MAX_DISTANCE = 18

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

local rfAltarRequest = ensureRemoteFunction("AltarRequest")

local function getModelPivot(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	local ok, pivot = pcall(function()
		return model:GetPivot()
	end)
	if ok and pivot then
		return pivot.Position
	end
	local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	return pp and pp.Position or nil
end

local function findAltarByTier(tier)
	tier = math.floor(tonumber(tier) or 0)
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") and math.floor(tonumber(inst:GetAttribute("AltarTier")) or 0) == tier then
			return inst
		end
	end
	if tier == 1 then
		return Workspace:FindFirstChild("T1AltarTemp")
	end
	return nil
end

local function playerNearAltar(player, altarTier)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	local altar = findAltarByTier(altarTier)
	local pos = altar and getModelPivot(altar)
	if not pos then
		return false
	end
	return (hrp.Position - pos).Magnitude <= ALTAR_MAX_DISTANCE
end

local function bootstrapAltarModel(model, tier)
	if not model or not model:IsA("Model") then
		return
	end
	model:SetAttribute("AltarTier", tier)
	if not model.PrimaryPart then
		local part = model:FindFirstChildWhichIsA("BasePart", true)
		if part then
			model.PrimaryPart = part
		end
	end
	local host = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not host then
		return
	end
	local prompt = host:FindFirstChild("AltarPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AltarPrompt"
		prompt.Parent = host
	end
	prompt.ActionText = "Use"
	prompt.ObjectText = string.format("T%d Altar", tier)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
end

local function bootstrapAltars()
	local t1 = Workspace:FindFirstChild("T1AltarTemp")
	if t1 then
		bootstrapAltarModel(t1, 1)
	end
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") then
			local tier = math.floor(tonumber(inst:GetAttribute("AltarTier")) or 0)
			if tier >= 1 and tier <= 5 then
				bootstrapAltarModel(inst, tier)
			end
		end
	end
end

bootstrapAltars()
Workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") then
		local tier = math.floor(tonumber(inst:GetAttribute("AltarTier")) or 0)
		if tier >= 1 and tier <= 5 then
			task.defer(bootstrapAltarModel, inst, tier)
		elseif inst.Name == "T1AltarTemp" then
			task.defer(bootstrapAltarModel, inst, 1)
		end
	end
end)

rfAltarRequest.OnServerInvoke = function(player, request)
	if type(request) ~= "table" or request.action ~= "Upgrade" then
		return { ok = false, err = "bad_request" }
	end

	local altarTier = math.floor(tonumber(request.altarTier) or 0)
	if altarTier < 1 or altarTier > 5 then
		return { ok = false, err = "bad_altar_tier" }
	end

	if not playerNearAltar(player, altarTier) then
		return { ok = false, err = "too_far" }
	end

	local profile = DungeonProfile.Load(player)
	if type(profile.flags) == "table" and profile.flags.inRaid then
		return { ok = false, err = "in_raid" }
	end

	local ok, err = DungeonProfile.ApplyAltarUpgrade(player, altarTier, request.centerUuid, request.sacrificeUuids)
	if not ok then
		return { ok = false, err = err or "upgrade_failed" }
	end

	local snap = DungeonProfile.GetLastSnapshotPayload(player)
	return { ok = true, snapshot = snap }
end

print("[AltarService] ready")
