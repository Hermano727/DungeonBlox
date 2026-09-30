--[[
	Nametags -- a tag above every OTHER player's head (client only):

	          Lv 12  PARTY        combat level (muted), plus PARTY for your party members
	          PlayerName          display name, coloured by alignment

	  Alignment colour: Lawful bone white, Neutral gold, Chaotic red (PlayerAlignment attribute,
	  set by ProfileService on every push). Level: the CombatLevel attribute (same place).
	  Party: the local-only PartyMemberIds attribute PartyClient keeps current.

	Replaces PartyClient's old separate "[NEUTRAL]/[CHAOTIC]" and "[PARTY] name" tags. Hidden
	for dead players and boss-fight spectators, not drawn through walls, fades out with distance.

	Streaming: other players' characters load on THIS client whenever they stream in, not when
	they spawn -- someone already in the server when you joined has no head yet, and never fires
	CharacterAdded for you. Streaming can also swap their parts for new ones. So a light watcher
	(every WATCH_INTERVAL) re-points each tag at its player's CURRENT head; CharacterAdded only
	speeds things up.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local player = Players.LocalPlayer

local ALIGNMENT_COLOR = {
	Lawful = Color3.fromRGB(238, 232, 220),
	Neutral = Color3.fromRGB(255, 212, 84),
	Chaotic = Color3.fromRGB(255, 82, 76),
}
local LEVEL_COLOR = Color3.fromRGB(190, 180, 166)
local PARTY_COLOR = Color3.fromRGB(120, 214, 255)
local MAX_DISTANCE = 90 -- studs
local WATCH_INTERVAL = .5

local tags = {} -- [Player] = { gui, level, name, conns, healthConn }

-- The tags live directly in PlayerGui (a head is destroyed on every respawn, and anything
-- parented to it with it) and only point at the current head through Adornee. Each is its own
-- ResetOnSpawn=false BillboardGui: they used to sit in a Folder, and PlayerGui is emptied on
-- YOUR respawn except for GUIs that opt out, so every tag vanished the first time you died.
local playerGui = player:WaitForChild("PlayerGui")

local function partySet()
	local set = {}
	for id in string.gmatch(tostring(player:GetAttribute("PartyMemberIds") or ""), "%d+") do
		set[tonumber(id)] = true
	end
	return set
end

local function refresh(target)
	local tag = tags[target]
	if not tag then return end
	local character = target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0 and target:GetAttribute("DungeonSpectating") == nil
	tag.gui.Enabled = alive
	if not alive then return end

	tag.name.Text = target.DisplayName ~= "" and target.DisplayName or target.Name
	tag.name.TextColor3 = ALIGNMENT_COLOR[target:GetAttribute("PlayerAlignment")] or ALIGNMENT_COLOR.Lawful
	local level = tonumber(target:GetAttribute("CombatLevel"))
	local levelText = level and ("Lv " .. math.floor(level)) or ""
	if partySet()[target.UserId] then
		levelText = levelText .. ('  <font color="#%s">PARTY</font>'):format(PARTY_COLOR:ToHex())
	end
	tag.level.Text = levelText
end

local function attach(target)
	local tag = tags[target]
	if not tag then return end
	local character = target.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not head then
		tag.gui.Adornee = nil
		tag.head = nil
		return
	end
	tag.gui.Adornee = head
	tag.head = head
	-- The engine's own name / health display would double up with ours.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if tag.healthConn then tag.healthConn:Disconnect(); tag.healthConn = nil end
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		tag.healthConn = humanoid.HealthChanged:Connect(function() refresh(target) end)
	end
	refresh(target)
end

local function build(target)
	if target == player or tags[target] then return end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nametag"
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = MAX_DISTANCE
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local level = Instance.new("TextLabel")
	level.Name = "Level"
	level.BackgroundTransparency = 1
	level.Size = UDim2.new(1, 0, 0, 14)
	level.FontFace = UIFonts.BodyBold
	level.TextSize = 12
	level.TextColor3 = LEVEL_COLOR
	level.TextStrokeColor3 = Color3.fromRGB(8, 6, 6)
	level.TextStrokeTransparency = .5
	level.RichText = true
	level.Parent = gui

	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(0, 14)
	name.Size = UDim2.new(1, 0, 0, 22)
	name.FontFace = UIFonts.BodyBold
	name.TextSize = 17
	name.TextStrokeColor3 = Color3.fromRGB(8, 6, 6)
	name.TextStrokeTransparency = .4
	name.Parent = gui

	local tag = { gui = gui, level = level, name = name, conns = {} }
	tags[target] = tag
	table.insert(tag.conns, target.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 5)
		attach(target)
	end))
	table.insert(tag.conns, target.AttributeChanged:Connect(function(attribute)
		if attribute == "PlayerAlignment" or attribute == "CombatLevel" or attribute == "DungeonSpectating" then
			refresh(target)
		end
	end))
	table.insert(tag.conns, target:GetPropertyChangedSignal("DisplayName"):Connect(function() refresh(target) end))
	attach(target)
end

local function remove(target)
	local tag = tags[target]
	if not tag then return end
	tags[target] = nil
	for _, conn in ipairs(tag.conns) do conn:Disconnect() end
	if tag.healthConn then tag.healthConn:Disconnect() end
	tag.gui:Destroy()
end

for _, target in ipairs(Players:GetPlayers()) do build(target) end
Players.PlayerAdded:Connect(build)
Players.PlayerRemoving:Connect(remove)

-- The watcher: re-attach any tag whose player's head is new, streamed in late, or gone.
task.spawn(function()
	while true do
		task.wait(WATCH_INTERVAL)
		local rebuild = {}
		for target, tag in pairs(tags) do
			-- Belt and braces: a tag knocked out of PlayerGui goes back (rebuilt if destroyed).
			if tag.gui.Parent ~= playerGui and not pcall(function() tag.gui.Parent = playerGui end) then
				table.insert(rebuild, target)
				continue
			end
			local character = target.Character
			local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
			if head ~= tag.head or (head and not head:IsDescendantOf(workspace)) then
				attach(target)
			end
		end
		for _, target in ipairs(rebuild) do
			remove(target)
			if target.Parent then build(target) end
		end
	end
end)

-- Party changes re-mark everyone.
player:GetAttributeChangedSignal("PartyMemberIds"):Connect(function()
	for target in pairs(tags) do refresh(target) end
end)
