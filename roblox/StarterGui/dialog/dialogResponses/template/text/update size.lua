local textLabel = script.Parent -- Make sure this script is inside the UI container
local screenGui = script:FindFirstAncestorWhichIsA("ScreenGui") -- Reference to the ScreenGui
local referenceResolution = Vector2.new(1920, 1080) -- Reference screen size
local referenceTextSize = 30 -- Desired TextSize at the reference resolution

local function updateTextSize()
	local currentSize = screenGui.AbsoluteSize -- Get the current screen size
	local scaleFactor = math.min(currentSize.X / referenceResolution.X, currentSize.Y / referenceResolution.Y) -- Uniform scaling factor
	local newTextSize = math.max(9, referenceTextSize * scaleFactor) -- Ensure TextSize doesn't go below 9
	textLabel.TextSize = newTextSize
end


-- Update whenever the screen size changes
screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateTextSize)

-- Run once at the start
updateTextSize()