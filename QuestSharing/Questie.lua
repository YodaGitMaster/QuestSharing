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

local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, ...)
    if ok then return v end
end

local function legacy()
    if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
    if Questie and Questie.started == false then return nil end             -- still starting (or failed to start)
    local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    if ok and type(mod) == "table" and type(mod.QueryQuestSingle) == "function" then return mod end
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
    if p[1] == -1 and p[2] == -1 then return { zone = zone, dungeon = true } end
    return { zone = zone, x = p[1], y = p[2] }
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
            s.from, s.zone, s.x, s.y, s.dungeon = field("npc", from, "name"), sp.zone, sp.x, sp.y, sp.dungeon
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
