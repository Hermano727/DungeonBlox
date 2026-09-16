local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
-- DevClient: F9 spawner placement tool (dev-only)
local Players=game:GetService("Players");local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService");local RunService=game:GetService("RunService")
local player=Players.LocalPlayer;local mouse=player:GetMouse()
local playerGui=player:WaitForChild("PlayerGui")
local MenuMouse=require(RS:WaitForChild("CursorUtils"))
local FLY_SPEED=90
local DevRoster=require(RS:WaitForChild("DevRoster"))
local function isDev() return DevRoster.IsDev(player) end
if not isDev() then return end
local GE=RS:WaitForChild("GameEvents",15)
local evPlace=GE and GE:WaitForChild("DevPlaceSpawner",10)
local evDelete=GE and GE:WaitForChild("DevDeleteSpawner",10)
local rfList=GE and GE:WaitForChild("DevListSpawners",10)
local rfPlaceZone=GE and GE:WaitForChild("DevPlaceZone",10)
local rfSetZoneMusic=GE and GE:WaitForChild("DevSetZoneMusic",10)
local rfDayNight=GE and GE:WaitForChild("DevDayNightControl",10)
local MobData=require(RS:WaitForChild("MobData"))
local NPCRegistry=require(RS:WaitForChild("NPCRegistry"))
local ZoneConfig=require(RS:WaitForChild("ZoneConfig"))
local DayNightConfig=require(RS:WaitForChild("DayNightConfig"))
-- Only mobs with a real, fully-authored model (not a generic/placeholder
-- mesh) show up in the dev tool's spawn list -- per direct request
-- ("remove the slop mobs... the only ones fully made with model are kane +
-- plains slime + skeleton"). MobData itself is untouched (other systems --
-- natural spawners already placed in the world, loot tables -- still
-- reference every MobID), this only filters what F8 offers for placing new
-- ones. Expand this set as more mobs get real models.
local MOB_ID_WHITELIST={PlainsSlime=true,SmallSkeleton=true,Kane=true}
local MOB_IDS={}
for t=1,5 do local tb=MobData[t];if type(tb)=="table" then for id in pairs(tb) do if MOB_ID_WHITELIST[id] then table.insert(MOB_IDS,id) end end end end
table.sort(MOB_IDS)
local NPC_TYPES={}
for k in pairs(NPCRegistry.Types) do table.insert(NPC_TYPES,k) end
table.sort(NPC_TYPES)
local ItemConfig=require(RS:WaitForChild("ItemConfig"))
local ItemDefinitions=require(RS:WaitForChild("ItemDefinitions"))
local rfSpawnItem=GE and GE:WaitForChild("DevSpawnItem",10)
local rfDevGrant=RS:WaitForChild("DevGrantItem",60)
if not rfDevGrant then warn("[DevClient] DevGrantItem RF not found after 60s") end
-- Reflected off ItemDefinitions.Items -- any new catalog entry (dungeon key, fragment,
-- material, etc.) shows up in the Item tab's "Other Items" list automatically, no
-- dev-tool code change needed.
local OTHER_ITEM_IDS={}
for id in pairs(ItemDefinitions.Items) do table.insert(OTHER_ITEM_IDS,id) end
table.sort(OTHER_ITEM_IDS)
local panelOpen,placingMode,mode,mobIdx,npcIdx=false,false,"Mob",1,1
local exploreMode=false
local panelMouseFree=false
local rmbLookActive=false
local RMB_LOOK_BIND="DevClient_RMBLook"
local setPlacing
local refreshList
local refreshPanelMouse
local setExploreMode
local showStatus
local devVisualsActive
local boxZoneName
local statusLbl
-- Zone placement state (read by ghost + place handler).
local zoneAlignment="Lawful"
local zoneBanned={Lawful=false,Neutral=false,Chaotic=false}
local zoneIsElite=false
local zoneEliteMobIdx=1
local zoneDrawPoints={}
local zonePreview=Instance.new('Folder')
zonePreview.Name='DevPlacerZonePreview'
zonePreview.Parent=nil
local ZONE_YELLOW=ZoneConfig.DEV_ZONE_COLOR
local function clearZoneDraw()
	table.clear(zoneDrawPoints)
	for _, c in ipairs(zonePreview:GetChildren()) do
		c:Destroy()
	end
	if zoneDrawLbl then zoneDrawLbl.Text = "Pts: 0" end
end
local function addPreviewEdge(x1, z1, x2, z2, y)
	local p1 = Vector3.new(x1, y + 0.2, z1)
	local p2 = Vector3.new(x2, y + 0.2, z2)
	local mid = (p1 + p2) * 0.5
	local len = (p2 - p1).Magnitude
	if len < 0.05 then return end
	local e = Instance.new("Part")
	e.Anchored = true
	e.CanCollide = false
	e.CanQuery = false
	e.CanTouch = false
	e.Material = Enum.Material.Neon
	e.Color = ZONE_YELLOW
	e.Transparency = 0.3
	e.Size = Vector3.new(len, ZoneConfig.DEV_ZONE_EDGE_THICKNESS, ZoneConfig.DEV_ZONE_EDGE_THICKNESS)
	e.CFrame = CFrame.new(mid, p2) * CFrame.Angles(0, math.rad(90), 0)
	e.Parent = zonePreview
end
local zoneDrawLbl
local function refreshZoneDrawPreview()
	for _, c in ipairs(zonePreview:GetChildren()) do
		c:Destroy()
	end
	local n = #zoneDrawPoints
	if zoneDrawLbl then zoneDrawLbl.Text = "Pts: " .. n end
	if n == 0 then return end
	local y = zoneDrawPoints[1].Y
	for i, p in ipairs(zoneDrawPoints) do
		local corner = Instance.new("Part")
		corner.Shape = Enum.PartType.Ball
		corner.Size = Vector3.new(ZoneConfig.DEV_ZONE_CORNER_SIZE, ZoneConfig.DEV_ZONE_CORNER_SIZE, ZoneConfig.DEV_ZONE_CORNER_SIZE)
		corner.Position = Vector3.new(p.X, y + 0.3, p.Z)
		corner.Anchored = true
		corner.CanCollide = false
		corner.CanQuery = false
		corner.CanTouch = false
		corner.Material = Enum.Material.Neon
		corner.Color = ZONE_YELLOW
		corner.Transparency = 0.2
		corner.Parent = zonePreview
		if i > 1 then
			addPreviewEdge(zoneDrawPoints[i - 1].X, zoneDrawPoints[i - 1].Z, p.X, p.Z, y)
		end
	end
	if n >= 3 then
		addPreviewEdge(zoneDrawPoints[n].X, zoneDrawPoints[n].Z, zoneDrawPoints[1].X, zoneDrawPoints[1].Z, y)
	end
end
local function getAimWorldPosition()
	local cam = workspace.CurrentCamera
	if not cam then
		return mouse.Hit.Position
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { zonePreview }
	if ghost then
		table.insert(filter, ghost)
	end
	if player.Character then
		table.insert(filter, player.Character)
	end
	params.FilterDescendantsInstances = filter
	local origin, direction
	local freeCursor = UIS.MouseBehavior == Enum.MouseBehavior.Default and UIS.MouseIconEnabled
	if freeCursor then
		local mousePos = UIS:GetMouseLocation()
		local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
		origin = ray.Origin
		direction = ray.Direction
	else
		origin = cam.CFrame.Position
		direction = cam.CFrame.LookVector
	end
	local hit = workspace:Raycast(origin, direction * 2000, params)
	local pos = hit and hit.Position or (origin + direction * 50)
	if mode == "Zone" and #zoneDrawPoints > 0 then
		pos = Vector3.new(pos.X, zoneDrawPoints[1].Y, pos.Z)
	end
	return pos
