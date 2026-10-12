--[[
	AudioCategories -- ReplicatedStorage. THE registry of sound buckets (2026-10-11). Everything
	audio-settings-related is derived from CATEGORIES below:
	  - the Settings > Audio page (sections + sliders, in this order: SettingsClient)
	  - which volume keys may be saved and their range (SettingsRanges.volume)
	  - every slider's default (VolumeSettings)
	  - the SoundGroup each bucket plays through (SoundService.Main.<group>, created on demand)
	Same idea as Minecraft's SoundSource / Wwise and FMOD buses / Unreal Sound Classes: every sound
	belongs to exactly ONE bucket, each bucket is one volume, and a sound nobody classified falls
	into the catch-all ("Other") instead of escaping the sliders.

	ADDING A BUCKET: one entry in CATEGORIES. The page, the saving and the group follow.

	ADDING A SOUND -- how it finds its bucket (first match wins):
	  1. A SoundEffects key (SfxService.PlayEffect / SfxService.GetGroupFor):
	       KEYS[key]  ->  the first PREFIXES entry the key starts with  ->  FALLBACK (Other).
	     So "MineGlint" or "HorseSnort" bucket themselves by name; add to KEYS only for an exception.
	     In Studio the client warns once about keys that ended up in Other (Audit, run by
	     client/SoundRouter), so a forgotten sound shows up in the output instead of silently.
	  2. A Sound a script builds itself: AudioCategories.Tag(sound, "combat") (sets the
	     SoundCategory attribute and, on the client, the group). Works for server-made Sounds too:
	     the attribute replicates and client/SoundRouter puts it in the group.
	  3. A stray Sound with neither (Studio-placed, toolbox): client/SoundRouter files it by where it
	     lives (ROOT_FALLBACK: Workspace -> Ambient & World, PlayerGui -> Interface, else Other).

	Ids are persisted (saved volumes): never rename one. "movement" (player footsteps) and
	"effects" (the catch-all, shown as "Other") are older names kept for that reason.
]]

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local AudioCategories = {}

-- Ordered: this is the Audio page top to bottom. `section` starts a titled block (nil = no title);
-- `group` = SoundGroup name under SoundService.Main (master scales Main itself, music is the
-- ZoneMusic Sound, so neither has one); `default` = the slider for a brand-new player (music's
-- comes from ZoneConfig, see VolumeSettings).
AudioCategories.CATEGORIES = {
	{ id = "master",      label = "Master",           section = nil,          default = 1.0, wide = true },
	{ id = "music",       label = "Music",            section = "Environment" },
	{ id = "ambient",     label = "Ambient & World",  section = "Environment", group = "World",       default = 1.0 },
	{ id = "movement",    label = "Player Footsteps", section = "Movement",    group = "Character",   default = 0.5 },
	{ id = "mount",       label = "Mount",            section = "Movement",    group = "Mount",       default = 0.6 },
	{ id = "combat",      label = "Combat",           section = "Combat",      group = "Combat",      default = 1.0 },
	{ id = "creatures",   label = "Creatures",        section = "Combat",      group = "Creatures",   default = 1.0 },
	{ id = "professions", label = "Professions",      section = "Activities",  group = "Professions", default = 1.0 },
	{ id = "rewards",     label = "Loot & Rewards",   section = "Activities",  group = "Rewards",     default = 1.0 },
	{ id = "interface",   label = "Interface",        section = "Interface",   group = "Interface",   default = 1.0 },
	{ id = "effects",     label = "Other",            section = "Interface",   group = "Effects",     default = 1.0 },
}

-- The catch-all bucket. Its id stays "effects" (saved volumes from before the buckets existed).
AudioCategories.FALLBACK = "effects"

