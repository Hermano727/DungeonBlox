local RS=game:GetService("ReplicatedStorage")
local Config=require(RS:WaitForChild("EnergyConfig"))
local EnergyData={} local _d={}
EnergyData.onEnergyDepleted=nil
EnergyData.onEnergyRecovered=nil

function EnergyData.init(p)
    _d[p]={energy=Config.MAX_ENERGY,isSprintHeld=false,isBlocked=false,isPanting=false,lastSent=0,regenRate=Config.REGEN_RATE}
    local ev=Instance.new("NumberValue") ev.Name="Energy" ev.Value=Config.MAX_ENERGY ev.Parent=p
    p:SetAttribute("EnergyPanting", false)
end
function EnergyData.remove(p)
	if p then p:SetAttribute("EnergyPanting", nil) end
	_d[p]=nil
end
function EnergyData.get(p) return _d[p] end
function EnergyData.setBlocked(p,v) local d=_d[p] if d then d.isBlocked=v end end
function EnergyData.setRegenRate(p,rate) local d=_d[p] if d and type(rate)=="number" and rate>=0 then d.regenRate=rate end end
function EnergyData.chargeHitEnergy(p) local d=_d[p] if not d or d.isBlocked or d.isPanting then return end d.energy=math.max(0,d.energy-Config.SWING_COST*0.5) end
function EnergyData.setSprintHeld(p,v) local d=_d[p] if d then d.isSprintHeld=v end end
function EnergyData.isBlocked(p) local d=_d[p] return d~=nil and d.isBlocked end

-- Dev tool (F8 Profile tab): full energy now, ending Low Energy Mode if it was on.
function EnergyData.refill(p)
	local d=_d[p] if not d then return false end
	d.energy=Config.MAX_ENERGY
	if d.isPanting then
		d.isPanting=false
		if EnergyData.onEnergyRecovered then task.spawn(EnergyData.onEnergyRecovered,p) end
	end
	return true
end

function EnergyData.isPanting(p)
	local d = _d[p]
	return d ~= nil and d.isPanting == true
end

local function checkDepletion(p)
    local d=_d[p]
    if not d or d.isBlocked or d.isPanting then return end
    if d.energy > 0.5 then return end
    d.energy=0 d.isPanting=true
    print("[EnergyData] "..p.Name.." depleted — panting until full energy")
    if EnergyData.onEnergyDepleted then task.spawn(EnergyData.onEnergyDepleted,p)
    else warn("[EnergyData] onEnergyDepleted not registered!") end
end

function EnergyData.tryDash(p)
	local d = _d[p]
	if not d or d.isBlocked or d.isPanting then
		return false
	end
	if d.energy < Config.DASH_COST then
		return false
	end
	d.energy = d.energy - Config.DASH_COST
	if d.energy < 0 then
		d.energy = 0
	end
	local ev = p:FindFirstChild("Energy")
	if ev then
		ev.Value = d.energy
	end
	checkDepletion(p)
	return true
end

function EnergyData.trySwing(p)
    local d=_d[p]
    if not d or d.isBlocked or d.isPanting then return false end
    if d.energy < Config.SWING_COST then
        print("[EnergyData] "..p.Name.." swing failed (energy="..string.format("%.1f",d.energy)..") — panting")
        d.energy = 0
        local ev = p:FindFirstChild("Energy")
        if ev then ev.Value = 0 end
        checkDepletion(p)
        return false
    end
    d.energy = d.energy - Config.SWING_COST * 0.5
    if d.energy < 0.5 then d.energy = 0 end
    print("[EnergyData] "..p.Name.." swung — energy: "..string.format("%.1f",d.energy))
    local ev2 = p:FindFirstChild("Energy")
    if ev2 then ev2.Value = d.energy end
    checkDepletion(p)
    return true
end

function EnergyData.applyTick(p,dt)
    local d=_d[p] if not d or d.isBlocked then return end
    local baseRegen = (d.regenRate or Config.REGEN_RATE) * dt
    if d.isPanting then
        -- Panting is regen-only; sprint flag was already cleared by onLow().
        local prev = d.energy
        d.energy = math.min(Config.MAX_ENERGY, d.energy + baseRegen)
        if prev < Config.MAX_ENERGY and d.energy >= Config.MAX_ENERGY - 1e-3 then
            d.energy = Config.MAX_ENERGY
            d.isPanting = false
            if EnergyData.onEnergyRecovered then task.spawn(EnergyData.onEnergyRecovered, p) end
        end
        return
    end
    -- While sprinting, regen is suppressed so SPRINT_COST is the actual drain rate.
    -- (Otherwise a player whose derived energyRegen ≥ SPRINT_COST would have zero
    -- net drain and could sprint forever — the bug we're fixing here.)
    local regen = d.isSprintHeld and 0 or baseRegen
    local drain = d.isSprintHeld and (Config.SPRINT_COST * dt) or 0
    local prev = d.energy
    d.energy = math.clamp(d.energy - drain + regen, 0, Config.MAX_ENERGY)
    if d.energy <= 0.5 and prev > 0.5 then
        d.energy = 0
        checkDepletion(p)
    end
end
return EnergyData
