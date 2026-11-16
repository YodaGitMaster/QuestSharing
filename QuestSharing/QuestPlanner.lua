-- QuestPlanner.lua: a prerequisite-aware, zone-local quest plan. Questie supplies facts; the player chooses the stops.
local ADDON, ns = ...
local P, U, S = {}, ns.optionalUI, ns.style
local Path = ns.questPlannerPath
ns.questPlanner = P

local MAX_FUTURE_LAYERS, SCAN_BATCH = 4, 120
local CLUSTER_DISTANCE, TAKEIN_DISTANCE = 0.065, 0.045
local catalog, route, selected, frameMap, playerPoint, plannedMap, loading, generation = {}, {}, 1, nil, nil, nil, false, 0
local selectionLocked = false
local panel, message, planScroll, planRows, planContent, emptyText, followButton
local buildGraph, buildRoute, render, selectStop, showPlanRows, stopIdentity
local nextStopID = 0
local PLAN_ROW_HEIGHT, PLAN_LIST_HEIGHT, PLAN_WIDTH = 56, 280, 320
local panelDismissed, refreshQueued, refreshForce, refreshZoneEntry = false, false, false, false
local lastLogMembers, lastLogStructure, lastLogProgress = nil, nil, nil

local function questie() return ns.questie end
local function distance(a, b)
    if not (a and b and a.x and a.y and b.x and b.y and a.map == b.map) then return math.huge end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function project(map, x, y)
    if not (map and x and y and frameMap) then return nil end
    if map == frameMap then return { map = frameMap, x = x, y = y } end
    if C_Map and C_Map.GetMapRectOnMap then
        local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, map, frameMap)
        if ok and left and right and top and bottom then
            return { map = frameMap, x = left + (right - left) * x, y = top + (bottom - top) * y }
        end
    end
end

local function pointForSpawn(spawn)
    if not spawn or spawn.dungeon or not spawn.map then return nil end
    return project(spawn.map, (spawn.x or 0) / 100, (spawn.y or 0) / 100)
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
    if Path then Path.cancelWalkEstimates() end
    loading, catalog, route, selected, plannedMap = false, {}, {}, 1, nil
    selectionLocked = false
    if message then message:SetText(reason) end
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

local function newCandidate(id, starter, log)
    local data = questie().plannerQuest(id)
    if not data then return nil end
    data.status = statusFor(id, log)
    data.starterPoint = nearestPoint(starter)
    data.starterRows = starter or {}
    data.entry = log[id]
    data.depth = 0
    data.prereqIDs = {}
    return data
end

