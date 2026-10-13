-- Owner-only Animator playback. Observers receive only the timed VFX copy.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Config = require(RS:WaitForChild("PotionDrinkConfig"))
local Assets = require(RS:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("PotionAnimations"))
local PotionAction = require(RS:WaitForChild("PotionAction"))
local JumpAnimations = require(RS:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("JumpAnimations"))

local Effect = require(script.Parent:WaitForChild("PotionDrinkEffect"))
local Presentation = require(script.Parent:WaitForChild("PotionPresentation"))
local player = Players.LocalPlayer
local remote = RS:WaitForChild("GameEvents"):WaitForChild("PotionDrunk")

local pending = {}
local owner

-- Tracks the drink takes the arms from: the Action layers (swings, bow draws), Action through Action4.
-- NOT a numeric ">= Action" test: Enum.AnimationPriority.Core is 1000, so that also caught the walk /
-- run / idle loops (Animate2 plays them at Core). Stopping those left the legs in the bind pose for the
-- whole drink: a T-pose that slid along without stepping, and the player could not "walk" while drinking.
local function isActionLayer(track)
	local value = track.Priority.Value
	if value < Enum.AnimationPriority.Action.Value or value > Enum.AnimationPriority.Action4.Value then return false end
	-- A jump's BODY clip (legs and spine, RS/Assets/Animations/JumpAnimations) is not the drink's to stop:
	-- it keeps the legs posed while the arms drink. Its ARMS clip is, like any other arm animation.
	return not (track.Animation and JumpAnimations.IsBodyClip(track.Animation.AnimationId))
end

local function clearOwner()
	if not owner then return end
	local state = owner
	owner = nil
	player:SetAttribute("PotionAnimationReady", false)
	player:SetAttribute("PotionDrinkCameraUntil", nil)
	for _, c in ipairs(state.connections) do c:Disconnect() end
	if state.track then state.track:Stop(0); state.track:Destroy() end
	if state.animation then state.animation:Destroy() end
end

local function tryLoad(state)
	if owner ~= state or state.track or state.loading or Assets.T1_POTION_DRINK == "" then return end
	state.loading = true
	task.spawn(function()
		local character = state.character
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", Config.ANIMATION_LOAD_TIMEOUT)
		-- Never manufacture a client Animator. Retry missing rig pieces on replication/drink.
		local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", Config.ANIMATION_LOAD_TIMEOUT))
		local mesh = character:FindFirstChild("Hero_Character")
		state.loading = false
		if owner ~= state then return end
		if not animator or not mesh or not mesh:FindFirstChild("Hand_R", true) then
			return
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = Assets.T1_POTION_DRINK
		local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
		if not ok then
			animation:Destroy()
			character:SetAttribute("PotionAnimationStatus", "LoadFailed")
			warn("[PotionDrink] Animation load failed:", track)
			return
		end
		if owner ~= state then track:Destroy(); animation:Destroy(); return end
		state.animation, state.track, state.animator = animation, track, animator
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		character:SetAttribute("PotionAnimationStatus", "Loading")
		table.insert(state.connections, humanoid.Died:Connect(clearOwner))
		table.insert(state.connections, animator.AnimationPlayed:Connect(function(other)
			if other ~= track and PotionAction.IsLocked(character) and isActionLayer(other) then other:Stop(0) end
		end))
		local function refreshReady()
			if owner == state then
				player:SetAttribute("PotionAnimationReady", track.Length > 0)
			end
		end
		table.insert(state.connections, track:GetPropertyChangedSignal("Length"):Connect(refreshReady))
		refreshReady()
		task.spawn(function()
			local loaded, loadError = pcall(function()
				ContentProvider:PreloadAsync({animation}, function(assetId, status)
				end)
			end)
			if owner == state then character:SetAttribute("PotionAnimationStatus", loaded and "Fetched" or "LoadFailed"); refreshReady() end
		end)
	end)
end

local function prepareCharacter(character)
	clearOwner()
	local state = {character = character, connections = {}, serial = 0}
	owner = state
	player:SetAttribute("PotionAnimationReady", Assets.T1_POTION_DRINK == "")
	table.insert(state.connections, character.DescendantAdded:Connect(function(child)
		if child:IsA("Animator") or child.Name == "Hand_R" then tryLoad(state) end
	end))
	tryLoad(state)
end

