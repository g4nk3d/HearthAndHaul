--[[ Hearth & Haul - UI/Stage.lua
	The picture: the zone's three parallax layers, the doors, the room's chest / shrine / trap, the hero,
	up to three creatures, effects and floating numbers. It draws what Game/Rules.lua says is there; it
	never decides anything. Stage pixels: 960 x 480, top-left origin, the floor at y 389.

	  St:Build(parent)                the stage frame (made once)
	  St:Zone(zone)                   the zone's layers (and the Rift's portal)
	  St:Doors(run) / St:Room(run)    the door choice / the room behind the chosen door
	  St:Event(run, code, a, b, c)    one rules event (strikes, hits, deaths, drops...)
	  St:Update(dt, run)              animation and movement for one frame (nothing is created here)
	  St:Clear()                      everything hidden (the inn draws over an empty stage) ]]

local _, ns = ...
local P = ns.P
local St = P:Module("Stage")
local A, Au, UI = P.Assets, P.Audio, P.UI
local R, D = ns.Rules, ns.Data

local floor, max, min, sin = math.floor, math.max, math.min, math.sin
local W, H = 960, 480
St.W, St.H = W, H
-- each zone's picture has its own walkable floor: where everyone stands (ground), where the hero stands
-- (heroX), how the rules' distances map onto the picture (k: stage x = heroX + (rules x - 300) * k), the
-- doors' places and size, and where the hero waits at the doors. Measured on the layers as the window
-- crops them (tools/hh_preview.py grids).
local LAYOUT = {
	cellars       = { ground = 438, heroX = 400, k = 0.55, doors = { 450, 545, 640 }, doorScale = 0.72, idleX = 368 },
	catacombs     = { ground = 418, heroX = 300, k = 1, doors = { 420, 550, 680 }, doorScale = 0.9, idleX = 300 },
	fungal_deep   = { ground = 402, heroX = 300, k = 1, doors = { 430, 560, 690 }, doorScale = 0.9, idleX = 300 },
	crystal_vault = { ground = 386, heroX = 300, k = 1, doors = { 430, 560, 690 }, doorScale = 0.85, idleX = 300 },
	rift          = { ground = 312, heroX = 300, k = 1, doors = { 430, 560, 690 }, doorScale = 0.85, idleX = 300 },
}
St.LAYOUT = LAYOUT
local L = LAYOUT.cellars
local GROUND, HERO_X, PROP_X = L.ground, L.heroX, L.heroX + 300 * L.k
St.GROUND = GROUND
-- the rules' x (hero at 300, creatures' places 470..710, entering at 1000) on this picture
local function VX(x) return HERO_X + (x - 300) * L.k end
St.VX = VX
local PARALLAX = { 0.15, 0.4, 1 }
local LAYERS = { "back", "middle", "front" }

local stage
St.cam = 0

-- ------------------------------------------------------------------ actors: a texture and its animation
-- a = { tex, name, anim, t, i, done, x, y, scale, dirty }
local function NewActor(parent, layer, sub)
	local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
	t:Hide()
	return { tex = t, scale = 1, t = 0, i = 1, x = -9999, y = -9999 }
end

local function Play(a, name, restart)
	if a.name == name and not restart then return true end
	local an = A:Anim(name)
	if not an then return false end
	a.name, a.anim, a.t, a.i, a.done, a.dirty = name, an, 0, 1, false, true
	A:Sprite(a.tex, an[1])
	a.tex:SetSize(an.w * a.scale, an.h * a.scale)
	a.tex:Show()
	return true
end
St.Play = Play
St.NewActor = NewActor

local function Step(a, dt)
	local an = a.anim
	if not an or a.done then return end
	a.t = a.t + dt
	local fd = 1 / an.fps
	if a.t < fd then return end
	local adv = floor(a.t / fd)
	a.t = a.t - adv * fd
	local n = #an
	local i = a.i + adv
	if i > n then
		if an.loop then i = (i - 1) % n + 1 else i = n a.done = true end
	end
	if i ~= a.i then
		a.i = i
		A:Frame(a.tex, an, i)
	end
