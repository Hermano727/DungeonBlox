--[[
	PotionClient
	The potion slot on the HUD (right of the hunger pips, in HealthClient's PotionIconsMount)
	and the quick-drink key.

	Two numbers, kept visually apart (2026-10-02):
	  - how many potions you CARRY: the vial icon and the count on it. Bag, hotbar and equip
	    boxes count; the bank does not. Read from the profile snapshot.
	  - how many you can DRINK right now: the charge diamonds beside it (PotionService's one
	    shared pool, PotionConfig.SharedCharges). The next charge fills in as it regenerates.
	With nothing carried the vial is faded and a request reports no potions.

	Keys.QuickDrink (Z for now) drinks without holding the potion: it fires
	GameEvents/QuickDrinkPotion and the server picks the stack (the strongest carried potion,
	since charges, not potions, are the scarce part). Right-clicking a held potion still works
	(DrinkPotionClientTemplate). A refused press shakes the part that refused it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

-- Register input before any module/UI waits. A missing HUD must never disable the key.
local DrinkRequest, Keys
local function onQuickDrink(_, state)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	if UserInputService:GetFocusedTextBox() ~= nil or GuiService.MenuIsOpen then return Enum.ContextActionResult.Pass end
	if DrinkRequest then DrinkRequest.Drink() end
	return Enum.ContextActionResult.Sink
end
local function bindQuickDrink(key)
	-- Above default camera/tool binds; below PotionActionLock's High + 100.
	ContextActionService:BindActionAtPriority("PotionQuickDrink", onQuickDrink,
		false, Enum.ContextActionPriority.High.Value, key)
end
bindQuickDrink(Enum.KeyCode.Z) -- rebound below from KeybindConfig once it loads

Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
bindQuickDrink(Keys.QuickDrink)
Keys.Changed:Connect(function(id) -- rebound on Settings > Controls
	if id == nil or id == "QuickDrink" then bindQuickDrink(Keys.QuickDrink) end
end)
DrinkRequest = require(ReplicatedStorage:WaitForChild("PotionDrinkRequest"))
script.Destroying:Connect(function() ContextActionService:UnbindAction("PotionQuickDrink") end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local PotionConfig = require(ReplicatedStorage:WaitForChild("PotionConfig"))
local HudBarStyle = require(ReplicatedStorage:WaitForChild("HudBarStyle"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local InteractionLock = require(ReplicatedStorage:WaitForChild("InteractionLock"))
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))

local gameEvents = ReplicatedStorage:WaitForChild("GameEvents", 10)
local chargesSync = gameEvents and gameEvents:WaitForChild("PotionChargesSync", 10)
local requestCharges = gameEvents and gameEvents:WaitForChild("RequestPotionCharges", 10)

local MAX_CHARGES = PotionConfig.SharedCharges.maxCharges
local CHARGE_COLOR = Color3.fromRGB(176, 36, 32) -- the HP crimson, a touch brighter
local CHARGE_LIGHT = Color3.fromRGB(236, 104, 88)
local REFUSE_COLOR = Color3.fromRGB(220, 60, 50)

local ICON_SIZE = 24
local KEY_SIZE = 16
local DIAMOND = 9 -- side of the square before its 45 degree turn

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local charges = MAX_CHARGES
local nextChargeAt = nil -- os.clock() when the next charge lands, nil when full
local carried = 0
local nextItemId = PotionConfig.Order[#PotionConfig.Order]

-- Strongest first: PotionConfig.Order runs weakest -> strongest.
local function readCarried(snapshot)
	local profile = snapshot and snapshot.profile
	local inventory = profile and profile.inventory
	if type(inventory) ~= "table" then return 0, nil end
	local banked = {}
	if type(profile.chestSlots) == "table" then
		for _, uuid in pairs(profile.chestSlots) do
			if type(uuid) == "string" then banked[uuid] = true end
		end
	end
	local byId = {}
	local total = 0
	for uuid, item in pairs(inventory) do
		if type(item) == "table" and PotionConfig.Tiers[item.itemId] and not banked[uuid] then
			local n = math.max(1, tonumber(item.count) or 1)
			byId[item.itemId] = (byId[item.itemId] or 0) + n
			total += n
		end
	end
	for i = #PotionConfig.Order, 1, -1 do
		local id = PotionConfig.Order[i]
		if byId[id] then return total, id end
	end
	return total, nil
end

---------------------------------------------------------------------------
-- Build into HealthClient's mount once it exists
---------------------------------------------------------------------------

local mount
repeat
	mount = playerGui:FindFirstChild("PotionIconsMount", true)
	if not mount then task.wait(0.5) end
until mount

local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 3)
	c.Parent = parent
	return c
end

local function label(parent, text, size)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = UIFonts.HUDLabel
	t.TextSize = size
	t.TextColor3 = HudBarStyle.BONE
	t.TextStrokeTransparency = 0.35
	t.Text = text
	t.Parent = parent
	return t
end

-- The key chip: which key drinks.
local keyChip = Instance.new("Frame")
keyChip.Name = "PotionKey"
keyChip.LayoutOrder = 1
keyChip.Size = UDim2.fromOffset(KEY_SIZE, KEY_SIZE)
keyChip.BackgroundColor3 = HudBarStyle.TROUGH
keyChip.BackgroundTransparency = HudBarStyle.TROUGH_TRANSPARENCY
keyChip.Parent = mount
corner(keyChip)
stroke(keyChip, HudBarStyle.BRONZE, 1, 0.2)
local keyText = label(keyChip, Keys.DisplayName(Keys.QuickDrink), 11)
keyText.Size = UDim2.fromScale(1, 1)

-- The key label follows a rebind (Settings > Controls).
do
	local conn
	conn = Keys.Changed:Connect(function()
		if not keyText.Parent then conn:Disconnect() return end
		keyText.Text = Keys.DisplayName(Keys.QuickDrink)
	end)
end

-- The vial: what you carry.
local vial = Instance.new("ImageLabel")
vial.Name = "PotionCarried"
vial.LayoutOrder = 2
vial.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
vial.BackgroundTransparency = 1
vial.ScaleType = Enum.ScaleType.Fit
vial.Parent = mount
local vialRest = vial.Position

local countText = label(vial, "", 12)
countText.AnchorPoint = Vector2.new(1, 1)
countText.Position = UDim2.new(1, 4, 1, 3)
countText.Size = UDim2.fromOffset(16, 12)
countText.TextXAlignment = Enum.TextXAlignment.Right
countText.ZIndex = 2

-- The diamonds: what you can drink now.
local chargeRow = Instance.new("Frame")
chargeRow.Name = "PotionCharges"
chargeRow.LayoutOrder = 3
chargeRow.BackgroundTransparency = 1
chargeRow.AutomaticSize = Enum.AutomaticSize.X
chargeRow.Size = UDim2.fromOffset(0, ICON_SIZE)
chargeRow.Parent = mount
local chargeRest = chargeRow.Position
local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Padding = UDim.new(0, 5)
rowLayout.Parent = chargeRow

local rechargeText = label(mount, "Full", 12)
rechargeText.Name = "NextPotionCharge"
rechargeText.LayoutOrder = 4
-- Fixed width, just enough for "+1 in 59s", so the vitals row (fish, hunger, potion, dash) stays
-- centred as one group and doesn't shuffle sideways every second while it counts down.
rechargeText.Size = UDim2.fromOffset(58, ICON_SIZE)
rechargeText.TextXAlignment = Enum.TextXAlignment.Left

local diamonds = {}
for i = 1, MAX_CHARGES do
	-- A square cell holds the turned diamond so the list layout spaces them evenly.
	local cell = Instance.new("Frame")
	cell.Name = "Charge" .. i
	cell.LayoutOrder = i
	cell.BackgroundTransparency = 1
	cell.Size = UDim2.fromOffset(math.ceil(DIAMOND * 1.42), ICON_SIZE)
	cell.Parent = chargeRow
	local d = Instance.new("Frame")
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.fromScale(0.5, 0.5)
	d.Size = UDim2.fromOffset(DIAMOND, DIAMOND)
	d.Rotation = 45
	d.BorderSizePixel = 0
	d.Parent = cell
	local edge = stroke(d, HudBarStyle.BRONZE, 1, 0.1)
	local shine = Instance.new("UIGradient")
	shine.Rotation = 45
	shine.Color = ColorSequence.new(CHARGE_LIGHT, CHARGE_COLOR)
	shine.Parent = d
	diamonds[i] = { frame = d, edge = edge, shine = shine }
end

---------------------------------------------------------------------------
-- Render
---------------------------------------------------------------------------

local function paintDiamond(entry, fill)
	-- fill: 1 = ready, 0..1 = regenerating, 0 = spent
	local d = entry.frame
	if fill >= 1 then
		d.BackgroundColor3 = Color3.new(1, 1, 1)
		d.BackgroundTransparency = 0
		entry.shine.Enabled = true
		entry.edge.Transparency = 0.1
	else
		entry.shine.Enabled = false
		d.BackgroundColor3 = HudBarStyle.TROUGH:Lerp(CHARGE_COLOR, fill * 0.7)
		d.BackgroundTransparency = HudBarStyle.TROUGH_TRANSPARENCY
		entry.edge.Transparency = 0.45 - fill * 0.3
	end
end

local regenConnection

local function renderCharges()
	local progress = 0
	if nextChargeAt then
		local interval = PotionConfig.SharedCharges.regenInterval
		progress = math.clamp(1 - (nextChargeAt - os.clock()) / interval, 0, 0.99)
	end
	rechargeText.Text = nextChargeAt and ("+1 in " .. math.max(0, math.ceil(nextChargeAt - os.clock())) .. "s") or "Full"
	for i, entry in ipairs(diamonds) do
		if i <= charges then
			paintDiamond(entry, 1)
		elseif i == charges + 1 then
			paintDiamond(entry, progress)
		else
			paintDiamond(entry, 0)
		end
	end
	-- Only tick while a charge is regenerating.
	local regenerating = nextChargeAt ~= nil and charges < MAX_CHARGES
	if regenerating and not regenConnection then
		regenConnection = RunService.Heartbeat:Connect(renderCharges)
	elseif not regenerating and regenConnection then
		regenConnection:Disconnect()
		regenConnection = nil
	end
end

local function renderCarried()
	local id = nextItemId or PotionConfig.Order[#PotionConfig.Order]
	vial.Image = ItemDefinitions.GetIcon(id)
	vial.ImageTransparency = carried > 0 and 0 or 0.65
	countText.Text = carried > 0 and tostring(carried) or ""
	keyChip.BackgroundTransparency = carried > 0 and HudBarStyle.TROUGH_TRANSPARENCY or 0.6
	keyText.TextTransparency = carried > 0 and 0 or 0.55
end

local function applyCharges(data)
	if type(data) ~= "table" then return end
	charges = math.clamp(tonumber(data.count) or 0, 0, MAX_CHARGES)
	local s = tonumber(data.secondsUntilNext)
	if type(data.nextChargeAt) == "number" then s = math.max(0, data.nextChargeAt - workspace:GetServerTimeNow()) end
	nextChargeAt = s and (os.clock() + s) or nil
	renderCharges()
end

DungeonMenuNet.addSnapshotListener(function(snapshot)
	carried, nextItemId = readCarried(snapshot)
	renderCarried()
end)
DungeonMenuNet.start()

if chargesSync then
	chargesSync.OnClientEvent:Connect(applyCharges)
end
if requestCharges then
	task.spawn(function()
		local ok, payload = pcall(requestCharges.InvokeServer, requestCharges)
		if ok then applyCharges(payload) end
	end)
end
renderCarried()
renderCharges()

---------------------------------------------------------------------------
-- Quick drink
---------------------------------------------------------------------------

local function shake(gui, rest)
	local info = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
	gui.Position = rest
	local t = TweenService:Create(gui, info, { Position = rest + UDim2.fromOffset(3, 0) })
	t.Completed:Connect(function() gui.Position = rest end)
	t:Play()
end

local function refuse(which)
	if which == "carried" then
		shake(vial, vialRest)
		countText.TextColor3 = REFUSE_COLOR
		task.delay(0.35, function() countText.TextColor3 = HudBarStyle.BONE end)
	else
		shake(chargeRow, chargeRest)
		for _, entry in ipairs(diamonds) do entry.edge.Color = REFUSE_COLOR end
		task.delay(0.35, function()
			for _, entry in ipairs(diamonds) do entry.edge.Color = HudBarStyle.BRONZE end
		end)
	end
end

local feedback = label(keyChip, "", 12)
feedback.Name = "DrinkFeedback"
feedback.AnchorPoint = Vector2.new(0.5, 1)
feedback.Position = UDim2.new(0.5, 0, 0, -6)
feedback.Size = UDim2.fromOffset(240, 20)
local feedbackSerial = 0
local function showFeedback(message)
	feedbackSerial += 1
	local serial = feedbackSerial
	feedback.Text = message
	task.delay(2, function() if feedbackSerial == serial then feedback.Text = "" end end)
end
local reasons = {
	drinking = "Finish drinking first",
	interaction = "Close the interaction to drink",
	loading = "Preparing potion animation...",
	load_failed = "Potion animation unavailable. Try again.",
	no_charges = "No potion charges",
	no_potions = "No potions carried",
	not_held = "Hold a potion to drink it",
	not_ready = "Potion unavailable right now",
}
DrinkRequest.Feedback.Event:Connect(function(reason)
	if reason == "sent" then feedbackSerial += 1; feedback.Text = ""
	else showFeedback(reasons[reason] or "Potion unavailable right now") end
end)
task.spawn(function()
	local rejected = gameEvents and gameEvents:WaitForChild("PotionDrinkRejected", 30)
	if rejected then rejected.OnClientEvent:Connect(function(reason, snapshot)
		applyCharges(snapshot)
		refuse(reason == "no_potions" and "carried" or "charges")
		showFeedback(reasons[reason] or "Potion unavailable right now")
	end) end
end)

print("[PotionClient] ready")
