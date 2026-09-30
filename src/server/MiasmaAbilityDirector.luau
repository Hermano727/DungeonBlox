local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))

local Director = {}
Director.__index = Director

local ORDER = { "FastProjectile", "PoisonScatter", "Submerge" }

function Director.new(controller)
	return setmetatable({ Controller = controller, Running = false, Last = nil, Serial = 0 }, Director)
end

function Director:_pick()
	local candidates, total = {}, 0
	for _, name in ipairs(ORDER) do
		if name ~= self.Last and self.Controller:CanUseAbility(name) then
			local weight = Config.Abilities[name].Weight or 1
			total += weight
			table.insert(candidates, { name = name, ceiling = total })
		end
	end
	if total <= 0 then return nil end
	local roll = math.random() * total
	for _, entry in ipairs(candidates) do if roll <= entry.ceiling then return entry.name end end
	return candidates[#candidates].name
end

function Director:Start()
	if self.Running then return end
	self.Running = true
	self.Serial += 1
	local serial = self.Serial
	task.spawn(function()
		while self.Running and serial == self.Serial and not self.Controller:IsFinished() do
			if not self.Controller:CanDirectorAct() then
				task.wait(.2)
			else
				local ability = self:_pick()
				if ability then
					self.Last = ability
					local ok, err = pcall(function() self.Controller["Cast" .. ability](self.Controller) end)
					if not ok then
						warn("[MiasmaAbilityDirector] " .. ability .. " failed: " .. tostring(err))
						self.Controller:AbortAbility()
					end
				end
				local gap = Config.Boss.NeutralDuration
				if self.Controller:IsEnraged() then gap *= Config.Boss.EnrageSpeedMultiplier end
				task.wait(gap)
			end
		end
	end)
end

function Director:Stop()
	self.Running = false
	self.Serial += 1
end

function Director:Destroy()
	self:Stop()
end

return Director
