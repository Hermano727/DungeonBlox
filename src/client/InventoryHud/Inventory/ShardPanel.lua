--!strict
--  ShardPanel -- the Shard Hopping menu. Same tile-grid visual language as
--  HearthstonePanel (gold-stroked square tiles inside one bordered grid
--  background), since it's the closest existing analog: a location picker
--  with a header status line and an async server round-trip per action.
--
--  Wiring (ShardService owns the actual server logic; ShardService itself
--  creates the RemoteFunctions/RemoteEvent this uses, at server start):
--    - ShardListRequest (RemoteFunction) -- fetch { shards, currentShardIndex }.
--      Polled every 5s while the panel is open so population counts stay fresh.
--    - ShardHopRequest (RemoteFunction) -- request a hop to a tile's shard
--      index. Returns ok, durationOrErr -- a successful, non-zero duration
--      starts the local channel/cast-bar countdown; 0 means it already
--      resolved (safe zone, instant).
--    - ShardHopStatus (RemoteEvent, server -> client) -- async pushes during
--      the channel: "channeling" (redundant with the RequestHop reply, but
--      harmless), "cancelled" (reason: "damaged" | "in_combat" | anything
--      ShardService.CancelChannel was called with), "shard_full",
--      "teleporting", "error".
--    - ShardReturnToMain (RemoteFunction) -- only shown when currentShardIndex
--      is set (i.e. we're actually on a shard right now): leaves the shard
--      pool and rejoins Roblox's normal public matchmaking for this place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local RunService = game:GetService("RunService")
local React = require(ReplicatedStorage.Packages.React)
local PanelShell = require(script.Parent:WaitForChild("PanelShell"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local e = React.createElement

local rfHop = ReplicatedStorage:WaitForChild("ShardHopRequest", 30)
local rfList = ReplicatedStorage:WaitForChild("ShardListRequest", 30)
local rfReturn = ReplicatedStorage:WaitForChild("ShardReturnToMain", 30)
local evStatus = ReplicatedStorage:WaitForChild("ShardHopStatus", 30)

-- Same palette as HearthstonePanel/PlayerPreview/InvSlots -- dark wood, gold
-- slot borders, cream text.
local THEME = {
	GridBg = Color3.fromRGB(20, 16, 13),
	SlotBg = Color3.fromRGB(26, 18, 11),
	SlotBorder = UITheme.Gold,
	LabelText = Color3.fromRGB(240, 230, 210),
	ActiveGold = Color3.fromRGB(255, 210, 110),
	FullRed = Color3.fromRGB(200, 90, 80),
}

local TILE_SIZE = 96
local TILE_GAP = 12
local HEADER_H = 60
local LIST_POLL_INTERVAL = 5

local function formatCountdown(secs: number): string
	secs = math.max(0, math.floor(secs))
	return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

local function ShardTile(props: {
	index: number,
	population: number,
	cap: number,
	isFull: boolean,
	isCurrent: boolean,
	isChanneling: boolean,
	layoutOrder: number,
	onClick: (() -> ())?,
})
	local disabled = props.isCurrent or props.isFull
	return e("TextButton", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.fromOffset(TILE_SIZE, TILE_SIZE),
		BackgroundColor3 = THEME.SlotBg,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = not disabled,
		Text = "",
		[React.Event.Activated] = (not disabled) and props.onClick or nil,
	}, {
		Stroke = e("UIStroke", {
			Color = props.isCurrent and THEME.ActiveGold or (props.isFull and THEME.FullRed or THEME.SlotBorder),
			Thickness = props.isCurrent and 3 or 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),

		Name = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.38),
			Size = UDim2.new(1, -8, 0, 24),
			BackgroundTransparency = 1,
			Text = "SHARD " .. tostring(props.index),
			FontFace = UIFonts.BodyBold,
			TextSize = 14,
			TextColor3 = THEME.LabelText,
			ZIndex = 2,
		}),

		Pop = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.62),
			Size = UDim2.new(1, -8, 0, 16),
			BackgroundTransparency = 1,
			Text = props.isFull and "FULL" or (tostring(props.population) .. "/" .. tostring(props.cap)),
			FontFace = UIFonts.Body,
			TextSize = 11,
			TextColor3 = props.isFull and THEME.FullRed or Color3.fromRGB(190, 180, 165),
			ZIndex = 2,
		}),

		ActiveTag = props.isCurrent and e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.new(1, 0, 0, 12),
			BackgroundTransparency = 1,
			Text = "HERE",
			FontFace = UIFonts.BodyBold,
			TextSize = 9,
			TextColor3 = THEME.ActiveGold,
			ZIndex = 2,
		}) or nil,
	})
end

