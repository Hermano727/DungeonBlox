--[[
	AnimationShowcase -- ServerScriptService (dev only)

	A platform far off the map (Workspace.AnimationShowcase, at ORIGIN) where every MobData mob with
	a model in ServerStorage.MobModels stands on its own pedestal, so its animations and specials
	can be played at will from the F8 menu's Showcase tab (client/DevMenu/Tabs/Showcase).

	Built lazily, the first time a dev asks for the catalogue, so no server pays for it otherwise.
	Everything is played here on the server, so every client there sees the same thing.

	What a mob can play:
	  - every clip registered for it in RS/MobAnimConfig: plain ids (Idle, Walk, Attack...), lists
	    (Walk#1, Walk#2) and each Moveset clip (Moveset/AxeCombo3Hit); Attack plays at the config's
	    AttackSpeed and a Moveset clip at its MobData entry's Speed, as in a real fight.
	  - every Cast special in its MobData Moveset whose handler has Showcase() (Kane's Fire Tornado),
	    which replays the whole cast, effects included, without damage.
	Play repeats until Stop or another Play: clips replay each time they end (replaying is what
	replicates reliably; a server-side Looped flag may not), casts every handler-given period.

	Remote GameEvents/DevShowcase (RemoteFunction), DevRoster-gated:
	  ("catalog")             -> { ok, mobs = { {id, name, tier, pedestal, anims, playing} }, origin, span }
	  ("goto", mobId?)        teleport in front of that pedestal (or the platform), remembering where
	                          you came from the first time
	  ("return")              back to where you were
	  ("play", mobId, key)    / ("stop", mobId)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local DevRoster = require(ReplicatedStorage:WaitForChild("DevRoster"))
local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local MobAnimConfig = require(ReplicatedStorage:WaitForChild("MobAnimConfig"))
local MobAnimController = require(ServerScriptService:WaitForChild("MobAnimController"))
local MobMovesetBehaviour = require(ServerScriptService:WaitForChild("MobMovesetBehaviour"))
local Remote = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("DevShowcase")

local ORIGIN = Vector3.new(0, 600, -60000) -- far -Z: the tutorial copies are +Z, dungeon realms +X
local FLOOR_DEPTH = 80
local GAP = 12
local MIN_SLOT = 16
local REPLAY_PAUSE = 0.4

local showcase = nil -- { entries = { [mobId] = entry }, order = { mobId }, center, span }
local building = false
local returnTo = {}  -- [player] = CFrame before their first jump here

---------------------------------------------------------------- what a mob can play

local function movesetEntries(stats)
	local set = stats and stats.Moveset
	if type(set) ~= "table" then return {} end
	if set.Id or set.HitTimes or set.Cast then return { set } end
	return set
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do table.insert(keys, k) end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

local function isAnimId(v)
	return type(v) == "string" and v:find("rbxassetid://", 1, true) ~= nil
end

local function animsFor(mobId)
	local anims = {}
	local cfg = MobAnimConfig[mobId]
	if type(cfg) == "table" then
		for _, key in ipairs(sortedKeys(cfg)) do
			local value = cfg[key]
			if isAnimId(value) then
				table.insert(anims, { key = key, label = key })
			elseif type(value) == "table" and key == "Moveset" then
				for _, name in ipairs(sortedKeys(value)) do
					if isAnimId(value[name]) then
						table.insert(anims, { key = "Moveset/" .. name, label = "Moveset: " .. name })
					end
				end
			elseif type(value) == "table" then
				for i, id in ipairs(value) do
					if isAnimId(id) then table.insert(anims, { key = key .. "#" .. i, label = key .. " " .. i }) end
				end
			end
		end
	end
	for _, entry in ipairs(movesetEntries(MobData.FindMobById(mobId))) do
		local handler = entry.Cast and MobMovesetBehaviour.Casts[entry.Cast]
		if handler and handler.Showcase then
			table.insert(anims, { key = "Cast/" .. entry.Cast, label = entry.Cast .. " (cast, with effects)" })
		end
	end
	return anims
end

-- key -> asset id and playback speed, as the mob would play it in a fight.
local function resolveClip(mobId, key)
	local cfg = MobAnimConfig[mobId]
	if type(cfg) ~= "table" then return nil end
	local name = key:match("^Moveset/(.+)$")
	if name then
		local speed = 1
		for _, entry in ipairs(movesetEntries(MobData.FindMobById(mobId))) do
			if entry.Id == name and tonumber(entry.Speed) then speed = entry.Speed end
		end
		return type(cfg.Moveset) == "table" and cfg.Moveset[name], speed
	end
	local listKey, index = key:match("^(.+)#(%d+)$")
	if listKey then
		return type(cfg[listKey]) == "table" and cfg[listKey][tonumber(index)], 1
	end
	return cfg[key], key == "Attack" and (tonumber(cfg.AttackSpeed) or 1) or 1
end

---------------------------------------------------------------- the platform

local function part(name, size, cframe, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.Material = Enum.Material.Slate
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A display copy: the root holds it in place, scripts off, no name/health bar.
local function prepareDisplay(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") then d.Enabled = false end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if root then
		model.PrimaryPart = root
		root.Anchored = true
		if humanoid then
			-- A rig's limbs must be free to move on their joints; only the root is pinned.
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d ~= root and d:FindFirstChildWhichIsA("JointInstance") then d.Anchored = false end
			end
		end
	end
end

local function nameplate(parent, text, height)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = 140
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(255, 225, 160)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
end

local function build()
	local folder = Instance.new("Folder")
	folder.Name = "AnimationShowcase"
	local models = ServerStorage:FindFirstChild("MobModels")
	local mobs = {}
	for tier = 1, 5 do
		for id, stats in pairs(MobData[tier] or {}) do
			if type(stats) == "table" then table.insert(mobs, { id = id, tier = tier, stats = stats }) end
		end
	end
	table.sort(mobs, function(a, b) return a.tier == b.tier and a.id < b.id or a.tier < b.tier end)

	local entries, order = {}, {}
	local x = 0
	local floorTop = ORIGIN.Y
	for _, mob in ipairs(mobs) do
		local template = models and models:FindFirstChild(mob.stats.ModelName or mob.id)
		if template then
			local model = template:Clone()
			model.Name = "Showcase_" .. mob.id
			prepareDisplay(model)
			model:SetAttribute("ShowcaseMobID", mob.id)
			-- Face the walkway (+Z), then sit the bounding box on the pedestal, centred in its slot.
			model:PivotTo(CFrame.lookAt(ORIGIN, ORIGIN + Vector3.new(0, 0, 1)))
			local _, size = model:GetBoundingBox()
			local width = math.max(MIN_SLOT, math.max(size.X, size.Z) + 6)
			local cx = ORIGIN.X + x + width / 2
			local box = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() + Vector3.new(cx - box.Position.X, floorTop + 1 + size.Y / 2 - box.Position.Y, ORIGIN.Z - box.Position.Z))
			model.Parent = folder

			local pedestal = part("Pedestal_" .. mob.id, Vector3.new(width - 2, 1, math.max(10, size.Z + 6)),
				CFrame.new(cx, floorTop + 0.5, ORIGIN.Z), Color3.fromRGB(58, 52, 48), folder)
			nameplate(pedestal, string.format("%s  (T%d)", mob.stats.Name or mob.id, mob.tier), size.Y + 3)

			local standZ = ORIGIN.Z + math.max(14, size.Z / 2 + size.Y * 0.9)
			local standPos = Vector3.new(cx, floorTop + 3.5, standZ)
			entries[mob.id] = {
				id = mob.id,
				name = mob.stats.Name or mob.id,
				tier = mob.tier,
				model = model,
				animator = MobAnimController.GetAnimator(model),
				pedestal = pedestal.Position,
				stand = CFrame.lookAt(standPos, Vector3.new(cx, standPos.Y, ORIGIN.Z)),
				anims = animsFor(mob.id),
				tracks = {},
				token = 0,
			}
			table.insert(order, mob.id)
			x += width + GAP
		end
	end

	local length = math.max(x, 40) + 40
	part("Floor", Vector3.new(length, 2, FLOOR_DEPTH),
		CFrame.new(ORIGIN.X + x / 2, floorTop - 1, ORIGIN.Z + FLOOR_DEPTH * 0.25), Color3.fromRGB(40, 38, 36), folder)
	folder.Parent = Workspace
	return {
		entries = entries,
		order = order,
		center = Vector3.new(ORIGIN.X + x / 2, floorTop, ORIGIN.Z),
		span = length / 2 + 40,
		entrance = CFrame.lookAt(Vector3.new(ORIGIN.X + 8, floorTop + 3.5, ORIGIN.Z + 30), Vector3.new(ORIGIN.X + 8, floorTop + 3.5, ORIGIN.Z)),
	}
end

---------------------------------------------------------------- playing

local function trackFor(entry, assetId)
	local track = entry.tracks[assetId]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = assetId
		track = entry.animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		entry.tracks[assetId] = track
	end
	return track
end

local function stopAll(entry)
	entry.token += 1
	entry.playing = nil
	for _, track in pairs(entry.tracks) do
		if track.IsPlaying then track:Stop(0.2) end
	end
end

local function play(entry, key)
	if not entry.animator then return false, "this model has no Humanoid or AnimationController to animate" end
	stopAll(entry)
	local token = entry.token
	local castName = key:match("^Cast/(.+)$")
	if castName then
		local handler = MobMovesetBehaviour.Casts[castName]
		local castEntry
		for _, e in ipairs(movesetEntries(MobData.FindMobById(entry.id))) do
			if e.Cast == castName then castEntry = e end
		end
		if not (handler and handler.Showcase and castEntry) then return false, "unknown cast" end
		task.spawn(function()
			while entry.token == token and entry.model.Parent do
				local period = handler.Showcase(entry.model, entry.id, castEntry, function(assetId)
					return trackFor(entry, assetId)
				end)
				task.wait(period)
			end
		end)
	else
		local assetId, speed = resolveClip(entry.id, key)
		if not isAnimId(assetId) then return false, "unknown animation " .. tostring(key) end
		local track = trackFor(entry, assetId)
		task.spawn(function()
			while entry.token == token and entry.model.Parent do
				track:Play(0.15)
				track:AdjustSpeed(speed)
				if track.Length <= 0 then task.wait(0.5) end -- still loading
				track.Stopped:Wait()
				if entry.token ~= token then return end
				task.wait(REPLAY_PAUSE)
			end
		end)
	end
	entry.playing = key
	return true
end

local function ensureBuilt()
	while building do task.wait(0.1) end
	if not showcase then
		building = true
		local ok, result = pcall(build)
		building = false
		if not ok then
			warn("[AnimationShowcase] build failed: " .. tostring(result))
			return nil
		end
		showcase = result
		for _, id in ipairs(showcase.order) do
			local entry = showcase.entries[id]
			local cfg = MobAnimConfig[id]
			if type(cfg) == "table" and isAnimId(cfg.Idle) then play(entry, "Idle") end
		end
	end
	return showcase
end

---------------------------------------------------------------- remote

local function teleport(player, cframe)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	pcall(player.RequestStreamAroundAsync, player, cframe.Position, 5)
	character:PivotTo(cframe)
	return true
end

Remote.OnServerInvoke = function(player, action, mobId, key)
	if not DevRoster.IsDev(player) then return { ok = false, error = "not a dev" } end
	local sc = ensureBuilt()
	if not sc then return { ok = false, error = "the showcase failed to build (see server output)" } end
	local entry = type(mobId) == "string" and sc.entries[mobId] or nil

	if action == "catalog" then
		local mobs = {}
		for _, id in ipairs(sc.order) do
			local e = sc.entries[id]
			table.insert(mobs, { id = e.id, name = e.name, tier = e.tier, pedestal = e.pedestal, anims = e.anims, playing = e.playing })
		end
		return { ok = true, mobs = mobs, origin = sc.center, span = sc.span }
	elseif action == "goto" then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - sc.center).Magnitude > sc.span + 200 then
			returnTo[player] = root.CFrame
		end
		return { ok = teleport(player, entry and entry.stand or sc.entrance), error = "no character" }
	elseif action == "return" then
		local back = returnTo[player]
		if not back then return { ok = false, error = "nowhere to return to" } end
		returnTo[player] = nil
		return { ok = teleport(player, back), error = "no character" }
	elseif action == "play" then
		if not entry or type(key) ~= "string" then return { ok = false, error = "unknown mob" } end
		local ok, err = play(entry, key)
		return { ok = ok, error = err }
	elseif action == "stop" then
		if not entry then return { ok = false, error = "unknown mob" } end
		stopAll(entry)
		return { ok = true }
	end
	return { ok = false, error = "unknown action" }
end

Players.PlayerRemoving:Connect(function(player)
	returnTo[player] = nil
end)
