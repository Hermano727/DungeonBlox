--[[
	StatusCleanse  (server)

	The ONE place that wipes every debuff and lingering effect off a player. Called when:
	  * they die                                  (DeathLootService, reason "Death")
	  * they leave a dungeon realm by any path    (DungeonInstanceService, "DungeonLeft")
	  * a dungeon instance ends, cleared/failed   (DungeonInstanceService, "DungeonEnded")
	  * the F8 dev Cleanse button                 (ProfileBootstrap, "Dev")

	Adding a new debuff / effect:
	  1. Server state: register a handler here (StatusCleanse.Register) that clears it, or add
	     it to BUILT_IN below. Handlers run protected, so one failing never skips the rest.
	  2. Client visuals: drive them from REPLICATED STATE (an attribute) wherever possible,
	     so clearing the state clears the visual on its own. Anything purely client-side
	     (a screen tint, an open UI) registers with the client twin, StatusCleanseClient,
	     which runs on the StatusCleansed remote fired from All() below.
	The old way (a one-shot "PoisonChanged" event as the only thing driving the purple
	screen tint) is exactly what left the tint up after a dungeon ended.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteUtils = require(ReplicatedStorage:WaitForChild("RemoteUtils"))

local gameEvents = RemoteUtils.EnsureFolder(ReplicatedStorage, "GameEvents")
local cleansedEvent = RemoteUtils.EnsureRemoteEvent(gameEvents, "StatusCleansed")

local StatusCleanse = {}

local handlers = {} -- ordered { { name, fn(player, character, reason) } }

local function lazy(name)
	local module = ServerScriptService:FindFirstChild(name) or ServerScriptService:WaitForChild(name, 2)
	return module and require(module)
end

-- fn(player, character, reason). character may be nil (between lives).
function StatusCleanse.Register(name, fn)
	for _, entry in ipairs(handlers) do
		if entry.name == name then entry.fn = fn; return end
	end
	table.insert(handlers, { name = name, fn = fn })
end

-- Wipes everything off `player` and tells their client to drop its local effects.
function StatusCleanse.All(player, reason)
	if not player or not player.Parent then return end
	reason = reason or "Cleanse"
	local character = player.Character
	for _, entry in ipairs(handlers) do
		local ok, err = pcall(entry.fn, player, character, reason)
		if not ok then warn(("[StatusCleanse] %s failed for %s: %s"):format(entry.name, player.Name, tostring(err))) end
	end
	cleansedEvent:FireClient(player, { reason = reason })
end

------------------------------------------------------------------------
-- Built-in handlers
------------------------------------------------------------------------

-- Miasma poison: the encounter's own record first (so its ticks stop), then the attribute
-- regardless (outside an encounter, or after the encounter was already torn down).
StatusCleanse.Register("MiasmaPoison", function(player)
	local encounters = lazy("MiasmaEncounterService")
	if encounters and encounters.Cleanse then encounters.Cleanse(player) end
	player:SetAttribute("MiasmaPoisonStacks", nil)
end)

-- Encounter-owned flags on the player (presentation immunity, the stagger meter).
StatusCleanse.Register("EncounterFlags", function(player)
	player:SetAttribute("MiasmaInvulnerable", nil)
	player:SetAttribute("BossStaggerVisible", nil)
	player:SetAttribute("BossStagger", nil)
	player:SetAttribute("BossStaggerState", nil)
end)

-- Enchant statuses (slow / blind / bleed) on the current body.
StatusCleanse.Register("EnchantStatus", function(_, character)
	if not character then return end
	local status = lazy("CombatEnchantStatus")
	if status and status.Clear then status.Clear(character) end
end)

return StatusCleanse