end

St.StepActor = function(a, dt) return Step(a, dt) end
-- the animation's pivot (its feet) at stage (x, y)
local Put
function Put(a, x, y)
	x, y = floor(x + 0.5), floor(y + 0.5)
	if not a.dirty and x == a.x and y == a.y then return end
	local an = a.anim
	if not an then return end
	a.x, a.y, a.dirty = x, y, false
	a.tex:ClearAllPoints()
	a.tex:SetPoint("TOPLEFT", stage, "TOPLEFT", x - an.px * a.scale, -(y - an.py * a.scale))
end

St.PutActor = function(a, x, y) return Put(a, x, y) end
local function Hide(a)
	a.tex:Hide()
	a.name, a.anim = nil, nil
end
St.HideActor = Hide

-- a still sprite placed by its bottom centre
local function Still(t, name, x, y, scale)
	local w, h = A:Sprite(t, name)
	scale = scale or 1
	t:SetSize(w * scale, h * scale)
	t:ClearAllPoints()
	t:SetPoint("BOTTOM", stage, "TOPLEFT", x, -y)
	t:Show()
end

-- ------------------------------------------------------------------ effects and numbers (fixed pools)
local fx, nums = {}, {}
local FX_N, NUM_N = 10, 10

local function Effect(name, x, y, scale, sub)
	local slot
	for i = 1, FX_N do if not fx[i].busy then slot = fx[i] break end end
	if not slot then slot = fx[1] end
	slot.scale = scale or 1
	slot.busy = true
	slot.tex:SetDrawLayer("OVERLAY", sub or 1)
	if not Play(slot, name, true) then slot.busy = false return end
	Put(slot, x, y)
	return slot
end
St.Effect = Effect

local NUM_COLOR = {
	hit = { 1, 0.86, 0.4 }, hurt = { 1, 0.3, 0.25 }, block = { 0.6, 0.8, 1 }, heal = { 0.4, 1, 0.45 }, gold = { 1, 0.82, 0.3 },
}
local function Number(text, kind, x, y)
	local slot
	for i = 1, NUM_N do if not nums[i].busy then slot = nums[i] break end end
	if not slot then slot = nums[1] end
	local c = NUM_COLOR[kind] or NUM_COLOR.hit
	slot.fs:SetText(text)
	slot.fs:SetTextColor(c[1], c[2], c[3])
	slot.busy, slot.t, slot.x, slot.y = true, 0, x, y
	slot.fs:ClearAllPoints()
	slot.fs:SetPoint("CENTER", stage, "TOPLEFT", x, -y)
	slot.fs:SetAlpha(1)
	slot.fs:Show()
end
St.Number = Number

-- ------------------------------------------------------------------ building
local layers = {}
local hero
local foeActors = {}
local doors, doorSym, doorLbl, doorBtn = {}, {}, {}, {}
local prop, propStill, portal, glow
local shadowTex = {}

