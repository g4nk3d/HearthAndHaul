--[[ Hearth & Haul - UI/Window.lua
	The game window and the one driver: the inn between dives, the dive itself (the rules tick 30 times a
	second while nothing covers the stage), the screens, the keyboard and mouse, and combat safety.

	  G:Open() / G:Close() / G:Toggle() / G:IsOpen()
	  G:Dive(perkId [, daily])     a new dive from the cellar stairs
	  G:Screen(name)               a screen over everything (nil = back to the inn or the dive)
	  G:Perf()                     the /hnh perf readout

	A dive stops the moment a screen covers it (Esc, closing the window, a /reload, combat); the bag panel
	does not stop it, since it is part of the stage. A stopped dive comes back paused and carries on only
	with a click on Resume. The dive is kept as its seed, perk and input log, so a /reload replays it to
	the very tick it was at. ]]

local _, ns = ...
local P = ns.P
local G = P:Module("Game")
local A, Au, UI, St, Hd, In, Pr = P.Assets, P.Audio, P.UI, P.Stage, P.HUD, P.Inn, P.Progress
local R, D = ns.Rules, ns.Data

local floor, max, min = math.floor, math.max, math.min
local WIN_W, WIN_H = 1000, 700
local TICK = 1 / R.TPS

local W
local screens, lazy = {}, {}
G.screens, G.lazy = screens, lazy
local run
local acc = 0
local endT              -- seconds until the results after the dive ended
local perf = { n = 0, sum = 0, max = 0, over = 0, tags = {} }
G.mode = "inn"

local function InCombat() return InCombatLockdown and InCombatLockdown() end

local function NewSeed()
	local t = (time and time() or 0) % 1000000
	local g = floor(((GetTime and GetTime() or 0) * 1000) % 1000000)
	return (t * 7919 + g * 104729) % 2147483646 + 1
end

-- ------------------------------------------------------------------ helpers
local function Panel(parent, w, h)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, h)
	f:EnableMouse(true)
	UI:Slice9(f, "BACKGROUND", 0, "inner_panel", 48, 64)
	return f
end

-- the ribbon: the parchment between the rolled ends takes the words (measured on the art: x 0.27..0.73 of
-- the width, its middle at 0.56 of the height)
local RIB_W, RIB_H = 400, 75
local function Ribbon(parent, text, dy)
	local r = parent:CreateTexture(nil, "ARTWORK")
	A:Sprite(r, "title_ribbon")
	r:SetSize(RIB_W, RIB_H)
	r:SetPoint("TOP", parent, "TOP", 0, dy or 34)
	local fs = UI:Text(parent, 18, "ink")
	fs:SetPoint("CENTER", r, "TOP", 0, -RIB_H * 0.56)
	fs:SetWordWrap(false)
	function fs:SetTitle(t)
		self:SetText(t)
		local font, _, flags = self:GetFont()
		for size = 18, 10, -1 do
			if font then self:SetFont(font, size, flags) end
			local w = self.GetUnboundedStringWidth and self:GetUnboundedStringWidth() or self:GetStringWidth()
			if not w or w <= RIB_W * 0.44 then break end
		end
	end
	fs:SetTitle(text)
	return fs
end
G.Ribbon = Ribbon

local function ScreenFrame(name, w, h, bare)
	local f = bare and CreateFrame("Frame", nil, G.shade) or Panel(G.shade, w, h)
	if bare then f:SetSize(w, h) f:EnableMouse(true) end
	f:SetPoint("CENTER", G.shade, "CENTER")
	f:SetFrameLevel(G.shade:GetFrameLevel() + 2)
	f:Hide()
	screens[name] = f
	return f
end
G.ScreenFrame = ScreenFrame

local MEDAL = { "bronze", "silver", "gold" }
local function MedalSprite(m)
	if not m or m < 1 then return "medal_bronze_not_earned" end
	return ("medal_%s_earned"):format(MEDAL[m])
end

local function Back() G:Screen(nil) end