local function validCharacter(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return character and character.Parent and humanoid and humanoid.Health > 0
end

local function onDrink(payload)
	if not validCharacter(payload.character) then return end
	if payload.character == player.Character then
		payload.character:SetAttribute(PotionAction.ATTRIBUTE, payload.finishAt)
	end
	local age = math.max(0, workspace:GetServerTimeNow() - payload.sentAt)
	if age > Config.MAX_EVENT_AGE then return end
	local animated = payload.animated and Assets.T1_POTION_DRINK ~= ""
	Presentation.Prepare(payload, animated and Config.ANIMATION_DURATION or Config.MAX_EVENT_AGE)
	if not animated then Effect.Play(payload); return end
	local popAt = payload.sentAt + Config.CORK_POP_TIME
	local record = {cancelled = false, fired = false}
	pending[payload.drinkId] = record
	local function pop()
		if record.fired or record.cancelled or not validCharacter(payload.character) then return end
		record.fired = true
		if record.marker then record.marker:Disconnect(); record.marker = nil end
		Presentation.Prepare(payload, Config.ANIMATION_DURATION)
		Effect.Play(payload, {timeScale = Config.ANIMATED_VFX_TIME_SCALE,
			elapsed = math.max(0, workspace:GetServerTimeNow() - popAt)})
	end
	local state = payload.character == player.Character and owner
	if state then tryLoad(state) end
	local track = state and state.track
	local ready = track and track.Length > 0 -- re-evaluate every drink, even after a slow load
	if ready and age < Config.ANIMATION_DURATION then -- Drinking owns the arms until its deadline. End an in-progress attack,
		-- but keep every Core/Idle/Movement locomotion track playing: the clip is upper body only, so the legs keep walking.
		for _, other in ipairs(state.animator:GetPlayingAnimationTracks()) do
			if other ~= track and isActionLayer(other) then other:Stop(Config.ANIMATION_FADE_IN) end
		end
		state.serial += 1
		record.owner, record.serial = state, state.serial
		record.marker = track:GetMarkerReachedSignal(Config.CORK_POP_MARKER):Connect(pop)
		track:Play(Config.ANIMATION_FADE_IN, 1, 1)
		track.TimePosition = math.min(age, track.Length)
		Presentation.TrackStarted(payload.character, track)
		payload.character:SetAttribute("PotionAnimationStatus", "Playing")
		player:SetAttribute("PotionDrinkCameraUntil", payload.sentAt + Config.ANIMATION_DURATION)
		task.delay(math.max(0, Config.ANIMATION_DURATION - age), function()
			if owner == state and state.serial == record.serial then
				track:Stop(Config.ANIMATION_FADE_OUT)
				player:SetAttribute("PotionDrinkCameraUntil", nil)
			end
		end)
	elseif state and not ready then
		payload.character:SetAttribute("PotionAnimationStatus", "VfxFallbackLoading")
	elseif payload.character == player.Character then end
	-- One confirmed action; the marker and timed observer fallback can only fire once.
	local remaining = math.max(0, popAt - workspace:GetServerTimeNow())
	if remaining == 0 then
		pop()
	else task.delay(remaining + (record.owner and Config.MARKER_FALLBACK_GRACE or 0), pop) end
	task.delay(Config.MAX_EVENT_AGE + Config.ANIMATION_DURATION, function()
		if record.marker then record.marker:Disconnect() end
		pending[payload.drinkId] = nil
	end)
end

local connection = remote.OnClientEvent:Connect(onDrink)
local added = player.CharacterAdded:Connect(prepareCharacter)
local prepareRequested = player:GetAttributeChangedSignal("PotionAnimationPrepare"):Connect(function()
	if not owner then return end
	if owner.track then
		player:SetAttribute("PotionAnimationReady", owner.track.Length > 0)
	else tryLoad(owner) end
end)
local removing = player.CharacterRemoving:Connect(function()
	clearOwner()
	for _, record in pairs(pending) do record.cancelled = true end
	Effect.Clear()
end)
if player.Character then prepareCharacter(player.Character) end
script.Destroying:Connect(function()
	connection:Disconnect(); added:Disconnect(); removing:Disconnect(); prepareRequested:Disconnect()
	for _, record in pairs(pending) do
		record.cancelled = true
		if record.marker then record.marker:Disconnect() end
	end
	clearOwner()
	Effect.Clear()
end)
