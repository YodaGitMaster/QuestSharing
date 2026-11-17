-- QuestPlanner.lua: a prerequisite-aware, zone-local quest plan. Questie supplies facts; the player chooses the stops.
local ADDON, ns = ...
local P, U, S = {}, ns.optionalUI, ns.style
local Path = ns.questPlannerPath
local Work = ns.dataWork
local Guidance = ns.questGuidance
ns.questPlanner = P

P.levelScope = "all"

local function emptyCoverage()
    return { external = {}, unknown = {}, blocked = {}, repeatable = {}, completed = {}, filtered = {} }
end
local coverage = emptyCoverage()
function P.coverage() return coverage end
local CLUSTER_DISTANCE, TAKEIN_DISTANCE = 0.065, 0.045
local catalog, route, selected, frameMap, playerPoint, plannedMap, loading, generation = {}, {}, 1, nil, nil, nil, false, 0
local selectionLocked = false
local panel, message, planScroll, planRows, planContent, emptyText, followButton
local previousButton, nextButton, stepCounter, modeButton, lockButton, waypointButton, guidePosition
local guideExpanded, guideLocked = true, false
local sessionActive, zoneQuestIDs, zoneOrder = false, {}, {}
local buildGraph, buildRoute, render, selectStop, showPlanRows, stopIdentity, objectiveIsDone, scheduleRefresh, rebuildProgress
local targetLocation
local nextStopID = 0
local PLAN_ROW_HEIGHT, PLAN_LIST_HEIGHT, PLAN_WIDTH = 56, 280, 320
local panelDismissed, refreshQueued, refreshForce, refreshZoneEntry = false, false, false, false
local lastLogMembers, lastLogStructure, lastLogProgress = nil, nil, nil
local panelMoved, lastLevelStats = false, { localCount = 0, below = 0, above = 0, eligible = 0, unknown = 0 }

local function questie() return ns.questie end

local function questLevelBand(level)
    level = tonumber(level)
    if not level or level <= 0 or type(GetQuestDifficultyColor) ~= "function" then return "unknown" end
    local ok, color = pcall(GetQuestDifficultyColor, level)
    local palette = QuestDifficultyColors or QuestDifficultyColor
    if not (ok and type(color) == "table" and type(palette) == "table") then return "unknown" end
    local function matches(key)
        local expected = palette[key]
        return type(expected) == "table" and type(expected.r) == "number" and type(expected.g) == "number"
            and type(expected.b) == "number" and type(color.r) == "number" and type(color.g) == "number"
            and type(color.b) == "number" and math.abs(color.r - expected.r) < 0.001
            and math.abs(color.g - expected.g) < 0.001 and math.abs(color.b - expected.b) < 0.001
    end
    if matches("standard") then return "green" end
    if matches("difficult") then return "yellow" end
    if matches("trivial") then return "below" end
    if matches("verydifficult") or matches("impossible") then return "above" end
    return "unknown"
end

local function isInLevelRange(band)
    return band == "green" or band == "yellow"
end
local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end
local function distance(a, b)
    if not (a and b and a.x and a.y and b.x and b.y and a.map == b.map) then return math.huge end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function project(map, x, y)
    if not (map and frameMap and finite(x) and finite(y)) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    if map == frameMap then return { map = frameMap, x = x, y = y } end
    -- A rectangle alone does not prove membership: unrelated maps can return zero or plausible rectangles.
    local chain, seen, id = {}, {}, map
    for _ = 1, 12 do
        if seen[id] then return nil end
        seen[id] = true
        local info = U.call(C_Map and C_Map.GetMapInfo, id)
        local parent = info and info.parentMapID
        if not parent or parent == 0 then return nil end
        chain[#chain + 1] = { id, parent }
        id = parent
        if id == frameMap then break end
    end
    if id ~= frameMap then return nil end
    for _, edge in ipairs(chain) do
        local ok, left, right, top, bottom
        if C_Map and type(C_Map.GetMapRectOnMap) == "function" then
            ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, edge[1], edge[2])
        end
        if not (ok and finite(left) and finite(right) and finite(top) and finite(bottom))
            or right <= left or bottom <= top or left < 0 or right > 1 or top < 0 or bottom > 1 then return nil end
        x, y = left + (right - left) * x, top + (bottom - top) * y
    end
    return { map = frameMap, x = x, y = y }
end

local function pointForSpawn(spawn)
    if not spawn or spawn.dungeon or not spawn.map or not finite(spawn.x) or not finite(spawn.y) then return nil end
    return project(spawn.map, spawn.x / 100, spawn.y / 100)
end

local function nearestPoint(points)
    local best, score
    for _, raw in ipairs(points or {}) do
        local p = pointForSpawn(raw)
        if p then
            local d = playerPoint and distance(p, playerPoint) or 0
            if not best or d < score then best, score = p, d end
        end
    end
    return best
end

local function nearestSource(sources)
    local bestPoint, bestSource, bestDistance
    for _, source in ipairs(sources or {}) do
        for _, spawn in ipairs(source.spawns or {}) do
            local point = pointForSpawn(spawn)
            if point then
                local d = playerPoint and distance(point, playerPoint) or 0
                if not bestPoint or d < bestDistance then bestPoint, bestSource, bestDistance = point, source, d end
            end
        end
    end
    return bestPoint, bestSource
end

local function currentZone()
    frameMap = nil
    playerPoint = nil
    local map, x, y = ns.compat.playerPos()
    if not map then return nil, "Open the quest planner outdoors, in a mapped zone." end
    local info = C_Map and U.call(C_Map.GetMapInfo, map)
    local isCity = C_Map and C_Map.IsCityMap and U.call(C_Map.IsCityMap, map)
    if isCity then return nil, "The quest planner only works in outdoor zones, not towns or cities." end
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    if not info or info.mapType ~= zoneType then
        return nil, "Open the quest planner in an outdoor zone, not on a town, dungeon, or continent map."
    end
    frameMap = map
    playerPoint = { map = map, x = x, y = y }
    return info.name or ("map " .. tostring(map)), nil, map
end

local function clearPlan(reason)
    Guidance.clear()
    if P.cancelEstimate then P.cancelEstimate() end
    coverage = emptyCoverage()
    Work.cancel("quest-plan")
    if Path then Path.cancelWalkEstimates() end
    loading, catalog, route, selected, plannedMap = false, {}, {}, 1, nil
    lastLevelStats = { localCount = 0, below = 0, above = 0, eligible = 0, unknown = 0 }
    selectionLocked = false
    if message then message:SetText("Quest guide") end
    if emptyText then emptyText:SetText(reason) end
    if planContent then planScroll:SetVerticalScroll(0); showPlanRows() end
end

