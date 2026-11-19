-- Static world data for the map overlay (TravelMap.lua): dungeon entrances, boat / zeppelin / tram links and the
-- towns with a flight master. Coordinates are percentages (0..100) on the zone map `map` (UiMapID), read from memory of
-- the Classic Era world, so treat them as approximate pointers (about 1-3 % off), not survey data.
local ADDON, ns = ...
local D = {}
ns.travelData = D

-- faction: "Alliance", "Horde" or "Both"
D.stops = {
    auberdine = { name = "Auberdine docks", zone = "Darkshore",           map = 1439, x = 33.0, y = 41.0 },
    menethil  = { name = "Menethil Harbor docks", zone = "Wetlands",      map = 1437, x = 4.9,  y = 57.4 },
    ruttheran = { name = "Rut'theran Village dock", zone = "Teldrassil",  map = 1438, x = 55.2, y = 92.7 },
    theramore = { name = "Theramore Isle dock", zone = "Dustwallow Marsh", map = 1445, x = 71.5, y = 56.5 },
    ratchet   = { name = "Ratchet docks", zone = "The Barrens",           map = 1413, x = 63.8, y = 38.6 },
    bootybay  = { name = "Booty Bay docks", zone = "Stranglethorn Vale",  map = 1434, x = 25.8, y = 73.1 },
    orgtower  = { name = "Orgrimmar zeppelin tower", zone = "Durotar",    map = 1411, x = 50.9, y = 13.8 },
    uctower   = { name = "Undercity zeppelin tower", zone = "Tirisfal Glades", map = 1420, x = 60.5, y = 58.9 },
    gromgol   = { name = "Grom'gol zeppelin tower", zone = "Stranglethorn Vale", map = 1434, x = 31.3, y = 29.5 },
    swtram    = { name = "Deeprun Tram (Stormwind)", zone = "Stormwind City", map = 1453, x = 68.5, y = 30.4 },
    iftram    = { name = "Deeprun Tram (Ironforge)", zone = "Ironforge",  map = 1455, x = 76.2, y = 51.3 },
}

-- seconds: rough ride time in Classic Era (the wait for the next ship is added by DungeonRoute.lua)
D.routes = {
    { kind = "Boat",     faction = "Alliance", a = "auberdine", b = "menethil", seconds = 150 },
    { kind = "Boat",     faction = "Alliance", a = "auberdine", b = "ruttheran", seconds = 150 },
    { kind = "Boat",     faction = "Alliance", a = "menethil",  b = "theramore", seconds = 150 },
    { kind = "Boat",     faction = "Both",     a = "ratchet",   b = "bootybay", seconds = 150 },
    { kind = "Zeppelin", faction = "Horde",    a = "orgtower",  b = "uctower", seconds = 120 },
    { kind = "Zeppelin", faction = "Horde",    a = "orgtower",  b = "gromgol", seconds = 120 },
    { kind = "Zeppelin", faction = "Horde",    a = "uctower",   b = "gromgol", seconds = 120 },
    { kind = "Tram",     faction = "Alliance", a = "swtram",    b = "iftram", seconds = 60 },
}

