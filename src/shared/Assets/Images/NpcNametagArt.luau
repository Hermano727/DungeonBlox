--[[
	NpcNametagArt -- ReplicatedStorage/Assets/Images

	Art for the floating NPC nametags (src/client/NpcNametags): a role crest sitting on a name
	plaque, with a talk marker under it. One kit for every NPC; per NPC only the icon changes
	(chosen by NPCRegistry.Types[<NpcType>].Nametag.Icon).

	Sources: assets/UI/incoming/npc name plaques/ (trimmed, edge-bled and capped by the
	scratchpad run of tools/ui_assets/process.py; the icons were packed into one atlas, see
	ICONS). An empty Image means the tag draws a flat stand-in, so art can land piece by piece.

		PLAQUE   npc_tag_plaque.png, 1024x201. 9-sliced: the bronze end caps
		         (0..115 and 909..1024) and the top / bottom rims (40 px each) never
		         stretch, the plain middle does. Insets must be non-zero: a 0 top/bottom inset made
		         Roblox smear the rim down the middle.
		CREST    npc_tag_crest.png, 1024x1012. HOLE = the empty green disc: X/Y its centre (fractions
		         of the width / height) and D its diameter (fraction of the width).
		MARKER   npc_tag_marker.png, 761x775. Painted at its lit (in talk range) look; the
		         tag dims it in code when out of range.
		ICONS    one 1024x204 atlas of 204x204 cells, one icon per cell (each icon is masked out
		         of its source, so no cell holds a piece of its neighbour). Keys are the icon
		         names NPCRegistry's Nametag.Icon uses. Sources: Dungeoneer.png (the key) and
		         "Medieval Crafting Icons Sprite Sheet.png" (the other four, left to right).
		         New icon: add a cell to the atlas (or a separate image: Image + Offset + Size)
		         and one entry here.
]]

local ICON_ATLAS = "rbxassetid://115406498172340" -- icons atlas (1024x204), uploaded 2026-10-05

local function icon(cell)
	return { Image = ICON_ATLAS, Offset = Vector2.new(cell * 204, 0), Size = Vector2.new(204, 204) }
end

return {
	PLAQUE = {
		Image = "rbxassetid://123026922995386", -- npc_tag_plaque.png
		Width = 1024,
		Height = 201,
		SliceCenter = Rect.new(115, 40, 909, 161),
	},
	CREST = {
		Image = "rbxassetid://139812123300874", -- npc_tag_crest.png
		Aspect = 1024 / 1012,
		HOLE = { X = .5, Y = .5, D = .75 },
	},
	MARKER = {
		Image = "rbxassetid://98764973955331", -- npc_tag_marker.png
		Aspect = 761 / 775,
	},
	ICONS = {
		Dungeoneer = icon(0), -- a gold dungeon key
		AnimalTrainer = icon(1), -- an iron horseshoe
		Merchant = icon(2), -- a coin pouch
		Auctioneer = icon(3), -- a gavel and block
		Blacksmith = icon(4), -- a hammer on an anvil
	},
}
