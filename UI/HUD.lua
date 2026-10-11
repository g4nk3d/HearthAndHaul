--[[ Hearth & Haul - UI/HUD.lua
	The strip under the stage and what floats on the stage: health and stamina, the hearth bar, the bag's
	worth, the room's action buttons, the depth meter, the finds waiting on the floor and the bag itself.

	  Hd:Build(parent, stage)         made once
	  Hd:Update(run)                  bars and labels (only what changed is touched)
	  Hd:Actions(run)                 the action buttons for the phase
	  Hd:Finds(run) / Hd:Bag(run, open, swapFor)   the floor's finds; the bag panel (swapFor: a find to swap in)
	  Hd:Inn(gold)                    the strip in the inn (purse, no bars) ]]

local _, ns = ...
local P = ns.P
local Hd = P:Module("HUD")
local A, Au, UI = P.Assets, P.Audio, P.UI
local R, D = ns.Rules, ns.Data

local floor, max, min = math.floor, math.max, math.min
local strip, stage
local hp, sta, cast, gold, depth, finds, bag = {}, {}, {}, {}, {}, {}, {}
local acts = {}
Hd.cast, Hd.finds, Hd.bag = cast, finds, bag

-- a bar: frame art, a fill cropped (not squashed) to the value, a label
local function Bar(parent, frameName, fillName, w, h, well, srcW, label)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, h)
	local k = w / srcW
	local fill = f:CreateTexture(nil, "ARTWORK", nil, 0)
	local fw, fh = well[3] * k, well[4] * k
	fill:SetPoint("TOPLEFT", f, "TOPLEFT", well[1] * k, -well[2] * k)
	fill:SetSize(fw, fh)
	A:Sprite(fill, fillName)
	local fr = f:CreateTexture(nil, "ARTWORK", nil, 2)
	fr:SetAllPoints()
	A:Sprite(fr, frameName)
	f.fill, f.fw, f.fh, f.frameTex = fill, fw, fh, fr
	f.rec = A:Rec(fillName)
	if label then
		f.text = UI:Text(f, label, "light")
		f.text:SetPoint("CENTER", fill, "CENTER", 0, 0)
	end
	f.v = -1
	return f
end

local function SetBar(b, v)
	v = max(0, min(1, v))
	if b.v == v then return end
	b.v = v
	local r = b.rec
	if not r then return end
	if v <= 0.001 then b.fill:Hide() return end
	b.fill:Show()
	b.fill:SetWidth(b.fw * v)
	b.fill:SetTexCoord(r[6], r[6] + (r[7] - r[6]) * v, r[8], r[9])
end
Hd.SetBar = SetBar

