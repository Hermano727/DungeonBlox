--[[
	PotionClient
	Charge/cooldown HUD for PotionService. Drinking itself is triggered by right-clicking
	while a potion is the equipped/held tool — see DrinkPotionClientTemplate (cloned into
	the DefaultPotionTool prefab by EquippedHotbar). This script owns only the
	charge readout, not the drink trigger.

	2026-09-10 rework (direct request: hunger on the left, potions on the right, same row,
	"this will replace the current 'minor x3/3' small box on the left of the screen right
	now"): the standalone list-box HUD is gone. Charges now render as icons parented into
	HealthClient.client.lua's PotionIconsMount (the mount point on the right side of its
	Hunger+Potion row) — HealthClient owns that row's layout, this script only owns the
	charge networking + the icons themselves. Also reflects PotionService's shared-pool
	charge model (one pool across every tier, not one per tier — see PotionConfig), so
	there's a single row of icons rather than one row per tier.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local PotionConfig = require(ReplicatedStorage:WaitForChild("PotionConfig"))

local gameEvents = ReplicatedStorage:WaitForChild("GameEvents", 10)
local chargesSync = gameEvents and gameEvents:WaitForChild("PotionChargesSync", 10)
local requestCharges = gameEvents and gameEvents:WaitForChild("RequestPotionCharges", 10)

-- Icon art: per direct request, every charge slot uses the Medium Potion icon -- the shared
-- pool isn't tier-specific anymore (drinking a Minor or a Medium both spend the same charge),
-- so there's no single "correct" tier to represent it with; Medium is the one explicitly
-- asked for ("we will use the icon for the medium potion in this case"). Read through
-- ItemDefinitions/ConsumableIcons (the shared asset ID registry the Merchant also uses)
-- instead of a hardcoded asset id, so it stays in sync if that icon is ever swapped.
local POTION_ICON = ItemDefinitions.GetIcon("MediumPotion")
local POTION_ICON_SIZE = 18 -- matches HealthClient's hunger-pip PIP_SIZE-driven row height
local MAX_CHARGES = PotionConfig.SharedCharges.maxCharges

---------------------------------------------------------------------------
-- Build the charge icons into HealthClient's mount point once it exists (same
-- wait-and-poll pattern HotbarHud uses to find SkillsPopupUI).
---------------------------------------------------------------------------

task.spawn(function()
	local mount
	repeat
		mount = playerGui:FindFirstChild("PotionIconsMount", true)
		if not mount then task.wait(0.5) end
	until mount

	local icons = {}
	for i = 1, MAX_CHARGES do
		local icon = Instance.new("ImageLabel")
		icon.Name = "PotionIcon" .. i
		icon.LayoutOrder = i
		icon.Size = UDim2.fromOffset(POTION_ICON_SIZE, POTION_ICON_SIZE)
		icon.BackgroundTransparency = 1
		icon.Image = POTION_ICON
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ImageTransparency = 0.7 -- dim until renderCharges lights up available ones
		icon.Parent = mount
		icons[i] = icon
	end

	local function renderCharges(data)
		local count = (type(data) == "table" and data.count) or 0
		for i, icon in ipairs(icons) do
			icon.ImageTransparency = (i <= count) and 0 or 0.7
		end
	end

	if chargesSync then
		chargesSync.OnClientEvent:Connect(renderCharges)
	end

	if requestCharges then
		local ok, payload = pcall(function()
			return requestCharges:InvokeServer()
		end)
		if ok then
			renderCharges(payload)
		end
	end
end)

print("[PotionClient] ready")