-- ------------------------------------------------------------------ building
local function Build()
	W = CreateFrame("Frame", nil, UIParent)
	G.W = W
	W:SetSize(WIN_W, WIN_H)
	W:SetPoint("CENTER")
	W:SetFrameStrata("HIGH")
	W:SetToplevel(true)
	W:SetClampedToScreen(true)
	W:SetMovable(true)
	W:EnableMouse(true)
	W:Hide()
	UI:Slice9(W, "BACKGROUND", 0, "main_window", 64, 64)

	-- the stage and the strip under it
	local stage = St:Build(W, W:GetFrameLevel() + 2)
	stage:SetPoint("TOPLEFT", W, "TOPLEFT", 20, -62)
	In:Build(stage)
	local strip = Hd:Build(W, stage)
	strip:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 0, -6)
	strip:SetFrameLevel(W:GetFrameLevel() + 4)

	-- the mouse on the stage: hold the left button to strike, the right button to guard
	local catcher = CreateFrame("Button", nil, stage)
	catcher:SetAllPoints()
	catcher:SetFrameLevel(stage:GetFrameLevel() + 1)
	catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	catcher:SetScript("OnMouseDown", function(_, btn) G:HoldMouse(btn, true) end)
	catcher:SetScript("OnMouseUp", function(_, btn) G:HoldMouse(btn, false) end)
	catcher:Hide()
	G.catcher = catcher
	-- the stage's own buttons (doors, the room's piece) sit above the catcher
	St.propBtn:SetFrameLevel(stage:GetFrameLevel() + 6)

	-- the top: drag strip, ribbon, a few icons, close
	local top = CreateFrame("Frame", nil, W)
	top:SetPoint("TOPLEFT", 0, 0)
	top:SetPoint("TOPRIGHT", 0, 0)
	top:SetHeight(60)
	top:SetFrameLevel(W:GetFrameLevel() + 10)
	top:EnableMouse(true)
	top:RegisterForDrag("LeftButton")
	top:SetScript("OnDragStart", function() if not InCombat() then W:StartMoving() end end)
	top:SetScript("OnDragStop", function()
		W:StopMovingOrSizing()
		local p, _, rp, x, y = W:GetPoint(1)
		P.db.window = { p, rp, x, y }
	end)
	G.title = Ribbon(top, "Hearth & Haul", 6)
	local close = UI:Close(top, function() G:Close() end)
	close:SetPoint("TOPRIGHT", W, "TOPRIGHT", -18, -16)
	UI:Tip(close, "Close", "A dive in progress waits, paused, until you come back.")
	local function Sq(x, icon, tip, fn)
		local b = UI:Square(top, icon, 36, tip, fn)
		b:SetPoint("TOPLEFT", W, "TOPLEFT", x, -14)
		return b
	end
	G.pauseBtn = Sq(22, "icon_pause", "Pause  (Esc)", function() G:Escape() end)
	G.soundBtn = Sq(62, P:Setting("sound") and "icon_sound_on" or "icon_sound_off", "Sound effects on or off", function()
		P:SetSetting("sound", not P:Setting("sound"))
		G.soundBtn:SetIcon(P:Setting("sound") and "icon_sound_on" or "icon_sound_off")
	end)
	G.musicBtn = Sq(102, P:Setting("music") and "icon_music_on" or "icon_music_off", "Music on or off", function()
		P:SetSetting("music", not P:Setting("music"))
		G.musicBtn:SetIcon(P:Setting("music") and "icon_music_on" or "icon_music_off")
	end)
	Sq(142, "icon_trophy", "Achievements", function() G:Screen("achievements") end)
	Sq(182, "icon_settings", "Settings", function() if P.Options then P.Options:Open() end end)

	-- the screens' shade
	local shade = CreateFrame("Frame", nil, W)
	shade:SetPoint("TOPLEFT", 14, -14)
	shade:SetPoint("BOTTOMRIGHT", -14, 14)
	shade:SetFrameLevel(W:GetFrameLevel() + 40)
	shade:EnableMouse(true)
	local sh = shade:CreateTexture(nil, "BACKGROUND")
	sh:SetAllPoints()
	sh:SetColorTexture(0.02, 0.02, 0.04, 0.78)
	shade:Hide()
	G.shade = shade

	-- the hooks the stage and the strip call
	St.onDoor = function(i) G:Door(i) end
	St.onDoorTip = function(owner, i) G:DoorTip(owner, i) end
	St.onProp = function() G:Primary() end
	St.onPropTip = function(owner) G:PropTip(owner) end
	Hd.onFind = function(i, leave) G:Find(i, leave) end
	Hd.onBag = function() G:ToggleBag() end
	Hd.onBagSlot = function(i) G:BagSlot(i) end

	W:SetScript("OnKeyDown", function(self, key)
		if InCombat() then return end
		local handled = G:Key(key, true)
		self:SetPropagateKeyboardInput(not handled)
	end)
	W:SetScript("OnKeyUp", function(_, key) if not InCombat() then G:Key(key, false) end end)
	W:SetScript("OnShow", function() G:Shown() end)
	W:SetScript("OnHide", function() G:Hidden() end)
	G:FitScale()
	local wp = P.db.window
	if type(wp) == "table" and type(wp[1]) == "string" and type(wp[3]) == "number" and type(wp[4]) == "number" then
		W:ClearAllPoints()
		if not pcall(W.SetPoint, W, wp[1], UIParent, wp[2] or wp[1], wp[3], wp[4]) then W:SetPoint("CENTER") end
	end
