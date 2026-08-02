--[[
	WorldLootTooltipClient
	Shows the shared ItemTooltip panel when the local player approaches their
	weapon/armor loot orb (same stats layout as inventory hover).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local ItemTooltip = require(script.Parent:WaitForChild("ItemTooltip"))

local player = Players.LocalPlayer
local activeAnchor = nil
local followConn = nil

local function stopFollowing()
	if followConn then
		followConn:Disconnect()
		followConn = nil
	end
	activeAnchor = nil
end

local function decodeItem(anchor)
	if typeof(anchor) ~= "Instance" then
		return nil
	end
	local json = anchor:GetAttribute("LootItemJson")
	if type(json) ~= "string" or json == "" then
		return nil
	end
	local ok, item = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok or type(item) ~= "table" then
		return nil
	end
	return item
end

local function isOwnedLootAnchor(anchor)
	if typeof(anchor) ~= "Instance" or not anchor:IsA("BasePart") then
		return false
	end
	if anchor:GetAttribute("LootTooltipItem") ~= true then
		return false
	end
	local ownerId = anchor:GetAttribute("LootOwnerUserId")
	return ownerId == player.UserId
end

local function showForPrompt(prompt)
	if not prompt or prompt.Name ~= "LootPrompt" then
		return
	end
	local anchor = prompt.Parent
	if not isOwnedLootAnchor(anchor) then
		return
	end
	local item = decodeItem(anchor)
	if not item or (item.type ~= "Weapon" and item.type ~= "Armor") then
		return
	end

	stopFollowing()
	activeAnchor = anchor
	ItemTooltip.showAtWorldPart(item, anchor)

	followConn = RunService.RenderStepped:Connect(function()
		if not activeAnchor or not activeAnchor.Parent then
			ItemTooltip.hide()
			stopFollowing()
			return
		end
		ItemTooltip.repositionAtWorldPart(activeAnchor)
	end)
end

local function hideForPrompt(prompt)
	if not prompt or prompt.Name ~= "LootPrompt" then
		return
	end
	local anchor = prompt.Parent
	if activeAnchor and anchor == activeAnchor then
		ItemTooltip.hide()
		stopFollowing()
	end
end

ProximityPromptService.PromptShown:Connect(function(prompt)
	showForPrompt(prompt)
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	hideForPrompt(prompt)
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who == player then
		hideForPrompt(prompt)
	end
end)

print("[WorldLootTooltipClient] ready")
