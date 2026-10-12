--[[
	DungeonClearSequence (client) -- the in-world show when a dungeon is cleared.
	Server: SSS/DungeonClearSequence. Timing: RS/DungeonClearConfig. Doc: docs/dungeon-clear-sequence.md.

	The server sends ONE payload: the whole show laid out as offsets from `startsAt` (server
	clock). Every frame this script computes t = GetServerTimeNow() - startsAt and hands it to each
	stage, which draws itself purely from t. Nothing is tweened, so every party member sees the same
	moment, and a client that gets the payload late jumps straight into the right frame.

	Stages (one module each, `Stage.new(show)`, `:Update(t)`, `:Destroy()`):
		Ambience     dims the arena's own lights for the show (blackout for the boss's echo)
		BossEcho     the main boss's echo, right after its death animation: rises, torn apart by light
		Benediction  the light and the wings; fades out on its own before the loot starts
		Pyres        a brazier per member; score embers, scrap burn-off, gutter
		ReliquaryRing  the relics: lift out of the fires, gather into the ring, unveil, streak home
		Judgement    the Mythic Judgements, minibosses first, the main boss last

	Players keep full control the whole time: no camera takeover, no HUD hiding.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")

local STAGES = {
	require(script:WaitForChild("Ambience")),
	require(script:WaitForChild("BossEcho")),
	require(script:WaitForChild("Benediction")),
	require(script:WaitForChild("Pyres")),
	require(script:WaitForChild("ReliquaryRing")),
	require(script:WaitForChild("Judgement")),
}
local Fx = require(script:WaitForChild("Fx"))

local OUTRO = 2.2 -- after the timeline ends: braziers sink, everything fades, then cleanup

local current -- the running show, if any

local function stopShow()
	if not current then return end
	local show = current
	current = nil
	if show.conn then show.conn:Disconnect() end
	for _, stage in ipairs(show.stages) do
		pcall(stage.Destroy, stage)
	end
	for _, gui in ipairs(show.guis) do
		gui:Destroy()
	end
	show.folder:Destroy()
end

local function newShow(payload)
	local folder = Instance.new("Folder")
	folder.Name = "DungeonClearFx"
	folder.Parent = Workspace

	local show = {
		payload = payload,
		startsAt = payload.startsAt,
		duration = payload.duration,
		outro = OUTRO,
		origin = payload.origin,
		floorY = payload.floorY or 0,
		members = payload.members or {},
		folder = folder,
		guis = {},       -- BillboardGuis (in PlayerGui), destroyed with the show
		braziers = {},   -- filled by Pyres: [memberIndex] = brazier API
		once = Fx.Once(),
		stages = {},
	}

	-- Arena-local (relative to the floor's centre) -> world.
	function show:world(x, y, z)
		return self.origin:PointToWorldSpace(Vector3.new(x, self.floorY + y, z))
	end
	-- Arena-local polar (0 deg = the entrance side, clockwise from above), as MiasmaArenaLayout.
	function show:polar(angleDeg, radius, y)
		local a = math.rad(angleDeg)
		return self:world(math.sin(a) * radius, y, -math.cos(a) * radius)
	end
	function show:centre(y)
		return self:world(0, y or 0, 0)
	end
	-- A member's character root, or nil (left, dead, streamed out).
	function show:memberRoot(index)
		local m = self.members[index]
		local plr = m and Players:GetPlayerByUserId(m.userId)
		local char = plr and plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and (root.Position - self:centre()).Magnitude < 400 then return root end
		return nil
	end
	function show:plaque(adornee, props)
		local gui, lines = Fx.plaque(adornee, props)
		table.insert(self.guis, gui)
		return gui, lines
	end

	for _, Stage in ipairs(STAGES) do
		local ok, stage = pcall(Stage.new, show)
		if ok and stage then
			table.insert(show.stages, stage)
		else
			warn("[DungeonClearSequence] stage failed to build: " .. tostring(stage))
		end
	end
	return show
end

local function startShow(payload)
	if type(payload) ~= "table" or type(payload.startsAt) ~= "number" or typeof(payload.origin) ~= "CFrame" then return end
	if Workspace:GetServerTimeNow() - payload.startsAt > payload.duration + OUTRO then return end -- long over
	stopShow()
	local show = newShow(payload)
	current = show
	local failures = {}
	show.conn = RunService.RenderStepped:Connect(function()
		local t = Workspace:GetServerTimeNow() - show.startsAt
		if t > show.duration + OUTRO then
			stopShow()
			return
		end
		for _, stage in ipairs(show.stages) do
			local ok, err = pcall(stage.Update, stage, t)
			if not ok and not failures[stage] then
				failures[stage] = true -- one warning per stage, the rest keeps playing
				warn("[DungeonClearSequence] stage update failed: " .. tostring(err))
			end
		end
	end)
end

local function bind(remote)
	remote.OnClientEvent:Connect(startShow)
end
-- The server creates the remote at boot; bind whenever it appears, however late.
local existing = GameEvents:FindFirstChild("DungeonClearSequence")
if existing then
	bind(existing)
else
	local conn
	conn = GameEvents.ChildAdded:Connect(function(child)
		if child.Name == "DungeonClearSequence" and child:IsA("RemoteEvent") then
			conn:Disconnect()
			bind(child)
		end
	end)
end

-- Leaving the dungeon (Leave Now, the instance ending) ends the show for you at once.
player:GetAttributeChangedSignal("InDungeon"):Connect(function()
	if not player:GetAttribute("InDungeon") then stopShow() end
end)