end
local function addZoneCorner()
	if mode ~= "Zone" or not placingMode then return end
	if #zoneDrawPoints >= ZoneConfig.MAX_POLYGON_POINTS then
		showStatus("Max polygon points (" .. ZoneConfig.MAX_POLYGON_POINTS .. ")", true)
		return
	end
	table.insert(zoneDrawPoints, getAimWorldPosition())
	refreshZoneDrawPreview()
	showStatus("Corner " .. #zoneDrawPoints .. " placed (E or click)")
end
local function undoZoneCorner()
	if #zoneDrawPoints == 0 then return end
	table.remove(zoneDrawPoints)
	refreshZoneDrawPreview()
	showStatus("Removed corner (" .. #zoneDrawPoints .. " left)")
end
local function finishZoneDraw()
	if #zoneDrawPoints < ZoneConfig.MIN_POLYGON_POINTS then
		showStatus("Need at least " .. ZoneConfig.MIN_POLYGON_POINTS .. " points", true)
		return
	end
	if not rfPlaceZone then
		showStatus("DevPlaceZone remote missing", true)
		return
	end
	local banned = {}
	for name, on in pairs(zoneBanned) do
		if on then table.insert(banned, name) end
	end
	local pts = {}
	for _, p in ipairs(zoneDrawPoints) do
		table.insert(pts, { x = p.X, z = p.Z })
	end
	local groundY = zoneDrawPoints[1].Y
	local ok, result = pcall(function()
		return rfPlaceZone:InvokeServer({
			Name = boxZoneName.Text,
			Alignment = zoneAlignment,
			BannedAlignments = banned,
			IsEliteZone = zoneIsElite,
			EliteMobId = MOB_IDS[zoneEliteMobIdx],
			Points = pts,
			Position = Vector3.new(0, groundY, 0),
			MusicId = boxZoneMusicId and boxZoneMusicId.Text or "",
		})
	end)
	if not ok or type(result) ~= "table" or not result.ok then
		local err = (type(result) == "table" and result.error) or tostring(result)
		showStatus("Zone save failed: " .. tostring(err), true)
		warn("[DevClient] Finish zone failed: " .. tostring(err))
		return
	end
	local z = result.zone
	showStatus("Saved zone: " .. (z and z.name or "?"))
	clearZoneDraw()
	setPlacing(false)
	setExploreMode(false)
	task.delay(0.3, refreshList)
end
local ghost=Instance.new("Part");ghost.Name="DevPlacerGhost";ghost.Anchored=true
ghost.CanCollide=false;ghost.CanQuery=false;ghost.CanTouch=false;ghost.CastShadow=false
ghost.Transparency=0.55;ghost.Shape=Enum.PartType.Cylinder;ghost.Material=Enum.Material.Neon
ghost.Size=Vector3.new(1,10,10);ghost.CFrame=CFrame.new(0,-500,0);ghost.Parent=workspace
local function updateGhost(r)
    if mode=="Time" or mode=="Gear" or mode=="Items" or mode=="Mythic" then ghost.CFrame=CFrame.new(0,-500,0); return end
    if mode=="Mob" then ghost.Color=Color3.fromRGB(220,60,60)
        local d=math.clamp((r or 100)*2,4,200);ghost.Size=Vector3.new(1,d,d)
    elseif mode=="Zone" then
        ghost.Color=ZONE_YELLOW
        ghost.Shape=Enum.PartType.Ball
        local s=ZoneConfig.DEV_ZONE_CORNER_SIZE
        ghost.Size=Vector3.new(s,s,s)
        ghost.Transparency=0.2
    else ghost.Color=Color3.fromRGB(60,140,220);ghost.Size=Vector3.new(1,6,6) end
end
RunService.RenderStepped:Connect(function()
    if placingMode then
        local pos=getAimWorldPosition()
        if mode=="Zone" then
            ghost.CFrame=CFrame.new(pos.X, pos.Y + 0.3, pos.Z)
        else
            ghost.CFrame=CFrame.new(pos + Vector3.new(0, .5, 0)) * CFrame.Angles(0, 0, math.rad(90))
        end
    elseif ghost.Parent then
        ghost.CFrame=CFrame.new(0, -500, 0)
    end
    if not (placingMode and mode=="Zone") then
        local hum=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.PlatformStand then hum.PlatformStand=false end
        return
    end
    local char=player.Character
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    local hrp=char and char:FindFirstChild("HumanoidRootPart")
    local cam=workspace.CurrentCamera
    if not hum or not hrp or not cam then return end
    hum.PlatformStand=true
    local move=Vector3.zero
    if UIS:IsKeyDown(Enum.KeyCode.W) then move+=cam.CFrame.LookVector end
    if UIS:IsKeyDown(Enum.KeyCode.S) then move-=cam.CFrame.LookVector end
    if UIS:IsKeyDown(Enum.KeyCode.A) then move-=cam.CFrame.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.D) then move+=cam.CFrame.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.Space) then move+=Vector3.yAxis end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.C) then move-=Vector3.yAxis end
    move=Vector3.new(move.X,move.Y,move.Z)
    if move.Magnitude>0 then move=move.Unit end
    hrp.AssemblyLinearVelocity=move*FLY_SPEED
    hrp.AssemblyAngularVelocity=Vector3.zero