function St:Build(parent, level)
	if stage then return stage end
	stage = CreateFrame("Frame", nil, parent)
	if level then stage:SetFrameLevel(level) end
	stage:SetSize(W, H)
	St.frame = stage
	stage:SetClipsChildren(true)
	for i, k in ipairs(LAYERS) do
		local t = stage:CreateTexture(nil, "BACKGROUND", nil, i - 8)
		t:SetAllPoints()
		layers[i] = t
	end
	-- the Rift's portal, behind the creatures
	portal = NewActor(stage, "BORDER", 0)
	-- doors and the room's piece
	for i = 1, 3 do
		doors[i] = NewActor(stage, "BORDER", 1)
		doorSym[i] = stage:CreateTexture(nil, "BORDER", nil, 3)
		doorSym[i]:SetSize(48, 48)
		doorLbl[i] = UI:Text(stage, 14, "title")
		local b = CreateFrame("Button", nil, stage)
		b:SetSize(120, 200)
		b:SetFrameLevel(stage:GetFrameLevel() + 6)
		b.i = i
		b:RegisterForClicks("LeftButtonUp")
		b:SetScript("OnClick", function(self) if St.onDoor then St.onDoor(self.i) end end)
		b:SetScript("OnEnter", function(self)
			doors[self.i].tex:SetVertexColor(1, 0.95, 0.75)
			if St.onDoorTip then St.onDoorTip(self, self.i) end
		end)
		b:SetScript("OnLeave", function(self) doors[self.i].tex:SetVertexColor(1, 1, 1) UI:HideTip() end)
		b:Hide()
		doorBtn[i] = b
	end
	prop = NewActor(stage, "BORDER", 2)
	propStill = stage:CreateTexture(nil, "BORDER", nil, 2)
	propStill:Hide()
	local pb = CreateFrame("Button", nil, stage)
	pb:SetSize(140, 200)
	pb:SetFrameLevel(stage:GetFrameLevel() + 6)
	pb:SetPoint("BOTTOM", stage, "TOPLEFT", PROP_X, -GROUND - 10)
	pb:SetScript("OnClick", function() if St.onProp then St.onProp() end end)
	pb:SetScript("OnEnter", function(self) if St.onPropTip then St.onPropTip(self) end end)
	pb:SetScript("OnLeave", function() UI:HideTip() end)
	pb:Hide()
	St.propBtn = pb
	-- soft shadows under the hero and the creatures
	for i = 1, 4 do
		local s = stage:CreateTexture(nil, "BORDER", nil, 5)
		-- a round mask darkened makes an oval when squashed
		if s:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask") == false then s:SetColorTexture(0, 0, 0, 0) end
		s:SetVertexColor(0, 0, 0, 0.35)
		s:SetSize(70, 8)
		s:Hide()
		shadowTex[i] = s
	end
	-- creatures in front of the room, the hero in front of the creatures
	for i = 1, 3 do foeActors[i] = NewActor(stage, "ARTWORK", i) end
	hero = NewActor(stage, "ARTWORK", 5)
	St.hero = hero
	glow = NewActor(stage, "ARTWORK", 6)
	for i = 1, FX_N do fx[i] = NewActor(stage, "OVERLAY", 1) end
	for i = 1, NUM_N do
		local fs = UI:Text(stage, 18, "title")
		fs:Hide()
		nums[i] = { fs = fs }
	end
	return stage
end

-- ------------------------------------------------------------------ the zone
local zoneNow
function St:Zone(z)
	zoneNow = z
	L = LAYOUT[z.bg] or LAYOUT.catacombs
	GROUND, HERO_X, PROP_X = L.ground, L.heroX, L.heroX + 300 * L.k
	St.GROUND = GROUND
	if St.propBtn then
		St.propBtn:ClearAllPoints()
		St.propBtn:SetPoint("BOTTOM", stage, "TOPLEFT", PROP_X, -GROUND - 10)
	end
	for i, k in ipairs(LAYERS) do
		A:Sprite(layers[i], ("BG_%s_%s"):format(z.bg, k))
		layers[i]:Show()
	end
	self:Pan(0)
	if z.id == "rift" then
		portal.scale = 1
		Play(portal, "rift_transition_loop")
		Put(portal, 880, GROUND + 4)
		portal.tex:SetAlpha(0.85)
	else
		Hide(portal)
	end
end

-- the camera: 0..1 across the 10% of each layer the window does not show
local CROP = 0.9
function St:Pan(c)
	self.cam = c
	for i = 1, 3 do
		local name = zoneNow and ("BG_%s_%s"):format(zoneNow.bg, LAYERS[i])
		local r = name and A:Rec(name)
		if r then
			local u0, u1, v0, v1 = r[6], r[7], r[8], r[9]
			local du = (u1 - u0)
			local off = (c * PARALLAX[i]) % 1 * (1 - CROP)
			local dv = (v1 - v0)
			layers[i]:SetTexCoord(u0 + du * off, u0 + du * (off + CROP), v0 + dv * 0.05, v0 + dv * 0.95)
		end
	end
