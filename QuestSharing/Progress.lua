-- Progress.lua: notices when the objectives of one of your quests are all done, tells the party
-- when that quest is shared, and keeps synced players up to date about changes in your quest log.
local ADDON, ns = ...
local C = ns.compat

local ICON = "{rt1}"
local LINES = { "I'm done with this one, ready to turn in!",
                "Finished the objectives here, ready to hand it in :)" }

local baseline            -- what the quest log looked like last time; nil until the first look
local pending

local function snapshot()
    local snap = {}
    for _, e in ipairs(C.entries()) do
        snap[e.questID] = { entry = e, complete = e.complete, code = ns.encodeEntry(e) }
    end
    return snap
end

function ns.onQuestCompleted(e)
    ns.syncUpdate("C|" .. e.questID)
    local names = ns.partyHas(e)
    if #names > 0 and ns.db.announce then
        ns.say(string.format("%s %s - %s", ICON, C.link(e), ns.pick(LINES)))
    end
end

local function check()
    pending = nil
    local snap = snapshot()
    if baseline then
        for id, cur in pairs(snap) do
            local old = baseline[id]
            if not old then
                ns.syncUpdate("P|" .. cur.code)                            -- a quest we just accepted
            elseif old.code ~= cur.code then
                ns.syncUpdate("P|" .. cur.code)
                if cur.complete and not old.complete then ns.onQuestCompleted(cur.entry) end
            end
        end
        for id in pairs(baseline) do
            if not snap[id] then ns.syncUpdate("R|" .. id) end            -- abandoned or turned in
        end
    end
    baseline = snap
    if ns.refreshPanel then ns.refreshPanel() end
end

-- the quest log fires many events in a burst: look once, shortly after
function ns.questLogChanged()
    if not pending then pending = ns.after(1.5, check) end
end

for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED",
                         "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
    ns.on(event, ns.questLogChanged)
end

-- the first look (no announcements) happens a moment after the loading screen
ns.on("PLAYER_ENTERING_WORLD", function() ns.after(3, check) end)
