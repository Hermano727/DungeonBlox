-- Directional Movement - R15 Version (Shift-Lock Fixed)
-- LocalScript in StarterCharacterScripts

local RunService = game:GetService('RunService')
local Player = game.Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild('Humanoid')
local HumanoidRootPart = Character:WaitForChild('HumanoidRootPart')

local PlayersTable = {}

-- ============================================
-- CUSTOMIZABLE SETTINGS
-- ============================================
local TurnAmount = 60
local LeanAmount = 5
local HipTurnAmount = 60
local LerpSpeed = 0.008

-- Crouch settings
local CrouchTurnReduction = 0.5
local CrouchLeanReduction = 0.1
local CrouchHipReduction = 1
local DisableHeadCorrectionInCrouch = true

local TurnAmountRad = math.rad(TurnAmount)
local LeanAmountRad = math.rad(LeanAmount)
local HipTurnAmountRad = math.rad(HipTurnAmount)

local LOWER_TURN_RATIO = 0.35
local UPPER_TURN_RATIO = 0.65

local characterData = {}

local function getCharacterData(char)
	if characterData[char] then return characterData[char] end

	local lt = char:FindFirstChild('LowerTorso')
	local ut = char:FindFirstChild('UpperTorso')
	local hd = char:FindFirstChild('Head')
	local rul = char:FindFirstChild('RightUpperLeg')
	local lul = char:FindFirstChild('LeftUpperLeg')

	if not (lt and ut and hd and rul and lul) then return nil end

	local root = lt:FindFirstChild('Root')
	local waist = ut:FindFirstChild('Waist')
	local neck = hd:FindFirstChild('Neck')
	local rh = rul:FindFirstChild('RightHip')
	local lh = lul:FindFirstChild('LeftHip')

	if not (root and waist and neck and rh and lh) then return nil end

	local data = {
		rootC0 = root.C0,
		waistC0 = waist.C0,
		neckC0 = neck.C0,
		rightHipC0 = rh.C0,
		leftHipC0 = lh.C0,
	}
	characterData[char] = data
	return data
end

local function IsCrouching(char)
	local rootPart = char:FindFirstChild("HumanoidRootPart")
	if rootPart then
		return rootPart:GetAttribute("IsCrouching") == true
	end
	return false
end

