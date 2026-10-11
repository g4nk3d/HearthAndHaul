--[[ Hearth & Haul - UI/Widgets.lua
	The game's own controls, drawn with its carved-wood-and-brass art. Every screen uses these, so
	they look and sound the same everywhere. Labels are always live text.

	  UI:Text(parent, size, role [, justify])   role: "light" (on wood/dark), "ink" (on parchment), "title"
	  UI:Slice3(parent, layer, sub, sprite, h, capFrac)   a 3-slice strip: ends keep shape, middle stretches;
	                                       returns a holder with :SetShown/:SetAlpha/:SetVertexColor
	  UI:Slice9(parent, layer, sub, sprite, corner [, srcCorner])   a 9-slice box filling parent
	  UI:Wide(parent, label, w, fn [, sound])   3-slice button (normal/hover/pressed/disabled)
	  UI:Square(parent, icon, size, tip, fn)    square icon button
	  UI:Close(parent, fn)                      the X
	  UI:Check(parent, label, get, set)         tick box
	  UI:Tip(owner, title, text)                the game's own tooltip (tooltip art, live text) ]]

local _, ns = ...
local P = ns.P
local UI = P:Module("UI")
local A, Au = P.Assets, P.Audio

local PARCH = { 0.97, 0.88, 0.68 }
local INK = { 0.24, 0.15, 0.07 }
local GOLD = { 1, 0.82, 0.42 }
UI.PARCH, UI.INK, UI.GOLD = PARCH, INK, GOLD
local BODY_FONT = "Fonts\\FRIZQT__.TTF"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"

function UI:Text(parent, size, role, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	local serif = role == "title"
	local font = serif and TITLE_FONT or (STANDARD_TEXT_FONT or BODY_FONT)
	local flags = (role == "ink") and "" or "OUTLINE"
	if not fs:SetFont(font, size, flags) then fs:SetFont(BODY_FONT, size, flags) end
	local c = role == "ink" and INK or (role == "title" and GOLD or PARCH)
	fs:SetTextColor(c[1], c[2], c[3])
	if role ~= "ink" then
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 0.85)
	end
	fs:SetJustifyH(justify or "CENTER")
	return fs
end

-- ------------------------------------------------------------------ slices
-- texcoords of a sub-rectangle (atlas pixels inside the sprite: x0..x1, y0..y1)
local function Sub(t, name, x0, x1, y0, y1)
	local s = A:Rec(name)
	if not s then A:Sprite(t, name) return end
	local size = A.texSize[s[1]]
	local aw, ah = size[2], size[3]
	t:SetTexture(A.TEX .. s[1])
	t:SetTexCoord((s[2] + x0) / aw, (s[2] + x1) / aw, (s[3] + y0) / ah, (s[3] + y1) / ah)
end
UI.Sub = Sub

local Holder = {}
Holder.__index = Holder
function Holder:SetShown(on) for i = 1, #self do self[i]:SetShown(on) end end
function Holder:Show() self:SetShown(true) end
function Holder:Hide() self:SetShown(false) end
function Holder:SetAlpha(a) for i = 1, #self do self[i]:SetAlpha(a) end end
function Holder:SetVertexColor(r, g, b, a) for i = 1, #self do self[i]:SetVertexColor(r, g, b, a) end end
function Holder:SetDesaturated(on) for i = 1, #self do if self[i].SetDesaturated then self[i]:SetDesaturated(on) end end end

-- capFrac: the end caps' share of the source width (the kit's 3-slices use 20%)
function UI:Slice3(parent, layer, sub, name, h, capFrac)
	local s = A:Rec(name)
	if not s then return setmetatable({}, Holder) end
	local sw, sh = s[4], s[5]
	local cap = math.floor(sw * (capFrac or 0.2) + 0.5)
	local capW = h * cap / sh
	local l, m, r = parent:CreateTexture(nil, layer, nil, sub), parent:CreateTexture(nil, layer, nil, sub),
		parent:CreateTexture(nil, layer, nil, sub)
	Sub(l, name, 0, cap, 0, sh)
	Sub(m, name, cap, sw - cap, 0, sh)
	Sub(r, name, sw - cap, sw, 0, sh)
	l:SetSize(capW, h)
	r:SetSize(capW, h)
	l:SetPoint("LEFT", parent, "LEFT", 0, 0)
	r:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	m:SetPoint("TOPLEFT", l, "TOPRIGHT")
	m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
	return setmetatable({ l, m, r }, Holder)
end

-- corner: display size of each corner; srcCorner: corner size in the sprite (default a quarter)
function UI:Slice9(parent, layer, sub, name, corner, srcCorner)
	local s = A:Rec(name)
	if not s then return setmetatable({}, Holder) end
	local sw, sh = s[4], s[5]
	local c = srcCorner or math.floor(sw / 4)
	local t = {}
	local xs = { { 0, c }, { c, sw - c }, { sw - c, sw } }
	local ys = { { 0, c }, { c, sh - c }, { sh - c, sh } }
	for row = 1, 3 do
		for col = 1, 3 do
			local tex = parent:CreateTexture(nil, layer, nil, sub)
			Sub(tex, name, xs[col][1], xs[col][2], ys[row][1], ys[row][2])
			t[#t + 1] = tex
		end
	end
	-- corners fixed, edges and middle stretch
	local tl, tm, tr, ml, mm, mr, bl, bm, br = unpack(t)
	for _, k in ipairs({ tl, tr, bl, br }) do k:SetSize(corner, corner) end
	tl:SetPoint("TOPLEFT", parent, "TOPLEFT")
	tr:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
	bl:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT")
	br:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")
	tm:SetPoint("TOPLEFT", tl, "TOPRIGHT") tm:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
	bm:SetPoint("TOPLEFT", bl, "TOPRIGHT") bm:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
	ml:SetPoint("TOPLEFT", tl, "BOTTOMLEFT") ml:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
	mr:SetPoint("TOPLEFT", tr, "BOTTOMLEFT") mr:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
	mm:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT") mm:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
	return setmetatable(t, Holder)
end

-- ------------------------------------------------------------------ tooltip
local tip
-- the tooltip art's carved rim is about 20 px deep at this size: the words keep clear of it
local TIP_PAD_X, TIP_PAD_TOP, TIP_PAD_BOTTOM, TIP_BODY_W = 26, 22, 24, 250
local function TipFrame()
	if tip then return tip end
	tip = CreateFrame("Frame", nil, UIParent)
	tip:SetFrameStrata("TOOLTIP")
	tip:SetClampedToScreen(true)
	tip:Hide()
	UI:Slice9(tip, "BACKGROUND", 0, "tooltip", 22, 40)
	tip.title = UI:Text(tip, 14, "title", "LEFT")
	tip.title:SetPoint("TOPLEFT", TIP_PAD_X, -TIP_PAD_TOP)
	tip.title:SetWordWrap(false)
	tip.body = UI:Text(tip, 12, "light", "LEFT")
	tip.body:SetPoint("TOPLEFT", tip.title, "BOTTOMLEFT", 0, -6)
	tip.body:SetSpacing(2)
	return tip
end

-- the tip sits above (or below) its owner and is kept inside the game window, so it never hangs off the
-- window's edge; its height comes from the body's wrapped lines
function UI:ShowTip(owner, title, text)
	local t = TipFrame()
	t:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
	t.title:SetText(title or "")
	local hasBody = text ~= nil and text ~= ""
	t.body:SetShown(hasBody)
	local tw = t.title.GetUnboundedStringWidth and t.title:GetUnboundedStringWidth() or t.title:GetStringWidth()
	local bodyW, bodyH = 0, 0
	if hasBody then
		t.body:SetWidth(TIP_BODY_W)
		t.body:SetText(text)
		local full = t.body.GetUnboundedStringWidth and t.body:GetUnboundedStringWidth() or t.body:GetStringWidth()
		bodyW = math.min(TIP_BODY_W, full)
		t.body:SetWidth(math.max(bodyW, math.min(TIP_BODY_W, tw)))
		local lineH = select(2, t.body:GetFont()) or 12
		local lines = t.body.GetNumLines and t.body:GetNumLines() or 0
		local est = 0
		for _ in (text .. "\n"):gmatch("([^\n]*)\n") do est = est + 1 end
		est = math.max(est, math.ceil(full / TIP_BODY_W))
		lines = math.max(lines or 0, est)
		bodyH = math.max(t.body:GetStringHeight() or 0, lines * (lineH + 2))
	end
	local w = math.max(tw, bodyW) + 2 * TIP_PAD_X
	local h = TIP_PAD_TOP + (t.title:GetStringHeight() or 14) + (hasBody and (6 + bodyH) or 0) + TIP_PAD_BOTTOM
	t:SetSize(w, h)
	t:ClearAllPoints()
	-- inside the game window: owner and window share the same scale, and the tip was scaled to match
	local G = P.Game
	local W = G and G.W
	local ol, or_, ot, ob = owner:GetLeft(), owner:GetRight(), owner:GetTop(), owner:GetBottom()
	if W and W:IsShown() and ol and W:GetLeft() and owner:GetEffectiveScale() == W:GetEffectiveScale() then
		local wl, wr, wt, wb = W:GetLeft() + 14, W:GetRight() - 14, W:GetTop() - 14, W:GetBottom() + 14
		local cx = (ol + or_) / 2
		local x = math.max(wl, math.min(wr - w, cx - w / 2))
		local y
		if ot + 6 + h <= wt then y = ot + 6 + h            -- above the owner
		elseif ob - 6 - h >= wb then y = ob - 6            -- below it
		else y = math.min(wt, math.max(wb + h, ot)) end
		t:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x * owner:GetEffectiveScale() / t:GetEffectiveScale(),
			y * owner:GetEffectiveScale() / t:GetEffectiveScale())
	else
		t:SetPoint("BOTTOM", owner, "TOP", 0, 6)
	end
	t:Show()
end

function UI:HideTip() if tip then tip:Hide() end end

function UI:Tip(owner, title, text)
	owner:HookScript("OnEnter", function(self)
		local tt, tx = title, text
		if type(tt) == "function" then tt, tx = tt(self) end
		if tt then UI:ShowTip(self, tt, tx) end
	end)
	owner:HookScript("OnLeave", function() UI:HideTip() end)
end

-- ------------------------------------------------------------------ buttons
local function Hover(b)
	b:HookScript("OnEnter", function(self) if self:IsEnabled() then Au:Play("ui_hover") end end)
end

function UI:Wide(parent, label, w, fn, sound)
	local h = math.floor(w / 4 + 0.5)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	b.n = UI:Slice3(b, "ARTWORK", 0, "wide_button_normal", h)
	b.h = UI:Slice3(b, "ARTWORK", 1, "wide_button_hover", h)
	b.p = UI:Slice3(b, "ARTWORK", 2, "wide_button_pressed", h)
	b.d = UI:Slice3(b, "ARTWORK", 3, "wide_button_disabled", h)
	b.h:Hide() b.p:Hide() b.d:Hide()
	b.label = UI:Text(b, math.max(11, math.floor(h * 0.36)), "ink")
	b.label:SetPoint("CENTER", 0, 1)
	b.label:SetWordWrap(false)
	-- the words stay on the parchment plank between the two hearthstone caps (measured on the art: x 68..188
	-- of 256 at its middle row, 0.47 of the width): a long label is set smaller until it fits there
	local full = math.max(11, math.floor(h * 0.36))
	local room = w * 0.44
	local function Fit(text)
		b.label:SetText(text)
		local font, _, flags = b.label:GetFont()
		for size = full, 9, -1 do
			if font then b.label:SetFont(font, size, flags) end
			local sw = b.label.GetUnboundedStringWidth and b.label:GetUnboundedStringWidth() or b.label:GetStringWidth()
			if not sw or sw <= room then break end
		end
	end
	b.FitLabel = Fit
	Fit(label)
	b:SetScript("OnEnter", function(self) if self:IsEnabled() then self.h:Show() end end)
	b:SetScript("OnLeave", function(self) self.h:Hide() self.p:Hide() end)
	b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.p:Show() end end)
	b:SetScript("OnMouseUp", function(self) self.p:Hide() end)
	b:SetScript("OnClick", function() Au:Play(sound or "ui_click") fn() end)
	b:HookScript("OnDisable", function(self) self.d:Show() self.n:Hide() self.h:Hide() self.label:SetAlpha(0.5) end)
	b:HookScript("OnEnable", function(self) self.d:Hide() self.n:Show() self.label:SetAlpha(1) end)
	Hover(b)
	function b:SetLabel(t) self.FitLabel(t) end
	return b