-- One pin per entrance; `inside` lists every instance reached from it with its level span.
D.dungeons = {
    { name = "Ragefire Chasm",    map = 1454, x = 52.0, y = 49.0, inside = { { "Ragefire Chasm", "13-18" } } },
    { name = "Wailing Caverns",   map = 1413, x = 46.0, y = 36.6, inside = { { "Wailing Caverns", "15-25" } } },
    { name = "Blackfathom Deeps", map = 1440, x = 14.2, y = 14.2, inside = { { "Blackfathom Deeps", "24-32" } } },
    { name = "Razorfen Kraul",    map = 1413, x = 40.8, y = 90.0, inside = { { "Razorfen Kraul", "30-40" } } },
    { name = "Razorfen Downs",    map = 1413, x = 49.3, y = 94.5, inside = { { "Razorfen Downs", "37-46" } } },
    { name = "Maraudon",          map = 1443, x = 29.0, y = 62.5, inside = { { "Maraudon", "46-55" } } },
    { name = "Zul'Farrak",        map = 1446, x = 39.0, y = 21.1, inside = { { "Zul'Farrak", "44-54" } } },
    { name = "Dire Maul",         map = 1444, x = 62.5, y = 30.3, inside = { { "Dire Maul", "55-60" } } },
    { name = "Onyxia's Lair",     map = 1445, x = 52.0, y = 76.0, inside = { { "Onyxia's Lair", "60" } } },
    { name = "Ahn'Qiraj",         map = 1451, x = 29.0, y = 94.0,
      inside = { { "Ruins of Ahn'Qiraj", "60" }, { "Temple of Ahn'Qiraj", "60" } } },
    { name = "The Deadmines",     map = 1436, x = 43.0, y = 72.0, inside = { { "The Deadmines", "18-23" } } },
    { name = "The Stockade",      map = 1453, x = 40.5, y = 58.0, inside = { { "The Stockade", "24-32" } } },
    { name = "Shadowfang Keep",   map = 1421, x = 44.7, y = 67.8, inside = { { "Shadowfang Keep", "22-30" } } },
    { name = "Gnomeregan",        map = 1426, x = 24.5, y = 39.0, inside = { { "Gnomeregan", "29-38" } } },
    { name = "Scarlet Monastery", map = 1420, x = 83.0, y = 33.5,
      inside = { { "Graveyard", "26-36" }, { "Library", "29-39" }, { "Armory", "32-42" }, { "Cathedral", "35-45" } } },
    { name = "Uldaman",           map = 1418, x = 42.4, y = 12.7, inside = { { "Uldaman", "41-51" } } },
    { name = "Sunken Temple",     map = 1435, x = 69.5, y = 53.6, inside = { { "The Temple of Atal'Hakkar", "50-60" } } },
    { name = "Blackrock Mountain", map = 1428, x = 29.5, y = 37.5,
      inside = { { "Blackrock Depths", "52-60" }, { "Lower Blackrock Spire", "55-60" }, { "Upper Blackrock Spire", "58-60" },
                 { "Molten Core", "60" }, { "Blackwing Lair", "60" } } },
    { name = "Scholomance",       map = 1422, x = 69.2, y = 73.0, inside = { { "Scholomance", "58-60" } } },
    { name = "Stratholme",        map = 1423, x = 31.0, y = 16.0, inside = { { "Stratholme", "58-60" } } },
    { name = "Naxxramas",         map = 1423, x = 39.2, y = 26.0, inside = { { "Naxxramas", "60" } } },
    { name = "Zul'Gurub",         map = 1434, x = 53.7, y = 17.5, inside = { { "Zul'Gurub", "60" } } },
}

