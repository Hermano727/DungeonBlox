local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local Debris            = game:GetService("Debris")
local SoundService      = game:GetService("SoundService")
local ContentProvider   = game:GetService("ContentProvider")

local Player       = Players.LocalPlayer
local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote")
-- PvP hit event. Lawful players are non-PvP — server enforces that, the client
-- just reports anything it raycasts and lets the server decide.
local PvPHitRemote = ReplicatedStorage:WaitForChild("DungeonPvPHit")
local TrySwing     = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("TrySwing")
local WeaponData   = require(ReplicatedStorage:WaitForChild("WeaponData"))
local ActiveEquipment = require(ReplicatedStorage:WaitForChild("ActiveEquipment"))
local ProfileMenusState = require(ReplicatedStorage:WaitForChild("ProfileMenusState"))
local Config       = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local CombatSfxConfig  = require(ReplicatedStorage:WaitForChild("CombatSfxConfig"))
local CombatAnimConfig = require(ReplicatedStorage:WaitForChild("CombatAnimConfig"))
local SfxService       = require(ReplicatedStorage:WaitForChild("SfxService"))

local partyMemberUserIds = {}
task.defer(function()
    local ge   = ReplicatedStorage:WaitForChild("GameEvents", 30)
    local sync = ge and ge:WaitForChild("PartyStateSync", 30)
    if sync and sync:IsA("RemoteEvent") then
        sync.OnClientEvent:Connect(function(payload)
            local ids = {}
            if type(payload) == "table" and type(payload.myParty) == "table" then
                local members = payload.myParty.members
                if type(members) == "table" then
                    for _, m in ipairs(members) do
                        if type(m.userId) == "number" then
                            ids[m.userId] = true
                        end
                    end
                end
            end
            partyMemberUserIds = ids
        end)
    end
end)

local attackTrack = nil
local attackCharacter = nil
local swingTool = nil
local characterGeneration = 0
local characterConnections = {}
local stopObservingEquipment = nil
local queuedSwingAt = nil
local lastSwingClickAt = nil
local smoothedClickInterval = 1 / CombatAnimConfig.SWING_DEFAULT_CPS
local swingStoppedConnection = nil
local swingGeneration = 0

local function resetSwing()
    swingGeneration += 1
    if swingStoppedConnection then swingStoppedConnection:Disconnect(); swingStoppedConnection = nil end
    queuedSwingAt = nil
    lastSwingClickAt = nil
    smoothedClickInterval = 1 / CombatAnimConfig.SWING_DEFAULT_CPS
    if attackTrack then attackTrack:Stop(CombatAnimConfig.CANCEL_FADE) end
end

local function canPresentSwing(character, tool)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    local gui = Player:FindFirstChildOfClass("PlayerGui")
    local menu = gui and gui:FindFirstChild("SkillsPopupUI", true)
    return character == Player.Character and hum and hum.Health > 0
        and tool ~= nil and ActiveEquipment.GetTool(character) == tool
        and WeaponData.ShouldUseClientHitDetection(WeaponData.GetWeaponIdFromTool(tool))
        and Player:GetAttribute("EnergyPanting") ~= true
        and not ProfileMenusState.IsOpen()
        and not UserInputService:GetFocusedTextBox()
        and not (menu and menu:IsA("ScreenGui") and menu.Enabled)
end

local function recordSwingClick(now)
    if not lastSwingClickAt or now - lastSwingClickAt > CombatAnimConfig.SWING_IDLE_RESET_SEC then
        smoothedClickInterval = 1 / CombatAnimConfig.SWING_DEFAULT_CPS
    else
        local interval = math.clamp(now - lastSwingClickAt,
            1 / CombatAnimConfig.SWING_MAX_CPS, 1 / CombatAnimConfig.SWING_MIN_CPS)
        smoothedClickInterval += CombatAnimConfig.SWING_INTERVAL_ALPHA * (interval - smoothedClickInterval)
    end
    lastSwingClickAt = now
end

local function swingPlaybackSpeed()
    local cps = math.clamp(1 / smoothedClickInterval,
        CombatAnimConfig.SWING_MIN_CPS, CombatAnimConfig.SWING_MAX_CPS)
    local speed = math.clamp(attackTrack.Length * cps / CombatAnimConfig.SWING_CYCLE_FRACTION,
        CombatAnimConfig.SWING_MIN_PLAYBACK_SPEED, CombatAnimConfig.SWING_MAX_PLAYBACK_SPEED)
    attackCharacter:SetAttribute("MeleeSwingCps", cps)
    attackCharacter:SetAttribute("MeleeSwingPlaybackSpeed", speed)
    attackCharacter:SetAttribute("MeleeSwingClipLength", attackTrack.Length)
    return speed
