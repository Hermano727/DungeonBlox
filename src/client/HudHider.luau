--[[
	HudHider -- hide ALL other UI for a full-screen moment, then put it back exactly as it was.

		local release = HudHider.Acquire(myScreenGui)   -- myScreenGui stays visible (optional)
		...
		release()                                       -- idempotent

		HudHider.Acquire(myScreenGui, { keepOverlays = true, keepCore = true })
			-- a full-screen MENU (the Tab menu): ScreenGuis tagged HudHider.OVERLAY_TAG stay up
			-- too, and the Roblox core UI (chat, player list...) is left alone

	Hides every ScreenGui in PlayerGui (including any created while hidden, e.g. by a respawn)
	and, unless kept, the Roblox core UI. Reference counted: nested users (the dungeon end
	banner firing while the wardrobe is open, say) share one hidden state, and the UI only comes
	back when the LAST one releases. Each Acquire's own gui is exempt. When holders disagree,
	the strictest wins (an overlay / the core UI stays up only if EVERY holder keeps it).

	Overlays (CollectionService tag OVERLAY_TAG, "OverMenus"): UI that belongs on top of a
	full-screen menu, by its own declaration: the HP / hunger cluster, centre-screen messages,
	loot banners, the inventory courtyard. Tag the ScreenGui BEFORE parenting it (an untagged
	gui added while hidden is hidden on arrival; a tag added later still un-hides it). Anything
	untagged (minimap, its settings / crosshair buttons, XP bars, party frames, any future HUD)
	hides behind a menu automatically, with no per-HUD code.

	Property signals are DEFERRED in this place, so the Enabled watcher runs after our own
	write: an Enabled == false seen there can't be told apart from ours. Only a gui's script
	SHOWING itself is acted on (remembered as "wants to be shown", kept hidden for now).
	Treating the false as the gui's own choice once left the whole HUD hidden after a banner.

	Users: DungeonCompleteBanner, Wardrobe, the Miasma cutscenes, SpectatorClient, and the Tab
	menu (InventoryHud, keepOverlays + keepCore).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local HudHider = {}

HudHider.OVERLAY_TAG = "OverMenus"

local holders = {} -- [token] = { keepOverlays = bool, keepCore = bool }
local count = 0
local tracked = {} -- [ScreenGui] = { wanted = bool, conn = RBXScriptConnection }
local exempt = {}  -- [ScreenGui] = number of holders exempting it
local applied = { keepOverlays = false, keepCore = false } -- the policy hideAll last used
local addedConn, tagConn
local coreSaved

-- Strictest policy over every current holder.
local function policy()
	local keepOverlays, keepCore = true, true
	for _, h in pairs(holders) do
		keepOverlays = keepOverlays and h.keepOverlays
		keepCore = keepCore and h.keepCore
	end
	return keepOverlays, keepCore
end

local function isKept(gui)
	return exempt[gui] ~= nil or (applied.keepOverlays and CollectionService:HasTag(gui, HudHider.OVERLAY_TAG))
end

local function track(gui)
	if not gui:IsA("ScreenGui") or tracked[gui] or isKept(gui) then return end
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
	local keepOverlays, keepCore = policy()
	applied.keepOverlays, applied.keepCore = keepOverlays, keepCore
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, gui in ipairs(playerGui:GetChildren()) do track(gui) end
	addedConn = playerGui.ChildAdded:Connect(track)
	-- A gui tagged after it was hidden comes back (if overlays are kept right now).
	tagConn = CollectionService:GetInstanceAddedSignal(HudHider.OVERLAY_TAG):Connect(function(gui)
		if applied.keepOverlays then untrack(gui) end
	end)
	if not keepCore then
		coreSaved = {}
		for _, coreType in ipairs(Enum.CoreGuiType:GetEnumItems()) do
			if coreType ~= Enum.CoreGuiType.All then
				local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, coreType)
				if ok then coreSaved[coreType] = enabled end
			end
		end
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false)
	end
end

local function restoreAll()
	if addedConn then addedConn:Disconnect(); addedConn = nil end
	if tagConn then tagConn:Disconnect(); tagConn = nil end
	local list = {}
	for gui in pairs(tracked) do table.insert(list, gui) end
	for _, gui in ipairs(list) do untrack(gui) end
	for coreType, enabled in pairs(coreSaved or {}) do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, coreType, enabled)
	end
	coreSaved = nil
end

-- Re-applies the hidden state after the set of holders changed. Restore + hide run in one go
-- (no frame renders in between), so nothing visibly flickers.
local function refresh()
	restoreAll()
	if count > 0 then hideAll() end
end

function HudHider.Acquire(exemptGui, options)
	options = options or {}
	local token = {}
	holders[token] = { keepOverlays = options.keepOverlays == true, keepCore = options.keepCore == true }
	if exemptGui then
		exempt[exemptGui] = (exempt[exemptGui] or 0) + 1
	end
	count += 1
	refresh()
	local released = false
	return function()
		if released then return end
		released = true
		holders[token] = nil
		if exemptGui then
			exempt[exemptGui] = (exempt[exemptGui] or 1) - 1
			if exempt[exemptGui] <= 0 then exempt[exemptGui] = nil end
		end
		count = math.max(0, count - 1)
		refresh()
	end
end

-- Declare a ScreenGui an overlay that stays up over full-screen menus (call before parenting).
function HudHider.MarkOverlay(gui)
	CollectionService:AddTag(gui, HudHider.OVERLAY_TAG)
end

function HudHider.IsHidden()
	return count > 0
end

return HudHider
