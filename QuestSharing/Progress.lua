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
        local objs = C.objectives(e)
        snap[e.questID] = { entry = e, complete = e.complete, objs = objs,
                            code = string.format("%d:%d:%s", e.questID, e.complete and 1 or 0, ns.encodeObjectives(objs)) }
    end
    return snap
end

-- Where you picked up or used quest things: the spot of the last progress on an item / object / event objective.
-- Told to the party only inside a message you send anyway (the "done" message, a quest click), and only when someone
-- in the party still needs it.
ns.spots = {}               -- ns.spots[questID] = { what, x, y, zone, at }
local PICK = { item = true, object = true, event = true }

local function noteProgress(old, cur)
    if not (old and old.objs and cur.objs) then return end
    for j, o in ipairs(cur.objs) do
        local was = old.objs[j]
        local moved = was and ((o.have and was.have and o.have > was.have) or (o.finished and not was.finished))
        if moved and PICK[o.type or ""] then
            if ns.onPickProgress then ns.onPickProgress(cur.entry.questID) end   -- you picked up / used one
            local map, x, y = C.playerPos()
            if x then ns.spots[cur.entry.questID] = { what = o.name or o.text, map = map, x = x, y = y, zone = C.zone(), at = GetTime() } end
        end
    end
end

-- does anybody in the party still work on this quest? (synced players who finished it do not)
function ns.someoneStillNeeds(e)
    for _, name in ipairs(ns.partyHas(e)) do
        local peer = ns.peers[ns.memberKey(name)]
        local rec = peer and peer.quests and peer.quests[e.questID]
        if not (rec and rec.complete) then return true end
    end
    return false
end

-- " (Wolf Pelt at 42.3, 61.8)", or "" when there is nothing useful to add (for the question you ask the party)
function ns.spotShort(e)
    if not ns.db.coords then return "" end
    local s = ns.spots[e.questID]
    if not s or not ns.someoneStillNeeds(e) then return "" end
    return string.format(" (%s at %.1f, %.1f)", s.what, s.x * 100, s.y * 100)
end

-- " - Wolf Pelt: 42.3, 61.8 in Elwynn Forest", or "" when there is nothing useful to add
function ns.spotText(e)
    if not ns.db.coords then return "" end
    local s = ns.spots[e.questID]
    if not s or not ns.someoneStillNeeds(e) then return "" end
    return string.format(" - %s: %.1f, %.1f in %s", s.what, s.x * 100, s.y * 100, s.zone ~= "" and s.zone or "this zone")
end

-- someone else just said this quest is done (a Quest Sharing user finished it, or a link of it in party chat)
local function alreadySaid(id)
    local t = ns.recentDone and ns.recentDone[id]
    return (t and GetTime() - t < 30) or (ns.saidLately and ns.recentlySaid[id] and GetTime() - ns.recentlySaid[id] < 30)
end

function ns.onQuestCompleted(e)
    ns.syncUpdate("C|" .. e.questID)
    if not (ns.db.announce and #ns.partyHas(e) > 0) then return end
    -- finishing together is common (the last kill counts for everybody): only the first one says it
    ns.after(ns.turnDelay and ns.turnDelay() or 0, function()
        if alreadySaid(e.questID) or not C.inGroup() then return end
        ns.say(string.format("%s %s - %s%s", ICON, C.link(e), ns.pick(LINES), ns.spotText(e)))
    end)
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
                noteProgress(old, cur)
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
