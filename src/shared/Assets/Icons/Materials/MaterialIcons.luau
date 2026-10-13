--[[
    MaterialIcons
    Central registry for crafting/currency material icon asset IDs.
    Require this instead of writing rbxassetid:// literals inline.

    Keys match the corresponding itemId in ReplicatedStorage/ItemDefinitions.
]]

return {
    T1_SCRAP = "rbxassetid://140184052977855",
    T2_SCRAP = "rbxassetid://99748696862001",
    T3_SCRAP = "rbxassetid://76333609407100",
    T4_SCRAP = "rbxassetid://126747341526231",
    T5_SCRAP = "rbxassetid://94367706624740",
    -- TEMPORARY: the coin art shown next to the wallet in the merchant menu
    -- (JournalUI.fx_coinfind). Swap for dedicated sack art; every tier shares it for now.
    COIN_SACK = "rbxassetid://108170715481607",
    COIN_NOTE = "rbxassetid://108170715481607", -- TEMPORARY, same coin art as the sack
}
