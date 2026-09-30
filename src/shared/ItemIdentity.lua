--[[
	ItemIdentity -- ReplicatedStorage

	A durable per-item identity (`item.serial`) and birth record (`item.origin`),
	minted once and carried through every transfer.

	NOT the same thing as `item.uuid`. The uuid is the key an item sits under in
	ONE profile's `inventory` dict, and it is deliberately re-minted whenever the
	item changes hands (auction house, world loot, death bundle, player drop) --
	that is why it can't answer "where did this item come from" or "are these two
	items actually the same object". The serial can, because nothing ever
	re-mints it.

	SERIAL FORMAT -- sortable on purpose, not a GUID:

		"<10-digit zero-padded unix seconds>-<8-char server tag>-<6-hex counter>"
		e.g. "1774039112-a1b2c3d4-00003f"

	Lexicographic order equals chronological order, because decimal seconds stay
	exactly 10 digits until the year 2286. That is the whole point: creation time
	lives INSIDE the item, so "remove everything minted between t0 and t1"
	is a predicate you can run per profile, with no cross-player ledger. A GUID
	would force a ledger for that same operation. (Do not "simplify" this to
	base36 -- base36 seconds roll from 6 to 7 characters in 2038 and silently
	break the ordering.)

	Uniqueness: the counter guarantees it within a server, the JobId-derived tag
	across servers. No DataStore round-trip, no RNG.

	Ordering caveat: the timestamp is the SERVER's clock, which drifts a second
	or two between Roblox servers. Treat it as a seconds-resolution bucket, not a
	strict global happens-before.

	STACKABLES GET NEITHER. A per-unit identity is meaningless for something that
	merges into an existing pile by count. This is load-bearing for the audit in
	ProfileTypes.AuditItemIdentity: without it, every stack merge would look like
	a dropped serial.

	SECURITY: this is a ReplicatedStorage module, so the client holds its own
	copy with its own counter. Harmless (the client cannot write a profile), but
	never accept a client-supplied `serial` or `origin` on any remote -- always
	mint server-side.
]]

local ItemIdentity = {}

----------------------------------------------------------------------
-- Source kinds
----------------------------------------------------------------------

-- Where an item came into existence. Always stored, so every item can answer
-- "who made me and why" even when no other system remembers.
ItemIdentity.SOURCE = table.freeze({
	MOB_DROP       = "mob_drop",
	NAMED_ELITE    = "named_elite",
	DUNGEON_BOSS   = "dungeon_boss",
	DUNGEON_REWARD = "dungeon_reward",
	SHOP_PURCHASE  = "shop_purchase",
	QUEST          = "quest",
	GATHER         = "gather",       -- mining / fishing
	CRAFT          = "craft",
	BANK           = "bank",
	STARTER_SEED   = "starter_seed",
	IMPORT         = "import",
	DEV_TOOL       = "dev_tool",
	MIGRATION      = "migration",    -- backfilled, real origin unknown
	UNKNOWN        = "unknown",      -- a mint path that hasn't been threaded yet
})

local VALID_KIND = {}
for _, kind in pairs(ItemIdentity.SOURCE) do
	VALID_KIND[kind] = true
end

local MAX_SRC_LEN = 32 -- keeps a bad MobID from bloating every saved profile

----------------------------------------------------------------------
-- Serial minting
----------------------------------------------------------------------

local LEGACY_TIME_PREFIX = "0000000000"

local counter = 0

local serverTag do
	-- Studio has no JobId. Tagging dev-minted items explicitly matters: all of
	-- today's save data was created in Studio, and being able to filter it out
	-- of any later analysis by substring is worth the eight characters.
	local jobId = tostring(game.JobId or ""):gsub("%-", "")
	if jobId == "" then
		serverTag = "studio00"
	else
		serverTag = string.sub(jobId .. "00000000", 1, 8)
	end
end

local function nextCounter()
	counter = (counter + 1) % 0x1000000 -- wraps at 6 hex digits; the timestamp disambiguates
	return counter
end

function ItemIdentity.NewSerial()
	return string.format("%010d-%s-%06x", os.time(), serverTag, nextCounter())
end

-- For items that existed before this system did. The time prefix is forced to
-- zero so they sort to the front of any chronological scan, stay trivially
-- greppable, and agree with the `origin.t = 0` those items also get.
function ItemIdentity.NewLegacySerial()
	return string.format("%s-%s-%06x", LEGACY_TIME_PREFIX, serverTag, nextCounter())
end

-- Shape check only -- says nothing about whether the serial was legitimately minted.
function ItemIdentity.IsSerial(value)
	if type(value) ~= "string" then
		return false
	end
	return string.match(value, "^%d%d%d%d%d%d%d%d%d%d%-%w%w%w%w%w%w%w%w%-%x%x%x%x%x%x$") ~= nil
end

-- Returns nil for anything that isn't a well-formed serial.
function ItemIdentity.DecodeSerial(serial)
	if not ItemIdentity.IsSerial(serial) then
		return nil
	end
	local seconds, tag, seq = string.match(serial, "^(%d+)%-(%w+)%-(%x+)$")
	return {
		createdAt = tonumber(seconds) or 0,
		server    = tag,
		seq       = tonumber(seq, 16) or 0,
	}
