--[[ Hearth & Haul - Core/Audio.lua
	Every sound goes through here, once per game event; the stage and screens never play files
	themselves.

	  Au:Play(name)          a sound effect on the Sound Effects channel (respects the Sound setting and
	                         a short per-sound cooldown, so a burst of identical events plays once)
	  Au:Pick(base, n)       one of base_01..base_0n, never the same twice in a row (footsteps, hits)
	  Au:Music(name)         a loop through the game's music player (replaces zone music until
	                         StopMusic); the same track again does nothing
	  Au:MusicLayer(zone, casting)   the zone's track, or its hearthing mix while the hearth is cast
	  Au:StopMusic(), Au:Cancel() ]]

local _, ns = ...
local P = ns.P
local Au = P:Module("Audio")
local A = P.Assets

local GetTime = GetTime
local lastAt, handles = {}, {}
local COOLDOWN = 0.05
local lastPick = {}

function Au:Enabled() return P:Setting("sound") ~= false end

function Au:Play(name)
	if not self:Enabled() then return false end
	local path = A:SoundPath(name)
	if not path then return false end
	local now = GetTime()
	if lastAt[name] and now - lastAt[name] < COOLDOWN then return false end
	lastAt[name] = now
	local t0 = P:ProfStart()
	local ok, willPlay, handle = pcall(PlaySoundFile, path, "SFX")
	P:ProfEnd("sound", t0)
	if ok and willPlay and handle then
		handles[#handles + 1] = handle
		if #handles > 24 then table.remove(handles, 1) end
	end
	return ok and willPlay
end

local PICK = {}
function Au:Pick(base, n)
	local i = ((lastPick[base] or 0) % n) + 1
	lastPick[base] = i
	local names = PICK[base]
	if not names then
		names = {}
		for k = 1, n do names[k] = ("%s_%02d"):format(base, k) end
		PICK[base] = names
	end
	return self:Play(names[i])
end

function Au:Cancel()
	if StopSound then
		for i = 1, #handles do pcall(StopSound, handles[i]) end
	end
	wipe(handles)
end

function Au:Music(name)
	if P:Setting("music") == false then return end
	local path = A:MusicPath(name)
	if not path or self.playing == name then return end
	if PlayMusic then
		local t0 = P:ProfStart()
		PlayMusic(path)
		P:ProfEnd("music", t0)
		self.playing = name
	end
end

function Au:StopMusic()
	if self.playing and StopMusic then StopMusic() end
	self.playing = nil
end

-- in the Undercroft: the zone's track, or its hearthing mix while the cast is up. The game's music player
-- plays one file at a time, so the two layers are two mixes of the same piece and switching swaps them.
function Au:MusicLayer(zone, casting)
	if not zone then return end
	self:Music(casting and zone.hearthing or zone.music)
end