end

-- ------------------------------------------------------------------ screens (each built the first time it is shown)
function G:Prebuild(name)
	if screens[name] or not lazy[name] then return end
	local build = lazy[name]
	lazy[name] = nil
	P:Safe("build " .. name, build)
	if screens[name] then screens[name]:Hide() end
end

function G:Screen(name, quiet)
	if not W then return end
	if name and not screens[name] and lazy[name] then
		local build = lazy[name]
		lazy[name] = nil
		P:Safe("build " .. name, build)
	end
	for k, f in pairs(screens) do f:SetShown(k == name) end
	self.screen = name
	G.shade:SetShown(name ~= nil)
	if name then
		UI:HideTip()
		self:ReleaseHolds()
		if not quiet then Au:Play("ui_menu_open") end
		local f = screens[name]
		if f and f.Refresh then P:Safe("screen " .. name, f.Refresh, f) end
	end
	self:MusicNow()
end

function G:MusicNow()
	if self.mode == "dive" and run then
		Au:MusicLayer(D:Zone(run.floor), run.cast ~= nil)
	else
		Au:Music("music_sleeping_gryphon")
	end
end

-- ------------------------------------------------------------------ the dive: inputs
local function Saving()
	if not P.char or P.readOnly or not run then return end
	if run.phase == "home" or run.phase == "dead" then P.char.resume = nil return end
	local rs = P.char.resume
	if type(rs) ~= "table" or rs.log ~= run.log then
		rs = { seed = run.seed, perk = run.perk, daily = run.daily, log = run.log }
		P.char.resume = rs
	end
	rs.tick = run.tick
end

local function Live() return G.mode == "dive" and run and not G.screen and run.phase ~= "home" and run.phase ~= "dead" end

function G:ReleaseHolds()
	if run and run.phase ~= "home" and run.phase ~= "dead" then
		R:Hold(run, "block", false)
		R:Hold(run, "strike", false)
	end
	self.keyBlock, self.keyStrike, self.mouseBlock, self.mouseStrike = false, false, false, false
end

local function ApplyHolds()
	if not run then return end
	R:Hold(run, "block", G.keyBlock or G.mouseBlock)
	R:Hold(run, "strike", G.keyStrike or G.mouseStrike)
end

function G:HoldMouse(btn, down)
	if not Live() then return end
	if btn == "RightButton" then self.mouseBlock = down else self.mouseStrike = down end
	ApplyHolds()
end

function G:Door(i)
	if not Live() or run.phase ~= "doors" then return end
	if R:Door(run, i) then self:Events() end
end

function G:Hearth()
	if not Live() then return end
	if R:Hearth(run) then self:Events() end
end

function G:Next()
	if not Live() then return end
	if R:Next(run) then self:Events() end
end

-- the room's main action: open the chest, use the shrine, onward
function G:Primary()
	if not Live() then return end
	local ph = run.phase
	if ph == "chest" then R:Open(run)
	elseif ph == "shrine" then R:Shrine(run, "use")
	elseif ph == "clear" then R:Next(run)
	end
	self:Events()
end

function G:Find(i, leave)
	if not Live() then return end
	if leave then
		if R:Leave(run, i) then Au:Play("ui_cancel") end
	elseif #run.bag >= run.bagMax then
		Au:Play("bag_full")
		self.swapIndex = i
		Hd:Bag(run, true, run.pending[i])
	else
		R:Take(run, i)
	end
	self:Events()
end

