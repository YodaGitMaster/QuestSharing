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

function W.start(owner, run, valid, finished)
    W.cancel(owner)
    local job = { owner = owner, thread = coroutine.create(run), valid = valid, finished = finished }
    jobs[owner] = job
    queue[#queue + 1] = job
    wake()
end

wake = function()
    if not timer and #queue > 0 and not fighting() then timer = ns.after(INTERVAL, pump) end
end

pump = function()
    timer = nil
    if fighting() then return end -- PLAYER_REGEN_ENABLED wakes work; no combat polling timer.
    local started, steps = clock(), 0
    local limit = started and 2000 or MAX_STEPS
    while #queue > 0 and steps < limit do
        local now = started and clock()
        if now and now - started >= BUDGET_MS then break end
        local job = table.remove(queue, 1)
        if jobs[job.owner] == job then
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
    wake()
end

ns.on("PLAYER_REGEN_ENABLED", wake)
