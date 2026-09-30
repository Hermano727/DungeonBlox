--!strict
--  PartyPanel -- quick, deliberately plain mockup of the party menu, wired
--  to the real PartyRequest/PartyStateSync remotes -- see
--  ServerScriptService.PartyService and StarterPlayerScripts.PartyClient for
--  the existing system this borrows its request/response shape from.
--
--  Behavior: "No Party" + Create/Leave (Leave greyed out until you're in a
--  party). Once in a party, an Invite button reveals a side list of other
--  players currently in the server, matching PartyClient's existing
--  server-list logic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local React = require(ReplicatedStorage.Packages.React)
local PanelShell = require(script.Parent:WaitForChild("PanelShell"))

local e = React.createElement
local player = Players.LocalPlayer

local PartyRequestUtil = require(ReplicatedStorage:WaitForChild("PartyRequestUtil"))

-- Shared with PartyClient (the legacy popup) so both UIs talk to
-- PartyRequest the same way instead of each keeping their own copy.
local function request(action: string, arg: any?): (boolean, any)
	return PartyRequestUtil.Request(action, arg)
end

local function PartyPanel(props: { onClose: () -> () })
	-- Seeded from the shared cache: this panel re-mounts on every open, and used to start
	-- empty ("No Party", Leave greyed out) until the next party change.
	local myParty, setMyParty = React.useState(PartyRequestUtil.GetMyParty() :: any)
	local inviteOpen, setInviteOpen = React.useState(false)
	local status, setStatus = React.useState("")
	local players, setPlayers = React.useState(Players:GetPlayers())

	React.useEffect(function()
		local conn = PartyRequestUtil.Changed:Connect(function(payload)
			setMyParty(payload.myParty)
		end)
		-- And ask the server once on open, in case the cache missed the join-time push.
		task.spawn(PartyRequestUtil.Refresh)
		return function()
			conn:Disconnect()
		end
	end, {})

	React.useEffect(function()
		local function refreshPlayers()
			setPlayers(Players:GetPlayers())
		end
		local c1 = Players.PlayerAdded:Connect(refreshPlayers)
		local c2 = Players.PlayerRemoving:Connect(refreshPlayers)
		return function()
			c1:Disconnect()
			c2:Disconnect()
		end
	end, {})

	local inParty = myParty ~= nil

	local function onCreate()
		local ok, err = request("create")
		setStatus(ok and "Party created" or ("Could not create party: " .. tostring(err)))
	end
	local function onLeave()
		if not inParty then
			return
		end
		local ok, err = request("leave")
		setStatus(ok and "Left party" or ("Leave failed: " .. tostring(err)))
		setInviteOpen(false)
	end
	local function onInvite(targetUserId: number, targetName: string)
		local ok, err = request("invite", targetUserId)
		setStatus(ok and ("Invite sent to " .. targetName) or ("Invite failed: " .. tostring(err)))
	end

	local memberRows: { [string]: any } = {
		Layout = e("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	if inParty and myParty.members then
		for i, m in ipairs(myParty.members) do
			memberRows["m" .. i] = e("TextLabel", {
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundTransparency = 1,
				FontFace = UIFonts.BodyMedium,
				TextSize = 14,
				TextColor3 = (m.userId == myParty.leaderUserId) and Color3.fromRGB(255, 220, 130)
					or Color3.fromRGB(220, 220, 225),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = (m.userId == myParty.leaderUserId) and ("* " .. m.name .. "  (leader)") or m.name,
			})
		end
	end

	local inviteRows: { [string]: any } = {
		Layout = e("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for i, plr in ipairs(players) do
		if plr ~= player then
			local display = plr.DisplayName ~= "" and plr.DisplayName or plr.Name
			inviteRows[tostring(plr.UserId)] = e("TextButton", {
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundColor3 = Color3.fromRGB(55, 95, 65),
				BorderSizePixel = 0,
				FontFace = UIFonts.BodyBold,
				TextSize = 13,
				TextColor3 = Color3.new(1, 1, 1),
				Text = "Invite " .. display,
				AutoButtonColor = true,
				[React.Event.Activated] = function()
					onInvite(plr.UserId, display)
				end,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			})
		end
	end

	return e(PanelShell, { title = "Party", onClose = props.onClose }, {
		Content = e("Frame", {
			Size = UDim2.new(1, -32, 1, -32),
			Position = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
		}, {
			Status = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				FontFace = UIFonts.Body,
				TextSize = 12,
				TextColor3 = Color3.fromRGB(150, 200, 150),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = status,
			}),

			NoPartyLabel = (not inParty) and e("TextLabel", {
				Position = UDim2.fromOffset(0, 26),
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundTransparency = 1,
				FontFace = UIFonts.BodyBold,
				TextSize = 16,
				TextColor3 = Color3.fromRGB(200, 190, 175),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "No Party",
			}) or nil,

			Members = inParty and e("Frame", {
				Position = UDim2.fromOffset(0, 26),
				Size = UDim2.new(1, 0, 0, 120),
				BackgroundTransparency = 1,
			}, memberRows) or nil,

			CreateBtn = e("TextButton", {
				Position = UDim2.fromOffset(0, 160),
				Size = UDim2.fromOffset(140, 32),
				BackgroundColor3 = inParty and Color3.fromRGB(40, 40, 40) or Color3.fromRGB(50, 80, 55),
				BorderSizePixel = 0,
				FontFace = UIFonts.BodyBold,
				TextSize = 14,
				TextColor3 = inParty and Color3.fromRGB(120, 120, 120) or Color3.new(1, 1, 1),
				Text = "Create Party",
				AutoButtonColor = not inParty,
				[React.Event.Activated] = (not inParty) and onCreate or nil,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
			}),

			LeaveBtn = e("TextButton", {
				Position = UDim2.fromOffset(150, 160),
				Size = UDim2.fromOffset(120, 32),
				BackgroundColor3 = inParty and Color3.fromRGB(120, 45, 45) or Color3.fromRGB(40, 40, 40),
				BorderSizePixel = 0,
				FontFace = UIFonts.BodyBold,
				TextSize = 14,
				TextColor3 = inParty and Color3.new(1, 1, 1) or Color3.fromRGB(120, 120, 120),
				Text = "Leave Party",
				AutoButtonColor = inParty,
				[React.Event.Activated] = inParty and onLeave or nil,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
			}),

			InviteBtn = inParty and e("TextButton", {
				Position = UDim2.fromOffset(0, 202),
				Size = UDim2.fromOffset(140, 32),
				BackgroundColor3 = Color3.fromRGB(50, 70, 90),
				BorderSizePixel = 0,
				FontFace = UIFonts.BodyBold,
				TextSize = 14,
				TextColor3 = Color3.new(1, 1, 1),
				Text = inviteOpen and "Hide Players" or "Invite...",
				AutoButtonColor = true,
				[React.Event.Activated] = function()
					setInviteOpen(function(v)
						return not v
					end)
				end,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
			}) or nil,

			InvitePanel = (inParty and inviteOpen) and e("Frame", {
				Position = UDim2.fromOffset(0, 246),
				Size = UDim2.new(1, 0, 1, -246),
				BackgroundColor3 = Color3.fromRGB(20, 15, 13),
				BorderSizePixel = 0,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
				List = e("ScrollingFrame", {
					Size = UDim2.new(1, -12, 1, -12),
					Position = UDim2.fromOffset(6, 6),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollBarThickness = 6,
				}, inviteRows),
			}) or nil,
		}),
	})
end

return PartyPanel
