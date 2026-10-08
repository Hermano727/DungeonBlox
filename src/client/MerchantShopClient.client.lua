-- MerchantShopClient: ROUTER ONLY. Zero UI code.
-- Every service NPC's ProximityPrompt lands here. If the NpcType has a dialog tree
-- (RS/DialogSystem/Trees/<NpcType>) the conversation opens and its options open the menu;
-- NPCRegistry `SkipDialog = true` (Merchant, Animal Trainer) opens the menu straight away.
-- To add a service NPC: its XxxClient module (with .open(npcId)) + one SERVICE entry below,
-- and a tree if it should talk first.
-- The tutorial / quest NPCs (Miner, Fisherman, QuestGiver) are not routed here; they still
-- use the old DialogModule through NPCClient.

local Players                = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")

local NPCRegistry         = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local DialogTrees         = require(ReplicatedStorage:WaitForChild("DialogSystem"):WaitForChild("DialogTreeLoader"))
local DialogRuntime       = require(script.Parent:WaitForChild("DialogHud"):WaitForChild("DialogRuntime"))
local HearthstoneClient   = require(script.Parent:WaitForChild("HearthstoneClient"))

local player = Players.LocalPlayer

-- NpcType -> the module whose .open(npcId) opens that NPC's menu.
local SERVICE = {
	Merchant      = require(script.Parent:WaitForChild("MerchantClient")),
	AnimalTrainer = require(script.Parent:WaitForChild("AnimalTrainerClient")),
	Dungeoneer    = require(script.Parent:WaitForChild("DungeoneerClient")),
	Auctioneer    = require(script.Parent:WaitForChild("AuctionHouseClient")),
	Blacksmith    = require(script.Parent:WaitForChild("BlacksmithClient")),
	SkillTrainer  = require(script.Parent:WaitForChild("SkillTrainerClient")),
	Innkeeper     = { open = function() HearthstoneClient.openInnkeeperShop() end },
}

-- The NPC behind a prompt: its model, NpcType and NpcId. Innkeeper models from before the
-- attributes existed are recognised by name.
local function resolve(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Parent then return nil end
	local model = prompt.Parent:FindFirstAncestorOfClass("Model")
	if not model then return nil end
	local npcType = model:GetAttribute("NpcType")
	if npcType == nil and model.Name == "Innkeeper" then npcType = "Innkeeper" end
	if type(npcType) ~= "string" or not SERVICE[npcType] then return nil end
	local npcId = model:GetAttribute("NpcId")
	if type(npcId) ~= "string" or npcId == "" then
		if npcType ~= "Innkeeper" then return nil end
		npcId = "innkeeper_01"
	end
	return model, npcType, npcId
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then return end
	local model, npcType, npcId = resolve(prompt)
	if not model then return end
	local reg = NPCRegistry.Get(npcType)
	if DialogTrees[npcType] and not (reg and reg.SkipDialog) then
		DialogRuntime.startConversation(model, npcId, npcType)
	else
		SERVICE[npcType].open(npcId)
	end
end)

print("[MerchantShopClient] router ready")