function G:BagSlot(slot)
	if not Live() then return end
	if self.swapIndex and run.pending[self.swapIndex] then
		if R:Take(run, self.swapIndex, slot) then
			self.swapIndex = nil
			Hd:Bag(run, false)
			self:Events()
		end
	end
end

function G:ToggleBag()
	if self.mode ~= "dive" or not run then return end
	self.swapIndex = nil
	Hd:Bag(run, not Hd.bagOpen)
	Au:Play(Hd.bagOpen and "ui_menu_open" or "ui_menu_close")
end

function G:DoorTip(owner, i)
	local d = run and run.doors[i]
	if not d then return end
	local TIPS = {
		fight = "A fight with creatures of this zone. Each may drop a find.",
		elite = "One tougher creature (and company deeper down). Two better finds.",
		chest = "A chest: wood, iron or gilded, deeper down. Two to four finds. In the Cellars and the Rift, some chests bite.",
		shrine = "A shrine: healing, a blessing (+50% damage for 3 floors) or a gamble.",
		trap = "A trap: guard at the right moment to take less. A find waits past it.",
		unknown = "Anything could be behind this one.",
		boss = "The zone's guardian. Three good finds, and some health back.",
	}
	UI:ShowTip(owner, St.KIND_NAME[d.shown] .. ("  (%d)"):format(i), TIPS[d.shown] or "")
end

function G:PropTip(owner)
	if not run or not run.room then return end
	local room = run.room
	if run.phase == "chest" then
		UI:ShowTip(owner, "Open the chest  (E)", room.mimic and run.perk == "lantern" and "|cffff7060Your lantern shows teeth.|r It's a mimic." or "What's inside goes on the floor for you to take.")
	elseif run.phase == "shrine" then
		local T = { heal = { "Shrine of Healing", "Heals 50." }, blessing = { "Shrine of Blessing", "+50% damage for 3 floors." },
			gamble = { "Shrine of Chance", "Half the time a good find; half the time it takes 20 health." } }
		local t = T[room.shrine]
		UI:ShowTip(owner, t[1] .. "  (E)", t[2] .. "\n|cffb8a888Or walk past it: Onward (L).|r")
	end
end

-- ------------------------------------------------------------------ the dive: what the rules say happened
local function Snd(name) Au:Play(name) end
local ROOM_PHASE = { fight = true, chest = true, shrine = true, trap = true, clear = true }

function G:Actions()
	if not run then return end
	local ph = run.phase
	local hearth = run.cast and { "Call it off  (H)", function() G:Hearth() end, "Stop casting. The creatures it drew stay.", "ui_cancel" }
		or { "Hearth  (H)", function() G:Hearth() end, "Ten seconds to get home with your bag. Hits knock the cast back; guarding holds it.", "ui_confirm" }
	if ph == "home" or ph == "dead" then Hd:SetActions() return end
	if ph == "chest" and not run.cast then
		Hd:SetActions({ "Open  (E)", function() G:Primary() end, "Open the chest.", "ui_confirm" }, hearth,
			{ "Onward  (L)", function() G:Leave() end, "Leave the chest shut and go on.", "ui_click" })
	elseif ph == "shrine" and not run.cast then
		Hd:SetActions({ "Use  (E)", function() G:Primary() end, "Take the shrine's gift.", "ui_confirm" }, hearth,
			{ "Onward  (L)", function() G:Leave() end, "Walk past it.", "ui_click" })
	elseif ph == "clear" and not run.cast then
		local nf = #run.pending
		Hd:SetActions({ "Onward  (E)", function() G:Next() end, nf > 0 and "On to the next floor. Finds you have not taken stay behind." or "On to the next floor.", "ui_confirm" },
			hearth, { "Bag  (B)", function() G:ToggleBag() end, "Look in your bag." })
	else
		Hd:SetActions(nil, hearth, { "Bag  (B)", function() G:ToggleBag() end, "Look in your bag." })
	end
end

-- walk past a chest or shrine
function G:Leave()
	if not Live() then return end
	if run.phase == "shrine" then R:Shrine(run, "leave")
	elseif run.phase == "chest" then R:Skip(run) end
	self:Events()
end

