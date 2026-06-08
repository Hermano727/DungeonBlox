-- DevClient: F9 spawner placement tool (dev-only)
local Players=game:GetService("Players");local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService");local RunService=game:GetService("RunService")
local player=Players.LocalPlayer;local mouse=player:GetMouse()
local playerGui=player:WaitForChild("PlayerGui")
local MenuMouse=require(RS:WaitForChild("CursorUtils"))
local DEV_USERIDS={}
local function isDev()
    for _,id in ipairs(DEV_USERIDS) do if player.UserId==id then return true end end
    return RunService:IsStudio()
end
if not isDev() then return end
local GE=RS:WaitForChild("GameEvents",15)
local evPlace=GE and GE:WaitForChild("DevPlaceSpawner",10)
local evDelete=GE and GE:WaitForChild("DevDeleteSpawner",10)
local rfList=GE and GE:WaitForChild("DevListSpawners",10)
local MobData=require(RS:WaitForChild("MobData"))
local NPCRegistry=require(RS:WaitForChild("NPCRegistry"))
local ZoneConfig=require(RS:WaitForChild("ZoneConfig"))
local MOB_IDS={}
for t=1,5 do local tb=MobData[t];if type(tb)=="table" then for id in pairs(tb) do table.insert(MOB_IDS,id) end end end
table.sort(MOB_IDS)
local NPC_TYPES={}
for k in pairs(NPCRegistry.Types) do table.insert(NPC_TYPES,k) end
table.sort(NPC_TYPES)
local panelOpen,placingMode,mode,mobIdx,npcIdx=false,false,"Mob",1,1
-- Zone placement state (read by ghost + place handler).
local zoneAlignment="Lawful"
local zoneBanned={Lawful=false,Neutral=false,Chaotic=false}
local zoneRadiusDefault=tostring(ZoneConfig.DEFAULT_RADIUS)
local ghost=Instance.new("Part");ghost.Name="DevPlacerGhost";ghost.Anchored=true
ghost.CanCollide=false;ghost.CanQuery=false;ghost.CanTouch=false;ghost.CastShadow=false
ghost.Transparency=0.55;ghost.Shape=Enum.PartType.Cylinder;ghost.Material=Enum.Material.Neon
ghost.Size=Vector3.new(1,10,10);ghost.CFrame=CFrame.new(0,-500,0);ghost.Parent=workspace
local function updateGhost(r)
    if mode=="Mob" then ghost.Color=Color3.fromRGB(220,60,60)
        local d=math.clamp((r or 100)*2,4,200);ghost.Size=Vector3.new(1,d,d)
    elseif mode=="Zone" then
        ghost.Color=ZoneConfig.ALIGNMENT_COLORS[zoneAlignment] or Color3.fromRGB(200,200,200)
        -- Cylinder size: X is height (after the 90° rotation it becomes vertical),
        -- Y/Z are diameter. Clamp diameter to keep the ghost from being absurdly huge.
        local rad=math.clamp(tonumber(r) or ZoneConfig.DEFAULT_RADIUS, ZoneConfig.MIN_RADIUS, ZoneConfig.MAX_RADIUS)
        local d=rad*2
        ghost.Size=Vector3.new(1,d,d)
    else ghost.Color=Color3.fromRGB(60,140,220);ghost.Size=Vector3.new(1,6,6) end
end
RunService.Heartbeat:Connect(function()
    if not placingMode then ghost.CFrame=CFrame.new(0,-500,0);return end
    ghost.CFrame=CFrame.new(mouse.Hit.Position+Vector3.new(0,.5,0))*CFrame.Angles(0,0,math.rad(90))
end)
local W,H=262,432
local DARK=Color3.fromRGB(20,15,15);local ACC=Color3.fromRGB(90,70,70);local GOLD=Color3.fromRGB(255,215,100)
local sg=Instance.new("ScreenGui");sg.Name="DevPlacerUI";sg.ResetOnSpawn=false
sg.IgnoreGuiInset=true;sg.DisplayOrder=200;sg.Enabled=false
sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;sg.Parent=playerGui
local pnl=Instance.new("Frame",sg);pnl.AnchorPoint=Vector2.new(0,.5)
pnl.Position=UDim2.new(0,8,.5,0);pnl.Size=UDim2.fromOffset(W,H)
pnl.BackgroundColor3=DARK;pnl.BorderSizePixel=0;pnl.ZIndex=2
Instance.new("UICorner",pnl).CornerRadius=UDim.new(0,10)
local sk=Instance.new("UIStroke",pnl);sk.Thickness=1;sk.Color=ACC
local function lbl(p,tx,x,y,w,h,sz,col,bold,xa)
    local l=Instance.new("TextLabel",p);l.BackgroundTransparency=1
    l.Position=UDim2.fromOffset(x,y);l.Size=UDim2.fromOffset(w,h)
    l.Font=bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
    l.TextSize=sz or 13;l.TextColor3=col or Color3.new(1,1,1)
    l.TextXAlignment=xa or Enum.TextXAlignment.Left;l.Text=tx;l.ZIndex=3;return l
