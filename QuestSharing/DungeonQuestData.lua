-- Generated: quests of every WoW Forever dungeon, from Wowhead's guide "Every Dungeon Quest in WoW Forever"
-- (https://www.wowhead.com/forever/guide=34916) and the Blackmaw Hold overview (guide=35373), read 2026-11-19.
-- Added on top of QuestieDB's locations: Questie files many dungeon quests under an outdoor zone, and the new
-- Forever dungeons have no quests filed under them at all. Area ids are the game's (Wowhead zone ids).
local ADDON, ns = ...
local D = {}
ns.dungeonQuestData = D
-- area id -> name, for dungeons the client or QuestieDB may not name
D.names = {
    [209] = "Shadowfang Keep",
    [491] = "Razorfen Kraul",
    [717] = "The Stockade",
    [718] = "Wailing Caverns",
    [719] = "Blackfathom Deeps",
    [721] = "Gnomeregan",
    [722] = "Razorfen Downs",
    [796] = "Scarlet Monastery",
    [1176] = "Zul'Farrak",
    [1337] = "Uldaman",
    [1477] = "The Temple of Atal'Hakkar",
    [1581] = "The Deadmines",
    [1583] = "Blackrock Spire",
    [1584] = "Blackrock Depths",
    [2017] = "Stratholme",
    [2057] = "Scholomance",
    [2100] = "Maraudon",
    [2437] = "Ragefire Chasm",
    [2557] = "Dire Maul",
    [16544] = "City of Dalaran",
    [16550] = "The Drowned City",
    [16554] = "Blackmaw Hold",
    [16611] = "Ruins of Lordaeron",
    [16620] = "Alcaz Prison",
    [16667] = "The Shaper's Terrace",
    [16732] = "Excavation Site: Wetlands",
    [16842] = "Krol'dok Stronghold",
    [16919] = "The Hall of Thanes",
}
-- area id -> quest ids
D.quests = {
    [209] = { 1013, 1098, 1014, 1740, 1654 }, -- Shadowfang Keep
    [491] = { 1102, 1109, 1113, 6522, 6521, 1101, 1100, 1142, 1221, 1144 }, -- Razorfen Kraul
    [717] = { 387, 388, 377, 386, 378, 303, 391, 373 }, -- The Stockade
    [718] = { 962, 1491, 865, 959, 1486, 1487, 6981, 914, 870 }, -- Wailing Caverns
    [719] = { 6563, 6561, 6921, 6922, 1740, 6565, 971, 1275, 1199, 1198, 1200, 1654 }, -- Blackfathom Deeps
    [721] = { 2841, 2842, 2843, 2922, 2928, 2924, 2930, 2929, 2926, 2962, 2951, 2904, 2945, 2947, 2949 }, -- Gnomeregan
    [722] = { 3341, 6521, 6522, 3636, 6626, 3523, 3525 }, -- Razorfen Downs
    [796] = { 1048, 1053, 6141, 1051, 1113, 1109, 1049, 1160, 1149, 1050, 1951, 1947 }, -- Scarlet Monastery
    [1176] = { 2936, 2933, 96775, 2991, 2988, 2768, 2865, 3042, 2846, 2770, 3527, 3520 }, -- Zul'Farrak
    [1337] = { 2342, 2202, 2258, 2283, 1360, 2398, 2240, 17, 2500, 704, 707, 1139, 720, 2198, 2418, 709, 2278, 1956, 1953 }, -- Uldaman
    [1477] = { 1445, 1424, 4146, 4145, 4143, 4141, 1475, 1448, 1446, 3373, 3446, 3380, 3445, 3447, 3528, 3520 }, -- The Temple of Atal'Hakkar
    [1581] = { 168, 167, 2040, 373, 391, 214, 166, 92753, 92742, 1654, 95036 }, -- The Deadmines
    [1583] = { 4724, 4981, 4982, 4903, 4701, 5089, 5001, 4862, 4729, 4866, 4742, 4867, 4788, 3520, 4768, 4769, 4974, 6602, 4764, 4766, 5102, 6502, 4182, 7761, 5160, 5047, 4735, 4734, 4726, 6821, 6805, 6804, 5127, 5126 }, -- Blackrock Spire
    [1584] = { 4081, 4134, 4133, 4082, 4063, 4061, 3906, 3907, 3981, 7201, 4132, 4122, 4003, 4262, 4263, 4286, 4126, 4341, 3702, 4362, 4241, 4182, 4322, 4282, 4136, 4324, 4123, 7848, 3802, 3801, 4201, 4024, 3441 }, -- Blackrock Depths
    [2017] = { 5214, 5251, 5282, 5122, 5281, 5262, 5848, 5543, 5544, 5542, 6163, 6133, 6022, 5243, 5212, 5213, 5125, 5263, 5463, 5382, 8945, 8923, 8922 }, -- Stratholme
    [2057] = { 5341, 7668, 7667, 5343, 5529, 5582, 5382, 5515, 5384, 4771, 4726, 5466 }, -- Scholomance
    [2100] = { 7068, 7029, 7064, 7070, 7041, 7065, 7028, 92914, 7067, 7044, 7046, 7066 }, -- Maraudon
    [2437] = { 5761, 5725, 5723, 5722, 5728, 5726 }, -- Ragefire Chasm
    [2557] = { 7489, 7488, 7441, 5526, 5527, 7463, 7461, 7507, 7481, 7485, 7483, 7484, 7482, 5525, 5518, 5528, 7703 }, -- Dire Maul
    [16544] = { 96986, 96988, 96987, 96984, 544, 92489, 92458, 92432, 92456, 92457 }, -- City of Dalaran
    [16550] = { 95788, 95798, 203, 204, 205, 95787, 95799, 97130, 95775, 629, 95776, 95773, 96774, 95789, 95791 }, -- The Drowned City
    [16554] = { 96246, 92065, 86746, 92069, 92066, 92070, 97173, 92344, 97198, 92343, 92346 }, -- Blackmaw Hold
    [16611] = { 92422, 99156, 92401, 92421, 95216, 451, 97288, 95204, 95189, 95250, 95195, 92415 }, -- Ruins of Lordaeron
    [16620] = { 96772, 96381, 95263, 95194, 95262, 95309, 95454, 95283, 96332, 96334 }, -- Alcaz Prison
    [16732] = { 98815, 469, 95772, 95646, 95647, 95737, 95809, 95810, 98824, 95697, 95664, 98823, 95682, 95663 }, -- Excavation Site: Wetlands
    [16842] = { 96771, 94983, 94998, 94881, 94879, 94877, 94982, 94984, 94980, 94981, 94975, 94744, 94972, 94968, 94973, 94974 }, -- Krol'dok Stronghold
    [16919] = { 96403, 96394, 96393, 96391, 98423, 96395 }, -- The Hall of Thanes
}
-- quest id -> { area, ... } (built once)
local byQuest
function D.areasOf(questID)
    if not byQuest then
        byQuest = {}
        for area, ids in pairs(D.quests) do
            for _, id in ipairs(ids) do
                byQuest[id] = byQuest[id] or {}
                table.insert(byQuest[id], area)
            end
        end
    end
    return byQuest[questID]
end
