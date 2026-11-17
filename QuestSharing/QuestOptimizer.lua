-- Predictive, bounded search over one zone's atomic actions. Coordinates and costs describe
-- player instructions only; the simulator never updates the real quest log or inventory.
local _, ns = ...
local O = {}
ns.questOptimizer = O

local function finite(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

local function number(value, fallback)
    return finite(value) and value or fallback
end

-- At kill k, outstanding drops r-X (where X ~ Binomial(k,p)) cost (r-X)/p extra
-- kills on average. Summing these nonnegative tails also handles probabilities near 1.
local function jointKills(k, r, p)
    if r == 0 then return k end
    if k == 0 then return r / p end
    if p == 1 then return math.max(k, r) end
    local logFailure = math.log(1 - p)
    local logOdds, logProb, tail = math.log(p) - logFailure, k * logFailure, 0
    for i = 0, math.min(r - 1, k) do
        tail = tail + (r - i) * math.exp(logProb)
        if i < k then logProb = logProb + math.log((k - i) / (i + 1)) + logOdds end
    end
    return math.max(k, r / p, k + tail / p)
end

local function idSet(values)
    local result = {}
    for key, value in pairs(values or {}) do
        local id = value == true and key or value
        if type(id) == "number" then result[id] = true end
    end
    return result
end

local function campKey(point, npc)
    if not point or not npc or not finite(point.x) or not finite(point.y) then return nil end
    return table.concat({ tostring(point.map), string.format("%.7f", point.x),
        string.format("%.7f", point.y), tostring(npc) }, "/")
end

local function farmAt(stop, point, npc)
    local rows = stop.objectives
    if stop.kind ~= "objective" or not rows or #rows ~= 1 then return end
    local row, target = rows[1], rows[1].target or {}
    if target.kind ~= "kill" and target.kind ~= "loot" then return end
    local remaining = row.remaining
    if remaining == nil then
        local required = target.required or target.count or target.need
        if finite(required) then remaining = math.max(0, required - number(target.have, 0)) end
    end
    if not finite(remaining) or remaining ~= math.floor(remaining) then return { unknown = true } end
    if remaining == 0 then return { kills = 0, items = 0 } end
    local key = row.shareable == true and campKey(point, npc) or nil
    if target.kind == "kill" then return { key = key, kills = remaining, items = 0 } end
    local p = npc and target.dropRates and target.dropRates[npc]
    if p == nil then
        local percent = row.dropRate or target.dropRate
        if finite(percent) then p = percent / 100 end
    end
    if p == 0 then return { unavailable = true } end
    if not finite(p) or p > 1 then return { unknown = true } end
    return { key = key, kills = 0, items = remaining, p = p }
end

-- A stop can offer alternative places for the same work (other camps of the objective's creatures).
-- The search picks one per visit from its current position; the first site is the planner's default.
local MAX_SITES = 6
local function sitesFor(stop)
    local row = stop.objectives and stop.objectives[1]
    local sites, usable = { { point = stop.point, sourceID = row and row.sourceID } }, {}
    for _, alt in ipairs(stop.alternatives or {}) do
        local p = alt.point
        if #sites >= MAX_SITES then break end
        if type(p) == "table" and finite(p.x) and finite(p.y) and not (stop.point and p.map == stop.point.map and p.x == stop.point.x and p.y == stop.point.y) then
            sites[#sites + 1] = { point = p, sourceID = alt.sourceID, tasks = alt.tasks, questTasks = alt.questTasks,
                destination = alt.destination }
        end
    end
    for _, site in ipairs(sites) do
        site.farm = farmAt(stop, site.point, site.sourceID)
        if not (site.farm and site.farm.unavailable) then usable[#usable + 1] = site end
    end
    return #usable > 0 and usable or { sites[1] }
end

local function compile(quests, stops, options)
    local m = { list = {}, byID = {}, byQuest = {}, excluded = {}, groups = {}, camps = {},
        options = options, qs = quests, selected = idSet(options.selectedIDs), xp = {}, alternativeChecks = 0,
        checkpoint = options.checkpoint or (ns.dataWork and ns.dataWork.checkpoint) or function() end,
        limit = number(options.maxSearchChecks, 36000) }
    for id, q in pairs(quests) do
        m.xp[id] = number(q.xp, 0)
        for other in pairs(idSet(q.exclusiveTo or q.excludedBy)) do
            m.excluded[id] = m.excluded[id] or {}; m.excluded[id][other] = true
            m.excluded[other] = m.excluded[other] or {}; m.excluded[other][id] = true
        end
    end
    for i, stop in ipairs(stops) do
        local qid = next(stop.quests or {}) or stop.questID
        if not qid or not quests[qid] or not stop.id or m.byID[stop.id] then return end
        local d = { s = stop, id = stop.id, qid = qid, order = i, parents = {}, children = {}, sites = sitesFor(stop) }
        d.farm = d.sites[1].farm
        m.list[i], m.byID[d.id] = d, d
        local qs = m.byQuest[qid] or {}; m.byQuest[qid] = qs; qs[#qs + 1] = d
        local seen = {}
        for _, site in ipairs(d.sites) do
            local key = site.farm and site.farm.key
            if key and not seen[key] then
                seen[key] = true
                local camp = m.camps[key]
                if not camp then camp = { stops = {} }; m.groups[#m.groups + 1] = camp; m.camps[key] = camp end
                camp.stops[#camp.stops + 1] = d
            end
        end
        m.checkpoint()
    end
    for _, d in ipairs(m.list) do
        for parent in pairs(d.s.deps or {}) do
            local dep = m.byID[parent]
            if dep then
                d.parents[#d.parents + 1] = dep; dep.children[#dep.children + 1] = d
            else d.missingParent = true end
        end
    end
    local function ancestors(roots)
        local set, stack = {}, {}
        for _, d in ipairs(roots) do stack[#stack + 1] = d end
        while #stack > 0 do
            local d = table.remove(stack)
            if not set[d.id] then
                set[d.id] = true
                for _, p in ipairs(d.parents) do stack[#stack + 1] = p end
                if d.s.kind == "pickup" then
                    for _, gate in ipairs(m.qs[d.qid].gates or {}) do
                        for _, parentID in ipairs(gate.choices) do
                            for _, parentAction in ipairs(m.byQuest[parentID] or {}) do
                                stack[#stack + 1] = parentAction
                            end
                        end
                    end
                end
                m.checkpoint()
            end
        end
        return set
    end
    m.ancestors = ancestors
    if options.mode == "selected" then
        local roots = {}
        for id in pairs(m.selected) do
            for _, d in ipairs(m.byQuest[id] or {}) do roots[#roots + 1] = d end
        end
        m.allowed = ancestors(roots)
    end
    return m
end

local function travel(m, a, b)
    if not a or not b then return 0, true end
    if a == b or (a.map == b.map and a.x == b.x and a.y == b.y) then return 0, false end
    if m.options.travelSeconds then
        local t, approximate = m.options.travelSeconds(a, b)
        if finite(t) then return t, approximate end
        if t == math.huge then return math.huge end
    end
    if a.map ~= b.map or not finite(a.x) or not finite(a.y) or not finite(b.x) or not finite(b.y) then
        return math.huge
    end
    local x, y = a.x - b.x, a.y - b.y
    return math.sqrt(x * x + y * y) * 600, true
end

local function service(m, d, s, site)
    local opts, f = m.options, (site or d.sites[1]).farm
    if not f or f.unknown then
        local rows = d.s.objectives
        local explicit = number(d.s.serviceSeconds, rows and rows[1] and rows[1].seconds)
        local uncertain = f and f.unknown or false
        local fallback = uncertain and number(opts.unknownWorkSeconds, 60) or number(opts.interactionSeconds, 2)
        return number(explicit, fallback), 0, nil, uncertain, 0,
            uncertain and "Work time estimated; the quantity or drop rate is unknown." or nil
    end
    local k, r, p = f.kills, f.items, f.p
    local last = f.key and s.campWork[f.key]
    local sameWindow = last and
        (s.openedAt[d.qid] or 0) < last.start
    if sameWindow then
        for _, parent in ipairs(d.parents) do
            if not s.done[parent.id] or s.done[parent.id] >= last.start then sameWindow = false; break end
        end
    end
    local jointUnknown = sameWindow and r > 0 and last.r > 0
    local combined = sameWindow and not jointUnknown
    -- One confirmed personal drop stream and any number of compatible kill counters.
    -- Different loot streams have no known joint distribution, so keep them separate.
    if combined then
        k, r, p = math.max(k, last.k), math.max(r, last.r), p or last.p
    end
    -- Avoid a single long UI slice on pathological provider quantities. Sequential work
    -- is a conservative estimate on this boundary and is labelled uncertain.
    local capped = k > 0 and r > 0 and math.min(r, k) > 128
    local total = capped and k + r / p or jointKills(k, r, p)
    local incremental = math.max(0, total - (combined and last.total or 0))
    local run = { key = f.key, k = k, r = r, p = p, total = total,
        start = combined and last.start or #s.order + 1,
        streams = jointUnknown and (last.streams or 1) + 1 or 1 }
    local alone = f.items > 0 and f.items / f.p or f.kills
    local bounds = jointUnknown and (last.streams or 1) == 1
        and {lowerKills=math.max(last.total, alone), upperKills=last.total + alone} or nil
    if jointUnknown and (last.streams or 1) > 1 then bounds = false end
    return incremental * number(opts.killSeconds, 8), incremental, run, capped or jointUnknown,
        combined and math.max(0, alone - incremental) or 0,
        jointUnknown and "Separate quest drops may overlap; their joint rate is unknown."
            or (capped and "Large drop counts use a conservative estimate." or nil), bounds
end

-- Where this visit happens: the site with the least travel plus incremental work from here,
-- so a camp already being farmed for another quest wins when its shared kills save time.
local function place(m, s, d)
    local sites = d.sites
    if #sites == 1 then
        local t, approx = travel(m, s.at, sites[1].point)
        return sites[1], t, approx
    end
    local best, bestTravel, bestApprox, bestCost
    for _, site in ipairs(sites) do
        local t, approx = travel(m, s.at, site.point)
        if t < math.huge then
            local cost = t + service(m, d, s, site)
            if not bestCost or cost < bestCost - 0.000001 then best, bestTravel, bestApprox, bestCost = site, t, approx, cost end
        end
    end
    if not best then return sites[1], math.huge end
    return best, bestTravel, bestApprox
end

local function newState(m)
    local s = { at = m.options.origin, time = 0, travel = 0, kills = 0, wait = 0, work = 0,
        inventory = {}, freeSlots = m.options.inventory and m.options.inventory.freeSlots,
        reputation = {},
        skillRanks = {},
        level = m.options.level, levelXP = m.options.currentXP, nextLevelXP = m.options.nextLevelXP,
        xp = 0, count = 0, targetCount = 0, targetWork = 0, slots = 0, cap = m.options.logCapacity,
        open = {}, openedAt = {}, campWork = {}, claimed = {}, finishedQuests = {},
        todo = {}, ready = {}, done = {}, order = {}, uncertain = false }
    for id, count in pairs(m.options.inventory and m.options.inventory.counts or {}) do
        s.inventory[id] = count
    end
    for id, value in pairs(m.options.reputation or {}) do s.reputation[id] = value end
    for id, value in pairs(m.options.skillRanks or {}) do s.skillRanks[id] = value end
    for id, q in pairs(m.qs) do
        if q.status == "active" or q.entry then
            s.open[id], s.claimed[id], s.slots = true, true, s.slots + 1
        elseif q.status == "done" then s.claimed[id], s.finishedQuests[id] = true, true end
    end
    s.slots = math.max(s.slots, number(m.options.logCount, 0))
    for _, d in ipairs(m.list) do
        if not m.allowed or m.allowed[d.id] then
            s.todo[d.id] = #d.parents
            if #d.parents == 0 and not d.missingParent then s.ready[#s.ready + 1] = d end
        end
    end
    return s
end

local function eligible(m, s, d)
    if d.farm and d.farm.unavailable then return false end
    if d.farm and (d.farm.items or 0) > 0 and s.freeSlots == 0 then
        local itemID = d.s.objectives and d.s.objectives[1].target.itemID
        if itemID and (s.inventory[itemID] or 0) == 0 then return false end
    end
    if d.s.kind ~= "pickup" then
        if not s.open[d.qid] then return false end
        if d.s.kind == "turnin" then
            for itemID, count in pairs(m.qs[d.qid].consumedItems or {}) do
                if (s.inventory[itemID] or 0) < count then return false end
            end
        end
        return true
    end
    if s.claimed[d.qid] or (s.cap and s.slots >= s.cap) then return false end
    local quest = m.qs[d.qid]
    if quest.requiredLevel and s.level and quest.requiredLevel > s.level then return false end
    if quest.requiredMaxLevel and s.level and s.level > quest.requiredMaxLevel then return false end
    local minRep, maxRep = quest.requiredMinRep, quest.requiredMaxRep
    if quest.status ~= "ready" and
        ((minRep and s.reputation[minRep[1]] == nil) or (maxRep and s.reputation[maxRep[1]] == nil)) then return false end
    if minRep and s.reputation[minRep[1]] and s.reputation[minRep[1]] < minRep[2] then return false end
    if maxRep and s.reputation[maxRep[1]] and s.reputation[maxRep[1]] >= maxRep[2] then return false end
    local skill = quest.requiredSkill
    if skill then
        local rank = s.skillRanks[skill[1]]
        if rank == nil and quest.status ~= "ready" then return false end
        if rank and rank < skill[2] then return false end
    end
    if quest.requiredRanks and #quest.requiredRanks > 0 then
        local matched, unknown = false, false
        for _, rule in ipairs(quest.requiredRanks) do
            local rank = s.skillRanks[rule[1]]
            if rank == nil then unknown = true
            elseif rank >= rule[2] then matched = true end
        end
        if not matched and (not unknown or quest.status ~= "ready") then return false end
    end
    local untilQuest = m.qs[d.qid].availableUntilCompleted
    if untilQuest and s.claimed[untilQuest] and not s.open[untilQuest] then return false end
    for other in pairs(m.excluded[d.qid] or {}) do if s.claimed[other] then return false end end
    for _, gate in ipairs(quest.gates or {}) do
        local satisfied = gate.satisfied
        if not satisfied then
            for _, parentID in ipairs(gate.choices) do
                if (gate.kind == "turnin" and s.finishedQuests[parentID])
                    or (gate.kind == "accepted" and s.claimed[parentID])
                    or (gate.kind == "active" and s.open[parentID]) then
                    satisfied = true
                    break
                end
            end
        end
        if not satisfied then return false end
    end
    return true
end

local function advance(m, s, d, travelTime, approx, detail, site)
    site = site or d.sites[1]
    local effort, kills, run, unknown, saved, uncertaintyReason, bounds = service(m, d, s, site)
    local waitUntil = m.options.availableAfter and m.options.availableAfter[d.id]
    local waitTime = math.max(0, number(waitUntil, 0) - s.time - travelTime)
    s.time = s.time + travelTime + effort + waitTime
    s.travel, s.kills, s.wait, s.work = s.travel + travelTime, s.kills + kills, s.wait + waitTime, s.work + effort
    s.uncertain = s.uncertain or approx or unknown or false
    if run and run.key then s.campWork[run.key] = run end
    if d.farm and (d.farm.items or 0) > 0 then
        local itemID = d.s.objectives and d.s.objectives[1].target.itemID
        if itemID then
            local owned = s.inventory[itemID] or 0
            s.inventory[itemID] = owned + d.farm.items
            if owned == 0 and s.freeSlots then s.freeSlots = s.freeSlots - 1 end
        end
    end
    s.at, s.done[d.id] = site.point, #s.order + 1
    s.order[#s.order + 1] = d
    if m.selected[d.qid] then s.targetWork = s.targetWork + 1 end
    if d.s.kind == "pickup" then
        s.open[d.qid], s.openedAt[d.qid], s.claimed[d.qid], s.slots = true, #s.order, true, s.slots + 1
    elseif d.s.kind == "turnin" then
        for itemID, count in pairs(m.qs[d.qid].consumedItems or {}) do
            s.inventory[itemID] = s.inventory[itemID] - count
            if s.inventory[itemID] == 0 and s.freeSlots then s.freeSlots = s.freeSlots + 1 end
        end
        if s.open[d.qid] then s.slots = s.slots - 1 end
        s.open[d.qid], s.claimed[d.qid], s.finishedQuests[d.qid] = nil, true, true
        s.count, s.xp = s.count + 1, s.xp + m.xp[d.qid]
        for id, gain in pairs(m.qs[d.qid].reputationReward or {}) do
            if s.reputation[id] then s.reputation[id] = s.reputation[id] + gain end
        end
        if s.level and s.levelXP and s.nextLevelXP and s.nextLevelXP > 0 then
            s.levelXP = s.levelXP + m.xp[d.qid]
            if s.levelXP >= s.nextLevelXP then
                s.level, s.levelXP, s.nextLevelXP = s.level + 1, s.levelXP - s.nextLevelXP, nil
            end
        end
        if m.selected[d.qid] then s.targetCount = s.targetCount + 1 end
    end
    for _, child in ipairs(d.children) do
        if s.todo[child.id] then
            s.todo[child.id] = s.todo[child.id] - 1
            if s.todo[child.id] == 0 and not child.missingParent then s.ready[#s.ready + 1] = child end
        end
    end
    if detail then
        if bounds ~= nil and run and run.key then detail.lootBounds[run.key] = bounds or nil end
        if saved and saved > 0.0001 then
            detail.reasons[d.id] = string.format("At this camp, shared kill credit avoids about %.1f extra kills.", saved)
        elseif waitTime > 0 then
            detail.reasons[d.id] = string.format("Estimated wait here: %.0f seconds.", waitTime)
        elseif unknown then
            detail.reasons[d.id] = bounds and string.format(
                "These two drops may overlap: about %.1f–%.1f expected kills at this camp; joint rate unknown.",
                bounds.lowerKills, bounds.upperKills) or uncertaintyReason or "Work time is uncertain."
        end
    end
end

local function score(mode, s)
    local length = #s.order
    if mode == "xp" then
        local ratio = s.time > 0 and s.xp / s.time or 0
        return ratio, s.xp, -s.time
    elseif mode == "budget" then return s.count, -s.time, 0
    elseif mode == "selected" then return s.targetCount, s.targetWork, -s.time end
    return s.count, -s.time, length
end

local function better(a, b)
    if not b then return true end
    for i = 1, 3 do
        if math.abs(a[i] - b[i]) > 0.0000001 then return a[i] > b[i] end
    end
    return false
end

local function snapshot(s, mode)
    local a, b, c = score(mode, s)
    return { a, b, c, length = #s.order, time = s.time, travel = s.travel, kills = s.kills,
        wait = s.wait, work = s.work, xp = s.xp, count = s.count, targetCount = s.targetCount, uncertain = s.uncertain }
end

local function rankLess(priority, cost, order, bp, bc, bo)
    return bp == nil or priority < bp or (priority == bp and (cost < bc or (cost == bc and order < bo)))
end

local function attempt(m, seed, baseline)
    local mode = m.options.mode
    local s, best = newState(m)
    local flexible = not seed.fixed and (mode == "budget" or mode == "xp" or mode == "selected")
    if flexible then best = snapshot(s, mode) end
    local remainingPrep = 0
    if seed.prep then for _ in pairs(seed.prep) do remainingPrep = remainingPrep + 1 end end
    local previousRank = seed.previous
    while #s.ready > 0 do
        local bestAt, firstPriority, bestCost, bestOrder, bestTravel, approximate, bestSite
        for i, d in ipairs(s.ready) do
            if i % 16 == 1 then m.checkpoint() end
            if not baseline then
                m.alternativeChecks = m.alternativeChecks + 1
                if m.alternativeChecks > m.limit then return nil end
            end
            if eligible(m, s, d) then
                local site, t, approx = place(m, s, d)
                local possible = t < math.huge
                if possible and mode == "budget" and not seed.fixed then
                    local effort = service(m, d, s, site)
                    local opens = m.options.availableAfter and m.options.availableAfter[d.id]
                    possible = math.max(s.time + t, number(opens, 0)) + effort <= m.options.budgetSeconds
                end
                if possible then
                    local priority, cost = 3, t
                    if seed.avoidWaiting then
                        local opens = m.options.availableAfter and m.options.availableAfter[d.id]
                        cost = math.max(t, number(opens, 0) - s.time)
                    end
                    if previousRank then
                        priority = previousRank[d.id] or (#m.list + 1)
                    elseif seed.prep then
                        if seed.prep[d.id] then priority = 1
                        elseif seed.group[d.id] then priority = remainingPrep == 0 and 1 or 4 end
                    end
                    if rankLess(priority, cost, d.order, firstPriority, bestCost, bestOrder) then
                        bestAt, firstPriority, bestCost, bestOrder, bestTravel, approximate, bestSite = i, priority, cost, d.order, t, approx, site
                    end
                end
            end
        end
        if not bestAt then break end
        -- A low-cost pickup, delivery or interaction physically on the chosen leg can
        -- avoid a later return. Farming is deliberately left to the full camp comparison.
        if seed.road and bestTravel > 0 then
            local destination, insertDistance, insertOrder = bestSite.point, bestTravel, bestOrder
            for i, d in ipairs(s.ready) do
                if i % 16 == 1 then m.checkpoint() end
                m.alternativeChecks = m.alternativeChecks + 1
                if m.alternativeChecks > m.limit then return end
                if i ~= bestAt and not d.farm and eligible(m, s, d) then
                    local site, there, approx = place(m, s, d)
                    if there < bestTravel and (there < insertDistance or (there == insertDistance and d.order < insertOrder)) then
                        local through = travel(m, site.point, destination)
                        local opens = m.options.availableAfter and m.options.availableAfter[d.id]
                        local delay = math.max(0, number(opens, 0) - s.time - there)
                        local withinBudget = mode ~= "budget" or s.time + there + delay + service(m, d, s, site) <= m.options.budgetSeconds
                        if withinBudget and delay == 0 and there + through <= bestTravel + 0.001 then
                            bestAt, insertDistance, insertOrder, approximate, bestSite = i, there, d.order, approx, site
                        end
                    end
                end
            end
            bestTravel = insertDistance
        end
        local d = s.ready[bestAt]
        s.ready[bestAt] = s.ready[#s.ready]; s.ready[#s.ready] = nil
        advance(m, s, d, bestTravel, approximate, nil, bestSite)
        if seed.prep and seed.prep[d.id] then remainingPrep = remainingPrep - 1 end
        if flexible and d.s.kind == "turnin" then
            local current = snapshot(s, mode)
            if better(current, best) then best = current end
        end
    end
    best = best or snapshot(s, mode)
    best.path = {}
    for i = 1, best.length do best.path[i] = s.order[i] end
    return best
end

local function cloneState(s)
    local copy = {}
    for key, value in pairs(s) do
        if type(value) == "table" and key ~= "at" then
            local rows = {}
            for k, v in pairs(value) do rows[k] = v end
            copy[key] = rows
        else copy[key] = value end
    end
    return copy
end

-- Explore distinct feasible action orders only while the plan is small enough to
-- fit the shared UI budget. The incumbent from attempt always survives exhaustion.
local function beamSearch(m, incumbent)
    if #m.list > 40 then return incumbent, false end
    if m.alternativeChecks >= m.limit then return incumbent, true end
    local mode, width = m.options.mode, math.min(32, number(m.options.beamWidth, 20))
    local frontier, best, exhausted = {newState(m)}, incumbent, false
    for _ = 1, #m.list do
        local nextStates = {}
        for _, s in ipairs(frontier) do
            for i, d in ipairs(s.ready) do
                m.alternativeChecks = m.alternativeChecks + 1
                if m.alternativeChecks > m.limit then exhausted = true; break end
                if eligible(m, s, d) then
                    local site, t, approx = place(m, s, d)
                    local effort = t < math.huge and service(m, d, s, site) or math.huge
                    local opens = m.options.availableAfter and m.options.availableAfter[d.id]
                    local arrival = math.max(s.time + t, number(opens, 0)) + effort
                    if t < math.huge and (mode ~= "budget" or arrival <= m.options.budgetSeconds) then
                        local child = cloneState(s)
                        child.ready[i] = child.ready[#child.ready]
                        child.ready[#child.ready] = nil
                        advance(m, child, d, t, approx, nil, site)
                        nextStates[#nextStates + 1] = child
                        if d.s.kind == "turnin" then
                            local current = snapshot(child, mode)
                            if better(current, best) then
                                current.path = {}; for j, action in ipairs(child.order) do current.path[j] = action end
                                best = current
                            end
                        end
                    end
                end
                if i % 16 == 1 then m.checkpoint() end
            end
            if exhausted then break end
        end
        if exhausted or #nextStates == 0 then break end
        table.sort(nextStates, function(a, b)
            local ap, aq, ar = score(mode, a)
            local bp, bq, br = score(mode, b)
            if ap ~= bp then return ap > bp end
            if aq ~= bq then return aq > bq end
            if ar ~= br then return ar > br end
            if #a.order ~= #b.order then return #a.order > #b.order end
            return a.order[#a.order].order < b.order[#b.order].order
        end)
        frontier = {}
        for i = 1, math.min(width, #nextStates) do frontier[i] = nextStates[i] end
        m.checkpoint()
    end
    return best, exhausted
end

-- Replay one fixed action order; nil when it breaks a dependency, eligibility, reachability or budget.
-- `saved` holds states of the incumbent every STRIDE actions, so a candidate that differs from position
-- `from` onward resumes there. In "all" mode every feasible permutation hands in the same quests, so a
-- candidate already slower than `bound` cannot win and stops early (exact pruning).
local STRIDE = 8
local function evaluate(m, path, from, saved, bound, record)
    local mode = m.options.mode
    local flexible = mode == "budget" or mode == "xp" or mode == "selected"
    local s, best, first
    local k = saved and math.floor(((from or 1) - 1) / STRIDE) * STRIDE or 0
    if k > 0 and saved[k] then
        s, best, first = cloneState(saved[k].state), saved[k].best, k + 1
    else
        s, first = newState(m), 1
        best = flexible and snapshot(s, mode) or nil
    end
    for index = first, #path do
        local d = path[index]
        if s.todo[d.id] ~= 0 or s.done[d.id] or d.missingParent or not eligible(m, s, d) then return nil end
        local site, t, approx = place(m, s, d)
        if not (t < math.huge) then return nil end
        if mode == "budget" then
            local opens = m.options.availableAfter and m.options.availableAfter[d.id]
            if math.max(s.time + t, number(opens, 0)) + service(m, d, s, site) > m.options.budgetSeconds then return nil end
        end
        advance(m, s, d, t, approx, nil, site)
        m.evalSteps = (m.evalSteps or 0) + 1
        if bound and not flexible and s.time > bound + 0.0000001 then return nil end
        if flexible and d.s.kind == "turnin" then
            local current = snapshot(s, mode)
            if better(current, best) then best = current end
        end
        if record and index % STRIDE == 0 then record[index] = { state = cloneState(s), best = best } end
    end
    local result = {}
    for key, value in pairs(best or snapshot(s, mode)) do result[key] = value end
    result.path = {}
    for i = 1, result.length do result.path[i] = s.order[i] end
    return result
end

local function moved(path, i, len, j)
    local out, last = {}, i + len - 1
    if j == 0 then for k = i, last do out[#out + 1] = path[k] end end
    for k = 1, #path do
        if k < i or k > last then
            out[#out + 1] = path[k]
            if k == j then for q = i, last do out[#out + 1] = path[q] end end
        end
    end
    return out
end

local function reversed(path, i, j)
    local out = {}
    for k = 1, #path do out[k] = (k >= i and k <= j) and path[i + j - k] or path[k] end
    return out
end

-- Local search over the best schedule found so far, any zone size: move runs of up to three actions
-- (or-opt) and reverse short segments (2-opt) within a window, keeping the first strict improvement.
-- Every candidate is fully re-simulated, so prerequisites, slots, budgets and shared camps stay exact.
-- Bounded by simulated action steps; the incumbent always survives.
local function improve(m, incumbent)
    local budget = number(m.options.maxImproveSteps, 250000)
    local window = math.max(1, math.floor(number(m.options.improveWindow, 10)))
    local best, used, moves, saved = incumbent, 0, 0, nil
    if #incumbent.path < 3 or budget <= 0 then return best, moves, false, 0 end
    local function remember()
        saved = {}
        local replay = evaluate(m, best.path, 1, nil, nil, saved)
        if replay then best = replay else saved = nil end
    end
    remember()
    local function try(candidate, from)
        local before = m.evalSteps or 0
        m.checkpoint()
        local plan = evaluate(m, candidate, from, saved, best.time)
        used = used + math.max(1, (m.evalSteps or 0) - before)
        if plan and better(plan, best) then best, moves = plan, moves + 1; remember(); return true end
        return false
    end
    -- All moves that start at action i; true after the first strict improvement.
    local function movesAt(i)
        local path = best.path
        local n = #path
        for len = 1, 3 do
            if i + len - 1 > n then break end
            for j = math.max(0, i - 1 - window), math.min(n, i + len - 1 + window) do
                if used >= budget then return false end
                if (j < i - 1 or j > i + len - 1) and try(moved(path, i, len, j), math.min(i, j + 1)) then return true end
            end
        end
        for j = i + 2, math.min(n, i + window) do
            if used >= budget then return false end
            if try(reversed(path, i, j), i) then return true end
        end
        return false
    end
    -- Cycle through positions and stop after one full lap without any improvement.
    local i, quiet = 1, 0
    while used < budget and quiet < #best.path do
        if i > #best.path then i = 1 end
        if movesAt(i) then quiet = 0 else quiet, i = quiet + 1, i + 1 end
    end
    return best, moves, used >= budget, used
end

-- The returned stop carries the chosen site; the caller's stop tables are never modified.
local function located(stop, site)
    if not site or site.point == stop.point then return stop end
    local copy = {}
    for key, value in pairs(stop) do copy[key] = value end
    copy.point, copy.site = site.point, site
    if stop.objectives then
        copy.objectives = {}
        for i, row in ipairs(stop.objectives) do
            local clone = {}
            for key, value in pairs(row) do clone[key] = value end
            copy.objectives[i] = clone
        end
        if copy.objectives[1] then copy.objectives[1].sourceID = site.sourceID end
    end
    if site.tasks then copy.tasks = site.tasks end
    if site.questTasks then copy.questTasks = site.questTasks end
    if site.destination then copy.destination = site.destination end
    return copy
end

function O.optimize(quests, stops, options)
    options = options or {}
    local mode = options.mode or "all"
    if mode ~= "all" and mode ~= "selected" and mode ~= "xp" and mode ~= "budget" then return nil end
    if mode == "budget" and not finite(options.budgetSeconds) then return nil end
    local m = compile(quests, stops, options)
    if not m then return nil end
    local baseline = attempt(m, {}, true)
    local best, iterations, preferred = baseline, 1, nil
    local function try(seed)
        if m.alternativeChecks >= m.limit then return nil end
        local plan = attempt(m, seed, false)
        if plan then
            iterations = iterations + 1
            if better(plan, best) then best = plan end
        end
        return plan
    end
    if options.preferredIDs and #options.preferredIDs > 0 then
        local ranks = {}
        for i, id in ipairs(options.preferredIDs) do ranks[id] = i end
        preferred = try({ previous = ranks })
    end
    try({avoidWaiting=true, road=true})
    for _, quest in pairs(m.qs) do
        for _, gate in ipairs(quest.gates or {}) do
            if #gate.choices > 1 then
                for _, parentID in ipairs(gate.choices) do
                    if m.alternativeChecks >= m.limit then break end
                    local parentActions = m.byQuest[parentID]
                    if parentActions then
                        try({prep=m.ancestors(parentActions), group={}, road=true})
                    end
                end
            end
        end
    end
    table.sort(m.groups, function(a, b)
        if #a.stops ~= #b.stops then return #a.stops > #b.stops end
        return a.stops[1].order < b.stops[1].order
    end)
    for _, camp in ipairs(m.groups) do
        if #camp.stops < 2 or iterations >= 10 or m.alternativeChecks >= m.limit then break end
        local group, parents, distinct = {}, {}, {}
        for _, d in ipairs(camp.stops) do
            if not m.allowed or m.allowed[d.id] then
                group[d.id], distinct[d.qid] = true, true
                for _, parent in ipairs(d.parents) do parents[#parents + 1] = parent end
            end
        end
        local first = next(distinct)
        if first and next(distinct, first) then
            local prep = m.ancestors(parents)
            for id in pairs(group) do prep[id] = nil end
            try({ group = group, prep = prep, road = true })
        end
    end
    -- Different terminal goals expose inexpensive quest sets, mutually exclusive branches,
    -- or an attractive unlock that the nearest-action baseline overlooks.
    if #m.list <= 220 or mode ~= "all" then
        local goals = {}
        for _, d in ipairs(m.list) do
            if d.s.kind == "turnin" and (not m.allowed or m.allowed[d.id]) then goals[#goals + 1] = d end
        end
        table.sort(goals, function(a, b)
            if mode == "xp" and m.xp[a.qid] ~= m.xp[b.qid] then return m.xp[a.qid] > m.xp[b.qid] end
            if (m.excluded[a.qid] ~= nil) ~= (m.excluded[b.qid] ~= nil) then return m.excluded[a.qid] ~= nil end
            return a.order < b.order
        end)
        for i = 1, math.min(#goals, 12) do
            if m.alternativeChecks >= m.limit then break end
            local goal = goals[i]
            try({ group = {}, prep = m.ancestors({ goal }), road = mode == "all" })
        end
    end
    local searchExhausted
    best, searchExhausted = beamSearch(m, best)
    local improveMoves, improveExhausted, improveSteps
    best, improveMoves, improveExhausted, improveSteps = improve(m, best)
    if preferred and best ~= preferred and preferred[1] == best[1] and preferred[2] == best[2]
        and preferred.time - best.time <= number(options.stabilitySeconds, 0) then best = preferred end
    -- A mode can choose a different subset than nearest-first. Reprice that exact set
    -- before claiming a time saving; the original unconstrained result is also retained.
    local comparable = baseline
    local wanted = {}
    for _, d in ipairs(best.path) do wanted[d.id] = true end
    local same = #best.path == #baseline.path
    if same then
        for _, d in ipairs(baseline.path) do if not wanted[d.id] then same = false; break end end
    end
    if not same then
        local allowed = m.allowed
        m.allowed = wanted
        comparable = attempt(m, { fixed = true }, true)
        m.allowed = allowed
    end
    local matched = #comparable.path == #best.path
    local report = { mode = mode, expectedSeconds = best.time, baselineSeconds = comparable.time,
        expectedKills = best.kills, baselineKills = comparable.kills, baselineTravelSeconds = comparable.travel,
        travelSeconds = best.travel, workSeconds = best.work, waitSeconds = best.wait, expectedXP = best.xp,
        uncertain = best.uncertain, iterations = iterations, searchChecks = m.alternativeChecks,
        searchExhausted = searchExhausted, improveMoves = improveMoves, improveExhausted = improveExhausted, improveSteps = improveSteps,
        coverage = best.count, baselineCoverage = comparable.count,
        baselineComparable = matched, nearestCoverage = baseline.count, nearestSeconds = baseline.time,
        plannedIDs = {}, completedIDs = {}, missingIDs = {}, reasons = {}, lootBounds = {}, baselineRoute = {} }
    local ordered, replay = {}, newState(m)
    for i, d in ipairs(best.path) do
        local site, t, approx = place(m, replay, d)
        ordered[i] = located(d.s, site)
        report.plannedIDs[d.qid] = true
        if d.s.kind == "turnin" then report.completedIDs[d.qid] = true end
        advance(m, replay, d, t, approx, report, site)
        m.checkpoint()
    end
    for i, d in ipairs(comparable.path) do report.baselineRoute[i] = d.s end
    if matched and best.path[1] and comparable.path[1] and best.path[1] ~= comparable.path[1]
        and comparable.time - best.time >= 1 then
        local name = m.qs[comparable.path[1].qid].name or "the nearest quest"
        report.reasons[best.path[1].id] = string.format(
            "Starting here saves about %.0f seconds over going straight to %s for the same work.",
            comparable.time - best.time, name)
    end
    for id in pairs(mode == "selected" and m.selected or quests) do
        if not report.completedIDs[id] then report.missingIDs[id] = true end
    end
    return ordered, report
end
