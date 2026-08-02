-- PartyConfig
-- Shared constants for the party invite / loot-buff system.

local PartyConfig = {}

PartyConfig.MAX_PARTY_SIZE = 8
PartyConfig.BOOST_PER_MEMBER = 0.05 -- +5% loot (coins) per party member (incl. self); 2+ required
PartyConfig.INVITE_TIMEOUT_SEC = 60
PartyConfig.ACTION_COOLDOWN_SEC = 0.35

return PartyConfig
