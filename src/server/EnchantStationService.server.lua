--[[
	EnchantStationService
	Bootstraps world-placed Enchanting Station models (ProximityPrompt) --
	same pattern as AltarService.server.luau, but for the +0..+9 gear-scroll
	enchant system (EnchantScrollApply/ProfileService.ApplyEnchantScroll),
	NOT the rarity-ascension Altar (AltarService/AltarUpgrade -- a different
	mechanic entirely, don't conflate the two).

	The actual enchant apply is already fully wired end-to-end via the
	DungeonInventoryAct RF (kind = "ApplyEnchantScroll") -- see
	ProfileBootstrap.server.lua. This service only has to make the world
	model interactable; the client (EnchantStationClient.client.lua) does
	the rest (camera pan + UI + calling that same existing remote).

	Workspace is Studio-owned, not Rojo-synced, so the model is hand-placed/
	imported in Studio and this script finds it at runtime rather than the
	model being declared on disk.
]]

local Workspace = game:GetService("Workspace")

-- Matches any instance whose Name CONTAINS "EnchantingAltar" anywhere --
-- covers the original import name ("EnchantingAltar_ImportReady") and any
-- renamed/prefixed/duplicated copy (e.g. "OakHaven_EnchantingAltar", a
-- second one in another town as "IronReach_EnchantingAltar", etc). This is
-- the convention: to make a new placed copy of the altar interactable,
-- just make sure "EnchantingAltar" appears somewhere in its Name -- no
-- script/attribute editing needed. A hand-set `EnchantStation = true`
-- attribute also opts an instance in regardless of name, for a copy named
-- completely differently.
--
-- NOTE: this was previously an anchored "^EnchantingAltar" prefix match,
-- which silently stopped matching the moment the altar got renamed to
-- "OakHaven_EnchantingAltar" (no longer STARTS WITH "EnchantingAltar") --
-- that's the reason the prompt stopped appearing after the rename.
local NAME_NEEDLE = "EnchantingAltar"
local PROMPT_NAME = "EnchantPrompt"

local function resolveHostPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		if not inst.PrimaryPart then
			local part = inst:FindFirstChildWhichIsA("BasePart", true)
			if part then
				inst.PrimaryPart = part
			end
		end
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function isEnchantStation(inst: Instance): boolean
	if inst:GetAttribute("EnchantStation") == true then
		return true
	end
	return (inst:IsA("BasePart") or inst:IsA("Model")) and string.find(inst.Name, NAME_NEEDLE, 1, true) ~= nil
end

local function bootstrapStation(inst: Instance)
	local host = resolveHostPart(inst)
	if not host then
		return
	end
	host:SetAttribute("EnchantStation", true)

	local prompt = host:FindFirstChild(PROMPT_NAME)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.Parent = host
	end
	prompt.ActionText = "Enchant"
	prompt.ObjectText = "Enchanting Station"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
end

local function scanExisting()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if isEnchantStation(inst) then
			bootstrapStation(inst)
		end
	end
end

scanExisting()
Workspace.DescendantAdded:Connect(function(inst)
	if isEnchantStation(inst) then
		task.defer(bootstrapStation, inst)
	end
end)

print("[EnchantStationService] ready")