-- SoundEffects key -> bucket, for keys whose name doesn't say it (checked before PREFIXES).
AudioCategories.KEYS = {
	CriticalHit = "combat", HeavyWeaponSwing = "combat", WeaponHitPlayer = "combat", BlockHit = "combat",
	FireTornadoBurn = "combat", MiasmaBiteHit = "combat", ItemBreak = "combat",
	PotionCorkPop = "combat", PotionOrbAbsorb = "combat", Panting = "movement", FireTornadoWind = "creatures",
	ItemPickup = "rewards", CombatXPGain = "rewards", LevelUp = "rewards", ClearChoir = "rewards",
	BrazierRise = "rewards", EmberPour = "rewards", ScrapBurn = "rewards", JudgementTick = "rewards",
	BossEchoRoar = "rewards", MiniEchoRise = "rewards", EchoTear = "rewards", EchoShatter = "rewards",
	TabSwitch = "interface", EnchantStationEnter = "interface", EnchantStationExit = "interface",
	SpearThrow = "professions", SpearSplash = "professions", SpearHit = "professions",
	GoldenFishCaught = "professions",
}

-- Name prefix -> bucket. A new key named like its family needs no entry anywhere.
AudioCategories.PREFIXES = {
	{ "Horse", "mount" },
	{ "Mine", "professions" }, { "Fish", "professions" }, { "Cook", "professions" },
	{ "Miasma", "creatures" }, { "Poison", "creatures" }, { "Kane", "creatures" }, { "Underling", "creatures" },
	{ "Reveal", "rewards" }, { "Relic", "rewards" }, { "Mythic", "rewards" }, { "Enchant", "rewards" },
	{ "Entrance", "ambient" },
}

-- Where an unmarked, ungrouped Sound lives -> bucket (client/SoundRouter).
AudioCategories.ROOT_FALLBACK = {
	Workspace = "ambient",
	PlayerGui = "interface",
}

local byId = {}
for _, c in ipairs(AudioCategories.CATEGORIES) do byId[c.id] = c end

function AudioCategories.Get(id)
	return byId[id]
end

-- Sections in page order: { { title = "Environment", items = { <category>, ... } }, ... }
function AudioCategories.Sections()
	local sections, current = {}, nil
	for _, c in ipairs(AudioCategories.CATEGORIES) do
		if not current or current.title ~= c.section then
			current = { title = c.section, items = {} }
			table.insert(sections, current)
		end
		table.insert(current.items, c)
	end
	return sections
end

-- The bucket a SoundEffects key plays in. Always a real id (FALLBACK when nothing matched).
function AudioCategories.CategoryOf(soundKey)
	local key = tostring(soundKey)
	local explicit = AudioCategories.KEYS[key]
	if explicit then return explicit end
	for _, rule in ipairs(AudioCategories.PREFIXES) do
		if string.sub(key, 1, #rule[1]) == rule[1] then return rule[2] end
	end
	return AudioCategories.FALLBACK
end

-- The SoundGroup for a bucket (client): SoundService.Main.<group>, created if missing. Unknown
-- ids resolve to the catch-all. nil for master / music, or before Main exists.
function AudioCategories.GetGroup(id)
	local c = byId[id] or byId[AudioCategories.FALLBACK]
	local main = SoundService:FindFirstChild("Main")
	if not c.group or not main then return nil end
	local group = main:FindFirstChild(c.group)
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = c.group
		group.Volume = 1
		group.Parent = main
	end
	return group
end

-- Put a script-made Sound in a bucket. Safe on the server (the attribute replicates; the client's
-- SoundRouter applies the group) and on the client (applied at once).
function AudioCategories.Tag(sound, id)
	sound:SetAttribute("SoundCategory", id)
	if RunService:IsClient() then
		sound.SoundGroup = AudioCategories.GetGroup(id)
	end
	return sound
end

-- Studio aid: the SoundEffects keys that fell through to Other. Empty = everything is filed.
function AudioCategories.Audit(soundEffects)
	local unfiled = {}
	for key in pairs(soundEffects) do
		if AudioCategories.CategoryOf(key) == AudioCategories.FALLBACK then table.insert(unfiled, key) end
	end
	table.sort(unfiled)
	return unfiled
end

return table.freeze(AudioCategories)