end

function St:Clear()
	for i = 1, 3 do
		Hide(doors[i]) doorSym[i]:Hide() doorLbl[i]:Hide() doorBtn[i]:Hide()
		Hide(foeActors[i])
	end
	for i = 1, 4 do shadowTex[i]:Hide() end
	Hide(prop) propStill:Hide() St.propBtn:Hide()
	Hide(hero) Hide(glow) Hide(portal)
	for i = 1, FX_N do Hide(fx[i]) fx[i].busy = false end
	for i = 1, NUM_N do nums[i].fs:Hide() nums[i].busy = false end
	for i = 1, 3 do layers[i]:Hide() end
	self.heroX = HERO_X
end

-- ------------------------------------------------------------------ doors
St.KIND_SYMBOL = { fight = "door_symbol_fight", elite = "door_symbol_elite_fight", chest = "door_symbol_chest",
	shrine = "door_symbol_shrine", trap = "door_symbol_trap", unknown = "door_symbol_unknown", boss = "door_symbol_elite_fight" }
St.KIND_NAME = { fight = "Fight", elite = "Elite", chest = "Chest", shrine = "Shrine", trap = "Trap", unknown = "Unknown", boss = "Boss" }

function St:Doors(run)
	local z = D:Zone(run.floor)
	self:HideRoom()
	for i = 1, 3 do
		local d = run.doors[i]
		local on = i <= run.ndoors and d and d.kind
		if on then
			local x = run.ndoors == 1 and L.doors[2] or L.doors[i]
			local a = doors[i]
			a.scale = L.doorScale * (run.ndoors == 1 and 1.2 or 1)
			-- a closed door is the opening animation's first frame
			Play(a, z.door .. "_door_opening", true)
			a.done = true
			Put(a, x, GROUND + 2)
			a.tex:SetVertexColor(1, 1, 1)
			local sym = St.KIND_SYMBOL[d.shown] or "door_symbol_unknown"
			A:Sprite(doorSym[i], sym)
			doorSym[i]:ClearAllPoints()
			doorSym[i]:SetPoint("BOTTOM", stage, "TOPLEFT", x, -(GROUND - 150 * a.scale))
			doorSym[i]:Show()
			doorLbl[i]:ClearAllPoints()
			doorLbl[i]:SetPoint("TOP", stage, "TOPLEFT", x, -(GROUND + 8))
			local label = d.kind == "unknown" and d.shown ~= "unknown" and ("? " .. St.KIND_NAME[d.shown]) or St.KIND_NAME[d.shown]
			doorLbl[i]:SetText(("%s  |cffb8a888(%d)|r"):format(label or "?", i))
			doorLbl[i]:Show()
			doorBtn[i]:ClearAllPoints()
			doorBtn[i]:SetPoint("BOTTOM", stage, "TOPLEFT", x, -(GROUND + 26))
			doorBtn[i]:SetSize(130 * a.scale, 230 * a.scale)
			doorBtn[i]:Show()
		else
			Hide(doors[i]) doorSym[i]:Hide() doorLbl[i]:Hide() doorBtn[i]:Hide()
		end
	end
	self.heroX = L.idleX
	self.walkTo = nil
end

function St:OpenDoor(i)
	local a = doors[i]
	if a.anim then a.done, a.t, a.i = false, 0, 1 end
	for k = 1, 3 do doorBtn[k]:Hide() if k ~= i then doorSym[k]:Hide() doorLbl[k]:Hide() end end
	self.walkTo = a.x
end

function St:HideDoors()
	for i = 1, 3 do Hide(doors[i]) doorSym[i]:Hide() doorLbl[i]:Hide() doorBtn[i]:Hide() end
end

