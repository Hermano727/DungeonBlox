--[[
	TutorialSteps (server)

	The tutorial, step by step, in order (first pass, 2026-10-04). Areas in
	TutorialRealmTemplate, left to right: the wake camp, the road with two slimes, the main camp
	(merchant, altar, coal ore, campfire; the pond just outside), the dash gap, the forest path
	with a key-chest, the repair camp (blacksmith), the elite arena, the totem.

	A step:
	  id          unique, saved as the player's progress (rejoin resumes here)
	  objective   the line at the top (string or function(ctx)); no em-dashes, sentence case
	  arrow       a marker name, or function(ctx) -> part / Vector3: the blue path leads there
	  highlight   the model to use there (NPC, altar, ore...), by name in the copy, or
	              function(ctx) -> Instance: it glows gold until the step ends
	  hints       key hints: { { key = "MouseLeft" | "Tab" | "Q" ..., text = "Attack" } }
	  focus       a UI element to keep lit while the rest greys (TutorialTarget key, "item:<uuid>",
	              or a list: the first that's on screen), string or function(ctx)
	  checkpoint  marker to resume / respawn at during this step (else the spawn point)
	  cutscene    a named client moment on entering ("wake")
	  spotlight   { target = TutorialTarget key or nil, caption = "..." } + waitForAck = true:
	              pauses the game (your controls, your copy's mobs) until the player clicks
	  ackOnClick  with waitForAck (no spotlight): done when the player clicks the FIRST focus
	              target (e.g. the Journal's Loot Score page); ctx.acked() turns true
	  enter(ctx)  set the step up. Scripted outcomes ONLY through ctx.rigs (ScriptedRigs).
	  done(ctx)   true when complete (checked 4x a second)

	ctx: player, profile(), marker(name), spawnMob(marker, mobId, level, { damage, healthFloor }),
	     rigs, instances, elapsed(), acked(), refresh(), state (this step), shared (this session),
	     data() (saved on the tutorial flag: survives a rejoin).

	Every enter() must be safe to run again on a rejoin (the step restarts at its checkpoint).
]]

local ServerScriptService = game:GetService("ServerScriptService")

local ProfileService = require(ServerScriptService:WaitForChild("ProfileService"))
local HungerData = require(ServerScriptService:WaitForChild("HungerData"))
local DurabilityService = require(ServerScriptService:WaitForChild("DurabilityService"))
local ItemIdentity = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemIdentity"))
local ItemFactory = require(game:GetService("ReplicatedStorage"):WaitForChild("Items"):WaitForChild("ItemFactory"))

local ORIGIN = { kind = ItemIdentity.SOURCE.QUEST, src = "tutorial" }

local Steps = {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function root(ctx)
	return ctx.player.Character and ctx.player.Character:FindFirstChild("HumanoidRootPart")
end

local function humanoid(ctx)
	return ctx.player.Character and ctx.player.Character:FindFirstChildOfClass("Humanoid")
end

local function near(ctx, markerName, radius)
	local marker, r = ctx.marker(markerName), root(ctx)
	return marker ~= nil and r ~= nil and (r.Position - marker.Position).Magnitude <= radius
end

local function count(ctx, itemId)
	return ProfileService.CountItemId(ctx.player, itemId)
end

local function grant(ctx, itemId, n)
	return ProfileService.GrantItemId(ctx.player, itemId, n or 1, { by = ctx.player, kind = ORIGIN.kind, src = ORIGIN.src })
end

local function grantCoins(ctx, amount)
	local profile = ctx.profile()
	if not profile then return end
	profile.currencies.Coins = math.floor((tonumber(profile.currencies.Coins) or 0) + amount)
	ProfileService.PushProfile(ctx.player)
end

-- The tutorial's own sword (dropped by the first slime): its uuid is saved in ctx.data().
local function sword(ctx)
	local profile = ctx.profile()
	local uuid = ctx.data().swordUuid
	return profile and uuid and profile.inventory[uuid], uuid
end

local function equippedWeapon(ctx)
	local profile = ctx.profile()
	local uuid = profile and profile.equipped and profile.equipped.Weapon
	return profile and uuid and profile.inventory[uuid], uuid
end

-- A Training Sword with a 5% crit (the drop, and its stand-in if a rejoin lost the drop).
local function critSwordTemplate()
	local item = ItemFactory.CreateOwnedItem("TrainingSword", { origin = ORIGIN })
	if not item then return nil end
	local template = {}
	for k, v in pairs(item) do
		if k ~= "uuid" and k ~= "serial" and k ~= "origin" then template[k] = v end
	end
	template.subStats = table.clone(item.subStats or {})
	template.subStats.critical = 5
	template.tags = { "Sword" } -- the drop shows the game's T1 sword model (LootDropVisuals)
	return template
end

-- The newest TrainingSword with a crit roll the player owns that isn't recorded yet.
local function findCritSword(ctx)
	local profile = ctx.profile()
	if not profile then return nil end
	for uuid, item in pairs(profile.inventory) do
		if item.itemId == "TrainingSword" and type(item.subStats) == "table" and item.subStats.critical then
			return uuid
		end
	end
	return nil
end

-- No natural healing (the shield's HP/s and Roblox's default 1%/s "Health" script) while
-- on: the potion is the only way back up. Server-side only (a player attribute the regen loop
-- reads, and the character's Health script switched off).
local function pauseRegen(ctx, paused)
	ctx.player:SetAttribute("RegenPaused", paused or nil)
	local health = ctx.player.Character and ctx.player.Character:FindFirstChild("Health")
	if health and health:IsA("Script") then health.Enabled = not paused end
end

local function mobDead(mob)
	return mob == nil or not mob:IsAlive()
end

---------------------------------------------------------------------------
-- The steps
---------------------------------------------------------------------------

Steps.List = {
	------------------------------------------------------------------ waking up
	{
		id = "wake",
		objective = "Wake up",
		cutscene = "wake",
		enter = function(ctx)
			-- Half health (no regen until the potion), and potions to fix it.
			pauseRegen(ctx, true)
			local h = humanoid(ctx)
			if h then h.Health = h.MaxHealth * 0.5 end
			if count(ctx, "MinorPotion") < 2 then grant(ctx, "MinorPotion", 2) end
		end,
		done = function(ctx) return ctx.elapsed() > 4.5 end,
	},
	{
		id = "drink",
		objective = "You're hurt. Drink a potion",
		hints = { { key = "Z", text = "Drink a potion" } },
		focus = "hud_potion",
		enter = function(ctx)
			pauseRegen(ctx, true) -- (again, on a rejoin into this step)
			if count(ctx, "MinorPotion") < 1 then grant(ctx, "MinorPotion", 2) end
			ctx.state.before = count(ctx, "MinorPotion")
		end,
		done = function(ctx)
			local drank = count(ctx, "MinorPotion") < ctx.state.before
			if drank then pauseRegen(ctx, false) end
			return drank
		end,
	},

	------------------------------------------------------------------ energy and panting
	{
		id = "spam_attack",
		objective = "A slime! Click as fast as you can",
		arrow = "FirstMob",
		hints = { { key = "MouseLeft", text = "Attack" } },
		enter = function(ctx)
			-- It can't die yet (HP floor 1) and barely hurts: the point is running out of energy.
			ctx.shared.slime = ctx.spawnMob("FirstMob", "PlainsSlime", 1, { damage = 2, healthFloor = 1 })
		end,
		done = function(ctx) return ctx.player:GetAttribute("EnergyPanting") == true end,
	},
	{
		id = "panting",
		objective = "Out of breath",
		spotlight = {
			target = "hud_energy",
			caption = "Every swing costs energy. Run out and you pant: slow, and no attacks until it refills. It refills every second, even mid-fight. Pace your swings.",
		},
		waitForAck = true,
		done = function(ctx) return ctx.acked() end,
	},
	{
		id = "finish_slime",
		objective = "Finish the slime",
		arrow = "FirstMob",
		hints = { { key = "MouseLeft", text = "Attack" } },
		checkpoint = "FirstMob",
		enter = function(ctx)
			local slime = ctx.shared.slime
			if mobDead(slime) then
				slime = ctx.spawnMob("FirstMob", "PlainsSlime", 1, { damage = 2 })
				ctx.shared.slime = slime
			end
			if slime then slime.HealthFloor = nil end
			-- It drops a sword with a 5% crit, on the ground (a moment before it can be picked
			-- up, so it's seen landing). No coins this time.
			ctx.rigs.Queue(ctx.player, "mobDrop", {
				template = critSwordTemplate(),
				pickupDelay = 2.5,
				onDropped = function(position)
					ctx.shared.dropAt = position
					ctx.refresh()
				end,
			})
		end,
		done = function(ctx) return mobDead(ctx.shared.slime) end,
	},
	{
		id = "pickup_sword",
		objective = "It dropped a sword. Pick it up",
		arrow = function(ctx) return ctx.shared.dropAt end,
		checkpoint = "FirstMob",
		enter = function(ctx)
			-- Rejoined after the drop vanished: hand it over directly.
			if not ctx.shared.dropAt and not findCritSword(ctx) then
				local template = critSwordTemplate()
				if template then ProfileService.GrantItem(ctx.player, template, 1, { by = ctx.player, kind = ORIGIN.kind, src = ORIGIN.src }) end
			end
		end,
		done = function(ctx)
			local uuid = findCritSword(ctx)
			if uuid then ctx.data().swordUuid = uuid end
			return uuid ~= nil
		end,
	},
	{
		id = "equip_sword",
		objective = "Equip your new sword: open your inventory, right-click it, Equip",
		hints = { { key = "Tab", text = "Inventory" } },
		checkpoint = "FirstMob",
		focus = function(ctx)
			local _, uuid = sword(ctx)
			return { uuid and ("item:" .. uuid) or "nav_inventory", "shortcut_inventory" }
		end,
		done = function(ctx)
			local _, wanted = sword(ctx)
			local _, equipped = equippedWeapon(ctx)
			return wanted ~= nil and wanted == equipped
		end,
	},

	------------------------------------------------------------------ critical hits
	{
		id = "crit_fight",
		objective = "Try it out on this slime",
		arrow = "CritMob",
		hints = { { key = "MouseLeft", text = "Attack" } },
		checkpoint = "FirstMob",
		enter = function(ctx)
			ctx.shared.critSlime = ctx.spawnMob("CritMob", "PlainsSlime", 1, { damage = 2 })
			ctx.rigs.Queue(ctx.player, "crit", true) -- the first hit crits
		end,
		-- The scripted crit has been used: that hit was a critical.
		done = function(ctx) return ctx.rigs.Peek(ctx.player, "crit") == nil end,
	},
	{
		id = "crit_spotlight",
		objective = "A critical hit",
		spotlight = {
			caption = "A critical hit! Your new sword has a 5% chance on every swing to deal extra damage. Better gear rolls stronger effects like this.",
		},
		waitForAck = true,
		done = function(ctx) return ctx.acked() end,
	},
	{
		id = "crit_finish",
		objective = "Finish it",
		arrow = "CritMob",
		checkpoint = "CritMob",
		enter = function(ctx)
			if mobDead(ctx.shared.critSlime) then
				ctx.shared.critSlime = ctx.spawnMob("CritMob", "PlainsSlime", 1, { damage = 2 })
			end
		end,
		done = function(ctx) return mobDead(ctx.shared.critSlime) end,
	},

	------------------------------------------------------------------ the camp: merchant, scroll, altar
	{
		id = "to_camp",
		objective = "Follow the path to the camp",
		arrow = "Camp",
		checkpoint = "CritMob",
		done = function(ctx) return near(ctx, "Camp", 18) end,
	},
	{
		id = "salvage",
		objective = "Salvage your old sword at the merchant for scrap",
		arrow = "Merchant",
		highlight = "The Merchant",
		hints = { { key = "E", text = "Talk" } },
		checkpoint = "Camp",
		enter = function(ctx)
			-- Something to salvage (the old training sword normally; a spare if it's gone).
			local profile = ctx.profile()
			local has = false
			for uuid, item in pairs(profile.inventory) do
				if item.type == "Weapon" and uuid ~= ctx.data().swordUuid and profile.equipped.Weapon ~= uuid then has = true end
			end
			if not has and count(ctx, "T1Scrap") < 4 then grant(ctx, "TrainingSword", 1) end
		end,
		done = function(ctx) return count(ctx, "T1Scrap") >= 4 end,
	},
	{
		id = "buy_scroll",
		objective = "Trade 4 scrap for a weapon scroll",
		arrow = "Merchant",
		highlight = "The Merchant",
		checkpoint = "Camp",
		enter = function(ctx)
			-- One-time tutorial price (server-side, tutorial-only).
			if not ctx.rigs.Peek(ctx.player, "price:T1WeaponScroll") then
				ctx.rigs.Queue(ctx.player, "price:T1WeaponScroll", { price = 4, currency = "T1Scrap" })
			end
		end,
		done = function(ctx) return count(ctx, "T1WeaponScroll") >= 1 end,
	},
	{
		id = "enchant",
		objective = "Use the scroll on your sword at the altar",
		arrow = "Altar",
		highlight = "Tutorial_EnchantingAltar",
		hints = { { key = "E", text = "Enchant" } },
		checkpoint = "Camp",
		done = function(ctx)
			local item = equippedWeapon(ctx)
			return item ~= nil and (tonumber(item.enchantLevel) or 0) >= 1
		end,
	},
	{
		id = "enchant_spotlight",
		objective = "Stronger",
		spotlight = {
			caption = "+1! Each enchant raises your weapon's damage. Up to +3 is safe. Past that, a failed enchant can break the item.",
		},
		waitForAck = true,
		done = function(ctx) return ctx.acked() end,
	},

	------------------------------------------------------------------ mining, orbs
	{
		id = "mine",
		objective = "Mine the coal ore",
		arrow = "Ore",
		highlight = "CoalOre",
		hints = { { key = "MouseLeft", text = "Strike the coal" } },
		checkpoint = "Camp",
		done = function(ctx) return count(ctx, "Coal") >= 1 end,
	},
	{
		id = "buy_orb",
		objective = "Trade the coal for an Orb of Alteration",
		arrow = "Merchant",
		highlight = "The Merchant",
		checkpoint = "Camp",
		enter = function(ctx)
			if not ctx.rigs.Peek(ctx.player, "price:T1OrbOfAlteration") then
				ctx.rigs.Queue(ctx.player, "price:T1OrbOfAlteration", { price = 1, currency = "Coal" })
			end
		end,
		done = function(ctx) return count(ctx, "T1OrbOfAlteration") >= 1 end,
	},
	{
		id = "orb_fail",
		objective = "Use the orb on your sword at the altar",
		arrow = "Altar",
		highlight = "Tutorial_EnchantingAltar",
		checkpoint = "Camp",
		enter = function(ctx)
			-- The first reroll loses the crit for one weak roll (a real orb always gives at least one
			-- substat, so the scripted fail does too); the second brings the crit back plus piercing
			-- (pierce 4 = the top of the T1 range; the crit stays the tutorial sword's 5).
			if not ctx.rigs.Peek(ctx.player, "alteration") then
				ctx.rigs.Queue(ctx.player, "alteration", { accuracy = 4 })
				ctx.rigs.Queue(ctx.player, "alteration", { critical = 5, pierce = 4 })
			end
			ctx.state.orbs = count(ctx, "T1OrbOfAlteration")
		end,
		done = function(ctx) return count(ctx, "T1OrbOfAlteration") < ctx.state.orbs end,
	},
	{
		id = "orb_retry",
		objective = "Oh no! It rerolled badly. Try again",
		arrow = "Altar",
		highlight = "Tutorial_EnchantingAltar",
		checkpoint = "Camp",
		enter = function(ctx)
			if count(ctx, "T1OrbOfAlteration") < 1 then grant(ctx, "T1OrbOfAlteration", 1) end
			ctx.state.orbs = count(ctx, "T1OrbOfAlteration")
		end,
		done = function(ctx) return count(ctx, "T1OrbOfAlteration") < ctx.state.orbs end,
	},
	{
		id = "orb_spotlight",
		objective = "Mine, trade, upgrade",
		spotlight = {
			caption = "Orbs reroll your gear's bonus effects: crit, piercing and more. Mine ore, trade it for orbs and scrolls. Merchants can be found in every town.",
		},
		waitForAck = true,
		done = function(ctx) return ctx.acked() end,
	},

	------------------------------------------------------------------ hunger, fishing, cooking, buffs
	{
		id = "hunger",
		objective = "Hungry",
		spotlight = {
			target = "hud_hunger",
			caption = "Hunger empties as you sprint and fight. Too hungry and you can't sprint or dash. Fish is food.",
		},
		waitForAck = true,
		enter = function(ctx) HungerData.set(ctx.player, 4) end,
		done = function(ctx) return ctx.acked() end,
	},
	{
		id = "fish_one",
		objective = "Spear a fish at the pond",
		arrow = "Pond",
		hints = { { key = "MouseLeft", text = "Throw" } },
		checkpoint = "Camp",
		enter = function(ctx)
			ctx.state.before = count(ctx, "Fish")
			ctx.rigs.Queue(ctx.player, "fish", { fishId = "Fish", count = 1 })
		end,
		done = function(ctx) return count(ctx, "Fish") > ctx.state.before end,
	},
	{
		id = "fish_swift",
		objective = "Now catch the swift fish",
		arrow = "Pond",
		checkpoint = "Camp",
		enter = function(ctx)
			ctx.state.before = count(ctx, "SwiftFish")
			ctx.rigs.Queue(ctx.player, "fish", { fishId = "SwiftFish", count = 1 })
		end,
		done = function(ctx) return count(ctx, "SwiftFish") > ctx.state.before end,
	},
	{
		id = "cook",
		objective = "Cook your fish at the campfire",
		arrow = "Fire",
		highlight = "T1_CookingCampfire",
		hints = { { key = "E", text = "Hold to cook" } },
		checkpoint = "Camp",
		done = function(ctx) return count(ctx, "T1_CookedFish") >= 1 and count(ctx, "T2_CookedSwiftFish") >= 1 end,
	},
	{
		id = "eat",
		objective = "Eat the cooked fish",
		hints = { { key = "V", text = "Eat" } },
		focus = "hud_fish",
		checkpoint = "Camp",
		enter = function(ctx)
			ctx.state.before = count(ctx, "T1_CookedFish")
			HungerData.set(ctx.player, math.min(4, (HungerData.get(ctx.player) or { hunger = 4 }).hunger))
		end,
		done = function(ctx) return count(ctx, "T1_CookedFish") < ctx.state.before end,
	},
	{
		id = "eat_swift",
		objective = "Hold V to switch to the swift fish, then tap V to eat it",
		hints = { { key = "V", text = "Hold: switch" }, { key = "V", text = "Tap: eat" } },
		focus = "hud_fish",
		checkpoint = "Camp",
		done = function(ctx)
			local Buffs = require(ServerScriptService:WaitForChild("BuffService"))
			for _, b in ipairs(Buffs.GetActiveBuffs(ctx.player)) do
				if b.type == "WalkSpeedPct" then return true end
			end
			return false
		end,
	},
	{
		id = "buff_spotlight",
		objective = "Swift",
		spotlight = {
			target = "hud_buffs",
			caption = "Special fish give buffs. Active buffs and their time left show here. You're faster for a minute: use it.",
		},
		waitForAck = true,
		done = function(ctx) return ctx.acked() end,
	},

	------------------------------------------------------------------ dash
	{
		id = "dash_gap",
		objective = "Cross the gap: jump, then dash in mid-air",
		arrow = "GapFar",
		hints = { { key = "Space", text = "Jump" }, { key = "Q", text = "Dash" } },
		checkpoint = "Camp",
		done = function(ctx)
			local r = root(ctx)
			local far = ctx.marker("GapFar")
			return r ~= nil and far ~= nil and (Vector3.new(r.Position.X, 0, r.Position.Z) - Vector3.new(far.Position.X, 0, far.Position.Z)).Magnitude < 5
				and r.Position.Y > far.Position.Y - 1
		end,
	},

	------------------------------------------------------------------ the forest path, the chest, the Journal
	{
		id = "forest",
		objective = "Clear the forest path",
		arrow = function(ctx)
			for i = 1, 5 do
				local mob = ctx.state.mobs and ctx.state.mobs[i]
				if mob and not mobDead(mob) then return mob:GetPosition() end
			end
			return ctx.marker("Path5")
		end,
		checkpoint = "GapFar",
		enter = function(ctx)
			ctx.state.mobs = {}
			for i = 1, 5 do
				ctx.state.mobs[i] = ctx.spawnMob("Path" .. i, "PlainsSlime", 2, { damage = 4 })
			end
			-- The last one (by the chest) drops a key, and the chest holds a potion and a broken sword.
			ctx.rigs.Queue(ctx.player, "chestReward", {
				coins = 25,
				items = { { "MinorPotion", 1 } },
				templates = { (function()
					local t = ItemFactory.CreateOwnedItem("TrainingSword", { origin = ORIGIN })
					if not t then return nil end
					local tpl = {}
					for k, v in pairs(t) do if k ~= "uuid" and k ~= "serial" and k ~= "origin" then tpl[k] = v end end
					tpl.maxDurability = DurabilityService.maxDurForTier(1)
					tpl.durability = 0
					tpl.broken = true
					tpl.name = "Rusted Training Sword"
					return tpl
				end)() },
			})
		end,
		done = function(ctx)
			for i = 1, 5 do
				if not mobDead(ctx.state.mobs[i]) then
					-- the arrow follows the next live slime
					if ctx.state.target ~= i then ctx.state.target = i; ctx.refresh() end
					return false
				end
			end
			return true
		end,
	},
	{
		id = "chest",
		objective = "Take the key and let it open the chest",
		arrow = "Path5",
		highlight = "Dropper",
		hints = { { key = "E", text = "Take key" } },
		checkpoint = "Path5",
		done = function(ctx)
			-- the chest's scripted reward has been paid
			return ctx.rigs.Peek(ctx.player, "chestReward") == nil
		end,
	},
	{
		id = "journal",
		objective = "Open your Journal and click Loot Score",
		hints = { { key = "Tab", text = "Menu" } },
		focus = { "journal_lootScore", "nav_journal", "shortcut_journal" },
		checkpoint = "Path5",
		waitForAck = true,
		ackOnClick = true, -- clicking the Loot Score page completes it
		done = function(ctx) return ctx.acked() end,
	},
	{
		id = "journal_spotlight",
		objective = "Your Journal",
		spotlight = {
			caption = "Loot Score tracks your drops. A dry streak is how long you've gone without one of each rarity. Most questions about the game and your stats are answered in the Journal.",
		},
		waitForAck = true,
		done = function(ctx) return ctx.acked() end,
	},

	------------------------------------------------------------------ death, durability, repair
	{
		id = "ambush",
		objective = "Head to the repair camp",
		arrow = "RepairCamp",
		checkpoint = "Path5",
		enter = function(ctx)
			-- Worn enough that this death breaks it (30% of max per death).
			local item = equippedWeapon(ctx)
			if item then
				DurabilityService.EnsureDurability(item)
				item.durability = math.floor(item.maxDurability * 0.2)
				ProfileService.PushProfile(ctx.player)
			end
			ctx.state.brute = ctx.spawnMob("Ambush", "PlainsSlimeElite", 30, { damage = 9999 })
			ctx.state.died = false
			local h = humanoid(ctx)
			if h then
				h.Died:Once(function() ctx.state.died = true end)
			end
			-- After the death: the repair camp.
			ctx.player:SetAttribute("RespawnAt", ctx.marker("RepairCamp") and ctx.marker("RepairCamp").CFrame)
		end,
		done = function(ctx)
			local r = root(ctx)
			local back = ctx.state.died and r ~= nil and humanoid(ctx) ~= nil and humanoid(ctx).Health > 0
			if back and ctx.state.brute and ctx.state.brute.Stats then
				-- its job is done: it stops hunting
				ctx.state.brute.Stats.BaseDamage = 0
				ctx.state.brute.Stats.AggroRange = 0
			end
			return back
		end,
	},
	{
		id = "broken_spotlight",
		objective = "Your sword broke",
		checkpoint = "RepairCamp",
		spotlight = {
			caption = "Dying costs every piece of gear you're wearing 30% of its durability. At zero it breaks and loses 3 enchant levels, which is why your +1 is gone. Repair it before it's too late.",
		},
		waitForAck = true,
		done = function(ctx) return ctx.acked() end,
	},
	{
		id = "repair",
		objective = "Repair your sword at the blacksmith",
		arrow = "Blacksmith",
		highlight = "T1_Blacksmith_R15",
		hints = { { key = "E", text = "Repair" } },
		checkpoint = "RepairCamp",
		enter = function(ctx)
			-- Coins for exactly the repair.
			local item = sword(ctx)
			local cost = item and DurabilityService.getRepairCost(item) or 0
			if cost > 0 then grantCoins(ctx, cost) end
		end,
		done = function(ctx)
			local item = sword(ctx)
			return item == nil or item.broken ~= true
		end,
	},
	{
		id = "reequip",
		objective = "Equip your repaired sword",
		focus = function(ctx)
			local _, uuid = sword(ctx)
			return { uuid and ("item:" .. uuid) or "nav_inventory", "shortcut_inventory" }
		end,
		checkpoint = "RepairCamp",
		done = function(ctx)
			local _, wanted = sword(ctx)
			local _, equipped = equippedWeapon(ctx)
			return wanted == nil or wanted == equipped
		end,
	},

	------------------------------------------------------------------ the named elite
	{
		id = "arena",
		objective = "Something lurks in the pit. Kill the slime",
		arrow = "ArenaMob",
		checkpoint = "RepairCamp",
		enter = function(ctx)
			-- One kill from the named elite (the pity bar shows 99/100).
			local system = rawget(_G, "MobSystem")
			if system and system.SetTutorialPity then system.SetTutorialPity(ctx.player, "The Slime Pit", 99) end
			ctx.state.slime = ctx.spawnMob("ArenaMob", "PlainsSlime", 2, { damage = 3 })
			ctx.rigs.Queue(ctx.player, "eliteDrop", { itemId = "T1KeyFragment", count = 1, pickupDelay = 1.5 })
			ctx.state.fragments = count(ctx, "T1KeyFragment")
		end,
		done = function(ctx) return mobDead(ctx.state.slime) end,
	},
	{
		id = "elite",
		objective = "The Slime King! Defeat it",
		arrow = "Arena",
		hints = { { key = "Q", text = "Dash out of the way" } },
		checkpoint = "RepairCamp",
		done = function(ctx)
			-- the elite's scripted drop has gone out: it died
			local dead = ctx.rigs.Peek(ctx.player, "eliteDrop") == nil
			if dead then ctx.shared.eliteKilled = true end
			return dead
		end,
	},
	{
		id = "fragment",
		objective = "Pick up the key fragment",
		arrow = "Arena",
		checkpoint = "Arena",
		enter = function(ctx)
			-- A rejoin lost the drop on the ground: hand it over.
			if not ctx.shared.eliteKilled and count(ctx, "T1KeyFragment") < 1 then grant(ctx, "T1KeyFragment", 1) end
		end,
		done = function(ctx) return count(ctx, "T1KeyFragment") >= 1 end,
	},
	{
		id = "fragment_spotlight",
		objective = "A key fragment",
		spotlight = {
			caption = "Named elites drop key fragments. Collect enough and the Dungeoneer will forge them into a dungeon key. Explore the world to find what dungeons await.",
		},
		waitForAck = true,
		done = function(ctx) return ctx.acked() end,
	},

	------------------------------------------------------------------ the hearthstone, and out
	{
		id = "totem",
		objective = "Attune the hearthstone totem",
		arrow = "Totem",
		highlight = "HearthTotem",
		hints = { { key = "E", text = "Hold to attune" } },
		checkpoint = "Arena",
		done = function(ctx)
			local profile = ctx.profile()
			return profile ~= nil and profile.flags.hearthstoneUnlocked == true
		end,
	},
	{
		id = "hearth",
		objective = "Open the Hearthstone and return to Oakhaven",
		hints = { { key = "Tab", text = "Menu" } },
		focus = { "hearth_return", "nav_hearthstone", "shortcut_hearthstone" },
		checkpoint = "Totem",
		done = function(ctx)
			local r = root(ctx)
			return r ~= nil and not ctx.instances.Contains(ctx.player, r.Position)
		end,
	},
}

return Steps