function Calculate(dt, hrp, humanoid, char)
	local lt = char:FindFirstChild('LowerTorso')
	local ut = char:FindFirstChild('UpperTorso')
	local hd = char:FindFirstChild('Head')
	local rul = char:FindFirstChild('RightUpperLeg')
	local lul = char:FindFirstChild('LeftUpperLeg')

	if not (lt and ut and hd and rul and lul) then return end

	local rootMotor = lt:FindFirstChild('Root')
	local waist = ut:FindFirstChild('Waist')
	local neck = hd:FindFirstChild('Neck')
	local rightHipJ = rul:FindFirstChild('RightHip')
	local leftHipJ = lul:FindFirstChild('LeftHip')

	if not (rootMotor and waist and neck and rightHipJ and leftHipJ) then return end

	local data = getCharacterData(char)
	if not data then return end

	local isCrouching = IsCrouching(char)

	local velocity = hrp.AssemblyLinearVelocity
	local speed = velocity.Magnitude

	-- Reset to neutral when not moving
	if speed < 0.5 then
		local LerpTime = 1 - LerpSpeed ^ dt
		rootMotor.C0 = rootMotor.C0:Lerp(data.rootC0, LerpTime)
		waist.C0 = waist.C0:Lerp(data.waistC0, LerpTime)
		neck.C0 = neck.C0:Lerp(data.neckC0, LerpTime)
		rightHipJ.C0 = rightHipJ.C0:Lerp(data.rightHipC0, LerpTime)
		leftHipJ.C0 = leftHipJ.C0:Lerp(data.leftHipC0, LerpTime)
		return
	end

	-- Get movement direction in WORLD space first
	local worldVelocity = velocity

	-- Use HumanoidRootPart's look vector (where character is ACTUALLY facing)
	-- Not camera look vector - this fixes shift-lock issues
	local lookVector = hrp.CFrame.LookVector
	local rightVector = hrp.CFrame.RightVector

	-- Project velocity onto character's local axes
	local forwardSpeed = worldVelocity:Dot(lookVector)
	local strafeSpeed = worldVelocity:Dot(rightVector)

	-- Normalize by walk speed and clamp
	local strafeX = math.clamp(strafeSpeed / math.max(humanoid.WalkSpeed, 1), -1, 1)
	local forwardZ = math.clamp(-forwardSpeed / math.max(humanoid.WalkSpeed, 1), -1, 1)  -- Negative because forward is -Z

	-- Calculate the dominant movement direction
	local movementMagnitude = math.sqrt(strafeX * strafeX + forwardZ * forwardZ)

	-- Prevent division by zero
	if movementMagnitude < 0.01 then
		strafeX = 0
		forwardZ = 0
	else
		-- Normalize the movement vector
		strafeX = strafeX / movementMagnitude
		forwardZ = forwardZ / movementMagnitude
	end

	-- Scale back by magnitude for smooth transitions
	strafeX = strafeX * math.min(movementMagnitude, 1)
	forwardZ = forwardZ * math.min(movementMagnitude, 1)

	-- Reduce effect when moving diagonally (more balanced distribution)
	local diagonalFactor = 1 - (math.abs(strafeX) * math.abs(forwardZ) * 0.3)

	-- Apply forward factor with diagonal compensation
	local forwardFactor = (1 - math.abs(forwardZ) * 0.5) * diagonalFactor

	-- Calculate turn and lean angles
	local turnAngle = strafeX * TurnAmountRad * forwardFactor
	local leanAngle = strafeX * LeanAmountRad * forwardFactor

	-- Apply crouch reduction
	if isCrouching then
		turnAngle = turnAngle * CrouchTurnReduction
		leanAngle = leanAngle * CrouchLeanReduction
	end

	-- Determine if moving backwards RELATIVE TO CHARACTER FACING
	-- forwardZ > 0 means moving away from look direction (backwards)
	local movingBackward = forwardZ > 0.1

	if movingBackward then
		turnAngle = -turnAngle
		leanAngle = -leanAngle
	end

	-- Split rotation between lower and upper body
	local lowerTurn = turnAngle * LOWER_TURN_RATIO
	local upperTurn = turnAngle * UPPER_TURN_RATIO
	local lowerLean = leanAngle * LOWER_TURN_RATIO
	local upperLean = leanAngle * UPPER_TURN_RATIO

	-- Hip rotation for legs
	local hipTurn = strafeX * HipTurnAmountRad * forwardFactor

	if isCrouching then
		hipTurn = hipTurn * CrouchHipReduction
	end

	if movingBackward then
		hipTurn = -hipTurn
	end

	-- Calculate total rotation for neck counter-rotation
	local totalTurn = lowerTurn + upperTurn
	local totalLean = lowerLean + upperLean

	-- Build target CFrames
	local RootResult = data.rootC0 * CFrame.Angles(0, -lowerTurn, -lowerLean)
	local WaistResult = data.waistC0 * CFrame.Angles(0, -upperTurn, -upperLean)

	-- Neck correction
	local NeckResult
	if isCrouching and DisableHeadCorrectionInCrouch then
		NeckResult = data.neckC0
	else
		NeckResult = data.neckC0 * CFrame.Angles(0, totalTurn, totalLean)
	end

	local RightHipResult = data.rightHipC0 * CFrame.Angles(0, -hipTurn, 0)
	local LeftHipResult = data.leftHipC0 * CFrame.Angles(0, -hipTurn, 0)

	-- Apply smoothing
	local LerpTime = 1 - LerpSpeed ^ dt

	rootMotor.C0 = rootMotor.C0:Lerp(RootResult, LerpTime)
	waist.C0 = waist.C0:Lerp(WaistResult, LerpTime)
	neck.C0 = neck.C0:Lerp(NeckResult, LerpTime)
	rightHipJ.C0 = rightHipJ.C0:Lerp(RightHipResult, LerpTime)
	leftHipJ.C0 = leftHipJ.C0:Lerp(LeftHipResult, LerpTime)
end

RunService.RenderStepped:Connect(function(dt)
	for _, plr in game.Players:GetPlayers() do
		if plr.Character == nil then continue end
		if table.find(PlayersTable, plr) then continue end
		table.insert(PlayersTable, plr)
	end

	for i = #PlayersTable, 1, -1 do
		local plr = PlayersTable[i]
		if plr == nil or game.Players:FindFirstChild(plr.Name) == nil or plr.Character == nil then
			if plr and plr.Character then
				characterData[plr.Character] = nil
			end
			table.remove(PlayersTable, i)
			continue
		end

		local hrp = plr.Character:FindFirstChild('HumanoidRootPart')
		local humanoid = plr.Character:FindFirstChild('Humanoid')

		if hrp == nil or humanoid == nil then continue end

		Calculate(dt, hrp, humanoid, plr.Character)
	end
end)