-- ------------------------------------------------------------------ the room's piece
function St:HideRoom()
	Hide(prop) propStill:Hide() St.propBtn:Hide()
end

-- the room behind the door: the hero walks in while the camera pans
function St:Room(run)
	self:HideDoors()
	self:HideRoom()
	local room = run.room
	self.heroX = HERO_X - 160 * L.k
	self.walkTo = HERO_X
	self.panFrom, self.panT = self.cam, 0
	if room.kind == "chest" then
		if room.mimic and run.perk == "lantern" then
			Still(propStill, "cask_mimic_disguised", PROP_X, GROUND + 4)
			propStill:SetVertexColor(1, 0.7, 0.7)
		else
			Still(propStill, ("chest_%s_closed"):format(room.tier), PROP_X, GROUND + 4)
			propStill:SetVertexColor(1, 1, 1)
		end
		St.propBtn:Show()
	elseif room.kind == "shrine" then
		prop.scale = 1
		Play(prop, ("shrine_%s_idle"):format(room.shrine), true)
		Put(prop, PROP_X, GROUND + 4)
		St.propBtn:Show()
	elseif room.kind == "trap" and room.trap then
		Still(propStill, ("trap_%s_hidden"):format(room.trap), HERO_X + 10, GROUND + 18, 0.9)
		propStill:SetVertexColor(1, 1, 1)
	end
end

function St:OpenChest(tier)
	propStill:Hide()
	prop.scale = 1
	Play(prop, ("chest_%s_opening"):format(tier), true)
	Put(prop, PROP_X, GROUND + 4)
	Effect("chest_glow_effect", PROP_X, GROUND - 10)
	Effect("coin_burst_effect", PROP_X, GROUND - 30)
	St.propBtn:Hide()
end

function St:UseShrine(kind)
	A:Sprite(propStill, ("shrine_%s_used"):format(kind))
	Hide(prop)
	Still(propStill, ("shrine_%s_used"):format(kind), PROP_X, GROUND + 4)
	St.propBtn:Hide()
end

function St:SpringTrap(kind)
	propStill:Hide()
	prop.scale = 0.9
	Play(prop, ("trap_%s_triggered"):format(kind), true)
	Put(prop, HERO_X + 10, GROUND + 18)
	Effect("trap_trigger_effect", HERO_X, GROUND - 20)
end

function St:HideProp() Hide(prop) propStill:Hide() St.propBtn:Hide() end

-- ------------------------------------------------------------------ hero and creatures
-- the hero's base animation follows the run; one-shots (strike, impact, hurt, pickup) play over it
local function HeroBase(run)
	if not run then return "hero_idle" end
	if run.phase == "dead" then return "hero_death" end
	if run.phase == "home" then return "hero_teleport_out" end
	if St.walkTo then return "hero_walk" end
	if run.cast then return "hero_channel" end
	if run.blocking then return "hero_block_hold" end
	return "hero_idle"
end

function St:HeroOnce(name)
	if self.heroFinal then return end
	hero.once = true
	Play(hero, name, true)
end

function St:HeroFinal(name)
	self.heroFinal = true
	hero.once = false
	Play(hero, name, true)
end

function St:ResetHero()
	self.heroFinal = false
	hero.once = false
	hero.tex:SetVertexColor(1, 1, 1)
	self.heroFlash = 0
end

function St:FoeX(slot) local f = self.run and self.run.foes[slot] return VX(f and f.x or 600) end

local FOE_ANIM = { walk = "_walk", idle = "_idle", tele = "_telegraph", attack = "_attack", dead = "_death" }
St.animName = {}
local function FoeAnimName(id, state, special)
	local key = special and (state == "attack") and "special" or state
	local byId = St.animName[id]
	if not byId then byId = {} St.animName[id] = byId end
	local n = byId[key]
	if not n then
		n = id .. (key == "special" and "_special" or FOE_ANIM[state] or "_idle")
		if not A:Anim(n) then n = id .. "_attack" end
		byId[key] = n
	end
	return n
