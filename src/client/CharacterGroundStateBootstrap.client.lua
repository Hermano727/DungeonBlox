local Players = game:GetService("Players")
local GroundState = require(script.Parent:WaitForChild("CharacterGroundState"))
local player = Players.LocalPlayer

player.CharacterAdded:Connect(GroundState.Start)
player.CharacterRemoving:Connect(function(character)
    if player.Character == character or player.Character == nil then GroundState.Stop() end
end)
if player.Character then GroundState.Start(player.Character) end
