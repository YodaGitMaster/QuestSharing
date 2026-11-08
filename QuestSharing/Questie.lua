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

local function loaded(name)
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not f then return nil end
    local ok, v = pcall(f, name)
    return ok and v and true or false
end

-- /qs questie: is Questie here, which way do we read it, is it ready, and a real lookup from your own quest log
function Q.report()
    local out = {}
    local qOn, dbOn = loaded("Questie"), loaded("QuestieDB")
    out[#out + 1] = "Questie addon: " .. (qOn and "loaded" or (qOn == false and "NOT loaded (installed and ticked at the character screen?)" or "?"))
        .. (dbOn and " | QuestieDB (its database): loaded" or "")
    local src = Q.source()
    if not src then
        if QuestieLoader and Questie and Questie.started == false then
            out[#out + 1] = "Questie is still starting (or failed to start): try again in a minute"
        else
            out[#out + 1] = "no Questie database found: \"tell them where to get it\" cannot work"
        end
        return out, false
    end
    local how = { QuestieDB = "QuestieDB (Questie 12 and newer)", LibQuestieDB = "LibQuestieDB", Questie = "Questie's own database (older Questie)" }
    out[#out + 1] = "reading: " .. how[src] .. ((Questie and Questie.API and Questie.API.isReady == false) and " - Questie is not fully ready yet" or "")
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
