local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local SSS=game:GetService("ServerScriptService")
local Config=require(RS:WaitForChild("EnergyConfig"))
local HungerConfig=require(RS:WaitForChild("HungerConfig"))
local EnergyData=require(SSS:WaitForChild("EnergyData"))
local HungerData=require(SSS:WaitForChild("HungerData"))
local ZoneService=require(SSS:WaitForChild("ZoneService"))
local BuffService=require(SSS:WaitForChild("BuffService"))
local CombatEnchantStatus=require(SSS:WaitForChild("CombatEnchantStatus"))
local States=require(RS:WaitForChild("PlayerStateEnum"))
local EE=RS:WaitForChild("EnergyEvents")
local EnergyChanged=EE:WaitForChild("EnergyChanged")
local RequestSprint=EE:WaitForChild("RequestSprint")
local RequestCrouch=EE:WaitForChild("RequestCrouch")
local Profiles=require(RS:WaitForChild("CharacterAnimProfiles"))
local CombatAnimations=require(RS:WaitForChild("CombatAnimConfig"))
local PresentationConfig=require(RS:WaitForChild("MovementPresentationConfig"))
local freefallTime = {}
local function setCrouching(p, value)
    local c=p.Character
    local r=c and c:FindFirstChild("HumanoidRootPart")
    local h=c and c:FindFirstChildOfClass("Humanoid")
    if r then r:SetAttribute("IsCrouching", value) end
    if h then h:SetStateEnabled(Enum.HumanoidStateType.Jumping, not value) end
end

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
local lastSpeedHumanoidByUid = {}
local function applyWalkSpeed(p)
    local d=EnergyData.get(p) if not d or d.isBlocked then return end
    local h=p.Character and p.Character:FindFirstChildOfClass("Humanoid") if not h then return end
    if h.Health <= 0 then return end
    local base = Config.NORMAL_SPEED
    local root=p.Character:FindFirstChild("HumanoidRootPart")
    local crouching=root and root:GetAttribute("IsCrouching") == true
    p.Character:SetAttribute("IsSprinting", d.isSprintHeld == true and not d.isPanting and not crouching)
    if crouching then
        base = Config.CROUCH_SPEED
    elseif d.isPanting then
        base = Config.PANT_WALK_SPEED
    elseif d.isSprintHeld then
        base = Config.SPRINT_SPEED
    end
    local bonus = BuffService.GetSpeedBonusPct(p)
    -- Enchant slow is the last factor: it scales whatever the sprint/crouch/pant
    -- state and speed buffs already decided, rather than fighting them for
    -- ownership of WalkSpeed. Multiplier is 1 when not slowed. This function is
    -- event-driven, so connectCharacter also re-runs it when the slow attribute
    -- flips -- otherwise a slow landing mid-run wouldn't show until the next
    -- sprint/crouch/buff change, and wouldn't lift on expiry.
    h.WalkSpeed = base * (1 + bonus / 100) * CombatEnchantStatus.GetSpeedMultiplier(p.Character)
    -- Cache only a completed write, scoped to this Humanoid. A player can
    -- have energy data before their character exists, or keep the same
    -- buff total across respawns; neither means the new body has its speed.
    lastSpeedBonusByUid[p.UserId] = bonus
    lastSpeedHumanoidByUid[p.UserId] = h
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

-- Minecraft-style exhaustion from movement (2026-09-07 hunger rework). Tracks
-- each player's HumanoidRootPart position every Heartbeat and charges
-- walk/sprint/swim exhaustion per horizontal stud covered -- vertical motion
-- (falling, launches) doesn't count, matching "blocks traveled" in Minecraft.
-- Standing still contributes nothing, since a near-zero delta is skipped
-- entirely below.
local lastPositionByUid = {}

local function trackMovementExhaustion(p)
    local char = p.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then
        lastPositionByUid[p.UserId] = nil
        return
    end

    local pos = root.Position
    local last = lastPositionByUid[p.UserId]
    lastPositionByUid[p.UserId] = pos
    if not last then
        return -- first tick after spawn/zone-entry -- no delta to charge yet
    end

    local delta = pos - last
    local studs = Vector3.new(delta.X, 0, delta.Z).Magnitude
    if studs < 0.001 then
        return -- standing still: zero exhaustion, same as Minecraft
    end

    local cost
    if hum:GetState() == Enum.HumanoidStateType.Swimming then
        cost = HungerConfig.EXHAUSTION.SWIM_PER_STUD
    else
        local d = EnergyData.get(p)
        local sprinting = d and d.isSprintHeld and not d.isPanting
        cost = (sprinting and HungerConfig.EXHAUSTION.SPRINT_PER_STUD) or HungerConfig.EXHAUSTION.WALK_PER_STUD
    end
    HungerData.addExhaustion(p, cost * studs)
end

