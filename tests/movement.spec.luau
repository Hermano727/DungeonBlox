return function(sources)
    local count=0
    local function check(v, label) assert(v,label); count+=1 end
    local function signal()
        local callbacks={}
        return {Connect=function(_,fn) callbacks[fn]=true; return {Disconnect=function() callbacks[fn]=nil end} end,
            Fire=function(_,...) for fn in pairs(callbacks) do fn(...) end end}
    end
    local config=assert(loadstring(sources.MovementPresentationConfig))()
    local chunk=assert(loadstring(sources.MovementPresentationMath))
    setfenv(chunk,setmetatable({script={Parent={WaitForChild=function(_,n) return n end}},require=function() return config end},{__index=getfenv()}))
    local motion=chunk()
    local function simulate(hz)
        local state=motion.New()
        for _=1,hz do motion.Step(state,1/hz,0.6,0.8,true,false,false,false) end
        return state
    end
    local a,b=simulate(30),simulate(144)
    check(math.abs(a.Side-b.Side)<1e-8 and math.abs(a.Yaw-b.Yaw)<1e-8,"frame-rate independent steady smoothing")
    local s=motion.New()
    motion.Step(s,.016,1,0,true,true,false,false)
    check(s.Burst>0 and s.Burst<=1,"accepted sprint movement triggers burst")
    for _=1,120 do motion.Step(s,1/60,1,0,true,true,false,false) end
    check(s.Burst<1e-6,"held sprint does not retrigger burst")
    motion.Step(s,1,1,1,false,true,false,false)
    check(math.abs(s.Forward)<.00001 and math.abs(s.Side)<.00001 and s.Burst==0,"airborne effects fade")
    motion.Step(s,1,1,1,true,true,true,false)
    check(not s.Sprinting and s.Forward<config.ForwardLean*.36,"crouch reduces lean and suppresses burst")
    motion.Step(s,1,1,1,true,false,false,true)
    check(math.abs(s.Forward)<.00001,"attacks suppress bone offsets")
    motion.Step(s,1,0,0,true,true,false,false)
    check(not s.Sprinting and math.abs(s.Side)<.00001,"stationary character stays neutral")
    check(motion.LandingStrength(0)==0 and motion.LandingStrength(4)==0,"tiny contacts do not shake")
    check(motion.LandingStrength(35)==1 and motion.LandingStrength(200)==1,"landing impulse is bounded")
    check(motion.LandingStrength(20)==.5,"landing impulse scales with approach speed")

    -- Exercise the actual controller's restore/lifecycle behavior. Scalar
    -- transforms model composition, not skeletal axes or Roblox evaluation.
    do
        local cv={}
        local function cf(v) return setmetatable({value=v},cv) end
        cv.__index=function(t,k)
            if k=="Rotation" then return t end
            if k=="Inverse" then return function() return cf(-t.value) end end
            if k=="VectorToObjectSpace" then return function(_,v) return v end end
        end
        cv.__mul=function(x,y) return cf(x.value+y.value) end
        local vv={}
        local function vec(x,y,z) return setmetatable({X=x,Y=y,Z=z},vv) end
        vv.__sub=function(x,y) return vec(x.X-y.X,x.Y-y.Y,x.Z-y.Z) end
        vv.__index=function(t,k) if k=="Magnitude" then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z) end end
        local zero=vec(0,0,0)
        local bones={}
        for _,n in ipairs({"Pelvis","Spine_01","Spine_02","Neck","Thigh_L","Thigh_R"}) do
            bones[n]={Parent=true,Transform=cf(.1),TransformedWorldCFrame=cf(0),IsA=function(_,c) return c=="Bone" end}
        end
        local mesh={FindFirstChild=function(_,n) return bones[n] end}
        local root={Parent=true,CFrame=cf(0),Position=zero,AssemblyLinearVelocity=vec(6,0,-8),
            GetAttribute=function() return false end}
        local animator={GetPlayingAnimationTracks=function() return {} end}
        local hum={Health=100,WalkSpeed=10,FindFirstChildOfClass=function() return animator end}
        local char={Parent=true,GetAttribute=function(_,n) return n=="GroundingCalibrated" end,
            FindFirstChild=function(_,n) return n=="HumanoidRootPart" and root or mesh end,
            FindFirstChildOfClass=function() return hum end}
        local player={Character=char}
        local players={LocalPlayer=player,GetPlayers=function() return {player} end}
        local run={Heartbeat=signal(),PreAnimation=signal(),PreSimulation=signal()}
        local destroy=signal()
        local ground={Character=char,Grounded=true,SurfaceVelocity=zero}
        local modules={MovementPresentationConfig=config,MovementPresentationMath=motion,
            CharacterGrounding={SampleInterval=.05,NewRaycastParams=function() return {} end},
            CharacterGroundState={GetState=function() return ground end}}
        local node={WaitForChild=function(_,n) return n end}
        local services={Players=players,RunService=run,ReplicatedStorage=node}
        local environment=setmetatable({
            game={GetService=function(_,n) return services[n] end},script={Parent=node,Destroying=destroy},
            require=function(n) return modules[n] end,Vector3={zero=zero},
            CFrame={Angles=function(x,y,z) return cf(x+y+z) end},Enum={AnimationPriority={Action={Value=2}}},
        },{__index=getfenv()})
        local runChunk=assert(loadstring(sources.Presentation));setfenv(runChunk,environment)
        local controller=runChunk();run.Heartbeat:Fire(.051)
        run.PreSimulation:Fire(.016)
        check(math.abs(bones.Spine_01.Transform.value-.1)>.0001,"controller adds offsets to animated pose")
        run.PreAnimation:Fire()
        check(math.abs(bones.Spine_01.Transform.value-.1)<1e-10,"before animation restores base pose")
        for _=1,600 do run.PreSimulation:Fire(1/60) end
        check(math.abs(bones.Spine_01.Transform.value)<.5,"skipped animation and repeated simulation cannot accumulate offsets")
        root.Position=vec(200,0,0)
        -- A second local root places this observed character beyond the range.
        players.LocalPlayer={Character={FindFirstChild=function() return {Position=zero} end}}
        run.PreSimulation:Fire(.016)
        check(math.abs(bones.Spine_01.Transform.value-.1)<1e-10,"out-of-range restores base pose")
        players.LocalPlayer=player;root.Position=zero;run.Heartbeat:Fire(.051);run.PreSimulation:Fire(.016)
        player.Character=nil;run.Heartbeat:Fire(.051)
        check(controller.GetLocalMotion()==nil and math.abs(bones.Spine_01.Transform.value-.1)<1e-10,"character removal restores pose and clears owner")
        player.Character=char;run.Heartbeat:Fire(.051);run.PreSimulation:Fire(.016);destroy:Fire()
        run.PreSimulation:Fire(.1)
        check(math.abs(bones.Spine_01.Transform.value-.1)<1e-10,"destroy disconnects simulation writers")
    end

    -- Execute the real server with service doubles; no engine physics is simulated.
    local stateNames={}
    for _,n in ipairs({"Running","RunningNoPhysics","Landed","Freefall","Jumping","Swimming","Seated","Climbing","Physics","Dead"}) do stateNames[n]=n end
    local attrs,rootAttrs={},{}
    local root={GetAttribute=function(_,k) return rootAttrs[k] end,SetAttribute=function(_,k,v) rootAttrs[k]=v end}
    local hum={Health=100,FloorMaterial="Grass",State="Running",Sit=false,PlatformStand=false,StateChanged=signal(),jumpEnabled=true,
        GetState=function(h) return h.State end,SetStateEnabled=function(h,_,v) h.jumpEnabled=v end}
    local character={Parent=true,FindFirstChild=function(_,n) return n=="HumanoidRootPart" and root or nil end,
        FindFirstChildOfClass=function() return hum end,WaitForChild=function(_,n) return n=="Humanoid" and hum or root end,
        GetAttribute=function(_,k) return attrs[k] end,SetAttribute=function(_,k,v) attrs[k]=v end}
    local player={UserId=1,Name="Test",Character=character,Parent=true,CharacterAdded=signal(),
        FindFirstChild=function() return nil end,SetAttribute=function() end}
    local players={PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function() return {player} end}
    local heartbeat=signal()
    local sprint={OnServerEvent=signal()}; local crouch={OnServerEvent=signal()}
    local energyChanged={FireClient=function() end}
    local dash={IsA=function() return true end}
    local ee={WaitForChild=function(_,n) return ({RequestSprint=sprint,RequestCrouch=crouch,EnergyChanged=energyChanged})[n] end,
        FindFirstChild=function() return dash end}
    local energy={energy=100,lastSent=0,isSprintHeld=false,isPanting=false,isBlocked=false}
    local ready,canSprint,bonus=true,true,0
    local modules={
        EnergyConfig={NORMAL_SPEED=9.6,SPRINT_SPEED=14.4,CROUCH_SPEED=8,PANT_WALK_SPEED=8},
        CharacterAnimProfiles={CrouchReady=function() return ready end},
        CombatAnimConfig={CROUCH_SWING_ANIM_ID="published-test"},
        MovementPresentationConfig=config,
        HungerConfig={EXHAUSTION={JUMP=1}},
        BuffService={GetSpeedBonusPct=function() return bonus end},
        ZoneService={IsPlayerInSafeZone=function() return true end},
        PlayerStateEnum={LOW_ENERGY="LOW_ENERGY",IDLE="IDLE"},
        EnergyData={init=function() end,get=function() return energy end,setSprintHeld=function(_,v) energy.isSprintHeld=v end,
            isBlocked=function() return energy.isBlocked end,isPanting=function() return energy.isPanting end,
            setBlocked=function(_,v) energy.isBlocked=v end,applyTick=function() end,remove=function() end},
        HungerData={init=function() end,enforceSprintGate=function() if not canSprint then energy.isSprintHeld=false end end,
            canSprint=function() return canSprint end,addExhaustion=function() end,remove=function() end},
    }
    local rs={WaitForChild=function(_,n) if n=="EnergyEvents" then return ee elseif n=="StateChangedBindable" then return {Event=signal()} else return n end end}
    local sss={WaitForChild=function(_,n) if n=="TransitionPlayerState" or n=="GetPlayerState" then return {Invoke=function() return "IDLE" end} else return n end end}
    local services={Players=players,RunService={Heartbeat=heartbeat},ReplicatedStorage=rs,ServerScriptService=sss}
    local env=setmetatable({game={GetService=function(_,n) return assert(services[n],n) end},
        require=function(n) return assert(modules[n],n) end,
        Enum={HumanoidStateType=stateNames,Material={Air="Air"}},tick=function() return 1 end,
        task={spawn=function(f,...) f(...) end},print=function() end},{__index=getfenv()})
    chunk=assert(loadstring(sources.Server));setfenv(chunk,env);chunk()
    check(hum.WalkSpeed==9.6 and attrs.IsSprinting==false and rootAttrs.IsCrouching==false,"spawn initializes normal movement")
    sprint.OnServerEvent:Fire(player,true)
    check(hum.WalkSpeed==14.4 and attrs.IsSprinting,"sprint is server accepted")
    crouch.OnServerEvent:Fire(player,true)
    check(hum.WalkSpeed==8 and rootAttrs.IsCrouching and not energy.isSprintHeld and not attrs.IsSprinting,"crouch cancels sprint")
    check(not hum.jumpEnabled,"jump disabled while crouched")
    bonus=25;heartbeat:Fire(.05)
    check(hum.WalkSpeed==10 and rootAttrs.IsCrouching,"buff recalculation retains crouch speed")
    bonus=0;sprint.OnServerEvent:Fire(player,true)
    check(hum.WalkSpeed==14.4 and not rootAttrs.IsCrouching and hum.jumpEnabled,"Shift stands and sprints")
    crouch.OnServerEvent:Fire(player,true);canSprint=false;sprint.OnServerEvent:Fire(player,true)
    check(not rootAttrs.IsCrouching and not attrs.IsSprinting and hum.WalkSpeed==9.6,"denied sprint still stands safely")
    canSprint=true;sprint.OnServerEvent:Fire(player,true);canSprint=false;heartbeat:Fire(.05)
    check(not attrs.IsSprinting and hum.WalkSpeed==9.6,"hunger cancellation refreshes speed and presentation")
    energy.isPanting=true;crouch.OnServerEvent:Fire(player,true)
    check(rootAttrs.IsCrouching,"panting does not prevent crouch")
    crouch.OnServerEvent:Fire(player,false)
    check(hum.WalkSpeed==8,"standing preserves panting speed")
    energy.isPanting=false;hum.FloorMaterial="Air";crouch.OnServerEvent:Fire(player,true)
    check(not rootAttrs.IsCrouching,"airborne crouch rejected")
    hum.FloorMaterial="Grass";ready=false;crouch.OnServerEvent:Fire(player,true)
    check(not rootAttrs.IsCrouching,"missing published clips gate crouch")
    ready=true;crouch.OnServerEvent:Fire(player,true);hum.State="Freefall";heartbeat:Fire(.2)
    check(rootAttrs.IsCrouching,"brief contact loss preserves crouch")
    heartbeat:Fire(.2)
    check(not rootAttrs.IsCrouching and hum.jumpEnabled,"sustained freefall exits crouch")
    hum.State="Running";crouch.OnServerEvent:Fire(player,true);hum.StateChanged:Fire("Running","Swimming")
    check(not rootAttrs.IsCrouching,"swimming exits crouch")
    crouch.OnServerEvent:Fire(player,"bad");sprint.OnServerEvent:Fire(player,{})
    check(not rootAttrs.IsCrouching and not attrs.IsSprinting,"invalid remote values ignored")
    canSprint=true;sprint.OnServerEvent:Fire(player,true);player.CharacterAdded:Fire(character)
    check(hum.WalkSpeed==9.6 and not attrs.IsSprinting and not rootAttrs.IsCrouching,"respawn clears stance and sprint")
    print(string.format("PASS: %d movement checks",count))
end
