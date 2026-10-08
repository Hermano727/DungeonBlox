--[[
	CookingClient
	The COOK prompt at fires (CookingService makes the prompts; CookingConfig has the rules).

	  - Styled as a PromptEmblem (like the bank and the wardrobe), with embers rising off the fire.
	  - Only shown while you carry raw fish: every CookPrompt is switched on or off locally from
	    the profile snapshot. The server re-checks when you hold it.
	  - Holding E cooks them all; the result comes back as a centre flash.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CookingConfig = require(ReplicatedStorage:WaitForChild("CookingConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local HudIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))
local PromptEmblem = require(script.Parent:WaitForChild("PromptEmblem"))
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))
local CenterFlashUI = require(script.Parent:WaitForChild("CenterFlashUI"))

local CookResult = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("CookResult")

PromptEmblem.Register({
	match = function(prompt) return prompt.Name == CookingConfig.PROMPT_NAME end,
	title = "COOK",
	verb = "cook your fish",
	icon = HudIcons.COOK ~= "" and HudIcons.COOK or nil,
	accent = Color3.fromRGB(226, 128, 52),
	bright = Color3.fromRGB(255, 196, 120),
	motes = true,
})

---------------------------------------------------------------------------
-- Show the prompt only to someone carrying raw fish
---------------------------------------------------------------------------

local rawCount = 0
local prompts: { [ProximityPrompt]: boolean } = {}

local function apply(prompt: ProximityPrompt)
	prompt.Enabled = rawCount > 0
end

local function track(inst: Instance)
	if inst:IsA("ProximityPrompt") and inst.Name == CookingConfig.PROMPT_NAME and not prompts[inst] then
		prompts[inst] = true
		apply(inst)
		inst.Destroying:Connect(function() prompts[inst] = nil end)
	end
end

for _, d in ipairs(workspace:GetDescendants()) do track(d) end
workspace.DescendantAdded:Connect(track)

DungeonMenuNet.addSnapshotListener(function(snapshot)
	local n = CookingConfig.CountRaw(snapshot and snapshot.profile)
	if n == rawCount then return end
	rawCount = n
	for prompt in pairs(prompts) do
		if prompt.Parent then apply(prompt) end
	end
end)
DungeonMenuNet.start()

---------------------------------------------------------------------------
-- The result
---------------------------------------------------------------------------

CookResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then return end
	local cooked = tonumber(result.cooked) or 0
	if cooked > 0 then
		SfxService.PlayEffect("CookSizzle")
		-- Name the kinds when it's only one, count them when it's a mix.
		local kinds, only = 0, nil
		for id in pairs(result.byId or {}) do
			kinds += 1
			only = id
		end
		local what = kinds == 1 and (ItemDefinitions.Get(only) or {}).DisplayName or "fish"
		local text = ("Cooked %d %s"):format(cooked, what or "fish")
		if result.full then text ..= ". Your bag is full" end
		CenterFlashUI.Show(text)
	elseif result.reason == "no_fish" then
		CenterFlashUI.Show("You have no raw fish")
	elseif result.full then
		CenterFlashUI.Show("Your bag is full")
	end
	DungeonMenuNet.requestSync()
end)