end

local function startSwing()
    if not attackTrack or attackTrack.Length <= 0 or not canPresentSwing(attackCharacter, swingTool) then return end
    if swingStoppedConnection then swingStoppedConnection:Disconnect() end
    swingGeneration += 1
    local generation, track = swingGeneration, attackTrack
    queuedSwingAt = nil
    track:Play(CombatAnimConfig.SWING_FADE_IN, 1, swingPlaybackSpeed())
    swingStoppedConnection = track.Stopped:Connect(function()
        if generation ~= swingGeneration or attackTrack ~= track or track.IsPlaying then return end
        local queuedAt = queuedSwingAt
        queuedSwingAt = nil
        if queuedAt and os.clock() - queuedAt <= CombatAnimConfig.SWING_QUEUE_MAX_AGE_SEC
            and canPresentSwing(attackCharacter, swingTool) then
            startSwing()
        end
    end)
end

local function PlayAttackAnimation(character, tool)
    if character ~= attackCharacter or not canPresentSwing(character, tool) then return end
    if tool ~= swingTool then resetSwing(); swingTool = tool end
    recordSwingClick(os.clock())
    -- Preserve locomotion while loading; never stop idle/walk to attempt a swing.
    if not attackTrack or attackTrack.Length <= 0 then return end
    if attackTrack.IsPlaying then
        attackTrack:AdjustSpeed(swingPlaybackSpeed())
        -- At most one follow-up visual. Fast bursts cannot create a backlog,
        -- and don't keep resetting the slash before it reaches its hit pose.
        queuedSwingAt = os.clock()
    else
        startSwing()
    end
end

local function clearAttackCharacter()
    characterGeneration += 1
    if stopObservingEquipment then stopObservingEquipment(); stopObservingEquipment = nil end
    for _, connection in ipairs(characterConnections) do connection:Disconnect() end
    table.clear(characterConnections)
    resetSwing()
    if attackTrack then attackTrack:Destroy(); attackTrack = nil end
    attackCharacter, swingTool = nil, nil
end

local function bindAttackCharacter(character)
    if character == attackCharacter then return end
    clearAttackCharacter()
    attackCharacter = character
    swingTool = ActiveEquipment.GetTool(character)
    local generation = characterGeneration
    stopObservingEquipment = ActiveEquipment.Observe(character, function(tool)
        if tool ~= swingTool then resetSwing(); swingTool = tool end
    end)
    task.spawn(function()
        local hum = character:WaitForChild("Humanoid", 10)
        local animator = hum and hum:WaitForChild("Animator", 10)
        if generation ~= characterGeneration or character ~= Player.Character then return end
        if not animator then warn("[CombatClient] Replicated Animator missing"); return end
        table.insert(characterConnections, hum.Died:Connect(resetSwing))
        local anim = Instance.new("Animation")
        anim.AnimationId = CombatAnimConfig.SWING_ANIM_ID
        local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
        if not ok then
            anim:Destroy()
            warn("[CombatClient] Swing animation load failed:", track)
            return
        end
        if generation ~= characterGeneration or character ~= Player.Character then
            track:Destroy()
            anim:Destroy()
            return
        end
        attackTrack = track
        track.Priority = CombatAnimConfig.ANIM_PRIORITY
        track.Looped = false
        local loaded, err = pcall(function()
            ContentProvider:PreloadAsync({ anim }, function(_, status)
                if generation == characterGeneration and status ~= Enum.AssetFetchStatus.Success then
                    warn("[CombatClient] Swing asset unavailable:", status.Name)
                end
            end)
        end)
        anim:Destroy()
        if not loaded and generation == characterGeneration then
            warn("[CombatClient] Swing preload failed:", err)
        end
    end)
end

local HITBOX_SIZE = CombatAnimConfig.HITBOX_SIZE

local function GetEquippedTool(character)
    return ActiveEquipment.GetTool(character)
end

local function ReportMobHit(mobUID, hitPos, weaponId)
    CombatRemote:FireServer(mobUID, hitPos, weaponId)
end

local function ReportPlayerHit(targetPlayer, hitPos, weaponId)
    if not targetPlayer or targetPlayer == Player then return end
    if partyMemberUserIds[targetPlayer.UserId] then return end
    PvPHitRemote:FireServer(targetPlayer, weaponId, hitPos)
end

-- Returns (kind, value) for what was hit:
--   "mob",    mobUID    -> hit a mob model (has MobUID attribute)
--   "player", Player    -> hit another player's character
--   nil               -> nothing combat-relevant
local function classifyHitModel(model)
    if not model then return nil end
    local mobUID = model:GetAttribute("MobUID")
    if mobUID then return "mob", mobUID end
    local hitPlayer = Players:GetPlayerFromCharacter(model)
    if hitPlayer and hitPlayer ~= Player then
        return "player", hitPlayer
    end
    return nil
