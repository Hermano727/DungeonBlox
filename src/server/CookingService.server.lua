--[[
	CookingService
	Cooking fish at a fire (2026-10-03; CookingConfig has the rules).

	Every cooking fire (CookingConfig.IsSource: the Torch_Stand for now, or anything tagged
	CookingFire) gets a CookPrompt, including the copies dungeon runs clone in later. Holding it
	cooks every raw fish the player carries (not the bank) into its cooked version, one for one.
	CookingClient styles the prompt (the COOK emblem) and hides it from players with no raw fish;
	this side re-checks everything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local CookingConfig = require(ReplicatedStorage:WaitForChild("CookingConfig"))
local ConsumableRequestUtil = require(ReplicatedStorage:WaitForChild("ConsumableRequestUtil"))

local gameEvents = ConsumableRequestUtil.EnsureGameEventsFolder()
local CookResult = ConsumableRequestUtil.EnsureRemoteEvent(gameEvents, "CookResult")

local COOK_GAP = 1 -- seconds between cooks per player
local lastCook = {}

---------------------------------------------------------------------------
-- Prompts on every fire
---------------------------------------------------------------------------

-- Where the prompt hangs: the flame's attachment if there is one, else the biggest part.
local function promptParent(source: Instance): Instance?
	local flame = source:FindFirstChild("TorchFlame", true)
	if flame and flame:IsA("Attachment") then return flame end
	if source:IsA("BasePart") then return source end
	local best, bestVolume = nil, 0
	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bestVolume then best, bestVolume = d, v end
		end
	end
	return best
end

local function attachPrompt(source: Instance)
	if not source.Parent or source:FindFirstChild(CookingConfig.PROMPT_NAME, true) then return end
	local parent = promptParent(source)
	if not parent then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = CookingConfig.PROMPT_NAME
	prompt.ActionText = "Cook fish"
	prompt.ObjectText = "Fire"
	prompt.HoldDuration = CookingConfig.HOLD_DURATION
	prompt.MaxActivationDistance = CookingConfig.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = parent
end

local function consider(inst: Instance)
	if CookingConfig.IsSource(inst) then
		-- Deferred: a freshly cloned model's children may still be arriving.
		task.defer(attachPrompt, inst)
	end
end

for _, d in ipairs(workspace:GetDescendants()) do consider(d) end
workspace.DescendantAdded:Connect(consider)
CollectionService:GetInstanceAddedSignal(CookingConfig.SOURCE_TAG):Connect(consider)

---------------------------------------------------------------------------
-- Cooking
---------------------------------------------------------------------------

local function cook(player: Player)
	local now = os.clock()
	if (lastCook[player.UserId] or 0) + COOK_GAP > now then return end
	lastCook[player.UserId] = now

	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile then return end
	local stacks = CookingConfig.CarriedStacks(profile, function(id) return CookingConfig.RECIPES[id] ~= nil end)
	if #stacks == 0 then
		CookResult:FireClient(player, { cooked = 0, reason = "no_fish" })
		return
	end

	-- Stack by stack: take the raw fish out, put the cooked ones in. Taking the raw stack first
	-- frees its slot, so a full bag still has room; if the grant fails anyway the raw fish go back.
	local cooked, byId, full = 0, {}, false
	for _, stack in ipairs(stacks) do
		local cookedId = CookingConfig.CookedFor(stack.itemId)
		local ok = cookedId and DungeonProfile.ConsumeFromStack(player, stack.uuid, stack.count)
		if ok then
			local granted = DungeonProfile.GrantItemId(player, cookedId, stack.count)
			if granted then
				cooked += stack.count
				byId[cookedId] = (byId[cookedId] or 0) + stack.count
			else
				DungeonProfile.GrantItemId(player, stack.itemId, stack.count)
				full = true
				break
			end
		end
	end
	CookResult:FireClient(player, { cooked = cooked, byId = byId, full = full })
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if prompt.Name ~= CookingConfig.PROMPT_NAME then return end
	cook(player)
end)

Players.PlayerRemoving:Connect(function(player)
	lastCook[player.UserId] = nil
end)