end

function St:Hurt(slot)
	local f = self.run and self.run.foes[slot]
	local a = f and f.vis
	if a then a.flash = 0.15 a.tex:SetVertexColor(1, 0.55, 0.55) end
end

-- a shadow moves only when its owner does (the anchor calls are the costly part)
local shX, shW = {}, {}
local function Shadow(i, x, w)
	x = floor(x + 0.5)
	local s = shadowTex[i]
	if shX[i] ~= x then
		shX[i] = x
		s:ClearAllPoints()
		s:SetPoint("CENTER", stage, "TOPLEFT", x, -GROUND - 2)
	end
	if shW[i] ~= w then shW[i] = w s:SetSize(w, w == 70 and 9 or 11) end
end

-- ------------------------------------------------------------------ one frame
function St:Update(dt, run)
	self.run = run
	-- walking (door, room entry) and the camera
	if self.walkTo then
		local speed = 260
		local d = self.walkTo - self.heroX
		local s = speed * dt
		if d > s then self.heroX = self.heroX + s
		elseif d < -s then self.heroX = self.heroX - s
		else self.heroX = self.walkTo self.walkTo = nil end
		if self.panT then
			self.panT = self.panT + dt
			self:Pan(self.panFrom + min(1, self.panT / 0.8) * 0.5)
			if self.panT >= 0.8 then self.panT = nil end
		end
	end
	-- the hero
	if hero.once and hero.done then hero.once = false end
	if not hero.once and not self.heroFinal then
		local base = HeroBase(run)
		if hero.name ~= base then Play(hero, base, true) end
	end
	Step(hero, dt)
	Put(hero, self.heroX or HERO_X, GROUND)
	if self.heroFlash and self.heroFlash > 0 then
		self.heroFlash = self.heroFlash - dt
		if self.heroFlash <= 0 then hero.tex:SetVertexColor(1, 1, 1) end
	end
	-- the hearth's swirl around the hero while casting
	if run and run.cast then
		if not glow.name or glow.done then
			glow.scale = 0.9
			Play(glow, "hearth_swirl_effect", true)
		end
		Step(glow, dt)
		Put(glow, self.heroX or HERO_X, GROUND + 2)
		glow.tex:SetAlpha(run.castPaused and 0.35 or 0.9)
	elseif glow.name then
		Hide(glow)
	end
	-- creatures
	local sh = 1
	Shadow(1, self.heroX or HERO_X, 70)
	shadowTex[1]:SetShown(hero.tex:IsShown())
	if run then
		for i = 1, 3 do
			local f = run.foes[i]
			if f.on and f.delay <= 0 then
				local a = f.vis
				if not a then
					for k = 1, 3 do
						local cand = foeActors[k]
						local used = false
						for j = 1, 3 do if run.foes[j].vis == cand then used = true end end
						if not used then a = cand break end
					end
					f.vis = a
					if a then
						a.flash = nil
						if f.elite then a.tex:SetVertexColor(1, 0.85, 0.6) else a.tex:SetVertexColor(1, 1, 1) end
					end
				end
				if a then
					a.scale = f.elite and 1.15 or 1
					local name = FoeAnimName(f.id, f.state, f.special)
					if a.name ~= name then Play(a, name, true) end
					Step(a, dt)
					Put(a, VX(f.x), GROUND + (f.boss and 4 or 0))
					if a.flash then
						a.flash = a.flash - dt
						if a.flash <= 0 then
							a.flash = nil
							if f.elite then a.tex:SetVertexColor(1, 0.85, 0.6) else a.tex:SetVertexColor(1, 1, 1) end
						end
					end
					if f.state == "dead" then a.tex:SetAlpha(max(0, f.t / 30)) else a.tex:SetAlpha(1) end
					sh = sh + 1
					if shadowTex[sh] then
						Shadow(sh, VX(f.x), f.boss and 160 or 80)
						shadowTex[sh]:Show()
					end
				end
			elseif f.vis then
				if not f.on then Hide(f.vis) f.vis = nil end
			end
		end
	end
	for k = sh + 1, 4 do shadowTex[k]:Hide() end
	-- the room's piece and the doors
	if prop.anim then Step(prop, dt) end
	for i = 1, 3 do if doors[i].anim then Step(doors[i], dt) end end
	if portal.anim then Step(portal, dt) end
	-- effects
	for i = 1, FX_N do
		local e = fx[i]
		if e.busy then
			Step(e, dt)
			if e.done then e.busy = false Hide(e) end
		end
	end
	for i = 1, NUM_N do
		local n = nums[i]
		if n.busy then
			n.t = n.t + dt
			if n.t >= 1 then n.busy = false n.fs:Hide()
			else
				n.fs:SetPoint("CENTER", stage, "TOPLEFT", n.x, -(n.y - n.t * 50))
				n.fs:SetAlpha(1 - n.t * n.t)
			end
		end
	end