end

local function PerformRaycastAttack(character, attackRange)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local ray = RaycastParams.new()
    ray.FilterDescendantsInstances = {character}
    ray.FilterType = Enum.RaycastFilterType.Exclude
    ray.IgnoreWater = true
    -- Origin MUST be the camera's own position, not hrp.Position. This is a
    -- first-person game -- HRP sits at torso height, noticeably below the
    -- camera/eye position, so a ray fired from HRP along the camera's
    -- LookVector traces a different line through the world than what the
    -- player actually sees down their crosshair. At close range that gap
    -- means aiming above a short mob's body can still trace back down
    -- through it, registering a hit the player visually shouldn't have
    -- landed. Firing from the camera's actual position makes the ray match
    -- the view exactly.
    local camera = workspace.CurrentCamera
    local origin = camera.CFrame.Position
    local result = workspace:Raycast(origin, camera.CFrame.LookVector * attackRange, ray)
    if result then
        local model = result.Instance:FindFirstAncestorOfClass("Model")
        local weaponId = WeaponData.GetWeaponIdFromTool(GetEquippedTool(character))
        local kind, value = classifyHitModel(model)
        if kind == "mob" then
            ReportMobHit(value, result.Position, weaponId)
            return true
        elseif kind == "player" then
            ReportPlayerHit(value, result.Position, weaponId)
            return true
        end
    end
    return false
end

local function PerformHitboxAttack(character, attackRange)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local cf = CFrame.new(hrp.Position + hrp.CFrame.LookVector * math.min(attackRange * 0.5, 5))
    local op = OverlapParams.new()
    op.FilterDescendantsInstances = {character}
    op.FilterType = Enum.RaycastFilterType.Exclude
    local weaponId = WeaponData.GetWeaponIdFromTool(GetEquippedTool(character))
    -- Track the closest player target so we don't fire multiple PvP events per swing.
    local closestPlayer, closestPlayerDist = nil, math.huge
    for _, part in ipairs(workspace:GetPartBoundsInBox(cf, HITBOX_SIZE, op)) do
        local model = part:FindFirstAncestorOfClass("Model")
        local kind, value = classifyHitModel(model)
        if kind == "mob" then
            ReportMobHit(value, (model.PrimaryPart and model.PrimaryPart.Position) or part.Position, weaponId)
            return true
        elseif kind == "player" then
            local root = model:FindFirstChild("HumanoidRootPart")
            local d = root and (root.Position - hrp.Position).Magnitude or math.huge
            if d < closestPlayerDist then
                closestPlayer, closestPlayerDist = value, d
            end
        end
    end
    if closestPlayer then
        local tgtChar = closestPlayer.Character
        local tgtRoot = tgtChar and tgtChar:FindFirstChild("HumanoidRootPart")
        local hitPos = tgtRoot and tgtRoot.Position or hrp.Position
        ReportPlayerHit(closestPlayer, hitPos, weaponId)
        return true
    end
    return false
end

local function OnAttackInput()
    if ProfileMenusState.IsOpen() or UserInputService:GetFocusedTextBox() then return end
    local gui = Player:FindFirstChildOfClass("PlayerGui")
    local menu = gui and gui:FindFirstChild("SkillsPopupUI", true)
    if menu and menu:IsA("ScreenGui") and menu.Enabled then return end
    local character = Player.Character
    if not character then 
        warn("[CombatClient] No character")
        return 
    end

    local tool = GetEquippedTool(character)
    if not tool then 
        warn("[CombatClient] No tool equipped")
        return 
    end
    
    print("[CombatClient] Tool equipped: " .. tool.Name)

    local weaponId = WeaponData.GetWeaponIdFromTool(tool)
    print("[CombatClient] WeaponId: " .. tostring(weaponId))

    -- Gate: only registered combat weapons drain energy and hit mobs.
    -- Pickaxe, fishing rod, etc. return nil from GetWeaponIdFromTool → skipped here.
    if not weaponId or not WeaponData.Weapons or not WeaponData.Weapons[weaponId] then 
        warn("[CombatClient] Weapon not registered: " .. tool.Name)
        return 
    end

    if Player:GetAttribute("EnergyPanting") == true then
        return
    end

    -- Client-side energy check (server is authoritative; this just prevents redundant fires)
    local energyValue = Player:FindFirstChild("Energy")
    local swingMult = tool:GetAttribute("WeaponSwingMult") or 1
    local effectiveCost = Config.SWING_COST * swingMult
    if energyValue and energyValue.Value < effectiveCost then 
        warn("[CombatClient] Not enough energy: " .. tostring(energyValue.Value) .. " / " .. tostring(effectiveCost) .. " — triggering pant")
        TrySwing:FireServer(weaponId)  -- notify server so it can trigger depletion/pant
        return  -- still skip animation and hit detection
    end

    -- Visual timing follows eligible melee clicks; hit/energy timing is unchanged.
    if WeaponData.ShouldUseClientHitDetection(weaponId) then
        PlayAttackAnimation(character, tool)
    end

    -- Deduct energy server-side
    TrySwing:FireServer(weaponId)

    -- Client-side hit detection (melee only)
    if not WeaponData.ShouldUseClientHitDetection(weaponId) then return end
    local range = WeaponData.GetStats(weaponId).MaxRange
    if not PerformRaycastAttack(character, range) then
        PerformHitboxAttack(character, range)
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        OnAttackInput()
    end
