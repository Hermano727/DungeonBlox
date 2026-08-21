--!strict
--  InventoryData -- shared React hook wrapping DungeonMenuNet so every inventory
--  component (InvSlots, PlayerPreview, StatsPanel, ...) reads the same live profile
--  snapshot instead of each re-deriving useState/useEffect subscription boilerplate.
local React = require(game:GetService("ReplicatedStorage").Packages.React)
local DungeonMenuNet = require(script.Parent.Parent.Parent:WaitForChild("DungeonMenuNet"))

local InventoryData = {}

function InventoryData.useSnapshot()
	local snapshot, setSnapshot = React.useState(DungeonMenuNet.getLastSnapshot())

	React.useEffect(function()
		local unsubscribe = DungeonMenuNet.addSnapshotListener(setSnapshot)
		DungeonMenuNet.start()
		if not DungeonMenuNet.getLastSnapshot() then
			DungeonMenuNet.requestSync()
		end
		return unsubscribe
	end, {})

	return snapshot
end

return InventoryData
