--[[ Hearth & Haul - Game/Daily.lua
	The daily dive: one seed for every player in the world on the same date (UTC, from the realm's clock),
	so everyone meets the same doors, rooms and creatures. You pick your perk as usual. It can be dived as
	often as you like (the best counts); its records are kept apart and its gold is not added to your purse.

	  Dy:Today()              "2026-10-10", the day number
	  Dy:Seed([day])          the day's seed (the same everywhere)
	  Dy:Record([date])       this character's record for that date { best, medal, runs, deepest, perk, code } or nil
	                          (perk and code: the best dive's perk and input log, R:Encode)
	  Dy:Finish(run)          a finished daily dive: keeps the best; returns medal, isNewBest, previousBest
	  Dy:DaysPlayed()         how many different days this character has dived the daily ]]

local _, ns = ...
local P = ns.P
local Dy = P:Module("Daily")
local R, D = ns.Rules, ns.Data

local KEEP_DAYS = 60
local floor = math.floor

local function Now()
	if GetServerTime then
		local ok, t = pcall(GetServerTime)
		if ok and type(t) == "number" and t > 0 then return t end
	end
	return time and time() or 0
end

-- the UTC calendar date of a day number (days since 1970-01-01), worked out by hand so it never depends on
-- the player's time zone (Howard Hinnant's civil-from-days)
local function DateOf(day)
	local z = day + 719468
	local era = floor(z / 146097)
	local doe = z - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local mp = floor((5 * doy + 2) / 153)
	local d = doy - floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	if m <= 2 then y = y + 1 end
	return ("%04d-%02d-%02d"):format(y, m, d)
end
Dy.DateOf = DateOf

function Dy:Day() return floor(Now() / 86400) end
function Dy:Today()
	local day = self:Day()
	return DateOf(day), day
end

-- the day's seed: the day number through the rules' own mixer, the same on every machine
function Dy:Seed(day)
	day = day or self:Day()
	local st = R.Seed({}, day * 7919 + 104729, 77)
	return R.Int(st, 1, 2147483000)
end

local function Days()
	local c = P.char
	if not c then return {} end
	if type(c.daily) ~= "table" then c.daily = {} end
	return c.daily
end

function Dy:Record(date) return Days()[date or self:Today()] end

function Dy:DaysPlayed()
	local c = P.char
	return c and tonumber(c.dailyDays) or 0
end

function Dy:Finish(run)
	local date = run.daily
	local score = R:Score(run)
	local medal = D:Medal(score)
	local c = P.char
	if not c or P.readOnly or not date then return medal, false, nil end
	local days = Days()
	local r = days[date]
	if not r then
		r = { medal = 0, runs = 0 }
		days[date] = r
		c.dailyDays = (tonumber(c.dailyDays) or 0) + 1
	end
	r.runs = (r.runs or 0) + 1
	r.deepest = math.max(r.deepest or 0, run.deepest or run.floor)
	local prev = r.best
	local newBest = false
	if score > 0 and (not prev or score > prev) then
		r.best = score
		-- the dive itself, so the shared board (and a check of the saved records) can replay it
		r.perk, r.code = run.perk, R:Encode(run.log)
		newBest = prev ~= nil
		run.dailyBest = true
	end
	if medal > (r.medal or 0) then r.medal = medal end
	-- old days are let go (the count of days played stays)
	local today = self:Day()
	for d in pairs(days) do
		local y, m, dd = tostring(d):match("^(%d+)-(%d+)-(%d+)$")
		if not y then days[d] = nil
		else
			local age = today - ((tonumber(y) - 1970) * 365.25 + (tonumber(m) - 1) * 30.44 + tonumber(dd))
			if age > KEEP_DAYS + 5 then days[d] = nil end
		end
	end
	return medal, newBest, prev
end
