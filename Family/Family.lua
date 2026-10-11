--[[ Hearth & Haul - Family/Family.lua
	Settings in one place, the slash commands, and Hearth & Haul's tile in NetherSuite (all optional:
	Hearth & Haul plays exactly the same alone).

	  P:Setting(key) / P:SetSetting(key, value)   applied at once wherever it is changed
	  /hnh, /hearthandhaul           open or close the game 
	  /hnh reset             forget this character's Hearth & Haul records (asks first)
	  /hnh perf              frame time and memory
	  /hnh debug             errors and missing art ]]

local ADDON, ns = ...
local P = ns.P

local DEFAULTS = { music = true, sound = true, nudge = false, size = 0.9, followNetherUI = true, minimapButton = true,
	shareScores = true }
P.SETTING_DEFAULTS = DEFAULTS

function P:Setting(key)
	local st = self.db and self.db.settings
	local v = st and st[key]
	if v == nil then return DEFAULTS[key] end
	return v
end

function P:SetSetting(key, value)
	if not self.db then return end
	local was = self:Setting(key)
	self.db.settings[key] = value
	if was == value then return end
	local G = self.Game
	if key == "music" then
		if not value then self.Audio:StopMusic()
		elseif G and G.IsOpen and G:IsOpen() and G.MusicNow then G:MusicNow() end
	elseif key == "shareScores" then
		if self.Leaderboard then self.Leaderboard:SetEnabled(value) end
	elseif key == "size" then
		if G then G:FitScale() end
	elseif key == "minimapButton" then
		if self.Minimap and self.Minimap.SetShown then self.Minimap:SetShown(value) end
	end
	self:Fire("SETTINGS_CHANGED", key)
end

-- ------------------------------------------------------------------ NetherSuite
local LABELS = {
	{ "music", "Music", { "music", "sound" } },
	{ "sound", "Sound effects", { "sound", "sfx", "effects" } },
	{ "nudge", "Remind me after 20 minutes of play", { "reminder", "nudge", "break", "time" } },
	{ "minimapButton", "Show the minimap button", { "minimap", "button" } },
	{ "shareScores", "Share daily scores with other players", { "scores", "leaderboard", "share", "channel", "daily" } },
	{ "followNetherUI", "Follow NetherUI's theme (options page)", { "theme", "look", "netherui", "skin" } },
}

local function Settings()
	local list = {}
	for _, l in ipairs(LABELS) do
		local key = l[1]
		list[#list + 1] = { id = key, kind = "toggle", label = l[2], page = "general", keywords = l[3],
			get = function() return P:Setting(key) and true or false end,
			set = function(v) P:SetSetting(key, v and true or false) end }
	end
	return list
end

local function Status()
	local Pr, Aw = P.Progress, P.Awards
	local got, all = Aw:Count()
	return {
		{ "Purse", ("%d gold"):format(Pr:Gold()) },
		{ "Best haul", Pr:Best() > 0 and ("%d gold"):format(Pr:Best()) or "none yet" },
		{ "Deepest floor", Pr:Deepest() > 0 and tostring(Pr:Deepest()) or "not dived yet" },
		{ "Achievements", ("%d of %d"):format(got, all) },
	}
end

local function Descriptor()
	return {
		id = "hearthandhaul", name = "Hearth & Haul", version = P.VERSION, apiVersion = 1, addon = ADDON,
		icon = P.MEDIA .. "Logo", banner = P.MEDIA .. "Banner",
		description = "Dive the Undercroft below the Sleeping Gryphon, fight with block and strike, and hearth home before the creatures knock your cast back: everything you carry home is banked.",
		category = "Games", slash = { "/hnh", "/hearthandhaul" },
		pages = { { id = "general", label = "General" } },
		settings = Settings(),
		open = function() P.Game:Open() return true end,
		focus = function() if P.Options and P.Options.Open then P.Options:Open() else P.Game:Open() end return true end,
		status = Status,
	}
end

local joined = false
local function JoinSuite()
	if joined then return end
	local S = rawget(_G, "NetherSuite")
	if type(S) == "table" and type(S.RegisterAddon) == "function" then
		joined = pcall(S.RegisterAddon, S, Descriptor())
	elseif C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("NetherSuite") then
		NetherSuite_Queue = NetherSuite_Queue or {}
		table.insert(NetherSuite_Queue, Descriptor())
		joined = true
	end
end

P:Register("LOGIN", JoinSuite)
P:On("ADDON_LOADED", function(_, name)
	if name == "NetherSuite" and P.loggedIn then P:After(0, JoinSuite) end
end)

if NetherFamily then
	if NetherFamily.Slash then NetherFamily:Slash(ADDON, "HEARTHANDHAUL", "Hearth & Haul") end
end

-- ------------------------------------------------------------------ slash commands
local confirmReset = 0
local function Slash(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "perf" then
		P.Game:Perf()
	elseif msg == "debug" then
		P.debug = not P.debug
		P:Print("version %s, schema %d, %d error(s), %d missing art; error messages in chat %s.", P.VERSION, P.SCHEMA,
			#P.errors, #P.Assets.missing, P.debug and "on" or "off")
		for _, e in ipairs(P.errors) do P:Print("  %s%s", e.text, e.n > 1 and (" (x" .. e.n .. ")") or "") end
		for _, e in ipairs(P.Assets.missing) do P:Print("  missing: %s", e) end
	elseif msg == "reset" then
		local now = GetTime()
		if now - confirmReset > 10 then
			confirmReset = now
			P:Print("this forgets this character's purse, records, furnishings, daily results, achievements and the dive in progress. Type /hnh reset again within 10 seconds to confirm.")
			return
		end
		confirmReset = 0
		if P.char then
			local c = P.char
			for _, k in ipairs({ "resume", "daily", "dailyDays", "ach", "seal", "best", "deepest", "runs", "deaths", "homes",
				"looks", "look", "decor", "perk" }) do c[k] = nil end
			c.gold, c.medal = 0, 0
		end
		P.Game:Forget()
		P:Print("this character's records have been reset.")
	elseif msg == "testopen" then
		-- for testing: every perk open until the next /reload (nothing is saved, no medals or achievements given)
		P.testOpen = not P.testOpen
		P:Print("every perk is %s for this session%s.", P.testOpen and "open" or "back to normal", P.testOpen and " (results are not saved)" or "")
	elseif msg == "daily" then
		P.Game:Open()
		if P.Game:IsOpen() and P.Game.mode == "inn" then P.Game:Screen("board") end
	elseif msg == "help" or msg == "?" then
		P:Print("/hnh opens the game. Also: /hnh daily, /hnh perf, /hnh debug, /hnh reset.")
	else
		P.Game:Toggle()
	end
end

SLASH_HEARTHANDHAUL1 = "/hnh"
SLASH_HEARTHANDHAUL2 = "/hearthandhaul"
SlashCmdList.HEARTHANDHAUL = function(msg) P:Safe("slash", Slash, msg) end
