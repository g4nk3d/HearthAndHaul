--[[ Hearth & Haul - Game/Data.lua
	The Undercroft's zones, its creatures, the loot that washes up, the perks, the hero's looks and the
	inn's decorations. Pure data and a few lookups; no game API (the balance tools run this file too).

	  D.ZONES[i]        { id, name, first, last, bg, door, sfx, music, foes = {...}, boss }
	  D:Zone(floor)     the zone a floor belongs to (floors 13 and deeper are the Rift)
	  D.FOES[id]        { name, hp, dmg, cd = {lo, hi}, tele, speed, boss, ranged }
	  D.ITEMS[zone]     12 finds per zone { name, q, icon }; the Rift draws from every zone
	  D.QUALITY[q]      { name, color, value }
	  D.PERKS, D.LOOKS, D.DECOR   the run perks (unlocked by achievements), hero looks and inn pieces ]]

local _, ns = ...
local D = {}
ns.Data = D

D.ZONES = {
	{ id = "cellars", name = "The Cellars", first = 1, last = 3, bg = "cellars", door = "cellars", sfx = "cellars",
		foes = { "cellar_rat", "grey_ooze", "cask_mimic" }, boss = "old_thornback", atlas = "E_cellars" },
	{ id = "catacombs", name = "Old Catacombs", first = 4, last = 6, bg = "catacombs", door = "catacombs", sfx = "catacombs",
		foes = { "skeleton_guard", "robed_cultist", "bone_hound" }, boss = "gatewarden" },
	{ id = "fungal", name = "Fungal Deep", first = 7, last = 9, bg = "fungal_deep", door = "fungal_deep", sfx = "fungal_deep",
		foes = { "spore_beast", "mushroom_shaman", "creeping_vine" }, boss = "mother_mycel" },
	{ id = "crystal", name = "Crystal Vault", first = 10, last = 12, bg = "crystal_vault", door = "crystal_vault", sfx = "crystal_vault",
		foes = { "crystal_sprite", "shard_golem", "prism_wisp" }, boss = "faceted_king" },
	{ id = "rift", name = "The Rift", first = 13, last = 9999, bg = "rift", door = "rift", sfx = "rift",
		foes = { "rift_shade", "rift_shade", "cellar_rat", "grey_ooze", "skeleton_guard", "bone_hound", "spore_beast",
			"creeping_vine", "crystal_sprite", "shard_golem", "prism_wisp", "robed_cultist", "mushroom_shaman" } },
}
for i, z in ipairs(D.ZONES) do
	z.index = i
	z.music = "music_" .. z.bg
	z.hearthing = "music_" .. z.bg .. "_hearthing"
end

function D:Zone(floor)
	for i = #self.ZONES, 1, -1 do
		local z = self.ZONES[i]
		if floor >= z.first then return z end
	end
	return self.ZONES[1]
end

function D:IsBossFloor(floor)
	local z = self:Zone(floor)
	return z.boss ~= nil and floor == z.last
end

