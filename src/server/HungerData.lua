local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Config = require(RS:WaitForChild("HungerConfig"))
local EnergyCfg = require(RS:WaitForChild("EnergyConfig"))
local EnergyData = require(SSS:WaitForChild("EnergyData"))

local HungerData = {}
local _d = {}

local function pushValues(player, d)
	local hv = player:FindFirstChild("Hunger")
	if hv and hv:IsA("NumberValue") then
		hv.Value = d.hunger
	end
end

function HungerData.init(player)
	_d[player] = {
		hunger = Config.MAX_HUNGER,
		maxHunger = Config.MAX_HUNGER,
		exhaustion = 0,
	}
	local v = Instance.new("NumberValue")
	v.Name = "Hunger"
	v.Value = Config.MAX_HUNGER
	v.Parent = player
end

function HungerData.remove(player)
	_d[player] = nil
	local nv = player:FindFirstChild("Hunger")
	if nv then
		nv:Destroy()
	end
end

function HungerData.get(player)
	return _d[player]
end

function HungerData.canSprint(player)
	local d = _d[player]
	if not d then
		return true
	end
	return d.hunger >= Config.MIN_HUNGER_TO_SPRINT
end

function HungerData.canDash(player)
	local d = _d[player]
	if not d then
		return true
	end
	return d.hunger > 0
end

-- Central exhaustion accumulator (Minecraft-style, 2026-09-07 rework). Every
-- tracked action -- movement, jumping, attacking, taking damage -- calls this
-- with its Minecraft-mapped cost (see HungerConfig.EXHAUSTION). Nothing calls
-- this while a player stands still, so hunger truly never drains at rest,
-- same as real Minecraft. Drains Hunger directly (Saturation was removed
-- 2026-09-07, same day it was added, per direct feedback).
function HungerData.addExhaustion(player, amount)
	local d = _d[player]
	if not d or type(amount) ~= "number" or amount <= 0 then
		return
	end
	d.exhaustion += amount
	local changed = false
	while d.exhaustion >= Config.EXHAUSTION_PER_PIP do
		d.exhaustion -= Config.EXHAUSTION_PER_PIP
		if d.hunger > 0 then
			d.hunger = math.max(0, d.hunger - 1)
			changed = true
		else
			-- Already empty -- nothing left to drain. (Real Minecraft starts
			-- damaging the player once hunger hits 0; we don't do that yet.)
			d.exhaustion = 0
			break
		end
	end
	if changed then
		pushValues(player, d)
	end
end

-- Eating: restores Hunger pips directly, capped at max.
function HungerData.eat(player, hungerPips)
	local d = _d[player]
	if not d or type(hungerPips) ~= "number" or hungerPips <= 0 then
		return
	end
	d.hunger = math.clamp(d.hunger + hungerPips, 0, d.maxHunger)
	pushValues(player, d)
end

-- If too hungry to sprint, clear sprint request and snap walk speed (EnergyServer owns RequestSprint).
function HungerData.enforceSprintGate(player)
	if HungerData.canSprint(player) then
		return
	end
	local d = EnergyData.get(player)
	if d and d.isSprintHeld then
		EnergyData.setSprintHeld(player, false)
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then
			if d.isPanting then
				h.WalkSpeed = EnergyCfg.PANT_WALK_SPEED
			else
				h.WalkSpeed = EnergyCfg.NORMAL_SPEED
			end
		end
	end
end

return HungerData
