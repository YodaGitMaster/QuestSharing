-- QuestPlanner.lua: a prerequisite-aware, zone-local quest plan. Questie supplies facts; the player chooses the stops.
local ADDON, ns = ...
local P, U, S = {}, ns.optionalUI, ns.style
ns.questPlanner = P

local MAX_FUTURE_LAYERS, SCAN_BATCH = 4, 120
local CLUSTER_DISTANCE, TAKEIN_DISTANCE = 0.065, 0.045
local catalog, route, selected, frameMap, playerPoint, loading, generation = {}, {}, 1, nil, nil, false, 0
local window, body, setBody, message, previousButton, nextButton, pinButton
local buildGraph, buildRoute
local nextStopID = 0

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

local function currentZone()
    frameMap = nil
    playerPoint = nil
    local map, x, y = ns.compat.playerPos()
    if map then
        frameMap = map
        playerPoint = { map = map, x = x, y = y }
        local info = C_Map and U.call(C_Map.GetMapInfo, map)
        return info and info.name or ("map " .. tostring(map))
    end
    return nil
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
    local ids = q.ids("quest")
    if type(ids) ~= "table" then
        loading = false
        if message then message:SetText("Questie needs a recent QuestieDB with quest IDs.") end
        return
    end
    local zone = currentZone()
    local log = ns.compat.entryMap()
    local inZone, index = {}, 1
    loading, catalog, route, selected = true, {}, {}, 1
    if message then message:SetText("Looking through Questie quests for this area…") end

    local function batch()
        if thisGeneration ~= generation or not loading then return end
        local stopAt = math.min(#ids, index + SCAN_BATCH - 1)
        while index <= stopAt do
            local id = ids[index]; index = index + 1
            local active = log[id] ~= nil
            local done = not active and q.questComplete(id) == true
            if not done then
                local starters = q.plannerStarters(id)
                local startPoint = nearestPoint(starters)
                if active or startPoint then
                    local candidate = newCandidate(id, starters, log)
                    if candidate and (active or candidate.status == "ready" or candidate.status == "any" or candidate.status == "all") then
                        inZone[id] = candidate
                    end
                end
            end
        end
        if index <= #ids then
            if message then message:SetText(string.format("Reading nearby quests… %d / %d", math.min(index - 1, #ids), #ids)) end
            ns.after(0.02, batch)
            return
        end
        if thisGeneration ~= generation then return end
        catalog = inZone
        buildGraph(log)
        buildRoute()
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

local function findOrAddStop(stops, kind, p, threshold, sourceKey)
    for _, s in ipairs(stops) do
        if s.kind == kind and ((sourceKey and s.sourceKeys[sourceKey]) or distance(s.point, p) <= threshold) then
            if sourceKey then s.sourceKeys[sourceKey] = true end
            return s
        end
    end
    local s = newStop(kind, p); s.sourceKeys = {}
    if sourceKey then s.sourceKeys[sourceKey] = true end
    stops[#stops + 1] = s
    return s
end

local function objectiveIsDone(entry, target)
    if not entry then return false end
    if entry.complete then return true end
    local objectives = ns.compat.objectives(entry)
    local terms = { string.lower(target.name or "") }
    for _, source in ipairs(target.sources or {}) do if source.name then terms[#terms + 1] = string.lower(source.name) end end
    local found, allDone = false, true
    for _, objective in ipairs(objectives) do
        local text = string.lower(objective.text or "")
        for _, term in ipairs(terms) do
            if #term > 2 and string.find(text, term, 1, true) then
                found = true
                if not objective.finished then allDone = false end
                break
            end
        end
    end
    return found and allDone -- Unknown matching stays visible so we do not hide work the quest log still needs.
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
    route = {}
    nextStopID = 0
    local stops, questStops = {}, {}
    local quests = {}; for _, q in pairs(catalog) do quests[#quests + 1] = q end
    table.sort(quests, function(a, b) if a.depth ~= b.depth then return a.depth < b.depth end; return a.id < b.id end)

    for _, q in ipairs(quests) do
        local data, entry = q.data, q.entry
        local pickup, objectives, turnin = nil, {}, nil
        if q.status ~= "active" then
            local point = nearestPoint((data.starters or q.starterRows)) or q.starterPoint
            if point then
                pickup = findOrAddStop(stops, "pickup", point, TAKEIN_DISTANCE)
                pickup.tasks[#pickup.tasks + 1] = "Pick up " .. q.name
                pickup.quests[q.id] = q.name
            end
        end
        local complete = entry and entry.complete
        if not complete then
            for _, target in ipairs(data.targets or {}) do
                if not objectiveIsDone(entry, target) then
                    local point = nearestPoint(target.points)
                    if point then
                        local key
                        if #((target.sources) or {}) == 1 then
                            local source = target.sources[1]
                            key = source.kind .. ":" .. tostring(source.id)
                        end
                        local stop = findOrAddStop(stops, "objective", point, CLUSTER_DISTANCE, key)
                        stop.tasks[#stop.tasks + 1] = targetSummary(target)
                        stop.quests[q.id] = q.name
                        objectives[#objectives + 1] = stop
                    end
                end
            end
        end
        local turnPoint = nearestPoint(data.turnIns and (function()
            local p = {}; for _, s in ipairs(data.turnIns) do for _, pt in ipairs(s.spawns or {}) do p[#p + 1] = pt end end; return p
        end)())
        if turnPoint then
            turnin = findOrAddStop(stops, "turnin", turnPoint, TAKEIN_DISTANCE)
            turnin.tasks[#turnin.tasks + 1] = "Turn in " .. q.name
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

    -- Stable nearest-ready-stop ordering: prerequisite edges always win, distance only chooses among legal steps.
    local remaining = {}; for _, s in ipairs(stops) do remaining[#remaining + 1] = s end
    local pos = playerPoint
    while #remaining > 0 do
        local bestIndex, bestScore
        for i, s in ipairs(remaining) do
            local ready = true
            for depID in pairs(s.deps) do
                local found = false; for _, done in ipairs(route) do if done.id == depID then found = true; break end end
                if not found then ready = false; break end
            end
            if ready then
                local d = pos and distance(pos, s.point) or 0
                local score = d + (s.kind == "turnin" and 0.005 or 0)
                if not bestScore or score < bestScore then bestIndex, bestScore = i, score end
            end
        end
        if not bestIndex then -- Bad or incomplete prerequisite data must not freeze the plan.
            bestIndex = 1
        end
        local stop = table.remove(remaining, bestIndex)
        route[#route + 1] = stop
        if stop.point then pos = stop.point end
    end
end

local function stopLabel(stop)
    local unique, names = {}, {}
    for id, name in pairs(stop.quests) do if not unique[id] then unique[id] = true; names[#names + 1] = name end end
    table.sort(names)
    return table.concat(names, ", ")
end

local function mapLine(stop)
    if not stop.point then return "Location unknown" end
    local p = stop.point
    return string.format("Map %s — %.1f, %.1f", tostring(p.map), p.x * 100, p.y * 100)
end

local function render(zone)
    if not setBody then return end
    if #route == 0 then
        setBody("No nearby quests were found. Check that Questie and QuestieDB are loaded, and that this map has Questie locations.")
        if message then message:SetText(zone and ("No plan found for " .. zone) or "Your current map position is unavailable.") end
        return
    end
    selected = math.min(selected, #route)
    local lines = {}
    lines[#lines + 1] = "Plan for " .. (zone or "your current area") .. " — straight map distance is an estimate, not a walkable path."
    lines[#lines + 1] = "Quests are grouped when the same camp can advance them, then by nearby map points."
    lines[#lines + 1] = ""
    for i = 1, math.min(#route, 18) do
        local stop = route[i]
        local kind = stop.kind == "pickup" and "PICK UP" or stop.kind == "turnin" and "TURN IN" or "OBJECTIVES"
        lines[#lines + 1] = string.format("%s %02d  %s", i == selected and ">" or " ", i, kind)
        if stop.point then lines[#lines + 1] = "    " .. mapLine(stop) end
        if stop.kind == "objective" and #stop.tasks > 1 then
            lines[#lines + 1] = "    Shared camp: work for " .. stopLabel(stop)
        else
            lines[#lines + 1] = "    " .. stopLabel(stop)
        end
        for _, task in ipairs(stop.tasks) do lines[#lines + 1] = "    • " .. task end
    end
    if #route > 18 then lines[#lines + 1] = string.format("…and %d more stops", #route - 18) end
    setBody(table.concat(lines, "\n"))
    if message then message:SetText(string.format("%d stops • step %d of %d • %s", #route, selected, #route, stopLabel(route[selected]))) end
    if previousButton then previousButton:SetEnabled(selected > 1) end
    if nextButton then nextButton:SetEnabled(selected < #route) end
end

local function selectStop(index)
    if #route == 0 then return end
    selected = math.max(1, math.min(#route, index))
    render(currentZone())
end

function P.pin()
    local stop = route[selected]
    if not stop or not stop.point then return ns.print("this stop has no map location") end
    local p = stop.point
    if not ns.compat.setWaypoint(p.map, p.x, p.y) then
        ns.print("the game cannot set a waypoint here; " .. mapLine(stop))
    end
end

function P.refresh()
    if not ns.db.questPlanner then return ns.print("turn on Quest planner in Extra tools first") end
    scan()
end

function P.open()
    if not ns.db.questPlanner then ns.setSetting("questPlanner", true) end
    if not window then
        window = U.window("QuestSharingPlanner", 780, 560, "Quest plan")
        if not window then return ns.print("this client cannot open the quest plan window") end
        U.text(window, "A suggested order for quest givers, shared camps and turn-ins.", 18, 40, 700)
        message = U.text(window, "", 18, 60, 720)
        body, setBody = U.scrollText(window, 18, 86, 744, 390)
        local SBtn = function(text, width, x, fn) local b = S.button(window, text, width, fn); b:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", x, 24); return b end
        previousButton = SBtn("Previous", 90, 18, function() selectStop(selected - 1) end)
        nextButton = SBtn("Next", 90, 116, function() selectStop(selected + 1) end)
        pinButton = SBtn("Set waypoint", 120, 214, P.pin)
        SBtn("Refresh plan", 110, 342, function() scan() end)
        SBtn("Close", 72, 460, function() window:Hide() end)
        window:SetScript("OnHide", function() generation = generation + 1; loading = false end)
    end
    window:Show()
    scan()
end

function P.command(arg)
    arg = string.lower(arg or "")
    if arg == "off" then ns.setSetting("questPlanner", false); if window then window:Hide() end
    elseif arg == "on" then ns.setSetting("questPlanner", true); ns.print("quest planner is on; use /qs plan to open it")
    elseif arg == "next" then selectStop(selected + 1); P.pin()
    elseif arg == "refresh" then P.refresh()
    else P.open() end
end
