------ [ Setup ] ------
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local maxStudsOffset = 100
local maxSpeed = 30

------ [ Animation ] ------
for _, waterTexture in ipairs(CollectionService:GetTagged("AnimatedWater")) do
	local transitionTime = math.clamp(maxSpeed - waterTexture.WaterSpeed.Value, 0.9, maxSpeed)

	local goal = {}
	if waterTexture.MoveDirectionX.Value then
		goal.OffsetStudsU = maxStudsOffset
	end

	if waterTexture.MoveDirectionZ.Value then
		goal.OffsetStudsV = maxStudsOffset
	end

	local info = TweenInfo.new(transitionTime, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	local tween = TweenService:Create(waterTexture, info, goal)
	tween:Play()
end