-- Track.lua: keeps the quest tracker (the list on the right) filled with the quests closest to you.
--
--   distance mode  re-ranks the quests every 2 seconds while you move (needs a client that can tell
--                  how far a quest is); the closest N are tracked
--   zone mode      works everywhere: tracks the quests of the zone you are standing in
--
-- Off by default. While it is on it manages the whole tracker list; turning it off puts your old
-- list back. It never fights you: if you change the tracker yourself it steps aside for 10 seconds (a setting).
local ADDON, ns = ...
local C = ns.compat

local INTERVAL = 2          -- seconds between two looks
local STICKY = 0.6          -- a quest that is already tracked counts as this much of its real squared distance
local function PAUSE() return (ns.db and ns.db.nearPause) or 10 end      -- seconds to leave the tracker alone after you changed it yourself

local state = { pinned = nil, pinSaved = nil, pinSeen = nil, pinPausedUntil = 0, active = false, expected = nil, sig = nil, pausedUntil = 0, ownChange = -100, lastAccept = -100, ticker = nil, soon = nil }

local dcache = {}             -- each quest's distance, measured once per look (the tracker and the pin share it)
local function distOf(e)
    local v = dcache[e.questID]
    if v == nil then v = C.distanceSq(e) or false; dcache[e.questID] = v end
    return v or nil
end

local evaluatePin          -- defined further down (the pin); declared here because nearEvaluate calls it

local function mode()
    local m = ns.db.nearMode
    if m == "distance" or m == "auto" then return C.hasDistance() and "distance" or "zone" end
    return "zone"
end
ns.nearMode = mode

-- "paused because you changed it" is said once per session: after that you know, and it would only be noise
local told = {}
ns.pauseCounts = { tracker = 0, pin = 0 }
function ns.notePause(what)
    ns.pauseCounts[what] = (ns.pauseCounts[what] or 0) + 1
    if told[what] then return end
    told[what] = true
    if what == "pin" then
        ns.print(string.format("pin: paused for %d seconds because you chose another quest (/qs near resume to continue). This is said once.", PAUSE()))
    else
        ns.print(string.format("tracker follows you: paused for %d seconds because you changed the tracker (/qs near resume to continue). This is said once.", PAUSE()))
    end
end

