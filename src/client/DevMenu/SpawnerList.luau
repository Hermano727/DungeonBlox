--[[
	DevMenu/SpawnerList -- the "Managed ..." column beside the tabs that place things.

	Shows what the active tab manages (its `listType`: "Zone", "Mob" or "NPC"), sorted by distance
	from you, with coordinates; x deletes an entry. Zone rows have in-place editors (rename, cycle
	alignment, music id), all through the one DevUpdateZone remote. Your own position sits on the
	header (4 Hz, only while the column is visible): refresh() round-trips the whole list to the
	server, far too heavy to run just to move a coordinate readout.

	new(column, ctx) -> list;  list:Refresh(listType?, title?)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ui = require(script.Parent:WaitForChild("Ui"))
local ZoneConfig = require(ReplicatedStorage:WaitForChild("ZoneConfig"))

local player = Players.LocalPlayer
local C = Ui.Color

local SpawnerList = {}
SpawnerList.__index = SpawnerList

function SpawnerList.new(column, ctx)
	local self = setmetatable({ ctx = ctx, column = column }, SpawnerList)
	local GE = ctx.GE
	self.rfList = GE and GE:WaitForChild("DevListSpawners", 10)
	self.evDelete = GE and GE:WaitForChild("DevDeleteSpawner", 10)
	self.rfUpdateZone = GE and GE:WaitForChild("DevUpdateZone", 10)

	self.title = Ui.lbl(column, "MANAGED", 10, 6, 220, 20, 13, C.Label, true)
	self.coords = Ui.lbl(column, "", 0, 6, 0, 20, 12, Color3.fromRGB(150, 160, 150), false, Enum.TextXAlignment.Right)
	self.coords.AnchorPoint = Vector2.new(1, 0)
	self.coords.Position = UDim2.new(1, -10, 0, 6)
	self.coords.Size = UDim2.fromOffset(200, 20)

	local frame = Instance.new("ScrollingFrame")
	frame.Position = UDim2.fromOffset(8, 32)
	frame.Size = UDim2.new(1, -16, 1, -40)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ScrollBarThickness = 5
	frame.ScrollBarImageColor3 = C.Rim
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.CanvasSize = UDim2.new()
	frame.ZIndex = 3
	frame.Parent = column
	Instance.new("UIListLayout", frame).Padding = UDim.new(0, 4)
	self.frame = frame

	task.spawn(function()
		while true do
			task.wait(0.25)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if column.Visible and column:FindFirstAncestorOfClass("ScreenGui").Enabled and root then
				self.coords.Text = string.format("YOU  %.0f, %.0f, %.0f", root.Position.X, root.Position.Y, root.Position.Z)
			end
		end
	end)
	return self
end

local function rowButton(row, text, position, size, color)
	local b = Instance.new("TextButton")
	b.Position = position
	b.Size = size
	b.BackgroundColor3 = color or C.Plate
	b.BorderSizePixel = 0
	pcall(function() b.FontFace = Ui.Font.BodyBold end)
	b.TextSize = 12
	b.TextColor3 = C.Text
	b.Text = text
	b.ZIndex = 5
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	b.Parent = row
	return b
end

local function rowBox(row, placeholder, text, position, size)
	local box = Instance.new("TextBox")
	box.Position = position
	box.Size = size
	box.BackgroundColor3 = C.Field
	box.BorderSizePixel = 0
	pcall(function() box.FontFace = Ui.Font.Body end)
	box.TextSize = 12
	box.TextColor3 = C.Text
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(110, 95, 80)
	box.ClearTextOnFocus = false
	box.Text = text
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ZIndex = 5
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
	box.Parent = row
	return box
end

function SpawnerList:Refresh(listType, title)
	for _, child in ipairs(self.frame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	self.title.Text = title or "MANAGED"
	if not listType or not self.rfList then return end

	local ok, entries = pcall(function() return self.rfList:InvokeServer() end)
	if not ok or type(entries) ~= "table" then return end
	for i = #entries, 1, -1 do
		if entries[i].SpawnerType ~= listType then table.remove(entries, i) end
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	table.sort(entries, function(a, b)
		if not root then return tostring(a.Label) < tostring(b.Label) end
		return (a.Position - root.Position).Magnitude < (b.Position - root.Position).Magnitude
	end)

	local ctx = self.ctx
	for _, entry in ipairs(entries) do
		local isMob, isZone = entry.SpawnerType == "Mob", entry.SpawnerType == "Zone"
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -4, 0, isZone and 84 or 30)
		row.BackgroundColor3 = Color3.fromRGB(44, 32, 24)
		row.BorderSizePixel = 0
		row.ZIndex = 4
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
		row.Parent = self.frame

		local p = entry.Position
		local label = Ui.lbl(row, "", 8, 0, 0, 30, 13,
			isZone and Color3.fromRGB(220, 215, 150) or (isMob and Color3.fromRGB(255, 150, 140) or Color3.fromRGB(150, 205, 255)))
		label.Size = UDim2.new(1, -40, 0, 30)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = 5
		label.Text = string.format("%s%s  [%.0f, %.0f, %.0f]", isZone and "ZONE " or (isMob and "MOB  " or "NPC  "),
			tostring(entry.Label), p.X, p.Y, p.Z)

		local spawnId, zoneId, partRef = entry.SpawnId, entry.ZoneId, entry.Part
		local delete = rowButton(row, "x", UDim2.new(1, -30, 0, 5), UDim2.fromOffset(24, 20), C.Bad)
		delete.Activated:Connect(function()
			if not self.evDelete then return end
			if type(zoneId) == "string" and zoneId ~= "" then
				self.evDelete:FireServer({ Type = "Zone", ZoneId = zoneId })
			elseif type(spawnId) == "string" and spawnId ~= "" then
				self.evDelete:FireServer({ SpawnId = spawnId })
			elseif partRef and partRef.Parent then
				self.evDelete:FireServer(partRef)
			end
			task.delay(0.4, function() self:Refresh(listType, title) end)
		end)

		if isZone then
			-- One helper for every per-row zone edit; they all go through DevUpdateZone.
			local function updateZone(fields, okMessage)
				if not self.rfUpdateZone or type(zoneId) ~= "string" or zoneId == "" then return end
				fields.ZoneId = zoneId
				local okCall, result = pcall(function() return self.rfUpdateZone:InvokeServer(fields) end)
				if okCall and type(result) == "table" and result.ok then
					ctx.status(okMessage(result.zone))
					task.delay(0.2, function() self:Refresh(listType, title) end)
				else
					local err = (okCall and type(result) == "table" and result.error) or tostring(result)
					ctx.status("Zone update failed: " .. tostring(err), true)
				end
			end

			local nameBox = rowBox(row, "zone name", tostring(entry.ZoneName or ""), UDim2.fromOffset(8, 30), UDim2.new(1, -200, 0, 22))
			rowButton(row, "Rename", UDim2.new(1, -188, 0, 30), UDim2.fromOffset(80, 22)).Activated:Connect(function()
				updateZone({ Name = nameBox.Text }, function(z) return "Zone renamed: " .. ((z and z.name) or nameBox.Text) end)
			end)

			local rowAlignment = tostring(entry.Alignment or "Lawful")
			local alignBtn = rowButton(row, "", UDim2.new(1, -102, 0, 30), UDim2.fromOffset(96, 22))
			local function paintAlign()
				alignBtn.Text = ZoneConfig.DisplayAlignment(rowAlignment):upper()
				alignBtn.BackgroundColor3 = ZoneConfig.ALIGNMENT_COLORS[rowAlignment] or C.Plate
				alignBtn.TextColor3 = Color3.new(0, 0, 0)
			end
			paintAlign()
			alignBtn.Activated:Connect(function()
				-- Cycles Lawful -> Wilderness (Neutral) -> Chaotic and saves immediately.
				local order = ZoneConfig.ALIGNMENTS_ORDERED
				local idx = table.find(order, rowAlignment) or 1
				rowAlignment = order[(idx % #order) + 1]
				paintAlign()
				updateZone({ Alignment = rowAlignment }, function(z)
					return "Zone alignment: " .. ZoneConfig.DisplayAlignment((z and z.alignment) or rowAlignment)
				end)
			end)

			local musicBox = rowBox(row, "music id (blank = none)", tostring(entry.MusicId or ""), UDim2.fromOffset(8, 56), UDim2.new(1, -74, 0, 22))
			rowButton(row, "Save", UDim2.new(1, -62, 0, 56), UDim2.fromOffset(56, 22)).Activated:Connect(function()
				updateZone({ MusicId = musicBox.Text }, function(z) return "Zone music updated: " .. ((z and z.name) or zoneId) end)
			end)
		end
	end
end

return SpawnerList
