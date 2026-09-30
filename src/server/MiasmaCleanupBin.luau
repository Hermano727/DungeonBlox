local CleanupBin = {}
CleanupBin.__index = CleanupBin

function CleanupBin.new()
	return setmetatable({ _items = {}, _destroyed = false }, CleanupBin)
end

function CleanupBin:Add(item)
	if item == nil then return item end
	if self._destroyed then
		if typeof(item) == "RBXScriptConnection" then item:Disconnect()
		elseif typeof(item) == "Instance" then item:Destroy()
		elseif type(item) == "function" then item() end
		return item
	end
	table.insert(self._items, item)
	return item
end

function CleanupBin:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	for i = #self._items, 1, -1 do
		local item = self._items[i]
		local kind = typeof(item)
		if kind == "RBXScriptConnection" then pcall(function() item:Disconnect() end)
		elseif kind == "Instance" then pcall(function() item:Destroy() end)
		elseif type(item) == "function" then pcall(item)
		elseif type(item) == "table" and type(item.Destroy) == "function" then pcall(function() item:Destroy() end) end
	end
	table.clear(self._items)
end

return CleanupBin
