--[[
	DevMenu/Placement -- world-side tools shared by the tabs that place things: the placement ghost,
	the aim point, and fly.

	ghost            one Part that follows the aim while a tab is placing (each tab styles it in
	                 its SetupGhost: a red radius disc for mob camps, a blue one for NPCs, a ball
	                 for zone corners). Hide() parks it under the map.
	Aim()            the world point under the cursor (free cursor) or the crosshair (locked), ignoring
	                 the player, the ghost and anything a tab registers with IgnoreForAim.
	Fly              SetEnabled(v) / IsEnabled(): WASD, Space up, Ctrl/C down at FLY_SPEED. Driven by a
	                 LinearVelocity constraint so the velocity holds on every physics step: setting
	                 AssemblyLinearVelocity once per rendered frame let gravity win between 240 Hz
	                 physics steps and read as a slow constant sink. A respawn drops fly.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local FLY_SPEED = 90

local Placement = {}

local ghost = Instance.new("Part")
ghost.Name = "DevPlacerGhost"
ghost.Anchored = true
ghost.CanCollide = false
ghost.CanQuery = false
ghost.CanTouch = false
ghost.CastShadow = false
ghost.Material = Enum.Material.Neon
ghost.CFrame = CFrame.new(0, -500, 0)
ghost.Parent = Workspace
Placement.ghost = ghost

function Placement.Hide()
	ghost.CFrame = CFrame.new(0, -500, 0)
end

-- A flat disc (cylinder on its side) of `diameter` studs, the camp/NPC radius preview.
function Placement.StyleDisc(color, diameter)
	ghost.Shape = Enum.PartType.Cylinder
	ghost.Color = color
	ghost.Transparency = 0.55
	ghost.Size = Vector3.new(1, diameter, diameter)
end

-- The disc lies flat at `position`.
function Placement.PlaceDisc(position)
	ghost.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
end

local aimIgnore = {}
function Placement.IgnoreForAim(instance)
	table.insert(aimIgnore, instance)
end

function Placement.Aim()
	local camera = Workspace.CurrentCamera
	if not camera then
		return player:GetMouse().Hit.Position
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { ghost }
	for _, instance in ipairs(aimIgnore) do
		table.insert(filter, instance)
	end
	if player.Character then
		table.insert(filter, player.Character)
	end
	params.FilterDescendantsInstances = filter
	local origin, direction
	if UserInputService.MouseBehavior == Enum.MouseBehavior.Default and UserInputService.MouseIconEnabled then
		local mousePos = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
		origin, direction = ray.Origin, ray.Direction
	else
		origin, direction = camera.CFrame.Position, camera.CFrame.LookVector
	end
	local hit = Workspace:Raycast(origin, direction * 2000, params)
	return hit and hit.Position or (origin + direction * 50)
end

---------------------------------------------------------------- fly

local Fly = { enabled = false }
Placement.Fly = Fly

local function stopMover()
	if Fly.mover then Fly.mover:Destroy() Fly.mover = nil end
	if Fly.attachment then Fly.attachment:Destroy() Fly.attachment = nil end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.PlatformStand = false end
end

local function ensureMover(root)
	if Fly.mover and Fly.mover.Parent == root then return Fly.mover end
	stopMover()
	Fly.attachment = Instance.new("Attachment")
	Fly.attachment.Name = "DevFlyAttachment"
	Fly.attachment.Parent = root
	Fly.mover = Instance.new("LinearVelocity")
	Fly.mover.Name = "DevFlyVelocity"
	Fly.mover.Attachment0 = Fly.attachment
	Fly.mover.MaxForce = 1e9
	Fly.mover.VectorVelocity = Vector3.zero
	Fly.mover.Parent = root
	return Fly.mover
end

function Fly.IsEnabled()
	return Fly.enabled
end

-- Only the physics; DevMenu's setFly wraps this with the menu-side bookkeeping.
function Fly.SetEnabled(v)
	Fly.enabled = v == true
	if not Fly.enabled then stopMover() end
end

RunService.RenderStepped:Connect(function()
	if not Fly.enabled then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not humanoid or not root or not camera then return end
	humanoid.PlatformStand = true
	local move = Vector3.zero
	if not UserInputService:GetFocusedTextBox() then
		local look, right = camera.CFrame.LookVector, camera.CFrame.RightVector
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += look end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= look end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C) then
			move -= Vector3.yAxis
		end
	end
	if move.Magnitude > 0 then move = move.Unit end
	ensureMover(root).VectorVelocity = move * FLY_SPEED
	root.AssemblyAngularVelocity = Vector3.zero
end)

player.CharacterAdded:Connect(function()
	-- The old mover died with the old character.
	Fly.attachment, Fly.mover = nil, nil
end)

return Placement