end)

Player.CharacterAdded:Connect(bindAttackCharacter)
Player.CharacterRemoving:Connect(function(character)
    if character == attackCharacter then clearAttackCharacter() end
end)
Player:GetAttributeChangedSignal("EnergyPanting"):Connect(function()
    if Player:GetAttribute("EnergyPanting") == true then resetSwing() end
end)
ProfileMenusState.Subscribe(function()
    if ProfileMenusState.IsOpen() then resetSwing() end
end)
script.Destroying:Connect(clearAttackCharacter)
if Player.Character then bindAttackCharacter(Player.Character) end

print("CombatClient initialized with animation system")

task.defer(function()
	local ge = ReplicatedStorage:WaitForChild("GameEvents", 30)
	if not ge then
		return
	end
	local ev = ge:WaitForChild("MeleeHitGlass", 30)
	if not ev or not ev:IsA("RemoteEvent") then
		return
	end
	local rng = Random.new()

	local function applyConfiguredTrim(snd, cfg)
		local trim = tonumber(cfg.MELEE_HIT_GLASS_TRIM_START_SEC) or 0
		if trim <= 0 then
			return
		end
		pcall(function()
			ContentProvider:PreloadAsync({ snd })
		end)
		local len = tonumber(snd.TimeLength) or 0
		if len > 0 then
			trim = math.clamp(trim, 0, math.max(0, len - 0.02))
		end
		snd.TimePosition = math.max(0, trim)
	end

	-- soundId: server-resolved per mob type (MobClass:GetHitSoundId() /
	-- overrides like SkeletonMobClass) -- nil/empty means the mob had no
	-- override, so this falls back to the shared default glass clip exactly
	-- like before soundId existed.
	ev.OnClientEvent:Connect(function(soundId)
		local cfg = CombatSfxConfig
		local usingDefaultClip = type(soundId) ~= "string" or soundId == ""
		local snd = Instance.new("Sound")
		snd.Name = "MeleeHitGlass"
		snd.SoundId = usingDefaultClip and cfg.MELEE_HIT_GLASS_SOUND_ID or soundId
		snd.Volume = cfg.VOLUME or 0.95
		snd.Looped = false
		snd.RollOffMode = Enum.RollOffMode.Linear
		snd.MaxDistance = 80
		snd.PlaybackSpeed = rng:NextNumber(cfg.PITCH_MIN or 0.9, cfg.PITCH_MAX or 1.15)
		-- Route through the same SoundService.Main.Effects bus as
		-- SfxService.PlayEffect (crit hits, item pickups) so the Settings
		-- menu's "VFX" slider actually reaches the single most frequent
		-- combat sound in the game -- this was the whole reason the
		-- SFX/VFX sliders looked broken: every other one-shot effect sound
		-- was correctly grouped, but this one (played on EVERY hit) never
		-- was, so dragging either slider never seemed to change anything.
		snd.SoundGroup = SfxService.GetEffectsGroup()
		snd.Parent = SoundService
		-- MELEE_HIT_GLASS_TRIM_START_SEC is tuned for the default clip's own
		-- leading silence -- only apply it when that's actually what's
		-- playing, never to a mob-specific override sound with unknown padding.
		if usingDefaultClip then
			applyConfiguredTrim(snd, cfg)
		end
		local played = false
		pcall(function()
			if SoundService.PlayLocalSound then
				SoundService:PlayLocalSound(snd)
				played = true
			end
		end)
		if not played then
			local char = Player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			snd.Parent = root or workspace.CurrentCamera or SoundService
			pcall(function()
				snd:Play()
			end)
		end
		Debris:AddItem(snd, 6)
	end)
end)