end

function UI:Square(parent, icon, size, tip, fn)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	local function Layer(name, sub)
		local t = b:CreateTexture(nil, "ARTWORK", nil, sub)
		A:Sprite(t, name)
		t:SetAllPoints()
		return t
	end
	b.n, b.h, b.p, b.d = Layer("square_button_normal", 0), Layer("square_button_hover", 1),
		Layer("square_button_pressed", 2), Layer("square_button_disabled", 3)
	b.h:Hide() b.p:Hide() b.d:Hide()
	b.icon = b:CreateTexture(nil, "OVERLAY")
	A:Sprite(b.icon, icon)
	b.icon:SetSize(size * 0.62, size * 0.62)
	b.icon:SetPoint("CENTER")
	b:SetScript("OnEnter", function(self) if self:IsEnabled() then self.h:Show() end end)
	b:SetScript("OnLeave", function(self) self.h:Hide() self.p:Hide() end)
	b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.p:Show() self.icon:SetPoint("CENTER", 1, -1) end end)
	b:SetScript("OnMouseUp", function(self) self.p:Hide() self.icon:SetPoint("CENTER") end)
	b:SetScript("OnClick", function() Au:Play("ui_click") fn() end)
	b:HookScript("OnDisable", function(self) self.d:Show() self.icon:SetDesaturated(true) self.icon:SetAlpha(0.5) end)
	b:HookScript("OnEnable", function(self) self.d:Hide() self.icon:SetDesaturated(false) self.icon:SetAlpha(1) end)
	if tip then UI:Tip(b, tip) end
	Hover(b)
	function b:SetIcon(name) A:Sprite(self.icon, name) end
	return b
