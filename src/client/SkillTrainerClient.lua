--[[
	SkillTrainerClient
	The Skill Trainer's wares. The window is NpcShop (a Journal-style book), the spread is
	NpcShop/TrainerBook. Opened from the Skill Trainer's dialog (DialogSystem/Trees/
	SkillTrainer, an OpenMenu action naming this module) with .open(npcId).
]]

local NpcShop = require(script.Parent:WaitForChild("NpcShop"))
local TrainerBook = require(script.Parent.NpcShop:WaitForChild("TrainerBook"))

return NpcShop.window("SkillTrainer", TrainerBook)
