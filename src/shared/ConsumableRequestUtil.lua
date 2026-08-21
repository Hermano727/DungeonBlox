--!strict
--[[
	ConsumableRequestUtil
	Shared plumbing for server-authoritative "consume this inventory item" request handlers
	(FoodService's EatFoodRequest, PotionService's DrinkPotionRequest). Both services followed
	the exact same shape -- ensure a RemoteEvent under ReplicatedStorage.GameEvents, require the
	item to be sitting in one of the player's 9 hotbar slots before honoring the request, and
	throttle how often one player can fire the request -- so that shape now lives in one place
	instead of being hand-copied (previously verbatim, drift-prone) across both scripts.

	Deliberately NOT folded in here: anything that reads DungeonProfileService or
	ItemDefinitions, since the two services diverge there (potions use a per-tier charge pool,
	food applies hunger + BuffService buffs). This module only owns the remote-wiring/hotbar/
	throttle boilerplate that was byte-for-byte identical between them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConsumableRequestUtil = {}

-- Same recover-from-wrong-class pattern already used throughout src/server for GameEvents/
-- remote setup: destroy and recreate if something else parented a non-Folder instance under
-- this name (e.g. a stale Studio edit), rather than erroring on FindFirstChild returning the
-- wrong ClassName.
function ConsumableRequestUtil.EnsureGameEventsFolder(): Folder
	local f = ReplicatedStorage:FindFirstChild("GameEvents")
	if f and f:IsA("Folder") then
		return f
	end
	if f then
		f:Destroy()
	end
	f = Instance.new("Folder")
	f.Name = "GameEvents"
	f.Parent = ReplicatedStorage
	return f
end

function ConsumableRequestUtil.EnsureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local ev = parent:FindFirstChild(name)
	if ev and not ev:IsA("RemoteEvent") then
		ev:Destroy()
		ev = nil
	end
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = parent
	end
	return ev :: RemoteEvent
end

function ConsumableRequestUtil.EnsureRemoteFunction(parent: Instance, name: string): RemoteFunction
	local rf = parent:FindFirstChild(name)
	if rf and not rf:IsA("RemoteFunction") then
		rf:Destroy()
		rf = nil
	end
	if not rf then
		rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = parent
	end
	return rf :: RemoteFunction
end

-- Hotbar is always exactly 9 slots (see DungeonEquippedHotbar) -- the item must be sitting in
-- one of them for a right-click eat/drink to be honored, i.e. the player actually had it
-- equipped/selected client-side rather than it merely existing somewhere in the bag.
local HOTBAR_SLOTS = 9

function ConsumableRequestUtil.FindHotbarSlotForUuid(profile: any, uuid: string): number?
	if type(profile) ~= "table" or type(profile.hotbar) ~= "table" then
		return nil
	end
	for i = 1, HOTBAR_SLOTS do
		if profile.hotbar[i] == uuid then
			return i
		end
	end
	return nil
end

-- Simple per-player minimum-interval throttle, e.g. "even an instant-feeling eat/drink
-- shouldn't be spammable faster than N seconds". One RateLimiter instance covers one request
-- type; call :Check(userId) each time the remote fires -- it both reports whether this call is
-- allowed AND (if allowed) stamps the new last-fired time, so callers don't separately manage
-- a timestamp table the way FoodService/PotionService each used to.
export type RateLimiter = {
	Check: (self: RateLimiter, userId: number) -> boolean,
	Clear: (self: RateLimiter, userId: number) -> (),
}

function ConsumableRequestUtil.NewRateLimiter(minIntervalSeconds: number): RateLimiter
	local lastByUid: { [number]: number } = {}
	local limiter = {} :: RateLimiter

	function limiter:Check(userId: number): boolean
		local now = os.clock()
		if (lastByUid[userId] or 0) + minIntervalSeconds > now then
			return false
		end
		lastByUid[userId] = now
		return true
	end

	function limiter:Clear(userId: number)
		lastByUid[userId] = nil
	end

	return limiter
end

return ConsumableRequestUtil
