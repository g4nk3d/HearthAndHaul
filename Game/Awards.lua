--[[ Hearth & Haul - Game/Awards.lua
	Twelve achievements, each with its own badge (achievement_<id>). Most are decided from the finished run
	alone; the bosses are counted whether you got home or not, and Daily Diver counts daily runs played.

	  Aw.LIST                 { id, name, how } in the order the achievements screen shows them
	  Aw:Has(id)              earned by this character (the time it was earned, or nil)
	  Aw:Check(run)           a finished run: the achievements it earns now (a list, possibly empty)
	  Aw:Count()              earned, total ]]

local _, ns = ...
local P = ns.P
local Aw = P:Module("Awards")

Aw.LIST = {
	{ "first_haul", "First Haul", "Hearth home with anything in your bag. Opens the Lantern perk." },
	{ "close_call", "Close Call", "Hearth home with 10 health or less." },
	{ "greedy", "Greedy", "Hearth home with a full bag. Opens the Deep Pockets perk." },
	{ "old_thornback", "Old Thornback", "Defeat Old Thornback in the Cellars. Opens the Thick Cloak perk." },
	{ "gatewarden", "The Gatewarden", "Defeat the Gatewarden in the Old Catacombs. Opens the Quick Hands perk." },
	{ "mother_mycel", "Mother Mycel", "Defeat Mother Mycel in the Fungal Deep." },
	{ "faceted_king", "The Faceted King", "Defeat the Faceted King in the Crystal Vault." },
	{ "reach_rift", "Reach the Rift", "Reach floor 13." },
	{ "deep_diver", "Deep Diver", "Reach floor 20." },
	{ "pacifist_floor", "Pacifist Floor", "Start your hearth in a fight you have not won and get home without striking a blow on that floor." },
	{ "no_pushback", "No Pushback", "Finish a hearth cast on floor 7 or deeper without a single pushback." },
	{ "daily_diver", "Daily Diver", "Play the daily dive on 7 different days." },
}
local byId = {}
for _, a in ipairs(Aw.LIST) do byId[a[1]] = a end
Aw.byId = byId

local function Store()
	local c = P.char
	if not c then return nil end
	if type(c.ach) ~= "table" then c.ach = {} end
	return c.ach
end

function Aw:Has(id) local s = Store() return s and s[id] end

function Aw:Count()
	local s, n = Store(), 0
	if s then for _, a in ipairs(self.LIST) do if s[a[1]] then n = n + 1 end end end
	return n, #self.LIST
end

-- what a finished run proves (true/false per achievement)
function Aw.Earned(run, dailyDays)
	local got = {}
	local home = run.phase == "home"
	local st = run.stats
	if home then
		got.first_haul = #run.bag > 0
		got.close_call = run.hp <= 10
		got.greedy = #run.bag >= run.bagMax
		got.pacifist_floor = st.castFromFight and not st.struck
		got.no_pushback = run.floor >= 7 and run.pushbacks == 0
	end
	for id in pairs(st.bosses) do got[id] = true end
	got.reach_rift = (run.deepest or run.floor) >= 13
	got.deep_diver = (run.deepest or run.floor) >= 20
	got.daily_diver = (dailyDays or 0) >= 7
	return got
end

function Aw:Check(run)
	local new = {}
	local s = Store()
	if not s or P.readOnly or P.testOpen then return new end
	local got = self.Earned(run, P.Daily and P.Daily:DaysPlayed() or 0)
	local now = time and time() or 0
	for _, a in ipairs(self.LIST) do
		if got[a[1]] and not s[a[1]] then
			s[a[1]] = now
			new[#new + 1] = a
		end
	end
	return new
end
