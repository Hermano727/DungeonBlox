--!strict
--  NpcShop -- the window every NPC shop opens in (rebuilt 2026-10-01): an open Journal-style
--  book (Journal/Book) over a dimmed screen, with the shop's sections in the Journal sidebar
--  beside it. Shops: MerchantBook, BlacksmithBook, StableBook (the Animal Trainer).
--
--    local shop = NpcShop.window("Merchant", MerchantBook, { sidebar = true })
--    shop.open(npcId) / shop.close()
--
--  The book component gets props { npcId, close }. It mounts fresh on every open (state such
--  as the selected item resets) and unmounts on close.
--
--  A shop is a BLOCKING overlay (RS/InteractionLock: menu hotkeys stand down while it's up),
--  frees the cursor (RS/CursorUtils) and hides the rest of the HUD (HudHider, like the Tab
--  menu). Esc, the Close button or a click on the dimmed edge closes it; so does respawning.
--  The NPC client modules (MerchantClient, BlacksmithClient, AnimalTrainerClient) are thin
--  wrappers around this, so the router (MerchantShopClient) and the dialog's OpenMenu action
--  keep calling .open(npcId) as before.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local CursorUtils = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local InteractionLock = require(ReplicatedStorage:WaitForChild("InteractionLock"))
local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local HudHider = require(script.Parent:WaitForChild("HudHider"))
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))
local Journal = script.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory"):WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))

local e = React.createElement
local player = Players.LocalPlayer

local MARGIN = 70 -- around the book, px
local SIDE_GAP = 22 -- Journal/Book's gap between the sidebar and the cover

local NpcShop = {}

function NpcShop.window(name: string, Book: any, options: { sidebar: boolean? }?)
	local sideRoom = (options and options.sidebar) and (Style.SIDEBAR_W + SIDE_GAP) or 0
	local lockOwner = "NpcShop_" .. name

	local gui = Instance.new("ScreenGui")
	gui.Name = name .. "ShopUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 160
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local root = ReactRoblox.createRoot(gui)

	local isOpen = false
	local releaseHud: (() -> ())? = nil
	local shop = {}

	local function render(npcId: string?)
		if not npcId then
			root:render(nil)
			return
		end
		root:render(e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
			Dim = e("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.45,
				AutoButtonColor = false,
				Text = "",
				ZIndex = 1,
				[React.Event.Activated] = function() shop.close() end,
			}),
			Content = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, sideRoom / 2, 0.5, 0),
				Size = UDim2.new(1, -(sideRoom + MARGIN * 2), 0.82, 0),
				BackgroundTransparency = 1,
				ZIndex = 2,
			}, {
				Book = e(Book, { npcId = npcId, close = function() shop.close() end }),
			}),
			Close = e(Parts.ChromeButton, {
				text = "Close", art = "chip", artSelected = "chip_selected",
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 24),
				Size = UDim2.fromOffset(120, 40), textSize = 16,
				onClick = function() shop.close() end,
			}),
		}))
	end

	function shop.open(npcId: string?)
		if isOpen then return end
		isOpen = true
		InteractionLock.Acquire(lockOwner)
		CursorUtils.acquire()
		releaseHud = HudHider.Acquire(gui, { keepOverlays = true, keepCore = true })
		DungeonMenuNet.requestSync() -- fresh wallet and bags before anything is priced
		render(npcId or "")
		gui.Enabled = true
	end

	function shop.close()
		if not isOpen then return end
		isOpen = false
		gui.Enabled = false
		render(nil)
		if releaseHud then releaseHud(); releaseHud = nil end
		CursorUtils.release()
		InteractionLock.Release(lockOwner)
	end

	UserInputService.InputBegan:Connect(function(input)
		if isOpen and input.KeyCode == Keys.CloseMenu then shop.close() end
	end)
	player.CharacterAdded:Connect(function() shop.close() end)

	return shop
end

return NpcShop