-- Towns with a flight master, by who may use them ("Both" = neutral or shared).
local towns = {}
local function town(name, zone, map, x, y, faction)
    towns[#towns + 1] = { name = name, zone = zone, map = map, x = x, y = y, faction = faction }
end
-- Eastern Kingdoms, Alliance
town("Stormwind City", "Elwynn Forest", 1453, 66.3, 62.2, "Alliance")
town("Ironforge", "Dun Morogh", 1455, 55.5, 47.8, "Alliance")
town("Sentinel Hill", "Westfall", 1436, 56.5, 52.6, "Alliance")
town("Lakeshire", "Redridge Mountains", 1433, 30.6, 59.3, "Alliance")
town("Darkshire", "Duskwood", 1431, 77.5, 44.3, "Alliance")
town("Menethil Harbor", "Wetlands", 1437, 9.5, 59.7, "Alliance")
town("Thelsamar", "Loch Modan", 1432, 33.9, 50.9, "Alliance")
town("Southshore", "Hillsbrad Foothills", 1424, 49.4, 52.3, "Alliance")
town("Refuge Pointe", "Arathi Highlands", 1417, 45.8, 46.1, "Alliance")
town("Aerie Peak", "The Hinterlands", 1425, 11.0, 46.0, "Alliance")
town("Morgan's Vigil", "Burning Steppes", 1428, 84.3, 68.3, "Alliance")
town("Nethergarde Keep", "Blasted Lands", 1419, 66.4, 18.4, "Alliance")
town("Chillwind Camp", "Western Plaguelands", 1422, 42.9, 85.1, "Alliance")
-- Eastern Kingdoms, Horde
town("Undercity", "Tirisfal Glades", 1458, 63.2, 48.6, "Horde")
town("Brill", "Tirisfal Glades", 1420, 58.8, 52.0, "Horde")
town("The Sepulcher", "Silverpine Forest", 1421, 45.5, 42.5, "Horde")
town("Tarren Mill", "Hillsbrad Foothills", 1424, 62.3, 19.3, "Horde")
town("Hammerfall", "Arathi Highlands", 1417, 73.1, 32.7, "Horde")
town("Revantusk Village", "The Hinterlands", 1425, 78.1, 81.0, "Horde")
town("Grom'gol Base Camp", "Stranglethorn Vale", 1434, 32.5, 29.3, "Horde")
town("Stonard", "Swamp of Sorrows", 1435, 45.2, 57.7, "Horde")
town("Kargath", "Badlands", 1418, 3.5, 47.9, "Horde")
town("Flame Crest", "Burning Steppes", 1428, 65.3, 24.2, "Horde")
-- Eastern Kingdoms, neutral
town("Booty Bay", "Stranglethorn Vale", 1434, 27.5, 77.8, "Both")
town("Light's Hope Chapel", "Eastern Plaguelands", 1423, 81.5, 59.2, "Both")
town("Thorium Point", "Searing Gorge", 1427, 37.9, 30.8, "Both")
-- Kalimdor, Alliance
town("Darnassus", "Teldrassil", 1457, 36.4, 47.6, "Alliance")
town("Rut'theran Village", "Teldrassil", 1438, 58.4, 94.0, "Alliance")
town("Auberdine", "Darkshore", 1439, 36.4, 45.6, "Alliance")
town("Astranaar", "Ashenvale", 1440, 34.4, 48.0, "Alliance")
town("Forest Song", "Ashenvale", 1440, 18.3, 51.5, "Alliance")
town("Stonetalon Peak", "Stonetalon Mountains", 1442, 36.4, 7.2, "Alliance")
town("Theramore Isle", "Dustwallow Marsh", 1445, 67.5, 51.1, "Alliance")
town("Feathermoon Stronghold", "Feralas", 1444, 30.2, 43.2, "Alliance")
town("Nijel's Point", "Desolace", 1443, 64.8, 10.2, "Alliance")
town("Thalanaar", "Thousand Needles", 1441, 89.5, 46.0, "Alliance")
town("Talonbranch Glade", "Felwood", 1448, 62.5, 24.2, "Alliance")
town("Talrendis Point", "Azshara", 1447, 11.9, 77.5, "Alliance")
-- Kalimdor, Horde
town("Orgrimmar", "Durotar", 1454, 45.1, 63.9, "Horde")
town("Thunder Bluff", "Mulgore", 1456, 47.0, 49.8, "Horde")
town("Sen'jin Village", "Durotar", 1411, 55.4, 74.0, "Horde")
town("Razor Hill", "Durotar", 1411, 52.2, 41.6, "Horde")
town("The Crossroads", "The Barrens", 1413, 51.5, 30.3, "Horde")
town("Camp Taurajo", "The Barrens", 1413, 44.5, 59.1, "Horde")
town("Splintertree Post", "Ashenvale", 1440, 73.2, 61.1, "Horde")
town("Zoram'gar Outpost", "Ashenvale", 1440, 12.2, 33.8, "Horde")
town("Sun Rock Retreat", "Stonetalon Mountains", 1442, 45.4, 59.8, "Horde")
town("Shadowprey Village", "Desolace", 1443, 24.2, 68.4, "Horde")
town("Camp Mojache", "Feralas", 1444, 75.5, 44.3, "Horde")
town("Freewind Post", "Thousand Needles", 1441, 45.1, 49.0, "Horde")
town("Brackenwall Village", "Dustwallow Marsh", 1445, 36.0, 30.5, "Horde")
town("Bloodvenom Post", "Felwood", 1448, 34.4, 52.9, "Horde")
town("Valormok", "Azshara", 1447, 22.0, 49.8, "Horde")
-- Kalimdor, neutral
town("Ratchet", "The Barrens", 1413, 63.0, 37.2, "Both")
town("Gadgetzan", "Tanaris", 1446, 51.0, 29.3, "Both")
town("Everlook", "Winterspring", 1452, 61.3, 38.9, "Both")
town("Cenarion Hold", "Silithus", 1451, 50.5, 34.4, "Both")
town("Marshal's Refuge", "Un'Goro Crater", 1449, 45.3, 5.8, "Both")
town("Moonglade", "Moonglade", 1450, 48.2, 67.5, "Both")
D.towns = towns
