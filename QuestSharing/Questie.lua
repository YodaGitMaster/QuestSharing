-- Questie.lua: if the Questie addon is installed, its quest database tells us where a quest starts and which quests
-- come before it, so a party member who does not have one of your quests can be told where to get it.
--   "Bob: [Wolves Among Us] starts at Marshal Dughan in Elwynn Forest (42.1, 65.9), after "A Threat Within"."
-- Only READS Questie's data (nothing is copied into this addon), and every call is guarded: without Questie, or with a
-- Questie version that looks different, these features simply say they need Questie.
--
-- Two ways in, newest first:
--   * Questie 12 ships its data as the addon "QuestieDB": globals QuestDB / NpcDB / ObjectDB / ItemDB, QuestDB.Get(id, key)
--   * Questie 11 and older: QuestieLoader:ImportModule("QuestieDB").QueryQuestSingle(id, key) (only once Questie started)
-- Spawns are { [areaId] = { {x, y}, ... } } with x, y from 0 to 100; {-1, -1} means inside a dungeon.
local ADDON, ns = ...
local C = ns.compat

local Q = {}
ns.questie = Q
local spawnList

local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, ...)
    if ok then return v end
end

-- Speed: every field Questie 12 has no value for falls through to here, thousands of times per scan. A module once found
-- is kept for as long as the same loader is installed (a failed or not-yet-started lookup is not kept, so it retries).
local foundLoader, foundModule
local function questieModule()
    if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
    if Questie and Questie.started == false then return nil end             -- still starting (or failed to start)
    if foundModule and foundLoader == QuestieLoader then return foundModule end
    local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    if ok and type(mod) == "table" then foundLoader, foundModule = QuestieLoader, mod; return mod end
end

local function legacy()
    local mod = questieModule()
    if mod and type(mod.QueryQuestSingle) == "function" then return mod end
end

-- one field of one record: kind = "quest" | "npc" | "object" | "item"
local NEW = { quest = "QuestDB", npc = "NpcDB", object = "ObjectDB", item = "ItemDB" }
local LIB = { quest = { "Quest" }, npc = { "Npc", "NPC" }, object = { "Object" }, item = { "Item" } }   -- LibQuestieDB.<x>.Get
local OLD = { quest = "QueryQuestSingle", npc = "QueryNPCSingle", object = "QueryObjectSingle", item = "QueryItemSingle" }

local function getFrom(db, id, key)
    if type(db) ~= "table" then return nil end
    if type(db.Get) == "function" then
        local v = call(db.Get, id, key)
        if v ~= nil then return v end
    end
    if type(db[key]) == "function" then return call(db[key], id) end
end

local function libTable(kind)
    if type(LibQuestieDB) ~= "table" then return nil end
    for _, n in ipairs(LIB[kind]) do if type(LibQuestieDB[n]) == "table" then return LibQuestieDB[n] end end
end

local function field(kind, id, key)
    if not id then return nil end
    local v = getFrom(_G[NEW[kind]], id, key)
    if v == nil then v = getFrom(libTable(kind), id, key) end
    if v ~= nil then return v end
    local mod = legacy()
    if mod then return call(mod[OLD[kind]], id, key) end
end

-- which way in works here: "QuestieDB" (Questie 12), "LibQuestieDB", "Questie" (older) or nil
function Q.source()
    local q = _G.QuestDB
    if type(q) == "table" and (type(q.Get) == "function" or type(q.name) == "function") then return "QuestieDB" end
    local lib = libTable("quest")
    if lib and type(lib.Get) == "function" then return "LibQuestieDB" end
    if legacy() then return "Questie" end
    return nil
end

function Q.available() return Q.source() ~= nil end

-- The language of the names Questie hands out, and the game's. QuestieDB starts in the game's language, but Questie
-- switches it to Questie's own language setting (English when the game's is one Questie has no translation for).
-- Names on screen are always in the game's language, so Questie's names only recognise creatures when the two agree.
local function oneEnglish(l) return (l == "enGB") and "enUS" or l end      -- the database has one English
function Q.languages()
    local client = call(GetLocale)
    client = oneEnglish(type(client) == "string" and client or "enUS")
    local names
    local l10n = type(LibQuestieDB) == "table" and LibQuestieDB.l10n
    if type(l10n) == "table" and type(l10n.currentLocale) == "string" then
        names = l10n.currentLocale                                          -- Questie 12: what QuestieDB reads now
    elseif type(Questie) == "table" and type(Questie.db) == "table" and type(Questie.db.global) == "table" then
        local g = Questie.db.global                                         -- older Questie: its language setting
        if g.questieLocaleDiff and type(g.questieLocale) == "string" then names = g.questieLocale end
    end
    return oneEnglish(names or client), client
end

function Q.sameLanguage()
    local names, client = Q.languages()
    return names == client
end

-- "Questie's names are in enUS, the game is in deDE: ..." when they differ, or nil
function Q.languageNote()
    local names, client = Q.languages()
    if names == client then return nil end
    return string.format("Questie's names are in %s, the game is in %s: they cannot recognise creatures on screen "
        .. "(set Questie's language to the game's)", names, client)
end

local function loaded(name)
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not f then return nil end
    local ok, v = pcall(f, name)
    return ok and v and true or false
end

-- What the game's AddOns list says about an addon: { installed, loaded, why (when not loaded), version }
local REASON = {
    MISSING = "not installed (no folder with that name in Interface/AddOns)",
    DISABLED = "installed but switched off: tick it in the AddOns list at the character screen",
    INTERFACE_VERSION = "installed but marked out of date: tick \"Load out of date AddOns\" at the character screen",
    DEP_MISSING = "installed, but an addon it needs is missing",
    DEP_DISABLED = "installed, but an addon it needs is switched off",
    CORRUPT = "damaged: install it again",
    INCOMPATIBLE = "not made for this game version",
    BANNED = "blocked by the game",
    DEMAND_LOADED = "installed, loads only when asked for",
}
local function addonState(name)
    local s = { loaded = loaded(name) == true }
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    local reason
    if info then
        local ok, n, _, _, loadable, r = pcall(info, name)
        if ok then
            reason = r
            if (n == nil or n == "") and not reason then reason = "MISSING" end
            if loadable and not reason then reason = nil end
        end
    end
    s.installed = s.loaded or (reason ~= "MISSING" and info ~= nil)
    if not s.loaded then s.why = REASON[reason or ""] or (reason and ("not loaded (" .. tostring(reason) .. ")")) or "not loaded" end
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if meta and s.loaded then
        local okV, v = pcall(meta, name, "Version")
        if okV and type(v) == "string" and v ~= "" then s.version = v end
    end
    return s
