-- Cosmetic idle animations for tagged NPCs. Play locally so skinned-mesh
-- bones animate for each viewer, including clients that join after the NPC
-- has already started its idle on the server.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local tracks = setmetatable({}, { __mode = "k" })
local starting = setmetatable({}, { __mode = "k" })

local function startIdle(model)
	if not model:IsA("Model") or tracks[model] or starting[model] then return end
	starting[model] = true

	local config
	for _ = 1, 20 do
		if not model:IsDescendantOf(workspace) then break end
		local npcType = model:GetAttribute("NpcType")
		config = npcType and NPCRegistry.Get(npcType)
		if config then break end
		task.wait(0.25)
	end

	if config and config.IdleAnimationId and model:IsDescendantOf(workspace) then
		local controller = model:WaitForChild("AnimationController", 10)
		local animator = controller and controller:WaitForChild("Animator", 10)
		if not animator then
			-- An imported AnimationController can arrive without its Animator; the idle then does nothing.
			warn("[NpcIdleAnimations] no AnimationController > Animator on", model:GetFullName())
		end
		if animator and model:IsDescendantOf(workspace) then
			local animation = Instance.new("Animation")
			animation.Name = model:GetAttribute("NpcType") .. "Idle"
			animation.AnimationId = config.IdleAnimationId
			animation.Parent = controller

			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok then
				track.Priority = Enum.AnimationPriority.Idle
				track.Looped = true
				tracks[model] = { track = track, animation = animation }
				track:Play(0.2)
			else
				animation:Destroy()
				warn("[NpcIdleAnimations] failed to load", config.IdleAnimationId, track)
			end
		end
	end

	starting[model] = nil
end

local function stopIdle(model)
	local state = tracks[model]
	if not state then return end
	state.track:Stop(0)
	state.animation:Destroy()
	tracks[model] = nil
end

for _, model in ipairs(CollectionService:GetTagged("NPC")) do
	task.spawn(startIdle, model)
end
CollectionService:GetInstanceAddedSignal("NPC"):Connect(function(model)
	task.spawn(startIdle, model)
end)
CollectionService:GetInstanceRemovedSignal("NPC"):Connect(stopIdle)