-- ------------------------------------------------------------------ building
function Hd:Build(parent, st)
	stage = st
	strip = CreateFrame("Frame", nil, parent)
	strip:SetSize(960, 140)
	Hd.frame = strip

	-- the hero: portrait, health, stamina
	local port = strip:CreateTexture(nil, "ARTWORK")
	-- clear of the window's carved bottom-left corner
	port:SetSize(74, 74)
	port:SetPoint("TOPLEFT", 36, -12)
	A:Sprite(port, "hero_portrait_calm")
	Hd.portrait = port
	hp.bar = Bar(strip, "health_bar_frame", "health_fill", 196, 25, { 16, 16, 480, 32 }, 512, 12)
	hp.bar:SetPoint("TOPLEFT", port, "TOPRIGHT", 8, -6)
	UI:Tip(hp.bar, "Health", "Creatures, traps and gambles take it; a shrine of healing and each boss give some back. At 0 the dive is over and the bag is lost.")
	hp.bar:EnableMouse(true)
	sta.bar = Bar(strip, "stamina_bar_frame", "stamina_fill", 148, 19, { 12, 12, 360, 24 }, 384, nil)
	sta.bar:SetPoint("TOPLEFT", hp.bar, "BOTTOMLEFT", 0, -8)
	sta.bar:EnableMouse(true)
	UI:Tip(sta.bar, "Stamina", "Holding your guard drains it, and every blocked hit costs more. At 0 your guard breaks until it is back to 35.")
	sta.broken = UI:Text(strip, 11, "light", "LEFT")
	sta.broken:SetPoint("LEFT", sta.bar, "RIGHT", 6, 0)
	sta.broken:SetText("|cffff7060Guard broken|r")
	sta.broken:Hide()
	Hd.bless = UI:Text(strip, 11, "title", "LEFT")
	Hd.bless:SetPoint("TOPLEFT", sta.bar, "BOTTOMLEFT", 2, -8)

	-- the hearth: the frame's well takes the fill; the stone sits in the frame's socket at the left
	cast.bar = Bar(strip, "hearth_bar_frame", "hearth_fill", 384, 48, { 88, 24, 656, 48 }, 768, nil)
	cast.bar:SetPoint("TOP", strip, "TOP", 60, -20)
	cast.bar:EnableMouse(true)
	UI:Tip(cast.bar, "Your hearthstone  (H)", "Ten seconds to get home with what is in your bag. The light draws creatures: every hit that gets through knocks the cast back a second, and holding your guard holds the cast still. Press H again to call it off.")
	local k = 384 / 768
	cast.crack = cast.bar:CreateTexture(nil, "ARTWORK", nil, 3)
	cast.crack:SetAllPoints()
	A:Sprite(cast.crack, "hearth_bar_crack_overlay")
	cast.crack:SetAlpha(0)
	cast.glow = cast.bar:CreateTexture(nil, "ARTWORK", nil, 4)
	cast.glow:SetAllPoints()
	A:Sprite(cast.glow, "hearth_bar_completion_glow")
	cast.glow:SetBlendMode("ADD")
	cast.glow:SetAlpha(0)
	cast.spark = cast.bar:CreateTexture(nil, "OVERLAY")
	cast.spark:SetSize(26, 26)
	A:Sprite(cast.spark, "hearth_spark")
	cast.spark:SetBlendMode("ADD")
	cast.spark:Hide()
	cast.stone = cast.bar:CreateTexture(nil, "OVERLAY")
	cast.stone:SetSize(40, 40)
	cast.stone:SetPoint("CENTER", cast.bar, "LEFT", 44 * k + 4, 0)
	A:Sprite(cast.stone, "hearthstone_idle")
	-- the caption sits just above the bar, centred on its well (the buttons need the room under it)
	cast.text = UI:Text(strip, 13, "light")
	cast.text:SetPoint("BOTTOM", cast.bar, "TOPLEFT", 88 * k + cast.bar.fw / 2, 0)
	cast.k = k
	cast.crackT = 0

	-- the bag's worth on the gold plate (only the parchment between the caps takes the number)
	gold.plate = CreateFrame("Button", nil, strip)
	gold.plate:SetSize(176, 44)
	gold.plate:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -8, -8)
	local gp = gold.plate:CreateTexture(nil, "ARTWORK")
	gp:SetAllPoints()
	A:Sprite(gp, "gold_plate")
	gold.text = UI:Text(gold.plate, 15, "ink")
	gold.text:SetPoint("CENTER", 0, 0)
	gold.text:SetWordWrap(false)
	gold.cap = UI:Text(strip, 11, "light")
	gold.cap:SetPoint("TOP", gold.plate, "BOTTOM", 0, 0)
	gold.plate:SetScript("OnClick", function() if Hd.onBag then Hd.onBag() end end)
	UI:Tip(gold.plate, function() return Hd.goldTip, Hd.goldTipText end)

	-- the room's buttons, under the hearth bar
	local function Act(x)
		local b = UI:Wide(strip, "", 168, function(self) end, "ui_confirm")
		b:SetPoint("TOP", cast.bar, "BOTTOM", x, -6)
		b:SetScript("OnClick", function(self) Au:Play(self.sound or "ui_click") if self.fn then self.fn() end end)
		UI:Tip(b, function(self) return self.tipTitle, self.tipText end)
		b:Hide()
		return b
	end
	acts[1], acts[2], acts[3] = Act(-180), Act(0), Act(180)
	Hd.acts = acts

	-- the depth meter on the stage's right edge
	depth.f = CreateFrame("Frame", nil, stage)
	depth.f:SetSize(30, 240)
	depth.f:SetPoint("TOPRIGHT", stage, "TOPRIGHT", -10, -40)
	depth.f:SetFrameLevel(stage:GetFrameLevel() + 8)
	local dm = depth.f:CreateTexture(nil, "ARTWORK")
	dm:SetAllPoints()
	A:Sprite(dm, "depth_meter")
	depth.marker = depth.f:CreateTexture(nil, "OVERLAY")
	depth.marker:SetSize(22, 22)
	A:Sprite(depth.marker, "hero_marker")
	depth.text = UI:Text(stage, 13, "title")
	depth.text:SetPoint("TOP", depth.f, "BOTTOM", 0, -2)
	depth.zone = UI:Text(stage, 12, "light", "RIGHT")
	depth.zone:SetPoint("TOPRIGHT", stage, "TOPRIGHT", -48, -12)
	depth.f:EnableMouse(true)
	UI:Tip(depth.f, "How deep", "Three floors to a zone, a boss at the end of each: the Cellars, the Old Catacombs, the Fungal Deep, the Crystal Vault, then the Rift, which never ends. Finds are worth 18% more with every floor.")

	-- the finds waiting on the floor: left-click to take, right-click to leave
	finds.f = CreateFrame("Frame", nil, stage)
	finds.f:SetSize(420, 96)
	finds.f:SetPoint("TOP", stage, "TOP", -40, -24)
	finds.f:SetFrameLevel(stage:GetFrameLevel() + 10)
	finds.title = UI:Text(finds.f, 14, "title")
	finds.title:SetPoint("TOP", 0, 0)
	finds.slots = {}
	for i = 1, 6 do
		local b = CreateFrame("Button", nil, finds.f)
		b:SetSize(60, 60)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b.bg = b:CreateTexture(nil, "ARTWORK", nil, 0)
		b.bg:SetAllPoints()
		A:Sprite(b.bg, "bag_slot_new")
		b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
		b.icon:SetPoint("TOPLEFT", 60 * 18 / 96, -60 * 18 / 96)
		b.icon:SetSize(60 * 60 / 96, 60 * 60 / 96)
		b.val = UI:Text(b, 10, "light")
		b.val:SetPoint("BOTTOM", b, "BOTTOM", 0, -12)
		b.i = i
		b:SetScript("OnClick", function(self, btn) if Hd.onFind then Hd.onFind(self.i, btn == "RightButton") end end)
		UI:Tip(b, function(self) return Hd:ItemTip(self.item, "Left-click: take it.  Right-click: leave it.") end)
		b:Hide()
		finds.slots[i] = b
	end
	finds.f:Hide()

	-- the bag panel
	bag.f = CreateFrame("Frame", nil, stage)
	bag.f:SetSize(384, 288)
	bag.f:SetPoint("CENTER", stage, "CENTER", -40, 10)
	bag.f:SetFrameLevel(stage:GetFrameLevel() + 20)
	bag.f:EnableMouse(true)
	local bf = bag.f:CreateTexture(nil, "BACKGROUND")
	bf:SetAllPoints()
	A:Sprite(bf, "bag_frame")
	local L = ns.Layout.bag_frame
	local bk = 384 / L.size[1]
	bag.k = bk
	bag.head = UI:Text(bag.f, 14, "title")
	local hd = L.live_bag_heading
	bag.head:SetPoint("TOPLEFT", hd[1] * bk, -hd[2] * bk)
	bag.head:SetSize(hd[3] * bk, hd[4] * bk)
	bag.region = L.default_slot_region
	bag.slots = {}
	for i = 1, 15 do
		local b = CreateFrame("Button", nil, bag.f)
		b.bg = b:CreateTexture(nil, "ARTWORK", nil, 0)
		b.bg:SetAllPoints()
		b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
		b.i = i
		b:SetScript("OnClick", function(self) if Hd.onBagSlot then Hd.onBagSlot(self.i) end end)
		UI:Tip(b, function(self) return Hd:ItemTip(self.item, Hd.swapFor and "Click: swap this out for the new find." or nil) end)
		bag.slots[i] = b
	end
	bag.hint = UI:Text(bag.f, 11, "light")
	bag.hint:SetPoint("BOTTOM", bag.f, "BOTTOM", 0, 14)
	bag.hint:SetWidth(330)
	local close = UI:Close(bag.f, function() Hd:Bag(Hd.run, false) end)
	close:SetPoint("TOPRIGHT", bag.f, "TOPRIGHT", -14, -14)
	bag.f:Hide()
	return strip