end

function UI:Close(parent, fn)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(30, 30)
	local function Layer(name, sub)
		local t = b:CreateTexture(nil, "ARTWORK", nil, sub)
		A:Sprite(t, name)
		t:SetAllPoints()
		return t
	end
	b.n, b.h, b.p = Layer("close_normal", 0), Layer("close_hover", 1), Layer("close_pressed", 2)
	b.h:Hide() b.p:Hide()
	b:SetScript("OnEnter", function(self) self.h:Show() end)
	b:SetScript("OnLeave", function(self) self.h:Hide() self.p:Hide() end)
	b:SetScript("OnMouseDown", function(self) self.p:Show() end)
	b:SetScript("OnMouseUp", function(self) self.p:Hide() end)
	b:SetScript("OnClick", function() Au:Play("ui_cancel") fn() end)
	Hover(b)
	return b
end

function UI:Check(parent, label, get, set, tipText)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(260, 26)
	b.box = b:CreateTexture(nil, "ARTWORK")
	b.box:SetSize(26, 26)
	b.box:SetPoint("LEFT")
	b.label = UI:Text(b, 13, "light", "LEFT")
	b.label:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
	b.label:SetText(label)
	b.hover = false
	function b:Refresh()
		local on = get() and true or false
		local name
		if not self:IsEnabled() then name = "checkbox_disabled"
		elseif self.hover then name = on and "checkbox_hover_on" or "checkbox_hover_off"
		else name = on and "checkbox_on" or "checkbox_off" end
		A:Sprite(self.box, name)
	end
	b:SetScript("OnEnter", function(self) self.hover = true self:Refresh() end)
	b:SetScript("OnLeave", function(self) self.hover = false self:Refresh() end)
	b:SetScript("OnClick", function(self)
		local v = not get()
		Au:Play(v and "ui_checkbox_on" or "ui_checkbox_off")
		set(v)
		self:Refresh()
	end)
	if tipText then UI:Tip(b, label, tipText) end
	Hover(b)
	b:Refresh()
	return b
end
