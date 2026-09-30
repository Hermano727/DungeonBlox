--[[
	TitleCards -- ReplicatedStorage/Assets/Images

	Boss intro title-card art, keyed by MobID. Shown by the boss's drop cutscene
	(MiasmaDropCutscene) right after its roar, for BossDropSequence.Cutscene.TitleCardSeconds.

		Layers    LAYERED card (preferred): separate transparent PNGs the cutscene animates on
		          their own -- the creature slides in, the title slams, they creep apart.
		            Creature  square PNG, the boss render (anchored bottom-right of the card)
		            Title     2:1 PNG, the name + epithet lettering (anchored left)
		            Backdrop  optional 2:1 PNG behind both ("" = just the in-engine band)
		          Source: assets/ui/title_cards/<boss>/ (Blender file + renders).
		Image     single flat card art (2:1) -- the older form, used when Layers has no Creature.
		          A card exists when either is set; with neither, the cutscene skips it and the
		          fight starts that much sooner (the server reads this too).
		DrawText  true = the game draws the boss's Name and Title (MobData) over the art, for art
		          generated WITHOUT lettering. false when the lettering is baked into the image.
		Sound     optional one-shot played as the card slams in ("" = silent).
		SfxKey    optional SoundEffects registry key played with it (e.g. the boss's own roar).
]]

local TitleCards = {
	-- v2 (2026-09-27): a real Blender render of the roar pose, layered. Sources + renders in
	-- assets/ui/title_cards/miasma/ (Miasma_TitleCard_v01.blend: Scene = creature, TitleScene
	-- = lettering). Re-render there and re-upload to change it.
	MiasmaBoss = {
		Layers = {
			Creature = "rbxassetid://107643250134779", -- Miasma_Card_Creature.png
			Title = "rbxassetid://112639380868531",    -- Miasma_Card_Title.png
			Backdrop = "rbxassetid://107939396064121", -- Miasma_Card_Backdrop.png (sewer wall + purple edges)
		},
		-- v1 flat art (AI-generated, "MIASMA / THE SCOURGE" baked in) -- the fallback.
		Image = "rbxassetid://90301044653424",
		DrawText = false,
		Sound = "rbxassetid://88314430562744",
		SfxKey = "MiasmaRoar", -- the roar again, over the card
	},
}

local NONE = { Image = "", DrawText = false, Sound = "", Layers = {} }

-- Always returns a table, so callers never branch on nil.
function TitleCards.Get(mobId)
	local row = type(mobId) == "string" and TitleCards[mobId]
	if type(row) ~= "table" or type(row.Image) ~= "string" then return NONE end
	return row
end

-- True when this card uses the layered form (a Creature layer is set).
function TitleCards.IsLayered(mobId)
	local layers = TitleCards.Get(mobId).Layers
	return type(layers) == "table" and type(layers.Creature) == "string" and layers.Creature ~= ""
end

function TitleCards.Has(mobId)
	return TitleCards.IsLayered(mobId) or TitleCards.Get(mobId).Image ~= ""
end

return TitleCards
