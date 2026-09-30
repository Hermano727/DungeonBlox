-- SpearFishHandler
-- Spear fishing tug minigame: hook a FishSilhouette, tug until progress >= 1, then grant fish.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local QuestProgress = require(ServerScriptService:WaitForChild("QuestProgressService"))
local PartyService = require(ServerScriptService:WaitForChild("PartyService"))
local FishingConfig = require(ReplicatedStorage:WaitForChild("FishingConfig"))
local SpearFishHook = ReplicatedStorage:WaitForChild("SpearFishHook")
local SpearFishTug = ReplicatedStorage:WaitForChild("SpearFishTug")
local SpearFishCancel = ReplicatedStorage:WaitForChild("SpearFishCancel")
local FishingXPEvent = ReplicatedStorage:WaitForChild("FishingXPEvent")

local MAX_HOOK_DISTANCE = 45
local TUG_CLICK_DELTA = 0.05 -- flat progress per successful fish click
local XP_PER_FISH = 5

local sessions = {}

local VALID_SPEAR_ITEM_IDS = {
	WoodenSpear = true,
	TrainingSpear = true,
}

local VALID_SPEAR_TOOL_NAMES = {
	WoodenSpear = true,
	Spear = true,
	["Wooden Spear"] = true,
	["Training Spear"] = true,
}

-- Weighted catch roll + table now live in shared/FishingConfig (see that file's header for why).
local rollFishEntry = FishingConfig.RollFishEntry

local function rollFishId()
	return rollFishEntry().id
end

local function ownsSpear(player)
	local function isSpearTool(t)
		if not t or not t:IsA("Tool") then
			return false
		end
		local itemId = t:GetAttribute("DungeonItemId")
		if type(itemId) == "string" and VALID_SPEAR_ITEM_IDS[itemId] then
			return true
		end
		local n = t.Name
		return VALID_SPEAR_TOOL_NAMES[n] == true
	end
	local character = player.Character
	if character then
		for _, c in ipairs(character:GetChildren()) do
			if isSpearTool(c) then
				return true
			end
		end
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		for _, c in ipairs(bp:GetChildren()) do
			if isSpearTool(c) then
				return true
			end
		end
	end
	return false
end

local function isFishSilhouette(inst)
	if typeof(inst) ~= "Instance" then
		return false
	end
	local cur = inst
	while cur do
		if cur.Name == "FishSilhouette" then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function clearSession(player)
	sessions[player.UserId] = nil
end

local function getHrp(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getFishSilhouettePosition(hitInstance)
	if typeof(hitInstance) ~= "Instance" then
		return nil
	end
	if hitInstance:IsA("BasePart") then
		return hitInstance.Position
	end
	if hitInstance:IsA("Model") then
		return hitInstance:GetPivot().Position
	end
	local part = hitInstance:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

local function sessionInRange(session, hrp)
	return (session.aimWorldPos - hrp.Position).Magnitude <= MAX_HOOK_DISTANCE
end

local function grantFish(player, fishId)
	local xpGain = XP_PER_FISH
	local _, _, totals = DungeonProfile.AddSkillXP(player, "fishing", xpGain)
	FishingXPEvent:FireClient(player, xpGain, totals)

	local resolvedFishId = fishId or rollFishId()
	local ok, err = DungeonProfile.GrantItemId(player, resolvedFishId, 1)
	if not ok then
		warn("[SpearFish] GrantItemId failed for", player.Name, resolvedFishId, err)
		return nil
	end
	QuestProgress.OnSpearFishCaught(player, 1)
	return resolvedFishId
end

SpearFishHook.OnServerInvoke = function(player, aimWorldPos, hitInstance)
	if typeof(aimWorldPos) ~= "Vector3" then
		return { ok = false, reason = "bad_aim" }
	end
	if not ownsSpear(player) then
		return { ok = false, reason = "no_spear" }
	end

	local hrp = getHrp(player)
	if not hrp then
		return { ok = false, reason = "no_char" }
	end
	if not isFishSilhouette(hitInstance) then
		return { ok = false, reason = "not_fish" }
	end

	local fishPos = getFishSilhouettePosition(hitInstance)
	if not fishPos then
		return { ok = false, reason = "no_fish_pos" }
	end
	if (fishPos - hrp.Position).Magnitude > MAX_HOOK_DISTANCE then
		return { ok = false, reason = "too_far" }
	end

	local fishEntry = rollFishEntry()

	sessions[player.UserId] = {
		progress = 0,
		aimWorldPos = aimWorldPos,
		hitInstance = hitInstance,
		fishId = fishEntry.id,
		tier = fishEntry.tier or 1,
	}

	return { ok = true, progress = 0, fishId = fishEntry.id, tier = fishEntry.tier or 1 }
end

SpearFishTug.OnServerInvoke = function(player)
	local session = sessions[player.UserId]
	if not session then
		return { ok = false, reason = "no_session" }
	end
	if not ownsSpear(player) then
		clearSession(player)
		return { ok = false, reason = "no_spear" }
	end

	local hrp = getHrp(player)
	if not hrp then
		clearSession(player)
		return { ok = false, reason = "no_char" }
	end
	if not sessionInRange(session, hrp) then
		clearSession(player)
		return { ok = false, reason = "too_far" }
	end

	session.progress = session.progress + TUG_CLICK_DELTA

	if session.progress >= 1 then
		local fishId = grantFish(player, session.fishId)
		clearSession(player)
		return {
			ok = true,
			progress = 1,
			completed = true,
			fishId = fishId,
		}
	end

	return {
		ok = true,
		progress = session.progress,
		completed = false,
	}
end

SpearFishCancel.OnServerEvent:Connect(function(player)
	clearSession(player)
end)

Players.PlayerRemoving:Connect(function(player)
	clearSession(player)
end)
