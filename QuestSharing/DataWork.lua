-- Cooperative guide/map database work: one small shared slice, and nothing polls when idle.
local ADDON, ns = ...
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

ns.on("PLAYER_REGEN_ENABLED", wake)
