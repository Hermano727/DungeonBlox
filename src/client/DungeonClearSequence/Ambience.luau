--[[
	Ambience -- the arena's own lights during the clear sequence (client-local only).

	Dims every Light in the boss room for the show so the braziers, relics and the Benediction
	carry the scene, goes fully dark for the main boss's echo that opens the show (the blackout), and gives the
	room its light back in the outro. Original brightness is restored on Destroy whatever happens.
]]

local Workspace = game:GetService("Workspace")

local Fx = require(script.Parent:WaitForChild("Fx"))

local DIM = 0.35        -- the show's resting level, as a fraction of each light's own brightness
local RADIUS = 170      -- lights this close to the arena centre count as the room's
local RESTORE_AFTER = 1 -- the room comes back over this long after a blackout ends

local Ambience = {}
Ambience.__index = Ambience

function Ambience.new(show)
	local self = setmetatable({ show = show, lights = {} }, Ambience)
	local centre = show:centre(0)
	local roots = {}
	local instances = Workspace:FindFirstChild("DungeonInstances")
	local realm = instances and instances:FindFirstChild(show.payload.instanceId)
	table.insert(roots, realm or Workspace)
	for _, root in ipairs(roots) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Light") and d.Enabled and not d:IsDescendantOf(show.folder) then
				local host = d.Parent
				local pos = host and (host:IsA("BasePart") and host.Position or (host:IsA("Attachment") and host.WorldPosition))
				if pos and (pos - centre).Magnitude <= RADIUS then
					table.insert(self.lights, { light = d, brightness = d.Brightness })
				end
			end
		end
	end
	-- The main boss's blackout (the echo that opens the show): dark as it rises, the light returns
	-- with the shockwave that tears it apart.
	self.blackouts = {}
	local echo = show.payload.echo
	if echo then table.insert(self.blackouts, { from = echo.t0, dark = echo.blackoutEnd, back = echo.echoEnd }) end
	return self
end

-- Level (fraction of each light's brightness) at time t.
function Ambience:level(t)
	local show = self.show
	local b = show.payload.benediction
	local level = 1 - (1 - DIM) * Fx.alpha(t, b.t0, b.descend)
	for _, w in ipairs(self.blackouts) do
		if t >= w.from then
			local into = Fx.alpha(t, w.from, w.dark)
			local outOf = Fx.alpha(t, w.back, w.back + RESTORE_AFTER)
			level = Fx.lerp(Fx.lerp(level, 0, into), level, outOf)
		end
	end
	-- Outro: the room's light returns.
	return Fx.lerp(level, 1, Fx.alpha(t, show.duration, show.duration + show.outro * 0.8))
end

function Ambience:Update(t)
	local level = self:level(t)
	if level == self.last then return end
	self.last = level
	for _, entry in ipairs(self.lights) do
		if entry.light.Parent then entry.light.Brightness = entry.brightness * level end
	end
end

function Ambience:Destroy()
	for _, entry in ipairs(self.lights) do
		if entry.light.Parent then entry.light.Brightness = entry.brightness end
	end
end

return Ambience