end)
local W,H=600,700
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
lbl(pnl,"MODE",12,44,120,14,11,ACC,true)
-- Data-driven mode row: append a { key, label, color, colorOff } entry to add a new F8
-- tab -- position/wrapping/coloring below are all computed, no pixel math to hand-edit.
-- immediate=true marks an "instant action" tab (Time, Gear, Items) whose main button fires
-- right away instead of entering a click-to-place mode (matches Time's original behavior).
-- Gear/Items split (2026-09-12, per direct request): these used to be one "ITEM" tab with
-- the procedural weapon/armor spawner on top and a "OTHER ITEMS" catalog cycle+grant button
-- underneath it, inside the same scrolling section. The catalog button sat below the fold
-- (needed scrolling to reach), while the panel's single global "confirm" button (placeBtn)
-- stayed pinned at the very bottom of the whole panel, always wired to the GEAR spawn
-- action for this tab -- so clicking what looked like "the bottom button" while a catalog
-- item was selected silently spawned random gear instead (regression report: pressing the
-- lower button after selecting a dungeon key spawned a Wooden Bow / Leather Chestplate
-- instead). Splitting into two tabs removes the ambiguity: GEAR keeps placeBtn as its
-- confirm action, ITEMS is a self-contained icon grid where clicking an item's own icon
-- grants it directly -- no shared confirm button involved.
local MODES={
    { key="Mob",  label="MOB",  color=Color3.fromRGB(160,50,50),  colorOff=Color3.fromRGB(80,30,30) },
    { key="NPC",  label="NPC",  color=Color3.fromRGB(50,50,160),  colorOff=Color3.fromRGB(40,40,80) },
    { key="Zone", label="ZONE", color=Color3.fromRGB(110,120,50), colorOff=Color3.fromRGB(60,65,30) },
    { key="Time", label="TIME", color=Color3.fromRGB(90,130,180), colorOff=Color3.fromRGB(40,55,80), immediate=true },
    { key="Gear", label="GEAR", color=Color3.fromRGB(150,110,40), colorOff=Color3.fromRGB(70,55,25), immediate=true },
    { key="Items", label="ITEMS", color=Color3.fromRGB(60,140,120), colorOff=Color3.fromRGB(30,65,55), immediate=true },
    { key="Mythic", label="MYTHIC", color=Color3.fromRGB(255,85,0), colorOff=Color3.fromRGB(110,40,10), immediate=true },
}
local modeButtons={}
local MODE_ROW_Y0=60
local function layoutModeButtons()
    local x,y=12,MODE_ROW_Y0
    local maxRight=W-12
    local bottom=y
    for _,m in ipairs(MODES) do
        local btnW=math.max(44,#m.label*8+20)
        if x>12 and x+btnW>maxRight then
            x=12;y=y+26+4
        end
        local b=modeButtons[m.key]
        if not b then
            b=mkB(pnl,m.label,x,y,btnW,26)
            modeButtons[m.key]=b
        else
            b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(btnW,26)
        end
        x=x+btnW+4
        bottom=math.max(bottom,y+26)
    end
    return bottom
end
local modeRowBottom=layoutModeButtons()
div(modeRowBottom+6)
local sectionY=modeRowBottom+12
local SECTION_H=360
local mobSec=Instance.new("Frame",pnl);mobSec.Position=UDim2.fromOffset(0,sectionY)
mobSec.Size=UDim2.fromOffset(W,196);mobSec.BackgroundTransparency=1
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
-- "Force Spawn Elite" (2026-09-14): instantly spawns whichever mob MOB_TYPE
-- is currently showing as a NAMED ELITE (rise-from-ground intro + top-middle
-- boss bar), through the exact same server path a real elite pity/chance
-- trigger uses -- see MobManager.ForceSpawnNamedElite. Independent of the
-- placing-mode click-to-place flow below; fires immediately on click.
local btnForceElite=mkB(mobSec,"Force Spawn Elite",12,164,W-24,26,Color3.fromRGB(90,40,90))
local npcSec=Instance.new("Frame",pnl);npcSec.Position=UDim2.fromOffset(0,sectionY)
npcSec.Size=UDim2.fromOffset(W,170);npcSec.BackgroundTransparency=1;npcSec.Visible=false
local zoneSec=Instance.new("ScrollingFrame",pnl);zoneSec.Position=UDim2.fromOffset(0,sectionY)
zoneSec.Size=UDim2.fromOffset(W,170);zoneSec.BackgroundTransparency=1;zoneSec.Visible=false
zoneSec.BorderSizePixel=0
zoneSec.CanvasSize=UDim2.new(0,0,0,0)
zoneSec.AutomaticCanvasSize=Enum.AutomaticSize.Y
zoneSec.ScrollingDirection=Enum.ScrollingDirection.Y
zoneSec.ScrollBarThickness=6
zoneSec.ScrollBarImageColor3=ACC
zoneSec.TopImage=""
zoneSec.BottomImage=""
local timeSec=Instance.new("Frame",pnl);timeSec.Position=UDim2.fromOffset(0,sectionY)
timeSec.Size=UDim2.fromOffset(W,188);timeSec.BackgroundTransparency=1;timeSec.Visible=false
lbl(timeSec,"TIME OF DAY",12,2,120,14,11,ACC,true)
local timeStatusLbl=lbl(timeSec,"Auto cycle",12,18,W-24,14,11,Color3.fromRGB(180,170,140),false)
local timePreviewLbl=lbl(timeSec,"12:00 PM",12,34,W-24,22,18,Color3.fromRGB(255,220,120),true,Enum.TextXAlignment.Left)
lbl(timeSec,"HOUR",12,62,50,14,11,ACC,true)
local boxTimeHour=mkI(timeSec,"12",12,78,58,28,"12")
lbl(timeSec,"MIN",80,62,40,14,11,ACC,true)
local boxTimeMin=mkI(timeSec,"0",80,78,58,28,"0")
lbl(timeSec,"PRESETS",12,114,W-24,14,11,ACC,true)
local btnTimeDawn=mkB(timeSec,"Dawn",12,130,58,24,Color3.fromRGB(55,45,35))
local btnTimeNoon=mkB(timeSec,"Noon",76,130,58,24,Color3.fromRGB(55,50,35))
local btnTimeDusk=mkB(timeSec,"Dusk",140,130,58,24,Color3.fromRGB(50,40,55))
local btnTimeMid=mkB(timeSec,"Midnight",204,130,58,24,Color3.fromRGB(35,35,55))
local btnResumeCycle=mkB(timeSec,"Resume Auto Cycle",12,160,W-24,26,Color3.fromRGB(40,70,110))
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
boxZoneName=mkI(zoneSec,"e.g. Stormhaven",12,18,W-24,28,"")
lbl(zoneSec,"Draw corners (min 3). Fly while drawing.",12,50,W-24,14,11,Color3.fromRGB(180,170,140),false)
lbl(zoneSec,"E=corner  Enter=finish  RMB=look  Backspace=undo",12,64,W-24,12,10,Color3.fromRGB(140,130,110),false)
lbl(zoneSec,"ALIGNMENT",12,82,100,14,11,ACC,true)
local btnAlnLaw=mkB(zoneSec,"LAWFUL",12,98,76,24)
local btnAlnNeu=mkB(zoneSec,"NEUTRAL",94,98,76,24)
local btnAlnCha=mkB(zoneSec,"CHAOTIC",176,98,76,24)
lbl(zoneSec,"BANNED ALIGNMENTS (entry flash)",12,130,W-24,14,11,ACC,true)
local btnBanLaw=mkB(zoneSec,"Lawful",12,146,76,24)
local btnBanNeu=mkB(zoneSec,"Neutral",94,146,76,24)
local btnBanCha=mkB(zoneSec,"Chaotic",176,146,76,24)
lbl(zoneSec,"ELITE MOB ZONE",12,176,120,14,11,ACC,true)
local btnEliteZone=mkB(zoneSec,"OFF",W-58,172,46,24,Color3.fromRGB(90,40,40))
local btnElitePrev=mkB(zoneSec,"<",12,200,24,26)
local btnEliteNext=mkB(zoneSec,">",W-34,200,24,26)
local eliteMobDisp=lbl(zoneSec,MOB_IDS[zoneEliteMobIdx] or "-",40,200,W-72,26,12,Color3.new(1,1,1),false,Enum.TextXAlignment.Center)
lbl(zoneSec,"MUSIC ID (optional, blank = none)",12,234,W-24,14,11,ACC,true)
local boxZoneMusicId=mkI(zoneSec,"rbxassetid://... or bare number",12,250,W-24,28,"")
local btnFinishZone=mkB(zoneSec,"Finish Zone",12,286,88,26,Color3.fromRGB(40,90,40))
local btnClearZone=mkB(zoneSec,"Clear",106,286,52,26,Color3.fromRGB(90,40,40))
local btnHideFly=mkB(zoneSec,"Hide & Fly",164,286,86,26,Color3.fromRGB(50,70,110))
zoneDrawLbl=lbl(zoneSec,"Pts: 0",12,316,W-24,18,11,Color3.fromRGB(255,220,80),false,Enum.TextXAlignment.Left)
zoneSec.CanvasPosition=Vector2.new(0,0)
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
local function refreshEliteZoneUi()
    btnEliteZone.Text = zoneIsElite and "ON" or "OFF"
    btnEliteZone.BackgroundColor3 = zoneIsElite and Color3.fromRGB(40,90,40) or Color3.fromRGB(90,40,40)
    eliteMobDisp.Text = MOB_IDS[zoneEliteMobIdx] or "-"
    eliteMobDisp.TextColor3 = zoneIsElite and Color3.new(1,1,1) or Color3.fromRGB(145,130,130)
    btnElitePrev.AutoButtonColor = zoneIsElite
    btnEliteNext.AutoButtonColor = zoneIsElite
    btnElitePrev.TextColor3 = zoneIsElite and Color3.new(1,1,1) or Color3.fromRGB(145,130,130)
    btnEliteNext.TextColor3 = zoneIsElite and Color3.new(1,1,1) or Color3.fromRGB(145,130,130)
end
btnAlnLaw.Activated:Connect(function() zoneAlignment="Lawful"; refreshAlignmentBtns() end)
btnAlnNeu.Activated:Connect(function() zoneAlignment="Neutral";refreshAlignmentBtns() end)
btnAlnCha.Activated:Connect(function() zoneAlignment="Chaotic";refreshAlignmentBtns() end)
btnBanLaw.Activated:Connect(function() zoneBanned.Lawful = not zoneBanned.Lawful;  refreshBanBtns() end)
btnBanNeu.Activated:Connect(function() zoneBanned.Neutral= not zoneBanned.Neutral; refreshBanBtns() end)
btnBanCha.Activated:Connect(function() zoneBanned.Chaotic= not zoneBanned.Chaotic; refreshBanBtns() end)
btnEliteZone.Activated:Connect(function() zoneIsElite = not zoneIsElite; refreshEliteZoneUi() end)
btnElitePrev.Activated:Connect(function()
    if not zoneIsElite or #MOB_IDS == 0 then return end
    zoneEliteMobIdx=((zoneEliteMobIdx-2)%#MOB_IDS)+1
    refreshEliteZoneUi()
end)
btnEliteNext.Activated:Connect(function()
    if not zoneIsElite or #MOB_IDS == 0 then return end
    zoneEliteMobIdx=(zoneEliteMobIdx%#MOB_IDS)+1
    refreshEliteZoneUi()
end)
refreshAlignmentBtns()
refreshBanBtns()
refreshEliteZoneUi()
-- GEAR tab: procedural weapon/armor spawner (ItemGenerator, same engine mob drops use).
-- The catalog "Other Items" granter used to live at the bottom of this same scrolling
-- section; it's now its own ITEMS tab (icon grid, further down this file) -- see the note
-- above MODES for why.
local itemSec=Instance.new("ScrollingFrame",pnl);itemSec.Position=UDim2.fromOffset(0,sectionY)
itemSec.Size=UDim2.fromOffset(W,SECTION_H);itemSec.BackgroundTransparency=1;itemSec.Visible=false
itemSec.BorderSizePixel=0
itemSec.CanvasSize=UDim2.new(0,0,0,0)
itemSec.AutomaticCanvasSize=Enum.AutomaticSize.Y
itemSec.ScrollingDirection=Enum.ScrollingDirection.Y
itemSec.ScrollBarThickness=6
itemSec.ScrollBarImageColor3=ACC
itemSec.TopImage=""
itemSec.BottomImage=""

local ITEM_KINDS={"Random","Weapon","Armor"}
local itemKindIdx=1
local WEAPON_POOL=ItemConfig.WEAPON_TYPES_BY_TIER[1] or ItemConfig.WEAPON_TYPES
local ARMOR_POOL=ItemConfig.ARMOR_SLOTS_BY_TIER[1] or ItemConfig.ARMOR_SLOTS
local weaponIdx,armorIdx=1,1
local RARITY_OPTIONS={"Random"}
for _,r in ipairs(ItemConfig.RARITY_ORDER) do table.insert(RARITY_OPTIONS,r) end
local rarityIdx=1

lbl(itemSec,"ITEM KIND",12,2,120,12,11,ACC,true)
local itemKindPrev=mkB(itemSec,"<",12,16,24,24)
local itemKindNext=mkB(itemSec,">",W-34,16,24,24)
local itemKindDisp=lbl(itemSec,ITEM_KINDS[itemKindIdx],40,16,W-92,24,13,Color3.new(1,1,1),false,Enum.TextXAlignment.Center)

lbl(itemSec,"SUBTYPE",12,44,120,12,11,ACC,true)
local itemSubPrev=mkB(itemSec,"<",12,58,24,24)
local itemSubNext=mkB(itemSec,">",W-34,58,24,24)
local itemSubDisp=lbl(itemSec,"Any",40,58,W-92,24,13,Color3.new(1,1,1),false,Enum.TextXAlignment.Center)

lbl(itemSec,"LEVEL (1-21 = T1)",12,86,W-24,12,11,ACC,true)
local boxItemLevel=mkI(itemSec,"1",12,100,60,26,"1")
local itemTierDisp=lbl(itemSec,"Tier: T1",84,103,W-96,20,12,Color3.fromRGB(180,220,180),true)

lbl(itemSec,"RARITY",12,130,120,12,11,ACC,true)
local itemRarityPrev=mkB(itemSec,"<",12,144,24,24)
local itemRarityNext=mkB(itemSec,">",W-34,144,24,24)
local itemRarityDisp=lbl(itemSec,RARITY_OPTIONS[rarityIdx],40,144,W-92,24,13,Color3.new(1,1,1),false,Enum.TextXAlignment.Center)

lbl(itemSec,"SUBSTATS (blank = default roll)",12,172,180,12,11,ACC,true)
local boxItemSubstats=mkI(itemSec,"e.g. 2",12,186,80,26,"")
lbl(itemSec,"COUNT",100,172,80,12,11,ACC,true)
local boxItemCount=mkI(itemSec,"1",100,186,60,26,"1")

-- FORCE SUBSTAT (optional, dev-only): pin one specific substat to an exact
-- value -- e.g. pick "critical" and set VALUE to 100 to spawn a weapon that
-- crits every hit, for testing. Pool reflects Kind/weapon-type so you only
-- ever see substats that can actually land on what you're about to spawn.
lbl(itemSec,"FORCE SUBSTAT (optional -- e.g. critical @ 100 = guaranteed crit)",12,218,W-24,12,11,ACC,true)
local forceSubPrev=mkB(itemSec,"<",12,232,24,24)
local forceSubDisp=lbl(itemSec,"None",40,232,260,24,13,Color3.new(1,1,1),false,Enum.TextXAlignment.Center)
local forceSubNext=mkB(itemSec,">",304,232,24,24)
lbl(itemSec,"VALUE",340,218,90,12,11,ACC,true)
local boxForceSubValue=mkI(itemSec,"e.g. 100",340,232,90,24,"")

local btnSpawnItem=mkB(itemSec,"Spawn Item",12,264,W-24,28,Color3.fromRGB(40,80,40))

local MELEE_WEAPON_TYPES={Sword=true,Scythe=true,Axe=true,Mace=true}
local forceSubIdx=1
local FORCE_SUB_POOL={"None"}

local function refreshForceSubPool()
    local kind=ITEM_KINDS[itemKindIdx]
    local pool={"None"}
    if kind=="Armor" then
        for _,e in ipairs(ItemConfig.ARMOR_EFFECTS) do table.insert(pool,e.id) end
    else
        -- Weapon (and Random -- crit etc. only exist on weapons anyway, so the
        -- weapon pool is the useful default there too).
        local wt=WEAPON_POOL[weaponIdx]
        local isMelee=MELEE_WEAPON_TYPES[wt]==true
        for _,e in ipairs(ItemConfig.WEAPON_EFFECTS) do
            if not (e.meleeOnly and not isMelee) and not (e.rangedOnly and isMelee) then
                table.insert(pool,e.id)
            end
        end
    end
    FORCE_SUB_POOL=pool
    if forceSubIdx>#FORCE_SUB_POOL then forceSubIdx=1 end
    forceSubDisp.Text=FORCE_SUB_POOL[forceSubIdx]
end

local function refreshItemKindUi()
    itemKindDisp.Text=ITEM_KINDS[itemKindIdx]
    local kind=ITEM_KINDS[itemKindIdx]
    if kind=="Weapon" then
        itemSubDisp.Text=WEAPON_POOL[weaponIdx] or "-"
        itemSubPrev.Visible=true;itemSubNext.Visible=true
    elseif kind=="Armor" then
        itemSubDisp.Text=ARMOR_POOL[armorIdx] or "-"
        itemSubPrev.Visible=true;itemSubNext.Visible=true
    else
        itemSubDisp.Text="Any"
        itemSubPrev.Visible=false;itemSubNext.Visible=false
    end
    refreshForceSubPool()
end
itemKindPrev.Activated:Connect(function() itemKindIdx=((itemKindIdx-2)%#ITEM_KINDS)+1;refreshItemKindUi() end)
itemKindNext.Activated:Connect(function() itemKindIdx=(itemKindIdx%#ITEM_KINDS)+1;refreshItemKindUi() end)
itemSubPrev.Activated:Connect(function()
    local kind=ITEM_KINDS[itemKindIdx]
    if kind=="Weapon" and #WEAPON_POOL>0 then weaponIdx=((weaponIdx-2)%#WEAPON_POOL)+1
    elseif kind=="Armor" and #ARMOR_POOL>0 then armorIdx=((armorIdx-2)%#ARMOR_POOL)+1 end
    refreshItemKindUi()
end)
itemSubNext.Activated:Connect(function()
    local kind=ITEM_KINDS[itemKindIdx]
    if kind=="Weapon" and #WEAPON_POOL>0 then weaponIdx=(weaponIdx%#WEAPON_POOL)+1
    elseif kind=="Armor" and #ARMOR_POOL>0 then armorIdx=(armorIdx%#ARMOR_POOL)+1 end
    refreshItemKindUi()
end)
refreshItemKindUi()

itemRarityPrev.Activated:Connect(function() rarityIdx=((rarityIdx-2)%#RARITY_OPTIONS)+1;itemRarityDisp.Text=RARITY_OPTIONS[rarityIdx] end)
itemRarityNext.Activated:Connect(function() rarityIdx=(rarityIdx%#RARITY_OPTIONS)+1;itemRarityDisp.Text=RARITY_OPTIONS[rarityIdx] end)

forceSubPrev.Activated:Connect(function() forceSubIdx=((forceSubIdx-2)%#FORCE_SUB_POOL)+1;forceSubDisp.Text=FORCE_SUB_POOL[forceSubIdx] end)
forceSubNext.Activated:Connect(function() forceSubIdx=(forceSubIdx%#FORCE_SUB_POOL)+1;forceSubDisp.Text=FORCE_SUB_POOL[forceSubIdx] end)

local TIER1_MAX_LEVEL=21 -- mirrors DevService's server-side check; this copy only drives
                          -- the "Tier: ..." preview label, the server independently re-validates.
local function refreshItemTierPreview()
    local lvl=math.floor(tonumber(boxItemLevel.Text) or 0)
    if lvl<1 then
        itemTierDisp.Text="Tier: ?";itemTierDisp.TextColor3=Color3.fromRGB(220,160,120)
    elseif lvl<=TIER1_MAX_LEVEL then
        itemTierDisp.Text="Tier: T1";itemTierDisp.TextColor3=Color3.fromRGB(180,220,180)
    else
        itemTierDisp.Text="T2+ not implemented";itemTierDisp.TextColor3=Color3.fromRGB(255,140,140)
    end
end
boxItemLevel.FocusLost:Connect(refreshItemTierPreview)
refreshItemTierPreview()

local function spawnItemAction()
    if not rfSpawnItem then
        showStatus("DevSpawnItem remote missing",true)
        return
    end
    local kind=ITEM_KINDS[itemKindIdx]
    local data={
        Level=math.floor(tonumber(boxItemLevel.Text) or 1),
        Kind=kind,
        Count=math.clamp(math.floor(tonumber(boxItemCount.Text) or 1),1,20),
    }
    if RARITY_OPTIONS[rarityIdx]~="Random" then
        data.Rarity=RARITY_OPTIONS[rarityIdx]
    end
    if boxItemSubstats.Text~="" then
        data.SubstatCount=tonumber(boxItemSubstats.Text)
    end
    local chosenSub=FORCE_SUB_POOL[forceSubIdx]
    if chosenSub and chosenSub~="None" then
        local v=tonumber(boxForceSubValue.Text)
        if v~=nil then
            data.ForceSubstatId=chosenSub
            data.ForceSubstatValue=v
        end
    end
    if kind=="Weapon" then
        data.WeaponType=WEAPON_POOL[weaponIdx]
    elseif kind=="Armor" then
        data.ArmorSlot=ARMOR_POOL[armorIdx]
    end
    local ok,result=pcall(function() return rfSpawnItem:InvokeServer(data) end)
    if not ok or type(result)~="table" or not result.ok then
        local err=(type(result)=="table" and result.error) or tostring(result)
        showStatus("Spawn failed: "..tostring(err),true)
        return
    end
    local it=result.item or {}
    showStatus(string.format("Spawned %s (%s, L%d)",tostring(it.name),tostring(it.rarity),tonumber(it.level) or 0))
end
btnSpawnItem.Activated:Connect(spawnItemAction)

-- ITEMS tab: a self-contained icon grid over the whole ItemDefinitions catalog (dungeon
-- keys/fragments/materials/consumables/...) via the existing DevGrantItem remote. Nothing
-- here is hardcoded -- add a new catalog item and it shows up with zero DevClient changes.
-- Each cell grants itself directly on click, deliberately NOT routed through the panel's
-- shared placeBtn -- that button is what caused the original regression (see the note
-- above MODES).
local itemsSec=Instance.new("ScrollingFrame",pnl);itemsSec.Position=UDim2.fromOffset(0,sectionY)
itemsSec.Size=UDim2.fromOffset(W,SECTION_H);itemsSec.BackgroundTransparency=1;itemsSec.Visible=false
itemsSec.BorderSizePixel=0
itemsSec.CanvasSize=UDim2.new(0,0,0,0)
itemsSec.AutomaticCanvasSize=Enum.AutomaticSize.Y
itemsSec.ScrollingDirection=Enum.ScrollingDirection.Y
itemsSec.ScrollBarThickness=6
itemsSec.ScrollBarImageColor3=ACC
itemsSec.TopImage=""
itemsSec.BottomImage=""

local itemsGrid=Instance.new("UIGridLayout",itemsSec)
itemsGrid.CellSize=UDim2.fromOffset(78,108)
itemsGrid.CellPadding=UDim2.fromOffset(8,8)
itemsGrid.SortOrder=Enum.SortOrder.LayoutOrder
local itemsPad=Instance.new("UIPadding",itemsSec)
itemsPad.PaddingTop=UDim.new(0,4)
itemsPad.PaddingLeft=UDim.new(0,4)
itemsPad.PaddingRight=UDim.new(0,4)

local function grantOtherItem(itemId,qty)
    if not rfDevGrant then
        showStatus("DevGrantItem remote missing",true)
        return
    end
    qty=math.clamp(math.floor(tonumber(qty) or 1),1,9999)
    local pOk,grantOk,grantErr=pcall(function() return rfDevGrant:InvokeServer(itemId,qty) end)
    if not pOk then
        showStatus("Grant failed: "..tostring(grantOk),true)
        return
    end
    if grantOk then
        showStatus("Granted "..tostring(qty).."x "..itemId)
    else
        showStatus("Grant failed: "..tostring(grantErr),true)
    end
end

for i,id in ipairs(OTHER_ITEM_IDS) do
    local def=ItemDefinitions.Get(id)

    local cell=Instance.new("Frame")
    cell.Name=id
    cell.LayoutOrder=i
    cell.BackgroundColor3=Color3.fromRGB(30,24,20)
    cell.BorderSizePixel=0
    cell.Parent=itemsSec
    Instance.new("UICorner",cell).CornerRadius=UDim.new(0,6)
    local cellStroke=Instance.new("UIStroke",cell);cellStroke.Thickness=1;cellStroke.Color=ACC

    local icon=Instance.new("ImageButton")
    icon.Position=UDim2.fromOffset(7,6)
    icon.Size=UDim2.fromOffset(64,64)
    icon.BackgroundColor3=Color3.fromRGB(14,10,10)
    icon.BorderSizePixel=0
    icon.AutoButtonColor=true
    icon.Image=(def and def.Icon) or ""
    icon.ScaleType=Enum.ScaleType.Fit
    icon.Parent=cell
    Instance.new("UICorner",icon).CornerRadius=UDim.new(0,5)

    local qtyBox=mkI(cell,"1",7,74,64,20,"1")
    qtyBox.TextSize=12

    local nameLbl=Instance.new("TextLabel")
    nameLbl.BackgroundTransparency=1
    nameLbl.Position=UDim2.fromOffset(2,95)
    nameLbl.Size=UDim2.fromOffset(74,11)
    nameLbl.Font=Enum.Font.GothamMedium
    nameLbl.TextSize=8
    nameLbl.TextColor3=Color3.fromRGB(190,180,170)
    nameLbl.TextTruncate=Enum.TextTruncate.AtEnd
    nameLbl.Text=(def and def.DisplayName) or id
    nameLbl.Parent=cell

    icon.Activated:Connect(function()
        grantOtherItem(id,qtyBox.Text)
    end)
end

-- MYTHIC tab.
-- Mythic is deliberately absent from ItemConfig.RARITY_ORDER (so it can never roll from
-- an ordinary kill), which is why it cannot be an option in the ITEM tab's rarity list.
-- Instead each mythic is hand-authored in MythicItemDefs and built by MythicItemBuilder,
-- so what this spawns is the REAL boss drop with its fixed substats -- not a random roll
-- wearing a Mythic label. Reflected off MythicItemDefs.Items: adding a boss item there
-- makes it appear here with no DevClient change.
local MythicItemDefs=require(RS:WaitForChild("MythicItemDefs"))
local MYTHIC_KEYS={}
for k in pairs(MythicItemDefs.Items) do table.insert(MYTHIC_KEYS,k) end
table.sort(MYTHIC_KEYS)
local mythicIdx=1

local mythicSec=Instance.new("ScrollingFrame",pnl)
mythicSec.Position=UDim2.fromOffset(0,sectionY)
mythicSec.Size=UDim2.fromOffset(W,SECTION_H)
mythicSec.BackgroundTransparency=1;mythicSec.Visible=false;mythicSec.BorderSizePixel=0
mythicSec.CanvasSize=UDim2.new(0,0,0,0)
mythicSec.AutomaticCanvasSize=Enum.AutomaticSize.Y
mythicSec.ScrollingDirection=Enum.ScrollingDirection.Y
mythicSec.ScrollBarThickness=6;mythicSec.ScrollBarImageColor3=ACC
mythicSec.TopImage="";mythicSec.BottomImage=""

lbl(mythicSec,"MYTHIC ITEM",12,2,120,12,11,ACC,true)
local mythPrev=mkB(mythicSec,"<",12,16,24,24)
local mythNext=mkB(mythicSec,">",W-34,16,24,24)
local mythDisp=lbl(mythicSec,MYTHIC_KEYS[1] or "(none)",40,16,W-92,24,13,Color3.new(1,1,1),false,Enum.TextXAlignment.Center)

local mythName=lbl(mythicSec,"",12,46,W-24,20,12,MythicItemDefs.RARITY_COLOR,true,Enum.TextXAlignment.Center)
local mythInfo=lbl(mythicSec,"",12,68,W-24,60,11,Color3.fromRGB(190,190,200),false,Enum.TextXAlignment.Left)
mythInfo.TextWrapped=true
mythInfo.TextYAlignment=Enum.TextYAlignment.Top

lbl(mythicSec,"COUNT",12,132,80,12,11,ACC,true)
local boxMythCount=mkI(mythicSec,"1",12,146,60,26,"1")

local function refreshMythic()
    local key=MYTHIC_KEYS[mythicIdx]
    mythDisp.Text=key or "(none)"
    local def=key and MythicItemDefs.Items[key]
    if not def then mythName.Text="";mythInfo.Text="No mythics defined." return end
    mythName.Text=def.DisplayName or key
    local base=def.BaseStatsAs or {}
    local subs={}
    for _,sdef in ipairs(def.SubStats or {}) do
        if sdef.useStandardRoll then
            table.insert(subs,sdef.id.." (std roll)")
        else
            table.insert(subs,string.format("%s %s-%s",sdef.id,tostring(sdef.min),tostring(sdef.max)))
        end
    end
    mythInfo.Text=string.format("%s  |  base as %s L%s (T%s)\nGuaranteed: %s\nSource: %s",
        tostring(def.Kind),tostring(base.rarity),tostring(base.level),tostring(base.tier),
        table.concat(subs,", "),tostring(def.SourceMobID))
end
refreshMythic()
mythPrev.Activated:Connect(function()
    if #MYTHIC_KEYS==0 then return end
    mythicIdx=((mythicIdx-2)%#MYTHIC_KEYS)+1;refreshMythic()
end)
mythNext.Activated:Connect(function()
    if #MYTHIC_KEYS==0 then return end
    mythicIdx=(mythicIdx%#MYTHIC_KEYS)+1;refreshMythic()
end)

local function spawnMythicAction()
    if not rfSpawnItem then showStatus("DevSpawnItem remote missing",true) return end
    local key=MYTHIC_KEYS[mythicIdx]
    if not key then showStatus("No mythic selected",true) return end
    local def=MythicItemDefs.Items[key] or {}
    local base=def.BaseStatsAs or {}
    local ok,result=pcall(function()
        return rfSpawnItem:InvokeServer({
            Mythic=key,
            Level=base.level or 21,
            Count=math.clamp(math.floor(tonumber(boxMythCount.Text) or 1),1,20),
        })
    end)
    if not ok or type(result)~="table" or not result.ok then
        local err=(type(result)=="table" and result.error) or tostring(result)
        showStatus("Mythic spawn failed: "..tostring(err),true)
        return
    end
    local it=result.item or {}
    showStatus(string.format("Spawned %s (%s, L%d)",tostring(it.name),tostring(it.rarity),tonumber(it.level) or 0))
end

local D=sectionY+SECTION_H+2
div(D)
local placeBtn=mkB(pnl,"Click to Place",10,D+8,W-20,36,Color3.fromRGB(40,80,40));placeBtn.TextSize=14
statusLbl=lbl(pnl,"",10,D+48,W-20,18,11,Color3.fromRGB(255,220,120),false,Enum.TextXAlignment.Center)
statusLbl.Visible=false
lbl(pnl,"MANAGED SPAWNERS",10,D+70,W-20,16,11,ACC,true)
local lf=Instance.new("ScrollingFrame",pnl);lf.Position=UDim2.fromOffset(8,D+88)
lf.Size=UDim2.fromOffset(W-16,math.max(80,H-(D+88)-8));lf.BackgroundTransparency=1;lf.BorderSizePixel=0
lf.ScrollBarThickness=4;lf.ScrollBarImageColor3=ACC
lf.AutomaticCanvasSize=Enum.AutomaticSize.Y;lf.CanvasSize=UDim2.new(0,0,0,0);lf.ZIndex=3
Instance.new("UIListLayout",lf).Padding=UDim.new(0,4)
local function syncTimeFieldsFromClock(clockTime)
	local t = DayNightConfig.clampClockTime(clockTime)
	local h = math.floor(t) % 24
	local m = math.floor((t % 1) * 60 + 0.5)
	if m >= 60 then m = 0 end
	boxTimeHour.Text = tostring(h)
	boxTimeMin.Text = tostring(m)
	if timePreviewLbl then
		timePreviewLbl.Text = DayNightConfig.formatClockTime(t)
	end
end
local function refreshTimeStatus(state)
	if mode ~= "Time" then return end
	if type(state) == "table" then
		syncTimeFieldsFromClock(state.clockTime)
		if timeStatusLbl then
			if state.devOverride then
				timeStatusLbl.Text = "Dev override — cycle paused"
				timeStatusLbl.TextColor3 = Color3.fromRGB(255, 200, 120)
			else
				timeStatusLbl.Text = "Auto cycle (20m day / 20m night)"
				timeStatusLbl.TextColor3 = Color3.fromRGB(180, 170, 140)
			end
		end
	else
		local ct = DayNightConfig.clockTimeFromHourMinute(boxTimeHour.Text, boxTimeMin.Text)
		if timePreviewLbl then
			timePreviewLbl.Text = DayNightConfig.formatClockTime(ct)
		end
	end
end
local function applyDevTime(hour, minute)
	if not rfDayNight then
		showStatus("DevDayNightControl missing", true)
		return
	end
	local ok, result = pcall(function()
		return rfDayNight:InvokeServer({ action = "SetTime", hour = hour, minute = minute })
	end)
	if not ok or type(result) ~= "table" or not result.ok then
		local err = (type(result) == "table" and result.error) or tostring(result)
		showStatus("Set time failed: " .. tostring(err), true)
		return
	end
	refreshTimeStatus(result.state)
	showStatus("Time set: " .. DayNightConfig.formatClockTime(result.state.clockTime))
end
local function resumeDevCycle()
	if not rfDayNight then
		showStatus("DevDayNightControl missing", true)
		return
	end
	local ok, result = pcall(function()
		return rfDayNight:InvokeServer({ action = "Resume" })
	end)
	if not ok or type(result) ~= "table" or not result.ok then
		local err = (type(result) == "table" and result.error) or tostring(result)
		showStatus("Resume failed: " .. tostring(err), true)
		return
	end
	refreshTimeStatus(result.state)
	showStatus("Automatic day/night cycle resumed")
end
local function fetchTimeState()
	if not rfDayNight then return end
	task.spawn(function()
		local ok, result = pcall(function()
			return rfDayNight:InvokeServer({ action = "Get" })
		end)
		if ok and type(result) == "table" and result.ok and type(result.state) == "table" then
			refreshTimeStatus(result.state)
		end
	end)
end
local function refreshMode()
    for _,m in ipairs(MODES) do
        modeButtons[m.key].BackgroundColor3 = (mode==m.key) and m.color or m.colorOff
    end
    mobSec.Visible=mode=="Mob";npcSec.Visible=mode=="NPC";zoneSec.Visible=mode=="Zone";timeSec.Visible=mode=="Time";itemSec.Visible=mode=="Gear";itemsSec.Visible=mode=="Items";mythicSec.Visible=mode=="Mythic"
    if mode~="Zone" then exploreMode=false end
    if mode=="Zone" then
        zoneSec.CanvasPosition=Vector2.new(0,0)
        updateGhost()
    elseif mode=="Time" or mode=="Gear" or mode=="Items" or mode=="Mythic" then updateGhost()
    else updateGhost(tonumber(boxRadius.Text)) end
    -- placeBtn is the panel's one shared "confirm" button; ITEMS deliberately has no use
    -- for it (each icon grants itself), so it's hidden rather than left pointing at Gear's
    -- spawn action -- that mismatch was the original bug (see the note above MODES).
    placeBtn.Visible = mode~="Items"
    if mode=="Zone" then
        placeBtn.Text=placingMode and "Drawing... (E or click)" or "Draw Zone"
    elseif mode=="Time" then
        placeBtn.Text="Apply Time"
        placeBtn.BackgroundColor3=Color3.fromRGB(40,80,40)
    elseif mode=="Gear" then
        placeBtn.Text="Spawn Item"
        placeBtn.BackgroundColor3=Color3.fromRGB(40,80,40)
        itemSec.CanvasPosition=Vector2.new(0,0)
    elseif mode=="Items" then
        itemsSec.CanvasPosition=Vector2.new(0,0)
    elseif mode=="Mythic" then
        placeBtn.Text="Spawn Mythic"
        placeBtn.BackgroundColor3=MythicItemDefs.RARITY_COLOR
        mythicSec.CanvasPosition=Vector2.new(0,0)
    else
        placeBtn.Text=placingMode and "Placing... (click world)" or "Click to Place"
    end
    if mode=="Time" then fetchTimeState() end
	player:SetAttribute("DevPlacerOpen", devVisualsActive())
	refreshPanelMouse()
end
showStatus=function(msg,isErr)
	if not statusLbl then return end
	statusLbl.Text=tostring(msg or "")
	statusLbl.TextColor3=isErr and Color3.fromRGB(255,120,120) or Color3.fromRGB(255,220,120)
	statusLbl.Visible=msg~=nil and msg~=""
end
devVisualsActive=function()
	return panelOpen or exploreMode or (placingMode and mode=="Zone")
end
refreshPanelMouse=function()
	local wantLook=panelOpen and not exploreMode and (rmbLookActive or UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))
	local wantFree=panelOpen and not exploreMode and not wantLook
	if wantLook then
		if panelMouseFree then
			MenuMouse.release()
			panelMouseFree=false
		end
		UIS.MouseBehavior=Enum.MouseBehavior.LockCenter
		UIS.MouseIconEnabled=false
	elseif wantFree then
		if not panelMouseFree then
			MenuMouse.acquire()
			panelMouseFree=true
		end
	else
		if panelMouseFree then
			MenuMouse.release()
			panelMouseFree=false
		end
		rmbLookActive=false
	end
end
RunService:BindToRenderStep(RMB_LOOK_BIND, Enum.RenderPriority.Last.Value + 1, function()
	if not (panelOpen and not exploreMode and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)) then
		return
	end
	UIS.MouseBehavior=Enum.MouseBehavior.LockCenter
	UIS.MouseIconEnabled=false
end)
setExploreMode=function(v)
	if mode~="Zone" or not placingMode then
		exploreMode=false
		sg.Enabled=panelOpen
		refreshPanelMouse()
		player:SetAttribute("DevPlacerOpen", devVisualsActive())
		return
	end
	exploreMode=v
	sg.Enabled=panelOpen and not exploreMode
	zonePreview.Parent=devVisualsActive() and workspace or nil
	player:SetAttribute("DevPlacerOpen", devVisualsActive())
	refreshPanelMouse()
	if exploreMode then
		showStatus("Fly mode: WASD+Space/Ctrl, E=corner, Enter=finish, F8=panel")
	else
		showStatus("Panel open — Hide & Fly to move around")
	end
end
setPlacing=function(v)
    if mode=="Time" or mode=="Gear" or mode=="Items" then placingMode=false; return end
    placingMode=v
    zonePreview.Parent=(v and mode=="Zone" and devVisualsActive()) and workspace or nil
    if not v then
		if mode=="Zone" then clearZoneDraw() end
		setExploreMode(false)
	end
    if mode=="Zone" then
        placeBtn.Text=v and "Drawing... (E or click)" or "Draw Zone"
    else
        placeBtn.Text=v and "Placing... (click world)" or "Click to Place"
    end
    placeBtn.BackgroundColor3=v and Color3.fromRGB(140,110,20) or Color3.fromRGB(40,80,40)
	player:SetAttribute("DevPlacerOpen", devVisualsActive())
	refreshPanelMouse()
end
local function setPanelOpen(v)
    panelOpen=v
	sg.Enabled=v and not exploreMode
    player:SetAttribute("DevPlacerOpen", devVisualsActive())
    if v then
		refreshPanelMouse()
	else
		rmbLookActive=false
		exploreMode=false
		if not (placingMode and mode=="Zone") then
			setPlacing(false)
			clearZoneDraw()
			zonePreview.Parent=nil
			showStatus("")
		else
			zonePreview.Parent=workspace
			showStatus("Panel hidden — F8 to reopen, Enter to finish zone")
		end
		refreshPanelMouse()
	end
end
refreshList=function()
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
        local isM=entry.SpawnerType=="Mob"
        local isZ=entry.SpawnerType=="Zone"
        local row=Instance.new("Frame",lf)
        row.Size=UDim2.new(1,0,0,isZ and 54 or 28);row.BackgroundColor3=Color3.fromRGB(35,26,26)
        row.BorderSizePixel=0;row.ZIndex=4
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,5)
        local p=entry.Position
        local coord=string.format("  [%.0f, %.0f, %.0f]",p.X,p.Y,p.Z)
        local rl=Instance.new("TextLabel",row);rl.BackgroundTransparency=1
        rl.Size=UDim2.new(1,-32,0,28);rl.Position=UDim2.fromOffset(8,0)
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
        if isZ then
            local musicBox=Instance.new("TextBox",row)
            musicBox.Position=UDim2.fromOffset(8,29);musicBox.Size=UDim2.fromOffset(row.AbsoluteSize.X>0 and (row.AbsoluteSize.X-70) or (W-86),20)
            musicBox.BackgroundColor3=Color3.fromRGB(14,10,10);musicBox.BorderSizePixel=0
            musicBox.Font=Enum.Font.GothamMedium;musicBox.TextSize=11;musicBox.TextColor3=Color3.new(1,1,1)
            musicBox.PlaceholderText="music id (blank = none)";musicBox.PlaceholderColor3=Color3.fromRGB(100,85,85)
            musicBox.ClearTextOnFocus=false;musicBox.Text=tostring(entry.MusicId or "");musicBox.ZIndex=5
            musicBox.TextXAlignment=Enum.TextXAlignment.Left
            Instance.new("UICorner",musicBox).CornerRadius=UDim.new(0,4)
            local musicStroke=Instance.new("UIStroke",musicBox);musicStroke.Thickness=1;musicStroke.Color=ACC
            local saveBtn=Instance.new("TextButton",row)
            saveBtn.AnchorPoint=Vector2.new(1,0);saveBtn.Position=UDim2.new(1,-4,0,29)
            saveBtn.Size=UDim2.fromOffset(50,20);saveBtn.BackgroundColor3=Color3.fromRGB(55,40,40)
            saveBtn.BorderSizePixel=0;saveBtn.Font=Enum.Font.GothamBold;saveBtn.TextSize=11
            saveBtn.TextColor3=Color3.new(1,1,1);saveBtn.Text="Save";saveBtn.ZIndex=5
            Instance.new("UICorner",saveBtn).CornerRadius=UDim.new(0,4)
            saveBtn.Activated:Connect(function()
                if not rfSetZoneMusic or type(zoneId)~="string" or zoneId=="" then return end
                local ok,result=pcall(function()
                    return rfSetZoneMusic:InvokeServer({ZoneId=zoneId,MusicId=musicBox.Text})
                end)
                if ok and type(result)=="table" and result.ok then
                    showStatus("Zone music updated: "..(result.zone and result.zone.name or zoneId))
                else
                    local err=(ok and type(result)=="table" and result.error) or tostring(result)
                    showStatus("Set music failed: "..tostring(err),true)
                end
            end)
        end
    end
end
btnFinishZone.Activated:Connect(finishZoneDraw)
btnClearZone.Activated:Connect(function() clearZoneDraw(); refreshZoneDrawPreview(); showStatus("Cleared corners") end)
btnHideFly.Activated:Connect(function() setExploreMode(not exploreMode) end)
closeX.Activated:Connect(function() setPanelOpen(false) end)
for _,m in ipairs(MODES) do
    local key,immediate=m.key,m.immediate
    modeButtons[key].Activated:Connect(function()
        mode=key
        if immediate then setPlacing(false) end
        refreshMode()
    end)
end
btnTimeDawn.Activated:Connect(function() applyDevTime(6, 0) end)
btnTimeNoon.Activated:Connect(function() applyDevTime(12, 0) end)
btnTimeDusk.Activated:Connect(function() applyDevTime(18, 0) end)
btnTimeMid.Activated:Connect(function() applyDevTime(0, 0) end)
btnResumeCycle.Activated:Connect(resumeDevCycle)
boxTimeHour.FocusLost:Connect(function() refreshTimeStatus() end)
boxTimeMin.FocusLost:Connect(function() refreshTimeStatus() end)
do
    task.spawn(function()
        if not GE then return end
        local dns = GE:WaitForChild("DayNightSync", 30)
        if dns and dns:IsA("RemoteEvent") then
            dns.OnClientEvent:Connect(function(state)
                if type(state)=="table" then refreshTimeStatus(state) end
            end)
        end
    end)
end
mobPrev.Activated:Connect(function() mobIdx=((mobIdx-2)%#MOB_IDS)+1;mobDisp.Text=MOB_IDS[mobIdx] end)
mobNext.Activated:Connect(function() mobIdx=(mobIdx%#MOB_IDS)+1;mobDisp.Text=MOB_IDS[mobIdx] end)
btnForceElite.Activated:Connect(function()
    if not evPlace then warn("[DevClient] evPlace missing");return end
    local mid=MOB_IDS[mobIdx];if not mid then return end
    evPlace:FireServer({SpawnerType="NamedElite",MobId=mid,Position=mouse.Hit.Position})
end)
npcPrev.Activated:Connect(function() npcIdx=((npcIdx-2)%#NPC_TYPES)+1;npcDisp.Text=NPC_TYPES[npcIdx] end)
npcNext.Activated:Connect(function() npcIdx=(npcIdx%#NPC_TYPES)+1;npcDisp.Text=NPC_TYPES[npcIdx] end)
placeBtn.Activated:Connect(function()
    if mode=="Time" then
        applyDevTime(boxTimeHour.Text, boxTimeMin.Text)
        return
    end
    if mode=="Gear" then
        spawnItemAction()
        return
    end
    -- mode=="Items" never reaches here -- placeBtn is hidden for that tab (see refreshMode);
    -- each catalog icon grants itself directly instead of going through this shared button.
    if mode=="Mythic" then
        spawnMythicAction()
        return
    end
    setPlacing(not placingMode)
end)
UIS.InputBegan:Connect(function(inp,gp)
    if inp.UserInputType==Enum.UserInputType.MouseButton2 and panelOpen and not exploreMode then
        rmbLookActive=true
        refreshPanelMouse()
    end
    if inp.KeyCode==Keys.CloseMenu then
        if exploreMode then setExploreMode(false); return end
        if placingMode then setPlacing(false);return end
        if panelOpen then setPanelOpen(false);return end
    end
    if inp.KeyCode==Keys.DevPlacer and not gp then
        if placingMode and mode=="Zone" and not panelOpen then
            setPanelOpen(true)
            refreshList(); refreshMode()
            return
        end
        setPanelOpen(not panelOpen)
        if panelOpen then refreshList();refreshMode() end
        return
    end
    if placingMode and mode=="Zone" then
        if inp.KeyCode==Keys.DevPlaceCorner and not gp then
            addZoneCorner()
            return
        end
        if inp.KeyCode==Keys.DevPlaceConfirm and not gp then
            finishZoneDraw()
            return
        end
        if inp.KeyCode==Keys.DevPlaceDelete and not gp then
            undoZoneCorner()
            return
        end
    end
    if not placingMode then return end
    if inp.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    if gp then return end
    if mode=="Zone" then
        addZoneCorner()
        return
    end
    if not evPlace then warn("[DevClient] evPlace missing");setPlacing(false);return end
    if mode=="Mob" then
        local mid=MOB_IDS[mobIdx];if not mid then return end
        evPlace:FireServer({SpawnerType="Mob",MobId=mid,
            Count=math.clamp(math.floor(tonumber(boxCount.Text) or 3),1,20),
            RespawnDelay=math.clamp(math.floor(tonumber(boxDelay.Text) or 10),1,300),
            ActivationRadius=math.clamp(math.floor(tonumber(boxRadius.Text) or 100),10,500),
            ZoneName=boxZone.Text~="" and boxZone.Text or "Default",
            Position=mouse.Hit.Position})
    elseif mode=="NPC" then
        local nn,ni=boxNpcName.Text,boxNpcId.Text
        if nn=="" or ni=="" then warn("[DevClient] Fill NPC Name and ID");return end
        evPlace:FireServer({SpawnerType="NPC",NpcType=NPC_TYPES[npcIdx],
            NpcName=nn,NpcId=ni,Position=mouse.Hit.Position})
    end
    setPlacing(false);task.delay(.5,refreshList)
end)
UIS.InputEnded:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton2 and rmbLookActive then
        rmbLookActive=false
        refreshPanelMouse()
    end
end)
refreshMode()
print("[DevClient] ready -- F8 DevPlacer | zone draw: E=corner Enter=finish Hide&Fly to explore")
