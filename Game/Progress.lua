--[[ Hearth & Haul - Game/Progress.lua
	This character's purse and records: the gold banked over every run (spent at the inn on looks and
	decorations), the best run, the deepest floor, which perks are open and what the inn has bought.

	  Pr:Gold()                 gold to spend
	  Pr:Best(), Pr:Deepest()   best single run's haul, deepest floor reached
	  Pr:Finish(run)            a finished run (banked or dead): returns medal, isNewBest, previousBest
	  Pr:PerkOpen(id)           a perk is open once its achievement is earned
	  Pr:Owns(kind, id)         kind "look" or "decor"
	  Pr:Buy(kind, id)          true when bought (spends the gold)
	  Pr:Look() / Pr:SetLook(id) the hero look being worn

	Medal thresholds come from the balance bot (tools/hh_bot.lua): bronze is a short careful run, silver a
	sound run that fills most of the bag, gold needs swapping finds deep past the first bosses. ]]

local _, ns = ...
local P = ns.P
local Pr = P:Module("Progress")
local D, R = ns.Data, ns.Rules

local function C() return P.char end

function Pr:Gold() local c = C() return c and c.gold or 0 end
function Pr:Best() local c = C() return c and c.best or 0 end
function Pr:Deepest() local c = C() return c and c.deepest or 0 end
function Pr:BestMedal() local c = C() return c and c.medal or 0 end
function Pr:Runs() local c = C() return c and c.runs or 0 end

function Pr:PerkOpen(id)
	local p = D.PERK[id]
	if not p then return false end
	if P.testOpen then return true end
	return P.Awards:Has(p.ach) ~= nil
end

function Pr:Owns(kind, id)
	local c = C()
	if not c then return false end
	if kind == "look" then
		local L
		for _, l in ipairs(D.LOOKS) do if l.id == id then L = l end end
		if not L then return false end
		return L.cost == 0 or (c.looks and c.looks[id]) == true
	elseif kind == "decor" then
		return (c.decor and c.decor[id]) == true
	end
	return false
end

local function Cost(kind, id)
	if kind == "look" then
		for _, l in ipairs(D.LOOKS) do if l.id == id then return l.cost end end
	elseif kind == "decor" then
		local d = D.DECOR_BY[id]
		return d and d.cost
	end
end

function Pr:Buy(kind, id)
	local c = C()
	local cost = Cost(kind, id)
	if not c or P.readOnly or not cost or self:Owns(kind, id) or (c.gold or 0) < cost then return false end
	c.gold = c.gold - cost
	local key = (kind == "look") and "looks" or "decor"
	c[key] = c[key] or {}
	c[key][id] = true
	return true
end

function Pr:Look()
	local c = C()
	local id = c and c.look
	if id and self:Owns("look", id) then return id end
	return "blue"
end

function Pr:SetLook(id)
	local c = C()
	if c and self:Owns("look", id) then c.look = id return true end
	return false
end

function Pr:Finish(run)
	local score = R:Score(run)
	local medal = D:Medal(score)
	local c = C()
	if not c or P.readOnly or run.daily then return medal, false, nil end
	c.runs = (c.runs or 0) + 1
	if run.phase == "dead" then c.deaths = (c.deaths or 0) + 1 else c.homes = (c.homes or 0) + 1 end
	c.gold = (c.gold or 0) + score
	c.deepest = math.max(c.deepest or 0, run.deepest or run.floor)
	local prev = c.best
	local newBest = false
	if score > 0 and (not prev or score > prev) then c.best = score newBest = prev ~= nil end
	if medal > (c.medal or 0) then c.medal = medal end
	return medal, newBest, prev
end
