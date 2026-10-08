-- Secure the physical potion on the server; client visuals follow the skinned Hand_R.
-- Standard Tool grips cannot attach to a Bone. No client physics owns the held vial.
local Storage = {}

function Storage.Bind(tool, player)
	local character = player.Character
	if not character or not character:FindFirstChild("Hero_Character") then return end
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return end
	local parts = {}
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") then
			parts[part] = part.Transparency
			part:SetAttribute("PotionVisualOffset", handle.CFrame:ToObjectSpace(part.CFrame))
			part:SetAttribute("PotionVisualTransparency", part.Transparency)
			part.Anchored = false
			part.CanCollide, part.CanTouch, part.CanQuery, part.Massless = false, false, false, true
		end
	end
	tool.RequiresHandle = false
	local count = 0
	for _ in pairs(parts) do count += 1 end
	tool:SetAttribute("PotionVisualPartCount", count)
	tool:SetAttribute("BonePotionVisual", true)
	local storageWeld
	local function refresh()
		if storageWeld then storageWeld:Destroy(); storageWeld = nil end
		local root = character:FindFirstChild("HumanoidRootPart")
		local held = tool.Parent == character and root ~= nil
		for part, transparency in pairs(parts) do
			if part.Parent then part.Transparency = held and 1 or transparency end
		end
		if held then
			-- Other vial parts already have WeldConstraints to Handle.
			handle.CFrame = root.CFrame
			storageWeld = Instance.new("WeldConstraint")
			storageWeld.Name = "PotionStorageWeld"
			storageWeld.Part0, storageWeld.Part1 = root, handle
			storageWeld.Parent = handle
		end
	end
	local connection = tool.AncestryChanged:Connect(refresh)
	tool.Destroying:Connect(function()
		connection:Disconnect()
		if storageWeld then storageWeld:Destroy(); storageWeld = nil end
	end)
	refresh()
end

return Storage
