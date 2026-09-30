-- Short, non-stacking target statuses. No position or WalkSpeed writers here.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("CombatEnchantConfig"))
local Status = {}

-- Tag + attribute are both the SLOW's public surface, and both replicate:
-- the tag is how the client finds slowed targets to draw foot markers on
-- (EnchantSlowMarkers), the attribute is what EnergyServer watches to re-apply
-- a slowed player's WalkSpeed. Keep them written together.
Status.SLOW_TAG = "EnchantSlowed"

local function setSlowed(model, slowed)
	if slowed then
		model:SetAttribute("EnchantSlowed", true)
		CollectionService:AddTag(model, Status.SLOW_TAG)
	else
		model:SetAttribute("EnchantSlowed", nil)
		CollectionService:RemoveTag(model, Status.SLOW_TAG)
	end
end
local states = {}
local rng = Random.new()
local connection

function Status.Roll(percent)
	local chance = math.clamp(tonumber(percent) or 0, 0, 100) / 100
	return chance > 0 and rng:NextNumber() < chance
end

function Status.GetSpeedMultiplier(model)
	local state = model and states[model]
	return state and state.slowUntil and state.slowUntil > os.clock() and Config.SlowMultiplier or 1
end

function Status.CanHit(model)
	local state = model and states[model]
	return not (state and state.blindUntil and state.blindUntil > os.clock() and rng:NextNumber() < Config.BlindMissChance)
end

local function clear(model)
	states[model] = nil
	if model.Parent then
		setSlowed(model, false)
		model:SetAttribute("EnchantBlinded", nil)
	end
end

-- Removes every status on `model` (dev cleanse / death cleanse).
function Status.Clear(model)
	if model then clear(model) end
end

local function step()
	local time = os.clock()
	for model, state in pairs(states) do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not model.Parent or (humanoid and humanoid.Health <= 0) then clear(model); continue end
		if state.slowUntil and state.slowUntil <= time then state.slowUntil = nil; setSlowed(model, false) end
		if state.blindUntil and state.blindUntil <= time then state.blindUntil = nil; model:SetAttribute("EnchantBlinded", nil) end
		local bleeds = state.bleeds
		if bleeds then
			-- Each stack keeps its own cadence and its own per-tick damage, so a
			-- big hit's bleed stays big even when a small one lands on top of it.
			for i = #bleeds, 1, -1 do
				local bleed = bleeds[i]
				if time >= bleed.nextTick then
					-- Advance from now, never burst several ticks after a hitch.
					bleed.nextTick = time + Config.BleedInterval
					bleed.remaining -= 1
					local ok, keep = pcall(bleed.tick, bleed.perTick)
					if not ok then warn("[CombatEnchantStatus] Bleed tick failed: " .. tostring(keep)) end
					if not ok or keep == false or bleed.remaining <= 0 then table.remove(bleeds, i) end
				end
			end
			if #bleeds == 0 then state.bleeds = nil end
		end
		if not state.bleeds and not state.slowUntil and not state.blindUntil then clear(model) end
	end
	if not next(states) and connection then connection:Disconnect(); connection = nil end
end

-- `context.elementalHit` marks a hit that dealt elemental damage, which gets its
-- own flat slow chance on top of the Slowness substat (ice chills). Either source
-- lands the same non-stacking status: a second proc refreshes the timer, never
-- deepens the slow.
function Status.Apply(model, subs, bleedTick, context)
	if not model or not model.Parent then return {} end
	subs = subs or {}
	local time = os.clock()
	local state = states[model] or {}
	local slowed = Status.Roll(subs.slowness)
	if not slowed and context and context.elementalHit then
		slowed = Status.Roll(Config.ElementalSlowChance)
	end
	local flags = { Slowness = slowed, Blinding = Status.Roll(subs.blinding) }
	if flags.Slowness then state.slowUntil = time + Config.SlowDuration; setSlowed(model, true) end
	if flags.Blinding then state.blindUntil = time + Config.BlindDuration; model:SetAttribute("EnchantBlinded", true) end
	-- Bleed: the item value is a PROC CHANCE, and the bleed's damage comes from
	-- the hit that applied it (context.hitDamage), not from the item.
	local hitDamage = math.max(0, tonumber(context and context.hitDamage) or 0)
	if bleedTick and hitDamage > 0 and Status.Roll(subs.bleeding) then
		local perTick = hitDamage * Config.BleedDamageFraction / Config.BleedTicks
		if perTick > 0 then
			local bleeds = state.bleeds or {}
			state.bleeds = bleeds
			-- Stacks rather than refreshes: each proc is its own bleed, running
			-- its own timer alongside the others. Oldest goes at the cap.
			if #bleeds >= Config.BleedMaxStacks then table.remove(bleeds, 1) end
			table.insert(bleeds, {
				nextTick = time + Config.BleedInterval,
				perTick = perTick,
				remaining = Config.BleedTicks,
				tick = bleedTick,
			})
			flags.Bleeding = true
		end
	end
	if state.bleeds or state.slowUntil or state.blindUntil then
		states[model] = state
		if not connection then connection = RunService.Heartbeat:Connect(step) end
	end
	return flags
end

return Status
