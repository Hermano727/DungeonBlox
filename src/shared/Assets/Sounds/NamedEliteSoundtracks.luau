--[[
	NamedEliteSoundtracks -- ReplicatedStorage/Assets/Sounds

	Which looped track plays while a named elite is alive. One row per elite,
	keyed by its MobID (same key MobAnimConfig uses). A row may list several
	ids; one is picked per spawn and held for that whole fight.

	Same registry rule as the icon/mesh ones: asset ids live here, never as
	inline rbxassetid:// literals in the systems that play them.

		Kane = { "rbxassetid://102529790211447" },
		SomeFutureElite = { "rbxassetid://1", "rbxassetid://2" }, -- rolled per spawn

	It takes PRIORITY over the zone soundtrack. MobManager picks the id when
	the elite spawns and hands it to ZoneService.SetMusicOverride for whoever
	is fighting it, then clears the override the moment the elite is gone.
	Nothing here needs to know about that -- it is just the data.

	Because the track is tied to the elite being alive, and a named elite
	despawns when it kills you (see MobManager.DespawnNamedElite), the fight,
	the boss bar and the music all end together: die and you lose the kill AND
	the music stops, rather than the track looping over your corpse.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ZoneConfig = require(ReplicatedStorage:WaitForChild("ZoneConfig"))

local NamedEliteSoundtracks = {}

NamedEliteSoundtracks.Tracks = {
	Kane = { "rbxassetid://102529790211447" },
}

-- One track id for this MobID, or "" when the elite has none authored.
-- `rng` is optional (a Random) so a caller can keep picks deterministic.
function NamedEliteSoundtracks.Pick(mobId, rng)
	if type(mobId) ~= "string" then return "" end
	local row = NamedEliteSoundtracks.Tracks[mobId]
	if type(row) == "string" then
		return ZoneConfig.NormalizeMusicId(row)
	end
	if type(row) ~= "table" or #row == 0 then return "" end
	local index = 1
	if #row > 1 then
		index = rng and rng:NextInteger(1, #row) or math.random(1, #row)
	end
	-- Normalized the same way zone music is, so a bare numeric id works here
	-- too and a malformed one becomes silence instead of a broken SoundId.
	return ZoneConfig.NormalizeMusicId(row[index])
end

return NamedEliteSoundtracks
