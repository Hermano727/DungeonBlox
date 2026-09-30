--[[
	AppearanceOptions -- ReplicatedStorage/Assets/Appearance

	Everything the wardrobe can change, as data. The server validates against it
	(AppearanceService), the wardrobe menu draws from it (Wardrobe), and both apply it
	through RS/AppearanceApply, so preview and real character can never disagree.

	A saved appearance is one flat table keyed by category Id:
		{ Skin = 0.3, Hair = "None", FacialHair = "None", Eyes = "Default", Nose = "Default", Mouth = "Default" }

	Focus (per category): the wardrobe camera shot while that tab is open, "Body" | "Face" | "Hair"
	(WardrobeStage SHOTS).

	Category kinds:
		Slider   a number 0..1 along a curated ramp (Skin: SkinRamp below). Continuous, so
		         there is no list of variants; the colour is computed from the number.
		List     pick one of Options by Id. Each option: Id (saved, never rename), Name, and its
		         asset: Decal = the image id for a face feature (drawn on the FacePlate, see
		         src/client/FacePlates; "" = nothing drawn yet), a model name for hair later.
		         Eyes options may also carry IrisDecal: a white iris on its own layer, tinted
		         by EyeColor (then Decal is the eye drawn with an iris-shaped hole). Without it,
		         the iris colour baked into Decal is what shows and the colour slider does nothing.
		         Face art sources: assets/models/main character/face/features/<Feature>_<Name>.png

	Adding a hair style = one entry in Hair.Options (+ its asset). Nothing else changes.
]]

local AppearanceOptions = {}

-- The skin tone ramp, pale to deep. The number a player saves is a position along it.
-- 0.30 is the base model's own painted tone (the skin-mask texture's default).
AppearanceOptions.SkinRamp = {
	{ 0.00, Color3.fromRGB(242, 214, 196) },
	{ 0.16, Color3.fromRGB(222, 182, 160) },
	{ 0.30, Color3.fromRGB(190, 143, 130) },
	{ 0.46, Color3.fromRGB(168, 120, 90) },
	{ 0.62, Color3.fromRGB(140, 96, 66) },
	{ 0.78, Color3.fromRGB(106, 70, 48) },
	{ 1.00, Color3.fromRGB(64, 42, 32) },
}

-- Quick-pick chips shown under the slider (positions on the ramp).
AppearanceOptions.SkinPresets = { 0.0, 0.16, 0.30, 0.46, 0.62, 0.78, 1.0 }

-- Eye colour, dark brown to pale ice. Tints the iris layer (Eyes option IrisDecal, a white
-- iris drawn on its own) through Decal.Color3, so any colour costs no extra image.
-- 0.15 is the brown baked into the first eye images.
AppearanceOptions.EyeRamp = {
	{ 0.00, Color3.fromRGB(58, 36, 24) },
	{ 0.15, Color3.fromRGB(104, 66, 40) },
	{ 0.30, Color3.fromRGB(168, 112, 44) },
	{ 0.45, Color3.fromRGB(128, 116, 58) },
	{ 0.60, Color3.fromRGB(70, 118, 72) },
	{ 0.75, Color3.fromRGB(122, 134, 146) },
	{ 0.88, Color3.fromRGB(66, 116, 176) },
	{ 1.00, Color3.fromRGB(160, 200, 228) },
}
AppearanceOptions.EyePresets = { 0.0, 0.15, 0.30, 0.45, 0.60, 0.75, 0.88, 1.0 }

-- Hair colour, black to white. Sets the hair mesh's own Color (no texture), so it is free.
AppearanceOptions.HairRamp = {
	{ 0.00, Color3.fromRGB(20, 17, 15) },
	{ 0.15, Color3.fromRGB(48, 32, 22) },
	{ 0.30, Color3.fromRGB(88, 56, 34) },
	{ 0.45, Color3.fromRGB(118, 52, 30) },
	{ 0.58, Color3.fromRGB(164, 84, 40) },
	{ 0.72, Color3.fromRGB(168, 138, 90) },
	{ 0.84, Color3.fromRGB(212, 184, 128) },
	{ 0.93, Color3.fromRGB(132, 130, 126) },
	{ 1.00, Color3.fromRGB(218, 216, 210) },
}
AppearanceOptions.HairPresets = { 0.0, 0.15, 0.30, 0.45, 0.58, 0.72, 0.84, 1.0 }

