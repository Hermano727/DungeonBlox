-- MerchantShopClient: ROUTER ONLY. Zero UI code.
-- To add a new NPC type: create XxxClient module + add one resolvePrompt line below.
-- Editing any client module will NEVER affect this file or any other client.

local Players                = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local DialogRuntime       = require(script.Parent:WaitForChild("DialogHud"):WaitForChild("DialogRuntime"))
local HearthstoneClient   = require(script.Parent:WaitForChild("HearthstoneClient"))
local AuctionHouseClient  = require(script.Parent:WaitForChild("AuctionHouseClient"))
local MerchantClient      = require(script.Parent:WaitForChild("MerchantClient"))
local DungeoneerClient    = require(script.Parent:WaitForChild("DungeoneerClient"))
local AnimalTrainerClient = require(script.Parent:WaitForChild("AnimalTrainerClient"))

local player = Players.LocalPlayer

local function resolvePrompt(prompt, npcType)
	if not prompt or not prompt:IsA("ProximityPrompt") then return nil end
	local parent = prompt.Parent; if not parent then return nil end
	local model  = parent:FindFirstAncestorOfClass("Model"); if not model then return nil end
	if model:GetAttribute("NpcType") ~= npcType then return nil end
	local npcId = model:GetAttribute("NpcId")
	if type(npcId) ~= "string" or npcId == "" then return nil end
	return model, npcId
end

local function resolveInnkeeper(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then return nil end
	local parent = prompt.Parent; if not parent then return nil end
	local model  = parent:FindFirstAncestorOfClass("Model"); if not model then return nil end
	local t = model:GetAttribute("NpcType")
	if t ~= "Innkeeper" and model.Name ~= "Innkeeper" then return nil end
	local npcId = model:GetAttribute("NpcId")
	if type(npcId) ~= "string" or npcId == "" then npcId = "innkeeper_01" end
	return model, npcId
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then return end
	-- Each NPC type routes to its own fully-isolated client module.
	-- Add new types at the bottom; never modify existing lines.
	local bsModel,bsId = resolvePrompt(prompt, "Blacksmith")
	if bsId then DialogRuntime.startConversation(bsModel, bsId, "Blacksmith"); return end
	local _,innId = resolveInnkeeper(prompt);               if innId then HearthstoneClient.openInnkeeperShop(); return end
	local _,aucId = resolvePrompt(prompt, "Auctioneer");    if aucId then AuctionHouseClient.open();       return end
	local _,merId = resolvePrompt(prompt, "Merchant");      if merId then MerchantClient.open(merId);     return end
	local _,dunId = resolvePrompt(prompt, "Dungeoneer");    if dunId then DungeoneerClient.open(dunId);   return end
	local _,atId  = resolvePrompt(prompt, "AnimalTrainer"); if atId  then AnimalTrainerClient.open(atId); return end
	-- Add new NPC types here:
end)

player.CharacterAdded:Connect(function()
	-- Each client handles its own cursor release on CharacterAdded.
end)

print("[MerchantShopClient] router ready")