end
local function mkB(p,tx,x,y,w,h,bg)
    local b=Instance.new("TextButton",p);b.Position=UDim2.fromOffset(x,y)
    b.Size=UDim2.fromOffset(w,h);b.BackgroundColor3=bg or Color3.fromRGB(55,40,40)
    b.BorderSizePixel=0;b.Font=Enum.Font.GothamBold;b.TextSize=13
    b.TextColor3=Color3.new(1,1,1);b.Text=tx;b.ZIndex=4
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6);return b
end
local function mkI(p,ph,x,y,w,h,def)
    local b=Instance.new("TextBox",p);b.Position=UDim2.fromOffset(x,y)
    b.Size=UDim2.fromOffset(w,h);b.BackgroundColor3=Color3.fromRGB(14,10,10)
    b.BorderSizePixel=0;b.Font=Enum.Font.GothamMedium;b.TextSize=13
    b.TextColor3=Color3.new(1,1,1);b.PlaceholderText=ph
    b.PlaceholderColor3=Color3.fromRGB(100,85,85);b.ClearTextOnFocus=false
    b.Text=def or "";b.ZIndex=4;Instance.new("UICorner",b).CornerRadius=UDim.new(0,5)
    local s=Instance.new("UIStroke",b);s.Thickness=1;s.Color=ACC;return b
end
local function div(y) local d=Instance.new("Frame",pnl)
    d.Size=UDim2.fromOffset(W-16,1);d.Position=UDim2.fromOffset(8,y)
    d.BackgroundColor3=ACC;d.BorderSizePixel=0 end
lbl(pnl,"DevPlacer",12,9,W-52,26,16,GOLD,true)
local closeX=mkB(pnl,"X",W-36,8,28,28,Color3.fromRGB(70,30,30))
lbl(pnl,"MODE",12,48,50,16,11,ACC,true)
local btnMob=mkB(pnl,"MOB",54,44,60,26);local btnNpc=mkB(pnl,"NPC",118,44,60,26);local btnZone=mkB(pnl,"ZONE",182,44,60,26)
div(76)
local mobSec=Instance.new("Frame",pnl);mobSec.Position=UDim2.fromOffset(0,82)
mobSec.Size=UDim2.fromOffset(W,170);mobSec.BackgroundTransparency=1
lbl(mobSec,"MOB TYPE",12,2,80,16,11,ACC,true)
local mobPrev=mkB(mobSec,"<",12,20,24,26)
local mobNext=mkB(mobSec,">",W-34,20,24,26)
local mobDisp=lbl(mobSec,MOB_IDS[1] or "-",40,20,W-72,26,13,Color3.new(1,1,1),false,Enum.TextXAlignment.Center)
lbl(mobSec,"COUNT",12,58,60,14,11,ACC,true)
local boxCount=mkI(mobSec,"3",12,74,58,28,"3")
lbl(mobSec,"DELAY(s)",80,58,80,14,11,ACC,true)
local boxDelay=mkI(mobSec,"10",80,74,68,28,"10")
lbl(mobSec,"ACT.RADIUS",12,112,100,14,11,ACC,true)
local boxRadius=mkI(mobSec,"100",12,128,78,28,"100")
lbl(mobSec,"ZONE",100,112,60,14,11,ACC,true)
local boxZone=mkI(mobSec,"Default",100,128,W-116,28,"Default")
local npcSec=Instance.new("Frame",pnl);npcSec.Position=UDim2.fromOffset(0,82)
npcSec.Size=UDim2.fromOffset(W,170);npcSec.BackgroundTransparency=1;npcSec.Visible=false
local zoneSec=Instance.new("Frame",pnl);zoneSec.Position=UDim2.fromOffset(0,82)
zoneSec.Size=UDim2.fromOffset(W,170);zoneSec.BackgroundTransparency=1;zoneSec.Visible=false
lbl(npcSec,"NPC TYPE",12,2,80,16,11,ACC,true)
local npcPrev=mkB(npcSec,"<",12,20,24,26)
local npcNext=mkB(npcSec,">",W-34,20,24,26)
local npcDisp=lbl(npcSec,NPC_TYPES[1] or "-",40,20,W-72,26,13,Color3.new(1,1,1),false,Enum.TextXAlignment.Center)
lbl(npcSec,"DISPLAY NAME",12,58,120,14,11,ACC,true)
local boxNpcName=mkI(npcSec,"e.g. The Merchant",12,74,W-24,28)
lbl(npcSec,"UNIQUE ID",12,112,100,14,11,ACC,true)
local boxNpcId=mkI(npcSec,"e.g. merchant_01",12,128,W-24,28)

