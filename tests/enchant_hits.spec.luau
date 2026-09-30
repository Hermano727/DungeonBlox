return function(sources)
	local count = 0
	local function check(value, message) assert(value, message); count += 1 end
	local function load(name, env)
		local chunk = assert(loadstring(sources[name], name))
		setfenv(chunk, setmetatable(env or {}, { __index = getfenv() }))
		return chunk()
	end
	local now, randomValue = 0, 0
	local armorConfig = load("ArmorConfig")
	local storage = { WaitForChild = function(_, name) return name end }
	local armor = load("Armor", {
		game = { GetService = function() return storage end },
		require = function() return armorConfig end,
		os = { clock = function() return now end },
		Random = { new = function() return { NextNumber = function() return randomValue end } end },
	})
	local target, other, respawn = {}, {}, {}
	local rating, flags = armor.Resolve(target, 100, { shatter = 100 })
	check(rating == 80 and flags.isShatter, "Shatter applies to triggering hit")
	now = 2
	check(armor.Resolve(target, 100, { shatter = 100 }) == 80, "refresh does not stack")
	now = 3.1
	check(armor.Resolve(target, 100, {}) == 80, "refresh extends expiry; no new enchant required")
	check(armor.Resolve(other, 100, {}) == 100, "other target unaffected")
	check(armor.Resolve(respawn, 100, {}) == 100, "new character starts without break")
	rating, flags = armor.Resolve(target, 100, { crushing = 100 })
	check(rating == 40 and flags.isCrushing, "Crushing ignores half of weakened armor")
	check(armor.Resolve(target, 100, {}) == 80, "Crushing lasts one hit")
	check(armor.Resolve(target, 200, {}) == 160, "armor changes derive from current base, not snapshot")
	now = 5
	check(armor.Resolve(target, 100, {}) == 100, "Shatter expires at deadline")
	rating, flags = armor.Resolve(target, 0, { shatter = 100, crushing = 100 })
	check(rating == 0 and not flags.isShatter and not flags.isCrushing, "no armor procs on unarmored targets")
	randomValue = 0.5
	rating, flags = armor.Resolve(other, 100, { shatter = 20, crushing = 20 })
	check(rating == 100 and not flags.isShatter and not flags.isCrushing, "failed rolls leave armor unchanged")
	rating, flags = armor.Resolve(other, 100, { shatter = -10, crushing = 1000 })
	check(rating == 50 and flags.isCrushing and not flags.isShatter, "chance bounds")

	-- Run the actual damage module with lightweight service doubles.
	local profile = { Combat = { Armor = 100, HP = 1000 } }
	local player = { Character = { FindFirstChildOfClass = function() return nil end } }
	local block = 0
	local remote = { FireClient = function() end }
	local root = { FindFirstChild = function(_, name) return name == "PlayEffectSfx" and remote or name end,
		WaitForChild = storage.WaitForChild }
	local modules = {
		ArmorEnchantService = armor, HungerConfig = { EXHAUSTION = { DAMAGE_TAKEN = 0 } },
		ItemConfig = { BLOCK_CHANCE_CAP_PCT = 100 }, PlayerDataManager = { Get = function() return profile end },
		ProfileService = { Get = function() return {} end }, StatsService = { SumEquippedSubStat = function() return block end },
		HungerData = { addExhaustion = function() end }, CombatStateService = { OnPlayerDamaged = function() end },
		DurabilityService = { armorHit = function() end },
	}
	-- GameEvents needs FindFirstChild, not the module token used by lazy requires.
	local gameEvents = { FindFirstChild = function() return remote end }
	remote.IsA = function() return true end
	local replicated = { FindFirstChild = function() return gameEvents end, WaitForChild = storage.WaitForChild }
	local damage = load("Damage", { game = { GetService = function(_, n) return n == "ReplicatedStorage" and replicated or root end },
		require = function(n) return assert(modules[n], n) end })
	randomValue = 0
	block = 100
	local dealt = damage.ApplyToPlayer(player, 100, nil, { shatter = 100 })
	check(dealt == 0 and profile.Combat.HP == 1000, "blocked damage unchanged")
	block = 0
	check(damage.ApplyToPlayer(player, 100, nil, {}) == 50, "blocked hit did not apply Shatter")
	dealt, flags = damage.ApplyToPlayer(player, 100, nil, { shatter = 100, crushing = 100 })
	check(math.abs(dealt - 100 / 1.4) < 1e-8 and flags.isShatter and flags.isCrushing, "PvP curve applies both effects once")
	check(math.abs(damage.ApplyToPlayer(player, 100, nil, {}) - 100 / 1.8) < 1e-8, "later hit retains only Shatter")
	local zeroTarget = {}
	check(damage.ComputeHitFinal(0, 100, zeroTarget, { shatter = 100 }) == 0, "zero damage rejected")
	check(armor.Resolve(zeroTarget, 100, {}) == 100, "zero damage cannot apply break")
	local amount, hit = damage.ComputeWeaponFinal(100, { execute = 100, pierce = 20 }, 0.5, "Mob")
	check(amount == 135 and hit.executeBonus == 15 and hit.isPiercing, "existing Execute and Piercing damage preserved")
	local feedback = load("Feedback")
	local selected = feedback.Select(hit, flags)
	check(selected.Execute and selected.Piercing and selected.Shatter and selected.Crushing, "visual flags follow resolved outcomes")
	check(not feedback.Select({ isExe = true, executeBonus = 0 }).Execute, "no Execute VFX for zero bonus")
	check(not feedback.Select().Shatter and not feedback.Select().Piercing, "legacy payload has no new procs")
	local mobFunction = assert(sources.Mob:match("(function MobClass:TakeDamage.-)\n%-%- Default hit sound"))
	local mobChunk = assert(loadstring("local MobClass = {}\n" .. mobFunction .. "\nreturn MobClass"))
	setfenv(mobChunk, setmetatable({ DamageService = damage }, { __index = getfenv() }))
	local mobClass = mobChunk()
	local mob = setmetatable({ CurrentHealth = 1000, IsInvulnerable = true, Stats = { Armor = 100 }, DamageTracker = {},
		UpdateHPBar = function() end, AIState = "Walking", Die = function(self) self.CurrentHealth = 0 end }, { __index = mobClass })
	local attacker = { UserId = 7 }
	check(not mob:TakeDamage(attacker, 100, { shatter = 100 }), "invulnerable mob rejects hit")
	mob.IsInvulnerable = false
	mob:TakeDamage(attacker, 100, {})
	check(mob.CurrentHealth == 950, "invulnerable hit did not leave Shatter")
	local died, mobFlags = mob:TakeDamage(attacker, 100, { shatter = 100, crushing = 100 })
	check(not died and mobFlags.isShatter and mobFlags.isCrushing, "PvE returns actual armor procs")
	check(mob.Stats.Armor == 100, "base stats never mutate")
	check(math.abs(mob.DamageTracker[7] - (50 + 100 / 1.4)) < 1e-8, "loot contribution uses post-enchant mitigation")
	damage.AwardKill = function() end
	mob.CurrentHealth = 1
	died, mobFlags = mob:TakeDamage(attacker, 100, { crushing = 100 })
	check(died and mobFlags.isCrushing, "killing blow retains proc flags")

	local motion = load("Motion")
	for _, kind in ipairs({ "Execute", "Shatter", "Crushing", "Piercing" }) do
		check(motion.State(kind, 1).fade == 1, kind .. " fully fades")
		for _, hz in ipairs({ 30, 60, 144 }) do
			local time = 0
			for _ = 1, hz / 2 do time += 1 / hz end
			check(math.abs(motion.State(kind, time).fade - motion.State(kind, 0.5).fade) < 1e-10, kind .. " time independent")
		end
	end
	check(motion.State("Execute", 0.28).close == 1, "jaw closes before burst")
	check(motion.State("Shatter", 0.20).burst == 0, "cracks precede fragments")
	check(motion.State("Crushing", 0.30).burst == 0, "compression holds before release")

	-- Execute the client builders/lifecycle using transform doubles. This checks
	-- cleanup and physics isolation, not Roblox rendering or visual appearance.
	local vm = {}
	local function vec(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, vm) end
	vm.__add = function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
	vm.__sub = function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
	vm.__unm = function(a) return vec(-a.X,-a.Y,-a.Z) end
	vm.__mul = function(a,b) return vec(a.X*b,a.Y*b,a.Z*b) end
	vm.__index = function(v,k)
		if k == "Magnitude" then return math.sqrt(v.X^2+v.Y^2+v.Z^2) end
		if k == "Unit" then return v * (1 / v.Magnitude) end
	end
	local cm = {}
	local function cf(x,y,z) return setmetatable({ Position = type(x) == "table" and x or vec(x,y,z) }, cm) end
	cm.__mul = function(a,b) return cf(a.Position+b.Position) end
	cm.__index = function(v,k)
		if k == "Rotation" then return cf() end
		if k == "LookVector" then return vec(0,0,-1) end
	end
	local objects = {}
	local function instance(kind)
		local obj = { ClassName = kind }
		function obj:Destroy()
			self.Parent = nil
			self.destroyed = true
			for _, child in ipairs(objects) do if child.Parent == self then child:Destroy() end end
		end
		table.insert(objects, obj)
		return obj
	end
	local callback, disconnects
	disconnects = 0
	local renderSignal = { Connect = function(_, fn)
		callback = fn
		return { Disconnect = function() callback = nil; disconnects += 1 end }
	end }
	local world = { CurrentCamera = { CFrame = cf(0,0,10) } }
	local fxConfig = load("Config", { Color3 = { fromRGB = function(...) return {...} end } })
	local fx = load("Effects", {
		game = { GetService = function(_, n)
			return n == "Workspace" and world or n == "RunService" and { RenderStepped = renderSignal } or storage
		end },
		require = function(n) return n == "EnchantHitEffectConfig" and fxConfig or motion end,
		Instance = { new = instance }, Enum = { Material = { Neon = 1, SmoothPlastic = 2, Slate = 3 } },
		Vector3 = { new = vec, xAxis = vec(1,0,0), yAxis = vec(0,1,0) },
		CFrame = { new = cf, lookAt = function(pos) return cf(pos) end, Angles = function() return cf() end },
		typeof = function(v) return getmetatable(v) == vm and "Vector3" or type(v) end,
		os = { clock = function() return now end }, script = { Destroying = { Connect = function() end } },
	})
	local origin, direction = vec(), vec(0,0,-1)
	now = 10
	for _, kind in ipairs({ "Execute", "Shatter", "Crushing", "Piercing" }) do fx.Play(kind, origin, direction, 1) end
	check(callback ~= nil, "active VFX starts one renderer")
	for _, object in ipairs(objects) do
		if object.ClassName == "Part" or object.ClassName == "WedgePart" then
			assert(object.Anchored and object.CanCollide == false and object.CanTouch == false and object.CanQuery == false,
				"effects must never join movement or hit detection")
		end
	end
	check(true, "all fragments isolated from physics and queries")
	now = 10.15; callback()
	for _ = 1, 20 do fx.Play("Execute", origin, direction, 1) end
	local liveGroups = 0
	for _, obj in ipairs(objects) do if obj.ClassName == "Model" and obj.Parent then liveGroups += 1 end end
	check(liveGroups == fxConfig.MaxActiveEffects, "burst bounded by active effect cap")
	now = 11; callback()
	check(callback == nil and disconnects == 1, "renderer disconnects after final effect")
	for _, obj in ipairs(objects) do if obj.ClassName ~= "Folder" then assert(obj.destroyed, "fragment leaked") end end
	check(true, "expired/evicted effects destroy all fragments")
	fx.Play("Piercing", vec(1000,0,0), direction, 1)
	check(callback == nil, "distant hits culled")
	fx.PlayHit({ effects = { Execute = true }, position = origin, direction = direction }, target)
	local before = #objects
	fx.PlayHit({ effects = { Execute = true }, position = origin, direction = direction }, target)
	check(#objects == before, "same-target rapid duplicates suppressed")
	fx.Clear()
	check(callback == nil and disconnects == 2, "explicit teardown disconnects")
	for _, obj in ipairs(objects) do assert(obj.destroyed, "teardown leaked object") end
	check(true, "explicit teardown clears folder and all effects")
	print(string.format("Enchant combat/motion: %d checks passed", count))
end