function G:Events()
	if not run then return end
	local t0 = P:ProfStart()
	local z = D:Zone(run.floor)
	local refreshFinds, refreshActs = false, false
	for i = 1, run.evn do
		local e = run.ev[i]
		local code, a, b, c = e[1], e[2], e[3], e[4]
		St:Event(run, code, a, b, c)
		if code == "phase" then
			refreshActs, refreshFinds = true, true
			if a == "doors" then
				St:Doors(run)
				G.catcher:Hide()
			elseif ROOM_PHASE[a] and self.lastPhase == "enter" then
				St:Room(run)
			elseif a == "fight" and self.lastPhase == "doors" then
				-- the hearth's light drew creatures before a door was chosen
				St:HideDoors()
				St.walkTo = St.VX(300)
			end
			if a == "fight" or a == "trap" then G.catcher:Show()
			elseif a ~= "fight" then G.catcher:SetShown(run.cast ~= nil) end
			self.lastPhase = a
		elseif code == "door" then
			St:OpenDoor(a)
			Snd("door_open_" .. z.sfx)
		elseif code == "floor" then
			local nz = D:Zone(a)
			if nz ~= self.zone then
				self.zone = nz
				St:Zone(nz)
				self:MusicNow()
			end
		elseif code == "strike" then
			Au:Pick("strike", 3)
			Snd("enemy_hit_" .. z.sfx)
		elseif code == "tele" then Snd("telegraph")
		elseif code == "blocked" then Snd("block")
		elseif code == "guardbreak" then Snd("block_broken")
		elseif code == "hurt" then Au:Pick("hurt", 2)
		elseif code == "spawn" then
			local f = D.FOES[b]
			if f and f.boss then Snd("boss_roar_" .. b) end
		elseif code == "die" then
			local f = D.FOES[b]
			Snd(f and f.boss and "stinger_boss_defeated" or ("enemy_death_" .. z.sfx))
		elseif code == "chest" then
			St:OpenChest(a)
			Snd("chest_open")
		elseif code == "mimic" then
			Snd("chest_open")
		elseif code == "heal" or code == "bless" or code == "gamble" or code == "shrineleft" then
			if code ~= "shrineleft" then Snd("shrine") end
			if run.room and run.room.kind == "shrine" then St:UseShrine(run.room.shrine) end
		elseif code == "trapwarn" then Snd("telegraph")
		elseif code == "trap" then
			St:SpringTrap(run.room.trap)
			Snd("trap_" .. run.room.trap)
		elseif code == "drop" or code == "take" or code == "swap" or code == "leave" or code == "lost" or code == "bagged" then
			refreshFinds = true
			if code == "take" or code == "swap" or code == "bagged" then Snd("loot_pickup") end
			if code == "lost" then Snd("bag_full") end
			if Hd.bagOpen then Hd:Bag(run, true, self.swapIndex and run.pending[self.swapIndex]) end
		elseif code == "caston" then
			Snd("hearth_cast_01")
			G.catcher:Show()
			refreshActs, refreshFinds = true, true
			Hd:Bag(run, false)
			self:MusicNow()
		elseif code == "castsec" then
			if a >= 1 and a <= 9 then Snd(("hearth_cast_%02d"):format(a + 1)) end
		elseif code == "castoff" then
			refreshActs, refreshFinds = true, true
			self:MusicNow()
		elseif code == "pushback" then
			Snd("pushback")
			Hd:Pushback()
		elseif code == "home" then
			Snd("hearth_complete")
			Hd:CastDone()
			self:Finished()
		elseif code == "dead" then
			Snd("stinger_died")
			self:Finished()
		elseif code == "won" then
			refreshActs = true
		end
	end
	R:Drain(run)
	if refreshFinds then Hd:Finds(run) end
	if refreshActs then self:Actions() end
	Saving()
	P:ProfEnd("events", t0)
end

-- ------------------------------------------------------------------ starting, resuming, finishing
local function EnterDive()
	G.mode = "dive"
	In:Hide()
	St:Clear()
	St:ResetHero()
	Hd:Dive()
	Hd:Reset()
	G.zone = D:Zone(run.floor)
	St:Zone(G.zone)
	G.lastPhase = run.phase
	if run.phase == "doors" then St:Doors(run)
	elseif ROOM_PHASE[run.phase] then St:Room(run) St.walkTo = nil St.heroX = 300 end
	G.catcher:SetShown(run.phase == "fight" or run.phase == "trap" or run.cast ~= nil)
	Hd:Finds(run)
	G:Actions()
	acc, endT = 0, nil
	G.title:SetTitle(run.daily and ("Daily Dive  " .. run.daily) or "Hearth & Haul")
