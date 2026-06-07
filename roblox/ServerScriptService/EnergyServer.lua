local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local SSS=game:GetService("ServerScriptService")
local Config=require(RS:WaitForChild("EnergyConfig"))
local EnergyData=require(SSS:WaitForChild("EnergyData"))
local HungerData=require(SSS:WaitForChild("HungerData"))
local BuffService=require(SSS:WaitForChild("BuffService"))
local States=require(RS:WaitForChild("PlayerStateEnum"))
local EE=RS:WaitForChild("EnergyEvents")
local EnergyChanged=EE:WaitForChild("EnergyChanged")
local RequestSprint=EE:WaitForChild("RequestSprint")

local function ensureRemoteFunction(parent, name)
	local x = parent:FindFirstChild(name)
	if x and x:IsA("RemoteFunction") then
		return x
	end
	if x then
		x:Destroy()
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = parent
	return rf
end
local RequestDash = ensureRemoteFunction(EE, "RequestDash")

local SCB=RS:WaitForChild("StateChangedBindable")
local TS=SSS:WaitForChild("TransitionPlayerState")
local GetPlayerState=SSS:WaitForChild("GetPlayerState")
local SEND_RATE=0.05
local lastSpeedBonusByUid = {}
local function speedMult(p)
    return 1 + (BuffService.GetSpeedBonusPct(p) / 100)
end
local function applyWalkSpeed(p)
    local d=EnergyData.get(p) if not d or d.isBlocked then return end
    local h=p.Character and p.Character:FindFirstChildOfClass("Humanoid") if not h then return end
    local base = Config.NORMAL_SPEED
    if d.isPanting then
        base = Config.PANT_WALK_SPEED
    elseif d.isSprintHeld then
        base = Config.SPRINT_SPEED
    end
    h.WalkSpeed = base * speedMult(p)
end
local function send(p,lockout)
    local d=EnergyData.get(p) if not d then return end
    local ev=p:FindFirstChild("Energy") if ev then ev.Value=d.energy end
    EnergyChanged:FireClient(p,d.energy,lockout or false)
    d.lastSent=tick()
end
local function onLow(p)
    local d=EnergyData.get(p) if not d then return end
    d.isSprintHeld=false
    p:SetAttribute("EnergyPanting", true)
    applyWalkSpeed(p)
    send(p,true)
    print("[EnergyServer] "..p.Name.." LOW ENERGY (panting)")
    TS:Invoke(p,States.LOW_ENERGY,"energy_depleted")
end
local function onRecovered(p)
    send(p,false)
    p:SetAttribute("EnergyPanting", false)
    applyWalkSpeed(p)
    local st = GetPlayerState:Invoke(p)
    if st == States.LOW_ENERGY then
        TS:Invoke(p, States.IDLE, "energy_full")
    end
    print("[EnergyServer] "..p.Name.." recovered from panting")
end
EnergyData.onEnergyDepleted=onLow
EnergyData.onEnergyRecovered=onRecovered
SCB.Event:Connect(function(p,new,prev)
    if new=="DEAD" then EnergyData.setBlocked(p,true) end
    if prev=="LOW_ENERGY" and new=="IDLE" then send(p,false) end
end)
RunService.Heartbeat:Connect(function(dt)
    local now=tick()
    for _,p in ipairs(Players:GetPlayers()) do
        HungerData.applyTick(p, dt)
        HungerData.enforceSprintGate(p)
        local d=EnergyData.get(p) if not d then continue end
        EnergyData.applyTick(p,dt)
        if d.isBlocked then continue end
        local ev=p:FindFirstChild("Energy") if ev then ev.Value=d.energy end
        -- Refresh WalkSpeed when this player's active speed-buff total changes
        -- (covers buff start, expiry, and Humanoid respawn).
        local curBonus = BuffService.GetSpeedBonusPct(p)
        if lastSpeedBonusByUid[p.UserId] ~= curBonus then
            lastSpeedBonusByUid[p.UserId] = curBonus
            applyWalkSpeed(p)
        end
        if now-d.lastSent>=SEND_RATE then EnergyChanged:FireClient(p,d.energy,d.isPanting == true) d.lastSent=now end
    end
end)
RequestSprint.OnServerEvent:Connect(function(p,isHeld)
    if EnergyData.isBlocked(p) or EnergyData.isPanting(p) then return end
    if isHeld and not HungerData.canSprint(p) then return end
    local h=p.Character and p.Character:FindFirstChildOfClass("Humanoid") if not h then return end
    EnergyData.setSprintHeld(p,isHeld)
    applyWalkSpeed(p)
end)

RequestDash.OnServerInvoke = function(p)
    if EnergyData.isBlocked(p) or EnergyData.isPanting(p) then
        return false
    end
    if not HungerData.canDash(p) then
        return false
    end
    local ok = EnergyData.tryDash(p)
    if ok then
        local d = EnergyData.get(p)
        send(p, d and d.isPanting or false)
    end
    return ok
end
local function initPlayer(p)
    EnergyData.init(p)
    HungerData.init(p)
    print("[EnergyServer] "..p.Name.." ready (energy + hunger)")
end
Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(function(p)
    lastSpeedBonusByUid[p.UserId] = nil
    EnergyData.remove(p)
    HungerData.remove(p)
end)
for _,p in ipairs(Players:GetPlayers()) do initPlayer(p) end