end

----------------------------------------------------------------------
-- Origin
----------------------------------------------------------------------

local warnedKinds = {}

--[[
	ctx = {
		by   = Player | number | nil,  -- who it was minted FOR; nil -> 0 (system)
		kind = ItemIdentity.SOURCE.*,  -- nil -> UNKNOWN, warns once per kind
		src  = string?,                -- MobID / npcId / questId / itemId
		def  = string?,                -- authored-def key (NamedEliteLootDefs pool
		                               --   entry Key, or a mythicKey). Required for
		                               --   named_elite/mythic gear: ItemStatRanges
		                               --   needs it to find the authored substat
		                               --   window instead of the generic one.
	}
]]
function ItemIdentity.NewOrigin(ctx)
	ctx = ctx or {}

	local by = ctx.by
	if typeof(by) == "Instance" and by:IsA("Player") then
		by = by.UserId
	end
	by = tonumber(by) or 0

	local kind = ctx.kind
	if type(kind) ~= "string" or not VALID_KIND[kind] then
		kind = ItemIdentity.SOURCE.UNKNOWN
	end
	if kind == ItemIdentity.SOURCE.UNKNOWN and not warnedKinds[kind] then
		warnedKinds[kind] = true
		warn("[ItemIdentity] minting with kind='unknown' -- a grant path still needs its originCtx threaded through")
	end

	local origin = {
		t = os.time(),
		by = by,
		k = kind,
		p = game.PlaceId,
	}
	if type(ctx.src) == "string" and ctx.src ~= "" then
		origin.s = string.sub(ctx.src, 1, MAX_SRC_LEN)
	end
	if type(ctx.def) == "string" and ctx.def ~= "" then
		origin.d = string.sub(ctx.def, 1, MAX_SRC_LEN)
	end
	return origin
end

----------------------------------------------------------------------
-- The mint chokepoint
----------------------------------------------------------------------

-- Takes origin.t from the serial that was just minted rather than from a second
-- os.time() call. The two are otherwise a second apart whenever the pair of calls
-- straddles a second boundary, which would trip AuditItemIdentity's
-- "origin.t disagrees with serial" check on a legitimately-minted item.
local function syncOriginTime(record)
	local decoded = ItemIdentity.DecodeSerial(record.serial)
	if decoded and type(record.origin) == "table" then
		record.origin.t = decoded.createdAt
	end
end

function ItemIdentity.HasSerial(record)
	return type(record) == "table" and ItemIdentity.IsSerial(record.serial)
end

-- Stamps a serial + origin, unless the record already carries a valid serial.
-- Every path that brings a NEW non-stackable item into existence goes through
-- here; nothing else may write `serial`.
function ItemIdentity.Stamp(record, ctx)
	if type(record) ~= "table" then
		return record
	end
	if ItemIdentity.IsSerial(record.serial) then
		return record
	end
	record.serial = ItemIdentity.NewSerial()
	record.origin = ItemIdentity.NewOrigin(ctx)
	syncOriginTime(record)
	return record
end

-- Forces a fresh identity even over an existing one. For paths that build a
-- genuinely NEW object out of an existing one (splitting a stack into separate
-- non-stackable units, for instance) -- NOT for transfers, which must preserve
-- the serial. There is no such path today; this exists so that when one is
-- written, the correct call is obvious.
function ItemIdentity.Remint(record, ctx)
	if type(record) ~= "table" then
		return record
	end
	record.serial = ItemIdentity.NewSerial()
	record.origin = ItemIdentity.NewOrigin(ctx)
	syncOriginTime(record)
	return record
end

-- Transfer helper: moves identity from `src` onto `dst`. Returns false when
-- `src` had none, so the caller can decide whether to Stamp or warn.
--
-- `origin` is SHALLOW-COPIED rather than aliased on purpose. ProfileService's
-- GrantItem already shares `template.subStats` and `template.tags` by reference
-- across all N granted units, which is a live bug (enchanting one unit mutates
-- the others); do not add a third aliased field to that pile.
function ItemIdentity.CarryForward(dst, src)
	if type(dst) ~= "table" or not ItemIdentity.HasSerial(src) then
		return false
	end
	dst.serial = src.serial
	if type(src.origin) == "table" then
		dst.origin = table.clone(src.origin)
	end
	return true
end

-- A copy of `record` with `origin` removed, for the client wire.
--
-- MUST return a copy. The profile snapshot path (ProfileService.BuildSnapshotPayload)
-- only shallow-clones the profile, so `profileWire.inventory` IS the live
-- `profile.inventory` and every item table inside it is shared. Nilling a field
-- on one of those in place would destroy provenance on the server's own profile,
-- silently and permanently.
function ItemIdentity.StripForWire(record)
	if type(record) ~= "table" then
		return record
	end
	local copy = table.clone(record)
	copy.origin = nil
	return copy
end

return ItemIdentity