end

function G:Dive(perkId, daily)
	if not W then Build() end
	if perkId and not Pr:PerkOpen(perkId) then perkId = nil end
	if P.char then P.char.perk = perkId end
	local seed = daily and P.Daily:Seed() or NewSeed()
	run = R:NewRun(seed, perkId)
	run.daily = daily
	G.run = run
	EnterDive()
	R:Drain(run)
	self:Screen(nil, true)
	Saving()
	self:MusicNow()
end

-- the dive in progress after a /reload: replayed to the tick it was at, then paused
function G:Resume(rs)
	local ok, r = pcall(R.Replay, R, rs.seed, rs.perk, rs.log, rs.tick)
	if not ok or not r or r.phase == "home" or r.phase == "dead" then
		if not ok then P:RecordError("resume", r) end
		P.char.resume = nil
		return false
	end
	run = r
	run.daily = rs.daily
	run.log = rs.log
	G.run = run
	R:Drain(run)
	EnterDive()
	self:ReleaseHolds()
	R:Drain(run)
	Saving()
	self:Screen("paused", true)
	screens.paused.text:SetText(("Your dive is waiting where you left it: floor %d, %d gold in the bag.\nClick Resume when you're ready."):format(run.floor, R:BagValue(run)))
	return true
end

function G:Finished()
	if run.recorded then return end
	run.recorded = true
	self:ReleaseHolds()
	G.catcher:Hide()
	Hd:Bag(run, false)
	Hd:Finds(run)
	local medal, newBest, prev
	if run.daily then
		medal, newBest, prev = P.Daily:Finish(run)
		-- a new best for the day goes on the shared daily board (checked by everyone who hears it)
		local rec = P.Daily:Record(run.daily)
		if run.dailyBest and rec and rec.code and P.Leaderboard then
			P:Safe("leaderboard record", P.Leaderboard.Record, P.Leaderboard, run.daily, rec.best, rec.perk, rec.code)
		end
	else medal, newBest, prev = Pr:Finish(run) end
	run.medal, run.newBest, run.prevBest = medal, newBest, prev
	run.awards = P.Awards:Check(run)
	for _, a in ipairs(run.awards) do P:Print("achievement earned: |cffe8c27a%s|r (%s)", a[2], a[3]) end
	if P.char then P.char.resume = nil end
	endT = 2.4
end

function G:ShowResults()
	endT = nil
	self:Screen("results", true)
	Snd(run.phase == "home" and "stinger_banked" or "stinger_died")
end

function G:ToInn(mood)
	if not W then Build() end
	self.mode = "inn"
	if run and (run.phase == "home" or run.phase == "dead") then run = nil G.run = nil end
	St:Clear()
	G.catcher:Hide()
	In:Show(mood)
	Hd:Inn(Pr:Gold())
	Hd:SetActions({ "Into the cellars", function() G:Screen("perk") end, "Pick a perk and dive.", "ui_confirm" },
		{ "Notice board", function() G:Screen("board") end, "Today's daily dive and your records." },
		{ "Stash", function() G:Screen("stash") end, "Furnish the inn." })
	G.title:SetTitle("The Sleeping Gryphon")
	if mood then Snd("arrive_inn") end
	self:Screen(nil, true)
end

-- ------------------------------------------------------------------ keyboard
function G:Escape()
	if self.screen == "welcome" then return end
	if self.screen == "paused" then return end
	if self.screen == "results" then self:ToInn(run and run.phase == "home" and "banked" or "dead") return end
	if self.screen then self:Screen(self.mode == "dive" and run and run.phase ~= "home" and run.phase ~= "dead" and "paused" or nil) return end
	if Hd.bagOpen then Hd:Bag(run, false) self.swapIndex = nil return end
	if self.mode == "dive" and run and run.phase ~= "home" and run.phase ~= "dead" then
		self:Screen("paused")
		screens.paused.text:SetText("Paused. The Undercroft waits.")
	else
		self:Close()
	end
end

