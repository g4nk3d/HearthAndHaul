--[[ Hearth & Haul - UI/Screens.lua
	The screens over the stage, each built the first time it is shown (G.lazy): the perk pick before a
	dive, the notice board (daily dive and records), achievements, the stash (furnishings), Marga's how to
	play, the results of a dive, paused, and the first-time welcome. ]]

local _, ns = ...
local P = ns.P
local G = P.Game
local A, Au, UI, In, Pr = P.Assets, P.Audio, P.UI, P.Inn, P.Progress
local R, D = ns.Rules, ns.Data
local lazy, screens = G.lazy, G.screens
local ScreenFrame, Ribbon = G.ScreenFrame, G.Ribbon
local floor, max, min = math.floor, math.max, math.min

local function BackBtn(f, x, y, label)
	local b = UI:Wide(f, label or "Back", 170, function() G:Screen(nil) end, "ui_cancel")
	b:SetPoint("BOTTOM", f, "BOTTOM", x or 0, y or 36)
	return b
end

-- ------------------------------------------------------------------ the perk pick
local PERK_W, PERK_H = 150, 225
lazy.perk = function()
	local f = ScreenFrame("perk", 900, 540)
	f.title = Ribbon(f, "Choose a Perk")
	local sub = UI:Text(f, 13, "light")
	sub:SetPoint("TOP", 0, -48)
	sub:SetWidth(820)
	f.sub = sub
	f.cards = {}
	local list = { false }
	for _, p in ipairs(D.PERKS) do list[#list + 1] = p end
	for i, p in ipairs(list) do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(PERK_W, PERK_H)
		b:SetPoint("TOP", f, "TOP", (i - 3) * (PERK_W + 18), -86)
		b.art = b:CreateTexture(nil, "ARTWORK")
		b.art:SetAllPoints()
		b.sel = b:CreateTexture(nil, "BACKGROUND")
		b.sel:SetPoint("TOPLEFT", -6, 6)
		b.sel:SetPoint("BOTTOMRIGHT", 6, -6)
		b.sel:SetColorTexture(1, 0.8, 0.35, 0.55)
		b.sel:Hide()
		-- the card's parchment (its lower 40%) takes the words
		b.text = UI:Text(b, 10, "ink")
		b.text:SetPoint("TOP", b, "TOP", 0, -PERK_H * 0.58)
		b.text:SetWidth(PERK_W - 30)
		b.text:SetHeight(PERK_H * 0.32)
		b.text:SetJustifyV("TOP")
		b.name = UI:Text(b, 14, "title")
		b.name:SetPoint("TOP", b, "BOTTOM", 0, -6)
		b.lock = b:CreateTexture(nil, "OVERLAY")
		b.lock:SetSize(36, 36)
		b.lock:SetPoint("CENTER", b, "TOP", 0, -PERK_H * 0.3)
		A:Sprite(b.lock, "lock")
		b.how = UI:Text(b, 10, "light")
		b.how:SetPoint("TOP", b.name, "BOTTOM", 0, -2)
		b.how:SetWidth(PERK_W + 10)
		b.perk = p
		b:SetScript("OnClick", function(self)
			if self.locked then Au:Play("ui_error") return end
			Au:Play("ui_click")
			f.pick = self.perk and self.perk.id or false
			f:Refresh()
		end)
		b:SetScript("OnDoubleClick", function(self) if not self.locked then f.go:Click() end end)
		f.cards[i] = b
	end
	f.go = UI:Wide(f, "Dive!  (Enter)", 200, function()
		local daily = G.pendingDaily
		G.pendingDaily = nil
		G:Dive(f.pick or nil, daily)
	end, "ui_confirm")
	f.go:SetPoint("BOTTOM", f, "BOTTOM", 110, 36)
	BackBtn(f, -110, 36)
	function f:Refresh()
		if self.pick == nil then
			local last = P.char and P.char.perk
			self.pick = (last and Pr:PerkOpen(last)) and last or false
		end
		if self.pick and not Pr:PerkOpen(self.pick) then self.pick = false end
		self.title:SetTitle(G.pendingDaily and "Daily Dive: Choose a Perk" or "Choose a Perk")
		self.sub:SetText(G.pendingDaily and ("Today's dive (%s): the same floors, rooms and creatures for everyone. Your best counts; its gold is not added to your purse."):format(G.pendingDaily)
			or "One perk a dive. More open as you earn achievements.")
		for _, b in ipairs(self.cards) do
			local p = b.perk
			local open = not p or Pr:PerkOpen(p.id)
			b.locked = not open
			if not p then
				A:Sprite(b.art, "perk_card_back")
				b.name:SetText("No Perk")
				b.text:SetText("")
				b.how:SetText("Just you, a sword and a hearthstone.")
				b.lock:Hide()
			else
				A:Sprite(b.art, open and p.card or "perk_card_back")
				b.name:SetText(p.name)
				b.text:SetText(open and p.text or "")
				local ach = P.Awards.byId[p.ach]
				b.how:SetText(open and "" or ("Earn |cffe8c27a%s|r to open."):format(ach and ach[2] or "?"))
				b.lock:SetShown(not open)
			end
			b.art:SetDesaturated(not open)
			local mine = (p and p.id or false) == self.pick
			b.sel:SetShown(mine)
			b.art:SetAlpha((mine or not open) and 1 or 0.8)
		end
	end
end

-- ------------------------------------------------------------------ the notice board: daily dive and records
lazy.board = function()
	local f = ScreenFrame("board", 940, 580)
	Ribbon(f, "The Notice Board")
	local nb = f:CreateTexture(nil, "ARTWORK")
	A:Sprite(nb, "notice_board")
	nb:SetSize(250, 250)
	nb:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -60)
	-- today's notice, on the board's big middle paper only (measured on the art: x 102..159, y 77..170 of 256):
	-- dark ink in the carved title face, short enough to stay on the paper
	f.notice = UI:Text(f, 13, "ink")
	local font = "Fonts\\MORPHEUS.TTF"
	if not f.notice:SetFont(font, 14, "") then f.notice:SetFont("Fonts\\FRIZQT__.TTF", 13, "") end
	f.notice:SetTextColor(0.16, 0.09, 0.03)
	f.notice:SetShadowOffset(0, 0)
	f.notice:SetPoint("CENTER", nb, "TOPLEFT", 130.5 / 256 * 250, -118 / 256 * 250)
	f.notice:SetWidth(57 / 256 * 250)
	f.notice:SetSpacing(6)
	f.daily = UI:Wide(f, "Dive the Daily", 220, function()
		G.pendingDaily = P.Daily:Today()
		G:Screen("perk")
	end, "ui_confirm")
	f.daily:SetPoint("TOP", nb, "BOTTOM", 0, -10)
	f.dailyText = UI:Text(f, 12, "light")
	f.dailyText:SetPoint("TOP", f.daily, "BOTTOM", 0, -8)
	f.dailyText:SetWidth(260)
	f.dailyText:SetSpacing(3)
	-- the records
	local head = UI:Text(f, 18, "title", "LEFT")
	head:SetPoint("TOPLEFT", f, "TOPLEFT", 320, -66)
	head:SetText("Your Records")
	f.rec = UI:Text(f, 13, "light", "LEFT")
	f.rec:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -10)
	f.rec:SetWidth(270)
	f.rec:SetSpacing(5)
	f.medal = f:CreateTexture(nil, "ARTWORK")
	f.medal:SetSize(56, 56)
	f.medal:SetPoint("LEFT", head, "RIGHT", 10, -4)
	local ach = UI:Wide(f, "Achievements", 200, function() G:Screen("achievements") end)
	ach:SetPoint("TOPLEFT", f.rec, "BOTTOMLEFT", 0, -16)
	-- today's shared board (the best hauls other players' games have checked by replaying them)
	local th = UI:Text(f, 18, "title", "LEFT")
	th:SetPoint("TOPLEFT", f, "TOPLEFT", 630, -66)
	th:SetText("Today's Best Hauls")
	f.top = UI:Text(f, 12, "light", "LEFT")
	f.top:SetPoint("TOPLEFT", th, "BOTTOMLEFT", 0, -10)
	f.top:SetWidth(270)
	f.top:SetSpacing(4)
	P:Register("LEADERBOARD_CHANGED", function() if G.screen == "board" then P:Safe("board", f.Refresh, f) end end)
	BackBtn(f)
	function f:Refresh()
		local date = P.Daily:Today()
		local rec = P.Daily:Record(date)
		local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
		local mo, dd = date:match("^%d+%-(%d+)%-(%d+)$")
		self.notice:SetText(("Daily\nDive\n%s %d"):format(MONTHS[tonumber(mo)] or "", tonumber(dd) or 0))
		if rec and rec.best then
			self.dailyText:SetText(("Your best today: |cffe8c27a%d gold|r (%s)\nDeepest today: floor %d   ·   Dives today: %d"):format(
				rec.best, D.MEDAL_NAME[rec.medal or 0], rec.deepest or 0, rec.runs or 0))
		elseif rec then
			self.dailyText:SetText(("Nothing banked yet today (dives: %d)."):format(rec.runs or 0))
		else
			self.dailyText:SetText("You haven't dived today's daily yet.")
		end
		self.dailyText:SetText("The same floors for every adventurer today.\n" .. self.dailyText:GetText())
		self.dailyText:SetText(self.dailyText:GetText() .. ("\n|cffb8a888Days dived: %d|r"):format(P.Daily:DaysPlayed()))
		local c = P.char or {}
		local got, all = P.Awards:Count()
		self.rec:SetText(("Purse: |cffe8c27a%d gold|r\nBest haul: %s\nDeepest floor: %s\nDives: %d   (home %d, fallen %d)\nBest medal: %s\nAchievements: %d of %d\n\n|cffb8a888Medals for one dive's haul: bronze %d, silver %d, gold %d gold.|r"):format(
			Pr:Gold(), Pr:Best() > 0 and (Pr:Best() .. " gold") or "none yet", Pr:Deepest() > 0 and tostring(Pr:Deepest()) or "-",
			c.runs or 0, c.homes or 0, c.deaths or 0, D.MEDAL_NAME[Pr:BestMedal()], got, all, D.MEDALS[1], D.MEDALS[2], D.MEDALS[3]))
		A:Sprite(self.medal, G.MedalSprite(Pr:BestMedal()))
		local LB = P.Leaderboard
		local list = LB and LB:Board(LB:BoardId(date)) or {}
		local out = {}
		for i = 1, math.min(10, #list) do
			local e = list[i]
			local perk = e.p and D.PERK[e.p] and D.PERK[e.p].name
			out[#out + 1] = ("%d.  %s  |cffe8c27a%d g|r%s%s"):format(i, e.who:match("^([^%-]+)") or e.who, e.s,
				perk and ("  |cffb8a888" .. perk .. "|r") or "", e.who == LB.me and "  |cff7fff7f(you)|r" or "")
		end
		if not (LB and LB:Enabled()) then out[#out + 1] = "|cffb8a888Sharing scores is off (Settings).|r"
		elseif #list == 0 then out[#out + 1] = "|cffb8a888No hauls heard yet today. Dive the daily and yours goes up first.|r" end
		if LB and LB:Pending() > 0 then out[#out + 1] = ("|cffb8a888Checking %d haul%s...|r"):format(LB:Pending(), LB:Pending() == 1 and "" or "s") end
		self.top:SetText(table.concat(out, "\n"))
	end
end

-- ------------------------------------------------------------------ achievements
lazy.achievements = function()
	local f = ScreenFrame("achievements", 900, 600)
	Ribbon(f, "Achievements")
	f.cells = {}
	for i, a in ipairs(P.Awards.LIST) do
		local c = CreateFrame("Frame", nil, f)
		c:SetSize(200, 150)
		c:SetPoint("TOP", f, "TOP", ((i - 1) % 4 - 1.5) * 210, -50 - floor((i - 1) / 4) * 152)
		c.frame = c:CreateTexture(nil, "ARTWORK", nil, 0)
		c.frame:SetSize(80, 80)
		c.frame:SetPoint("TOP", 0, -2)
		c.badge = c:CreateTexture(nil, "ARTWORK", nil, 1)
		c.badge:SetSize(66, 66)
		c.badge:SetPoint("CENTER", c.frame, "CENTER")
		A:Sprite(c.badge, "achievement_" .. a[1])
		c.name = UI:Text(c, 13, "title")
		c.name:SetPoint("TOP", c.frame, "BOTTOM", 0, -2)
		c.name:SetWidth(196)
		c.name:SetText(a[2])
		c.how = UI:Text(c, 10, "light")
		c.how:SetPoint("TOP", c.name, "BOTTOM", 0, -2)
		c.how:SetWidth(190)
		c.how:SetText(a[3])
		c.id = a[1]
		f.cells[i] = c
	end
	f.count = UI:Text(f, 12, "light")
	f.count:SetPoint("BOTTOM", 0, 84)
	BackBtn(f)
	function f:Refresh()
		for _, c in ipairs(self.cells) do
			local has = P.Awards:Has(c.id)
			A:Sprite(c.frame, has and "badge_frame_earned" or "badge_frame_locked")
			c.badge:SetDesaturated(not has)
			c.badge:SetAlpha(has and 1 or 0.45)
			c.name:SetAlpha(has and 1 or 0.6)
		end
		local got, all = P.Awards:Count()
		self.count:SetText(("%d of %d earned"):format(got, all))
	end
end

-- ------------------------------------------------------------------ the stash: furnishings
lazy.stash = function()
	local f = ScreenFrame("stash", 880, 580)
	Ribbon(f, "The Stash")
	f.purse = UI:Text(f, 15, "title")
	f.purse:SetPoint("TOP", 0, -48)
	f.cells = {}
	for i, d in ipairs(D.DECOR) do
		-- each furnishing is its own small card: picture, name, price and its Buy button together
		local c = CreateFrame("Frame", nil, f)
		c:SetSize(200, 116)
		c:SetPoint("TOP", f, "TOP", ((i - 1) % 4 - 1.5) * 206, -74 - floor((i - 1) / 4) * 124)
		UI:Slice9(c, "BACKGROUND", 1, "inner_panel", 22, 64)
		c.icon = c:CreateTexture(nil, "ARTWORK")
		c.icon:SetSize(64, 64)
		c.icon:SetPoint("LEFT", 14, 0)
		A:Sprite(c.icon, d.sprite)
		c.name = UI:Text(c, 12, "title", "LEFT")
		c.name:SetPoint("TOPLEFT", c, "TOPLEFT", 86, -16)
		c.name:SetWidth(104)
		c.name:SetText(d.name)
		c.cost = UI:Text(c, 11, "light", "LEFT")
		c.cost:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -3)
		c.buy = UI:Wide(c, "Buy", 104, function()
			if Pr:Buy("decor", d.id) then
				Au:Play("bank_gold")
				In:Refresh()
				In:Coins()
				f:Refresh()
				P.HUD:Inn(Pr:Gold())
			else
				Au:Play("ui_error")
			end
		end, "ui_confirm")
		c.buy:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 84, 12)
		UI:Tip(c.buy, function() return ("Buy the %s"):format(d.name), ("%d gold. It goes up in the inn straight away."):format(d.cost) end)
		c.d = d
		f.cells[i] = c
	end
	local note = UI:Text(f, 11, "light")
	note:SetPoint("BOTTOM", 0, 86)
	note:SetWidth(760)
	note:SetText("Furnishings are for the look of the inn only. Banked gold from your dives pays for them (daily dives don't fill the purse).")
	BackBtn(f)
	function f:Refresh()
		local gold = Pr:Gold()
		self.purse:SetText(("Your purse: %d gold"):format(gold))
		for _, c in ipairs(self.cells) do
			local own = Pr:Owns("decor", c.d.id)
			c.cost:SetText(own and "|cff7fff7fIn the inn|r" or ("%d gold"):format(c.d.cost))
			c.buy:SetShown(not own)
			c.buy:SetEnabled(gold >= c.d.cost and not P.readOnly)
			c.icon:SetDesaturated(not own and gold < c.d.cost)
		end
	end
end

-- ------------------------------------------------------------------ Marga explains
local HELP = {
	{ "marga_portrait_happy", "Welcome to the Sleeping Gryphon",
		"Under my cellar is the Undercroft, love. Folk go down with an empty bag and come back up with treasure, if they come back up. Take the stairs (click them, or Enter), pick a door on each floor, and fill your bag." },
	{ "marga_portrait_worried", "Fighting",
		"Hold |cffe8c27aF|r (or the left mouse button) to swing. Watch for the red glow: that's a creature winding up. Hold |cffe8c27aSpace|r (or the right mouse button) to guard. Guarding costs stamina, and blocked hits cost more; run dry and your guard breaks until you catch your breath." },
	{ "marga_portrait_happy", "Doors and rooms",
		"Three doors a floor: fights, elites, chests, shrines, traps, or a door you can't read. Every third floor a guardian blocks the way. Finds land on the floor: click to take, right-click to leave. A full bag means choosing what to drop." },
	{ "marga_portrait_worried", "Getting home",
		"Press |cffe8c27aH|r to cast your hearthstone: ten seconds, and the light draws creatures to you. Every hit that gets through knocks your cast back a second; guarding holds the cast still. Fall down there and the bag is lost. Get home and every coin is banked." },
	{ "marga_portrait_cheering", "Perks, medals and the daily dive",
		"Achievements open perks for your next dives. A dive's haul earns bronze, silver or gold. The notice board has the daily dive: the same floors for everyone, once a day. Banked gold buys furnishings for my inn. I do like a nice rug." },
}
lazy.help = function()
	local h = ScreenFrame("help", 720, 460)
	Ribbon(h, "Marga Explains")
	h.port = h:CreateTexture(nil, "ARTWORK")
	h.port:SetSize(150, 150)
	h.port:SetPoint("TOPLEFT", 36, -64)
	h.head = UI:Text(h, 18, "title", "LEFT")
	h.head:SetPoint("TOPLEFT", h.port, "TOPRIGHT", 22, -4)
	h.head:SetWidth(480)
	h.text = UI:Text(h, 13, "light", "LEFT")
	h.text:SetPoint("TOPLEFT", h.head, "BOTTOMLEFT", 0, -10)
	h.text:SetWidth(480)
	h.text:SetSpacing(4)
	h.page = UI:Text(h, 11, "light")
	h.page:SetPoint("BOTTOM", 0, 84)
	h.prev = UI:Wide(h, "Previous", 150, function() h.at = max(1, h.at - 1) h:Show2() end)
	h.prev:SetPoint("BOTTOM", h, "BOTTOM", -170, 36)
	BackBtn(h, 0, 36)
	h.next = UI:Wide(h, "Next", 150, function() h.at = min(#HELP, h.at + 1) h:Show2() end)
	h.next:SetPoint("BOTTOM", h, "BOTTOM", 170, 36)
	h.at = 1
	function h:Show2()
		local pg = HELP[self.at]
		A:Sprite(self.port, pg[1])
		self.head:SetText(pg[2])
		self.text:SetText(pg[3])
		self.page:SetText(("%d / %d"):format(self.at, #HELP))
		self.prev:SetEnabled(self.at > 1)
		self.next:SetEnabled(self.at < #HELP)
	end
	function h:Refresh() self.at = 1 self:Show2() end
end

-- ------------------------------------------------------------------ the results of a dive
-- run_summary's live parts (measured on the 504 px art): three stat wells and a 5 x 2 grid of slots
local RS = 440
local RS_K = RS / 504
local STAT_X, STAT_Y = { 156, 276, 391 }, 192
local SLOT_X, SLOT_Y, SLOT_S = { 111, 180, 250, 320, 390 }, { 270, 335 }, 50
lazy.results = function()
	local r = ScreenFrame("results", 960, 650, true)
	local bg = r:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0)
	r.title = Ribbon(r, "Home Safe", -2)
	local sum = r:CreateTexture(nil, "ARTWORK", nil, 0)
	A:Sprite(sum, "run_summary")
	sum:SetSize(RS, RS)
	sum:SetPoint("TOPLEFT", r, "TOPLEFT", 30, -84)
	r.stats = {}
	for i = 1, 3 do
		local fs = UI:Text(r, 15, "ink")
		fs:SetPoint("CENTER", sum, "TOPLEFT", (STAT_X[i] + 12) * RS_K, -STAT_Y * RS_K)
		r.stats[i] = fs
	end
	r.slots = {}
	for row = 1, 2 do
		for col = 1, 5 do
			local b = CreateFrame("Frame", nil, r)
			b:SetSize(SLOT_S * RS_K, SLOT_S * RS_K)
			b:SetPoint("CENTER", sum, "TOPLEFT", SLOT_X[col] * RS_K, -SLOT_Y[row] * RS_K)
			b.icon = b:CreateTexture(nil, "ARTWORK", nil, 2)
			b.icon:SetAllPoints()
			b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			b:EnableMouse(true)
			UI:Tip(b, function(self) return P.HUD:ItemTip(self.item) end)
			r.slots[#r.slots + 1] = b
		end
	end
	r.more = UI:Text(r, 12, "ink")
	r.more:SetPoint("CENTER", sum, "TOPLEFT", 225 * RS_K, -420 * RS_K)
	-- the right column
	r.pic = r:CreateTexture(nil, "ARTWORK")
	r.pic:SetSize(420, 210)
	r.pic:SetPoint("TOPRIGHT", r, "TOPRIGHT", -30, -70)
	r.medal = r:CreateTexture(nil, "ARTWORK", nil, 3)
	r.medal:SetSize(90, 90)
	r.medal:SetPoint("TOPRIGHT", r.pic, "BOTTOMRIGHT", -10, 4)
	r.headline = UI:Text(r, 22, "title", "LEFT")
	r.headline:SetPoint("TOPLEFT", r.pic, "BOTTOMLEFT", 10, -8)
	r.headline:SetWidth(310)
	r.line = UI:Text(r, 13, "light", "LEFT")
	r.line:SetPoint("TOPLEFT", r.headline, "BOTTOMLEFT", 0, -8)
	r.line:SetWidth(310)
	r.line:SetSpacing(4)
	r.badges = {}
	for i = 1, 5 do
		local b = CreateFrame("Frame", nil, r)
		b:SetSize(52, 52)
		b:SetPoint("TOPLEFT", r.pic, "BOTTOMLEFT", 10 + (i - 1) * 60, -190)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b:EnableMouse(true)
		UI:Tip(b, function(self) if self.a then return self.a[2], "Achievement earned: " .. self.a[3] end end)
		b:Hide()
		r.badges[i] = b
	end
	r.inn = UI:Wide(r, "Back to the Inn  (Enter)", 230, function()
		local run = G.run
		G:ToInn(run and run.phase == "home" and "banked" or "dead")
	end, "ui_confirm")
	r.inn:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -270, 30)
	r.again = UI:Wide(r, "Dive Again", 200, function()
		local run = G.run
		local daily = run and run.daily
		local perk = run and run.perk
		G:ToInn(nil)
		if daily then G.pendingDaily = daily end
		G:Screen("perk")
		if screens.perk then screens.perk.pick = perk or false screens.perk:Refresh() end
	end)
	r.again:SetPoint("LEFT", r.inn, "RIGHT", 16, 0)
	function r:Refresh()
		local run = G.run
		if not run then return end
		local home = run.phase == "home"
		self.title:SetTitle(home and (run.daily and "Daily Dive: Home Safe" or "Home Safe") or (run.daily and "Daily Dive: Fallen" or "Fallen in the Deep"))
		A:Sprite(self.pic, home and "banked_screen" or "death_screen")
		-- the bag, best finds first
		local list = {}
		for i, it in ipairs(run.bag) do list[i] = it end
		table.sort(list, function(a, b) return a.value > b.value end)
		local bv = R:BagValue(run)
		self.stats[1]:SetText(("%d"):format(#run.bag))
		self.stats[2]:SetText(("%d"):format(run.floor))
		self.stats[3]:SetText(home and ("%d"):format(run.banked) or "0")
		for i, b in ipairs(self.slots) do
			local it = list[i]
			b.item = it
			if it then
				b.icon:SetTexture(it.icon)
				b.icon:SetDesaturated(not home)
				b.icon:SetAlpha(home and 1 or 0.5)
				b.icon:Show()
			else
				b.icon:Hide()
			end
		end
		self.more:SetText(#list > 10 and ("and %d more"):format(#list - 10) or "")
		local medal = run.medal or 0
		A:Sprite(self.medal, G.MedalSprite(medal))
		self.headline:SetText(home and ("%d gold banked"):format(run.banked) or "The bag is lost")
		local lines = {}
		if home then
			lines[#lines + 1] = medal > 0 and ("|cffe8c27a%s medal.|r"):format(D.MEDAL_NAME[medal]:gsub("^%l", string.upper)) or ("Bronze at %d gold."):format(D.MEDALS[1])
			if run.newBest then lines[#lines + 1] = ("|cff7fff7fNew best haul!|r (was %d)"):format(run.prevBest or 0) end
			if not run.daily then lines[#lines + 1] = ("Purse: %d gold"):format(Pr:Gold()) end
		else
			lines[#lines + 1] = ("You fell on floor %d with %d gold in the bag."):format(run.floor, bv)
			lines[#lines + 1] = "Marga will keep a candle in the window."
		end
		if medal < 3 and home then lines[#lines + 1] = ("Silver at %d, gold at %d."):format(D.MEDALS[2], D.MEDALS[3]) end
		if run.daily then lines[#lines + 1] = ("|cffb8a888Daily dive %s: not added to your purse.|r"):format(run.daily) end
		if P.testOpen then lines[#lines + 1] = "|cffaaaaaaTest mode: nothing was saved.|r" end
		self.line:SetText(table.concat(lines, "\n"))
		for i, b in ipairs(self.badges) do
			local a = run.awards and run.awards[i]
			b.a = a
			if a then A:Sprite(b.tex, "achievement_" .. a[1]) b:Show() else b:Hide() end
		end
		if run.awards and #run.awards > 0 then Au:Play("ui_achievement") end
	end
end

-- ------------------------------------------------------------------ paused
lazy.paused = function()
	local pz = ScreenFrame("paused", 500, 280)
	Ribbon(pz, "Paused")
	pz.text = UI:Text(pz, 14, "light")
	pz.text:SetPoint("TOP", 0, -60)
	pz.text:SetWidth(420)
	pz.text:SetSpacing(3)
	pz.resume = UI:Wide(pz, "Resume", 180, function()
		if InCombatLockdown and InCombatLockdown() then Au:Play("ui_error") return end
		G:Screen(nil)
		G:Keyboard(true)
	end, "ui_confirm")
	pz.resume:SetPoint("BOTTOM", 100, 36)
	pz.quit = UI:Wide(pz, "Give Up the Dive", 180, function()
		if G.mode ~= "dive" then G:Screen(nil) return end
		G:Abandon()
	end, "ui_cancel")
	pz.quit:SetPoint("BOTTOM", -100, 36)
	UI:Tip(pz.quit, "Give up the dive", "You fall where you stand: the bag is lost.")
	function pz:Refresh() self.quit:SetShown(G.mode == "dive") end
end

-- ------------------------------------------------------------------ the first time
lazy.welcome = function()
	local w = ScreenFrame("welcome", 660, 420)
	Ribbon(w, "Welcome to the Sleeping Gryphon")
	local port = w:CreateTexture(nil, "ARTWORK")
	A:Sprite(port, "marga_portrait_happy")
	port:SetSize(140, 140)
	port:SetPoint("TOPLEFT", 36, -62)
	local t = UI:Text(w, 13, "light", "LEFT")
	t:SetPoint("TOPLEFT", port, "TOPRIGHT", 18, 0)
	t:SetWidth(430)
	t:SetSpacing(3)
	t:SetText("\"Another one with an empty bag! The cellar stairs are behind the bar, love. Fill that bag down in the Undercroft, then hearth home before something fills you with holes.\"\n\nClick Marga any time for how it all works.\n\nHow big should the window be? You can change it in the options.")
	local function Size(label, v, x)
		local b = UI:Wide(w, label, 170, function()
			P:SetSetting("size", v)
			P.db.welcomed = true
			G:Screen(nil)
		end, "ui_confirm")
		b:SetPoint("BOTTOM", w, "BOTTOM", x, 36)
	end
	Size("Large", 1, -180)
	Size("Normal", 0.9, 0)
	Size("Small", 0.75, 180)
end
