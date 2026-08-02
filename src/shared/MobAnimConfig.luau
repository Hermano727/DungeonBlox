-- MobAnimConfig
-- Per-mob animation table. MobAnimController reads this on spawn.
--
-- Walk:   string  = single animation ID
--         table   = list of IDs; one is picked randomly each time walking starts
-- Attack: string  = plays on PerformAttack
-- Idle:   string  = loops when the mob is standing still
--
-- Omit any key the mob doesn't need — it falls back gracefully.

local RS = game:GetService("ReplicatedStorage")
local WalkRegistry = require(RS:WaitForChild("MobAnimWalkRegistry"))

return {
	SmallSkeleton = {
		Walk = "rbxassetid://102225428779386",
		Attack = "rbxassetid://102078367847818",
		Idle   = "rbxassetid://180435571",
	},

	-- Template for adding future mobs:
	-- MyNewMob = {
	-- 	Walk   = WalkRegistry.Walk1,
	-- 	Attack = "rbxassetid://...",
	-- 	Idle   = "rbxassetid://...",
	-- },
}