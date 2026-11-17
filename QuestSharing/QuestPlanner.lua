-- QuestPlanner.lua: a prerequisite-aware, zone-local quest plan. Questie supplies facts; the player chooses the stops.
local ADDON, ns = ...
local P, U, S = {}, ns.optionalUI, ns.style
local Path = ns.questPlannerPath
local Work = ns.dataWork
local Guidance = ns.questGuidance
ns.questPlanner = P

local MAX_FUTURE_LAYERS = 4
local CLUSTER_DISTANCE, TAKEIN_DISTANCE = 0.065, 0.045
local catalog, route, selected, frameMap, playerPoint, plannedMap, loading, generation = {}, {}, 1, nil, nil, nil, false, 0
local selectionLocked = false
local panel, message, planScroll, planRows, planContent, emptyText, followButton
local previousButton, nextButton, stepCounter, modeButton, lockButton, waypointButton, guidePosition
local guideExpanded, guideLocked = true, false
local sessionActive, zoneQuestIDs, zoneOrder = false, {}, {}
local buildGraph, buildRoute, render, selectStop, showPlanRows, stopIdentity, objectiveIsDone
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

local function copyIds(list)
    local out = {}
    for _, id in ipairs(type(list) == "table" and list or {}) do
        id = math.abs(tonumber(id) or 0)
        if id > 0 then out[#out + 1] = id end
    end
    return out
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
    data = data or questie().plannerQuest(id)
    if not data then return nil end
    data.status = statusFor(id, log)
    data.starterPoint = nearestSource(starter)
    data.starterRows = starter or {}
    data.entry = log[id]
    local localWork, allWorkLocal = false, true
    for _, target in ipairs(data.targets or {}) do
        if not objectiveIsDone(data.entry, target) then
            if nearestPoint(target.points) then localWork = true else allWorkLocal = false end
        end
    end
    local turnPoint = nearestSource(data.turnIns)
    data.canFinishHere = allWorkLocal and turnPoint ~= nil
    if data.entry then
        if not (data.entry.complete and turnPoint) and not localWork then return nil end
    elseif not allWorkLocal or (#(data.turnIns or {}) > 0 and not turnPoint) then
        return nil
    end
    data.depth = 0
    data.prereqIDs = {}
    return data
end

local function scan(rediscover)
    Guidance.clear()
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
    local keepSelection = plannedMap == zoneMap
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
            local starters, startPoint, candidate, data, band
            if not discovered or not active then
                starters = q.plannerStarters(id, sourceCache)
                startPoint = nearestSource(starters)
                if not discovered and startPoint then discoveredIDs[#discoveredIDs + 1] = id end
            end
            if active then
                data = q.plannerQuest(id, sourceCache)
                band = data and questLevelBand(data.level) or "unknown"
                if data and isInLevelRange(band) then candidate = newCandidate(id, {}, log, data) end
            else
                if startPoint then
                    data = q.plannerQuest(id, sourceCache)
                    band = data and questLevelBand(data.level) or "unknown"
                    levelStats.localCount = levelStats.localCount + 1
                    if band == "below" then levelStats.below = levelStats.below + 1
                    elseif band == "above" then levelStats.above = levelStats.above + 1
                    elseif isInLevelRange(band) then levelStats.eligible = levelStats.eligible + 1
                    else levelStats.unknown = levelStats.unknown + 1 end
                    if data and q.questComplete(id) ~= true and isInLevelRange(band) then
                        candidate = newCandidate(id, starters, log, data)
                    end
                end
            end
            if candidate and (active or candidate.status == "ready" or candidate.status == "any" or candidate.status == "all") then
                inZone[id] = candidate
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
    local nodes = catalog
    local activeOrReady = {}
    for id, q in pairs(nodes) do
        if q.status == "active" or q.status == "ready" then activeOrReady[id] = true end
    end
    -- Walk forward from quests the character can do now. A later quest is included only when its prerequisite
    -- gates can be satisfied by already completed or planned quests in this same area.
    for layer = 1, MAX_FUTURE_LAYERS do
        local additions = {}
        for id, child in pairs(nodes) do
            if not activeOrReady[id] and (child.status == "any" or child.status == "all") then
                local anyReq, allReq = copyIds(child.beforeAny), copyIds(child.beforeAll)
                local parents, valid, depth = {}, true, 0
                if #anyReq > 0 then
                    local bestDepth, bestParent
                    for _, parentID in ipairs(anyReq) do
                        local parent = nodes[parentID]
                        if activeOrReady[parentID] and parent.canFinishHere and (parent.depth or 0) < layer then
                            local candidateDepth = (parent.depth or 0) + 1
                            if not bestDepth or candidateDepth < bestDepth then bestDepth, bestParent = candidateDepth, parentID end
                        elseif questie().questComplete(parentID) == true then
                            bestDepth, bestParent = 0, nil
                            break
                        end
                    end
                    if bestDepth == nil then valid = false
                    elseif bestParent then
                        parents[#parents + 1] = bestParent
                        depth = math.max(depth, bestDepth)
                    end
                end
                for _, parentID in ipairs(allReq) do
                    local parent = nodes[parentID]
                    if activeOrReady[parentID] and parent.canFinishHere and (parent.depth or 0) < layer then
                        parents[#parents + 1] = parentID
                        depth = math.max(depth, (parent.depth or 0) + 1)
                    elseif questie().questComplete(parentID) ~= true then
                        valid = false
                        break
                    end
                end
                if valid and #parents > 0 and depth == layer then
                    additions[#additions + 1] = { quest = child, id = id, depth = depth, parents = parents }
                end
            end
            Work.checkpoint()
        end
        if #additions == 0 then break end
        for _, a in ipairs(additions) do
            a.quest.status, a.quest.depth, a.quest.prereqIDs = "future", a.depth, a.parents
            activeOrReady[a.id] = true
        end
    end
    local kept = {}
    for id, q in pairs(nodes) do
        if q.status == "active" or q.status == "ready" or q.status == "future" then
            kept[id] = q
        end
    end
    catalog = kept
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

local function findOrAddStop(stops, kind, p, threshold, phase)
    for _, s in ipairs(stops) do
        -- A source ID can have spawn points on opposite sides of a zone; merge by camp distance only.
        -- A follow-up at the same giver/camp must remain after its parent's hand-in.
        if s.kind == kind and s.phase == phase and distance(s.point, p) <= threshold then
            return s
        end
    end
    local s = newStop(kind, p, phase)
    stops[#stops + 1] = s
    return s
end

objectiveIsDone = function(entry, target)
    if not entry then return false end
    if entry.complete then return true end
    local objectives = ns.compat.objectives(entry)
    local terms = { string.lower(target.name or "") }
    for _, source in ipairs(target.sources or {}) do if source.name then terms[#terms + 1] = string.lower(source.name) end end
    local found, allDone, progress = false, true, nil
    for _, objective in ipairs(objectives) do
        local text = string.lower(objective.text or "")
        for _, term in ipairs(terms) do
            if #term > 2 and string.find(text, term, 1, true) then
                found = true
                if not objective.finished then allDone = false end
                if objective.have ~= nil and objective.need ~= nil then
                    progress = tostring(objective.have) .. "/" .. tostring(objective.need)
                end
                break
            end
        end
    end
    return found and allDone, found and progress -- Unknown matching stays visible so we do not hide work the quest log still needs.
end

local function targetSummary(target)
    local label = (target.kind == "kill" and "Kill " or target.kind == "loot" and "Collect "
        or target.kind == "object" and "Use " or "Visit ") .. (target.name or "objective")
    local bestRate, sourceName
    if target.kind == "loot" and target.itemID then
        for _, source in ipairs(target.sources or {}) do
            if source.kind == "npc" then
                local rate = questie().itemDropRate(target.itemID, source.id)
                if rate and (not bestRate or rate > bestRate) then bestRate, sourceName = rate, source.name end
            end
        end
    end
    if bestRate then label = label .. string.format(" from %s (%.1f%%)", sourceName or "a creature", bestRate) end
    return label
end

buildRoute = function()
    if Path then Path.cancelWalkEstimates() end
    route = {}
    nextStopID = 0
    local stops, questStops = {}, {}
    local quests = {}; for _, q in pairs(catalog) do quests[#quests + 1] = q end
    table.sort(quests, function(a, b) if a.depth ~= b.depth then return a.depth < b.depth end; return a.id < b.id end)

    for _, q in ipairs(quests) do
        local data, entry = q, q.entry
        local pickup, objectives, turnin = nil, {}, nil
        if q.status ~= "active" then
            local point, giver = nearestSource(data.starters or q.starterRows)
            point = point or q.starterPoint
            if point then
                pickup = findOrAddStop(stops, "pickup", point, TAKEIN_DISTANCE, q.depth)
                addTask(pickup, q, "Pick up " .. q.name .. (giver and giver.name and (" from " .. giver.name) or ""), giver and giver.name)
            end
        end
        local complete = entry and entry.complete
        if not complete then
            for _, target in ipairs(data.targets or {}) do
                local done, progress = objectiveIsDone(entry, target)
                if not done then
                    local point = nearestPoint(target.points)
                    if point then
                        local stop = findOrAddStop(stops, "objective", point, CLUSTER_DISTANCE, q.depth)
                        addTask(stop, q, targetSummary(target) .. (progress and (" (" .. progress .. ")") or ""),
                            target.name and ("the " .. target.name .. " area"))
                        objectives[#objectives + 1] = stop
                    end
                end
            end
        end
        local turnPoint, turner = nearestSource(data.turnIns)
        if turnPoint and (complete or q.canFinishHere) then
            turnin = findOrAddStop(stops, "turnin", turnPoint, TAKEIN_DISTANCE, q.depth)
            addTask(turnin, q, "Turn in " .. q.name .. (turner and turner.name and (" to " .. turner.name) or ""), turner and turner.name)
        end
        questStops[q.id] = { pickup = pickup, objectives = objectives, turnin = turnin }
        for _, stop in ipairs(objectives) do addDep(stop, pickup) end
        if turnin then
            if #objectives > 0 then for _, stop in ipairs(objectives) do addDep(turnin, stop) end
            else addDep(turnin, pickup) end
        end
        Work.checkpoint()
    end

    for _, q in ipairs(quests) do
        local own = questStops[q.id]
        for _, parentID in ipairs(q.prereqIDs or {}) do
            local parent = questStops[parentID]
            if parent then
                local terminal = parent.turnin
                if not terminal then
                    for _, obj in ipairs(parent.objectives or {}) do terminal = obj end
                    terminal = terminal or parent.pickup
                end
                addDep(own and own.pickup, terminal)
                if own and not own.pickup then
                    for _, obj in ipairs(own.objectives or {}) do addDep(obj, terminal) end
                    addDep(own.turnin, terminal)
                end
            end
        end
    end

    -- Outings connect each quest's giver, work sites and turn-in; shared stops and prerequisite edges join outings.
    local parent, stopByID = {}, {}
    for _, stop in ipairs(stops) do parent[stop] = stop; stopByID[stop.id] = stop end
    local function root(stop)
        if parent[stop] ~= stop then parent[stop] = root(parent[stop]) end
        return parent[stop]
    end
    local function join(a, b)
        if a and b then
            local ra, rb = root(a), root(b)
            if ra ~= rb then parent[rb] = ra end
        end
    end
    for _, q in pairs(questStops) do
        local first
        local function include(stop)
            if stop then if first then join(first, stop) else first = stop end end
        end
        include(q.pickup)
        for _, stop in ipairs(q.objectives or {}) do include(stop) end
        include(q.turnin)
    end
    for _, stop in ipairs(stops) do
        for depID in pairs(stop.deps) do join(stop, stopByID[depID]) end
    end
    local outings, outingList, outingByStop = {}, {}, {}
    for _, stop in ipairs(stops) do
        local r = root(stop)
        local outing = outings[r]
        if not outing then outing = { stops = {}, quests = {} }; outings[r] = outing; outingList[#outingList + 1] = outing end
        outing.stops[#outing.stops + 1] = stop
        outingByStop[stop] = outing
        for id in pairs(stop.quests) do outing.quests[id] = true end
    end
    for i, outing in ipairs(outingList) do
        outing.id = i
        for _, stop in ipairs(outing.stops) do stop.outingID = i end
    end

    local function isReady(stop, doneIDs)
        for depID in pairs(stop.deps) do if not doneIDs[depID] then return false end end
        return true
    end
    local function outingCost(outing, remainingSet, doneIDs, origin)
        local first, firstDistance
        for _, stop in ipairs(outing.stops) do
            if remainingSet[stop] and isReady(stop, doneIDs) then
                local d = origin and distance(origin, stop.point) or 0
                if not firstDistance or d < firstDistance then first, firstDistance = stop, d end
            end
        end
        if not first then return nil end
        local total, at, unvisited = firstDistance, first.point, {}
        for _, stop in ipairs(outing.stops) do
            if remainingSet[stop] and stop ~= first then unvisited[#unvisited + 1] = stop end
        end
        -- Nearest-neighbour estimate covers the full outing but is advisory; dependency order is enforced below.
        while #unvisited > 0 do
            local bestIndex, bestDistance
            for i, stop in ipairs(unvisited) do
                local d = distance(at, stop.point)
                if not bestDistance or d < bestDistance then bestIndex, bestDistance = i, d end
            end
            local nextStop = table.remove(unvisited, bestIndex)
            total = total + (bestDistance == math.huge and 0 or bestDistance)
            at = nextStop.point
            Work.checkpoint()
        end
        local count = 0; for _ in pairs(outing.quests) do count = count + 1 end
        return total / math.sqrt(math.max(1, count))
    end

    local remaining, remainingSet, doneIDs = {}, {}, {}
    for _, stop in ipairs(stops) do remaining[#remaining + 1] = stop; remainingSet[stop] = true end
    local pos, currentOuting = playerPoint, nil
    while #remaining > 0 do
        local bestIndex, bestDistance
        local function consider(i, stop)
            if isReady(stop, doneIDs) then
                local d = pos and distance(pos, stop.point) or 0
                if not bestDistance or d < bestDistance then bestIndex, bestDistance = i, d end
            end
        end
        if currentOuting then
            local hasRemaining = false
            for i, stop in ipairs(remaining) do
                if outingByStop[stop] == currentOuting then
                    hasRemaining = true
                    consider(i, stop)
                end
            end
            if not hasRemaining then currentOuting = nil end
        end
        if not currentOuting then
            local bestOuting, bestScore
            for _, outing in ipairs(outingList) do
                local score = outingCost(outing, remainingSet, doneIDs, pos)
                if score and (not bestScore or score < bestScore) then bestOuting, bestScore = outing, score end
            end
            currentOuting = bestOuting
            if currentOuting then
                bestIndex, bestDistance = nil, nil
                for i, stop in ipairs(remaining) do
                    if outingByStop[stop] == currentOuting then consider(i, stop) end
                end
            end
        end
        if not bestIndex then -- Bad or incomplete prerequisite data must not freeze the plan.
            bestIndex = 1
            currentOuting = outingByStop[remaining[bestIndex]]
        end
        local stop = table.remove(remaining, bestIndex)
        remainingSet[stop], doneIDs[stop.id] = nil, true
        route[#route + 1] = stop
        if stop.point then pos = stop.point end
        Work.checkpoint()
    end

    if Path and playerPoint then
        Path.prioritizeFirstOuting(route, playerPoint, function(changed)
            if not changed then return end
            local oldKey = selectionLocked and route[selected] and stopIdentity(route[selected]) or nil
            selected = 1
            if selectionLocked and oldKey then
                for i, stop in ipairs(route) do
                    if stopIdentity(stop) == oldKey then selected = i; break end
                end
            end
            render()
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
    smallButton("?", 20, 30, 6, function(self)
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
    Guidance.clear()
    sessionActive = false
    generation = generation + 1
    Work.cancel("quest-plan")
    if Path then Path.cancelWalkEstimates() end
    loading = false
    if panel then panel:Hide() end
end

local function rebuildProgress(log, zone)
    Guidance.clear()
    local oldIndex, oldKey = selected, route[selected] and stopIdentity(route[selected])
    generation = generation + 1
    local token = generation
    if Path then Path.cancelWalkEstimates() end
    loading = true
    Work.start("quest-plan", function()
        for id, quest in pairs(catalog) do quest.entry = log[id] end
        buildRoute()
        selected = math.max(1, math.min(oldIndex, #route))
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

local function scheduleRefresh(force, zoneEntry)
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
ns.on("QUEST_WATCH_UPDATE", function() scheduleRefresh(false, false) end)
ns.on("UNIT_QUEST_LOG_CHANGED", function() scheduleRefresh(false, false) end)

function P.command(arg)
    arg = string.lower(arg or "")
    if arg == "off" then ns.setSetting("questPlanner", false)
    elseif arg == "hide" or arg == "close" then Guidance.clear(); panelDismissed = true; if panel then panel:Hide() end
    elseif arg == "on" then ns.setSetting("questPlanner", true); ns.print("quest planner is on")
    elseif arg == "next" then if selectStop(selected + 1) then P.pin() end
    elseif arg == "follow" then P.follow()
    elseif arg == "refresh" then P.refresh()
    else P.open() end
end