-- Initialize movement on every body, including a character already present
-- when this service starts. Sprint input from the old body must not carry over.
local function connectCharacter(p, character)
    if p.Character ~= character then return end
    EnergyData.setSprintHeld(p, false)
    character:SetAttribute("IsSprinting", false)
    freefallTime[p.UserId] = 0
    lastSpeedBonusByUid[p.UserId] = nil
    lastSpeedHumanoidByUid[p.UserId] = nil
    lastPositionByUid[p.UserId] = nil
    character:WaitForChild("HumanoidRootPart", 5)
    local hum = character:WaitForChild("Humanoid", 5)
    if not hum or p.Character ~= character or not p.Parent then
        return
    end
    setCrouching(p, false)
    applyWalkSpeed(p)
    character:GetAttributeChangedSignal("EnchantSlowed"):Connect(function()
        if p.Character ~= character then return end
        applyWalkSpeed(p)
    end)
    -- Jump exhaustion is connected once per Humanoid.
    hum.StateChanged:Connect(function(_, new)
        if p.Character ~= character then return end
        if new == Enum.HumanoidStateType.Dead or new == Enum.HumanoidStateType.Swimming
            or new == Enum.HumanoidStateType.Seated or new == Enum.HumanoidStateType.Climbing
            or new == Enum.HumanoidStateType.Physics then
            setCrouching(p, false)
            if new == Enum.HumanoidStateType.Dead then
                EnergyData.setSprintHeld(p, false)
                character:SetAttribute("IsSprinting", false)
            end
            applyWalkSpeed(p)
        end
        if new == Enum.HumanoidStateType.Jumping then
            HungerData.addExhaustion(p, HungerConfig.EXHAUSTION.JUMP)
        end
    end)
end

RunService.Heartbeat:Connect(function(dt)
    local now=tick()
    for _,p in ipairs(Players:GetPlayers()) do
        if not ZoneService.IsPlayerInSafeZone(p) then
            trackMovementExhaustion(p)
        else
            -- Reset so re-entering the wild doesn't credit a huge
            -- teleport-distance jump in exhaustion on the first tick back.
            lastPositionByUid[p.UserId] = nil
        end
        HungerData.enforceSprintGate(p)
        local d=EnergyData.get(p) if not d then continue end
        EnergyData.applyTick(p,dt)
        if d.isBlocked then continue end
        local ev=p:FindFirstChild("Energy") if ev then ev.Value=d.energy end
        -- Refresh WalkSpeed when this player's active speed-buff total changes
        -- or a new Humanoid arrives. Failed early attempts never fill the cache.
        local curBonus = BuffService.GetSpeedBonusPct(p)
        local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
        local character=p.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local crouching=root and root:GetAttribute("IsCrouching") == true
        freefallTime[p.UserId] = hum and hum:GetState() == Enum.HumanoidStateType.Freefall
            and ((freefallTime[p.UserId] or 0) + dt) or 0
        if crouching and freefallTime[p.UserId] >= PresentationConfig.CrouchFreefallTime then
            setCrouching(p, false)
            applyWalkSpeed(p)
            crouching=false
        end
        local expectedSprint=d.isSprintHeld == true and not d.isPanting and not crouching
        if lastSpeedBonusByUid[p.UserId] ~= curBonus or lastSpeedHumanoidByUid[p.UserId] ~= hum
            or (character and character:GetAttribute("IsSprinting") ~= expectedSprint) then
            applyWalkSpeed(p)
        end
        if now-d.lastSent>=SEND_RATE then EnergyChanged:FireClient(p,d.energy,d.isPanting == true) d.lastSent=now end
    end
end)
RequestSprint.OnServerEvent:Connect(function(p,isHeld)
    if type(isHeld) ~= "boolean" then return end
    local h=p.Character and p.Character:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return end
    -- Shift always stands up, even when energy/hunger refuses sprint.
    if isHeld then setCrouching(p, false) end
    local accepted=isHeld and not EnergyData.isBlocked(p) and not EnergyData.isPanting(p) and HungerData.canSprint(p)
    EnergyData.setSprintHeld(p, accepted == true)
    applyWalkSpeed(p)
end)
RequestCrouch.OnServerEvent:Connect(function(p,wantCrouch)
    if type(wantCrouch) ~= "boolean" then return end
    local h=p.Character and p.Character:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return end
    if wantCrouch then
        -- Remain safely disabled until the exported clips have published IDs.
        if not Profiles.CrouchReady() or CombatAnimations.CROUCH_SWING_ANIM_ID == "" then return end
        local state=h:GetState()
        if EnergyData.isBlocked(p) or h.Sit or h.PlatformStand or h.FloorMaterial == Enum.Material.Air
            or (state ~= Enum.HumanoidStateType.Running and state ~= Enum.HumanoidStateType.Landed
                and state ~= Enum.HumanoidStateType.RunningNoPhysics) then return end
        EnergyData.setSprintHeld(p, false)
    end
    setCrouching(p, wantCrouch)
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
    p.CharacterAdded:Connect(function(character)
        connectCharacter(p, character)
    end)
    if p.Character then
        connectCharacter(p, p.Character)
    end
    print("[EnergyServer] "..p.Name.." ready (energy + hunger)")
end
Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(function(p)
    lastSpeedBonusByUid[p.UserId] = nil
    lastSpeedHumanoidByUid[p.UserId] = nil
    lastPositionByUid[p.UserId] = nil
    freefallTime[p.UserId] = nil
    EnergyData.remove(p)
    HungerData.remove(p)
end)
for _,p in ipairs(Players:GetPlayers()) do initPlayer(p) end
