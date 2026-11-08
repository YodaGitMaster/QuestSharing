-- Track.lua: keeps the quest tracker (the list on the right) filled with the quests closest to you.
--
--   distance mode  re-ranks the quests every 2 seconds while you move (needs a client that can tell
--                  how far a quest is); the closest N are tracked
--   zone mode      works everywhere: tracks the quests of the zone you are standing in
--
-- Off by default. While it is on it manages the whole tracker list; turning it off puts your old
-- list back. It never fights you: if you change the tracker yourself it pauses for 5 minutes.
local ADDON, ns = ...
local C = ns.compat

local INTERVAL = 2          -- seconds between two looks
local STICKY = 0.6          -- a quest that is already tracked counts as this much of its real squared distance
local PAUSE = 300           -- seconds to leave the tracker alone after you changed it yourself

local state = { sig = nil, pausedUntil = 0, ownChange = -100, lastAccept = -100, ticker = nil, soon = nil }

local function mode()
    local m = ns.db.nearMode
    if m == "distance" or m == "auto" then return C.hasDistance() and "distance" or "zone" end
    return "zone"
end
ns.nearMode = mode

local function chooseDistance(entries, current, n)
    local ranked = {}
    for _, e in ipairs(entries) do
        local d = C.distanceSq(e)
        if d then
            if current[e.questID] then d = d * STICKY end        -- hysteresis: do not swap for a small gain
            ranked[#ranked + 1] = { e = e, d = d }
        end
    end
    table.sort(ranked, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.e.questID < b.e.questID
    end)
    local chosen = {}
    for i = 1, math.min(n, #ranked) do chosen[ranked[i].e.questID] = ranked[i].e end
    return chosen
end

local function chooseZone(entries, current, n)
    local inZone = {}
    for _, e in ipairs(entries) do if C.inArea(e) then inZone[#inZone + 1] = e end end
    table.sort(inZone, function(a, b)                            -- already tracked first, then unfinished, then log order
        local ca, cb = current[a.questID] and 0 or 1, current[b.questID] and 0 or 1
        if ca ~= cb then return ca < cb end
        if a.complete ~= b.complete then return not a.complete end
        return a.index < b.index
    end)
    local chosen = {}
    for i = 1, math.min(n, #inZone) do chosen[inZone[i].questID] = inZone[i] end
    return chosen
end

local function signature(add, remove)
    local a, r = {}, {}
    for _, e in ipairs(add) do a[#a + 1] = e.questID end
    for _, id in ipairs(remove) do r[#r + 1] = id end
    table.sort(a); table.sort(r)
    return table.concat(a, ",") .. "/" .. table.concat(r, ",")
end

-- set the tracker to `wanted` (a set of questIDs): remove first to free slots, then add
local function apply(wanted, current, byId)
    state.ownChange = GetTime()
    for id in pairs(current) do
        if not wanted[id] and byId[id] then C.setWatched(byId[id], false) end
    end
    for id in pairs(wanted) do
        if not current[id] and byId[id] then C.setWatched(byId[id], true) end
    end
end

local function byIdMap(entries)
    local m = {}
    for _, e in ipairs(entries) do m[e.questID] = e end
    return m
end

-- force = act now (switching on, zone change, quest accepted); otherwise a change must be seen twice in a
-- row, so a short detour does not reshuffle the list
function ns.nearEvaluate(force)
    local d = ns.db
    if not (d.near and C.canWatch()) then return end
    if GetTime() < state.pausedUntil then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if IsInInstance and IsInInstance() then return end
    local entries = C.entries()
    local current = C.watchedSet()
    local n = math.max(1, math.min(d.nearCount or 5, C.maxWatch()))
    local chosen = (mode() == "distance") and chooseDistance(entries, current, n) or chooseZone(entries, current, n)

    local add, remove = {}, {}
    for id, e in pairs(chosen) do if not current[id] then add[#add + 1] = e end end
    for id in pairs(current) do if not chosen[id] then remove[#remove + 1] = id end end
    if #add == 0 and #remove == 0 then state.sig = nil; return end

    local sig = signature(add, remove)
    if not force and state.sig ~= sig then state.sig = sig; return end
    state.sig = nil
    local wanted = {}
    for id in pairs(chosen) do wanted[id] = true end
    apply(wanted, current, byIdMap(entries))
end

-- On / off ---------------------------------------------------------------------------------------------
local function tick()
    state.ticker = nil
    if not ns.db.near then return end
    ns.nearEvaluate(false)
    state.ticker = ns.after(INTERVAL, tick)
end

local function startTicker()
    if not state.ticker then state.ticker = ns.after(INTERVAL, tick) end
end

local function stopTicker()
    if state.ticker then ns.cancel(state.ticker); state.ticker = nil end
end

function ns.setNear(on)
    local d = ns.db
    if on and not C.canWatch() then
        d.near = false
        return ns.print("this client has no calls to change the quest tracker, so this feature is not available")
    end
    if on then
        d.near = true
        d.nearSaved = d.nearSaved or {}
        local saved = {}
        for id in pairs(C.watchedSet()) do saved[#saved + 1] = id end
        d.nearSaved = saved                                      -- what to put back when switched off
        state.pausedUntil, state.sig = 0, nil
        ns.nearEvaluate(true)
        startTicker()
        ns.print(string.format("tracker follows you: %s mode, %d quest(s). /qs near off puts your old list back (%s)",
            mode(), math.min(d.nearCount or 5, C.maxWatch()),
            mode() == "zone" and (C.hasDistance() and "zone mode was asked for" or "this client cannot measure distance, so it uses the quests of your zone") or "distance mode"))
    else
        d.near = false
        stopTicker()
        local entries = C.entries()
        local wanted = {}
        for _, id in ipairs(d.nearSaved or {}) do wanted[id] = true end
        if d.nearSaved then apply(wanted, C.watchedSet(), byIdMap(entries)) end
        d.nearSaved = nil
        ns.print("tracker follows you: off" .. (d.nearSaved == nil and ", your earlier list is back" or ""))
    end
end

-- /qs near ...
function ns.nearCommand(arg)
    local d = ns.db
    arg = string.lower(arg or "")
    local n = tonumber(arg)
    if arg == "" then ns.setNear(not d.near)
    elseif arg == "on" then ns.setNear(true)
    elseif arg == "off" then ns.setNear(false)
    elseif n then
        d.nearCount = math.max(1, math.min(math.floor(n), C.maxWatch()))
        ns.print("the tracker keeps " .. d.nearCount .. " quest(s)")
        if d.near then ns.nearEvaluate(true) end
    elseif arg == "now" then
        state.pausedUntil = 0
        ns.nearEvaluate(true)
    elseif arg == "resume" then
        state.pausedUntil = 0
        ns.print("tracker follows you: resumed")
        ns.nearEvaluate(true)
    elseif string.match(arg, "^mode") then
        local m = string.match(arg, "^mode%s+(%a+)")
        if m == "auto" or m == "distance" or m == "zone" then
            d.nearMode = m
            ns.print("mode: " .. m .. " (in use: " .. mode() .. ")")
            if d.near then ns.nearEvaluate(true) end
        else
            ns.print("/qs near mode auto|distance|zone   (in use: " .. mode() .. ")")
        end
    else
        ns.print("/qs near [on|off] | N (how many quests) | mode auto|distance|zone | now | resume")
    end
end

-- Events -------------------------------------------------------------------------------------------------
local function soon()
    if state.soon then return end
    state.soon = ns.after(1, function() state.soon = nil; ns.nearEvaluate(true) end)
end

ns.on("ZONE_CHANGED_NEW_AREA", soon)
ns.on("QUEST_REMOVED", soon)
ns.on("QUEST_TURNED_IN", soon)
ns.on("QUEST_ACCEPTED", function() state.lastAccept = GetTime(); soon() end)

-- You changed the tracker yourself: stay out of the way for a while. The game also adds a quest to the
-- tracker by itself when you accept one, and our own changes fire the event too: both are ignored.
ns.on("QUEST_WATCH_LIST_CHANGED", function()
    if not ns.db.near then return end
    local now = GetTime()
    if now - state.ownChange < 3 or now - state.lastAccept < 3 then return end
    state.pausedUntil = now + PAUSE
    ns.print("tracker follows you: paused for 5 minutes because you changed the tracker (/qs near resume to continue)")
end)

ns.on("PLAYER_ENTERING_WORLD", function()
    if ns.db.near then startTicker() end
end)
