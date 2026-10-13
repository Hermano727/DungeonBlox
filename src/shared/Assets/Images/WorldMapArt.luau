--[[
	WorldMapArt -- ReplicatedStorage/Assets/Images

	The painted world map: real top-down captures of the T1 region, stitched and cut into
	1024 px tiles (assets/ui/world_map/, README there). Drawn by client/Minimap (MapView) under
	the fog of war, so the map shows the real world instead of one colour per 4-stud cell.

		Regions[name].Tiles    the ground, covering Bounds completely
		Regions[name].Landmark images drawn ON TOP of the ground: big things seen from above
		                       (the T1 world tree's canopy). Faded as you zoom in, so the ground
		                       under it can still be read (MapView.SetWorldArt, landmark fade).
		Each image: { Image, X, Z, W, H } in studs (X/Z = its north-west corner, +X east, +Z south).

	Captured 2026-10-11 at 2.22 px per stud: FOV 12 from 1715 studs up, Atmosphere off, ClockTime 13,
	nametags hidden. Recapture after big builds (README); the server's per-cell colours
	(MinimapService) still cover any ground outside these regions.
]]

return {
	Regions = {
		T1 = {
			Bounds = { X0 = -3200, Z0 = -1060, X1 = -1080, Z1 = 1110 },
			PxPerStud = 2.22,
			Tiles = {
				{ Image = "rbxassetid://101695355467947", X = -3200.00, Z = -1060.00, W = 461.26, H = 461.26 }, -- T1_WorldMap_0_0.png
				{ Image = "rbxassetid://87580432100683", X = -2738.74, Z = -1060.00, W = 461.26, H = 461.26 }, -- T1_WorldMap_0_1.png
				{ Image = "rbxassetid://92789376856618", X = -2277.48, Z = -1060.00, W = 461.26, H = 461.26 }, -- T1_WorldMap_0_2.png
				{ Image = "rbxassetid://128753690895729", X = -1816.22, Z = -1060.00, W = 461.26, H = 461.26 }, -- T1_WorldMap_0_3.png
				{ Image = "rbxassetid://92779215526215", X = -1354.95, Z = -1060.00, W = 274.77, H = 461.26 }, -- T1_WorldMap_0_4.png
				{ Image = "rbxassetid://134377046722361", X = -3200.00, Z = -598.74, W = 461.26, H = 461.26 }, -- T1_WorldMap_1_0.png
				{ Image = "rbxassetid://122926591826255", X = -2738.74, Z = -598.74, W = 461.26, H = 461.26 }, -- T1_WorldMap_1_1.png
				{ Image = "rbxassetid://73662640541640", X = -2277.48, Z = -598.74, W = 461.26, H = 461.26 }, -- T1_WorldMap_1_2.png
				{ Image = "rbxassetid://136808297042260", X = -1816.22, Z = -598.74, W = 461.26, H = 461.26 }, -- T1_WorldMap_1_3.png
				{ Image = "rbxassetid://101931864855541", X = -1354.95, Z = -598.74, W = 274.77, H = 461.26 }, -- T1_WorldMap_1_4.png
				{ Image = "rbxassetid://111177636281060", X = -3200.00, Z = -137.48, W = 461.26, H = 461.26 }, -- T1_WorldMap_2_0.png
				{ Image = "rbxassetid://89329608527222", X = -2738.74, Z = -137.48, W = 461.26, H = 461.26 }, -- T1_WorldMap_2_1.png
				{ Image = "rbxassetid://87245086784345", X = -2277.48, Z = -137.48, W = 461.26, H = 461.26 }, -- T1_WorldMap_2_2.png
				{ Image = "rbxassetid://100866001356296", X = -1816.22, Z = -137.48, W = 461.26, H = 461.26 }, -- T1_WorldMap_2_3.png
				{ Image = "rbxassetid://87818152533145", X = -1354.95, Z = -137.48, W = 274.77, H = 461.26 }, -- T1_WorldMap_2_4.png
				{ Image = "rbxassetid://105437413074360", X = -3200.00, Z = 323.78, W = 461.26, H = 461.26 }, -- T1_WorldMap_3_0.png
				{ Image = "rbxassetid://82694925490873", X = -2738.74, Z = 323.78, W = 461.26, H = 461.26 }, -- T1_WorldMap_3_1.png
				{ Image = "rbxassetid://88018407382806", X = -2277.48, Z = 323.78, W = 461.26, H = 461.26 }, -- T1_WorldMap_3_2.png
				{ Image = "rbxassetid://124206010652038", X = -1816.22, Z = 323.78, W = 461.26, H = 461.26 }, -- T1_WorldMap_3_3.png
				{ Image = "rbxassetid://113573353974341", X = -1354.95, Z = 323.78, W = 274.77, H = 461.26 }, -- T1_WorldMap_3_4.png
				{ Image = "rbxassetid://115108838696814", X = -3200.00, Z = 785.05, W = 461.26, H = 324.77 }, -- T1_WorldMap_4_0.png
				{ Image = "rbxassetid://112880220328536", X = -2738.74, Z = 785.05, W = 461.26, H = 324.77 }, -- T1_WorldMap_4_1.png
				{ Image = "rbxassetid://136979388384328", X = -2277.48, Z = 785.05, W = 461.26, H = 324.77 }, -- T1_WorldMap_4_2.png
				{ Image = "rbxassetid://126039596917740", X = -1816.22, Z = 785.05, W = 461.26, H = 324.77 }, -- T1_WorldMap_4_3.png
				{ Image = "rbxassetid://84659719364591", X = -1354.95, Z = 785.05, W = 274.77, H = 324.77 }, -- T1_WorldMap_4_4.png
			},
			Landmark = { -- the world tree's canopy (Workspace.Tree3)
				{ Image = "rbxassetid://88083617174989", X = -3176.13, Z = -976.22, W = 461.26, H = 461.26 }, -- T1_WorldTreeCanopy_0_0.png
				{ Image = "rbxassetid://133905423343801", X = -2714.86, Z = -976.22, W = 461.26, H = 461.26 }, -- T1_WorldTreeCanopy_0_1.png
				{ Image = "rbxassetid://122369516080115", X = -2253.60, Z = -976.22, W = 119.37, H = 461.26 }, -- T1_WorldTreeCanopy_0_2.png
				{ Image = "rbxassetid://107234909967389", X = -3176.13, Z = -514.95, W = 461.26, H = 440.54 }, -- T1_WorldTreeCanopy_1_0.png
				{ Image = "rbxassetid://131605475263613", X = -2714.86, Z = -514.95, W = 461.26, H = 440.54 }, -- T1_WorldTreeCanopy_1_1.png
				{ Image = "rbxassetid://129611045274625", X = -2253.60, Z = -514.95, W = 119.37, H = 440.54 }, -- T1_WorldTreeCanopy_1_2.png
			},
		},
	},
}