end

-- ------------------------------------------------------------------ items
function Hd:ItemTip(it, hint)
	if not it then return nil end
	local Q = D.QUALITY[it.q]
	local c = Q.color
	local title = ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, it.name)
	local text = ("%s.  Worth %d gold."):format(Q.name, it.value)
	if hint then text = text .. "\n|cffb8a888" .. hint .. "|r" end
	return title, text
end

local function SetItem(b, it, slotArt)
	b.item = it
	if it then
		b.icon:SetTexture(it.icon)
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		b.icon:Show()
		local c = D.QUALITY[it.q].color
		if b.val then b.val:SetText(("|cff%02x%02x%02x%dg|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, it.value)) end
	else
		b.icon:Hide()
		if b.val then b.val:SetText("") end
	end
	if slotArt then A:Sprite(b.bg, slotArt) end
end

function Hd:Finds(run)
	self.run = run
	local n = run and #run.pending or 0
	if n == 0 or run.cast or run.phase == "home" or run.phase == "dead" then finds.f:Hide() return end
	finds.f:Show()
	finds.title:SetText(n == 1 and "A find!" or ("%d finds"):format(n))
	local shown = min(6, n)
	for i = 1, 6 do
		local b = finds.slots[i]
		if i <= shown then
			SetItem(b, run.pending[i])
			b:ClearAllPoints()
			b:SetPoint("TOP", finds.f, "TOP", (i - (shown + 1) / 2) * 68, -22)
			b:Show()
		else
			b:Hide()
			b.item = nil
		end
	end
end

-- the bag: 4 x 3 slots of 80, or 5 x 3 of 64 with Deep Pockets (the art's slot region either way)
function Hd:Bag(run, open, swapFor)
	self.run = run
	self.swapFor = swapFor
	if not open or not run then bag.f:Hide() self.bagOpen = false return end
	self.bagOpen = true
	bag.f:Show()
	local cols = run.bagMax > 12 and 5 or 4
	local size = run.bagMax > 12 and 64 or 80
	local gap = 8
	local rg = bag.region
	local k = bag.k
	local totalW = cols * size + (cols - 1) * gap
	local x0 = (rg[1] + (rg[3] - totalW) / 2) * k
	local y0 = (rg[2] + (rg[4] - (3 * size + 2 * gap)) / 2) * k
	for i = 1, 15 do
		local b = bag.slots[i]
		if i <= run.bagMax then
			local c, r = (i - 1) % cols, floor((i - 1) / cols)
			b:SetSize(size * k, size * k)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", bag.f, "TOPLEFT", x0 + c * (size + gap) * k, -(y0 + r * (size + gap) * k))
			local s = size * k
			b.icon:ClearAllPoints()
			b.icon:SetPoint("TOPLEFT", s * 18 / 96, -s * 18 / 96)
			b.icon:SetSize(s * 60 / 96, s * 60 / 96)
			local it = run.bag[i]
			SetItem(b, it, it and (swapFor and "bag_slot_selected" or "bag_slot_filled") or "bag_slot_empty")
			b:Show()
		else
			b:Hide()
		end
	end
	bag.head:SetText(("Bag  %d / %d   ·   %d gold"):format(#run.bag, run.bagMax, R:BagValue(run)))
	bag.hint:SetText(swapFor and ("|cffffd070Your bag is full.|r Click an item to swap it for the %s, or close to leave it."):format(swapFor.name)
		or "Everything here is lost if you fall. Hearth home (H) to bank it.")
end

-- ------------------------------------------------------------------ actions
-- list: { label, fn, tip, sound } x up to 3 (nil hides)
function Hd:SetActions(a1, a2, a3)
	local list = { a1, a2, a3 }
	for i = 1, 3 do
		local b, a = acts[i], list[i]
		if a then
			b:SetLabel(a[1])
			b.fn, b.sound = a[2], a[4]
			b.tipTitle, b.tipText = a[1], a[3]
			b:SetEnabled(a[5] ~= false)
			b:Show()
		else
			b:Hide()
		end
	end
end

-- ------------------------------------------------------------------ per frame
local last = {}
function Hd:Update(run, dt)
	if not run then return end
	SetBar(hp.bar, run.hp / R.MAX_HP)
	local h = floor(run.hp + 0.5)
	if last.hp ~= h then
		last.hp = h
		hp.bar.text:SetText(("%d / %d"):format(h, R.MAX_HP))
		A:Sprite(self.portrait, run.phase == "home" and "hero_portrait_triumphant" or (h <= 35 and "hero_portrait_hurt" or "hero_portrait_calm"))
	end
	SetBar(sta.bar, run.sta / R.MAX_STA)
	if last.broken ~= run.broken then
		last.broken = run.broken
		sta.broken:SetShown(run.broken)
		sta.bar.fill:SetVertexColor(run.broken and 1 or 1, run.broken and 0.45 or 1, run.broken and 0.4 or 1)
	end
	if last.bless ~= run.bless then
		last.bless = run.bless
		self.bless:SetText(run.bless > 0 and ("Blessed: +50%% damage, %d floor%s"):format(run.bless, run.bless == 1 and "" or "s") or "")
	end
	-- the hearth
	local c = run.cast
	if c then
		SetBar(cast.bar, c / R.CAST_T)
		local x = 88 * cast.k + cast.bar.fw * (c / R.CAST_T)
		cast.spark:ClearAllPoints()
		cast.spark:SetPoint("CENTER", cast.bar, "LEFT", x, 0)
		cast.spark:Show()
	else
		SetBar(cast.bar, run.phase == "home" and 1 or 0)
		cast.spark:Hide()
	end
	local stone = c and (run.castPaused and "hearthstone_idle" or "hearthstone_glowing") or "hearthstone_idle"
	if last.stone ~= stone then last.stone = stone A:Sprite(cast.stone, stone) end
	if cast.crackT > 0 then
		cast.crackT = cast.crackT - (dt or 0)
		cast.crack:SetAlpha(max(0, cast.crackT / 0.6))
	end
	if cast.glowT and cast.glowT > 0 then
		cast.glowT = cast.glowT - (dt or 0)
		cast.glow:SetAlpha(max(0, min(1, cast.glowT)))
	end
	local secs = c and floor((R.CAST_T - c) / 3 + 0.5) or -1
	local ct = c and (run.castPaused and 1 or 2) or 0
	if last.secs ~= secs or last.ct ~= ct then
		last.secs, last.ct = secs, ct
		if not c then cast.text:SetText("|cffb8a888Hearth home (H)|r")
		elseif run.castPaused then cast.text:SetText(("Guarding: the cast holds  ·  %.1f s left"):format(secs / 10))
		else cast.text:SetText(("|cff9fd8ffHearthing...|r %.1f s"):format(secs / 10)) end
	end
	-- the bag's worth and the depth
	local bv = R:BagValue(run)
	local nb = #run.bag
	if last.bv ~= bv or last.nb ~= nb or last.bm ~= run.bagMax then
		last.bv, last.nb, last.bm = bv, nb, run.bagMax
		gold.text:SetText(("%d g"):format(bv))
		gold.cap:SetText(("Bag %d / %d  (B)"):format(nb, run.bagMax))
		self.goldTip, self.goldTipText = "Your bag  (B)", ("%d item%s worth %d gold. Lost if you fall; banked when you hearth home."):format(nb, nb == 1 and "" or "s", bv)
	end
	if last.floor ~= run.floor then
		last.floor = run.floor
		local z = D:Zone(run.floor)
		local t = min(1, (run.floor - 1) / 19)
		depth.marker:ClearAllPoints()
		depth.marker:SetPoint("CENTER", depth.f, "TOP", 0, -(36 + t * 180))
		depth.text:SetText(("Floor %d"):format(run.floor))
		depth.zone:SetText(z.name .. (D:IsBossFloor(run.floor) and "  |cffff7060(boss floor)|r" or ""))
	end
end

function Hd:Pushback()
	cast.crackT = 0.6
	cast.crack:SetAlpha(1)
end

function Hd:CastDone()
	cast.glowT = 1.2
	cast.glow:SetAlpha(1)
end

function Hd:Reset() wipe(last) end

-- the inn: the purse on the plate, no bars
function Hd:Inn(goldNow)
	wipe(last)
	hp.bar:Hide() sta.bar:Hide() cast.bar:Hide() cast.text:Hide() self.portrait:Hide() sta.broken:Hide() self.bless:SetText("")
	depth.f:Hide() depth.text:Hide() depth.zone:Hide()
	finds.f:Hide()
	bag.f:Hide()
	gold.text:SetText(("%d g"):format(goldNow or 0))
	gold.cap:SetText("Your purse")
	self.goldTip, self.goldTipText = "Your purse", "Gold banked from every dive that made it home. Spend it at the stash chest on the inn's furnishings."
end

function Hd:Dive()
	wipe(last)
	hp.bar:Show() sta.bar:Show() cast.bar:Show() cast.text:Show() self.portrait:Show()
	depth.f:Show() depth.text:Show() depth.zone:Show()
	cast.crack:SetAlpha(0) cast.glow:SetAlpha(0)
	cast.crackT, cast.glowT = 0, 0
end
