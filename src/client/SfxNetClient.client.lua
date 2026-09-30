--[[
	SfxNetClient
	Plays one-shot effect sounds the SERVER decided on.

	The server can't call SfxService itself (it's client-only, and the sound has
	to route through this player's own Effects volume group), so it fires a KEY
	from the shared SoundEffects registry through GameEvents.PlayEffectSfx and
	this resolves it. No asset id ever crosses the wire.

	Generic on purpose: any server-decided one-shot can reuse the same remote
	rather than adding another. First user is the block roll in
	DamageService.ApplyToPlayer ("BlockHit"), which needs feedback or a blocked
	hit is indistinguishable from the mob simply missing.

	(WorldLootService's older ItemPickupSfx remote does the same thing for
	pickups, bound in LootClient. Worth folding into this one eventually.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))

local gameEvents = ReplicatedStorage:WaitForChild("GameEvents", 120)
if not gameEvents then
	warn("[SfxNetClient] GameEvents missing after wait -- server-driven sfx disabled.")
	return
end

local event = gameEvents:WaitForChild("PlayEffectSfx", 120)
if not event or not event:IsA("RemoteEvent") then
	warn("[SfxNetClient] GameEvents.PlayEffectSfx missing after wait -- server-driven sfx disabled.")
	return
end

event.OnClientEvent:Connect(function(key)
	if type(key) ~= "string" or key == "" then
		return
	end
	SfxService.PlayEffect(key)
end)

print("[SfxNetClient] ready")
