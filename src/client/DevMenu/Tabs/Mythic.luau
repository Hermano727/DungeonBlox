--[[
	Mythic -- grants the real hand-authored mythic (MythicItemDefs, built by MythicItemBuilder) with
	its fixed substats, not a random roll wearing a Mythic label. Mythic is absent from
	ItemConfig.RARITY_ORDER on purpose (it never rolls from an ordinary kill), which is why it isn't
	a Gear rarity. New MythicItemDefs entries appear with no edit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MythicItemDefs = require(ReplicatedStorage:WaitForChild("MythicItemDefs"))
local Lists = require(script.Parent.Parent:WaitForChild("Lists"))
local MythicForce = require(script.Parent.Parent:WaitForChild("MythicForce"))

local Tab = { key = "Mythic", label = "Mythic", group = "Items" }

local KEYS = {}
for k in pairs(MythicItemDefs.Items) do table.insert(KEYS, k) end
table.sort(KEYS)
local idx = 1
local boxCount

function Tab.Build(ctx)
	local Ui, lbl, mkB, mkI = ctx.Ui, ctx.lbl, ctx.mkB, ctx.mkI
	local W = math.min(ctx.w, 640)
	local sec = Ui.section(ctx, "MythicSection", true)
	lbl(sec, "MYTHIC ITEM", 12, 2, 160, 16, 12, ctx.acc, true)
	local prev = mkB(sec, "<", 12, 20, 30, 28)
	local nxt = mkB(sec, ">", W - 30, 20, 30, 28)
	local disp = lbl(sec, "", 48, 20, W - 96, 28, 15, nil, false, Enum.TextXAlignment.Center)
	local name = lbl(sec, "", 12, 56, W - 24, 22, 15, MythicItemDefs.RARITY_COLOR, true, Enum.TextXAlignment.Center)
	local info = lbl(sec, "", 12, 82, W - 24, 80, 13, Color3.fromRGB(200, 195, 205))
	info.TextWrapped = true
	info.TextYAlignment = Enum.TextYAlignment.Top
	lbl(sec, "COUNT", 12, 170, 80, 16, 12, ctx.acc, true)
	boxCount = mkI(sec, "1", 12, 188, 70, 28, "1")

	-- Boss Mythic roll for YOUR next kills (also on the Dungeon tab).
	MythicForce.Build(ctx, sec, 100, 170, 200)

	local function refresh()
		local key = KEYS[idx]
		disp.Text = key or "(none)"
		local def = key and MythicItemDefs.Items[key]
		if not def then
			name.Text, info.Text = "", "No mythics defined."
			return
		end
		name.Text = def.DisplayName or key
		local base = def.BaseStatsAs or {}
		local subs = {}
		for _, s in ipairs(def.SubStats or {}) do
			table.insert(subs, s.useStandardRoll and (s.id .. " (std roll)") or string.format("%s %s-%s", s.id, tostring(s.min), tostring(s.max)))
		end
		info.Text = string.format("%s  |  base as %s L%s (T%s)\nGuaranteed: %s\nSource: %s", tostring(def.Kind),
			tostring(base.rarity), tostring(base.level), tostring(base.tier), table.concat(subs, ", "), tostring(def.SourceMobID))
	end
	prev.Activated:Connect(function() idx = Lists.step(idx, -1, #KEYS) refresh() end)
	nxt.Activated:Connect(function() idx = Lists.step(idx, 1, #KEYS) refresh() end)
	refresh()
	return sec
end

function Tab.ActionLabel()
	return "Spawn Mythic", MythicItemDefs.RARITY_COLOR
end

function Tab.OnAction(ctx)
	local rf = ctx.GE and ctx.GE:FindFirstChild("DevSpawnItem")
	if not rf then ctx.status("DevSpawnItem remote missing", true) return end
	local key = KEYS[idx]
	if not key then ctx.status("No mythic selected", true) return end
	local base = (MythicItemDefs.Items[key] or {}).BaseStatsAs or {}
	local ok, result = pcall(function()
		return rf:InvokeServer({ Mythic = key, Level = base.level or 21,
			Count = math.clamp(math.floor(tonumber(boxCount.Text) or 1), 1, 20) })
	end)
	if not ok or type(result) ~= "table" or not result.ok then
		ctx.status("Mythic spawn failed: " .. tostring((type(result) == "table" and result.error) or result), true)
		return
	end
	local it = result.item or {}
	ctx.status(string.format("Spawned %s (%s, L%d)", tostring(it.name), tostring(it.rarity), tonumber(it.level) or 0))
end

return Tab
