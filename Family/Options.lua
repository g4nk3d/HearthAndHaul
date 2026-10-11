--[[ Hearth & Haul - Family/Options.lua
	Esc > Options > AddOns > Hearth & Haul: every switch, the window size and a Play button. It has the Nether
	family look and follows the current NetherUI theme when NetherUI is installed (Family/Skin.lua); the
	game's own screens keep Hearth & Haul's art. Always there, NetherSuite or not.

	  P.Options:Open()   show this page in the game's settings ]]

local _, ns = ...
local P = ns.P
local Options = P:Module("Options")
local W, Skin = P.Widgets, P.Skin

local function CloseSettings()
	local sp = rawget(_G, "SettingsPanel")
	if sp and sp:IsShown() and HideUIPanel then HideUIPanel(sp) end
end

function Options:Build()
	local SS = rawget(_G, "Settings")
	if type(SS) ~= "table" or not SS.RegisterCanvasLayoutCategory or not SS.RegisterAddOnCategory or self.panel then return end
	local p = CreateFrame("Frame")
	p:Hide()
	p.widgets = {}
	self.panel = p
	-- the page is registered at login but its contents are made the first time it is shown
	p:SetScript("OnShow", function() Options:Fill() W.Refresh(p) end)
	local ok, cat = pcall(SS.RegisterCanvasLayoutCategory, p, "Hearth & Haul")
	if ok and cat then
		pcall(SS.RegisterAddOnCategory, cat)
		self.category = cat
	end
end

function Options:Fill()
	local p = self.panel
	if not p or p.filled then return end
	p.filled = true

	local logo = p:CreateTexture(nil, "ARTWORK")
	logo:SetSize(52, 52)
	logo:SetPoint("TOPLEFT", 16, -14)
	logo:SetTexture(P.MEDIA .. "Logo")
	local title = W.Text(p, "title", 22, "header")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -6)
	title:SetText("Hearth & Haul  " .. P.VERSION)
	local about = W.Text(p, "body", 12, "text")
	about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	about:SetText("Dive the Undercroft below the Sleeping Gryphon, fight with block and strike, and hearth home before the creatures knock your cast back: everything you carry home is banked.")
	about:SetWidth(560)

	local st = W.Stack(p, 16, -86)
	local function C(key, label, tip)
		local cb = W.Check(p, label, function() return P:Setting(key) end, function(v) P:SetSetting(key, v) end, tip)
		p.widgets[#p.widgets + 1] = cb
		st:Add(cb, 30)
	end
	C("music", "Music")
	C("sound", "Sound effects")
	C("nudge", "Remind me after 20 minutes of play", "Marga suggests a break after twenty minutes with the game open. Off unless you turn it on.")
	C("minimapButton", "Show the minimap button")
	C("shareScores", "Share daily scores with other players", "Your best daily dive goes to other Hearth & Haul players (the Nether games' shared hidden channel and your guild), and theirs come to you. Every haul is checked by replaying the dive.")
	C("followNetherUI", "Follow NetherUI's theme", "This page takes your current NetherUI theme (when NetherUI is installed). The game itself keeps Hearth & Haul's art.")
	local size = W.Cycle(p, "Window size", function()
		return { { 0.6, "Small" }, { 0.75, "Medium" }, { 0.9, "Large" }, { 1, "Fill the screen" } }
	end, function() return P:Setting("size") end, function(v)
		P:SetSetting("size", v)
	end)
	p.widgets[#p.widgets + 1] = size
	st:Add(size, 36)
	st:Gap(6)
	local play = st:Add(W.Button(p, "Play Hearth & Haul", 160, function() CloseSettings() P.Game:Open() end), 32)
	local hint = W.Text(p, "body", 11, "textDim")
	hint:SetPoint("TOPLEFT", play, "BOTTOMLEFT", 0, -12)
	hint:SetText("Commands: /hnh or /hearthandhaul (play), /hnh daily, /hnh perf, /hnh debug, /hnh reset.")

	W.pages[#W.pages + 1] = p
	-- the page's backing and text follow the skin (the family look, or the current NetherUI theme)
	local bg = p:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	Skin:Paint(bg, "bg", { alpha = 0.35 })
end

function Options:Open()
	self:Build()
	local SS = rawget(_G, "Settings")
	if self.category and SS and SS.OpenToCategory then
		local id = self.category.GetID and self.category:GetID() or self.category.ID
		pcall(SS.OpenToCategory, id)
	end
end

P:Register("LOGIN", function() Options:Build() end)
P:Register("SETTINGS_CHANGED", function() if Options.panel and Options.panel:IsShown() then W.Refresh(Options.panel) end end)
