local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local SSS=game:GetService("ServerScriptService")
local States=require(RS:WaitForChild("PlayerStateEnum"))
local SCR=RS:WaitForChild("GameEvents"):WaitForChild("StateChanged")
local SCB=RS:WaitForChild("StateChangedBindable")
local GS=SSS:WaitForChild("GetPlayerState")
local CA=SSS:WaitForChild("CanPlayerAct")
local TS=SSS:WaitForChild("TransitionPlayerState")
local EnergyData=require(SSS:WaitForChild("EnergyData"))
local VALID={
    [States.IDLE]={[States.WALKING]=true,[States.SPRINTING]=true,[States.ATTACKING]=true,[States.LOW_ENERGY]=true,[States.DEAD]=true},
    [States.WALKING]={[States.IDLE]=true,[States.SPRINTING]=true,[States.ATTACKING]=true,[States.LOW_ENERGY]=true,[States.DEAD]=true},
    [States.SPRINTING]={[States.IDLE]=true,[States.WALKING]=true,[States.ATTACKING]=true,[States.LOW_ENERGY]=true,[States.DEAD]=true},
    [States.ATTACKING]={[States.IDLE]=true,[States.WALKING]=true,[States.LOW_ENERGY]=true,[States.DEAD]=true},
    [States.LOW_ENERGY]={[States.IDLE]=true,[States.DEAD]=true},
    [States.DEAD]={[States.IDLE]=true},
}
local BLK={[States.LOW_ENERGY]=true,[States.DEAD]=true}
local data={}
local function gs(p) return data[p] and data[p].state or nil end
local function ca(p) local s=gs(p) return s~=nil and not BLK[s] end
local function tt(p,new,reason)
    local d=data[p] if not d then return false end
    local cur=d.state if cur==new then return true end
    if not(VALID[cur] and VALID[cur][new]) then warn("[PSS] Bad: "..cur.."->"..new) return false end
    if d.lt then pcall(task.cancel,d.lt) d.lt=nil end
    d.state=new
    print("[PSS] "..p.Name.."  "..cur.."->"..new.."  ["..(reason or "").."]")
    SCR:FireClient(p,new,cur) SCB:Fire(p,new,cur)
    if new==States.DEAD then
        local h=p.Character and p.Character:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed=16 end
    end
    return true
end
GS.OnInvoke=gs CA.OnInvoke=ca TS.OnInvoke=tt
local function add(p)
    data[p]={state=States.IDLE,lt=nil}
    p.CharacterAdded:Connect(function()
        if not data[p] then return end
        data[p].state=States.IDLE
        EnergyData.setBlocked(p, false)
        SCR:FireClient(p,States.IDLE,States.DEAD)
        SCB:Fire(p,States.IDLE,States.DEAD)
    end)
    print("[PSS] "..p.Name.." ready")
end
Players.PlayerAdded:Connect(add)
Players.PlayerRemoving:Connect(function(p) local d=data[p] if d and d.lt then pcall(task.cancel,d.lt) end data[p]=nil end)
for _,p in ipairs(Players:GetPlayers()) do task.spawn(add,p) end
