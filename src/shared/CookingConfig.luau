--[[
	CookingConfig
	Cooking fish at a fire (2026-10-03). Shared by CookingService (server) and CookingClient.

	  - A fire is any model named in SOURCE_NAMES or tagged SOURCE_TAG. For now that's only the
	    Torch_Stand (the T1 boss room); the goal is every fire, so tag new ones rather than
	    adding names.
	  - Walking up with raw fish shows the COOK prompt (the client hides it when you carry none).
	    Holding E cooks every raw fish you carry (bag, hotbar; not the bank) into its cooked
	    version, one for one.
	  - Cooked fish are the food, all quick-eatable (Keys.QuickEat, the HUD slot left of the
	    hunger pips): tap the key to eat the selected kind, hold it to step the selection through
	    the kinds you carry (QUICK_EAT_ITEMS order). Plain fish is the default; the special fish
	    carry buffs. They can still be eaten from the bag (right click, Eat).
]]

local CookingConfig = {}

CookingConfig.SOURCE_TAG = "CookingFire"
CookingConfig.SOURCE_NAMES = { Torch_Stand = true }
CookingConfig.PROMPT_NAME = "CookPrompt"
CookingConfig.HOLD_DURATION = 1.5
CookingConfig.PROMPT_DISTANCE = 9

-- Raw itemId -> cooked itemId.
CookingConfig.RECIPES = {
	Fish = "T1_CookedFish",
	SwiftFish = "T2_CookedSwiftFish",
	LuckyFish = "T2_CookedLuckyFish",
	GoldenFish = "T3_CookedGoldenFish",
}

-- The quick-eat kinds, in the order holding the key steps through them. QUICK_EAT_ITEM is the
-- default selection.
CookingConfig.QUICK_EAT_ITEMS = { "T1_CookedFish", "T2_CookedSwiftFish", "T2_CookedLuckyFish", "T3_CookedGoldenFish" }
CookingConfig.QUICK_EAT_ITEM = "T1_CookedFish"

function CookingConfig.IsQuickEat(itemId: any): boolean
	return type(itemId) == "string" and table.find(CookingConfig.QUICK_EAT_ITEMS, itemId) ~= nil
end

-- Why a bite was refused (FoodService's reasons), for the centre flash.
CookingConfig.EAT_REFUSALS = {
	full = "You're full",
	none = "You have no cooked fish",
	banked = "Take it out of the bank first",
	busy = "You can't eat right now",
	too_fast = "Slow down",
}

function CookingConfig.CookedFor(itemId: string): string?
	return CookingConfig.RECIPES[itemId]
end

local function bankedSet(profile): { [string]: boolean }
	local banked = {}
	if type(profile.chestSlots) == "table" then
		for _, uuid in pairs(profile.chestSlots) do
			if type(uuid) == "string" then banked[uuid] = true end
		end
	end
	return banked
end

-- Every carried (not banked) stack matching `want(itemId)`, as { uuid, itemId, count }.
function CookingConfig.CarriedStacks(profile, want: (string) -> boolean)
	local stacks = {}
	local inventory = profile and profile.inventory
	if type(inventory) ~= "table" then return stacks end
	local banked = bankedSet(profile)
	for uuid, item in pairs(inventory) do
		if type(item) == "table" and type(item.itemId) == "string" and not banked[uuid] and want(item.itemId) then
			table.insert(stacks, { uuid = uuid, itemId = item.itemId, count = math.max(1, tonumber(item.count) or 1) })
		end
	end
	return stacks
end

local function total(stacks)
	local n = 0
	for _, s in ipairs(stacks) do n += s.count end
	return n
end

-- How many raw fish the profile carries.
function CookingConfig.CountRaw(profile): number
	return total(CookingConfig.CarriedStacks(profile, function(id) return CookingConfig.RECIPES[id] ~= nil end))
end

-- How many of one quick-eat kind (default the plain fish) the profile carries.
function CookingConfig.CountQuickEat(profile, itemId: string?): number
	local want = itemId or CookingConfig.QUICK_EAT_ITEM
	return total(CookingConfig.CarriedStacks(profile, function(id) return id == want end))
end

-- The quick-eat kinds the profile carries, in QUICK_EAT_ITEMS order: { { itemId, count } }.
function CookingConfig.CarriedQuickEatKinds(profile): { { itemId: string, count: number } }
	local out = {}
	for _, itemId in ipairs(CookingConfig.QUICK_EAT_ITEMS) do
		local n = CookingConfig.CountQuickEat(profile, itemId)
		if n > 0 then table.insert(out, { itemId = itemId, count = n }) end
	end
	return out
end

-- Is this instance a cooking fire?
function CookingConfig.IsSource(inst: Instance): boolean
	if not (inst:IsA("Model") or inst:IsA("BasePart")) then return false end
	if CookingConfig.SOURCE_NAMES[inst.Name] then return true end
	return game:GetService("CollectionService"):HasTag(inst, CookingConfig.SOURCE_TAG)
end

return CookingConfig