local function ShardPanel(props: { onClose: () -> () })
	local shards, setShards = React.useState({} :: { any })
	local currentShardIndex, setCurrentShardIndex = React.useState(nil :: number?)
	local status, setStatus = React.useState("")
	local channel, setChannel = React.useState(nil :: { targetShardIndex: number, duration: number, startedAt: number }?)
	local _tick, setTick = React.useState(0)

	local function showStatus(msg: string)
		setStatus(msg)
		task.delay(4, function()
			setStatus(function(cur)
				if cur == msg then return "" end
				return cur
			end)
		end)
	end

	local function refreshList()
		task.spawn(function()
			local ok, result = pcall(function()
				return rfList:InvokeServer()
			end)
			if ok and type(result) == "table" then
				setShards(result.shards or {})
				setCurrentShardIndex(result.currentShardIndex)
			end
		end)
	end

	-- Initial fetch + periodic poll while the panel is open.
	React.useEffect(function()
		refreshList()
		local acc = 0
		local conn = RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc >= LIST_POLL_INTERVAL then
				acc = 0
				refreshList()
			end
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	-- ~1/sec re-render tick so the channel countdown stays live.
	React.useEffect(function()
		local nextUpdate = 0
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now >= nextUpdate then
				nextUpdate = now + 1
				setTick(function(n) return n + 1 end)
			end
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	-- Server-pushed async updates during a channel.
	React.useEffect(function()
		local conn = evStatus.OnClientEvent:Connect(function(kind, extra)
			if kind == "channeling" then
				-- no-op here -- local state already set by doHop below
			elseif kind == "cancelled" then
				setChannel(nil)
				if extra == "damaged" then
					showStatus("Shard hop cancelled -- you took damage.")
				elseif extra == "in_combat" then
					showStatus("Shard hop cancelled -- you're in combat.")
				else
					showStatus("Shard hop cancelled.")
				end
			elseif kind == "shard_full" then
				setChannel(nil)
				showStatus("Shard " .. tostring(extra) .. " is full -- pick another.")
				refreshList()
			elseif kind == "teleporting" then
				showStatus("Entering Shard " .. tostring(extra) .. "...")
			elseif kind == "error" then
				setChannel(nil)
				showStatus("Shard hop failed: " .. tostring(extra))
			end
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	local function doHop(targetIndex: number)
		if channel then return end
		local ok, success, durationOrErr = pcall(function()
			return rfHop:InvokeServer(targetIndex)
		end)
		if not (ok and success) then
			local err = (ok and durationOrErr) or success
			if err == "in_combat" then
				showStatus("Can't hop while in combat.")
			elseif err == "already_channeling" then
				showStatus("Already channeling a hop.")
			else
				showStatus(tostring(err or "Shard hop failed."))
			end
			return
		end
		local duration = tonumber(durationOrErr) or 0
		if duration <= 0 then
			showStatus("Entering Shard " .. tostring(targetIndex) .. "...")
			return
		end
		setChannel({ targetShardIndex = targetIndex, duration = duration, startedAt = os.clock() })
	end

	local function doReturnToMain()
		task.spawn(function()
			local ok, success, err = pcall(function()
				return rfReturn:InvokeServer()
			end)
			if not (ok and success) then
				showStatus(tostring((ok and err) or success or "Failed to return to main."))
			else
				showStatus("Returning to the main server...")
			end
		end)
	end

	local remaining = channel and (channel.duration - (os.clock() - channel.startedAt)) or 0

	local tiles: { [string]: any } = {
		Layout = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(TILE_SIZE, TILE_SIZE),
			CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
	}
	for _, row in ipairs(shards) do
		local idx = row.index
		tiles["shard" .. tostring(idx)] = e(ShardTile, {
			index = idx,
			population = row.population or 0,
			cap = row.cap or 0,
			isFull = row.isFull == true,
			isCurrent = currentShardIndex == idx,
			isChanneling = channel ~= nil,
			layoutOrder = idx,
			onClick = function()
				doHop(idx)
			end,
		})
	end

	local headerLabel = currentShardIndex
		and ("Current Shard: " .. tostring(currentShardIndex))
		or "Current Shard: Main Server"

	return e(PanelShell, { title = "Shards", onClose = props.onClose }, {
		Content = e("Frame", {
			Size = UDim2.new(1, -32, 1, -32),
			Position = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
		}, {
			Header = e("Frame", {
				Size = UDim2.new(1, 0, 0, HEADER_H),
				BackgroundTransparency = 1,
			}, {
				Label = e("TextLabel", {
					Size = UDim2.new(1, -220, 0, 24),
					BackgroundTransparency = 1,
					FontFace = UIFonts.BodyBold,
					TextSize = 16,
					TextColor3 = THEME.LabelText,
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = headerLabel,
				}),
				Status = e("TextLabel", {
					Position = UDim2.fromOffset(0, 26),
					Size = UDim2.new(1, -220, 0, 16),
					BackgroundTransparency = 1,
					FontFace = UIFonts.Body,
					TextSize = 11,
					TextColor3 = Color3.fromRGB(150, 216, 150),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					Text = channel and ("Channeling... " .. formatCountdown(remaining)) or status,
				}),
				ReturnButton = currentShardIndex and e("TextButton", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 4),
					Size = UDim2.fromOffset(160, 36),
					BackgroundColor3 = Color3.fromRGB(160, 118, 38),
					BorderSizePixel = 0,
					FontFace = UIFonts.BodyBold,
					TextSize = 13,
					TextColor3 = Color3.new(1, 1, 1),
					Text = "Return to Main",
					[React.Event.Activated] = doReturnToMain,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
				}) or nil,
			}),

			GridPanel = e("Frame", {
				Position = UDim2.fromOffset(0, HEADER_H),
				Size = UDim2.new(1, 0, 1, -HEADER_H),
				BackgroundColor3 = THEME.GridBg,
				BorderSizePixel = 0,
			}, {
				Stroke = e("UIStroke", { Color = THEME.SlotBorder, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
				Padding = e("UIPadding", {
					PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
					PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16),
				}),
				Tiles = e("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
				}, tiles),
			}),
		}),
	})
end

return ShardPanel
