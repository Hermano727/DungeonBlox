-- Executes production modules with small engine doubles. No gameplay simulation.
return function(sources)
    local count = 0
    local function check(value, label)
        assert(value, label)
        count += 1
    end
    local function near(a, b) return math.abs(a - b) < 0.0001 end
    local V = {}
    local function vec(x,y,z) return setmetatable({X=x,Y=y,Z=z},V) end
    V.__index = function(v,k)
        if k == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
        if k == "Dot" then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
    end
    V.__add = function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
    V.__sub = function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
    V.__mul = function(a,n) return vec(a.X*n,a.Y*n,a.Z*n) end
    local zero = vec(0,0,0)
    local up = vec(0,1,0)
    local function signal()
        local callbacks = {}
        local s = {}
        function s:Connect(fn)
            callbacks[fn] = true
            return {Disconnect=function() callbacks[fn]=nil end}
        end
        function s:Fire(...)
            for fn in pairs(callbacks) do fn(...) end
        end
        function s:Count() local n=0 for _ in pairs(callbacks) do n+=1 end return n end
        return s
    end
    local states = {}
    for _,name in ipairs({"Running","RunningNoPhysics","Landed","Jumping","Freefall","Dead","Swimming","Seated","Climbing","Physics"}) do states[name]=name end
    local materials = {Air="Air",Grass="Grass",Concrete="Concrete"}
    local heartbeat = signal()
    local rayHit, rayCalls, lastParams, rayLength = nil, 0, nil, 0
    local world = {Raycast=function(_,origin,direction,params)
        rayCalls+=1 lastParams=params rayLength=direction.Magnitude
        if rayHit and rayHit.Distance <= direction.Magnitude then return rayHit end
        return nil
    end}
    local player = {CharacterAdded=signal(),CharacterRemoving=signal()}
    local players = {LocalPlayer=player,PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function() return {player} end}
    local node = {WaitForChild=function(_,name) return name end}
    local services = {Players=players,RunService={Heartbeat=heartbeat},ReplicatedStorage=node}
    local env = setmetatable({
        Enum={HumanoidStateType=states,HumanoidRigType={R15="R15"},Material=materials,RaycastFilterType={Exclude="Exclude"}},
        Vector3={new=vec,zero=zero},RaycastParams={new=function() return {} end},
        workspace=world,game={GetService=function(_,name) return assert(services[name],name) end},
        script={Parent=node},task={spawn=function(fn,...) fn(...) end},
        warn=function(message) error(message) end,
        Instance={new=function(class)
            assert(class=="BindableEvent")
            local event=signal()
            return {Event=event,Fire=function(_,...) event:Fire(...) end}
        end},
    },{__index=getfenv()})
    local modules={}
    local function execute(name)
        local chunk=assert(loadstring(sources[name],name))
        setfenv(chunk,env)
        return chunk()
    end
    env.require=function(name)
        if not modules[name] then modules[name]=execute(name) end
        return modules[name]
    end
    local function newCharacter()
        local root={Size=vec(2,2,1),Position=vec(0,20,0),AssemblyLinearVelocity=zero,CollisionGroup="Default",IsA=function(_,c) return c=="BasePart" end}
        root.CFrame={UpVector=up,ToObjectSpace=function(_,cf) return cf end}
        local bone={IsA=function(_,c) return c=="Bone" end}
        local mesh={Size=vec(4.4,5,1),CFrame={Position=vec(0,1.5,0),RightVector=vec(1,0,0),UpVector=up,LookVector=vec(0,0,-1)},
            IsA=function(_,c) return c=="MeshPart" end,FindFirstChild=function(_,name) return name=="Root" and bone or nil end}
        -- Model Position's documented single-part behavior. These doubles do
        -- not simulate the physics solver or network replication of welds.
        local function trackPosition(part)
            part.PositionWrites=0
            return setmetatable(part,{
                __index=function(t,key)
                    if key=="Position" then return root.Position+t.CFrame.Position end
                end,
                __newindex=function(t,key,value)
                    if key=="Position" then
                        t.CFrame.Position=value-root.Position
                        t.PositionWrites+=1
                    else rawset(t,key,value) end
                end,
            })
        end
        trackPosition(mesh)
        local head=trackPosition({CFrame={Position=vec(0,3.5,0)},IsA=function(_,c) return c=="BasePart" end})
        mesh.WaitForChild=mesh.FindFirstChild
        local hum={HipHeight=1,AutomaticScalingEnabled=true,RigType="R15",Health=100,Sit=false,PlatformStand=false,FloorMaterial=materials.Grass,State=states.Running,
            IsA=function(_,c) return c=="Humanoid" end,GetState=function(h) return h.State end}
        local attributes={}
        local children={Hero_Character=mesh,HumanoidRootPart=root,Humanoid=hum,Head=head}
        local char={Name="Player",Parent=world,
            FindFirstChild=function(_,name) return children[name] end,
            FindFirstChildOfClass=function(_,name) return name=="Humanoid" and hum or nil end,
            SetAttribute=function(_,key,value) attributes[key]=value end,
            GetAttribute=function(_,key) return attributes[key] end,
        }
        char.WaitForChild=char.FindFirstChild
        return char,root,mesh,hum,children
    end
    local core=env.require("CharacterGrounding")
    local char,root,mesh,hum,children=newCharacter()
    local measurement=core.MeasureRig(char)
    check(near(measurement.HipHeight,1) and near(measurement.RootToSole,1) and near(measurement.VisualOffsetY,-1),"retain native clearance and lower visuals")
    children.Sword={Size=vec(100,100,100)} children.Armor={Size=vec(100,100,100)}
    check(core.MeasureRig(char).VisualOffsetY==-1,"equipment does not enter body measurement")
    -- Translation and yaw are removed by ToObjectSpace; only root-local body bounds enter the calculation.
    mesh.Size=vec(8.8,10,2) mesh.CFrame.Position=vec(0,3,0) root.Size=vec(4,4,2)
    check(core.MeasureRig(char).RootToSole==2 and core.MeasureRig(char).HipHeight==1,"larger rig still retains positive clearance")
    mesh.Size=vec(4.4,5,1) mesh.CFrame.Position=vec(0,1.5,0) root.Size=vec(2,1,1)
    check(core.MeasureRig(char).HipHeight==1 and core.MeasureRig(char).VisualOffsetY==-0.5,"root half-height subtracted exactly once")
    root.Size=vec(2,3,1)
    check(core.MeasureRig(char)==nil,"incompatible collider is reported rather than silently sinking feet")
    root.Size=vec(2,2,1)
    children.Hero_Character=nil
    check(core.MeasureRig(char)==nil,"non-custom rig ignored") children.Hero_Character=mesh

    -- A naturally taller support layout needs no visual correction.
    mesh.CFrame.Position=vec(0,-0.5,0)
    check(core.MeasureRig(char).HipHeight==2 and core.MeasureRig(char).VisualOffsetY==0,"sufficient clearance preserved")
    mesh.CFrame.Position=vec(0,1.5,0)
    local originalRootPosition,originalRootCFrame=root.Position,root.CFrame
    local eyeToBody=children.Head.Position-mesh.Position
    player.Character=char execute("Server")
    check(hum.HipHeight==1 and not hum.AutomaticScalingEnabled,"server restores native clearance")
    check(near(mesh.CFrame.Position.Y,0.5) and near(children.Head.CFrame.Position.Y,2.5),"body and helper lowered together")
    check(near((children.Head.Position-mesh.Position).Y,eyeToBody.Y),"camera-to-body height preserved")
    check(root.Position==originalRootPosition and root.CFrame==originalRootCFrame and root.AssemblyLinearVelocity==zero,"calibration leaves root transform and velocity unchanged")
    check(core.MeasureRig(char).VisualOffsetY==0 and near(core.MeasureRig(char).RootToSole,2),"corrected soles match native support plane")
    check(children.Sword.Size.Y==100 and children.Sword.Position==nil,"equipment is not repositioned")
    player.CharacterAdded:Fire(char)
    check(mesh.PositionWrites==1 and children.Head.PositionWrites==1,"duplicate character setup cannot accumulate offsets")
    check(char:GetAttribute("GroundingCalibrated") and char:GetAttribute("GroundingRootToSole")==2 and char:GetAttribute("GroundingVisualOffsetY")==-1,"readiness and measurements replicated")
    local char2,root2,mesh2,hum2=newCharacter()
    player.Character=char2 player.CharacterAdded:Fire(char2)
    check(hum2.HipHeight==1 and char2:GetAttribute("GroundingCalibrated"),"server calibrates respawn")

    local terrain={IsA=function(_,name) return name=="Terrain" or name=="BasePart" end,
        GetVelocityAtPosition=function() error("Terrain has no platform velocity") end}
    rayHit={Instance=terrain,Distance=2,Position=vec(0,18,0),Normal=up,Material=materials.Grass}
    local params=core.NewRaycastParams(char)
    local sample=core.Sample(char,hum,root,params)
    check(sample.Grounded and sample.Instance==terrain and sample.Material==materials.Grass,"native terrain contact retained")
    check(sample.SurfaceVelocity==zero and sample.Normal==up,"terrain has normal and zero surface velocity")
    check(table.isfrozen(sample),"snapshot is read-only")
    check(lastParams.RespectCanCollide and lastParams.IgnoreWater and lastParams.FilterDescendantsInstances[1]==char,"probe filters")
    check(near(rayLength,2.35),"probe limited to support clearance plus tolerance")
    local platform={IsA=function(_,name) return name=="BasePart" end,GetVelocityAtPosition=function() return vec(2,3,0) end}
    rayHit.Instance=platform rayHit.Material=materials.Concrete root.AssemblyLinearVelocity=vec(5,3,0)
    sample=core.Sample(char,hum,root,params)
    check(sample.RelativeVelocity.X==3 and sample.RelativeVelocity.Y==0,"moving platform-relative velocity")
    rayHit.Distance=8 check(not core.Sample(char,hum,root,params).Grounded,"distant floor is not support") rayHit.Distance=2
    for _,state in ipairs({states.Jumping,states.Freefall,states.Swimming,states.Seated,states.Dead}) do
        hum.State=state
        check(not core.Sample(char,hum,root,params).Grounded,"nearby terrain cannot ground "..state)
    end
    hum.State=states.Running hum.FloorMaterial=materials.Air
    check(not core.Sample(char,hum,root,params).Grounded,"ray alone cannot ground an airborne Humanoid")
    hum.FloorMaterial=materials.Grass

    local tracker=core.NewTracker()
    local function tickState(state,velocity)
        hum.State=state root.AssemblyLinearVelocity=velocity or zero
        return tracker:Update(core.Sample(char,hum,root,params))
    end
    local _,impact=tickState(states.Freefall,vec(0,-20,0))
    _,impact=tickState(states.Running)
    check(impact==nil,"initial spawn fall is not a landing effect")
    tickState(states.Jumping,vec(0,10,0)) tickState(states.Freefall,vec(0,-12,0))
    local changed
    changed,impact=tickState(states.Landed)
    check(changed and impact==15,"landing speed accounts for upward platform velocity")
    _,impact=tickState(states.Running)
    check(impact==nil,"one landing per airborne transition")
    for _,state in ipairs({states.Seated,states.Swimming,states.Dead,states.Physics}) do
        tickState(states.Freefall,vec(0,-20,0)) tickState(state)
        _,impact=tickState(states.Running)
        check(impact==nil,"no false landing after "..state)
    end
    tickState(states.Freefall,vec(0,-6,0)) _,impact=tickState(states.Running)
    check(impact==9,"walking off a ledge also arms landing")

    player.Character=char2
    local owner=env.require("CharacterGroundState")
    execute("Bootstrap")
    local landed=0
    owner.Landed:Connect(function() landed+=1 end)
    rayCalls=0 heartbeat:Fire(.02) heartbeat:Fire(.02)
    check(rayCalls==0,"20Hz sampler waits for interval")
    heartbeat:Fire(.02) check(rayCalls==1 and owner.GetState().Character==char2,"one local sampler")
    heartbeat:Fire(.5) check(rayCalls==2,"long frames do not cause catch-up ray bursts")
    hum2.State=states.Freefall root2.AssemblyLinearVelocity=vec(0,-5,0) heartbeat:Fire(.051)
    hum2.State=states.Running heartbeat:Fire(.051) heartbeat:Fire(.051)
    check(landed==1,"public Landed signal fires once")
    player.CharacterRemoving:Fire(char2)
    check(heartbeat:Count()==0 and owner.GetState()==nil,"character removal detaches sampler and clears state")
    local char3,_,_,hum3=newCharacter()
    player.Character=char3 player.CharacterAdded:Fire(char3)
    heartbeat:Fire(.051)
    check(hum3.HipHeight==1 and heartbeat:Count()==1 and owner.GetState().Character==char3,"respawn reconnects exactly once")
    check(landed==1,"respawn does not emit landing")
    owner.Start(char3) check(heartbeat:Count()==1,"duplicate starts are idempotent")
    owner.Stop()
    local char4=newCharacter() owner.Start(char4)
    rayCalls=0 heartbeat:Fire(.051)
    check(rayCalls==0 and owner.GetState()==nil,"wait for server calibration before sampling")
    char4.Parent=nil heartbeat:Fire(.051)
    check(heartbeat:Count()==0,"removed character cleans itself up")
    check(mesh2.PositionWrites==1 and root2.Position.Y==20,"sampling never adjusts character positions")
    owner.Stop() players.PlayerRemoving:Fire(player)
    print(string.format("PASS: %d grounding checks",count))
end