local function questLogState(log)
    local ids, members, structure, progress = {}, {}, {}, {}
    for id in pairs(log or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local entry = log[id]
        members[#members + 1] = tostring(id)
        local flags, counts = { entry.complete and "1" or "0" }, {}
        for _, objective in ipairs(ns.compat.objectives(entry)) do
            flags[#flags + 1] = objective.finished and "1" or "0"
            counts[#counts + 1] = tostring(objective.have or "?") .. "/" .. tostring(objective.need or "?")
        end
        structure[#structure + 1] = tostring(id) .. ":" .. table.concat(flags)
        progress[#progress + 1] = tostring(id) .. ":" .. table.concat(counts, ",")
    end
    return table.concat(members, ";"), table.concat(structure, ";"), table.concat(progress, ";")
end

local function statusFor(id, log)
    if log[id] then return "active" end
    if questie().questComplete(id) == true then return "done" end
    local doable = questie().questDoable(id)
    if doable == true then return "ready" end
    if doable == false then return questie().questBlockReason(id) end
    return "unknown"
end

local function newCandidate(id, starter, log, data)
    local turnPoint = nearestSource(data.turnIns)
    if log[id] and not turnPoint and not nearestSource(data.starters) then
        local area = tonumber((questie().get("quest", id, "zoneOrSort")))
        local associated = area and area > 0 and questie().uiMapOf(area) == frameMap
        for _, target in ipairs(data.targets) do
            if not associated and nearestPoint(target.points) then associated = true; break end
        end
        if not associated then return end
    end
    local status, detail = statusFor(id, log)
    local level = U.call(UnitLevel,"player")
    if data.repeatable then coverage.repeatable[id] = "Repeatable quest"; return end
    if status == "done" then coverage.completed[id] = "Already turned in"; return end
    if not log[id] then
        if (level and data.requiredLevel > level) or status == "level" then
            local reason = data.requiredLevel > 0 and ("Requires level " .. data.requiredLevel) or "Level requirement unmet"
            if level and data.requiredLevel == level + 1 then
                local xp, max = U.call(UnitXP,"player"), U.call(UnitXPMax,"player")
                if finite(xp) and finite(max) and max > xp and xp >= 0 then
                    reason = reason .. " (" .. (max - xp) .. " XP to next level)"
                end
            end
            local currentXP, nextXP = U.call(UnitXP, "player"), U.call(UnitXPMax, "player")
            if not (level and data.requiredLevel == level + 1 and finite(currentXP) and
                finite(nextXP) and nextXP > currentXP and nextXP > 0) then
                coverage.blocked[id] = reason .. "; recheck on level-up"
                return
            end
            coverage.unknown[id] = reason .. "; route depends on estimated quest XP"
            status = "level"
        end
        if (data.requiredMaxLevel and level and level > data.requiredMaxLevel) or status == "overlevel" then
            coverage.blocked[id] = "Above the maximum acceptance level"; return
        end
        if status == "any" or status == "all" or status == "parent" or status == "reputation" then
            local category, reason = questie().futureCharacterGate(id, true)
            if category then coverage[category][id] = reason; return end
        end
        for _, other in ipairs(data.exclusiveTo) do
            if log[other] or questie().questComplete(other) == true then
                coverage.blocked[id] = "Exclusive with quest " .. other; return
            end
        end
        if data.availableUntilCompleted and questie().questComplete(data.availableUntilCompleted) == true then
            coverage.blocked[id] = "Availability ended at quest " .. data.availableUntilCompleted; return
        end
    end
    data.status, data.entry = status, log[id]
    data.starterPoint = nearestSource(starter)
    data.starterRows = starter or {}
    local localWork, allWorkLocal = false, true
    for _, target in ipairs(data.targets) do
        local done, _, have, required = objectiveIsDone(data.entry, target)
        if have ~= nil and required then target.have,target.required,target.progressVerified = have,required,true end
        if not done then
            if targetLocation(target) then
                localWork = true
            else
                allWorkLocal = false
                if nearestPoint(target.points) then
                    coverage.blocked[id] = "No local source with a possible drop: " .. (target.name or target.kind)
                elseif #target.points > 0 then coverage.external[id] = "Objective outside this zone: " .. (target.name or target.kind)
                else coverage.unknown[id] = "Objective location unknown: " .. (target.name or target.kind) end
            end
        end
    end
    if not turnPoint then
        if #data.turnIns > 0 then
            local mapped
            for _,source in ipairs(data.turnIns) do if #(source.spawns or {}) > 0 then mapped=true end end
            if mapped then coverage.external[id] = "Turn-in outside this zone"
            else coverage.unknown[id] = "Turn-in location unknown" end
        else coverage.unknown[id] = "No known turn-in" end
    end
    data.canFinishHere = allWorkLocal and turnPoint ~= nil
    if data.entry then
        if not (data.entry.complete and turnPoint) and not localWork then return end
    elseif not allWorkLocal or (#data.turnIns > 0 and not turnPoint) then
        return
    end
    if status ~= "ready" and status ~= "active" and status ~= "any" and status ~= "all" and status ~= "parent" and status ~= "level" and status ~= "reputation" then
        if status == nil or status == "unknown" then coverage.unknown[id] = "Acceptance eligibility unknown"
        else coverage.blocked[id] = detail or (status == "exclusive" and "Exclusive quest already chosen"
            or status == "character" and "Class, race or faction requirement" or "A character or world requirement is unmet") end
        return
    end
    data.depth, data.prereqIDs, data.prereqKinds = 0, {}, {}
    return data
end

local function scan(rediscover)
    Guidance.clear()
    if P.cancelEstimate then P.cancelEstimate() end
    coverage = emptyCoverage()
    generation = generation + 1
    Work.cancel("quest-plan")
    if Path then Path.cancelWalkEstimates() end
    local thisGeneration = generation
    local q = questie()
    local zone, locationError, zoneMap = currentZone()
    if not zone then
        clearPlan(locationError)
        return
    end
    local log = ns.compat.entryMap()
    lastLogMembers, lastLogStructure, lastLogProgress = questLogState(log)
    if plannedMap ~= zoneMap then selectionLocked = false end
    local keepSelection = selectionLocked and plannedMap == zoneMap
    local oldSelected = selected
    local oldSelectedKey = keepSelection and route[selected] and stopIdentity(route[selected]) or nil
    local inZone, index = {}, 1
    if rediscover then zoneQuestIDs[zoneMap] = nil end
    local discovered = zoneQuestIDs[zoneMap]
    local discoveredIDs, sourceCache = {}, {}
    local levelStats = { localCount = 0, below = 0, above = 0, eligible = 0, unknown = 0 }
    lastLevelStats = levelStats
    loading, catalog, route, selected, plannedMap = true, {}, {}, 1, zoneMap
    if message then message:SetText(zone) end
    if emptyText then emptyText:SetText("Checking quest locations…") end
    if planContent then planScroll:SetVerticalScroll(0); showPlanRows() end

    Work.start("quest-plan", function()
        local ids
        if discovered then
            ids = {}; local seen = {}
            for _, id in ipairs(discovered) do ids[#ids + 1] = id; seen[id] = true end
            for id in pairs(log) do if not seen[id] then ids[#ids + 1] = id end end
        else
            ids = q.ids("quest")
        end
        if type(ids) ~= "table" then clearPlan("Questie needs a recent QuestieDB with quest IDs."); return end
        while index <= #ids do
            if index % 20 == 1 then
                local currentName, locationError, currentMap = currentZone()
                if not currentName then clearPlan(locationError); return end
                if currentMap ~= zoneMap then scan(); return end
            end
            local id = ids[index]; index = index + 1
            local active = log[id] ~= nil
            local starters, startPoint, zoneAssociated
            if not discovered or not active then
                starters = q.plannerStarters(id, sourceCache)
                startPoint = nearestSource(starters)
                if not startPoint then
                    local area = tonumber((q.get("quest", id, "zoneOrSort")))
                    zoneAssociated = area and area > 0 and q.uiMapOf(area) == zoneMap
                end
                if not discovered and (startPoint or zoneAssociated) then discoveredIDs[#discoveredIDs + 1] = id end
            end
            if active or startPoint then
                local data = q.plannerQuest(id, sourceCache)
                local band = data and questLevelBand(data.level) or "unknown"
                if not active then
                    levelStats.localCount = levelStats.localCount + 1
                    if band == "below" then levelStats.below = levelStats.below + 1
                    elseif band == "above" then levelStats.above = levelStats.above + 1
                    elseif isInLevelRange(band) then levelStats.eligible = levelStats.eligible + 1
                    else levelStats.unknown = levelStats.unknown + 1 end
                end
                if not data then coverage.unknown[id] = "Quest data missing"
                elseif P.levelScope == "green-yellow" and not isInLevelRange(band) then
                    coverage.filtered[id] = "Outside the green/yellow level filter"
                else
                    data.band = band
                    local candidate = newCandidate(id, starters or {}, log, data)
                    if candidate then inZone[id] = candidate end
                end
            elseif zoneAssociated then
                if q.questComplete(id) == true then coverage.completed[id] = "Already turned in"
                else
                    local mapped = false
                    for _,source in ipairs(starters or {}) do if #(source.spawns or {}) > 0 then mapped=true end end
                    if mapped then coverage.external[id] = "Quest starts outside this zone"
                    else coverage.unknown[id] = "Quest starter location unknown" end
                end
            end
            Work.yield()
        end
        if not discovered then
            zoneQuestIDs[zoneMap] = discoveredIDs
            for i = #zoneOrder, 1, -1 do if zoneOrder[i] == zoneMap then table.remove(zoneOrder, i) end end
            zoneOrder[#zoneOrder + 1] = zoneMap
            while #zoneOrder > 2 do zoneQuestIDs[table.remove(zoneOrder, 1)] = nil end
        end
        if thisGeneration ~= generation then return end
        local earned, currentXP, nextXP = 0, U.call(UnitXP, "player"), U.call(UnitXPMax, "player")
        for _, candidate in pairs(inZone) do
            if candidate.status ~= "level" then earned = earned + (tonumber(candidate.xp) or 0) end
        end
        for id, candidate in pairs(inZone) do
            if candidate.status == "level" and (not finite(nextXP) or not finite(currentXP)
                or earned < nextXP - currentXP) then
                inZone[id] = nil
                coverage.unknown[id] = nil
                local need = finite(nextXP) and finite(currentXP) and nextXP > currentXP
                    and (" (" .. tostring(nextXP - currentXP) .. " XP to next level)") or ""
                coverage.blocked[id] = "Requires level " .. tostring(candidate.requiredLevel)
                    .. need .. "; known local quest XP does not establish the unlock"
            end
        end
        catalog = inZone
        lastLevelStats = levelStats
        buildGraph(log)
        buildRoute()
        if keepSelection then
            selected = math.max(1, math.min(oldSelected, #route))
            if oldSelectedKey then
                for i, stop in ipairs(route) do
                    if stopIdentity(stop) == oldSelectedKey then selected = i; break end
                end
            end
        end
        loading = false
        render(zone)
    end, function()
        return thisGeneration == generation and loading and ns.db.enabled and ns.db.questPlanner
            and sessionActive and not panelDismissed and panel and panel:IsShown()
    end, function(ok)
        if not ok and thisGeneration == generation then clearPlan("Quest data could not be read; try Refresh.") end
    end)
end

buildGraph = function(log)
    local nodes, reverse, eligible, pending, queue = catalog, {}, {}, {}, {}
    local completed, alternate = {}, {}
    local function isComplete(id)
        if completed[id] == nil then completed[id] = questie().questComplete(id) == true end
        return completed[id]
    end
    local function alternatives(id)
        if not alternate[id] then
            local list = nodes[id] and nodes[id].exclusiveTo or questie().get("quest", id, "exclusiveTo")
            alternate[id] = type(list) == "table" and list or {}
        end
        return alternate[id]
    end
    for id, q in pairs(nodes) do
        local gates = {}
        local function gate(kind, choices)
            gates[#gates + 1] = {kind=kind, choices=choices}
            for _,parentID in ipairs(choices) do
                reverse[parentID] = reverse[parentID] or {}
                reverse[parentID][#reverse[parentID] + 1] = id
            end
        end
        if q.status ~= "active" then
            -- A live ready judgment already satisfies completed-quest gates. In-log gates still
            -- constrain ordering: handing in a parent too soon can close its child's pickup.
            if q.status ~= "ready" then
                if #q.beforeAny > 0 then gate("turnin",q.beforeAny) end
                for _, raw in ipairs(q.beforeAll) do
                    if type(raw) == "number" and raw ~= 0 then
                        local choices = {math.abs(raw)}
                        if raw > 0 then for _, other in ipairs(alternatives(raw)) do choices[#choices+1] = other end end
                        gate("turnin",choices)
                    end
                end
            end
            if q.parentQuest then gate("active",{q.parentQuest}) end
            if q.availableStartingWith then gate("accepted",{q.availableStartingWith}) end
        end
        q.gates = gates
        if #gates == 0 and (q.status == "ready" or q.status == "active" or q.status == "level" or q.status == "reputation") then
            eligible[id] = true
        else
            pending[id] = gates
        end
        queue[#queue+1] = id
        Work.checkpoint()
    end
    table.sort(queue)
    local index, queued = 1, {}
    for _, id in ipairs(queue) do queued[id] = true end
    while index <= #queue do
        local id = queue[index]; index = index + 1; queued[id] = nil
        local gates, q = pending[id], nodes[id]
        if gates and #gates > 0 then
            local parents, kinds, valid, depth, future = {}, {}, true, 0, false
            for _, g in ipairs(gates) do
                local best, bestDepth, already = nil, nil, false
                for _, parentID in ipairs(g.choices) do
                    if g.kind ~= "active" and isComplete(parentID) then already = true; g.satisfied = true; break end
                    if g.kind ~= "turnin" and log[parentID] then
                        if nodes[parentID] then best, bestDepth = parentID, 0
                        else already = true; g.satisfied = true end
                        break
                    end
                    local parent = eligible[parentID] and nodes[parentID]
                    if parent and (g.kind ~= "turnin" or parent.canFinishHere)
                        and (not bestDepth or parent.depth < bestDepth or (parent.depth == bestDepth and parentID < best)) then
                        best, bestDepth = parentID, parent.depth
                    end
                end
                if not already then
                    if not best then valid = false; break end
                    if not kinds[best] then parents[#parents+1] = best end
                    if not kinds[best] or kinds[best] == "accepted" then kinds[best] = g.kind
                    elseif kinds[best] ~= g.kind and g.kind ~= "accepted" then valid = false; break end
                    depth = math.max(depth, bestDepth + 1)
                    if g.kind == "turnin" or not log[best] then future = true end
                end
            end
            if valid then
                q.depth, q.prereqIDs, q.prereqKinds = depth, parents, kinds
                q.status = future and "future" or "ready"
                eligible[id], pending[id] = true, nil
                for _, child in ipairs(reverse[id] or {}) do
                    if pending[child] and not queued[child] then queue[#queue+1]=child; queued[child]=true end
                end
            end
        end
        Work.checkpoint()
    end
    for id in pairs(pending) do
        coverage.blocked[id] = "Prerequisite unavailable in this zone or cyclic"
        nodes[id] = nil
    end
end

local function addDep(stop, dep)
    if dep and stop and dep ~= stop then stop.deps[dep.id] = true end
end

local function newStop(kind, p, phase)
    nextStopID = nextStopID + 1
    return { id = nextStopID, kind = kind, phase = phase, point = p, quests = {}, tasks = {}, questTasks = {}, deps = {}, done = false }
end

local function addTask(stop, quest, text, destination)
    stop.tasks[#stop.tasks + 1] = text
    stop.quests[quest.id] = quest.name
    stop.questTasks[quest.id] = stop.questTasks[quest.id] or {}
    table.insert(stop.questTasks[quest.id], text)
    stop.destination = stop.destination or destination
end

local goal = { mode = "all", selectedIDs = {}, budgetSeconds = 1800 }
local report, previousPlan, previousMap, lastOrigin, plannedSpeed
local waitingAt = {}
local function campKey(p)
    return string.format("%d/%.5f/%.5f", p.map, p.x, p.y)
end

function P.cancelEstimate()
    Work.cancel("quest-costs")
    if Path then Path.cancelWalkEstimates() end
    report = nil
end

local function atom(stops, kind, point, quest, task, destination, key)
    local stop = newStop(kind, point, quest.depth)
    stop.key = tostring(quest.id) .. "/" .. kind .. "/" .. tostring(key or "")
    addTask(stop, quest, task, destination)
    stops[#stops + 1] = stop
    return stop
end

objectiveIsDone = function(entry, target)
    if not entry then return false end
    if entry.complete then return true end
    -- Live inventory and kills can name the same NPC. A loot counter must match the item itself.
    local names = {}
    local function add(name)
        if type(name) == "string" and name ~= "" then names[string.lower(name)] = true end
    end
    add(target.name)
    if target.kind == "kill" then
        for _, source in ipairs(target.sources or {}) do add(source.name) end
    end
    local match
    for _, objective in ipairs(ns.compat.objectives(entry)) do
        local name = string.lower(objective.name or objective.text or "")
        local compatible = not objective.type or (target.kind == "kill" and objective.type == "monster")
            or (target.kind == "loot" and objective.type == "item")
            or (target.kind ~= "kill" and target.kind ~= "loot")
        if compatible and (names[name] or names[(name:gsub(" slain$", ""))] or names[(name:gsub(" killed$", ""))]) then
            if match then return false end
            match = objective
        end
    end
    if not match then return false end
    local have, need = tonumber(match.have), tonumber(match.need)
    if finite(have) and finite(need) and have >= 0 and need > 0 and have <= need then
        return match.finished, string.format("%d/%d", have, need), have, need
    end
    return match.finished
end

local function targetSummary(target, source, probability)
    local verbs = { kill = "Kill ", loot = "Collect ", object = "Use ", explore = "Visit ",
        talk = "Talk to ", escort = "Escort ", use = "Use ", event = "Complete " }
    local text = (verbs[target.kind] or "Visit ") .. (target.name or "objective")
    if target.kind == "loot" and source and source.name then
        text = text .. " from " .. source.name
        if probability then text = text .. string.format(" (%.2g%%)", probability * 100) end
    end
    return text
end

targetLocation = function(target)
    local best, chosen, score
    for _, source in ipairs(target.sources or {}) do
        local probability = target.dropRates and target.dropRates[source.id]
        if source.kind ~= "npc" or target.kind ~= "loot" or probability ~= 0 then
            local point = nearestPoint(source.spawns)
            if point then
                local d = distance(playerPoint, point)
                if not best or d < score then best, chosen, score = point, source, d end
            end
        end
    end
    if not chosen and #(target.sources or {}) == 0 then return nearestPoint(target.points) end
    return best, chosen
end

local function questActions()
    local stops, actions, ids = {}, {}, {}
    for id in pairs(catalog) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local q = catalog[id]
        local a = { objectives = {} }
        actions[id] = a
        if q.status ~= "active" then
            local point, giver = nearestSource(q.starters or q.starterRows)
            point = point or q.starterPoint
            if point then
                local name = giver and giver.name
                a.pickup = atom(stops, "pickup", point, q, "Pick up " .. q.name .. (name and (" from " .. name) or ""), name)
            end
        end
        for i, target in ipairs(q.targets or {}) do
            local done, progress, have, need = objectiveIsDone(q.entry, target)
            if not done then
                local point, source = targetLocation(target)
                if point then
                    local npc = source and source.kind == "npc" and source.id or nil
                    local probability = npc and target.dropRates and target.dropRates[npc]
                    local required = need or target.required
                    local text = targetSummary(target, source, probability)
                    if progress then text = text .. " (" .. progress .. ")"
                    elseif required then text = text .. " ×" .. required end
                    local stop = atom(stops, "objective", point, q, text,
                        target.name and ("the " .. target.name .. " area"), i)
                    local sharing = npc and target.shareable ~= false and
                        ((target.kind == "kill" and target.creditID) or (target.kind == "loot" and target.itemID))
                    stop.objectives = { { questID = id, target = target, remaining = required and math.max(0, required - (have or 0)),
                        sourceID = npc, shareable = sharing and true or false } }
                    addDep(stop, a.pickup)
                    a.objectives[#a.objectives + 1] = stop
                end
            end
        end
        local turnPoint, turner = nearestSource(q.turnIns)
        if turnPoint and (q.entry and q.entry.complete or q.canFinishHere) then
            local name = turner and turner.name
            a.turnin = atom(stops, "turnin", turnPoint, q, "Turn in " .. q.name .. (name and (" to " .. name) or ""), name)
            addDep(a.turnin, a.pickup)
            for _, objective in ipairs(a.objectives) do addDep(a.turnin, objective) end
        end
        Work.checkpoint()
    end
    for _, id in ipairs(ids) do
        local q, child = catalog[id], actions[id]
        for _, parentID in ipairs(q.prereqIDs or {}) do
            local alternative = false
            for _, gate in ipairs(q.gates or {}) do
                if #gate.choices > 1 then
                    for _, choice in ipairs(gate.choices) do
                        if choice == parentID then alternative = true end
                    end
                end
            end
            local parent = not alternative and actions[parentID]
            if parent then
                local kind = q.prereqKinds and q.prereqKinds[parentID] or "turnin"
                if kind == "active" or kind == "accepted" then
                    addDep(child.pickup, parent.pickup)

                else
                    addDep(child.pickup, parent.turnin)
                end
            end
        end
        Work.checkpoint()
    end
    return stops
end

local function visibleStops(ordered, reasons)
    local grouped, last = {}, nil
    for _, stop in ipairs(ordered) do
        local radius = stop.kind == "objective" and CLUSTER_DISTANCE or TAKEIN_DISTANCE
        -- Only collapse consecutive instructions. Their physical actions still run in scheduled order.
        if not last or last.kind ~= stop.kind or distance(last.point, stop.point) > radius then
            last = { point = stop.point, kind = stop.kind, phase = stop.phase, destination = stop.destination,
                quests = {}, tasks = {}, questTasks = {}, reasons = {}, atoms = {} }
            grouped[#grouped + 1] = last
        end
        last.atoms[#last.atoms + 1] = stop
        local reason = reasons and reasons[stop.id]
        if type(reason) == "string" and last.reasons[#last.reasons] ~= reason then last.reasons[#last.reasons + 1] = reason end
        for id, name in pairs(stop.quests) do
            for _, task in ipairs(stop.questTasks[id]) do addTask(last, {id = id, name = name}, task) end
        end
    end
    return grouped
end

local function runSpeed()
    local current, run = U.call(GetUnitSpeed, "player")
    if finite(run) and run > 0 then return run end
    if finite(current) and current > 0 then return current end
    return 7
end

local function planOptions(stops, origin)
    local width, height = U.call(C_Map and C_Map.GetMapWorldSize, origin.map)
    local estimatedScale = not (finite(width) and width > 0 and finite(height) and height > 0)
    if estimatedScale then width, height = 3000, 2000 end
    local speed, firstLeg = runSpeed(), {}
    local function travel(a, b)
        if a == origin then
            local walking = firstLeg[campKey(b)]
            if type(walking) == "number" then return walking / speed end
            if walking == false then return math.huge end
        end
        local dx, dy = (a.x - b.x) * width, (a.y - b.y) * height
        return math.sqrt(dx * dx + dy * dy) / speed
    end
    local count = 0
    for _ in pairs(ns.compat.entryMap()) do count = count + 1 end
    local capacity = U.call(C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept)
        or (Constants and Constants.QuestLogConsts and Constants.QuestLogConsts.MaxQuestLogSize) or MAX_QUESTLOG_QUESTS
    local relevantItems = {}
    for _, quest in pairs(catalog) do
        for _, target in ipairs(quest.targets or {}) do
            if target.itemID then relevantItems[target.itemID] = true end
        end
        for itemID in pairs(quest.consumedItems or {}) do relevantItems[itemID] = true end
    end
    local inventory = ns.compat.plannerInventory(relevantItems)
    local factions, skills = {}, {}
    for _, quest in pairs(catalog) do
        if quest.requiredMinRep then factions[quest.requiredMinRep[1]] = true end
        if quest.requiredMaxRep then factions[quest.requiredMaxRep[1]] = true end
        for id in pairs(quest.reputationReward or {}) do factions[id] = true end
        if quest.requiredSkill then skills[quest.requiredSkill[1]] = true end
        for _, rank in ipairs(quest.requiredRanks or {}) do skills[rank[1]] = true end
    end
    local reputation = ns.compat.plannerReputation(factions)
    local skillRanks = ns.compat.plannerSkills(skills)
    local availableAfter, byKey, preferred = {}, {}, {}
    local now = GetTime()
    for key, expires in pairs(waitingAt) do if expires <= now then waitingAt[key] = nil end end
    for _, stop in ipairs(stops) do
        byKey[stop.key] = stop.id
        local expires = stop.kind == "objective" and waitingAt[campKey(stop.point)]
        if expires then availableAfter[stop.id] = expires - now end
    end
    if previousMap == origin.map then
        for _, key in ipairs(previousPlan or {}) do if byKey[key] then preferred[#preferred + 1] = byKey[key] end end
    end
    return { mode = goal.mode, selectedIDs = goal.selectedIDs, budgetSeconds = goal.budgetSeconds, origin = origin,
        checkpoint = Work.checkpoint, travelSeconds = travel, killSeconds = 10, interactionSeconds = 3,
        logCount = count, logCapacity = capacity, preferredIDs = preferred, stabilitySeconds = 10,
        availableAfter = availableAfter, inventory = inventory,
        reputation = reputation,
        skillRanks = skillRanks,
        level = U.call(UnitLevel, "player"), currentXP = U.call(UnitXP, "player"),
        nextLevelXP = U.call(UnitXPMax, "player") }, firstLeg, estimatedScale, speed
end

buildRoute = function()
    P.cancelEstimate()
    nextStopID = 0
    local stops, origin = questActions(), playerPoint
    if not origin then route = {}; return end
    local opts, firstLeg, estimatedScale, speed = planOptions(stops, origin)
    local token = generation
    local function solve()
        local ordered, result = ns.questOptimizer.optimize(catalog, stops, opts)
        if generation ~= token then return end
        report = result or {}
        report.estimatedScale = estimatedScale
        report.range = P.levelScope
        previousMap, previousPlan = origin.map, {}
        for _, stop in ipairs(ordered or {}) do previousPlan[#previousPlan + 1] = stop.key end
        lastOrigin, plannedSpeed = origin, speed
        route = visibleStops(ordered or {}, report.reasons)
    end
    solve()
    if Path and Path.available() then
        local targets, seen = {}, {}
        for _, stop in ipairs(stops) do
            local key = campKey(stop.point)
            if not next(stop.deps) and not seen[key] then
                targets[#targets + 1], seen[key] = stop.point, true
            end
        end
        Path.estimateWalks(origin, targets, function(costs)
            if not costs or generation ~= token or not sessionActive then return end
            for i, point in ipairs(targets) do firstLeg[campKey(point)] = costs[i] end
            Work.start("quest-costs", function()
                local key = selectionLocked and route[selected] and stopIdentity(route[selected])
                solve()
                if token ~= generation then return end
                selected = 1
                if key then
                    for i, stop in ipairs(route) do if stopIdentity(stop) == key then selected = i; break end end
                end
                render()
            end, function() return generation == token and sessionActive and not panelDismissed and ns.db.enabled end)
        end)
    end
end

local function stopLabel(stop)
    local unique, names = {}, {}
    for id, name in pairs(stop.quests) do if not unique[id] then unique[id] = true; names[#names + 1] = name end end
    table.sort(names)
    return table.concat(names, ", ")
end

stopIdentity = function(stop)
    local p = stop.point or {}
    return table.concat({ stop.kind, tostring(stop.phase), tostring(p.map), string.format("%.4f", p.x or 0), string.format("%.4f", p.y or 0),
        stopLabel(stop) }, "\31")
end

local function mapLine(stop)
    if not stop.point then return "Location unknown" end
    local p = stop.point
    return string.format("Map %s — %.1f, %.1f", tostring(p.map), p.x * 100, p.y * 100)
end

local function dockPanel()
    if panelMoved then return end
    local tracker = ObjectiveTrackerFrame or WatchFrame or QuestWatchFrame
    panel:ClearAllPoints()
    if tracker and tracker.GetTop then
        panel:SetPoint("TOPRIGHT", tracker, "TOPLEFT", -8, 0)
    else
        panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -36, -180)
    end
end

local function ensurePanel()
    if panel then return true end
    if not (CreateFrame and UIParent) then return false end
    panel = S.window("QuestSharingPlannerPanel", PLAN_WIDTH, 380, "Quest plan", "hud")
    if not panel then return false end
    S.fill(panel, "BACKGROUND", 0.035, 0.032, 0.027, 1):SetAllPoints(panel)
    panel.title:ClearAllPoints()
    panel.title:SetPoint("TOP", panel, "TOP", 0, -8)
    panel.title:SetText(S.GOLD .. "QUEST SHARING|r")
    panel.onMoved = function() panelMoved = true end
    panel:SetScript("OnDragStart", function(self) if not guideLocked then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self)
        if not guideLocked then self:StopMovingOrSizing(); panelMoved = true end
    end)
    panel:EnableMouse(true)
    local function smallButton(label, width, x, y, action, tip)
        local b = S.button(panel, label, width, action, tip)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
        b.bg:Hide(); b.edge:Hide()
        return b
    end
    smallButton("...", 20, 7, 6, function() ns.toggleSettings(true, "optional") end, "Quest Sharing settings")
    smallButton("Plan", 38, 28, 6, function() P.options() end, "Choose the objective and review route estimates")
    smallButton("?", 20, 68, 6, function(self)
        U.tip(self, "Quest guide", { "Follow the highlighted step, then use the arrows to review the next step.",
            "Quest progress updates the guide automatically. Click a step to mark its location.",
            "Lock keeps the guide in place. Minus shows only the current step." })
    end, "How to use the quest guide")
    lockButton = smallButton("Lock", 46, PLAN_WIDTH - 80, 6, function(self)
        guideLocked = not guideLocked
        panel:SetMovable(not guideLocked)
        self:SetLabel(guideLocked and "Unlock" or "Lock")
    end, "Lock or unlock the guide position")
    local headerLine = S.fill(panel, "ARTWORK", 0.56, 0.39, 0.14, 1)
    headerLine:SetPoint("TOPLEFT", panel, "TOPLEFT", 7, -29)
    headerLine:SetWidth(PLAN_WIDTH - 14); headerLine:SetHeight(1)
    previousButton = smallButton("<", 20, 8, 34, function() P.navigate(-1) end, "Previous step")
    stepCounter = U.text(panel, "0/0", 32, 38, 40)
    nextButton = smallButton(">", 20, 74, 34, function() P.navigate(1) end, "Next step")
    message = U.text(panel, "", 100, 38, PLAN_WIDTH - 138)
    message:SetWordWrap(false)
    modeButton = smallButton("-", 22, PLAN_WIDTH - 32, 34, function(self)
        guideExpanded = not guideExpanded
        self:SetLabel(guideExpanded and "-" or "+")
        if planScroll then planScroll:SetVerticalScroll(0) end
        showPlanRows()
    end, "Show upcoming steps or only the current step")
    planScroll = CreateFrame("ScrollFrame", nil, panel)
    planScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -60)
    planScroll:SetWidth(PLAN_WIDTH - 20)
    planScroll:SetHeight(PLAN_LIST_HEIGHT)
    planScroll:EnableMouseWheel(true)
    planContent = CreateFrame("Frame", nil, planScroll)
    planContent:SetWidth(PLAN_WIDTH - 20)
    planContent:SetHeight(PLAN_LIST_HEIGHT)
    planScroll:SetScrollChild(planContent)
    emptyText = U.text(planContent, "", 8, 8, PLAN_WIDTH - 36)
    emptyText:SetWordWrap(true)
    planScroll:SetScript("OnMouseWheel", function(self, delta)
        local pos = self:GetVerticalScroll() - delta * PLAN_ROW_HEIGHT
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), pos)))
    end)
    planRows = {}
    S.button(panel, "Refresh", 72, function() scan(true) end):SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 12)
    waypointButton = S.button(panel, "Waypoint", 90, function() P.pin() end)
    waypointButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)
    followButton = S.button(panel, "Follow with SPF", 126, function() P.follow() end)
    followButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 94, 12)
    followButton:SetScript("OnEnter", function(self)
        U.tip(self, "Walk this stop", { "Shortest Path Forever draws the route on your map and minimap.",
            "Following it replaces the route you are using now." })
    end)
    followButton:SetScript("OnLeave", function() U.hideTip() end)
    followButton:Hide()
    local track = S.fill(panel, "BACKGROUND", 0.11, 0.1, 0.08, 1)
    track:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 4)
    track:SetWidth(PLAN_WIDTH - 16); track:SetHeight(3)
    guidePosition = S.fill(panel, "ARTWORK", 0.86, 0.64, 0.24, 1)
    guidePosition:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 4)
    guidePosition:SetHeight(3); guidePosition:SetWidth(1)
    S.closeButton(panel, function() panelDismissed = true; panel:Hide() end, -2, -2)
    panel:SetScript("OnHide", function()
        Guidance.clear()
        panelDismissed = true
        sessionActive = false
        Work.cancel("quest-plan")
        P.cancelEstimate()
        panel:SetScript("OnUpdate", nil)
        generation = generation + 1
        loading = false
    end)

    dockPanel()
    return true
end

local function rowTaskText(stop)
    local tasks = {}
    for i = 1, math.min(#stop.tasks, 2) do tasks[#tasks + 1] = stop.tasks[i] end
    if #stop.tasks > 2 then tasks[#tasks + 1] = string.format("+%d more", #stop.tasks - 2) end
    return table.concat(tasks, " • ")
end

local function sortedQuestIDs(stop)
    local ids = {}
    for id in pairs(stop.quests) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

local function rowDetailsText(stop, numbers)
    local tasks = { stop.kind == "pickup" and "Take these quests:" or stop.kind == "turnin"
        and "Hand in these quests:" or "Complete these quests here:" }
    for _, id in ipairs(sortedQuestIDs(stop)) do
        local questTasks = stop.questTasks[id] or {}
        if stop.kind == "objective" or #questTasks == 0 then
            tasks[#tasks + 1] = string.format("[%d] %s", numbers[id], stop.quests[id])
            for _, task in ipairs(questTasks) do tasks[#tasks + 1] = "  " .. task end
        else
            for _, task in ipairs(questTasks) do tasks[#tasks + 1] = string.format("[%d] %s", numbers[id], task) end
        end
    end
    if stop.reasons and stop.reasons[1] then tasks[#tasks + 1] = stop.reasons[1] end
    return table.concat(tasks, "\n")
end

local function destinationName(stop)
    local p = stop.point
    local info = p and U.call(C_Map and C_Map.GetMapInfoAtPosition, p.map, p.x, p.y)
    local zone = p and U.call(C_Map and C_Map.GetMapInfo, p.map)
    if type(info) == "table" and type(info.name) == "string" and info.name ~= ""
        and (not zone or info.name ~= zone.name) then return info.name end
    return stop.destination or "the marked location"
end

local function showStopOnMap(index)
    if not selectStop(index) then return false end
    local stop = route[selected]
    if not (stop and stop.point) then return ns.print("this stop has no map location") end
    if InCombatLockdown and InCombatLockdown() then return ns.print("mark this location after combat") end
    local p = stop.point
    if not ns.compat.setWaypoint(p.map, p.x, p.y) then
        return ns.print("the game cannot mark this location on the map")
    end
    return true
end

showPlanRows = function()
    if not planContent then return end
    if emptyText then if #route == 0 then emptyText:Show() else emptyText:Hide() end end
    for _, row in ipairs(planRows) do row:Hide() end
    local numbers, count = {}, 0
    for _, stop in ipairs(route) do
        for _, id in ipairs(sortedQuestIDs(stop)) do
            if not numbers[id] then count = count + 1; numbers[id] = count end
        end
    end
    local contentY = 0
    local lastVisible = math.min(#route, selected + (guideExpanded and 5 or 0))
    for i = selected, lastVisible do
        local stop = route[i]
        local row = planRows[i]
        if not row then
            row = CreateFrame("Button", nil, planContent)
            row:SetHeight(PLAN_ROW_HEIGHT - 3)
            row.bg = S.fill(row, "BACKGROUND", 1, 1, 1, 1)
            row.bg:SetAllPoints(row)
            row.edge = S.fill(row, "BORDER", 1, 1, 1, 1)
            row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.edge:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            row.edge:SetHeight(1)
            row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 7, -4)
            row.title:SetWidth(PLAN_WIDTH - 36)
            row.title:SetJustifyH("LEFT")
            row.title:SetWordWrap(true)
            row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
            row.detail:SetWidth(PLAN_WIDTH - 36)
            row.detail:SetJustifyH("LEFT")
            row.detail:SetWordWrap(true)
            planRows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", planContent, "TOPLEFT", 0, -contentY)
        row:SetWidth(PLAN_WIDTH - 20)
        row.stepIndex, row.current = i, i == selected
        local pointText = stop.point and string.format("%.1f, %.1f", stop.point.x * 100, stop.point.y * 100) or "location unknown"
        row.title:SetText((row.current and S.GOLD or "|cffb6ad9d") ..
            string.format("Step %d: Go to %s\n%s", i, destinationName(stop), pointText) .. "|r")
        row.detail:SetText((row.current and S.WHITE or "|cffa9a69f") .. rowDetailsText(stop, numbers) .. "|r")
        local titleHeight = row.title.GetStringHeight and row.title:GetStringHeight() or 12
        local detailHeight = row.detail.GetStringHeight and row.detail:GetStringHeight() or 12
        local rowHeight = math.max(PLAN_ROW_HEIGHT - 3, titleHeight + detailHeight + 16)
        row:SetHeight(rowHeight)
        contentY = contentY + rowHeight + 3
        if row.current then
            row.bg:SetVertexColor(0.23, 0.075, 0.045, 1)
            row.edge:SetVertexColor(0.82, 0.54, 0.18, 1)
        else
            row.bg:SetVertexColor(0.065, 0.06, 0.052, 1)
            row.edge:SetVertexColor(0.18, 0.16, 0.12, 1)
        end
        local rowIndex = i
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(_, button)
            if button == "RightButton" then showStopOnMap(rowIndex)
            elseif selectStop(rowIndex) then P.pin() end
        end)
        row:SetScript("OnEnter", function(self)
            U.tip(self, "Quest location", { "Left-click: set a waypoint.", "Right-click: mark this location on the map." })
        end)
        row:SetScript("OnLeave", function() U.hideTip() end)
        row:SetEnabled(stop.point ~= nil)
        row:Show()
    end
    local viewport = guideExpanded and PLAN_LIST_HEIGHT or math.max(70, math.min(PLAN_LIST_HEIGHT, contentY + 3))
    planScroll:SetHeight(viewport)
    panel:SetHeight(60 + viewport + 40)
    planContent:SetHeight(math.max(viewport, contentY))
    if stepCounter then stepCounter:SetText(string.format("%d/%d", #route > 0 and selected or 0, #route)) end
    if previousButton then previousButton:SetEnabled(#route > 0 and selected > 1) end
    if nextButton then nextButton:SetEnabled(selected < #route) end
    if guidePosition then guidePosition:SetWidth(math.max(1, (PLAN_WIDTH - 16) * (#route > 0 and selected / #route or 0))) end
    if waypointButton then
        if #route > 0 and not (Path and Path.available()) then waypointButton:Show() else waypointButton:Hide() end
    end
    local stop = route[selected]
    if stop and not loading then
        local action = stop.kind == "pickup" and "Accept quests at " or stop.kind == "turnin" and "Hand in quests at "
            or "Complete objectives at "
        Guidance.set(route, selected, panel, function(index) if selectStop(index) then P.pin() end end,
            action .. destinationName(stop))
    else Guidance.clear() end
end

render = function(zone)
    if not planScroll then return end
    local info = plannedMap and U.call(C_Map and C_Map.GetMapInfo, plannedMap)
    zone = zone or (info and info.name)
    if followButton then
        if Path and Path.available() and #route > 0 then followButton:Show() else followButton:Hide() end
    end
    local active, ready, future = 0, 0, 0
    for _, quest in pairs(catalog) do
        if quest.status == "active" then active = active + 1
        elseif quest.status == "ready" then ready = ready + 1
        elseif quest.status == "future" then future = future + 1 end
    end
    if #route == 0 then
        if message then
            message:SetText(zone or "Quest guide")
        end
        if emptyText then
            local stats = lastLevelStats or {}
            local reason
            if (stats.localCount or 0) > 0 and stats.below == stats.localCount then
                reason = "This zone is too low level for you."
            elseif (stats.localCount or 0) > 0 and stats.eligible == 0 and stats.above == stats.localCount then
                reason = "The quests in this zone are above your level range."
            elseif (stats.localCount or 0) > 0 and stats.eligible == 0 and stats.unknown == stats.localCount then
                reason = "Quest levels are not available for this zone."
            elseif (stats.localCount or 0) > 0 and stats.eligible == 0 then
                reason = "No quests here are green or yellow for your level."
            elseif active + ready + future == 0 then
                reason = (stats.localCount or 0) == 0 and "Questie has no mapped quest givers here."
                    or "No active or ready quests found here."
            else
                reason = "Quest data was found, but no route locations are mapped here."
            end
            emptyText:SetText(reason)
        end
        showPlanRows()
        return
    end
    selected = math.min(selected, #route)
    if message then
        message:SetText(zone or "Current zone")
    end
    showPlanRows()
end

selectStop = function(index)
    if loading or #route == 0 then return false end
    local zone, reason, map = currentZone()
    if not zone then clearPlan(reason); return false end
    if map ~= plannedMap then scan(); return false end
    selected = math.max(1, math.min(#route, index))
    selectionLocked = true
    render(zone)
    return true
end

function P.navigate(direction)
    local index = selected + direction
    if index < 1 or index > #route then return false end
    if not selectStop(index) then return false end
    if planScroll then planScroll:SetVerticalScroll(0) end
    P.pin()
    return true
end

function P.pin()
    if loading then return ns.print("the quest guide is updating") end
    if not plannedMap and #route == 0 then return ns.print("there is no quest plan yet; use /qs plan") end
    local zone, reason, map = currentZone()
    if not zone then clearPlan(reason); return end
    if plannedMap and map ~= plannedMap then scan(); return ns.print("you changed zones; rebuilding the quest plan") end
    local stop = route[selected]
    if not stop or not stop.point then return ns.print("this stop has no map location") end
    local p = stop.point
    if not ns.compat.setWaypoint(p.map, p.x, p.y) then
        ns.print("the game cannot set a waypoint here; " .. mapLine(stop))
    end
end

function P.follow()
    if loading then return ns.print("the quest guide is updating") end
    local stop = route[selected]
    if not stop or not stop.point then return ns.print("this stop has no map location") end
    local zone, reason, map = currentZone()
    if not zone then clearPlan(reason); return end
    if plannedMap and map ~= plannedMap then
        scan()
        return ns.print("you changed zones; rebuilding the quest plan")
    end
    if not (Path and Path.available()) then
        return ns.print("Shortest Path Forever is not ready; click a stop for a regular map pin")
    end
    local title = rowTaskText(stop)
    local ok, why = Path.follow(stop.point, title, stop.kind)
    if ok then ns.print("Shortest Path Forever accepted the route to " .. title)
    else ns.print("Shortest Path Forever could not start this route (" .. tostring(why) .. "); click the stop for a regular map pin") end
end

function P.refresh()
    if not ns.db.questPlanner then return ns.print("turn on Quest planner in Extra tools first") end
    if not panel or not panel:IsShown() then return P.open() end
    sessionActive = true
    scan(true)
end

function P.open()
    if not ns.db.questPlanner then ns.setSetting("questPlanner", true); return end
    panelDismissed = false
    sessionActive = true
    if not ensurePanel() then return ns.print("this client cannot open the quest plan panel") end
    dockPanel()
    panel:Show()
    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 3 then return end
        elapsed = 0
        if loading or not sessionActive or U.call(InCombatLockdown) then return end
        local map, x, y = ns.compat.playerPos()
        if map and finite(x) and finite(y) and lastOrigin and map == lastOrigin.map then
            local point = {map=map,x=x,y=y}
            if distance(lastOrigin, point) >= 0.025 or math.abs(runSpeed() - (plannedSpeed or 7)) > 0.5 then
                playerPoint = point
                rebuildProgress(ns.compat.entryMap())
            end
        end
    end)
    scan()
end

function P.settingChanged(enabled)
    if enabled then
        panelDismissed = false
        P.open()
    else
        panelDismissed = true
        sessionActive = false
        zoneQuestIDs, zoneOrder = {}, {}
        generation = generation + 1
        loading = false
        clearPlan("Quest planner is off.")
        if panel then panel:Hide() end
    end
end

function P.masterChanged(enabled)
    if enabled then return end
    if panel then panel:SetScript("OnUpdate", nil) end
    Guidance.clear()
    sessionActive = false
    generation = generation + 1
    Work.cancel("quest-plan")
    P.cancelEstimate()
    if Path then Path.cancelWalkEstimates() end
    loading = false
    if panel then panel:Hide() end
end

rebuildProgress = function(log, zone)
    Guidance.clear()
    local oldIndex, oldKey = selected, selectionLocked and route[selected] and stopIdentity(route[selected])
    generation = generation + 1
    local token = generation
    if Path then Path.cancelWalkEstimates() end
    loading = true
    Work.start("quest-plan", function()
        for id, quest in pairs(catalog) do quest.entry = log[id] end
        buildRoute()
        selected = selectionLocked and math.max(1, math.min(oldIndex, #route)) or 1
        if oldKey then
            for i, stop in ipairs(route) do
                if stopIdentity(stop) == oldKey then selected = i; break end
            end
        end
        loading = false
        render(zone)
    end, function()
        return token == generation and ns.db.enabled and ns.db.questPlanner and sessionActive
            and not panelDismissed and panel and panel:IsShown()
    end, function(ok) if not ok and token == generation then clearPlan("Refresh the quest guide to try again.") end end)
end

scheduleRefresh = function(force, zoneEntry)
    if not (ns.db and ns.db.enabled and ns.db.questPlanner and sessionActive)
        or panelDismissed or not (panel and panel:IsShown()) then return end
    if zoneEntry and plannedMap then
        local zone, reason, map = currentZone()
        if map ~= plannedMap then
            generation = generation + 1
            clearPlan(zone and ("Building a new plan for " .. zone .. "…") or reason)
        end
    end
    refreshForce = refreshForce or force
    refreshZoneEntry = refreshZoneEntry or zoneEntry
    if refreshQueued then return end
    refreshQueued = true
    ns.after(zoneEntry and 1.2 or 0.65, function()
        refreshQueued = false
        local mustRefresh, enteredZone = refreshForce, refreshZoneEntry
        refreshForce, refreshZoneEntry = false, false
        if not (ns.db and ns.db.enabled and ns.db.questPlanner and sessionActive)
            or panelDismissed or not (panel and panel:IsShown()) then return end

        if enteredZone and not panelDismissed and ensurePanel() then
            dockPanel()
            panel:Show()
        end
        local zone, _, map = currentZone()
        if not zone then
            if enteredZone or mustRefresh then scan() end
            return
        end
        local log = ns.compat.entryMap()
        local members, structure, progress = questLogState(log)
        if mustRefresh or map ~= plannedMap or members ~= lastLogMembers or structure ~= lastLogStructure
            or (loading and progress ~= lastLogProgress) then
            scan()
        elseif progress ~= lastLogProgress then
            lastLogMembers, lastLogStructure, lastLogProgress = members, structure, progress
            rebuildProgress(log, zone)
        end
    end)
end

ns.on("PLAYER_ENTERING_WORLD", function() scheduleRefresh(false, true) end)
ns.on("ZONE_CHANGED_NEW_AREA", function() scheduleRefresh(false, true) end)
ns.on("ZONE_CHANGED", function() scheduleRefresh(false, true) end)
ns.on("QUEST_ACCEPTED", function() scheduleRefresh(true, false) end)
ns.on("QUEST_REMOVED", function() scheduleRefresh(true, false) end)
ns.on("QUEST_TURNED_IN", function() scheduleRefresh(true, false) end)
ns.on("PLAYER_LEVEL_UP", function() scheduleRefresh(true, false) end)
ns.on("QUEST_LOG_UPDATE", function() scheduleRefresh(false, false) end)
ns.on("BAG_UPDATE_DELAYED", function() scheduleRefresh(true, false) end)
ns.on("SPELLS_CHANGED", function() scheduleRefresh(true, false) end)
ns.on("UPDATE_FACTION", function() scheduleRefresh(true, false) end)
ns.on("SKILL_LINES_CHANGED", function() scheduleRefresh(true, false) end)
ns.on("QUEST_WATCH_UPDATE", function() scheduleRefresh(false, false) end)
ns.on("UNIT_QUEST_LOG_CHANGED", function() scheduleRefresh(false, false) end)

local modeNames = {all="Complete the zone", xp="Fastest quest XP/hour", selected="Selected quests", budget="Quest count within time"}
function P.report() return report end

local function explainPlan()
    local lines = {modeNames[goal.mode] .. " • " .. (P.levelScope == "all" and "All acceptance levels" or "Green/yellow only")}
    if report then
        lines[#lines+1] = string.format("Estimated %.1f min • travel %.1f min • %.1f kills • %d hand-ins",
            (report.expectedSeconds or 0)/60, (report.travelSeconds or 0)/60, report.expectedKills or 0, report.coverage or 0)
        lines[#lines+1] = "Times use estimated combat and interaction costs. Map distances approximate travel."
        if report.estimatedScale then lines[#lines+1] = "Map dimensions unavailable. Travel uses an illustrative 3000 × 2000 yard zone scale." end
        if report.uncertain then lines[#lines+1] = "Some quantities, drop rates or task durations are unknown or estimated." end
        if report.baselineComparable then
            lines[#lines+1] = string.format("Same-work nearest-first estimate %.1f min. Best route found by bounded search.", (report.baselineSeconds or 0)/60)
        end
    else lines[#lines+1] = "Open the guide and wait for the zone scan." end
    local pending = {}
    for id in pairs(report and report.missingIDs or {}) do pending[#pending+1]=id end
    table.sort(pending)
    for _,id in ipairs(pending) do
        lines[#lines+1] = string.format("Quest %d • unfinished, excluded by this goal, incompatible branch or missing data",id)
    end
    for _, category in ipairs({"external","unknown","blocked","filtered","repeatable"}) do
        local ids = {}
        for id in pairs(coverage[category]) do ids[#ids+1]=id end
        table.sort(ids)
        for _,id in ipairs(ids) do lines[#lines+1] = string.format("%d • %s",id,coverage[category][id]) end
    end
    lines[#lines+1] = "Unknown future levels, inventory restrictions, flight routes and world conditions need live confirmation."
    return table.concat(lines,"\n\n")
end

function P.setGoal(mode, value)
    if modeNames[mode] == nil then return false end
    if mode == "selected" then
        local ids={}
        for token in tostring(value or ""):gmatch("%d+") do ids[tonumber(token)]=true end
        if not next(ids) then ns.print("enter quest IDs for the Selected quests goal"); return false end
        goal.selectedIDs=ids
    elseif mode == "budget" then
        value=tonumber(value)
        if not finite(value) or value <= 0 or value > 1440 then ns.print("enter a time budget from 1 to 1440 minutes"); return false end
        goal.budgetSeconds=value*60
    end
    goal.mode=mode
    selectionLocked=false
    previousPlan=nil
    if sessionActive then scan() else P.open() end
    return true
end

local optionsPanel, optionsText, selectedBox, budgetBox
function P.options()
    if not optionsPanel then
        optionsPanel=U.window("QuestSharingPlannerOptions",420,520,"Quest plan objective")
        if not optionsPanel then return end
        S.button(optionsPanel,"Complete zone",124,function() P.setGoal("all"); P.options() end):SetPoint("TOPLEFT",optionsPanel,"TOPLEFT",12,-36)
        S.button(optionsPanel,"Quest XP/hour",124,function() P.setGoal("xp"); P.options() end):SetPoint("TOPLEFT",optionsPanel,"TOPLEFT",146,-36)
        S.button(optionsPanel,"Level range",124,function()
            P.levelScope=P.levelScope=="all" and "green-yellow" or "all"
            selectionLocked=false; previousPlan=nil
            if sessionActive then scan() end
            P.options()
        end):SetPoint("TOPLEFT",optionsPanel,"TOPLEFT",280,-36)
        selectedBox=U.box(optionsPanel,"Quest IDs",12,70,252,"",150)
        S.button(optionsPanel,"Plan selected",134,function() P.setGoal("selected",selectedBox:GetText()); P.options() end):SetPoint("TOPLEFT",optionsPanel,"TOPLEFT",274,-87)
        budgetBox=U.box(optionsPanel,"Minutes available",12,118,252,30,5)
        S.button(optionsPanel,"Plan within time",134,function() P.setGoal("budget",budgetBox:GetText()); P.options() end):SetPoint("TOPLEFT",optionsPanel,"TOPLEFT",274,-135)
        S.button(optionsPanel,"Camp busy 5 min",150,function()
            local stop=route[selected]
            if stop and stop.kind=="objective" then
                waitingAt[campKey(stop.point)]=GetTime()+300
                selectionLocked=false; scan()
            else ns.print("select an objective camp first") end
        end):SetPoint("TOPLEFT",optionsPanel,"TOPLEFT",12,-173)
        S.button(optionsPanel,"Clear camp wait",134,function() waitingAt={}; selectionLocked=false; if sessionActive then scan() end end):SetPoint("TOPLEFT",optionsPanel,"TOPLEFT",174,-173)
        local _, setText = U.scrollText(optionsPanel,12,210,396,268)
        optionsText=setText
        S.button(optionsPanel,"Refresh report",134,function() P.options() end):SetPoint("BOTTOMLEFT",optionsPanel,"BOTTOMLEFT",12,10)
    end
    optionsText(explainPlan())
    optionsPanel:Show()
end

function P.command(arg)
    arg = string.lower(arg or "")
    local mode, value = arg:match("^(%S+)%s*(.-)$")
    if mode == "all" or mode == "xp" or mode == "selected" or mode == "budget" then P.setGoal(mode,value)
    elseif arg == "options" or arg == "why" then P.options()
    elseif arg == "range" or arg == "unrestricted" then
        P.levelScope=arg=="range" and "green-yellow" or "all"
        selectionLocked=false; previousPlan=nil
        if sessionActive then scan() else P.open() end
    elseif arg == "off" then ns.setSetting("questPlanner", false)
    elseif arg == "hide" or arg == "close" then
        Guidance.clear(); panelDismissed = true; sessionActive = false
        Work.cancel("quest-plan"); P.cancelEstimate(); generation = generation + 1; loading = false
        if panel then panel:SetScript("OnUpdate", nil); panel:Hide() end
    elseif arg == "on" then ns.setSetting("questPlanner", true); ns.print("quest planner is on")
    elseif arg == "next" then if selectStop(selected + 1) then P.pin() end
    elseif arg == "follow" then P.follow()
    elseif arg == "refresh" then P.refresh()
    else P.open() end
end
