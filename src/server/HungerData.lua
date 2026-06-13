local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Config = require(RS:WaitForChild("HungerConfig"))
local EnergyCfg = require(RS:WaitForChild("EnergyConfig"))
local EnergyData = require(SSS:WaitForChild("EnergyData"))

local HungerData = {}
local _d = {}

function HungerData.init(player)
	_d[player] = {
		hunger = Config.MAX_HUNGER,
		maxHunger = Config.MAX_HUNGER,
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

function HungerData.addHunger(player, amount)
	local d = _d[player]
	if not d or type(amount) ~= "number" or amount <= 0 then
		return
	end
	d.hunger = math.clamp(d.hunger + amount, 0, d.maxHunger)
	local nv = player:FindFirstChild("Hunger")
	if nv and nv:IsA("NumberValue") then
		nv.Value = d.hunger
	end
end

function HungerData.applyTick(player, dt)
	local d = _d[player]
	if not d then
		return
	end
	d.hunger = math.clamp(d.hunger - Config.PASSIVE_DRAIN_PER_SEC * dt, 0, d.maxHunger)
	local nv = player:FindFirstChild("Hunger")
	if nv and nv:IsA("NumberValue") then
		nv.Value = d.hunger
	end
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