end
Q.addonState = addonState

-- folders whose name has "questie" in it, other than Questie and QuestieDB (a renamed download, e.g. "Questie-master")
local function otherFolders()
    local out = {}
    local count = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not (count and info) then return out end
    local okN, n = pcall(count)
    for i = 1, (okN and tonumber(n) or 0) do
        local ok, name = pcall(info, i)
        if ok and type(name) == "string" and string.find(string.lower(name), "questie", 1, true)
           and name ~= "Questie" and name ~= "QuestieDB" then
            out[#out + 1] = name .. (loaded(name) and " (loaded)" or " (not loaded)")
        end
    end
    return out
end

-- why Questie's data cannot be read, in a few words (nil when it can): for grey menu lines and the doctor
function Q.whyMissing()
    if Q.source() then return nil end
    local q, db = addonState("Questie"), addonState("QuestieDB")
    if q.loaded and not db.installed then return "Questie is here but its quest data (the QuestieDB folder) is missing - /qs questie" end
    if q.loaded and not db.loaded then return "QuestieDB (Questie's quest data) is not loaded - /qs questie" end
    if Questie and Questie.started == false then return "Questie is still starting (or failed to start) - /qs questie" end
    if not q.installed and not db.installed then return "needs the Questie addon (both folders: Questie and QuestieDB)" end
    return "Questie's quest data cannot be read - /qs questie says why"
end

-- /qs questie: each addon's state in the AddOns list, what the game has, a verdict with what to do, then (when it
-- works) the language and a real lookup from your own quest log
function Q.report()
    local out = {}
    local q, db = addonState("Questie"), addonState("QuestieDB")
    local function state(s) return s.loaded and ("loaded" .. (s.version and (", version " .. s.version) or "")) or s.why end
    out[#out + 1] = "Questie: " .. state(q)
    out[#out + 1] = "QuestieDB (Questie's quest data, its own folder since Questie 12): " .. state(db)
    local others = otherFolders()
    if #others > 0 then out[#out + 1] = "other folders with Questie in the name: " .. table.concat(others, ", ") end
    local function yn(v) return v and "yes" or "no" end
    out[#out + 1] = string.format("found in the game: QuestDB %s, LibQuestieDB %s, QuestieLoader %s%s",
        yn(type(_G.QuestDB) == "table"), yn(type(LibQuestieDB) == "table"), yn(type(QuestieLoader) == "table"),
        (type(Questie) == "table" and Questie.started ~= nil) and (", Questie started " .. yn(Questie.started)) or "")
    local src = Q.source()
    if not src then
        if q.loaded and not db.installed then
            out[#out + 1] = "-> Questie 12 keeps its quest data in a second folder, QuestieDB, and it is missing. Copy BOTH " ..
                "folders of the Questie download (Questie and QuestieDB) into Interface/AddOns, then restart the game. " ..
                "(Questie itself cannot work without it either.)"
        elseif db.installed and not db.loaded then
            out[#out + 1] = "-> QuestieDB is " .. tostring(db.why)
        elseif Questie and Questie.started == false then
            out[#out + 1] = "-> Questie is still starting (or failed to start): try again in a minute"
        elseif not q.installed and #others > 0 then
            out[#out + 1] = "-> Questie's folder has another name (" .. others[1] .. "): rename it to Questie (and its database " ..
                "folder to QuestieDB), then restart the game"
        elseif not q.installed and not db.installed then
            out[#out + 1] = "-> no Questie found: install Questie (both folders, Questie and QuestieDB) for \"Tell them " ..
                "where to get it\" and \"Trace back the chain\""
        elseif not q.loaded then
            out[#out + 1] = "-> Questie is " .. tostring(q.why)
        else
            out[#out + 1] = "-> Questie and QuestieDB are loaded but their data cannot be read: please send me this report"
        end
        return out, false
    end
    local how = { QuestieDB = "QuestieDB (Questie 12 and newer)", LibQuestieDB = "LibQuestieDB", Questie = "Questie's own database (older Questie)" }
    out[#out + 1] = "reading: " .. how[src] .. ((Questie and Questie.API and Questie.API.isReady == false) and " - Questie is not fully ready yet" or "")
    out[#out + 1] = Q.languageNote() or ("names: " .. (Q.languages()) .. ", the game's language")
    local tried, found = 0, 0
    for _, e in ipairs(C.entries()) do
        if tried >= 3 then break end
        tried = tried + 1
        local where = Q.whereText(e.questID)
        if where then found = found + 1 end
        out[#out + 1] = C.link(e) .. " " .. (where or "- Questie has no start for this quest")
    end
    if tried == 0 then out[#out + 1] = "(no quests in your log to look up)" end
    out[#out + 1] = (found > 0) and "Questie works with Quest Sharing." or (tried > 0 and "Questie answered nothing for these quests - send me this report." or "")
    return out, found > 0
end

local function zoneName(areaId)
    if not areaId then return nil end
    if C_Map and C_Map.GetAreaInfo then
        local n = call(C_Map.GetAreaInfo, areaId)
        if type(n) == "string" and n ~= "" then return n end
    end
    if GetAreaInfo then
        local n = call(GetAreaInfo, areaId)
        if type(n) == "string" and n ~= "" then return n end
    end
end

-- the first spawn of an npc or object: zone name, x, y (0..100), or "dungeon"
local function firstSpawn(kind, id)
    local spawns = field(kind, id, "spawns")
    if type(spawns) ~= "table" then return nil end
    local bestArea, bestList
    for areaId, list in pairs(spawns) do
        if type(list) == "table" and list[1] then
            if not bestArea or areaId < bestArea then bestArea, bestList = areaId, list end     -- the same answer every time
        end
    end
    if not bestList then return nil end
    local p = bestList[1]
    local zone = zoneName(bestArea)
    if p[1] == -1 and p[2] == -1 then return { zone = zone, area = bestArea, dungeon = true } end
    return { zone = zone, area = bestArea, x = p[1], y = p[2] }
end

-- Where a quest starts: { who = "Marshal Dughan", kind = "npc"|"object"|"item", zone, x, y, dungeon } or nil
function Q.starter(questID)
    local by = field("quest", questID, "startedBy")
    if type(by) ~= "table" then return nil end
    local npc = type(by[1]) == "table" and by[1][1]
    local obj = type(by[2]) == "table" and by[2][1]
    local item = type(by[3]) == "table" and by[3][1]
    if npc then
        local s = firstSpawn("npc", npc) or {}
        s.who, s.kind = field("npc", npc, "name") or "a quest giver", "npc"
        return s
    elseif obj then
        local s = firstSpawn("object", obj) or {}
        s.who, s.kind = field("object", obj, "name") or "an object", "object"
        return s
    elseif item then
        local s = { who = field("item", item, "name") or "an item", kind = "item" }
        local drops = field("item", item, "npcDrops")
        local from = type(drops) == "table" and drops[1]
        if from then
            local sp = firstSpawn("npc", from) or {}
            s.from, s.zone, s.area, s.x, s.y, s.dungeon = field("npc", from, "name"), sp.zone, sp.area, sp.x, sp.y, sp.dungeon
        end
        return s
    end
end

-- The quests that must be done first: names, ids, any. preQuestSingle = any one of them, preQuestGroup = all of them.
local function beforeIds(questID)
    local single = field("quest", questID, "preQuestSingle")
    local group = field("quest", questID, "preQuestGroup")
    if type(single) == "table" and #single > 0 then return single, true end
    if type(group) == "table" then return group, false end
    return {}, false
end

function Q.before(questID)
    local list, any = beforeIds(questID)
    local names, ids = {}, {}
    for i = 1, math.min(#list, 3) do
        local id = math.abs(list[i])
        local n = field("quest", id, "name")
        if n then names[#names + 1] = n; ids[#ids + 1] = id end
    end
    return names, any, ids
end

-- how many steps come before this quest, following the first earlier quest each time (at most 10 are counted)
function Q.stepsBefore(questID)
    local n, id, seen = 0, questID, {}
    while n < 10 do
        local list = beforeIds(id)
        local first = list[1] and math.abs(list[1])
        if not first or seen[first] then break end
        seen[first] = true
        n, id = n + 1, first
    end
    return n
end

-- "Marshal McBride in Elwynn Forest (48.9, 41.6)" for where a quest starts, or nil
local function placeOf(s)
    if not s then return nil end
    local where
    if s.dungeon then where = " inside a dungeon" .. (s.zone and (" (" .. s.zone .. ")") or "")
    elseif s.x then where = string.format(" in %s (%.1f, %.1f)", s.zone or "this zone", s.x, s.y)
    else where = s.zone and (" in " .. s.zone) or "" end
    return where
end

-- the creatures a quest's objectives need: the ones to kill (also those that count for another), and the ones that
-- drop its items (names, in Questie's language: see Q.sameLanguage)
function Q.creatureNames(questID)
    local out = {}
    local objs = field("quest", questID, "objectives")
    if type(objs) ~= "table" then return out end
    if type(objs[1]) == "table" then                                  -- creatures to kill: { { npcId, text }, ... }
        for _, o in ipairs(objs[1]) do
            local id = type(o) == "table" and o[1] or o
            local n = id and field("npc", id, "name")
            if n then out[#out + 1] = n end
        end
    end
    if type(objs[5]) == "table" then                                  -- kill credit, any of them counts: { { {npcIds}, npcId, text }, ... }
        for _, o in ipairs(objs[5]) do
            local ids = type(o) == "table" and o[1]
            if type(ids) == "table" then
                for i = 1, math.min(#ids, 10) do
                    local n = field("npc", ids[i], "name")
                    if n then out[#out + 1] = n end
                end
            end
        end
    end
    if type(objs[3]) == "table" then                                  -- items to get: the creatures that drop them
        for _, o in ipairs(objs[3]) do
            local item = type(o) == "table" and o[1] or o
            local drops = item and field("item", item, "npcDrops")
            if type(drops) == "table" then
                for i = 1, math.min(#drops, 6) do
                    local n = field("npc", drops[i], "name")
                    if n then out[#out + 1] = n end
                end
            end
        end
    end
    return out
end

-- Where things are: QuestieDB's zones (area IDs) on the game's maps (UI map IDs) ---------------------------------------
Q.get = field                                                   -- one field of one record, shared by data-driven tools

-- Enumerable IDs are available in current QuestieDB / LibQuestieDB builds. Older Questie versions can still
-- answer direct item queries, but cannot build a whole-catalogue map search.
-- Inspect capabilities without reading/enumerating the database on a blank map.
function Q.canEnumerate(kind)
    local db, lib = _G[NEW[kind]], libTable(kind)
    return (type(db) == "table" and type(db.GetAllIds) == "function")
        or (type(lib) == "table" and type(lib.GetAllIds) == "function")
end

function Q.ids(kind)
    local db = _G[NEW[kind]]
    if type(db) == "table" and type(db.GetAllIds) == "function" then
        local ids = call(db.GetAllIds)
        if type(ids) == "table" then return ids end
    end
    db = libTable(kind)
    if type(db) == "table" and type(db.GetAllIds) == "function" then
        local ids = call(db.GetAllIds)
        if type(ids) == "table" then return ids end
    end
end

-- Scoped reads. QuestieDB keeps every (id, field) it reads for the whole session, so a scan that reads the big
-- tables (startedBy, spawns, vendors) of every id pays memory for data nobody asked about. These gates read only
-- single numbers and strings; a scan reads the big tables for the ids that pass. Unknown data never skips.
function Q.me()
    local ui, enums = ns.optionalUI, type(LibQuestieDB) == "table" and LibQuestieDB.Enum or {}
    local _, token = ui.call(UnitClass, "player")
    local _, _, raceID = ui.call(UnitRace, "player")
    local group = ui.call(UnitFactionGroup, "player")
    local level = tonumber(ui.call(UnitLevel, "player"))
    return { level = level and level >= 1 and level or nil,
        classMask = enums.classKeys and enums.classKeys[token], raceMask = enums.raceMaskById and enums.raceMaskById[raceID],
        faction = (group == "Alliance" and "A") or (group == "Horde" and "H") or nil }
end

-- scope = { raceMask, classMask, level, slack, noMax }: a nil member is not checked. Returns nil (keep) or why it is skipped:
-- "character" (other race, faction or class), "level" (needs more than level + slack), "overlevel" (past its maximum).
function Q.questGate(id, scope)
    if scope.raceMask then
        local races = tonumber((field("quest", id, "requiredRaces"))) or 0
        if races > 0 and not ns.rewards.overlaps(races, scope.raceMask) then return "character" end
    end
    if scope.classMask then
        local classes = tonumber((field("quest", id, "requiredClasses"))) or 0
        if classes > 0 and not ns.rewards.overlaps(classes, scope.classMask) then return "character" end
    end
    if scope.level then
        if (tonumber((field("quest", id, "requiredLevel"))) or 0) > scope.level + (scope.slack or 0) then return "level" end
        if scope.noMax then return nil end             -- a scan that a lower level filter must still be able to use
        local max = tonumber((field("quest", id, "requiredMaxLevel"))) or 0
        if max > 0 and scope.level > max then return "overlevel" end
    end
end

-- false only for an NPC that is friendly to the other faction alone ("A", "H" or "AH"; nil is unknown or hostile to both).
function Q.npcFriendly(id, faction)
    if not faction then return true end
    local friendly = field("npc", id, "friendlyToFaction")
    return type(friendly) ~= "string" or friendly == "" or string.find(friendly, faction, 1, true) ~= nil
end

-- Quest planner reads a complete, uncapped projection. Q.targets() is intentionally a short chat/display summary;
-- using it for optimization would silently lose alternate mobs and item sources.
local function plannerField(kind, id, key, cache)
    local value = field(kind, id, key)
    if cache and ns.dataWork then ns.dataWork.checkpoint() end
    return value
end

local function appendSources(out, kind, ids, cache)
    if type(ids) ~= "table" then return end
    for _, id in ipairs(ids) do
        if type(id) == "number" then
            local key = kind .. ":" .. tostring(id)
            local source = cache and cache[key]
            if not source then
                source = { kind = kind, id = id, name = plannerField(kind, id, "name", cache), spawns = spawnList(kind, id) }
                if cache then
                    cache._keys = cache._keys or {}
                    cache._slot = (cache._slot or 0) % 256 + 1
                    local old = cache._keys[cache._slot]
                    if old then cache[old] = nil end
                    cache._keys[cache._slot], cache[key] = key, source
                end
            end
            out[#out + 1] = source
        end
    end
end

local function itemSources(itemID, cache)
    local out = {}
    appendSources(out, "npc", plannerField("item", itemID, "npcDrops", cache), cache)
    appendSources(out, "object", plannerField("item", itemID, "objectDrops", cache), cache)
    return out
end

local function allStarters(questID, cache)
    local out, by = {}, plannerField("quest", questID, "startedBy", cache)
    if type(by) ~= "table" then return out end
    appendSources(out, "npc", by[1], cache)
    appendSources(out, "object", by[2], cache)
    for _, itemID in ipairs(type(by[3]) == "table" and by[3] or {}) do
        for _, source in ipairs(itemSources(itemID, cache)) do
            out[#out + 1] = { kind = source.kind, id = source.id, name = source.name, spawns = source.spawns,
                startsFrom = { id = itemID, name = plannerField("item", itemID, "name", cache) } }
        end
    end
    return out
end
function Q.plannerStarters(questID, cache) return allStarters(questID, cache) end

local function positiveInteger(value)
    if type(value) == "number" and value > 0 and value < math.huge and value == math.floor(value) then return value end
end

-- The normal Questie row has ID, optional localized label, and icon. None of its positional fields
-- is a quantity. The English descriptions sometimes give a quantity directly before the source name.
local function describedQuantity(descriptions, name)
    if not (type(descriptions) == "table" and type(name) == "string" and #name > 1) then return end
    local needle, count = string.lower(name), nil
    for _, line in ipairs(descriptions) do
        if type(line) == "string" then
            local lower, from = string.lower(line), 1
            while true do
                local first, last = string.find(lower, needle, from, true)
                if not first then break end
                local tail = string.sub(lower, last + 1)
                if tail == "" or string.match(tail, "^%W") or string.match(tail.." ", "^s%W") then
                    local before = string.sub(lower, 1, first - 1)
                    local n = positiveInteger(tonumber(string.match(before, "%f[%d](%d+)%s+$")
                        or string.match(before, "%f[%d](%d+)%s+pieces%s+of%s+$")))
                    if n and count and n ~= count then return end
                    count = n or count
                end
                from = last + 1
            end
        end
    end
    return count
end

local function plannerTargets(questID, cache)
    local out, objs = {}, plannerField("quest", questID, "objectives", cache)
    local descriptions = plannerField("quest", questID, "objectivesText", cache)
    local function add(kind, row, id, name, sources)
        local target = {kind=kind, name=name, sources=sources, creditID=kind=="kill" and id or nil,
            itemID=kind=="loot" and id or nil, objectiveText=type(row[2])=="string" and row[2] or nil}
        target.required = positiveInteger(row.required)
        if target.required then target.countSource = "provider"
        elseif kind == "kill" or kind == "loot" then
            target.required = describedQuantity(descriptions, name)
            if target.required then target.countSource = "description" end
        end
        if kind == "loot" then
            target.dropRates, target.rateSources = {}, {}
            for _, source in ipairs(sources) do
                if source.kind == "npc" then
                    local percent, origin = Q.itemDropRate(id, source.id)
                    if percent then target.dropRates[source.id], target.rateSources[source.id] = percent / 100, origin end
                    if cache and ns.dataWork then ns.dataWork.checkpoint() end
                end
            end
        end
        out[#out + 1] = target
    end
    if type(objs) == "table" then
        for _, row in ipairs(type(objs[1]) == "table" and objs[1] or {}) do
            local id = type(row)=="table" and positiveInteger(row[1])
            if id then
                local sources = {}; appendSources(sources, "npc", {id}, cache)
                local custom = type(row[2]) == "string" and row[2] ~= ""
                add(custom and "interact" or "kill", row, id, sources[1] and sources[1].name, sources)
            end
        end
        for _, row in ipairs(type(objs[5]) == "table" and objs[5] or {}) do
            local ids = type(row) == "table" and type(row[1]) == "table" and row[1] or nil
            local sources = {}; appendSources(sources, "npc", ids, cache)
            if #sources > 0 then
                local names = {}; for _, src in ipairs(sources) do if src.name then names[#names + 1] = src.name end end
                add("kill", row, positiveInteger(row[2]), table.concat(names, " or "), sources)
            end
        end
        for _, row in ipairs(type(objs[2])=="table" and objs[2] or {}) do
            local id = type(row)=="table" and positiveInteger(row[1])
            if id then
                local sources = {}; appendSources(sources, "object", {id}, cache)
                add("object", row, id, sources[1] and sources[1].name, sources)
            end
        end
        for _, row in ipairs(type(objs[3])=="table" and objs[3] or {}) do
            local id = type(row)=="table" and positiveInteger(row[1])
            if id then add("loot", row, id, plannerField("item", id, "name", cache), itemSources(id, cache)) end
        end
        for _, slot in ipairs({4, 6}) do
            if type(objs[slot])=="table" and next(objs[slot]) then
                out[#out + 1] = {kind="unknown", name=slot==4 and "Reputation objective" or "Spell objective",sources={}}
            end
        end
    end
    local trigger = plannerField("quest", questID, "triggerEnd", cache)
    if type(trigger) == "table" and type(trigger[2]) == "table" then
        local points = {}
        for area, locations in pairs(trigger[2]) do
            for _, pt in ipairs(type(locations) == "table" and locations or {}) do
                if type(pt) == "table" and pt[1] and pt[2] then
                    points[#points + 1] = { area = area, map = Q.uiMapOf(area), x = pt[1], y = pt[2] }
                end
            end
        end
        out[#out + 1] = { kind = "explore", name = type(trigger[1]) == "string" and trigger[1] or "Explore", points = points, sources = {} }
    end
    for _, target in ipairs(out) do
        target.points = target.points or {}
        for _, source in ipairs(target.sources or {}) do
            for _, point in ipairs(source.spawns or {}) do target.points[#target.points + 1] = point end
        end
    end
    return out
end

local function questBaseXP(id, cache)
    local module = cache and cache._xp
    if module == nil then
        local support = type(LibQuestieDB)=="table" and LibQuestieDB.Support
        module = support and call(support.Get, "QuestXP")
        if type(module)~="table" or type(module.db)~="table" then
            module = QuestieLoader and call(QuestieLoader.ImportModule, QuestieLoader, "QuestXP")
        end
        if cache then cache._xp = module or false end
    end
    local row = type(module)=="table" and type(module.db)=="table" and module.db[id]
    local value = type(row)=="table" and row[2]
    if type(value)=="number" and value>=0 and value<math.huge then return value end
end

function Q.plannerQuest(questID, cache)
    local name = plannerField("quest", questID, "name", cache)
    if not name then return nil end
    local single, group = plannerField("quest", questID, "preQuestSingle", cache), plannerField("quest", questID, "preQuestGroup", cache)
    local finish = plannerField("quest", questID, "finishedBy", cache)
    local turnIns = {}
    if type(finish) == "table" then
        appendSources(turnIns, "npc", finish[1], cache)
        appendSources(turnIns, "object", finish[2], cache)
    end
    local flags = tonumber(plannerField("quest", questID, "specialFlags", cache)) or 0
    local exclusives = plannerField("quest", questID, "exclusiveTo", cache)
    local targets = plannerTargets(questID, cache)
    local function pair(key)
        local value = plannerField("quest", questID, key, cache)
        if type(value) == "table" and positiveInteger(value[1]) and type(value[2]) == "number"
            and value[2] == value[2] and math.abs(value[2]) < math.huge then
            return {value[1], value[2]}
        end
    end
    local rewards = {}
    local rewardRows = plannerField("quest", questID, "reputationReward", cache)
    for _, row in ipairs(type(rewardRows) == "table" and rewardRows or {}) do
        if type(row) == "table" and positiveInteger(row[1]) and type(row[2]) == "number"
            and row[2] == row[2] and math.abs(row[2]) < math.huge then
            rewards[row[1]] = (rewards[row[1]] or 0) + row[2]
        end
    end
    local rankRows = plannerField("quest", questID, "requiredRanks", cache)
    local requiredRanks = {}
    for _, row in ipairs(type(rankRows) == "table" and rankRows or {}) do
        if type(row) == "table" and positiveInteger(row[1]) and type(row[2]) == "number"
            and row[2] >= 0 and row[2] < math.huge then
            requiredRanks[#requiredRanks + 1] = {row[1], row[2]}
        end
    end
    if flags % 4 >= 2 and #targets == 0 then
        targets[1] = {kind="event", name="Quest event", sources={}, points={}}
    end
    return {
        repeatable = flags % 2 == 1, xp = questBaseXP(questID, cache),
        requiredMinRep = pair("requiredMinRep"), requiredMaxRep = pair("requiredMaxRep"),
        requiredSkill = pair("requiredSkill"), requiredRanks = requiredRanks,
        reputationReward = rewards,
        exclusiveTo = type(exclusives) == "table" and exclusives or {},
        parentQuest = positiveInteger(plannerField("quest",questID,"parentQuest",cache)),
        availableStartingWith = positiveInteger(plannerField("quest",questID,"availableStartingWith",cache)),
        availableUntilCompleted = positiveInteger(plannerField("quest",questID,"availableUntilCompleted",cache)),
        requiredMaxLevel = positiveInteger(plannerField("quest",questID,"requiredMaxLevel",cache)),
        id = questID, name = name, level = tonumber(plannerField("quest", questID, "questLevel", cache) or 0) or 0,
        requiredLevel = tonumber(plannerField("quest", questID, "requiredLevel", cache) or 0) or 0,
        beforeAny = type(single) == "table" and single or {},
        beforeAll = type(group) == "table" and group or {},
        starters = allStarters(questID, cache), targets = targets, turnIns = turnIns,
    }
end

-- Questie's own policy check accounts for more than prerequisite fields (race, class, level, phase, event, etc.).
-- It is optional because older Questie builds expose a different API; callers must treat nil as unknown.
function Q.questDoable(questID)
    local mod = questieModule()
    if mod and type(mod.IsDoable) == "function" then
        local value = call(mod.IsDoable, questID)
        if type(value) == "boolean" then return value end
    end
end

-- The provider's first failure can be a chain gate. Check other character restrictions
-- before predicting that turning in the parent alone will make this quest attainable.
function Q.futureCharacterGate(id, skipReputation)
    local enums = type(LibQuestieDB)=="table" and LibQuestieDB.Enum or {}
    local ui = ns.optionalUI
    local _, token = ui.call(UnitClass, "player")
    local _, _, raceID = ui.call(UnitRace, "player")
    local masks = {requiredClasses = enums.classKeys and enums.classKeys[token],
        requiredRaces = enums.raceMaskById and enums.raceMaskById[raceID]}
    for _, key in ipairs({"requiredClasses", "requiredRaces"}) do
        local required = tonumber((field("quest",id,key))) or 0
        if required > 0 then
            if not masks[key] then return "unknown", "Character restriction cannot be verified" end
            if not ns.rewards.overlaps(required, masks[key]) then
                return "blocked", key=="requiredClasses" and "Wrong class for this quest" or "Wrong race or faction for this quest"
            end
        end
    end
    for _, key in ipairs({"requiredMinRep","requiredMaxRep","requiredSpecialization"}) do
        local requirement = field("quest",id,key)
        if (not skipReputation or (key ~= "requiredMinRep" and key ~= "requiredMaxRep"))
            and ((type(requirement)=="table" and next(requirement)) or (type(requirement)=="number" and requirement~=0)) then
            return "unknown", "Future eligibility needs a profession or reputation check"
        end
    end
    local spell = positiveInteger(field("quest", id, "requiredSpell"))
    if spell then
        local known = call(IsSpellKnown, spell)
        if known == nil then return "unknown","Required spell cannot be verified" end
        if not known then return "blocked","Requires spell " .. spell end
    end
    local skill, ranks = field("quest", id, "requiredSkill"), field("quest", id, "requiredRanks")
    local skills = {}
    if type(skill) == "table" and positiveInteger(skill[1]) then skills[skill[1]] = true end
    for _, row in ipairs(type(ranks) == "table" and ranks or {}) do
        if type(row) == "table" and positiveInteger(row[1]) then skills[row[1]] = true end
    end
    if next(skills) then
        local values = ns.compat.plannerSkills(skills)
        if type(skill) == "table" and positiveInteger(skill[1]) then
            local current = values[skill[1]]
            if current == nil then return "unknown", "Future eligibility needs a profession skill value" end
            if current < (tonumber(skill[2]) or math.huge) then return "blocked", "Profession skill too low" end
        end
        if type(ranks) == "table" and #ranks > 0 then
            local matched, unknown = false, false
            for _, row in ipairs(ranks) do
                if type(row) == "table" and positiveInteger(row[1]) then
                    local current = values[row[1]]
                    if current == nil then unknown = true
                    elseif current >= (tonumber(row[2]) or math.huge) then matched = true end
                end
            end
            if not matched then
                if unknown then return "unknown", "Future eligibility needs a profession rank value" end
                return "blocked", "Profession rank too low"
            end
        end
    end
    if skipReputation then
        local factions = {}
        for _, key in ipairs({"requiredMinRep", "requiredMaxRep"}) do
            local rule = field("quest", id, key)
            if type(rule) == "table" and positiveInteger(rule[1]) then factions[rule[1]] = true end
        end
        if next(factions) then
            local values = ns.compat.plannerReputation(factions)
            for faction in pairs(factions) do
                if values[faction] == nil then return "unknown", "Future eligibility needs a reputation value" end
            end
        end
    end
end

function Q.questBlockReason(questID)
    local mod = questieModule()
    if not (mod and type(mod.IsDoableVerbose) == "function") then return nil end
    local ok, detail, blocked, reason = pcall(mod.IsDoableVerbose, questID, false, true, true)
    if not ok then return nil end
    local states = mod.DoableStates or {}
    if blocked ~= true then
        if reason ~= nil and (reason == states.AVAILABLE or reason == states.PARENT_ACTIVE) then return "ready" end
        return nil
    end
    if reason == nil then return "unknown" end
    if reason == states.NO_PREQUESTSINGLE then return "any" end
    if reason == states.NO_PREQUESTGROUP then return "all" end
    if reason == states.PARENT_INACTIVE or reason == states.ENABLING_QUEST_MISSING then return "parent" end
    if reason == states.LEVEL_TOO_LOW then return "level" end
    if reason == states.LEVEL_TOO_HIGH then return "overlevel" end
    if reason == states.MISSING_REPUTATION or reason == states.EXCEED_REPUTATION then return "reputation" end
    if reason == states.WRONG_RACE or reason == states.WRONG_CLASS then return "character" end
    if reason == states.EXCLUSIVE_COMPLETED or reason == states.EXCLUSIVE_IN_QUEST_LOG then return "exclusive" end
    return "other", type(detail)=="string" and detail or nil
end

function Q.questComplete(questID)
    if C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted) == "function" then
        local value = call(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if value ~= nil then return value and true or false end
    end
    local complete = type(Questie) == "table" and type(Questie.db) == "table"
        and type(Questie.db.char) == "table" and Questie.db.char.complete
    if type(complete) == "table" then return complete[questID] == true end
end

-- DropDB.GetItemDroprate returns {percent, source}. Its units are 0..100, including
-- sub-one-percent drops. Never reinterpret a smaller percentage as a fraction.
function Q.itemDropRate(itemID, npcID)
    if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
    local drops = call(QuestieLoader.ImportModule, QuestieLoader, "DropDB")
    local result = type(drops) == "table" and call(drops.GetItemDroprate, itemID, npcID)
    local value, origin
    if type(result) == "table" then value, origin = result[1], result[2]
    elseif type(result) == "number" then value = result
    elseif type(result) == "string" then value = tonumber((result:match("^%s*([%d%.]+)%%%s*$"))) end
    if type(value) == "number" and value >= 0 and value <= 100 then
        return value, type(origin) == "string" and origin or "Questie"
    end
end

local areaToMap
local function decodeTable(s)
    if type(s) == "table" then return s end
    if type(s) ~= "string" or not loadstring then return nil end
    local chunk = loadstring(s)
    if not chunk then return nil end
    local ok, v = pcall(chunk)
    return (ok and type(v) == "table") and v or nil
end
-- the game's map for one of QuestieDB's zones (QuestieDB ships the table, with its overrides), or nil
function Q.uiMapOf(areaId)
    if areaToMap == nil then
        areaToMap = false
        local lib = type(LibQuestieDB) == "table" and LibQuestieDB.Support
        local ok, zone = pcall(function() return lib and lib.Get and lib.Get("ZoneDB") end)
        local priv = ok and type(zone) == "table" and zone.private
        if type(priv) == "table" then
            local base = decodeTable(priv.areaIdToUiMapId)
            if base then
                for a, m in pairs(decodeTable(priv.areaIdToUiMapIdOverride) or {}) do base[a] = m end
                areaToMap = base
            end
        end
    end
    return areaToMap and areaToMap[areaId] or nil
end

-- every spawn of an npc or object: { { area, map, x, y (0..100), dungeon }, ... }
spawnList = function(kind, id)
    local out = {}
    local spawns = field(kind, id, "spawns")
    if type(spawns) ~= "table" then return out end
    for areaId, list in pairs(spawns) do
        if type(list) == "table" then
            for _, pt in ipairs(list) do
                if type(pt) == "table" and pt[1] and pt[2] then
                    out[#out + 1] = { area = areaId, map = Q.uiMapOf(areaId), x = pt[1], y = pt[2], dungeon = (pt[1] == -1 and pt[2] == -1) }
                end
            end
        end
    end
    table.sort(out, function(a, b) if a.area ~= b.area then return a.area < b.area end; if a.x ~= b.x then return a.x < b.x end; return a.y < b.y end)
    return out
end
Q.spawnList = spawnList

-- the n spawns nearest to you (on the map you are on), else the first n
local function nearest(list, n)
    local here, px, py = C.playerPos()
    local scored = {}
    for _, s in ipairs(list) do
        if not s.dungeon then
            local d = (here and s.map == here) and ((s.x / 100 - px) ^ 2 + (s.y / 100 - py) ^ 2) or (10 + #scored)
            scored[#scored + 1] = { s = s, d = d }
        end
    end
    table.sort(scored, function(a, b) return a.d < b.d end)
    local out = {}
    for i = 1, math.min(n, #scored) do out[i] = scored[i].s end
    if #out == 0 and list[1] then out[1] = list[1] end           -- only inside a dungeon: say so
    return out
end
Q.nearest = nearest

-- "Elwynn Forest 40.1, 80.2" / "a dungeon (The Deadmines)"
local function where(s)
    if not s then return nil end
    local zone = zoneName(s.area)
    if s.dungeon then return "in a dungeon" .. (zone and (" (" .. zone .. ")") or "") end
    return string.format("%s %.1f, %.1f", zone or "?", s.x, s.y)
end
Q.where = where

-- What a quest asks for and where: { { kind = "kill"|"loot"|"object"|"explore", name, label, from, spawns }, ... }
--   kill: the creature (or any of several for kill credit); loot: the item and who or what drops it; object: the
--   thing to use; explore: the place (triggerEnd).
local MAX_SOURCES = 3
function Q.targets(questID)
    local out = {}
    local objs = field("quest", questID, "objectives")
    if type(objs) == "table" then
        for _, o in ipairs(type(objs[1]) == "table" and objs[1] or {}) do
            local id = type(o) == "table" and o[1] or o
            local name = id and field("npc", id, "name")
            if name then out[#out + 1] = { kind = "kill", name = name, label = "kill " .. name, spawns = spawnList("npc", id) } end
        end
        for _, o in ipairs(type(objs[5]) == "table" and objs[5] or {}) do       -- kill credit: any of them counts
            local ids, names, spawns = type(o) == "table" and o[1], {}, {}
            for i = 1, math.min(type(ids) == "table" and #ids or 0, MAX_SOURCES) do
                local n = field("npc", ids[i], "name")
                if n then names[#names + 1] = n; for _, s in ipairs(spawnList("npc", ids[i])) do spawns[#spawns + 1] = s end end
            end
            if #names > 0 then out[#out + 1] = { kind = "kill", name = names[1], label = "kill " .. table.concat(names, " or "), spawns = spawns } end
        end
        for _, o in ipairs(type(objs[2]) == "table" and objs[2] or {}) do       -- objects to use
            local id = type(o) == "table" and o[1] or o
            local name = id and field("object", id, "name")
            if name then out[#out + 1] = { kind = "object", name = name, label = "use " .. name, spawns = spawnList("object", id) } end
        end
        for _, o in ipairs(type(objs[3]) == "table" and objs[3] or {}) do       -- items: who or what drops them
            local item = type(o) == "table" and o[1] or o
            local name = item and field("item", item, "name")
            if name then
                local from, spawns = {}, {}
                for _, kind in ipairs({ "npc", "object" }) do
                    local list = field("item", item, kind == "npc" and "npcDrops" or "objectDrops")
                    for i = 1, math.min(type(list) == "table" and #list or 0, MAX_SOURCES) do
                        local n = field(kind, list[i], "name")
                        if n then from[#from + 1] = n; for _, s in ipairs(spawnList(kind, list[i])) do spawns[#spawns + 1] = s end end
                    end
                end
                out[#out + 1] = { kind = "loot", name = name, from = from,
                                  label = name .. (#from > 0 and (" from " .. table.concat(from, " or ")) or ""), spawns = spawns }
            end
        end
    end
    local trig = field("quest", questID, "triggerEnd")                         -- a place to go: { text, { [area] = points } }
    if type(trig) == "table" and type(trig[2]) == "table" then
        local spawns = {}
        for areaId, list in pairs(trig[2]) do
            for _, pt in ipairs(type(list) == "table" and list or {}) do
                spawns[#spawns + 1] = { area = areaId, map = Q.uiMapOf(areaId), x = pt[1], y = pt[2] }
            end
        end
        local text = type(trig[1]) == "string" and trig[1] or "the place"
        out[#out + 1] = { kind = "explore", name = text, label = "go to " .. text, spawns = spawns }
    end
    return out
end

-- where a quest is turned in: { who, spawns } or nil
function Q.turnIn(questID)
    local by = field("quest", questID, "finishedBy")
    if type(by) ~= "table" then return nil end
    local npc = type(by[1]) == "table" and by[1][1]
    local obj = type(by[2]) == "table" and by[2][1]
    if npc then return { who = field("npc", npc, "name") or "the quest giver", spawns = spawnList("npc", npc) } end
    if obj then return { who = field("object", obj, "name") or "an object", spawns = spawnList("object", obj) } end
end

-- One chat line (at most 255 letters): how to do a quest, the objectives still open first, then where to turn it in.
--   [Wolves Among Us]: kill Kobold Vermin (Elwynn Forest 40.1, 80.2); Wolf Pelt from Prowler (Elwynn Forest 41.0,
--   62.0); then turn in at Marshal McBride (Elwynn Forest 48.9, 41.6)
-- done(name) says whether the game already counts that objective as finished. nil when Questie does not know it.
function Q.howText(questID, link, done, complete)
    if not field("quest", questID, "name") then return nil end
    local head = link or ('"' .. tostring(field("quest", questID, "name")) .. '"')
    local parts = {}
    if not complete then
        for _, tg in ipairs(Q.targets(questID)) do
            if not (done and done(tg.name)) then
                local spot = where(nearest(tg.spawns, 1)[1])
                parts[#parts + 1] = tg.label .. (spot and (" (" .. spot .. ")") or "")
            end
        end
    end
    local t = Q.turnIn(questID)
    local back = t and ("turn in at " .. t.who .. (where(nearest(t.spawns, 1)[1]) and (" (" .. where(nearest(t.spawns, 1)[1]) .. ")") or ""))
    local text
    if complete or #parts == 0 then
        text = head .. ": " .. (complete and "all done - " or "") .. (back or "Questie does not know where to turn it in")
    else
        text = head .. ": " .. table.concat(parts, "; ") .. (back and ("; then " .. back) or "")
        if #text > 255 and back then text = head .. ": " .. table.concat(parts, "; ") end      -- the turn-in goes first
        while #text > 255 and #parts > 1 do table.remove(parts); text = head .. ": " .. table.concat(parts, "; ") .. " (and more)" end
    end
    return text
end

-- the items a quest hands you or needs (sourceItemId, requiredSourceItems): candidates for "use this item"
function Q.questItemIds(questID)
    local out = {}
    local src = field("quest", questID, "sourceItemId")
    if type(src) == "number" and src > 0 then out[#out + 1] = src end
    local req = field("quest", questID, "requiredSourceItems")
    if type(req) == "table" then for _, id in ipairs(req) do if type(id) == "number" then out[#out + 1] = id end end end
    return out
end

-- The chain that leads to a quest, first step first and the quest itself last: { { id, name, before, beforeAny }, ... }.
-- before = how many quests come right before that step (the first one is followed), beforeAny = any one of them is
-- enough. steps.cut = the chain goes back further than MAX_CHAIN (only a guard against broken data: real chains are
-- far shorter, and the first quest is the one that says where it all starts).
local MAX_CHAIN = 40
function Q.chain(questID)
    local steps, id, seen = {}, questID, {}
    while id and not seen[id] and #steps < MAX_CHAIN do
        seen[id] = true
        local list, any = beforeIds(id)
        table.insert(steps, 1, { id = id, name = field("quest", id, "name"), before = #list, beforeAny = any })
        id = list[1] and math.abs(list[1]) or nil
    end
    steps.cut = (id ~= nil and not seen[id]) or nil
    return steps
end

-- "Marshal McBride in Northshire Valley 48.9, 41.6" / "the item Torn Page, dropped by Kobold Miner in ..." / nil
local function shortPlace(s)
    if not s then return nil end
    local who = (s.kind == "item") and ("the item " .. s.who .. (s.from and (", dropped by " .. s.from) or "")) or s.who
    if s.dungeon then return who .. " in a dungeon" .. (s.zone and (" (" .. s.zone .. ")") or "") end
    if s.x then return string.format("%s in %s %.1f, %.1f", who, s.zone or "?", s.x, s.y) end
    return who .. (s.zone and (" in " .. s.zone) or "")
end

-- One chat line (at most 255 letters): where a quest's chain starts and every quest in it, then where this one starts.
--   [Wolves Among Us] (level 5+): 2 quests before it: "A Threat Within" at Marshal McBride in Northshire Valley
--   48.9, 41.6 > "Kobold Camp Cleanup" > then this one at Marshal Dughan in Elwynn Forest 42.1, 65.9
-- Too long: the middle steps become "(3 more)". nil when Questie does not know the quest.
function Q.chainText(questID, link)
    local steps = Q.chain(questID)
    local me = steps[#steps]
    if not (me and me.name) then return nil end
    local level = field("quest", questID, "requiredLevel")
    local head = (link or ('"' .. me.name .. '"')) ..
        ((type(level) == "number" and level > 1) and (" (level " .. level .. "+)") or "")
    local here = shortPlace(Q.starter(questID))
    if #steps == 1 then
        return head .. ": no quests before it, starts at " .. (here or "a place Questie does not know")
    end
    local names = {}
    for i = 1, #steps - 1 do
        local s, nxt = steps[i], steps[i + 1]
        local n = '"' .. (s.name or ("quest " .. s.id)) .. '"'
        if nxt.before > 1 then
            n = n .. (nxt.beforeAny and string.format(" (or %d other)", nxt.before - 1) or string.format(" (+%d more)", nxt.before - 1))
        end
        if i == 1 then
            local p = shortPlace(Q.starter(s.id))
            if p then n = n .. " at " .. p end
        end
        names[i] = n
    end
    local count = #names
    local function line(list)
        return string.format("%s: %s%d quest%s before it: %s%s > then this one%s", head, steps.cut and "at least " or "",
            count, count == 1 and "" or "s", steps.cut and "... > " or "", table.concat(list, " > "), here and (" at " .. here) or "")
    end
    local text = line(names)
    local keepLast = #names - 1
    while #text > 255 and keepLast >= 0 do              -- the first step (where it all starts) and the latest ones stay
        local list = { names[1], string.format("(%d more)", #names - 1 - keepLast) }
        for i = #names - keepLast + 1, #names do list[#list + 1] = names[i] end
        text = line(list)
        keepLast = keepLast - 1
    end
    return text
end

-- "starts at Marshal Dughan in Elwynn Forest (42.1, 65.9), after "A Threat Within""   (nil when Questie does not know)
function Q.whereText(questID)
    local s = Q.starter(questID)
    if not s then return nil end
    local place = placeOf(s)
    local text
    if s.kind == "item" then
        text = "starts from the item " .. s.who .. (s.from and (", dropped by " .. s.from) or "") .. place
    else
        text = "starts at " .. s.who .. place
    end
    -- the earlier step, and where IT starts, so they can go and get it; and how many steps lie before that one
    local names, any, ids = Q.before(questID)
    if #names > 0 then
        local quoted = {}
        for _, n in ipairs(names) do quoted[#quoted + 1] = '"' .. n .. '"' end
        text = text .. ", after " .. table.concat(quoted, any and " or " or " and ")
        local first = Q.starter(ids[1])
        if first and first.kind ~= "item" then
            text = text .. " (from " .. first.who .. (placeOf(first) or "") .. ")"
        end
        local more = Q.stepsBefore(ids[1])
        if more > 0 then text = text .. string.format(", %d more step%s before that", more, more == 1 and "" or "s") end
    end
    return text
end
