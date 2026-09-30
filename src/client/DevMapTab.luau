--[[
	DevMapTab -- the F8 dev panel's MAP tab (DevClient mode "Map").

	Resets YOUR world map: forgets every discovered region and every explored cell (Oakhaven
	comes back as the default), through the dev-gated MinimapDevAction remote
	(SSS/MinimapService). The map reloads at once; the region you're standing in is
	re-discovered within half a second, banner and peek included, which makes this the quick
	way to test discovery. Lives outside DevClient (Luau's 200-locals limit), like DevProfileTab.

	Build(ctx) -> section Frame (starts hidden; DevClient toggles Visible with the tab).
	ctx: parent, y, w, h, lbl, mkB, mkI (DevClient's UI helpers), acc, gold, status(msg, isErr).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevMapTab = {}

local CONFIRM_SECONDS = 4

function DevMapTab.Build(ctx)
	local lbl, mkB, status = ctx.lbl, ctx.mkB, ctx.status
	local W = ctx.w

	local sec = Instance.new("Frame")
	sec.Name = "MapSection"
	sec.Position = UDim2.fromOffset(0, ctx.y)
	sec.Size = UDim2.fromOffset(W, ctx.h)
	sec.BackgroundTransparency = 1
	sec.Visible = false
	sec.Parent = ctx.parent

	lbl(sec, "WORLD MAP", 12, 2, 200, 16, 11, ctx.acc, true)
	lbl(sec, "Forgets your discovered regions and explored ground. Saved to your profile.", 12, 18, W - 24, 14, 10, Color3.fromRGB(150, 135, 120))
	lbl(sec, "The region you stand in is re-discovered right away (banner + peek).", 12, 32, W - 24, 14, 10, Color3.fromRGB(150, 135, 120))

	local IDLE_TEXT = "Reset My Map"
	local button = mkB(sec, IDLE_TEXT, 12, 56, 180, 32, Color3.fromRGB(120, 40, 40))
	local armedUntil = 0

	button.Activated:Connect(function()
		local now = os.clock()
		if now > armedUntil then
			-- First click arms it: a map reset can't be undone.
			armedUntil = now + CONFIRM_SECONDS
			button.Text = "Click again to confirm"
			task.delay(CONFIRM_SECONDS, function()
				if os.clock() >= armedUntil then button.Text = IDLE_TEXT end
			end)
			return
		end
		armedUntil = 0
		button.Text = IDLE_TEXT
		local rf = ReplicatedStorage:WaitForChild("GameEvents"):FindFirstChild("MinimapDevAction")
		if not rf then status("MinimapDevAction remote missing", true) return end
		local pOk, ok, err = pcall(function() return rf:InvokeServer("reset") end)
		if not pOk then
			status("Failed: " .. tostring(ok), true)
		elseif ok then
			status("Map reset")
		else
			status("Failed: " .. tostring(err), true)
		end
	end)

	return sec
end

return DevMapTab