AppearanceOptions.Categories = {
	{
		Id = "Skin", Name = "Skin", Focus = "Body", Kind = "Slider", Default = 0.30,
		Subtitle = "Skin tone", ValueLabel = "TONE",
		Ramp = AppearanceOptions.SkinRamp, Presets = AppearanceOptions.SkinPresets,
	},
	{
		Id = "Hair", Name = "Hair", Focus = "Hair", Kind = "List", Default = "None",
		Subtitle = "Hair style", Slider = "HairColor", -- the colour slider sits under these cards
		Options = {
			{ Id = "None", Name = "Shaved" },
			-- Model = MeshPart template in ReplicatedFirst.CharacterParts; Offset = its centre from the
			-- body mesh centre (hair_layout.json, assets/models/main character/hair/).
			{ Id = "Buzzed", Name = "Buzzed", Model = "Hair_Buzzed", Offset = Vector3.new(0.0121, 2.2580, 0.0709) },
			{ Id = "Cropped", Name = "Cropped", Model = "Hair_Cropped", Offset = Vector3.new(0.0125, 2.2647, 0.0586) },
			{ Id = "Topknot", Name = "Top-knot", Model = "Hair_Topknot", Offset = Vector3.new(0.0120, 2.3208, 0.0774) },
		},
	},
	{
		-- No tab of its own: drawn under the Hair cards (Hair.Slider). Colours the hair mesh.
		Id = "HairColor", Name = "Hair Color", Focus = "Hair", Kind = "Slider", Default = 0.15, Hidden = true,
		Subtitle = "Hair color", ValueLabel = "COLOR",
		Ramp = AppearanceOptions.HairRamp, Presets = AppearanceOptions.HairPresets,
	},
	{
		Id = "FacialHair", Name = "Facial Hair", Focus = "Face", Kind = "List", Default = "None",
		Subtitle = "Facial hair",
		Options = {
			{ Id = "None", Name = "Clean Shaven" },
		},
	},
	{
		Id = "Eyes", Name = "Eyes", Focus = "Face", Kind = "List", Default = "Default",
		Subtitle = "Eyes", Slider = "EyeColor", -- the colour slider sits under these cards
		Options = {
			{ Id = "Default", Name = "Steady", Decal = "rbxassetid://73944812228809", IrisDecal = "rbxassetid://82013356973561" }, -- Eyes_Steady(_Iris).png
			{ Id = "Fierce", Name = "Fierce", Decal = "rbxassetid://131553610115308", IrisDecal = "rbxassetid://87336450380888" }, -- Eyes_Fierce(_Iris).png
			{ Id = "Weary", Name = "Weary", Decal = "rbxassetid://133565689313982", IrisDecal = "rbxassetid://123360964335298" }, -- Eyes_Weary(_Iris).png
		},
	},
	{
		-- No tab of its own: drawn under the Eyes cards (Eyes.Slider).
		Id = "EyeColor", Name = "Eye Color", Focus = "Face", Kind = "Slider", Default = 0.15, Hidden = true,
		Subtitle = "Eye color", ValueLabel = "COLOR",
		Ramp = AppearanceOptions.EyeRamp, Presets = AppearanceOptions.EyePresets,
	},
	{
		Id = "Nose", Name = "Nose", Focus = "Face", Kind = "List", Default = "Default",
		Subtitle = "Nose",
		Options = {
			{ Id = "Default", Name = "Straight", Decal = "rbxassetid://122108231157276" }, -- Nose_Straight.png
			{ Id = "Broad", Name = "Broad", Decal = "rbxassetid://136497895966701" },      -- Nose_Broad.png
			{ Id = "Crooked", Name = "Crooked", Decal = "rbxassetid://139548807532734" },  -- Nose_Crooked.png
		},
	},
	{
		Id = "Mouth", Name = "Mouth", Focus = "Face", Kind = "List", Default = "Default",
		Subtitle = "Mouth",
		Options = {
			{ Id = "Default", Name = "Set", Decal = "rbxassetid://137651620687841" },  -- Mouth_Set.png
			{ Id = "Grim", Name = "Grim", Decal = "rbxassetid://138007836399677" },    -- Mouth_Grim.png
			{ Id = "Smirk", Name = "Smirk", Decal = "rbxassetid://88298316665348" },  -- Mouth_Smirk.png
		},
	},
}

-- The categories drawn on the face plate, bottom layer first.
AppearanceOptions.FaceLayers = { "Nose", "Mouth", "Eyes" }

local byId = {}
for _, category in ipairs(AppearanceOptions.Categories) do byId[category.Id] = category end

function AppearanceOptions.GetCategory(id)
	return byId[id]
end

function AppearanceOptions.GetOption(categoryId, optionId)
	local category = byId[categoryId]
	if not category or category.Kind ~= "List" then return nil end
	for _, option in ipairs(category.Options) do
		if option.Id == optionId then return option end
	end
	return nil
end

-- Colour at position t (0..1) along a Slider category's Ramp.
function AppearanceOptions.RampColor(categoryId, t)
	local category = byId[categoryId]
	local ramp = category and category.Ramp or AppearanceOptions.SkinRamp
	t = math.clamp(tonumber(t) or (category and category.Default) or 0, 0, 1)
	for i = 2, #ramp do
		local a, b = ramp[i - 1], ramp[i]
		if t <= b[1] then
			return a[2]:Lerp(b[2], (t - a[1]) / math.max(b[1] - a[1], 1e-6))
		end
	end
	return ramp[#ramp][2]
end

-- A ColorSequence of the whole ramp (the slider's track).
function AppearanceOptions.RampSequence(categoryId)
	local category = byId[categoryId]
	local keys = {}
	for _, k in ipairs(category and category.Ramp or AppearanceOptions.SkinRamp) do
		table.insert(keys, ColorSequenceKeypoint.new(k[1], k[2]))
	end
	return ColorSequence.new(keys)
end

function AppearanceOptions.SkinColor(t)
	return AppearanceOptions.RampColor("Skin", t)
end

function AppearanceOptions.Default()
	local out = {}
	for _, category in ipairs(AppearanceOptions.Categories) do out[category.Id] = category.Default end
	return out
end

-- Any table in, a valid appearance out: unknown keys dropped, bad values reset to defaults.
-- The server runs every save through this; never trust the client's table.
function AppearanceOptions.Sanitize(input)
	local out = AppearanceOptions.Default()
	if type(input) ~= "table" then return out end
	for _, category in ipairs(AppearanceOptions.Categories) do
		local value = input[category.Id]
		if category.Kind == "Slider" then
			local n = tonumber(value)
			if n and n == n then out[category.Id] = math.floor(math.clamp(n, 0, 1) * 1000 + .5) / 1000 end
		elseif type(value) == "string" and AppearanceOptions.GetOption(category.Id, value) then
			out[category.Id] = value
		end
	end
	return out
end

return AppearanceOptions
