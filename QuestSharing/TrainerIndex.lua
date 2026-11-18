-- Finds every class and profession trainer in QuestieDB once (a low-priority background job that runs only while a
-- zone or continent map is open) and says which of them are yours: your class, your professions, your faction.
-- TravelMap.lua draws the result. Needs QuestieDB's NPC list; without it nothing is indexed and nothing is drawn.
local ADDON, ns = ...
local Q, Work = ns.questie, ns.dataWork
local I = {}
ns.trainerIndex = I

local call = ns.optionalUI.call
local function lower(s) return string.lower(type(s) == "string" and s or "") end

-- stem: found in the NPC's title ("Mining Trainer"); skill: the client's skill-line id (Classic Era numbers)
I.KINDS = {
    { key = "alchemy", stem = "alchem", skill = 171, label = "Alchemy" },
    { key = "blacksmithing", stem = "blacksmith", skill = 164, label = "Blacksmithing" },
    { key = "enchanting", stem = "enchant", skill = 333, label = "Enchanting" },
    { key = "engineering", stem = "engineer", skill = 202, label = "Engineering" },
    { key = "herbalism", stem = "herbal", skill = 182, label = "Herbalism" },
    { key = "leatherworking", stem = "leatherwork", skill = 165, label = "Leatherworking" },
    { key = "mining", stem = "mining", skill = 186, label = "Mining" },
    { key = "skinning", stem = "skinn", skill = 393, label = "Skinning" },
    { key = "tailoring", stem = "tailor", skill = 197, label = "Tailoring" },
    { key = "cooking", stem = "cook", skill = 185, label = "Cooking" },
    { key = "firstaid", stem = "first aid", skill = 129, label = "First Aid" },
    { key = "fishing", stem = "fish", skill = 356, label = "Fishing" },
    { key = "DRUID", stem = "druid", class = true, label = "Druid" },
    { key = "HUNTER", stem = "hunter", class = true, label = "Hunter" },
    { key = "MAGE", stem = "mage", class = true, label = "Mage" },
    { key = "PALADIN", stem = "paladin", class = true, label = "Paladin" },
    { key = "PRIEST", stem = "priest", class = true, label = "Priest" },
    { key = "ROGUE", stem = "rogue", class = true, label = "Rogue" },
    { key = "SHAMAN", stem = "shaman", class = true, label = "Shaman" },
    { key = "WARLOCK", stem = "warlock", class = true, label = "Warlock" },
    { key = "WARRIOR", stem = "warrior", class = true, label = "Warrior" },
}
local TRAINER_WORDS = { "trainer", "instructor", "teacher" }
local byKey = {}
for _, kind in ipairs(I.KINDS) do byKey[kind.key] = kind end
I.byKey = byKey

local entries, state, token = {}, "idle", 0
I.revision = 0

-- Which kind of trainer a title describes ("Mining Trainer" -> mining), or nil for anything else.
function I.kindOf(title)
    local t = lower(title)
    local trains = false
    for _, word in ipairs(TRAINER_WORDS) do if string.find(t, word, 1, true) then trains = true; break end end
    if not trains then return nil end
    for _, kind in ipairs(I.KINDS) do
        if string.find(t, kind.stem, 1, true) then return kind end
    end
end

function I.state() return state end
function I.entries() return entries end

local function scan()
    local ids = Q.ids("npc") or {}
    local mine = token
    for i, id in ipairs(ids) do
        local title = Q.get("npc", id, "subName")
        if type(title) == "string" then
            local kind = I.kindOf(title)
            if kind then
                entries[#entries + 1] = { id = id, name = Q.get("npc", id, "name") or "Trainer", title = title,
                    kind = kind.key, friendly = Q.get("npc", id, "friendlyToFaction"), spawns = Q.spawnList("npc", id) }
            end
        end
        if i % 400 == 0 then Work.yield(); if mine ~= token then return end end
    end
end

local function visible()
    local wm = WorldMapFrame
    return ns.db.enabled and ns.db.myTrainers and wm and call(wm.IsShown, wm)
end

-- Start (or continue) the index; call while a zone or continent map is open.
function I.start()
    if state == "done" or state == "unavailable" then return end
    if not (Q and Q.canEnumerate and Q.canEnumerate("npc")) then state = "unavailable"; return end
    if Work.busy("trainer-index") then Work.resume("trainer-index"); return end
    state, entries, token = "running", {}, token + 1
    local mine = token
    Work.start("trainer-index", scan, function() return mine == token and visible() end, function(ok)
        if mine ~= token then return end
        state = ok and "done" or "failed"
        I.revision = I.revision + 1
        if ns.travelMap then ns.travelMap.refresh() end
    end, nil, "idle")
end

function I.pause() if state == "running" then Work.pause("trainer-index") end end

-- The ranks the player has, by profession key. The skill-line API is tried first; older clients are read by name.
local function professions()
    local have = {}
    local ids = {}
    for _, kind in ipairs(I.KINDS) do if kind.skill then ids[kind.skill] = kind.key end end
    local ranks = ns.compat and ns.compat.plannerSkills and ns.compat.plannerSkills(ids) or {}
    local viaIds = false
    for skill, rank in pairs(ranks) do
        if rank > 0 and ids[skill] then have[ids[skill]] = true; viaIds = true end
    end
    if not viaIds and GetNumSkillLines and GetSkillLineInfo then
        for i = 1, (call(GetNumSkillLines) or 0) do
            local name, header, _, rank = call(GetSkillLineInfo, i)
            if name and not header and (tonumber(rank) or 0) > 0 then
                local t = lower(name)
                for _, kind in ipairs(I.KINDS) do
                    if kind.skill and string.find(t, kind.stem, 1, true) then have[kind.key] = true end
                end
            end
        end
    end
    return have
end

-- { [key] = true } for the player's class and professions, plus a stable string of them for change checks
function I.known()
    local have = professions()
    local _, class = call(UnitClass, "player")
    if class then have[class] = true end
    local keys = {}
    for key in pairs(have) do keys[#keys + 1] = key end
    table.sort(keys)
    return have, table.concat(keys, ",")
end

-- false only for an NPC that is friendly to the other faction alone
function I.usable(entry, faction)
    local f = entry.friendly
    if not faction or type(f) ~= "string" or f == "" then return true end
    return string.find(f, faction, 1, true) ~= nil
end

function I.faction()
    local group = call(UnitFactionGroup, "player")
    return (group == "Alliance" and "A") or (group == "Horde" and "H") or nil
end

function I._reset() Work.cancel("trainer-index"); entries, state, token = {}, "idle", token + 1 end
