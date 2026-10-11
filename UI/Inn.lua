--[[ Hearth & Haul - UI/Inn.lua
	The Sleeping Gryphon, between dives: Marga at the bar, Dunstan and Lira, Pip by the fire, the stash
	chest, the notice board and the cellar stairs. Everything you do between dives starts by clicking
	something in the room (or its key):

	  the cellar stairs (Enter)   choose a perk and dive
	  the notice board (N)        today's daily dive and your records
	  the stash chest (S)         furnish the inn with banked gold
	  Marga (?)                   how to play
	  Pip                         a cat; he judges you

	  In:Build(stage)             made once, over the stage
	  In:Show(mood)               mood: "arrive" (back from a dive), "banked", "dead" or nil
	  In:Hide(), In:Update(dt), In:Refresh()   (Refresh: the furnishings bought) ]]

local _, ns = ...
local P = ns.P
local In = P:Module("Inn")
local A, Au, UI, St = P.Assets, P.Audio, P.UI, P.Stage
local D = ns.Data

local f
local bg, fire, marga, dunstan, lira, pip, chest, hero
local decor = {}
local hot = {}
local pipT, chatter = 0, 0

local function Actor(scale, sub)
	local a = St.NewActor(f, "ARTWORK", sub or 1)
	a.scale = scale or 1
	return a
end

-- a hot spot: an invisible button over part of the picture
local function Hot(x, y, w, h, title, text, fn)
	local b = CreateFrame("Button", nil, f)
	b:SetSize(w, h)
	b:SetPoint("CENTER", f, "TOPLEFT", x, -y)
	b:SetFrameLevel(f:GetFrameLevel() + 5)
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", function() Au:Play("ui_click") fn() end)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	b.hl:SetVertexColor(1, 0.85, 0.5, 0.18)
	b.hl:SetBlendMode("ADD")
	UI:Tip(b, title, text)
	hot[#hot + 1] = b
	return b
end

function In:Build(stage)
	if f then return f end
	f = CreateFrame("Frame", nil, stage)
	f:SetAllPoints(stage)
	f:SetFrameLevel(stage:GetFrameLevel() + 2)
	In.frame = f
	bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	A:Sprite(bg, "BG_inn")
	-- the furnishings, under everyone
	for i, d in ipairs(D.DECOR) do
		local t = f:CreateTexture(nil, "BORDER", nil, 1)
		t:SetSize(d.w, d.h)
		t:SetPoint("CENTER", f, "TOPLEFT", d.x, -d.y)
		A:Sprite(t, d.sprite)
		t:Hide()
		decor[d.id] = t
	end
	fire = Actor(0.75, 0)
	chest = f:CreateTexture(nil, "ARTWORK", nil, 0)
	marga = Actor(0.9, 2)
	dunstan = Actor(0.95, 2)
	lira = Actor(0.95, 2)
	pip = Actor(0.8, 3)
	hero = Actor(1, 4)
	self.chestFx = Actor(0.75, 1)

	local G = P.Game
	Hot(868, 186, 120, 116, "The cellar stairs  (Enter)", "Down into the Undercroft. Pick a perk, then dive: every find you carry home is banked.", function() G:Screen("perk") end)
	Hot(717, 152, 84, 82, "The notice board  (N)", "Today's daily dive (the same floors for everyone), your records and achievements.", function() G:Screen("board") end)
	Hot(150, 276, 96, 80, "The stash chest  (S)", "Spend banked gold on furnishings for the inn.", function() G:Screen("stash") end)
	Hot(520, 210, 90, 170, "Marga, the innkeeper  (?)", "She has seen a hundred adventurers go down those stairs. Ask her how it works.", function() G:Screen("help") end)
	Hot(330, 228, 70, 40, "Pip", "The inn's cat. Unimpressed.", function()
		St.Play(pip, "pip_tail_flick", true)
		pipT = 0
	end)
	f:Hide()
	return f
end

function In:Refresh()
	if not f then return end
	local Pr = P.Progress
	for _, d in ipairs(D.DECOR) do decor[d.id]:SetShown(Pr:Owns("decor", d.id)) end
end

local function Place(a, name, x, y)
	St.Play(a, name, true)
	St.PutActor(a, x, y)
end

function In:Show(mood)
	if not f then return end
	f:Show()
	self:Refresh()
	Place(fire, "fireplace_fire_loop", 265, 238)
	fire.tex:SetBlendMode("BLEND")
	A:Sprite(chest, "stash_chest_closed")
	chest:SetSize(96, 96)
	chest:ClearAllPoints()
	chest:SetPoint("BOTTOM", f, "TOPLEFT", 150, -312)
	Place(dunstan, mood == "banked" and "dunstan_cheer" or "dunstan_idle", 395, 302)
	Place(lira, mood == "banked" and "lira_cheer" or "lira_idle", 652, 300)
	Place(pip, "pip_sleep", 330, 244)
	local mg = (mood == "banked" and "marga_cheer") or (mood == "dead" and "marga_worried") or (mood == "arrive" and "marga_wave") or "marga_idle"
	Place(marga, mg, 520, 294)
	if mood then Place(hero, "hero_arrive_inn", 780, 340) else Place(hero, "hero_idle", 780, 340) end
	if mood == "banked" then
		Place(self.chestFx, "stash_chest_coins", 150, 312)
	else
		St.HideActor(self.chestFx)
	end
	pipT, chatter = 0, 0
end

function In:Hide() if f then f:Hide() end end
function In:Shown() return f ~= nil and f:IsShown() end

-- one-shot animations settle back to their idle loops (the lists are made once: the frame loop allocates nothing)
local people, idles
function In:Update(dt)
	if not f or not f:IsShown() then return end
	local Step = St.StepActor
	Step(fire, dt)
	if not people then
		people = { marga, dunstan, lira, hero }
		idles = { "marga_idle", "dunstan_idle", "lira_idle", "hero_idle" }
	end
	for i = 1, 4 do
		local a = people[i]
		Step(a, dt)
		if a.done then
			local x, y = a.x, a.y
			St.Play(a, idles[i], true)
			St.PutActor(a, x, y)
		end
	end
	Step(pip, dt)
	pipT = pipT + dt
	if pip.done and pipT > 3 then
		pipT = 0
		St.Play(pip, "pip_sleep", true)
	end
	if self.chestFx.anim then
		Step(self.chestFx, dt)
		if self.chestFx.done then St.HideActor(self.chestFx) end
	end
end

-- a purchase: coins tumble into the chest
function In:Coins()
	if not f then return end
	St.Play(self.chestFx, "stash_chest_coins", true)
	St.PutActor(self.chestFx, 150, 312)
	St.Play(marga, "marga_cheer", true)
	St.PutActor(marga, 520, 294)
end
