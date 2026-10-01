--!strict
--  FIRST PASS (2026-10-01): built from the art we already had (Journal book, carved
--  medallions, bar troughs). Due a second pass: its own skill art, a richer milestone track.
--
--  SkillsPage -- the Journal's Skills page.
--    left   Combat / Mining / Fishing: icon in a carved ring, level, XP bar, XP to the next level
--    right  Milestones: the combat tiers (T1-T5 at combat level 1/21/41/61/81: where the Loot
--           Score tiers open), total level, and how each skill is trained
--
--  Data: RS/SkillXPShared (the client display cache the server's XP totals keep in step, see
--  CLAUDE.md "Skill XP is server-authoritative"); re-renders on SkillXPShared.Subscribe.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local HudIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))
local Journal = script.Parent:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))
local Book = require(Journal:WaitForChild("Book"))

local e = React.createElement
local text, list = Parts.Text, Parts.List

local SKILLS = {
	{ key = "Combat",  label = "Combat",  icon = HudIcons.COMBAT,                fill = Color3.fromRGB(96, 116, 72),
		how = "Defeat monsters out in the world and in dungeons." },
	{ key = "Mining",  label = "Mining",  icon = ItemConfig.TOOL_ICONS.Pickaxe,    fill = Color3.fromRGB(128, 128, 136),
		how = "Mine ore with your pickaxe." },
	{ key = "Fishing", label = "Fishing", icon = ItemConfig.TOOL_ICONS.FishingRod, fill = Color3.fromRGB(78, 120, 150),
		how = "Spear fish in open water." },
}
local TIER_LEVELS = { 1, 21, 41, 61, 81 }

local function useSkills()
	local _, setVersion = React.useState(0)
	React.useEffect(function()
		return SkillXPShared.Subscribe(function()
			setVersion(function(v) return v + 1 end)
		end)
	end, {})
end

local function SkillBlock(props: { skill: any, order: number })
	local s = props.skill
	local state = SkillXPShared[s.key] or { Level = 1, XP = 0 }
	local level = math.max(1, math.floor(tonumber(state.Level) or 1))
	local xp = math.max(0, math.floor(tonumber(state.XP) or 0))
	local need = math.max(1, SkillXPShared.GetXPForLevel(level))
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, 116), BackgroundTransparency = 1 }, {
		Icon = e(Parts.Medallion, {
			image = s.icon, size = 78, imageScale = 0.56, lit = true,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		}),
		Name = text({
			text = s.label, font = Style.Font.Heading, size = 22, color = Style.Text.Heading,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(94, 12), Size = UDim2.new(1, -200, 0, 28),
		}),
		Level = text({
			text = "Level " .. level, font = Style.Font.Number, size = 22, color = Style.Text.Value,
			align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 12),
			Size = UDim2.fromOffset(140, 28),
		}),
		Bar = e(Parts.BarTrough, {
			fill = xp / need, color = s.fill,
			Position = UDim2.fromOffset(94, 48), Size = UDim2.new(1, -94, 0, 16),
		}),
		Xp = text({
			text = ("%d / %d XP"):format(xp, need), size = 14, color = Style.Text.Muted,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(94, 70), Size = UDim2.new(0.5, -47, 0, 18),
		}),
		Next = text({
			text = ("%d XP to level %d"):format(math.max(0, need - xp), level + 1), size = 14, color = Style.Text.Muted,
			align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 70),
			Size = UDim2.new(0.5, -47, 0, 18),
		}),
	})
end

local function TierRow(props: { tier: number, need: number, combat: number, order: number })
	local reached = props.combat >= props.need
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1 }, {
		Ring = e(Parts.Medallion, {
			size = 38, lit = reached, dim = not reached,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		}),
		Tier = text({
			text = "T" .. props.tier, font = Style.Font.Heading, size = 15,
			color = reached and Style.Chrome.Selected or Style.Chrome.Dim,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 19, 0.5, 0), Size = UDim2.fromOffset(38, 20), ZIndex = 4,
		}),
		Label = text({
			text = ("Tier %d, combat level %d"):format(props.tier, props.need), font = Style.Font.BodyBold, size = 15,
			color = reached and Style.Text.Heading or Style.Text.Muted,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -170, 1, 0),
		}),
		State = text({
			text = reached and "Reached" or ("%d levels to go"):format(props.need - props.combat), size = 14,
			color = reached and Style.Text.Good or Style.Text.Muted,
			align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 120, 1, 0),
		}),
	})
end

local function SkillsPage(props: { side: any? })
	useSkills()

	local blocks: { [string]: any } = {
		Heading = e(Parts.Heading, { text = "Skills", size = 26, order = 0, height = 34 }),
	}
	local total = 0
	for i, s in ipairs(SKILLS) do
		blocks[s.key] = e(SkillBlock, { skill = s, order = i })
		total += math.max(1, math.floor(tonumber((SkillXPShared[s.key] or {}).Level) or 1))
	end

	local combat = math.max(1, math.floor(tonumber((SkillXPShared.Combat or {}).Level) or 1))
	local right: { [string]: any } = {
		Heading = e(Parts.Heading, { text = "Milestones", size = 26, order = 0, height = 34 }),
		Total = text({ text = ("Total level %d"):format(total), font = Style.Font.Number, size = 16, color = Style.Text.Body, height = 20, order = 1 }),
	}
	for i, need in ipairs(TIER_LEVELS) do
		right["T" .. i] = e(TierRow, { tier = i, need = need, combat = combat, order = 1 + i })
	end
	right.Divider = e(Parts.Divider, { order = 10 })
	for i, s in ipairs(SKILLS) do
		right["How" .. s.key] = e("Frame", { LayoutOrder = 10 + i, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, {
			Icon = e("ImageLabel", {
				AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), Size = UDim2.fromOffset(22, 22),
				BackgroundTransparency = 1, Image = s.icon, ScaleType = Enum.ScaleType.Fit,
			}),
			Line = text({
				text = s.label .. ": " .. s.how, size = 14, color = Style.Text.Body,
				align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -34, 1, 0),
			}),
		})
	end

	return e(Book, { side = props.side, left = list(8, blocks), right = list(4, right) })
end

return SkillsPage
