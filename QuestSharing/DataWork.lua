-- Cooperative guide/map database work: one small shared slice, and nothing polls when idle.
local ADDON, ns = ...
ns.inModule(nil)          -- core: always on (Modules.lua)
local W, jobs, queue, timer, running = {}, {}, {}, nil, nil
ns.dataWork = W
local BUDGET_MS, MAX_STEPS, INTERVAL = 2, 80, 0.1
local pump, wake

local function clock()
    if type(debugprofilestop) ~= "function" then return nil end
    return debugprofilestop()
end

local function fighting()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

function W.cancel(owner)
    jobs[owner] = nil
    for i = #queue, 1, -1 do if queue[i].owner == owner then table.remove(queue, i) end end
    if #queue == 0 and timer then ns.cancel(timer); timer = nil end
end

function W.pause(owner)
    local job = jobs[owner]
    if not job then return end
    job.paused = true
    for i = #queue, 1, -1 do if queue[i] == job then table.remove(queue, i) end end
    if #queue == 0 and timer then ns.cancel(timer); timer = nil end
end

function W.resume(owner)
    local job = jobs[owner]
    if job and job.paused then job.paused = false; queue[#queue + 1] = job end
    wake()
end

function W.busy(owner) return jobs[owner] ~= nil end
-- true while combat holds every job back (a window can say "waits until the fight ends" instead of a frozen count)
function W.fighting() return fighting() and true or false end
function W.yield() coroutine.yield() end
function W.checkpoint()
    if running and coroutine.running() == running then coroutine.yield() end
end

-- budget (ms, optional): a larger slice for a visible window the player is waiting on. Background jobs keep BUDGET_MS.
-- priority (optional): "idle" resumes the job only while no other job can run (queued, not paused, valid).
function W.start(owner, run, valid, finished, budget, priority)
    W.cancel(owner)
    local job = { owner = owner, thread = coroutine.create(run), valid = valid, finished = finished,
        budget = type(budget) == "number" and budget > BUDGET_MS and budget or nil, idle = priority == "idle" }
    jobs[owner] = job
    queue[#queue + 1] = job
    wake()
end

wake = function()
    if not timer and #queue > 0 and not fighting() then timer = ns.after(INTERVAL, pump) end
end

-- A job that is not idle and could run now: still current, not paused and valid.
local function canRun(list)
    for _, job in ipairs(list) do
        if not job.idle and jobs[job.owner] == job and not job.paused and not (job.valid and not job.valid()) then
            return true
        end
    end
    return false
end

local function requeue(list)
    for _, job in ipairs(list) do if jobs[job.owner] == job and not job.paused then queue[#queue + 1] = job end end
end

pump = function()
    timer = nil
    if fighting() then return end -- PLAYER_REGEN_ENABLED wakes work; no combat polling timer.
    local started, steps = clock(), 0
    local deferred, waiting = {}, {}
    -- Idle jobs wait while another job can run; once the others finish or pause they get the rest of the slice.
    while #queue > 0 or (#waiting > 0 and not canRun(deferred)) do
        if #queue == 0 then requeue(waiting); waiting = {} end
        local job = table.remove(queue, 1)
        if not job then break end -- every waiting idle job was paused or cancelled meanwhile
        -- Each job may run only while the slice is within its own budget; a job past it waits for the next slice.
        local scale = (job.budget or BUDGET_MS) / BUDGET_MS
        local within = started and (steps < 2000 * scale and clock() - started < BUDGET_MS * scale)
            or (not started and steps < MAX_STEPS * scale)
        if not within then
            deferred[#deferred + 1] = job
        elseif job.idle and (canRun(queue) or canRun(deferred)) then
            waiting[#waiting + 1] = job
        elseif jobs[job.owner] == job then
            if job.valid and not job.valid() then
                job.paused = true
            else
                steps = steps + 1
                running = job.thread
                local ok, err = coroutine.resume(job.thread)
                running = nil
                if not ok or coroutine.status(job.thread) == "dead" then
                    if jobs[job.owner] == job then
                        jobs[job.owner] = nil
                        if job.finished then job.finished(ok, err) end
                    end
                    if not ok then ns.print("optional data task failed: " .. tostring(err)) end
                elseif jobs[job.owner] == job and not job.paused then
                    queue[#queue + 1] = job
                end
            end
        end
    end
    for _, job in ipairs(deferred) do queue[#queue + 1] = job end
    requeue(waiting)
    wake()
end

-- Memory: a catalogue built for a window stays for a short grace period after it closes (reopening is instant), then
-- fn() frees it. keep(owner) cancels the pending release. One timer per owner.
local releases = {}
function W.keep(owner)
    local t = releases[owner]
    if t then ns.cancel(t); releases[owner] = nil end
end

function W.releaseLater(owner, seconds, fn)
    W.keep(owner)
    releases[owner] = ns.after(seconds, function()
        releases[owner] = nil
        fn()
    end)
end

function W.releasePending(owner) return releases[owner] ~= nil end

-- Catalogues read from QuestieDB are kept for the session; one Purge (Settings, /qs memory purge) frees them all.
-- Each module registers a free function; W.purge() runs every one and returns how many ran.
local purgers = {}
function W.onPurge(name, fn) purgers[#purgers + 1] = { name = name, fn = fn } end
-- Saved ID lists (SavedVariables QuestSharingCache): a catalogue saves only which IDs its full QuestieDB scan kept, so
-- the next session reads just those records. Every list is dropped when the game build or the Quest Sharing, Questie
-- or QuestieDB version changes (W.stamp), and by Purge. A list is any table of plain values (IDs, numbers, strings).
local DB_ADDONS = { ADDON, "Questie", "QuestieDB", "Questie-DB", "!Questie" }
local function version(name)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if type(get) ~= "function" then return "" end
    local ok, v = pcall(get, name, "Version")
    return ok and type(v) == "string" and v or ""
end
function W.stamp()
    local parts = { type(GetBuildInfo) == "function" and tostring((select(2, GetBuildInfo()))) or "" }
    for _, name in ipairs(DB_ADDONS) do parts[#parts + 1] = version(name) end
    return table.concat(parts, "|")
end
local checked = false
local function lists()
    if type(QuestSharingCache) ~= "table" then QuestSharingCache = {} end
    if not checked then
        checked = true
        local stamp = W.stamp()
        if QuestSharingCache.stamp ~= stamp or type(QuestSharingCache.lists) ~= "table" then
            QuestSharingCache = { stamp = stamp, lists = {} }
        end
    end
    return QuestSharingCache.lists
end
-- The saved list for (name, scope), or nil when there is none for this build and these versions.
function W.saved(name, scope)
    local entry = lists()[name]
    local value = type(entry) == "table" and type(entry.scopes) == "table" and entry.scopes[scope or ""]
    return type(value) == "table" and value or nil
end
-- keep (optional, default 4): how many scopes of this name are kept; the oldest saved goes first.
function W.save(name, scope, value, keep)
    scope = scope or ""
    local all = lists()
    local entry = type(all[name]) == "table" and all[name] or { scopes = {}, order = {} }
    all[name] = entry
    for i = #entry.order, 1, -1 do if entry.order[i] == scope then table.remove(entry.order, i) end end
    entry.order[#entry.order + 1], entry.scopes[scope] = scope, value
    while #entry.order > (keep or 4) do entry.scopes[table.remove(entry.order, 1)] = nil end
end
function W.forget(name) if type(QuestSharingCache) == "table" and type(QuestSharingCache.lists) == "table" then QuestSharingCache.lists[name] = nil end end
-- Sorted array of the keys of a set (a saved ID list).
function W.sortedKeys(set) local out = {}; for id in pairs(set) do out[#out + 1] = id end; table.sort(out); return out end

function W.purge()
    QuestSharingCache, checked = nil, false
    local n = 0
    for _, p in ipairs(purgers) do
        local ok, err = pcall(p.fn)
        if ok then n = n + 1 else ns.print("could not free " .. p.name .. ": " .. tostring(err)) end
    end
    return n
end
function W.purgeNames() local out = {}; for _, p in ipairs(purgers) do out[#out + 1] = p.name end; return out end

ns.on("PLAYER_REGEN_ENABLED", wake)