function G:Key(key, down)
	if IsModifierKeyDown and IsModifierKeyDown() and down then return false end
	if key == "ESCAPE" then
		if down then self:Escape() end
		return true
	end
	if self.screen then
		if down and self.screen == "results" and (key == "ENTER" or key == "SPACE") then
			self:ToInn(run and run.phase == "home" and "banked" or "dead")
			return true
		end
		if down and self.screen == "perk" and key == "ENTER" then screens.perk.go:Click() return true end
		return false
	end
	if self.mode == "inn" then
		if not down then return false end
		if key == "ENTER" then self:Screen("perk") return true end
		if key == "N" then self:Screen("board") return true end
		if key == "S" then self:Screen("stash") return true end
		if key == "/" or key == "?" then self:Screen("help") return true end
		return false
	end
	if not run then return false end
	if key == "SPACE" then self.keyBlock = down ApplyHolds() return true end
	if key == "F" or key == "A" then self.keyStrike = down ApplyHolds() return true end
	if not down then return false end
	if key == "H" then self:Hearth() return true end
	if key == "B" then self:ToggleBag() return true end
	if key == "E" or key == "ENTER" then self:Primary() return true end
	if key == "L" then self:Leave() return true end
	if key == "T" and #run.pending > 0 then self:Find(1, false) return true end
	local n = tonumber(key)
	if n and n >= 1 and n <= 3 and run.phase == "doors" then self:Door(n) return true end
	return false
end

function G:Keyboard(on)
	if not W then return end
	if InCombat() then on = false end
	W:EnableKeyboard(on and true or false)
	if not on then self:ReleaseHolds() end
end

-- ------------------------------------------------------------------ the driver
local function OnError(err)
	P:RecordError("game loop", err)
	return err
end

local stepDt = 0
local function Step()
	local dt = stepDt
	if run and G.mode == "dive" then
		if Live() then
			acc = acc + dt
			local n = 0
			while acc >= TICK and n < 4 do
				acc = acc - TICK
				n = n + 1
				R:Tick(run)
				if run.evn > 0 then G:Events() end
				if run.phase == "home" or run.phase == "dead" then break end
			end
			if acc > TICK then acc = 0 end
			local rs = P.char and P.char.resume
			if rs and rs.log == run.log then rs.tick = run.tick end
		end
		if endT and not G.screen then
			endT = endT - dt
			if endT <= 0 then G:ShowResults() end
		end
		if not G.screen then
			local t1 = P:ProfStart()
			St:Update(dt, run)
			Hd:Update(run, dt)
			P:ProfEnd("stage", t1)
		end
	elseif G.mode == "inn" and not G.screen then
		In:Update(dt)
	end
end

local function Drive(_, elapsed)
	if elapsed > 0.1 then elapsed = 0.1 end
	local t0 = debugprofilestop and debugprofilestop()
	stepDt = elapsed
	local ok = xpcall(Step, OnError)
	if not ok then
		W:SetScript("OnUpdate", nil)
		P:Print("something went wrong, so the game stopped. /hnh debug shows details; reopening restarts it.")
		return
	end
	if P:Setting("nudge") then
		G.played = (G.played or 0) + elapsed
		if G.played >= 1200 and not G.nudged then
			G.nudged = true
			P:Print("|cffe8c27aMarga:|r Twenty minutes down there, love. Come up for a drink and stretch your legs?")
		end
	end
	if t0 then
		local ms = debugprofilestop() - t0
		perf.n = perf.n + 1
		perf.sum = perf.sum + ms
		if ms > perf.max then perf.max = ms end
		if ms > 0.5 then perf.over = perf.over + 1 end
	end
end

function G:Shown()
	self:FitScale()
	W:SetScript("OnUpdate", Drive)
	self:Keyboard(true)
	P:Listen("PLAYER_REGEN_DISABLED")
	-- a dive comes back paused: it carries on with a click
	if self.mode == "dive" and run and not self.screen and run.phase ~= "home" and run.phase ~= "dead" then
		self:Screen("paused", true)
		screens.paused.text:SetText(("Your dive is waiting: floor %d, %d gold in the bag."):format(run.floor, R:BagValue(run)))
	end
	self:MusicNow()
	-- the screens a dive ends on, built ahead (one per frame) so the frame it ends in only fills them
	P:After(0, function() G:Prebuild("results") end)
	P:After(0.1, function() G:Prebuild("perk") end)
end

function G:Hidden()
	W:SetScript("OnUpdate", nil)       -- closed costs nothing
	self:ReleaseHolds()
	UI:HideTip()
	Au:StopMusic()
	Au:Cancel()
	if not self.combatHidden then P:Off("PLAYER_REGEN_DISABLED") end
	A:Trim()
