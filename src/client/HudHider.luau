--[[
	HudHider -- hide ALL other UI for a full-screen moment, then put it back exactly as it was.

		local release = HudHider.Acquire(myScreenGui)   -- myScreenGui stays visible (optional)
		...
		release()                                       -- idempotent

	Hides every ScreenGui in PlayerGui (including any created while hidden, e.g. by a respawn)
	and the Roblox core UI (chat, player list, backpack...). Reference counted: nested users
	(the dungeon end banner firing while the wardrobe is open, say) share one hidden state, and
	the UI only comes back when the LAST one releases. Each Acquire's own gui is exempt.

	Property signals are DEFERRED in this place, so the Enabled watcher runs after our own
	write: an Enabled == false seen there can't be told apart from ours. Only a gui's script
	SHOWING itself is acted on (remembered as "wants to be shown", kept hidden for now).
	Treating the false as the gui's own choice once left the whole HUD hidden after a banner.

	Users: DungeonCompleteBanner, Wardrobe.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local HudHider = {}

local count = 0
local tracked = {} -- [ScreenGui] = { wanted = bool, conn = RBXScriptConnection }
local exempt = {}  -- [ScreenGui] = number of holders exempting it
local addedConn
local coreSaved

local function track(gui)
	if not gui:IsA("ScreenGui") or exempt[gui] or tracked[gui] then return end
	local entry = { wanted = gui.Enabled }
	tracked[gui] = entry
	gui.Enabled = false
	entry.conn = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			entry.wanted = true
			gui.Enabled = false
		end
	end)
end

local function untrack(gui)
	local entry = tracked[gui]
	if not entry then return end
	tracked[gui] = nil
	entry.conn:Disconnect()
	if gui.Parent then gui.Enabled = entry.wanted end
end

local function hideAll()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, gui in ipairs(playerGui:GetChildren()) do track(gui) end
	addedConn = playerGui.ChildAdded:Connect(track)
	coreSaved = {}
	for _, coreType in ipairs(Enum.CoreGuiType:GetEnumItems()) do
		if coreType ~= Enum.CoreGuiType.All then
			local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, coreType)
			if ok then coreSaved[coreType] = enabled end
		end
	end
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false)
end

local function restoreAll()
	if addedConn then addedConn:Disconnect(); addedConn = nil end
	local list = {}
	for gui in pairs(tracked) do table.insert(list, gui) end
	for _, gui in ipairs(list) do untrack(gui) end
	for coreType, enabled in pairs(coreSaved or {}) do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreType, enabled)
	end
	coreSaved = nil
end

function HudHider.Acquire(exemptGui)
	if exemptGui then
		exempt[exemptGui] = (exempt[exemptGui] or 0) + 1
		untrack(exemptGui) -- an earlier holder may have hidden it
	end
	count += 1
	if count == 1 then hideAll() end
	local released = false
	return function()
		if released then return end
		released = true
		if exemptGui then
			exempt[exemptGui] = (exempt[exemptGui] or 1) - 1
			if exempt[exemptGui] <= 0 then exempt[exemptGui] = nil end
		end
		count -= 1
		if count <= 0 then
			count = 0
			restoreAll()
		elseif exemptGui and exemptGui.Parent and not exempt[exemptGui] then
			track(exemptGui) -- still hidden for whoever else holds it
		end
	end
end

function HudHider.IsHidden()
	return count > 0
end

return HudHider
