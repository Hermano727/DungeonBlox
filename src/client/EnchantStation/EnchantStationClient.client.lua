--!strict
--[[
	EnchantStationClient
	World-interaction entry point for the Enchanting Station: reacts to the
	"EnchantPrompt" ProximityPrompt EnchantStationService.server.lua attaches
	to the altar model, pans the (first-person) camera to an overhead view of
	it, frees the cursor, and mounts EnchantStationScreen. Everything the
	screen needs (odds, stat preview, the actual apply) is either computed
	client-side from EnchantScrollApply or goes through the existing,
	already-working ApplyEnchantScroll DungeonInventoryAct kind -- this
	script + EnchantStationScreen only build the missing front door.

	NOT the T1Altar/AltarService rarity-ascension system -- see that file's
	own header comment for why the two are easy to conflate.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local CursorUtils = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local CameraOverrideState = require(ReplicatedStorage:WaitForChild("CameraOverrideState"))
local InteractionLock = require(ReplicatedStorage:WaitForChild("InteractionLock"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))

-- Unique per interaction type; see InteractionLock's header.
local LOCK_OWNER = "EnchantStation"

local EnchantStationScreen = require(script.Parent:WaitForChild("EnchantStationScreen"))

local PROMPT_NAME = "EnchantPrompt"

-- Tuned for the current altar mesh's scale/placement -- adjust live in Studio if the
-- framing looks off; per CLAUDE.md this can't be playtested from here to dial in exactly.
local CAMERA_HEIGHT = 10
local CAMERA_BACK = 4
local CAMERA_LOOK_AHEAD = 1
-- EnchantStationScreen puts the inventory grid on the LEFT half and the altar UI on the
-- RIGHT half, so the altar itself needs to render in the right half of the viewport, not
-- dead center. Rather than move the camera sideways (which changes the framing/perspective
-- on the altar), this keeps the camera aimed dead-on at the altar via CFrame.lookAt and then
-- yaws the view a bit -- turning the camera LEFT makes a subject that's still dead ahead
-- render further toward the RIGHT edge of frame (same effect as turning your own head left
-- while looking at something fixed in front of you). Positive degrees = altar shifts right.
-- If it shifts the wrong way once you see it in Studio, just negate this constant.
local CAMERA_YAW_OFFSET_DEGREES = 16
local CAMERA_TWEEN_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "EnchantStationGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 130
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

local root = ReactRoblox.createRoot(gui)

local isOpen = false
local closeGeneration = 0

local function computeStationCameraCFrame(hostPart: BasePart): CFrame
	local altarCFrame = hostPart.CFrame
	local up = altarCFrame.UpVector
	local look = altarCFrame.LookVector
	local basePos = altarCFrame.Position
	local camPos = basePos + up * CAMERA_HEIGHT - look * CAMERA_BACK
	local target = basePos + look * CAMERA_LOOK_AHEAD
	local aimCFrame = CFrame.lookAt(camPos, target, up)
	return aimCFrame * CFrame.Angles(0, math.rad(CAMERA_YAW_OFFSET_DEGREES), 0)
end

local closeStation

local function renderWithClose()
	root:render(React.createElement(EnchantStationScreen, {
		onClose = function()
			closeStation()
		end,
		resetKey = closeGeneration,
	}))
end

closeStation = function()
	if not isOpen then
		return
	end
	isOpen = false
	closeGeneration += 1
	renderWithClose()
	gui.Enabled = false
	CameraOverrideState.SetActive(false)
	CursorUtils.release()
	InteractionLock.Release(LOCK_OWNER)
	SfxService.PlayEffect("EnchantStationExit")
end

local function openStation(hostPart: BasePart)
	if isOpen then
		return
	end
	isOpen = true

	SfxService.PlayEffect("EnchantStationEnter")
	InteractionLock.Acquire(LOCK_OWNER)
	CursorUtils.acquire()
	CameraOverrideState.SetActive(true)

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		TweenService:Create(camera, CAMERA_TWEEN_INFO, { CFrame = computeStationCameraCFrame(hostPart) }):Play()
	end

	renderWithClose()
	gui.Enabled = true
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then
		return
	end
	if prompt.Name ~= PROMPT_NAME then
		return
	end
	local host = prompt.Parent
	if not host or not host:IsA("BasePart") then
		return
	end
	openStation(host)
end)

UserInputService.InputBegan:Connect(function(input, _gameProcessed)
	if not isOpen then
		return
	end
	if input.KeyCode == Keys.CloseMenu then
		closeStation()
	end
end)

player.CharacterAdded:Connect(function()
	closeStation()
end)

print("[EnchantStationClient] ready")
