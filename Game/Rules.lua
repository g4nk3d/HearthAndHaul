--[[ Hearth & Haul - Game/Rules.lua
	The whole dive as plain, deterministic Lua (no game API: the balance bot runs this same file).
	Time moves in fixed ticks (30 a second). A run is fixed by its seed: every door, every room, every
	creature's pause and every drop. Only your inputs change what happens, and every input is stamped with
	the tick it arrived on, so a run is its seed, its perk and its input log, and replays exactly.

	  run = R:NewRun(seed, perkId)       floor 1, three doors; run.phase == "doors"
	  R:Tick(run)                        one tick (1/30 s) of the world
	  R:Hold(run, "block"|"strike", on)  the two held keys
	  R:Door(run, i)                     walk through door i (1-3)
	  R:Hearth(run)                      start the hearth cast (or call it off)
	  R:Open(run) / R:Skip(run)          open the chest / walk past it
	  R:Shrine(run, "use"|"leave")      the room's shrine (heal 50, a blessing of +50% damage for 3 floors, or a gamble)
	  R:Take(run, i [, swap])            pick up waiting find i (swap: the bag slot it replaces when the bag is full)
	  R:Leave(run, i)                    leave find i on the floor
	  R:Next(run)                        on to the next floor
	  R:Replay(seed, perkId, log, ticks) the same run again

	run.phase: doors, enter, fight, chest, shrine, trap, clear, home (banked), dead (bag lost).
	Events: run.ev[1..run.evn], each { code, a, b, c } (the tables are reused; R:Drain empties the list). ]]

local _, ns = ...
local D = ns.Data
local R = {}
ns.Rules = R

local floor, min, max = math.floor, math.min, math.max

R.TPS = 30
local TPS = 30
local function T(sec) return floor(sec * TPS + 0.5) end

-- hero
R.MAX_HP, R.MAX_STA = 100, 100
local STRIKE_DMG, STRIKE_T, STRIKE_T_QUICK = 12, T(0.8), T(0.6)
local BLOCK_DRAIN, STA_REGEN, REGEN_WAIT = 12 / TPS, 22 / TPS, T(0.4)
R.CHIP = 0.15 -- a blocked hit still bruises
local BLOCK_COST, BLOCK_COST_SPECIAL, GUARD_BACK = 20, 45, 35
local REST_HEAL = 4
R.HP_GROW, R.DMG_GROW, R.HERO_GROW = 0.14, 0.12, 0.06
-- hearth
R.CAST_T = 300
local CAST_T, PUSHBACK = 300, 30
-- creatures
local HIT_GAP = T(0.4)
local TELE_SPECIAL = T(0.9)
local ATTACK_T, DEATH_T, ENTER_T = T(0.4), T(1.0), T(0.7)
local SLOTS = { 470, 590, 710 }
local BOSS_SLOTS = { 560, 740, 840 }
R.SLOTS, R.BOSS_SLOTS = SLOTS, BOSS_SLOTS
local SPAWN_X = 1000
local MAX_FOES = 3
-- rooms
local DOOR_WEIGHTS = { { "fight", 40 }, { "elite", 12 }, { "chest", 14 }, { "shrine", 12 }, { "trap", 10 }, { "unknown", 12 } }
local HIDDEN_WEIGHTS = { { "fight", 40 }, { "elite", 12 }, { "chest", 14 }, { "shrine", 12 }, { "trap", 10 } }
local DROP_CHANCE = 0.45
local BAG, BAG_DEEP = 12, 14
local MIMIC_CHANCE = 0.2

-- ------------------------------------------------------------------ deterministic numbers
-- Park-Miller (16807): exact in double arithmetic, the same on every machine
local M = 2147483647
local function Mix(seed, a, b, c)
	local h = (floor(seed) % (M - 1)) + 1
	h = (h * 48271 + (a or 0) * 7919 + (b or 0) * 104729 + (c or 0) * 1299709) % M
	if h == 0 then h = 1 end
	for _ = 1, 3 do h = (h * 16807) % M end
	return h
