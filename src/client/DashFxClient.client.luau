--[[
	DashFxClient -- draws OTHER players' dashes (the dasher's own DashClient draws theirs at once).
	EnergyServer fires GameEvents/DashFx(character, direction, inAir, duration) to everyone within 250
	studs after a dash it allowed; RS/DashFx does the drawing. The pose itself needs nothing here: it
	plays on the dasher's Animator and replicates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DashFx = require(ReplicatedStorage:WaitForChild("DashFx"))
local remote = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("DashFx")

remote.OnClientEvent:Connect(function(character, direction, inAir, duration)
	if typeof(character) ~= "Instance" or not character:IsDescendantOf(workspace) then return end
	DashFx.Play(character, direction, { inAir = inAir, duration = duration })
end)