end

-- ------------------------------------------------------------------ rules events
local FOE_TOP = 120
function St:Event(run, code, a, b, c)
	self.run = run
	local hx = self.heroX or HERO_X
	if code == "strike" then
		local f = run.foes[a]
		local fx = VX(f.x)
		self:HeroOnce(self.altStrike and "hero_strike_b" or "hero_strike_a")
		self.altStrike = not self.altStrike
		Effect(self.altStrike and "strike_slash_a_effect" or "strike_slash_b_effect", fx - 30, GROUND - 10)
		Effect("hit_flash_effect", fx, GROUND - 50)
		Number(tostring(b), "hit", fx, GROUND - (f.boss and 220 or FOE_TOP))
		self:Hurt(a)
	elseif code == "tele" then
		local f = run.foes[a]
		Effect("telegraph_glow_effect", VX(f.x), GROUND + 6, b == 1 and 1.6 or (f.boss and 1.3 or 1), 0)
	elseif code == "blocked" then
		self:HeroOnce("hero_block_impact")
		Effect("block_sparks_effect", hx + 40, GROUND - 50)
		Number(c and c > 0 and ("-" .. c) or "Blocked", "block", hx, GROUND - 140)
	elseif code == "hurt" then
		self:HeroOnce("hero_hurt")
		hero.tex:SetVertexColor(1, 0.45, 0.45)
		self.heroFlash = 0.2
		Number("-" .. b, "hurt", hx, GROUND - 140)
	elseif code == "cloak" then
		Number("Cloak!", "block", hx, GROUND - 140)
	elseif code == "trap" then
		hero.tex:SetVertexColor(1, 0.45, 0.45)
		self.heroFlash = 0.2
		if b ~= 1 then self:HeroOnce("hero_hurt") end
		Number("-" .. a, "hurt", hx, GROUND - 140)
	elseif code == "die" then
		local f = run.foes[a]
		Effect("death_wisp_effect", VX(f.x), GROUND - 10)
	elseif code == "heal" then
		Number("+" .. a, "heal", hx, GROUND - 150)
		Effect("shrine_blessing_effect", hx, GROUND, 1.2)
	elseif code == "bless" then
		Effect("shrine_blessing_effect", hx, GROUND, 1.2)
		Number("Blessed!", "gold", hx, GROUND - 150)
	elseif code == "take" or code == "swap" or code == "bagged" then
		if code ~= "bagged" then self:HeroOnce("hero_loot_pickup") end
	elseif code == "home" then
		self:HeroFinal("hero_teleport_out")
		Effect("teleport_burst_effect", hx, GROUND + 2)
	elseif code == "dead" then
		self:HeroFinal("hero_death")
		Effect("death_wisp_effect", hx, GROUND - 10)
	elseif code == "mimic" then
		propStill:Hide()
		St.propBtn:Hide()
	elseif code == "won" then
		if run.room and run.room.kind == "boss" then self:HeroOnce("hero_victory") end
	end
end
