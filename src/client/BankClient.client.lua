--[[
  BankClient
  Opens the bank when you use the Treasure Chest's prompt (any prompt named BankPrompt, or any
  prompt under a model named "Treasure Chest"). The window is NpcShop (a Journal-style book),
  the spread is NpcShop/BankBook: the vault grid with unlockable rows, your bags, and
  wallet <-> bag coins. Rebuilt 2026-10-01; the old hand-built window was ~1,260 lines.

  The prompt is drawn by PromptEmblem (shared with the wardrobe): BANK over the coin icon,
  gold beads that fill while E is held, gold motes rising off the chest while you're in range.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NpcShop = require(script.Parent:WaitForChild("NpcShop"))
local BankBook = require(script.Parent.NpcShop:WaitForChild("BankBook"))
local PromptEmblem = require(script.Parent:WaitForChild("PromptEmblem"))
local JournalUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("JournalUI"))

local player = Players.LocalPlayer
local bank = NpcShop.window("Bank", BankBook)

local function isBankPrompt(prompt: ProximityPrompt): boolean
	return prompt.Name == "BankPrompt" or prompt:FindFirstAncestor("Treasure Chest") ~= nil
end

PromptEmblem.Register({
	match = isBankPrompt,
	title = "BANK",
	verb = "open",
	icon = JournalUI.fx_coinfind and JournalUI.fx_coinfind.Image or "",
	accent = Color3.fromRGB(232, 190, 96),
	bright = Color3.fromRGB(255, 232, 170),
	motes = true,
})

local connected: { [ProximityPrompt]: boolean } = {}
local function connectPrompt(prompt: ProximityPrompt)
	if connected[prompt] then return end
	connected[prompt] = true
	prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer == player then bank.open("") end
	end)
end

for _, desc in ipairs(workspace:GetDescendants()) do
	if desc:IsA("ProximityPrompt") and isBankPrompt(desc) then connectPrompt(desc) end
end
workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("ProximityPrompt") and isBankPrompt(desc) then connectPrompt(desc) end
end)