-- hp and dmg at the zone's first floor; cd: seconds idle between attacks; tele: the red wind-up before a hit
-- lands (0.5 s, a boss's special 0.9 s); speed: walking pace in stage pixels per second
D.FOES = {
	cellar_rat      = { name = "Cellar Rat",      hp = 18,  dmg = 6,  cd = { 1.5, 2.3 }, speed = 260 },
	grey_ooze       = { name = "Grey Ooze",       hp = 30,  dmg = 7,  cd = { 2.2, 3.0 }, speed = 120 },
	cask_mimic      = { name = "Cask Mimic",      hp = 34,  dmg = 9,  cd = { 1.9, 2.7 }, speed = 150, mimic = true },
	old_thornback   = { name = "Old Thornback",   hp = 170, dmg = 12, cd = { 1.6, 2.2 }, speed = 170, boss = true },
	skeleton_guard  = { name = "Skeleton Guard",  hp = 42,  dmg = 10, cd = { 1.9, 2.6 }, speed = 150 },
	robed_cultist   = { name = "Robed Cultist",   hp = 34,  dmg = 12, cd = { 2.2, 3.0 }, speed = 140, ranged = true },
	bone_hound      = { name = "Bone Hound",      hp = 30,  dmg = 9,  cd = { 1.4, 2.0 }, speed = 280 },
	gatewarden      = { name = "The Gatewarden",  hp = 250, dmg = 15, cd = { 1.7, 2.3 }, speed = 130, boss = true },
	spore_beast     = { name = "Spore Beast",     hp = 54,  dmg = 13, cd = { 2.0, 2.8 }, speed = 150 },
	mushroom_shaman = { name = "Mushroom Shaman", hp = 42,  dmg = 15, cd = { 2.3, 3.1 }, speed = 120, ranged = true },
	creeping_vine   = { name = "Creeping Vine",   hp = 38,  dmg = 12, cd = { 1.6, 2.3 }, speed = 170 },
	mother_mycel    = { name = "Mother Mycel",    hp = 330, dmg = 18, cd = { 1.7, 2.3 }, speed = 110, boss = true },
	crystal_sprite  = { name = "Crystal Sprite",  hp = 48,  dmg = 15, cd = { 1.6, 2.2 }, speed = 240 },
	shard_golem     = { name = "Shard Golem",     hp = 72,  dmg = 18, cd = { 2.3, 3.0 }, speed = 110 },
	prism_wisp      = { name = "Prism Wisp",      hp = 50,  dmg = 17, cd = { 2.0, 2.7 }, speed = 200, ranged = true },
	faceted_king    = { name = "The Faceted King", hp = 430, dmg = 22, cd = { 1.7, 2.2 }, speed = 120, boss = true },
	rift_shade      = { name = "Rift Shade",      hp = 60,  dmg = 20, cd = { 1.6, 2.3 }, speed = 230 },
}
for id, f in pairs(D.FOES) do
	f.id = id
	f.tele = 0.5
end
-- the zone each creature's base numbers belong to (their first floor), for scaling in the Rift
D.FOE_HOME = {}
for _, z in ipairs(D.ZONES) do
	if z.id ~= "rift" then
		for _, f in ipairs(z.foes) do D.FOE_HOME[f] = z.first end
		D.FOE_HOME[z.boss] = z.first
	end
end
D.FOE_HOME.rift_shade = 13

-- ------------------------------------------------------------------ loot
-- value: gold at floor 1; it grows 18% with every floor deeper
D.QUALITY = {
	{ name = "Poor",     color = { 0.62, 0.62, 0.62 }, value = 4 },
	{ name = "Common",   color = { 1, 1, 1 },          value = 10 },
	{ name = "Uncommon", color = { 0.12, 1, 0 },       value = 24 },
	{ name = "Rare",     color = { 0, 0.44, 0.87 },    value = 55 },
	{ name = "Epic",     color = { 0.64, 0.21, 0.93 }, value = 130 },
}

local IC = "Interface\\Icons\\"
local function L(list)
	for i, e in ipairs(list) do list[i] = { name = e[1], q = e[2], icon = IC .. e[3] } end
	return list
end
D.ITEMS = {
	cellars = L({
		{ "Dusty Wine Bottle", 1, "INV_Drink_04" }, { "Cracked Tankard", 1, "INV_Drink_10" },
		{ "Candle Stub", 1, "INV_Misc_Candle_01" }, { "Cellar Key", 2, "INV_Misc_Key_03" },
		{ "Rat-Chewed Boots", 2, "INV_Boots_05" }, { "Tapster's Knife", 2, "INV_Weapon_ShortBlade_05" },
		{ "Vintage Red", 3, "INV_Drink_03" }, { "Cooper's Mallet", 3, "INV_Hammer_05" },
		{ "Brass Spigot Ring", 3, "INV_Jewelry_Ring_02" }, { "Barrel-Stave Buckler", 4, "INV_Shield_05" },
		{ "Silk of Old Thornback", 4, "INV_Fabric_Silk_01" }, { "Marga's Lost Locket", 5, "INV_Jewelry_Necklace_09" },
	}),
	catacombs = L({
		{ "Yellowed Bone", 1, "INV_Misc_Bone_08" }, { "Burial Shroud", 1, "INV_Fabric_Linen_01" },
		{ "Mourner's Cowl", 2, "INV_Helmet_29" }, { "Grave-Moss Sandals", 2, "INV_Boots_Cloth_03" },
		{ "Burial Knife", 2, "INV_Weapon_ShortBlade_10" }, { "Candlewax Wand", 3, "INV_Wand_02" },
		{ "Barrowguard Leggings", 3, "INV_Pants_06" }, { "Ossuary Censer", 3, "INV_Misc_Lantern_01" },
		{ "Old Bronze War Axe", 4, "INV_Axe_09" }, { "Signet of the Barrow King", 4, "INV_Jewelry_Ring_15" },
		{ "Gatewarden's Halberd", 4, "INV_Axe_05" }, { "Crown of Green Flame", 5, "INV_Helmet_24" },
	}),
	fungal = L({
		{ "Glowcap Mushroom", 1, "INV_Mushroom_11" }, { "Sporestained Pants", 1, "INV_Pants_Cloth_04" },
		{ "Fungal Cap", 2, "INV_Helmet_31" }, { "Webspinner Wristguards", 2, "INV_Bracer_02" },
		{ "Mossback Vest", 2, "INV_Chest_Leather_07" }, { "Gloomcap Wand", 3, "INV_Wand_07" },
		{ "Fang of the Deep", 3, "INV_Weapon_ShortBlade_11" }, { "Thornbark Greatstaff", 3, "INV_Staff_11" },
		{ "Sporecloud Talisman", 4, "INV_Jewelry_Talisman_05" }, { "Rootwarden Mail", 4, "INV_Pants_03" },
		{ "Broodsilk Robe", 4, "INV_Chest_Cloth_21" }, { "Heart of Mother Mycel", 5, "INV_Misc_Orb_03" },
	}),
	crystal = L({
		{ "Crystal Shard", 1, "INV_Misc_Gem_Crystal_02" }, { "Cloudy Gem", 1, "INV_Misc_Gem_Pearl_04" },
		{ "Lensgrinder's Gloves", 2, "INV_Gauntlets_03" }, { "Prism Lens", 2, "INV_Misc_Spyglass_02" },
		{ "Tidal Lens Wand", 3, "INV_Wand_04" }, { "Stargazer's Vestments", 3, "INV_Chest_Cloth_25" },
		{ "Brass Astrolabe Mace", 3, "INV_Mace_08" }, { "Ring of the Seventh Lens", 4, "INV_Jewelry_Ring_29" },
		{ "Starsplinter Staff", 4, "INV_Staff_13" }, { "Moonwake Spellblade", 4, "INV_Sword_23" },
		{ "Orrery Heartstone", 5, "INV_Misc_Orb_02" }, { "Crown of the Faceted King", 5, "INV_Helmet_08" },
	}),
}
D.ITEMS.rift = {}
for _, k in ipairs({ "cellars", "catacombs", "fungal", "crystal" }) do
	for _, it in ipairs(D.ITEMS[k]) do D.ITEMS.rift[#D.ITEMS.rift + 1] = it end
end
for _, list in pairs(D.ITEMS) do
	for _, it in ipairs(list) do it.byQ = true end
end

-- quality weights (poor, common, uncommon, rare, epic) by zone; a chest's tier and an elite add one step
D.QUALITY_WEIGHTS = {
	cellars   = { 40, 34, 18, 7, 1 },
	catacombs = { 28, 34, 24, 11, 3 },
	fungal    = { 18, 30, 30, 17, 5 },
	crystal   = { 10, 24, 34, 24, 8 },
	rift      = { 4, 16, 34, 32, 14 },
}

function D:Value(q, floor)
	return math.floor(self.QUALITY[q].value * (1 + 0.18 * (floor - 1)) + 0.5)
end

-- ------------------------------------------------------------------ perks, looks, decorations
-- a perk is unlocked by an achievement; one is picked per run
D.PERKS = {
	{ id = "lantern", name = "Lantern", ach = "first_haul", card = "perk_card_lantern",
		text = "Unknown doors show what is behind them, and you spot every trap (no damage)." },
	{ id = "thick_cloak", name = "Thick Cloak", ach = "old_thornback", card = "perk_card_thick_cloak",
		text = "While you cast your hearth, the first hit that gets through does nothing: no damage, no pushback." },
	{ id = "deep_pockets", name = "Deep Pockets", ach = "greedy", card = "perk_card_deep_pockets",
		text = "Your bag holds 14 items instead of 12." },
	{ id = "quick_hands", name = "Quick Hands", ach = "gatewarden", card = "perk_card_quick_hands",
		text = "You strike every 0.6 seconds instead of 0.8." },
}
D.PERK = {}
for _, p in ipairs(D.PERKS) do D.PERK[p.id] = p end

-- hero looks: banked gold buys them (cosmetic only)
D.LOOKS = {
	{ id = "blue", name = "Hearthstone Blue", cost = 0, card = "hero_look_blue" },
	{ id = "red", name = "Crossroads Red", cost = 1500, card = "hero_look_red" },
	{ id = "green", name = "Cellar Moss", cost = 1500, card = "hero_look_green" },
	{ id = "gold", name = "Innkeeper's Gold", cost = 3000, card = "hero_look_gold" },
}

-- inn decorations (cosmetic only): where each goes in the inn picture (centre and size, pixels of the 960 x 480 view;
-- placed on the picture's free walls, the gallery rail, the hearth and the floor: tools/hh_preview.py inn grid)
D.DECOR = {
	{ id = "rug", name = "Blue Gryphon Rug", cost = 150, x = 470, y = 352, w = 230, h = 66 },
	{ id = "banner_red", name = "Red Banner", cost = 200, x = 545, y = 62, w = 50, h = 64 },
	{ id = "banner_gold", name = "Gold Banner", cost = 200, x = 790, y = 62, w = 50, h = 64 },
	{ id = "banner_blue", name = "Blue Banner", cost = 200, x = 395, y = 62, w = 50, h = 64 },
	{ id = "boar_trophy", name = "Boar Trophy", cost = 350, x = 862, y = 108, w = 54, h = 54 },
	{ id = "map", name = "Map of the Undercroft", cost = 400, x = 470, y = 52, w = 56, h = 56 },
	{ id = "mushroom_planter", name = "Glowcap Planter", cost = 450, x = 368, y = 226, w = 46, h = 46 },
	{ id = "bard_lute", name = "Lira's Spare Lute", cost = 500, x = 768, y = 208, w = 40, h = 40 },
	{ id = "stuffed_spider", name = "Stuffed Spider", cost = 650, x = 140, y = 28, w = 40, h = 40 },
	{ id = "crystal_lamp", name = "Crystal Lamp", cost = 750, x = 628, y = 150, w = 44, h = 44 },
	{ id = "chandelier", name = "Chandelier", cost = 900, x = 300, y = 22, w = 76, h = 76 },
	{ id = "marga_painting", name = "Portrait of Marga", cost = 1200, x = 326, y = 42, w = 44, h = 44 },
}
D.DECOR_BY = {}
for _, d in ipairs(D.DECOR) do d.sprite = "inn_decor_" .. d.id D.DECOR_BY[d.id] = d end

-- run medals: banked gold of a single run
D.MEDALS = { 75, 350, 1000 }
D.MEDAL_NAME = { [0] = "no medal", "bronze", "silver", "gold" }
function D:Medal(gold)
	local m = 0
	for i, t in ipairs(self.MEDALS) do if gold >= t then m = i end end
	return m
end
