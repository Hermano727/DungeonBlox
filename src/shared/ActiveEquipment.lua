-- Replicated active-selection contract. Slot assignment is still profile.equipped;
-- only the server writes ActiveEquipmentUuid on the current character.
local ActiveEquipment = {}

ActiveEquipment.ATTRIBUTE = "ActiveEquipmentUuid"
ActiveEquipment.Slots = { "Weapon", "Bow", "Pickaxe", "FishingSpear" }

function ActiveEquipment.GetTool(character)
	if not character then return nil end
	local uuid = character:GetAttribute(ActiveEquipment.ATTRIBUTE)
	if type(uuid) ~= "string" or uuid == "" then return nil end
	for _, tool in ipairs(character:GetChildren()) do
		if tool:IsA("Tool") and tool:GetAttribute("DungeonEquipped") == true
			and tool:GetAttribute("DungeonItemUuid") == uuid then
			return tool
		end
	end
	return nil
end

-- Coalesce replication events, including metadata arriving after Tool.Parent.
-- The returned cleanup also invalidates already-deferred callbacks.
function ActiveEquipment.Observe(character, callback)
	local alive, queued = true, false
	local connections, toolConnections = {}, {}
	local function refresh()
		if queued or not alive then return end
		queued = true
		task.defer(function()
			queued = false
			if alive then callback(ActiveEquipment.GetTool(character)) end
		end)
	end
	local function watch(tool)
		if tool:IsA("Tool") and not toolConnections[tool] then
			toolConnections[tool] = tool.AttributeChanged:Connect(refresh)
		end
	end
	table.insert(connections, character:GetAttributeChangedSignal(ActiveEquipment.ATTRIBUTE):Connect(refresh))
	table.insert(connections, character.ChildAdded:Connect(function(child)
		watch(child)
		refresh()
	end))
	table.insert(connections, character.ChildRemoved:Connect(function(child)
		if toolConnections[child] then
			toolConnections[child]:Disconnect()
			toolConnections[child] = nil
		end
		refresh()
	end))
	for _, child in ipairs(character:GetChildren()) do watch(child) end
	refresh()
	return function()
		alive = false
		for _, connection in ipairs(connections) do connection:Disconnect() end
		for _, connection in pairs(toolConnections) do connection:Disconnect() end
	end
end

return ActiveEquipment