local function scan()
    generation = generation + 1
    local thisGeneration = generation
    local q = questie()
    local zone, locationError, zoneMap = currentZone()
    if not zone then
        clearPlan(locationError)
        return
    end
    local ids = q.ids("quest")
    if type(ids) ~= "table" then
        clearPlan("Questie needs a recent QuestieDB with quest IDs.")
        return
    end
    local log = ns.compat.entryMap()
    lastLogMembers, lastLogStructure, lastLogProgress = questLogState(log)
    local keepSelection = plannedMap == zoneMap
    local oldSelected = selected
    local oldSelectedKey = keepSelection and route[selected] and stopIdentity(route[selected]) or nil
    local inZone, index = {}, 1
    loading, catalog, route, selected, plannedMap = true, {}, {}, 1, zoneMap
    if message then message:SetText("Looking through Questie quests for this area…") end
    if emptyText then emptyText:SetText("Checking quest locations…") end
    if planContent then planScroll:SetVerticalScroll(0); showPlanRows() end

    local function batch()
        if thisGeneration ~= generation or not loading then return end
        local currentName, locationError, currentMap = currentZone()
        if not currentName then
            clearPlan(locationError)
            return
        end
        if currentMap ~= zoneMap then
            scan()
            return
        end
        local stopAt = math.min(#ids, index + SCAN_BATCH - 1)
        while index <= stopAt do
            local id = ids[index]; index = index + 1
            local active = log[id] ~= nil
            local starters, startPoint, candidate
            if active then
                candidate = newCandidate(id, {}, log)
            else
                starters = q.plannerStarters(id)
                startPoint = nearestPoint(starters)
                if startPoint and q.questComplete(id) ~= true then
                    candidate = newCandidate(id, starters, log)
                end
            end
            if candidate and (active or candidate.status == "ready" or candidate.status == "any" or candidate.status == "all") then
                inZone[id] = candidate
            end
        end
        if index <= #ids then
            if message then message:SetText(string.format("Checking %s quest data… %d / %d", zone, math.min(index - 1, #ids), #ids)) end
            ns.after(0.02, batch)
            return
        end
        if thisGeneration ~= generation then return end
        catalog = inZone
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
    end
    ns.after(0.01, batch)
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
                        if activeOrReady[parentID] and (parent.depth or 0) < layer then
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
                    if activeOrReady[parentID] and (parent.depth or 0) < layer then
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

local function newStop(kind, p)
    nextStopID = nextStopID + 1
    return { id = nextStopID, kind = kind, point = p, quests = {}, tasks = {}, deps = {}, done = false }
end

local function findOrAddStop(stops, kind, p, threshold)
    for _, s in ipairs(stops) do
        -- A source ID can have spawn points on opposite sides of a zone; merge by camp distance only.
        if s.kind == kind and distance(s.point, p) <= threshold then
            return s
        end
    end
    local s = newStop(kind, p)
    stops[#stops + 1] = s
    return s
end

local function objectiveIsDone(entry, target)
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
                pickup = findOrAddStop(stops, "pickup", point, TAKEIN_DISTANCE)
                pickup.tasks[#pickup.tasks + 1] = "Pick up " .. q.name .. (giver and giver.name and (" from " .. giver.name) or "")
                pickup.quests[q.id] = q.name
            end
        end
        local complete = entry and entry.complete
        if not complete then
            for _, target in ipairs(data.targets or {}) do
                local done, progress = objectiveIsDone(entry, target)
                if not done then
                    local point = nearestPoint(target.points)
                    if point then
                        local stop = findOrAddStop(stops, "objective", point, CLUSTER_DISTANCE)
                        stop.tasks[#stop.tasks + 1] = targetSummary(target) .. (progress and (" (" .. progress .. ")") or "")
                        stop.quests[q.id] = q.name
                        objectives[#objectives + 1] = stop
                    end
                end
            end
        end
        local turnPoint, turner = nearestSource(data.turnIns)
        if turnPoint then
            turnin = findOrAddStop(stops, "turnin", turnPoint, TAKEIN_DISTANCE)
            turnin.tasks[#turnin.tasks + 1] = "Turn in " .. q.name .. (turner and turner.name and (" to " .. turner.name) or "")
            turnin.quests[q.id] = q.name
        end
        questStops[q.id] = { pickup = pickup, objectives = objectives, turnin = turnin }
        for _, stop in ipairs(objectives) do addDep(stop, pickup) end
        if turnin then
            if #objectives > 0 then for _, stop in ipairs(objectives) do addDep(turnin, stop) end
            else addDep(turnin, pickup) end
        end
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
    return table.concat({ stop.kind, tostring(p.map), string.format("%.4f", p.x or 0), string.format("%.4f", p.y or 0),
        stopLabel(stop) }, "\31")
end

local function mapLine(stop)
    if not stop.point then return "Location unknown" end
    local p = stop.point
    return string.format("Map %s — %.1f, %.1f", tostring(p.map), p.x * 100, p.y * 100)
end

local function dockPanel()
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
    panel:SetMovable(false)
    panel:SetScript("OnDragStart", nil)
    panel:SetScript("OnDragStop", nil)
    panel:EnableMouse(true)
    message = U.text(panel, "", 12, 34, PLAN_WIDTH - 24)
    planScroll = CreateFrame("ScrollFrame", nil, panel)
    planScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -56)
    planScroll:SetWidth(PLAN_WIDTH - 20)
    planScroll:SetHeight(PLAN_LIST_HEIGHT)
    planScroll:EnableMouseWheel(true)
    planContent = CreateFrame("Frame", nil, planScroll)
    planContent:SetWidth(PLAN_WIDTH - 20)
    planContent:SetHeight(PLAN_LIST_HEIGHT)
    planScroll:SetScrollChild(planContent)
    emptyText = U.text(planContent, "", 8, 8, PLAN_WIDTH - 36)
    planScroll:SetScript("OnMouseWheel", function(self, delta)
        local pos = self:GetVerticalScroll() - delta * PLAN_ROW_HEIGHT
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), pos)))
    end)
    planRows = {}
    S.button(panel, "Refresh", 72, function() scan() end):SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 12)
    followButton = S.button(panel, "Follow with SPF", 126, function() P.follow() end)
    followButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 94, 12)
    followButton:SetScript("OnEnter", function(self)
        U.tip(self, "Walk this stop", { "Shortest Path Forever draws the route on your map and minimap.",
            "Following it replaces the route you are using now." })
    end)
    followButton:SetScript("OnLeave", function() U.hideTip() end)
    followButton:Hide()
    S.closeButton(panel, function() panelDismissed = true; panel:Hide() end)
    panel:SetScript("OnHide", function()
        panelDismissed = true
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

showPlanRows = function()
    if not planContent then return end
    if emptyText then if #route == 0 then emptyText:Show() else emptyText:Hide() end end
    for _, row in ipairs(planRows) do row:Hide() end
    for i, stop in ipairs(route) do
        local row = planRows[i]
        if not row then
            row = CreateFrame("Button", nil, planContent)
            row:SetHeight(PLAN_ROW_HEIGHT - 3)
            row.bg = S.fill(row, "BACKGROUND", 0.08, 0.1, 0.14, 0.96)
            row.bg:SetAllPoints(row)
            row.edge = S.fill(row, "BORDER", 0.33, 0.8, 1, 0.4)
            row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.edge:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            row.edge:SetHeight(1)
            row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 7, -4)
            row.title:SetWidth(PLAN_WIDTH - 36)
            row.title:SetJustifyH("LEFT")
            row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 7, -22)
            row.detail:SetWidth(PLAN_WIDTH - 36)
            row.detail:SetJustifyH("LEFT")
            row.detail:SetWordWrap(true)
            planRows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", planContent, "TOPLEFT", 0, -((i - 1) * PLAN_ROW_HEIGHT))
        row:SetWidth(PLAN_WIDTH - 20)
        local kind = stop.kind == "pickup" and "PICK UP" or stop.kind == "turnin" and "TURN IN" or "OBJECTIVES"
        local pointText = stop.point and string.format("%.1f, %.1f", stop.point.x * 100, stop.point.y * 100) or "location unknown"
        row.title:SetText(string.format("%02d  TRIP %d  ·  %s  ·  %s", i, stop.outingID or 1, kind, pointText))
        row.detail:SetText(rowTaskText(stop) .. " — " .. stopLabel(stop))
        row.bg:SetVertexColor(i == selected and 1.35 or 1, i == selected and 1.05 or 1, i == selected and 0.55 or 1)
        local rowIndex = i
        row:SetScript("OnClick", function() if selectStop(rowIndex) then P.pin() end end)
        row:SetEnabled(stop.point ~= nil)
        row:Show()
    end
    planContent:SetHeight(math.max(PLAN_LIST_HEIGHT, #route * PLAN_ROW_HEIGHT))
end

render = function(zone)
    if not planScroll then return end
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
            message:SetText(zone and string.format("%s • %d active • %d ready • %d later", zone, active, ready, future)
                or "Open this panel outdoors in a zone.")
        end
        if emptyText then
            emptyText:SetText((active + ready + future == 0) and "No active or eligible quests found in this zone."
                or "Quest data was found, but no route locations are mapped here.")
        end
        showPlanRows()
        return
    end
    selected = math.min(selected, #route)
    if message then
        message:SetText(string.format("%s • %d active • %d ready • %d later • %d stops",
            zone or "Current zone", active, ready, future, #route))
    end
    showPlanRows()
end

selectStop = function(index)
    if #route == 0 then return false end
    local zone, reason, map = currentZone()
    if not zone then clearPlan(reason); return false end
    if map ~= plannedMap then scan(); return false end
    selected = math.max(1, math.min(#route, index))
    selectionLocked = true
    render(zone)
    return true
end

function P.pin()
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
    scan()
end

function P.open()
    if not ns.db.questPlanner then ns.setSetting("questPlanner", true); return end
    panelDismissed = false
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
        generation = generation + 1
        loading = false
        clearPlan("Quest planner is off.")
        if panel then panel:Hide() end
    end
end

local function rebuildProgress(log, zone)
    local oldIndex, oldKey = selected, route[selected] and stopIdentity(route[selected])
    for id, quest in pairs(catalog) do quest.entry = log[id] end
    buildRoute()
    selected = math.max(1, math.min(oldIndex, #route))
    if oldKey then
        for i, stop in ipairs(route) do
            if stopIdentity(stop) == oldKey then selected = i; break end
        end
    end
    render(zone)
end

local function scheduleRefresh(force, zoneEntry)
    if not (ns.db and ns.db.questPlanner) then return end
    refreshForce = refreshForce or force
    refreshZoneEntry = refreshZoneEntry or zoneEntry
    if refreshQueued then return end
    refreshQueued = true
    ns.after(zoneEntry and 1.2 or 0.65, function()
        refreshQueued = false
        local mustRefresh, enteredZone = refreshForce, refreshZoneEntry
        refreshForce, refreshZoneEntry = false, false
        if not (ns.db and ns.db.questPlanner) then return end

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
        if mustRefresh or map ~= plannedMap or members ~= lastLogMembers
            or (loading and (structure ~= lastLogStructure or progress ~= lastLogProgress)) then
            scan()
        elseif structure ~= lastLogStructure or progress ~= lastLogProgress then
            lastLogMembers, lastLogStructure, lastLogProgress = members, structure, progress
            rebuildProgress(log, zone)
        end
    end)
end

ns.on("PLAYER_ENTERING_WORLD", function() scheduleRefresh(true, true) end)
ns.on("ZONE_CHANGED_NEW_AREA", function() scheduleRefresh(true, true) end)
ns.on("ZONE_CHANGED", function() scheduleRefresh(true, true) end)
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
    elseif arg == "hide" or arg == "close" then panelDismissed = true; if panel then panel:Hide() end
    elseif arg == "on" then ns.setSetting("questPlanner", true); ns.print("quest planner is on")
    elseif arg == "next" then if selectStop(selected + 1) then P.pin() end
    elseif arg == "follow" then P.follow()
    elseif arg == "refresh" then P.refresh()
    else P.open() end
end
