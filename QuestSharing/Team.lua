-- Team.lua: "Picked up [Wolves Among Us] - Anna has it too. Want to do it together?"
-- Said once per quest per party, when you take a quest from a quest giver and someone in the party already has it.
-- Never for a quest somebody shared with you (they know), never twice, and several quests picked up at one quest giver
-- go into one message. It also counts against the budget of automatic messages (Core.lua: at most 4 a minute).
local ADDON, ns = ...
local C = ns.compat

local LINES = { "Picked up %s - %s %s %s too. Want to do %s together?",
                "Just got %s - %s %s %s too. Shall we do %s together?" }
local WINDOW = 120            -- a quest accepted this soon after a share window / an offer counts as shared
local MAX_LINKS = 3

local fromShare = { at = -1000 }   -- when a quest window was opened by a player (a shared quest), not by a quest giver
ns.offeredBy = {}                  -- ns.offeredBy[questID] = time another Quest Sharing user offered it to the party
local said = {}                    -- quests already mentioned this way in this party
local batch, timer = {}, nil

ns.on("QUEST_DETAIL", function()
    if UnitExists and UnitExists("questnpc") and UnitIsPlayer and UnitIsPlayer("questnpc") then
        fromShare = { name = UnitName("questnpc"), at = GetTime() }
    end
end)
-- the window closed without an accept: forget it (the accept itself can arrive a moment after the window closes)
ns.on("QUEST_FINISHED", function()
    local at = fromShare.at
    ns.after(3, function() if fromShare.at == at then fromShare = { at = -1000 } end end)
end)

local function cameFromShare(id)
    local now = GetTime()
    if ns.offeredBy[id] and now - ns.offeredBy[id] < WINDOW then return true end
    if now - fromShare.at < WINDOW then fromShare = { at = -1000 }; return true end
    return false
end

local function joinNames(list)
    table.sort(list)
    if #list == 1 then return list[1] end
    if #list > 3 then return "some of you" end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

local function flush()
    timer = nil
    local ids = batch
    batch = {}
    local d = ns.db
    if not (d.enabled and d.pickup and C.inGroup() and not C.inRaid()) then return end
    local links, names, seen = {}, {}, {}
    for _, id in ipairs(ids) do
        local e = C.findEntry(id)
        if e and not said[id] and not (ns.saidLately and ns.saidLately(id)) then
            local with = ns.partyHas(e)
            if #with > 0 and #links < MAX_LINKS then
                said[id] = true
                links[#links + 1] = C.link(e)
                for _, n in ipairs(with) do if not seen[n] then seen[n] = true; names[#names + 1] = n end end
            end
        end
    end
    if #links == 0 then return end
    local it = (#links == 1) and "it" or "them"
    local has = (#names == 1) and "has" or "have"
    local msg = string.format(ns.pick(LINES), table.concat(links, ", "), joinNames(names), has, it, it)
    ns.say(C.safeCut(msg, 255), true)
end

function ns.onPickedUp(id)
    if not id or cameFromShare(id) then return end
    batch[#batch + 1] = id
    if not timer then timer = ns.after(3, flush) end
end

-- classic: QUEST_ACCEPTED(logIndex, questID), modern: QUEST_ACCEPTED(questID)
ns.on("QUEST_ACCEPTED", function(_, first, second) ns.onPickedUp(second or first) end)

local function onRoster() if not C.inGroup() then said = {} end end
ns.on("GROUP_ROSTER_UPDATE", onRoster)
ns.on("GROUP_JOINED", onRoster)
ns.on("PARTY_MEMBERS_CHANGED", onRoster)
