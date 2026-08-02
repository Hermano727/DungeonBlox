local MiningExcavationConfig = {}

MiningExcavationConfig.GRID_ROWS = 6
MiningExcavationConfig.GRID_COLS = 8
MiningExcavationConfig.GRID_SIZE = MiningExcavationConfig.GRID_ROWS * MiningExcavationConfig.GRID_COLS

MiningExcavationConfig.Tiers = {
	[1] = {
		tier = 1,
		oreId = "Coal",
		grantItemId = "Coal",
		matchName = "Coal",
		displayName = "coal",
		displayNameTitle = "Coal",
		minOreTiles = 5,
		maxOreTiles = 12,
		maxDigAttempts = 12,
		tileOreAmounts = { 1 },
		xpPerUnit = 5,
		respawnSeconds = 10,
		dropChance = 1,
		iconDecalName = "CoalIconMain",
		iconImage = "rbxassetid://257670479",
		oreRevealColor = Color3.fromRGB(69,69,69),
		emptyRevealColor = Color3.fromRGB(69,69,69),
	},
}

function MiningExcavationConfig.getIconImage(tierCfg)
	if not tierCfg then
		return ""
	end
	if type(tierCfg.iconImage) == "string" and tierCfg.iconImage ~= "" then
		return tierCfg.iconImage
	end
	if tierCfg.iconDecalName then
		local Workspace = game:GetService("Workspace")
		local inst = Workspace:FindFirstChild(tierCfg.iconDecalName, true)
		if inst then
			if inst:IsA("Decal") and inst.Texture ~= "" then
				return inst.Texture
			end
			if inst:IsA("ImageLabel") and inst.Image ~= "" then
				return inst.Image
			end
		end
	end
	return ""
end

function MiningExcavationConfig.getTierConfig(tier)
	return MiningExcavationConfig.Tiers[tier]
end

function MiningExcavationConfig.getTierForOreModel(oreModel)
	if typeof(oreModel) ~= "Instance" then
		return nil, nil
	end
	local cur = oreModel
	while cur do
		for tier, cfg in pairs(MiningExcavationConfig.Tiers) do
			if cfg.matchName and string.find(cur.Name, cfg.matchName, 1, true) then
				return tier, cfg
			end
		end
		cur = cur.Parent
	end
	return nil, nil
end

function MiningExcavationConfig.rollTileOreAmount(tierCfg)
	if not tierCfg or type(tierCfg.tileOreAmounts) ~= "table" or #tierCfg.tileOreAmounts == 0 then
		return 0
	end
	local amounts = tierCfg.tileOreAmounts
	return amounts[math.random(1, #amounts)]
end

return MiningExcavationConfig