-- Zone section: Name (left) + Radius (right) on row 1; alignment radio row 2;
-- banned-alignments toggle row 3.
lbl(zoneSec,"ZONE NAME",12,2,80,14,11,ACC,true)
lbl(zoneSec,"RADIUS",W-80,2,68,14,11,ACC,true)
local boxZoneName=mkI(zoneSec,"e.g. Stormhaven",12,18,W-100,28,"")
local boxZoneRadius=mkI(zoneSec,zoneRadiusDefault,W-80,18,68,28,zoneRadiusDefault)
lbl(zoneSec,"ALIGNMENT",12,54,100,14,11,ACC,true)
local btnAlnLaw=mkB(zoneSec,"LAWFUL",12,70,76,24)
local btnAlnNeu=mkB(zoneSec,"NEUTRAL",94,70,76,24)
local btnAlnCha=mkB(zoneSec,"CHAOTIC",176,70,76,24)
lbl(zoneSec,"BANNED ALIGNMENTS (entry flash)",12,102,W-24,14,11,ACC,true)
local btnBanLaw=mkB(zoneSec,"Lawful",12,118,76,24)
local btnBanNeu=mkB(zoneSec,"Neutral",94,118,76,24)
local btnBanCha=mkB(zoneSec,"Chaotic",176,118,76,24)
local function tintAlnBtn(b,name,active)
    local c=ZoneConfig.ALIGNMENT_COLORS[name]
    if active then
        b.BackgroundColor3=c
        b.TextColor3=Color3.new(0,0,0)
    else
        b.BackgroundColor3=Color3.fromRGB(50,40,40)
        b.TextColor3=c
    end
end
local function refreshAlignmentBtns()
    tintAlnBtn(btnAlnLaw,"Lawful", zoneAlignment=="Lawful")
    tintAlnBtn(btnAlnNeu,"Neutral",zoneAlignment=="Neutral")
    tintAlnBtn(btnAlnCha,"Chaotic",zoneAlignment=="Chaotic")
end
local function refreshBanBtns()
    tintAlnBtn(btnBanLaw,"Lawful", zoneBanned.Lawful==true)
    tintAlnBtn(btnBanNeu,"Neutral",zoneBanned.Neutral==true)
    tintAlnBtn(btnBanCha,"Chaotic",zoneBanned.Chaotic==true)
