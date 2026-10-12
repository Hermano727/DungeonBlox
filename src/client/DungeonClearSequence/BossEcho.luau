--[[
	BossEcho -- the opening of the clear show: the main boss's echo, right AFTER its death animation.

	The boss falls (its own defeat animation plays before the show starts), the room goes dark, its
	spectral echo rises in smoke with burning eyes and roars, and a shockwave of light tears it apart.
	That light is what the Benediction answers. The drawing is Echo (shared with the minibosses').

	Timeline (payload.echo): t0, blackoutEnd (the echo starts rising), echoEnd (torn apart), tearEnd.
	The arena's lights are handled by Ambience from the same numbers.
]]

local Echo = require(script.Parent:WaitForChild("Echo"))

local BossEcho = {}
BossEcho.__index = BossEcho

function BossEcho.new(show)
	local s = show.payload.echo
	if not s then return setmetatable({ empty = true }, BossEcho) end
	local self = setmetatable({ s = s }, BossEcho)
	self.echo = Echo.new(show, show.folder, {
		final = true, base = show:centre(0), key = "final", seed = 0,
		riseFrom = s.blackoutEnd, breakAt = s.echoEnd, breakEnd = s.tearEnd,
	})
	return self
end

function BossEcho:Update(t)
	if self.empty or self.done then return end
	if t > self.s.tearEnd + 1 then
		self.echo:Destroy()
		self.done = true
		return
	end
	self.echo:Update(t)
end

function BossEcho:Destroy()
	if self.empty or self.done then return end
	self.echo:Destroy()
end

return BossEcho