local function chooseDistance(entries, current, n)
    local ranked = {}
    for _, e in ipairs(entries) do
        local d = distOf(e)
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
    if not (d.near and state.active and C.canWatch()) then return end      -- 'active' = the startup snapshot is done
    if InCombatLockdown and InCombatLockdown() then return end
    if IsInInstance and IsInInstance() then return end
    local entries = C.entries()
    dcache = {}
    evaluatePin(entries, force)                                            -- the pin has its own pause
    if GetTime() < state.pausedUntil then return end
    if state.pausedUntil > 0 and state.expected == nil and GetTime() >= state.pausedUntil then state.pausedUntil = 0 end
    local current = C.watchedSet(entries)
    local now = GetTime()
    if state.expected then
        if now - state.lastAccept < 10 then
            state.expected = nil                                   -- the game tracks a new quest by itself: accept that
        else
            local inLog, changed = {}, false
            for _, e in ipairs(entries) do inLog[e.questID] = true end
            for id in pairs(current) do if not state.expected[id] then changed = true end end
            for id in pairs(state.expected) do if inLog[id] and not current[id] then changed = true end end
            if changed then                                        -- someone else changed the tracker: you did
                state.pausedUntil, state.expected, state.sig = now + PAUSE(), nil, nil
                ns.notePause("tracker")
                return
            end
        end
    end
    local n = math.max(1, math.min(d.nearCount or 5, C.maxWatch()))
    local chosen = (mode() == "distance") and chooseDistance(entries, current, n) or chooseZone(entries, current, n)

    local add, remove = {}, {}
    for id, e in pairs(chosen) do if not current[id] then add[#add + 1] = e end end
    for id in pairs(current) do if not chosen[id] then remove[#remove + 1] = id end end
    local function remember(set)
        state.expected = {}
        for id in pairs(set) do state.expected[id] = true end
    end
    if #add == 0 and #remove == 0 then state.sig = nil; remember(current); return end

    local sig = signature(add, remove)
    if not force and state.sig ~= sig then state.sig = sig; remember(current); return end
    state.sig = nil
    local wanted = {}
    for id in pairs(chosen) do wanted[id] = true end
    apply(wanted, current, byIdMap(entries))
    remember(wanted)
end

-- Pinning the nearest quest as the game's own highlighted quest (the waypoint marker in the world) -----------
function ns.canPin()
    return (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID) and true or false
end

evaluatePin = function(entries, force)
    local d = ns.db
    if not (d.nearPin and ns.canPin() and mode() == "distance") then return end
    local now = GetTime()
    if now < state.pinPausedUntil then return end
    local cur = C_SuperTrack.GetSuperTrackedQuestID() or 0
    if state.pinned and cur ~= state.pinned then
        if now - state.lastAccept < 10 then
            state.pinned = nil                                    -- the game pins a quest you just accepted: that is fine
        else
            state.pinPausedUntil, state.pinned, state.pinSeen = now + PAUSE(), nil, nil
            ns.notePause("pin")
            return
        end
    end
    -- in a party, the quest you do TOGETHER comes first: the nearest one somebody else also has; otherwise the nearest
    local best, bestD, shared, sharedD
    local grouped = C.inGroup()
    for _, e in ipairs(entries) do
        local dist = distOf(e)
        if dist then
            if e.questID == cur and state.pinned == cur then dist = dist * STICKY end      -- hysteresis
            if not best or dist < bestD or (dist == bestD and e.questID < best.questID) then best, bestD = e, dist end
            if grouped and not C.doneByMe(e) and #ns.partyHas(e) > 0 and (not shared or dist < sharedD) then shared, sharedD = e, dist end
        end
    end
    if shared then best, bestD = shared, sharedD end
    if not best or best.questID == cur then
        state.pinSeen = nil
        if best then state.pinned = cur end
        return
    end
    if not force and state.pinSeen ~= best.questID then state.pinSeen = best.questID; return end    -- seen twice in a row
    state.pinSeen = nil
    if state.pinSaved == nil then state.pinSaved = cur end
    if pcall(C_SuperTrack.SetSuperTrackedQuestID, best.questID) then state.pinned = best.questID end
end

-- you chose a quest yourself (the menu's "Focus it on my map"): the "nearest quest" pin leaves it alone for a while
function ns.pinPauseFor(seconds)
    state.pinPausedUntil, state.pinned, state.pinSeen = GetTime() + seconds, nil, nil
end

-- give the game's highlighted quest back to whatever it was before we started pinning
function ns.releasePin()
    if ns.canPin() and state.pinned and (C_SuperTrack.GetSuperTrackedQuestID() or 0) == state.pinned
       and state.pinSaved and state.pinSaved ~= 0 then
        pcall(C_SuperTrack.SetSuperTrackedQuestID, state.pinSaved)
    end
    state.pinned, state.pinSaved, state.pinSeen, state.pinPausedUntil = nil, nil, nil, 0
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
        local already = d.near and d.nearSaved                    -- already running: keep the ORIGINAL list to restore
        d.near = true
        if not already then
            local saved = {}
            for id in pairs(C.watchedSet()) do saved[#saved + 1] = id end
            d.nearSaved = saved                                  -- what to put back when switched off
        end
        state.pausedUntil, state.sig, state.expected = 0, nil, nil
        state.active = true
        ns.nearEvaluate(true)
        startTicker()
        ns.print(string.format("tracker follows you: %s mode, %d quest(s). /qs near off puts your old list back (%s)",
            mode(), math.min(d.nearCount or 5, C.maxWatch()),
            mode() == "zone" and (C.hasDistance() and "zone mode was asked for" or "this client cannot measure distance, so it uses the quests of your zone") or "distance mode"))
        if ns.refreshSettings then ns.refreshSettings() end
    else
        d.near = false
        state.active = false
        ns.releasePin()
        stopTicker()
        if ns.refreshSettings then ns.refreshSettings() end
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
        ns.setSetting("nearCount", math.max(1, math.min(math.floor(n), C.maxWatch())))
        ns.print("the tracker keeps " .. d.nearCount .. " quest(s)")
    elseif arg == "now" then
        state.pausedUntil, state.expected = 0, nil
        ns.nearEvaluate(true)
    elseif arg == "resume" then
        state.pausedUntil, state.expected, state.pinPausedUntil = 0, nil, 0
        ns.print("tracker follows you: resumed")
        ns.nearEvaluate(true)
    elseif string.match(arg, "^mode") then
        local m = string.match(arg, "^mode%s+(%a+)")
        if m == "auto" or m == "distance" or m == "zone" then
            ns.setSetting("nearMode", m)
            ns.print("mode: " .. m .. " (in use: " .. mode() .. ")")
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
    state.pausedUntil, state.expected = now + PAUSE(), nil
    ns.notePause("tracker")
end)

-- "near" is on by default: after the loading screen (the quest log needs a moment), remember the player's own
-- list once, then start following
ns.on("PLAYER_ENTERING_WORLD", function()
    if not ns.db.near then return end
    ns.after(5, function()
        if not (ns.db.near and C.canWatch()) then return end
        if ns.db.nearSaved == nil then
            local saved = {}
            for id in pairs(C.watchedSet()) do saved[#saved + 1] = id end
            ns.db.nearSaved = saved
        end
        state.active = true
        ns.nearEvaluate(true)
        startTicker()
    end)
end)