end
btnAlnLaw.Activated:Connect(function() zoneAlignment="Lawful"; refreshAlignmentBtns(); updateGhost(tonumber(boxZoneRadius.Text)) end)
btnAlnNeu.Activated:Connect(function() zoneAlignment="Neutral";refreshAlignmentBtns(); updateGhost(tonumber(boxZoneRadius.Text)) end)
btnAlnCha.Activated:Connect(function() zoneAlignment="Chaotic";refreshAlignmentBtns(); updateGhost(tonumber(boxZoneRadius.Text)) end)
btnBanLaw.Activated:Connect(function() zoneBanned.Lawful = not zoneBanned.Lawful;  refreshBanBtns() end)
btnBanNeu.Activated:Connect(function() zoneBanned.Neutral= not zoneBanned.Neutral; refreshBanBtns() end)
btnBanCha.Activated:Connect(function() zoneBanned.Chaotic= not zoneBanned.Chaotic; refreshBanBtns() end)
boxZoneRadius:GetPropertyChangedSignal("Text"):Connect(function()
    if mode=="Zone" then updateGhost(tonumber(boxZoneRadius.Text)) end
end)
refreshAlignmentBtns()
refreshBanBtns()
div(256)
local placeBtn=mkB(pnl,"Click to Place",10,264,W-20,36,Color3.fromRGB(40,80,40));placeBtn.TextSize=14
lbl(pnl,"MANAGED SPAWNERS",10,308,W-20,16,11,ACC,true)
local lf=Instance.new("ScrollingFrame",pnl);lf.Position=UDim2.fromOffset(8,326)
lf.Size=UDim2.fromOffset(W-16,H-334);lf.BackgroundTransparency=1;lf.BorderSizePixel=0
lf.ScrollBarThickness=4;lf.ScrollBarImageColor3=ACC
lf.AutomaticCanvasSize=Enum.AutomaticSize.Y;lf.CanvasSize=UDim2.new(0,0,0,0);lf.ZIndex=3
Instance.new("UIListLayout",lf).Padding=UDim.new(0,4)
local function refreshMode()
    btnMob.BackgroundColor3=mode=="Mob" and Color3.fromRGB(160,50,50) or Color3.fromRGB(80,30,30)
    btnNpc.BackgroundColor3=mode=="NPC" and Color3.fromRGB(50,50,160) or Color3.fromRGB(40,40,80)
    btnZone.BackgroundColor3=mode=="Zone" and Color3.fromRGB(110,120,50) or Color3.fromRGB(60,65,30)
    mobSec.Visible=mode=="Mob";npcSec.Visible=mode=="NPC";zoneSec.Visible=mode=="Zone"
    if mode=="Zone" then updateGhost(tonumber(boxZoneRadius.Text))
    else updateGhost(tonumber(boxRadius.Text)) end
end
local function setPlacing(v)
    placingMode=v
    placeBtn.Text=v and "Placing... (click world)" or "Click to Place"
    placeBtn.BackgroundColor3=v and Color3.fromRGB(140,110,20) or Color3.fromRGB(40,80,40)
end
local function setPanelOpen(v)
    panelOpen=v;sg.Enabled=v
    -- Surface the open state so ZoneDevVisuals can toggle its cylinders.
    player:SetAttribute("DevPlacerOpen", v)
    if v then MenuMouse.acquire() else MenuMouse.release();setPlacing(false) end
end
local function refreshList()
    for _,c in ipairs(lf:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    if not rfList then return end
    local ok,entries=pcall(function() return rfList:InvokeServer() end)
    if not ok or type(entries)~="table" then return end
    local hrp=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    table.sort(entries,function(a,b)
        if not hrp then return tostring(a.Label)<tostring(b.Label) end
        return (a.Position-hrp.Position).Magnitude<(b.Position-hrp.Position).Magnitude
    end)
    for _,entry in ipairs(entries) do
        local row=Instance.new("Frame",lf)
        row.Size=UDim2.new(1,0,0,28);row.BackgroundColor3=Color3.fromRGB(35,26,26)
        row.BorderSizePixel=0;row.ZIndex=4
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,5)
        local isM=entry.SpawnerType=="Mob"
        local isZ=entry.SpawnerType=="Zone"
        local p=entry.Position
        local coord=string.format("  [%.0f, %.0f, %.0f]",p.X,p.Y,p.Z)
        local rl=Instance.new("TextLabel",row);rl.BackgroundTransparency=1
        rl.Size=UDim2.new(1,-32,1,0);rl.Position=UDim2.fromOffset(8,0)
        rl.Font=Enum.Font.GothamMedium;rl.TextSize=12
        local rowColor
        if isZ then rowColor=Color3.fromRGB(200,200,140)
        elseif isM then rowColor=Color3.fromRGB(255,140,140)
        else rowColor=Color3.fromRGB(140,200,255) end
        rl.TextColor3=rowColor
        rl.TextXAlignment=Enum.TextXAlignment.Left
        local prefix=isZ and "ZONE " or (isM and "MOB  " or "NPC  ")
        rl.Text=prefix..tostring(entry.Label)..coord;rl.ZIndex=5
        local db=Instance.new("TextButton",row)
        db.Size=UDim2.fromOffset(22,20);db.AnchorPoint=Vector2.new(1,.5)
        db.Position=UDim2.new(1,-4,.5,0);db.BackgroundColor3=Color3.fromRGB(100,30,30)
        db.Font=Enum.Font.GothamBold;db.TextSize=11
        db.TextColor3=Color3.new(1,1,1);db.Text="x";db.ZIndex=6
        Instance.new("UICorner",db).CornerRadius=UDim.new(0,4)
        local spawnId=entry.SpawnId
        local zoneId=entry.ZoneId
        local partRef=entry.Part
        db.Activated:Connect(function()
            if not evDelete then return end
            if type(zoneId)=="string" and zoneId~="" then
                evDelete:FireServer({Type="Zone",ZoneId=zoneId})
            elseif type(spawnId)=="string" and spawnId~="" then
                evDelete:FireServer({SpawnId=spawnId})
            elseif partRef and partRef.Parent then
                evDelete:FireServer(partRef)
            end
            task.delay(.4,refreshList)
        end)
    end
