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
local Config       = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local CombatSfxConfig  = require(ReplicatedStorage:WaitForChild("CombatSfxConfig"))
local CombatAnimConfig = require(ReplicatedStorage:WaitForChild("CombatAnimConfig"))

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

local animator = nil
local attackTracks = {}
local currentAttackTrack = nil
local attackComboIndex = 1
local isAttacking = false

local function InitAnimator(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        warn("[CombatClient] No Humanoid found in character")
        return nil
    end

    -- WaitForChild ensures we get Roblox's real Animator (created by the Animate
    -- LocalScript). FindFirstChildOfClass too early returns nil and causes a
    -- duplicate Animator that silently swallows all animation calls.
    local anim = humanoid:FindFirstChildOfClass("Animator")
        or humanoid:WaitForChild("Animator", 10)

    if not anim then
        warn("[CombatClient] No Animator found — creating fallback")
        anim = Instance.new("Animator")
        anim.Parent = humanoid
    end

    return anim
end

local function LoadAttackAnimations()
    if not animator then return end
    local animObj = Instance.new("Animation")
    animObj.AnimationId = CombatAnimConfig.SWING_ANIM_ID
    local track = animator:LoadAnimation(animObj)
    track.Priority = CombatAnimConfig.ANIM_PRIORITY
    table.insert(attackTracks, track)
    animObj:Destroy()
    print("[CombatClient] Loaded swing animation: " .. CombatAnimConfig.SWING_ANIM_ID)
    -- [[ DEBUG: uncomment to inspect rig type and track on load
    -- if CombatAnimConfig.DEBUG then
    --     local char = Player.Character
    --     local hum  = char and char:FindFirstChildOfClass("Humanoid")
    --     warn("[CombatAnim] RigType:", hum and hum.RigType)
    --     warn("[CombatAnim] AnimId:", CombatAnimConfig.SWING_ANIM_ID)
    --     warn("[CombatAnim] Track length:", track.Length)
    -- end
    --]]
end

local function PlayAttackAnimation()
    if not animator then
        warn("[CombatClient] No animator")
        return
    end

    if #attackTracks == 0 then
        warn("[CombatClient] No attack tracks loaded")
        return
    end

    -- Cancel current attack if playing (snappy high-CPS cancellation)
    if currentAttackTrack and currentAttackTrack.IsPlaying then
        currentAttackTrack:Stop(CombatAnimConfig.CANCEL_FADE)
    end

    attackComboIndex = (attackComboIndex % #attackTracks) + 1
    currentAttackTrack = attackTracks[attackComboIndex]

    currentAttackTrack:Play()
    currentAttackTrack:AdjustSpeed(CombatAnimConfig.ANIM_SPEED_MULT)
    -- [[ DEBUG: uncomment to inspect per-swing playback
    -- if CombatAnimConfig.DEBUG then
    --     warn("[CombatAnim] Play() | Length:", currentAttackTrack.Length,
    --          "| IsPlaying:", currentAttackTrack.IsPlaying,
    --          "| Speed:", CombatAnimConfig.ANIM_SPEED_MULT,
    --          "| AnimId:", CombatAnimConfig.SWING_ANIM_ID)
    -- end
    --]]

    isAttacking = true
    task.delay(currentAttackTrack.Length / CombatAnimConfig.ANIM_SPEED_MULT, function()
        if currentAttackTrack == attackTracks[attackComboIndex] then
            isAttacking = false
        end
    end)
end

local HITBOX_SIZE = CombatAnimConfig.HITBOX_SIZE

local function GetEquippedTool(character)
    return character and character:FindFirstChildOfClass("Tool")
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
    local result = workspace:Raycast(hrp.Position, workspace.CurrentCamera.CFrame.LookVector * attackRange, ray)
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
    local character = Player.Character
    if not character then 
        warn("[CombatClient] No character")
        return 
    end

    -- Initialize animator if needed
    if not animator then
        print("[CombatClient] Initializing animator...")
        animator = InitAnimator(character)
        if animator then
            LoadAttackAnimations()
        else
            warn("[CombatClient] Failed to initialize animator")
        end
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

    -- Play attack animation (with cancellation for high CPS)
    PlayAttackAnimation()

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

-- Reinitialize animator on character respawn
Player.CharacterAdded:Connect(function(character)
    animator = nil
    attackTracks = {}
    currentAttackTrack = nil
    attackComboIndex = 1
    isAttacking = false
    
    -- InitAnimator uses WaitForChild internally — no fixed wait needed
    animator = InitAnimator(character)
    if animator then
        LoadAttackAnimations()
    end
end)

-- Initial setup if character already exists
task.spawn(function()
    if Player.Character then
        animator = InitAnimator(Player.Character)
        if animator then
            LoadAttackAnimations()
        end
    end
end)

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

	ev.OnClientEvent:Connect(function()
		local cfg = CombatSfxConfig
		local snd = Instance.new("Sound")
		snd.Name = "MeleeHitGlass"
		snd.SoundId = cfg.MELEE_HIT_GLASS_SOUND_ID
		snd.Volume = cfg.VOLUME or 0.95
		snd.Looped = false
		snd.RollOffMode = Enum.RollOffMode.Linear
		snd.MaxDistance = 80
		snd.PlaybackSpeed = rng:NextNumber(cfg.PITCH_MIN or 0.9, cfg.PITCH_MAX or 1.15)
		snd.Parent = SoundService
		applyConfiguredTrim(snd, cfg)
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
