local InteractiveGrass = require(game.ReplicatedStorage.Modules.Enviroment.InteractiveGrass)

local grass = InteractiveGrass.new({
	grassFolder = workspace:WaitForChild("Grass"),
})

grass:Start()
