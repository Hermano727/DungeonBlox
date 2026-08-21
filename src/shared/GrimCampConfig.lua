-- GrimCamp Layout Configuration
-- JSON-style mapping of all camp assets with prompts, positions, and procedural parameters
-- Aesthetic: Grim-Stylized (desaturated, weathered, ominous)

local GrimCampConfig = {
	campLayout = {
		name = "GrimCamp",
		parentPath = "Workspace.TutorialPathway.Structures",
		assets = {
			{
				id = "large_main_tent",
				instanceName = "LargeMainTent",
				prompt = "A large grim-stylized medieval A-frame campaign tent with tattered dark charcoal canvas, reinforced with rotting leather straps and rusted iron stakes. The fabric sags between weathered wooden poles, stained with soot and age. Jagged tears reveal a dark interior. Grim fantasy aesthetic, desaturated muted tones, ominous and weathered.",
				position = { x = 0, y = 0, z = -25 },
				parameters = {
					style = "grim_stylized",
					primaryColor = "#2C2C2C",
					secondaryColor = "#4A3728",
					accentColor = "#8B0000",
					material = "fabric_over_wood",
					complexity = "high",
					scale = 1.2
				}
			},
			{
				id = "small_tent_left",
				instanceName = "SmallTentLeft",
				prompt = "A small grim-stylized wedge tent pitched at an angle, with faded dark olive canvas stretched over crooked wooden poles. The fabric is patched and torn, edges frayed and trailing. Rusted iron stakes pin it to the ground. Muted, desaturated, grim fantasy aesthetic.",
				position = { x = -22, y = 0, z = -10 },
				parameters = {
					style = "grim_stylized",
					primaryColor = "#3B3B2F",
					secondaryColor = "#4A3728",
					accentColor = "#5C4033",
					material = "fabric_over_wood",
					complexity = "medium",
					scale = 0.8
				}
			},
			{
				id = "small_tent_right",
				instanceName = "SmallTentRight",
				prompt = "A small grim-stylized wedge tent, mirror of the left tent, with dark weathered canvas sagging between notched wooden poles. Stained with mud and ash, one corner collapsed slightly. Rusted stakes and frayed rope. Grim fantasy aesthetic, desaturated.",
				position = { x = 22, y = 0, z = -10 },
				parameters = {
					style = "grim_stylized",
					primaryColor = "#3B3B2F",
					secondaryColor = "#4A3728",
					accentColor = "#5C4033",
					material = "fabric_over_wood",
					complexity = "medium",
					scale = 0.8
				}
			},
			{
				id = "campfire",
				instanceName = "Campfire",
				prompt = "A grim-stylized campfire pit ringed with jagged dark stones, blackened by soot. Glowing embers and charred logs sit in the center, with faint orange-red light. Ash and cinders scattered around the ring. Ominous, desaturated, grim fantasy aesthetic.",
				position = { x = 0, y = 0, z = 0 },
				parameters = {
					style = "grim_stylized",
					primaryColor = "#1A1A1A",
					secondaryColor = "#8B2500",
					accentColor = "#FF4500",
					material = "stone_and_char",
					complexity = "medium",
					scale = 1.0
				}
			},
			{
				id = "log_bench_left",
				instanceName = "LogBenchLeft",
				prompt = "A grim-stylized rough-hewn log bench, a split timber resting on two short stumps. Bark peeling, surface scored with axe marks and stained dark with age and grime. Muted brown tones, grim fantasy aesthetic.",
				position = { x = -8, y = 0, z = 5 },
				parameters = {
					style = "grim_stylized",
					primaryColor = "#3E2723",
					secondaryColor = "#2C1B0E",
					accentColor = "#1A1A1A",
					material = "rough_wood",
					complexity = "low",
					scale = 1.0
				}
			},
			{
				id = "log_bench_right",
				instanceName = "LogBenchRight",
				prompt = "A grim-stylized rough-hewn log bench, split timber on stumps, weathered and scored with deep axe marks. Dark stained wood, peeling bark, muted and grimy. Grim fantasy aesthetic.",
				position = { x = 8, y = 0, z = 5 },
				parameters = {
					style = "grim_stylized",
					primaryColor = "#3E2723",
					secondaryColor = "#2C1B0E",
					accentColor = "#1A1A1A",
					material = "rough_wood",
					complexity = "low",
					scale = 1.0
				}
			},
			{
				id = "crate_stack",
				instanceName = "CrateStack",
				prompt = "A stack of grim-stylized wooden crates, two stacked and one tilted beside them. Boards are rough-sawn, gaps between planks, iron banding rusted. One crate lid ajar revealing dark interior. Stained, weathered, grim fantasy aesthetic.",
				position = { x = 18, y = 0, z = -20 },
				parameters = {
					style = "grim_stylized",
					primaryColor = "#5C4033",
					secondaryColor = "#3E2723",
					accentColor = "#6E6E6E",
					material = "weathered_wood_iron",
					complexity = "medium",
					scale = 1.0
				}
			},
			{
				id = "barrel_cluster",
				instanceName = "BarrelCluster",
				prompt = "A cluster of two grim-stylized wooden barrels, one upright and one on its side. Dark oak staves with rusted iron hoops, one barrel with a broken stave. Stained with dark liquid residue. Grim fantasy aesthetic, desaturated.",
				position = { x = 24, y = 0, z = -18 },
				parameters = {
					style = "grim_stylized",
					primaryColor = "#4A3728",
					secondaryColor = "#3E2723",
					accentColor = "#6E6E6E",
					material = "dark_oak_iron",
					complexity = "medium",
					scale = 1.0
				}
			},
			{
				id = "npc_table",
				instanceName = "NPCTable",
				prompt = "A grim-stylized rough wooden table on uneven legs, surface covered with a tattered map, a guttering candle in a rusted holder, and scattered bones or tokens. Wood is dark and stained, edges chipped. Grim fantasy aesthetic, ominous and weathered.",
				position = { x = -18, y = 0, z = 8 },
				parameters = {
					style = "grim_stylized",
					primaryColor = "#3E2723",
					secondaryColor = "#2C1B0E",
					accentColor = "#8B8558",
					material = "rough_wood",
					complexity = "high",
					scale = 1.0
				}
			},
			{
				id = "weapon_rack",
				instanceName = "WeaponRack",
				prompt = "A grim-stylized freestanding weapon rack of dark rough-hewn timber, holding notched swords and a spear with a tattered banner strip. Wood is scored and dark, metal rusted and pitted. Grim fantasy aesthetic, desaturated and ominous.",
				position = { x = -5, y = 0, z = -22 },
				parameters = {
					style = "grim_stylized",
					primaryColor = "#2C1B0E",
					secondaryColor = "#6E6E6E",
					accentColor = "#8B0000",
					material = "dark_wood_rusted_iron",
					complexity = "high",
					scale = 1.0
				}
			},
			{
				id = "supply_sacks",
				instanceName = "SupplySacks",
				prompt = "A pile of grim-stylized burlap supply sacks, two upright and one slumped over. Fabric is stained, torn at seams, tied with frayed rope. Contents suggest grain or provisions. Muted earth tones, grim fantasy aesthetic.",
				position = { x = 20, y = 0, z = -14 },
				parameters = {
					style = "grim_stylized",
					primaryColor = "#8B8558",
					secondaryColor = "#6B6340",
					accentColor = "#3E2723",
					material = "burlap_rope",
					complexity = "low",
					scale = 1.0
				}
			}
		}
	},

	-- Design principles for the Grim-Stylized aesthetic
	aestheticGuide = {
		name = "Grim-Stylized",
		colorPalette = {
			description = "Desaturated, muted — charcoal blacks, dark browns, rust reds, olive drabs, ash grays",
			primary = { "#2C2C2C", "#3B3B2F", "#1A1A1A" },
			secondary = { "#4A3728", "#3E2723", "#2C1B0E", "#5C4033" },
			accent = { "#8B0000", "#8B2500", "#FF4500", "#8B8558" },
			metal = { "#6E6E6E", "#8B8558" }
		},
		materials = {
			"Weathered wood",
			"Tattered fabric",
			"Rusted iron",
			"Stained burlap",
			"Soot-blackened stone"
		},
		surfaceDetail = {
			"Axe marks",
			"Tears and fraying",
			"Stains and soot",
			"Rust and pitting",
			"Nothing pristine or geometrically perfect"
		},
		lighting = "Warm but dim — firelight orange against cold dark surroundings",
		silhouettes = "Crooked, asymmetrical, sagging — nothing is pristine or geometrically perfect"
	},

	-- Campfire effects configuration
	campfireEffects = {
		pointLight = {
			color = "#FF781E",
			brightness = 2.5,
			range = 25,
			shadows = true,
			flickerAmplitude = 0.3,
			flickerInterval = 0.1
		},
		emberParticles = {
			colorStart = "#FF6400",
			colorMid = "#FFB432",
			colorEnd = "#FF3200",
			sizeStart = 0.15,
			sizeMid = 0.1, -- matches the tuned value GrimCampfireEffects already used; added here so the script has no leftover literal
			sizeEnd = 0,
			lifetime = { 1, 3 },
			rate = 30,
			speed = { 2, 5 },
			spreadAngle = 30
		},
		smokeParticles = {
			colorStart = "#3C3C3C",
			colorEnd = "#1E1E1E",
			sizeStart = 0.5,
			sizeMid = 2,
			sizeEnd = 4,
			lifetime = { 3, 6 },
			rate = 8,
			speed = { 1, 3 },
			spreadAngle = 15
		}
	},

	-- NPC dialogue configuration
	npcDialogue = {
		npcName = "Hollow Merchant",
		instanceName = "CampMerchant",
		promptAction = "Talk",
		maxActivationDistance = 10,
		dialogNodes = {
			{
				id = 1,
				text = "The fire burns low, stranger... but not as low as my spirits. What brings you to this wretched camp?",
				responses = {
					{ text = "What can you tell me about this place?", nextNode = 2 },
					{ text = "Got anything to trade?", nextNode = 3 },
					{ text = "Just passing through.", exitQuip = "May the ash guide your path..." }
				}
			},
			{
				id = 2,
				text = "This camp? A refuge for the forgotten. We scrape by on what the dead leave behind. The mountains hold worse things than us, I promise you that.",
				responses = {
					{ text = "What kind of things?", nextNode = 4 },
					{ text = "Sounds dangerous. I'll be going.", exitQuip = "Cowardice keeps you alive. Can't fault that." }
				}
			},
			{
				id = 3,
				text = "Trade? Ha! I've got rations that taste like ash and blades duller than a beggar's wit. But if you're desperate... take a look.",
				responses = {
					{ text = "Show me what you have.", exitQuip = "Take what you need. Payment? Your continued breathing is enough." },
					{ text = "Maybe another time.", exitQuip = "Suit yourself. The offer rots with everything else here." }
				}
			},
			{
				id = 4,
				text = "Shadows with teeth. Echoes that wear the faces of the dead. The mountains have a way of... changing things. Best keep your blade close and your wits closer.",
				responses = {
					{ text = "How do I survive out there?", nextNode = 5 },
					{ text = "I've heard enough.", exitQuip = "Ignorance is a kind of armor. Wear it well." }
				}
			},
			{
				id = 5,
				text = "Stay near the fire when darkness falls. The light keeps the worst of it at bay. And never... NEVER... follow the whispering.",
				responses = {
					{ text = "What whispering?", exitQuip = "You'll know when you hear it. And when you do... don't listen. Don't follow. Don't look back." },
					{ text = "I'll keep that in mind.", exitQuip = "Mmm. We'll see." }
				}
			}
		}
	}
}

-- Converts a "#RRGGBB" string (as used throughout this config's color
-- palettes) into a Color3. Scripts that consume campfireEffects/aestheticGuide
-- colors should go through this rather than hand-rolling their own
-- Color3.fromRGB(...) copies of the same numbers — see GrimCampfireEffects
-- for the worked example. Falls back to white on a malformed string so a
-- typo'd hex code never silently becomes a black/invisible effect.
function GrimCampConfig.HexToColor3(hex)
	if type(hex) ~= "string" then
		return Color3.new(1, 1, 1)
	end
	local clean = hex:gsub("^#", "")
	local r = tonumber(clean:sub(1, 2), 16)
	local g = tonumber(clean:sub(3, 4), 16)
	local b = tonumber(clean:sub(5, 6), 16)
	if not r or not g or not b then
		return Color3.new(1, 1, 1)
	end
	return Color3.fromRGB(r, g, b)
end

return GrimCampConfig