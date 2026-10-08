-- One server-authored action deadline, shared by input and authoritative action handlers.
local PotionAction = { ATTRIBUTE = "PotionDrinkingUntil" }

function PotionAction.IsLocked(character)
	return character ~= nil and (character:GetAttribute(PotionAction.ATTRIBUTE) or 0) > workspace:GetServerTimeNow()
end

-- The next drink may start at this server time: PotionDrinkConfig.DRINK_COOLDOWN after the last
-- one started. Longer than the animation lock, so spamming the key flows one drink into the next
-- instead of chaining them back to back (and movement isn't slowed for the extra time).
PotionAction.READY_ATTRIBUTE = "PotionReadyAt"

function PotionAction.IsCoolingDown(character)
	return character ~= nil and (character:GetAttribute(PotionAction.READY_ATTRIBUTE) or 0) > workspace:GetServerTimeNow()
end

return PotionAction