end
closeX.Activated:Connect(function() setPanelOpen(false) end)
btnMob.Activated:Connect(function() mode="Mob";refreshMode() end)
btnNpc.Activated:Connect(function() mode="NPC";refreshMode() end)
btnZone.Activated:Connect(function() mode="Zone";refreshMode() end)
mobPrev.Activated:Connect(function() mobIdx=((mobIdx-2)%#MOB_IDS)+1;mobDisp.Text=MOB_IDS[mobIdx] end)
mobNext.Activated:Connect(function() mobIdx=(mobIdx%#MOB_IDS)+1;mobDisp.Text=MOB_IDS[mobIdx] end)
npcPrev.Activated:Connect(function() npcIdx=((npcIdx-2)%#NPC_TYPES)+1;npcDisp.Text=NPC_TYPES[npcIdx] end)
npcNext.Activated:Connect(function() npcIdx=(npcIdx%#NPC_TYPES)+1;npcDisp.Text=NPC_TYPES[npcIdx] end)
placeBtn.Activated:Connect(function() setPlacing(not placingMode) end)
UIS.InputBegan:Connect(function(inp,gp)
    if inp.KeyCode==Enum.KeyCode.Escape then
        if placingMode then setPlacing(false);return end
        if panelOpen then setPanelOpen(false);return end
    end
    if inp.KeyCode==Enum.KeyCode.F8 and not gp then
        setPanelOpen(not panelOpen)
        if panelOpen then refreshList();refreshMode() end
        return
    end
    if not placingMode then return end
    if inp.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    if gp then return end
    if not evPlace then warn("[DevClient] evPlace missing");setPlacing(false);return end
    if mode=="Mob" then
        local mid=MOB_IDS[mobIdx];if not mid then return end
        evPlace:FireServer({SpawnerType="Mob",MobId=mid,
            Count=math.clamp(math.floor(tonumber(boxCount.Text) or 3),1,20),
            RespawnDelay=math.clamp(math.floor(tonumber(boxDelay.Text) or 10),1,300),
            ActivationRadius=math.clamp(math.floor(tonumber(boxRadius.Text) or 100),10,500),
            ZoneName=boxZone.Text~="" and boxZone.Text or "Default",
            Position=mouse.Hit.Position})
    elseif mode=="Zone" then
        local banned={}
        for name,on in pairs(zoneBanned) do if on then table.insert(banned,name) end end
        evPlace:FireServer({SpawnerType="Zone",
            Name=boxZoneName.Text,
            Alignment=zoneAlignment,
            BannedAlignments=banned,
            Radius=math.clamp(math.floor(tonumber(boxZoneRadius.Text) or ZoneConfig.DEFAULT_RADIUS),
                ZoneConfig.MIN_RADIUS, ZoneConfig.MAX_RADIUS),
            Position=mouse.Hit.Position})
    else
        local nn,ni=boxNpcName.Text,boxNpcId.Text
        if nn=="" or ni=="" then warn("[DevClient] Fill NPC Name and ID");return end
        evPlace:FireServer({SpawnerType="NPC",NpcType=NPC_TYPES[npcIdx],
            NpcName=nn,NpcId=ni,Position=mouse.Hit.Position})
    end
    setPlacing(false);task.delay(.5,refreshList)
end)
refreshMode()
print("[DevClient] ready -- F8 to open DevPlacer")