end
-- a stream is a two-slot table { state } so floors can reseed it without making a new closure
local function Seed(st, seed, a, b, c) st[1] = Mix(seed, a, b, c) return st end
local function Rnd(st) st[1] = (st[1] * 16807) % M return (st[1] - 1) / (M - 1) end
local function Int(st, lo, hi) return lo + floor(Rnd(st) * (hi - lo + 1)) end
R.Mix, R.Rnd, R.Int, R.Seed = Mix, Rnd, Int, Seed

local K_DOORS, K_ROOM, K_FIGHT = 1, 2, 3

local function Weighted(st, list)
	local total = 0
	for i = 1, #list do total = total + list[i][2] end
	local r = Rnd(st) * total
	for i = 1, #list do
		r = r - list[i][2]
		if r < 0 then return list[i][1] end
	end
	return list[#list][1]
end

-- ------------------------------------------------------------------ events (reused tables, no garbage)
local function Emit(run, code, a, b, c)
	local n = run.evn + 1
	run.evn = n
	local e = run.ev[n]
	if not e then e = {} run.ev[n] = e end
	e[1], e[2], e[3], e[4] = code, a, b, c
end
function R:Drain(run) run.evn = 0 end

local function SetPhase(run, p)
	if run.phase ~= p then
		run.phase = p
		Emit(run, "phase", p)
	end
end

-- ------------------------------------------------------------------ a new run
function R:NewRun(seed, perkId)
	seed = floor(tonumber(seed) or 1)
	local run = {
		seed = seed, perk = perkId, tick = 0, phase = "doors", floor = 1,
		hp = R.MAX_HP, sta = R.MAX_STA, broken = false, blockHeld = false, strikeHeld = false, blocking = false,
		swing = 0, regenT = 0, strikeT = (perkId == "quick_hands") and STRIKE_T_QUICK or STRIKE_T,
		bagMax = (perkId == "deep_pockets") and BAG_DEEP or BAG, bag = {}, pending = {},
		cast = nil, castPaused = false, cloak = false, spawnT = 0, pushbacks = 0, castHits = 0,
		bless = 0, hitGate = 0, foes = {}, doors = {}, room = nil, resume = nil, enterT = 0, trapT = 0,
		banked = 0, deepest = 1,
		-- what the achievements look at
		stats = { struck = false, castFromFight = false, bosses = {}, kills = 0, floorsCleared = 0 },
		ev = {}, evn = 0, log = {}, logn = 0,
		rngDoors = {}, rngRoom = {}, rngFight = {},
	}
	for i = 1, MAX_FOES do run.foes[i] = { on = false, slot = i } end
	R:MakeDoors(run)
	return run
end

local function Log(run, code, a, b)
	local n = run.logn
	local L = run.log
	L[n + 1], L[n + 2], L[n + 3], L[n + 4] = run.tick, code, a or 0, b or 0
	run.logn = n + 4
end

local function Zone(run) return D:Zone(run.floor) end

-- ------------------------------------------------------------------ doors
function R:MakeDoors(run)
	local st = Seed(run.rngDoors, run.seed, K_DOORS, run.floor)
	Seed(run.rngFight, run.seed, K_FIGHT, run.floor, 0)   -- creatures the hearth draws before a door is chosen
	local doors = run.doors
	for i = 1, 3 do doors[i] = doors[i] or {} doors[i].kind = nil end
	if D:IsBossFloor(run.floor) then
		doors[1].kind, doors[1].shown, doors[1].hidden = "boss", "boss", nil
		run.ndoors = 1
	else
		for i = 1, 3 do
			local k
			repeat k = Weighted(st, DOOR_WEIGHTS) until not (k == "elite" and run.floor < 2)
			local d = doors[i]
			d.kind, d.shown, d.hidden = k, k, nil
			if k == "unknown" then
				local h
				repeat h = Weighted(st, HIDDEN_WEIGHTS) until not (h == "elite" and run.floor < 2)
				d.hidden = h
				d.shown = (run.perk == "lantern") and h or "unknown"
			end
		end
		run.ndoors = 3
	end
	SetPhase(run, "doors")
	Emit(run, "doors", run.floor)
end

-- ------------------------------------------------------------------ loot
local function RollItem(run, st, bump)
	local z = Zone(run)
	local q = (function()
		local w = D.QUALITY_WEIGHTS[z.id]
		local total = 0
		for i = 1, 5 do total = total + w[i] end
		local r = Rnd(st) * total
		for i = 1, 5 do r = r - w[i] if r < 0 then return i end end
		return 5
	end)()
	q = min(5, q + (bump or 0))
	-- a find of that quality from the zone's list (the nearest quality down when the zone has none)
	local list = D.ITEMS[z.id]
	local pick, n = nil, 0
	for qq = q, 1, -1 do
		for i = 1, #list do
			if list[i].q == qq then
				n = n + 1
				if Rnd(st) * n < 1 then pick = i end
			end
		end
		if pick then break end
	end
	local it = list[pick]
	return { zone = z.id, idx = pick, q = it.q, name = it.name, icon = it.icon, value = D:Value(it.q, run.floor) }
end

local function BagValue(run)
	local v = 0
	for i = 1, #run.bag do v = v + run.bag[i].value end
	return v
end
R.BagValue = function(_, run) return BagValue(run) end

local function GiveDrop(run, item)
	if run.cast then
		-- mid-cast there is no time to sort: it goes straight in if there is room, else it is lost
		if #run.bag < run.bagMax then
			run.bag[#run.bag + 1] = item
			Emit(run, "bagged", item)
		else
			Emit(run, "lost", item)
		end
	else
		run.pending[#run.pending + 1] = item
		Emit(run, "drop", item)
	end
end

-- ------------------------------------------------------------------ creatures
local function Scale(run, id)
	local home = D.FOE_HOME[id] or 1
	local deeper = max(0, run.floor - home)
	return 1 + R.HP_GROW * deeper, 1 + R.DMG_GROW * deeper
end

local function FreeSlot(run, ranged)
	local foes = run.foes
	if ranged then
		for i = MAX_FOES, 1, -1 do if not foes[i].on then return i end end
	else
		for i = 1, MAX_FOES do if not foes[i].on then return i end end
	end
end

local function Alive(run)
	local n = 0
	for i = 1, MAX_FOES do
		local f = run.foes[i]
		if f.on and f.state ~= "dead" then n = n + 1 end
	end
	return n
end
R.Alive = function(_, run) return Alive(run) end

local function Spawn(run, id, delay, elite)
	local def = D.FOES[id]
	local slot = FreeSlot(run, def.ranged)
	if not slot then return nil end
	local f = run.foes[slot]
	local hs, ds = Scale(run, id)
	if elite then hs, ds = hs * 2.2, ds * 1.25 end
	f.on, f.id, f.def, f.elite, f.boss = true, id, def, elite or false, def.boss or false
	f.maxhp = floor(def.hp * hs + 0.5)
	f.hp = f.maxhp
	f.dmg = floor(def.dmg * ds + 0.5)
	f.x = SPAWN_X
	f.tx = (f.boss or run.bossFight) and BOSS_SLOTS[slot] or SLOTS[slot]
	f.state, f.t, f.delay = "walk", 0, delay or 0
	f.attacks, f.special = 0, false
	f.disguised = false
	Emit(run, "spawn", slot, id)
	return f
end

local function Cooldown(run, f)
	local cd = f.def.cd
	local pace = max(0.6, 1 - 0.02 * (run.floor - 1))
	return T((cd[1] + Rnd(run.rngFight) * (cd[2] - cd[1])) * pace)
end

local function FirstTarget(run)
	for i = 1, MAX_FOES do
		local f = run.foes[i]
		if f.on and f.state ~= "dead" and f.state ~= "walk" then return f, i end
	end
end

local function Kill(run, f, slot)
	f.state, f.t = "dead", DEATH_T
	run.stats.kills = run.stats.kills + 1
	Emit(run, "die", slot, f.id)
	local st = run.rngFight
	if f.boss then
		run.stats.bosses[f.id] = true
		run.hp = min(R.MAX_HP, run.hp + 30)
		Emit(run, "heal", 30)
		for _ = 1, 3 do GiveDrop(run, RollItem(run, st, 1)) end
	elseif f.elite then
		for _ = 1, 2 do GiveDrop(run, RollItem(run, st, 1)) end
	elseif Rnd(st) < DROP_CHANCE then
		GiveDrop(run, RollItem(run, st, 0))
	end
end

-- a hit lands on the hero: blocked, absorbed by the cloak, or taken
local function Land(run, f, slot)
	local special = f.special
	local dmg = special and floor(f.dmg * 1.6 + 0.5) or f.dmg
	if run.blocking then
		local cost = special and BLOCK_COST_SPECIAL or BLOCK_COST
		if run.sta >= cost then
			run.sta = run.sta - cost
			local chip = floor(dmg * R.CHIP + 0.5)
			run.hp = run.hp - chip
			Emit(run, "blocked", slot, dmg, chip)
			if run.hp <= 0 then run.hp = 0 R:Die(run) end
			return
		end
		run.sta, run.broken, run.blocking = 0, true, false
		Emit(run, "guardbreak", slot)
	end
	if run.cast and run.perk == "thick_cloak" and not run.cloak then
		run.cloak = true
		Emit(run, "cloak", slot)
		return
	end
	run.hp = run.hp - dmg
	Emit(run, "hurt", slot, dmg)
	if run.cast then
		run.cast = max(0, run.cast - PUSHBACK)
		run.pushbacks = run.pushbacks + 1
		Emit(run, "pushback", run.cast)
	end
	if run.hp <= 0 then
		run.hp = 0
		R:Die(run)
	end
end

local function FoeTick(run, f, slot)
	if f.state == "dead" then
		f.t = f.t - 1
		if f.t <= 0 then f.on = false end
		return
	end
	if f.delay > 0 then f.delay = f.delay - 1 return end
	if f.state == "walk" then
		f.x = f.x - f.def.speed / TPS
		if f.x <= f.tx then
			f.x = f.tx
			f.state, f.t = "idle", floor(Cooldown(run, f) / 2) + T(0.3)
		end
	elseif f.state == "idle" then
		f.t = f.t - 1
		if f.t <= 0 then
			local special = f.boss and (f.attacks % 3 == 2)
			local tele = special and TELE_SPECIAL or T(f.def.tele)
			local landing = run.tick + tele
			if landing < run.hitGate then
				f.t = run.hitGate - landing -- wait for the gap
			else
				run.hitGate = landing + HIT_GAP
				f.state, f.t, f.special = "tele", tele, special
				Emit(run, "tele", slot, special and 1 or 0)
			end
		end
	elseif f.state == "tele" then
		f.t = f.t - 1
		if f.t <= 0 then
			f.attacks = f.attacks + 1
			f.state, f.t = "attack", ATTACK_T
			Emit(run, "attack", slot)
			Land(run, f, slot)
		end
	elseif f.state == "attack" then
		f.t = f.t - 1
		if f.t <= 0 then f.state, f.t, f.special = "idle", Cooldown(run, f), false end
	end
end

-- ------------------------------------------------------------------ rooms
local function FightSize(run, st)
	local fl = run.floor
	if fl == 1 then return Int(st, 1, 2) end
	if fl < 4 then return 2 end
	return Int(st, 2, 3)
end

local function ZoneFoe(run, st)
	local list = Zone(run).foes
	return list[Int(st, 1, #list)]
end

local function StartRoom(run)
	local room = run.room
	local kind = room.kind
	local st = Seed(run.rngRoom, run.seed, K_ROOM, run.floor, room.door)
	Seed(run.rngFight, run.seed, K_FIGHT, run.floor, room.door)
	run.resume = nil
	if kind == "fight" then
		local n = FightSize(run, st)
		for i = 1, n do Spawn(run, ZoneFoe(run, st), (i - 1) * T(0.8)) end
		SetPhase(run, "fight")
	elseif kind == "elite" then
		Spawn(run, ZoneFoe(run, st), 0, true)
		if run.floor >= 4 then Spawn(run, ZoneFoe(run, st), T(1.2)) end
		SetPhase(run, "fight")
	elseif kind == "boss" then
		run.bossFight = true
		Spawn(run, Zone(run).boss, 0)
		SetPhase(run, "fight")
	elseif kind == "chest" then
		room.tier = (run.floor >= 10) and "gilded" or (run.floor >= 5) and "iron" or "wood"
		local zid = Zone(run).id
		room.mimic = (zid == "cellars" or zid == "rift") and Rnd(st) < MIMIC_CHANCE
		room.opened = false
		SetPhase(run, "chest")
	elseif kind == "shrine" then
		room.used = false
		room.shrine = R.SHRINES[Int(st, 1, 3)]
		SetPhase(run, "shrine")
	elseif kind == "trap" then
		room.dmg = 14 + 2 * run.floor
		room.trap = R.TRAPS[Int(st, 1, 3)]
		if run.perk == "lantern" then
			Emit(run, "disarm")
			GiveDrop(run, RollItem(run, st, 0))
			SetPhase(run, "clear")
		else
			run.trapT = T(0.8)
			Emit(run, "trapwarn")
			SetPhase(run, "trap")
		end
	end
	if room.mimic and run.perk == "lantern" then Emit(run, "mimicspotted") end
end

function R:Door(run, i)
	if run.phase ~= "doors" or not run.doors[i] or not run.doors[i].kind or i > run.ndoors then return false end
	Log(run, 3, i)
	local d = run.doors[i]
	local kind = d.kind == "unknown" and d.hidden or d.kind
	run.room = run.room or {}
	local room = run.room
	room.kind, room.door, room.tier, room.mimic, room.opened, room.used, room.shrine, room.trap = kind, i, nil, false, false, false, nil, nil
	run.bossFight = false
	run.stats.struck = false
	run.stats.castFromFight = false
	run.enterT = ENTER_T
	Emit(run, "door", i, kind)
	SetPhase(run, "enter")
	return true
end

function R:Open(run)
	local room = run.room
	if run.phase ~= "chest" or room.opened then return false end
	Log(run, 5)
	room.opened = true
	if room.mimic then
		Emit(run, "mimic")
		local f = Spawn(run, "cask_mimic", 0, run.floor >= 2)
		if f then f.x = f.tx f.state, f.t = "idle", T(0.6) end
		room.kind = "fight"
		SetPhase(run, "fight")
		return true
	end
	local n = (room.tier == "gilded") and 4 or (room.tier == "iron") and 3 or 2
	local bump = (room.tier == "wood") and 0 or 1
	Emit(run, "chest", room.tier)
	for _ = 1, n do GiveDrop(run, RollItem(run, run.rngRoom, bump)) end
	SetPhase(run, "clear")
	return true
end

R.SHRINES = { "heal", "blessing", "gamble" }
R.TRAPS = { "spikes", "gas", "falling_stone" }
-- a shrine offers one thing: "use" takes it, "leave" walks past
function R:Shrine(run, choice)
	local room = run.room
	if run.phase ~= "shrine" or room.used or (choice ~= "use" and choice ~= "leave") then return false end
	Log(run, 6, choice == "use" and 1 or 2)
	room.used = true
	if choice == "leave" then
		Emit(run, "shrineleft")
	elseif room.shrine == "heal" then
		run.hp = min(R.MAX_HP, run.hp + 50)
		Emit(run, "heal", 50)
	elseif room.shrine == "blessing" then
		run.bless = 3
		Emit(run, "bless")
	else
		if Rnd(run.rngRoom) < 0.5 then
			Emit(run, "gamble", 1)
			GiveDrop(run, RollItem(run, run.rngRoom, 1))
		else
			local loss = min(run.hp - 1, 20)
			run.hp = run.hp - loss
			Emit(run, "gamble", 0, loss)
		end
	end
	SetPhase(run, "clear")
	return true
end

-- walk past a chest without opening it
function R:Skip(run)
	if run.phase ~= "chest" or run.room.opened or run.cast then return false end
	Log(run, 10)
	run.room.opened = true
	Emit(run, "skip")
	SetPhase(run, "clear")
	return true
end

function R:Take(run, i, swap)
	local it = run.pending[i]
	if not it or run.cast or run.phase == "dead" or run.phase == "home" then return false end
	if #run.bag >= run.bagMax then
		if not swap or not run.bag[swap] then return false end
		Log(run, 7, i, swap)
		local old = run.bag[swap]
		run.bag[swap] = it
		table.remove(run.pending, i)
		Emit(run, "swap", it, old)
		return true
	end
	Log(run, 7, i, 0)
	run.bag[#run.bag + 1] = it
	table.remove(run.pending, i)
	Emit(run, "take", it)
	return true
end

function R:Leave(run, i)
	if not run.pending[i] then return false end
	Log(run, 8, i)
	table.remove(run.pending, i)
	Emit(run, "leave")
	return true
end

function R:Next(run)
	if run.phase ~= "clear" or run.cast then return false end
	Log(run, 9)
	for i = #run.pending, 1, -1 do run.pending[i] = nil end
	run.stats.floorsCleared = run.stats.floorsCleared + 1
	run.floor = run.floor + 1
	run.deepest = max(run.deepest, run.floor)
	if run.bless > 0 then run.bless = run.bless - 1 end
	run.hp = min(R.MAX_HP, run.hp + REST_HEAL)
	run.bossFight = false
	Emit(run, "floor", run.floor)
	R:MakeDoors(run)
	return true
end

-- ------------------------------------------------------------------ the hearth
local CASTABLE = { doors = true, enter = true, fight = true, chest = true, shrine = true, trap = true, clear = true }
function R:Hearth(run)
	if not CASTABLE[run.phase] then return false end
	Log(run, 4)
	if run.cast then
		run.cast = nil
		Emit(run, "castoff")
		return true
	end
	run.cast, run.cloak, run.castPaused = 0, false, false
	run.pushbacks = 0
	run.spawnT = R:SpawnEvery(run)
	if run.phase == "fight" and Alive(run) > 0 and run.room and run.room.kind ~= "boss" then
		run.stats.castFromFight = true
	end
	Emit(run, "caston")
	return true
end

function R:SpawnEvery(run)
	return T(max(1.8, 5.5 - run.floor * 0.25))
end

local function CastTick(run)
	if run.blocking then
		if not run.castPaused then run.castPaused = true Emit(run, "castpause", 1) end
	else
		if run.castPaused then run.castPaused = false Emit(run, "castpause", 0) end
		run.cast = run.cast + 1
		if run.cast % TPS == 0 then Emit(run, "castsec", run.cast / TPS) end
		if run.cast >= CAST_T then
			R:Home(run)
			return
		end
	end
	run.spawnT = run.spawnT - 1
	if run.spawnT <= 0 then
		run.spawnT = R:SpawnEvery(run)
		if Alive(run) < MAX_FOES then
			if run.phase ~= "fight" then run.resume = run.resume or run.phase SetPhase(run, "fight") end
			Spawn(run, ZoneFoe(run, run.rngFight), 0)
		end
	end
end

function R:Home(run)
	run.cast = nil
	run.banked = BagValue(run)
	for i = 1, MAX_FOES do run.foes[i].on = false end
	Emit(run, "home", run.banked)
	SetPhase(run, "home")
end

function R:Die(run)
	run.cast = nil
	run.banked = 0
	Emit(run, "dead", BagValue(run))
	SetPhase(run, "dead")
end

-- ------------------------------------------------------------------ input
function R:Hold(run, key, on)
	on = on and true or false
	if key == "block" then
		if run.blockHeld == on then return false end
		Log(run, 1, on and 1 or 0)
		run.blockHeld = on
	elseif key == "strike" then
		if run.strikeHeld == on then return false end
		Log(run, 2, on and 1 or 0)
		run.strikeHeld = on
	else
		return false
	end
	return true
end

-- ------------------------------------------------------------------ the tick
function R:Tick(run)
	local ph = run.phase
	if ph == "home" or ph == "dead" then return end
	run.tick = run.tick + 1

	-- guard and stamina
	if run.broken and run.sta >= GUARD_BACK then
		run.broken = false
		Emit(run, "guardback")
	end
	local blocking = run.blockHeld and not run.broken
	if blocking then
		run.sta = run.sta - BLOCK_DRAIN
		if run.sta <= 0 then
			run.sta, run.broken, blocking = 0, true, false
			Emit(run, "guardbreak", 0)
		end
		run.regenT = REGEN_WAIT
	elseif run.regenT > 0 then
		run.regenT = run.regenT - 1
	else
		run.sta = min(R.MAX_STA, run.sta + STA_REGEN)
	end
	if blocking ~= run.blocking then
		run.blocking = blocking
		Emit(run, "block", blocking and 1 or 0)
	end

	if ph == "enter" then
		run.enterT = run.enterT - 1
		if run.enterT <= 0 then StartRoom(run) end
	elseif ph == "trap" then
		run.trapT = run.trapT - 1
		if run.trapT <= 0 then
			local dmg = run.room.dmg
			if run.blocking then dmg = floor(dmg * 0.4 + 0.5) end
			run.hp = run.hp - dmg
			Emit(run, "trap", dmg, run.blocking and 1 or 0)
			if run.hp <= 0 then run.hp = 0 R:Die(run) return end
			GiveDrop(run, RollItem(run, run.rngRoom, 0))
			SetPhase(run, "clear")
		end
	end

	-- the hero's swing
	if run.swing > 0 then run.swing = run.swing - 1 end
	if run.strikeHeld and not run.blocking and not run.cast and run.swing == 0 and run.phase == "fight" then
		local f, slot = FirstTarget(run)
		if f then
			run.swing = run.strikeT
			run.stats.struck = true
			local dmg = STRIKE_DMG * (1 + R.HERO_GROW * (run.floor - 1))
			if run.bless > 0 then dmg = dmg * 1.5 end
			dmg = floor(dmg + 0.5)
			f.hp = f.hp - dmg
			Emit(run, "strike", slot, dmg)
			if f.hp <= 0 then f.hp = 0 Kill(run, f, slot) end
		end
	end

	-- creatures
	for i = 1, MAX_FOES do
		local f = run.foes[i]
		if f.on then FoeTick(run, f, i) end
		if run.phase == "dead" then return end
	end
	-- a melee creature that is standing still steps up into a free slot in front of it
	for i = 2, MAX_FOES do
		local f, front = run.foes[i], run.foes[i - 1]
		if f.on and not front.on and f.state == "idle" and not f.def.ranged then
			run.foes[i - 1], run.foes[i] = f, front
			f.slot, front.slot = i - 1, i
			f.tx = (f.boss or run.bossFight) and BOSS_SLOTS[i - 1] or SLOTS[i - 1]
			f.state = "walk"
			Emit(run, "step", i - 1, i)
		end
	end

	if run.cast then
		CastTick(run)
		if run.phase == "home" then return end
	end

	-- the room is won
	if run.phase == "fight" and not run.cast and Alive(run) == 0 then
		local back = run.resume
		run.resume = nil
		if back and back ~= "fight" and back ~= "enter" then
			SetPhase(run, back)
		else
			SetPhase(run, "clear")
		end
		Emit(run, "won")
	end
end

-- ------------------------------------------------------------------ replay
-- log: the flat list run.log ({ tick, code, a, b } * n). ticks: how far to run (default: until the run ends)
local SHRINE = { "use", "leave" }
local function Apply(run, code, a, b)
	if code == 1 then R:Hold(run, "block", a == 1)
	elseif code == 2 then R:Hold(run, "strike", a == 1)
	elseif code == 3 then R:Door(run, a)
	elseif code == 4 then R:Hearth(run)
	elseif code == 5 then R:Open(run)
	elseif code == 6 then R:Shrine(run, SHRINE[a])
	elseif code == 7 then R:Take(run, a, b ~= 0 and b or nil)
	elseif code == 8 then R:Leave(run, a)
	elseif code == 9 then R:Next(run)
	elseif code == 10 then R:Skip(run)
	end
end

function R:Replay(seed, perkId, log, ticks)
	local run = R:NewRun(seed, perkId)
	local n, i = #log, 1
	local limit = ticks or 30 * 60 * 120
	while true do
		while i <= n and log[i] == run.tick do
			Apply(run, log[i + 1], log[i + 2], log[i + 3])
			i = i + 4
		end
		if run.phase == "home" or run.phase == "dead" or run.tick >= limit then break end
		if i > n and ticks == nil and run.phase ~= "fight" and run.phase ~= "enter" and run.phase ~= "trap" and not run.cast then break end
		R:Tick(run)
		R:Drain(run)
	end
	return run
end

-- the same replay a slice at a time (the shared scores check other players' dives without a frame spike):
--   st = R:ReplayStart(seed, perk, log);  repeat done = R:ReplayStep(st, ticks) until done;  st.run
-- A dive that has used up its inputs gets two more minutes to finish its cast, then it is given up.
function R:ReplayStart(seed, perkId, log)
	local last = #log >= 4 and log[#log - 3] or 0
	return { run = R:NewRun(seed, perkId), log = log, i = 1, n = #log, limit = last + 30 * 120 }
end

function R:ReplayStep(st, ticks)
	local run, log = st.run, st.log
	for _ = 1, ticks do
		while st.i <= st.n and log[st.i] == run.tick do
			Apply(run, log[st.i + 1], log[st.i + 2], log[st.i + 3])
			st.i = st.i + 4
		end
		if st.i <= st.n and log[st.i] < run.tick then return true end      -- out of order: not a real log
		if run.phase == "home" or run.phase == "dead" or run.tick >= st.limit then return true end
		R:Tick(run)
		R:Drain(run)
	end
	return false
end

-- ------------------------------------------------------------------ the input log as text
-- For the shared daily scores: each input is its tick distance from the one before (base 32, digits 0-9 a-v)
-- then one capital letter and, for some, fixed-width arguments:
--   B/C guard on/off, S/R strike on/off, D<door>, H hearth, O open, U/W shrine use/leave, T<find><slot>
--   (base 36, slot 0 = no swap), L<find>, N next floor, K walk past the chest
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function C36(n) return B36:sub(n + 1, n + 1) end
local function N36(c) local i = B36:find(c, 1, true) return i and i - 1 end
local function D32(n)
	if n == 0 then return "0" end
	local out = ""
	while n > 0 do local d = n % 32 out = B36:sub(d + 1, d + 1) .. out n = floor(n / 32) end
	return out
end

function R:Encode(log)
	local parts, prev = {}, 0
	for i = 1, #log, 4 do
		local t, code, a, b = log[i], log[i + 1], log[i + 2], log[i + 3]
		local c
		if code == 1 then c = a == 1 and "B" or "C"
		elseif code == 2 then c = a == 1 and "S" or "R"
		elseif code == 3 then c = "D" .. C36(a)
		elseif code == 4 then c = "H"
		elseif code == 5 then c = "O"
		elseif code == 6 then c = a == 1 and "U" or "W"
		elseif code == 7 then c = "T" .. C36(a) .. C36(b or 0)
		elseif code == 8 then c = "L" .. C36(a)
		elseif code == 9 then c = "N"
		elseif code == 10 then c = "K" end
		if c then
			parts[#parts + 1] = D32(t - prev) .. c
			prev = t
		end
	end
	return table.concat(parts)
end

local SIMPLE = { B = { 1, 1 }, C = { 1, 0 }, S = { 2, 1 }, R = { 2, 0 }, H = { 4, 0 }, O = { 5, 0 }, U = { 6, 1 }, W = { 6, 2 }, N = { 9, 0 }, K = { 10, 0 } }
-- the log back, or nil when the text is not a log
function R:Decode(str, maxInputs)
	if type(str) ~= "string" then return nil end
	local log, n, pos, t, len = {}, 0, 1, 0, #str
	maxInputs = maxInputs or 20000
	while pos <= len do
		local dstart = pos
		local d = 0
		while pos <= len do
			local ch = str:sub(pos, pos)
			local v = N36(ch)
			if not v or v >= 32 then break end
			d = d * 32 + v
			pos = pos + 1
		end
		if pos == dstart or pos > len then return nil end
		t = t + d
		local c = str:sub(pos, pos)
		pos = pos + 1
		local code, a, b
		local s = SIMPLE[c]
		if s then code, a, b = s[1], s[2], 0
		elseif c == "D" or c == "L" then
			a = N36(str:sub(pos, pos))
			pos = pos + 1
			if not a then return nil end
			code, b = (c == "D") and 3 or 8, 0
		elseif c == "T" then
			a, b = N36(str:sub(pos, pos)), N36(str:sub(pos + 1, pos + 1))
			pos = pos + 2
			if not a or not b then return nil end
			code = 7
		else
			return nil
		end
		log[n + 1], log[n + 2], log[n + 3], log[n + 4] = t, code, a, b
		n = n + 4
		if n / 4 > maxInputs then return nil end
	end
	return log
end

-- the run's score is what it banked
function R:Score(run) return run.phase == "home" and run.banked or 0 end

return R
