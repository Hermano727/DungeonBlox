--[[
	BuffDisplay
	How each BuffService buff type shows in the buff list (BuffHudClient, left middle of the
	screen): its name, icon and colour. A new buff type needs one entry here; an unknown type
	still shows, under its raw type name.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))

export type Entry = { name: string, icon: string, color: Color3, unit: string }

local BuffDisplay: { [string]: Entry } = {
	WalkSpeedPct = { name = "Swiftness", icon = HudIcons.BUFF_SWIFTNESS, color = Color3.fromRGB(120, 196, 232), unit = "% speed" },
	LuckPct = { name = "Fortune", icon = HudIcons.BUFF_FORTUNE, color = Color3.fromRGB(132, 206, 104), unit = "% luck" },
}

return BuffDisplay