end

-- ------------------------------------------------------------------ open / close
function G:FitScale()
	if not W then return end
	local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
	local size = tonumber(P:Setting("size")) or 0.9
	local sc = min(uw / WIN_W, uh / WIN_H) * max(0.5, min(1, size))
	W:SetScale(max(0.35, min(1.6, sc)))
end

function G:Open()
	if InCombat() then
		P:Print("opens after combat.")
		return
	end
	if not P.char then return end
	local first = not W
	if not W then Build() end
	if first then
		local rs = P.char.resume
		local today = P.Daily:Today()
		local resumed = false
		if type(rs) == "table" and (not rs.daily or rs.daily == today) then resumed = self:Resume(rs) end
		if not resumed then
			P.char.resume = nil
			self:ToInn(nil)
		end
		if P.db and not P.db.welcomed then self:Screen("welcome") end
	end
	W:Show()
	Au:Play("ui_menu_open")
end

function G:Close()
	if not W or not W:IsShown() then return end
	Au:Play("ui_menu_close")
	W:Hide()
end

function G:Toggle()
	if W and W:IsShown() then self:Close() else self:Open() end
end

function G:IsOpen() return W ~= nil and W:IsShown() end

-- after /hnh reset: back to an empty inn
function G:Forget()
	if W and W:IsShown() then W:Hide() end
	run = nil
	G.run = nil
	if W then self:ToInn(nil) end
end

-- give up the dive in progress (the bag is lost)
function G:Abandon()
	if not run or run.phase == "home" or run.phase == "dead" then return end
	R:Die(run)
	self:Events()
	self:Screen(nil, true)
end

-- ------------------------------------------------------------------ combat: step aside at once
P:On("PLAYER_REGEN_DISABLED", function()
	if not W or not W:IsShown() then return end
	G.combatHidden = true
	W:EnableKeyboard(false)
	G:ReleaseHolds()
	G:Screen("paused", true)
	screens.paused.text:SetText("You're in combat. The dive is frozen exactly as it was.\nWhen the fight is over, click Resume.")
	screens.paused.resume:SetEnabled(false)
	W:Hide()
	P:Listen("PLAYER_REGEN_ENABLED")
end)
P:Off("PLAYER_REGEN_DISABLED")

P:On("PLAYER_REGEN_ENABLED", function()
	P:Off("PLAYER_REGEN_ENABLED")
	if not G.combatHidden then return end
	G.combatHidden = false
	if not W then return end
	screens.paused.text:SetText("The fight is over. Your game is waiting.")
	screens.paused.resume:SetEnabled(true)
	W:Show()
	G:Keyboard(false)            -- the keyboard comes back with the Resume click, not before
	G:Screen("paused", true)
end)
P:Off("PLAYER_REGEN_ENABLED")

P:On("DISPLAY_SIZE_CHANGED", function() G:FitScale() end)
P:On("UI_SCALE_CHANGED", function() G:FitScale() end)

-- ------------------------------------------------------------------ perf
function G:Perf()
	local avg = perf.n > 0 and perf.sum / perf.n or 0
	local mem
	if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		UpdateAddOnMemoryUsage()
		mem = GetAddOnMemoryUsage(P.name)
	end
	P:Print("frame time %.3f ms average, %.3f ms worst over %d frames, %d frame(s) over the 0.5 ms budget; %s; memory %s KB.",
		avg, perf.max, perf.n, perf.over, (W and W:IsShown()) and "window open" or "window closed: 0 ms, no OnUpdate",
		mem and ("%.0f"):format(mem) or "?")
	local parts = {}
	for name, ms in pairs(P.prof) do if ms >= 0.2 then parts[#parts + 1] = name end end
	table.sort(parts, function(a, b) return P.prof[a] > P.prof[b] end)
	for i = 1, #parts do parts[i] = ("%s %.2f"):format(parts[i], P.prof[parts[i]]) end
	if #parts > 0 then P:Print("slowest parts (ms): %s.", table.concat(parts, ", ")) end
	wipe(P.prof)
	perf.n, perf.sum, perf.max, perf.over = 0, 0, 0, 0
end

G.MedalSprite, G.Back, G.Panel = MedalSprite, Back, Panel
