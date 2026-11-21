-- QuestPlanner.lua: a prerequisite-aware, zone-local quest plan. Questie supplies facts; the player chooses the stops.
local ADDON, ns = ...
ns.inModule("guide")          -- Modules.lua: Settings > General > Tools can switch this off
local P, U, S = {}, ns.optionalUI, ns.style
local Path = ns.questPlannerPath
local Work = ns.dataWork
local Guidance = ns.questGuidance
ns.questPlanner = P

P.levelScope = "all"

local function emptyCoverage()
    -- skipped is a count per reason, not a list: those quests were ruled out by one cheap read each (see scopeSkip)
    return { external = {}, unknown = {}, blocked = {}, repeatable = {}, completed = {}, filtered = {}, skipped = {} }
end
local coverage = emptyCoverage()
function P.coverage() return coverage end
-- Camp and stop radii in yards, converted per map with C_Map.GetMapWorldSize. Map fractions are the fallback
-- when a map has no known size: 0.045 of Dun Morogh is ~220 yd, which merged NPCs a player sees as two stops.
local CLUSTER_YARDS, TAKEIN_YARDS = 100, 45
local CLUSTER_DISTANCE, TAKEIN_DISTANCE = 0.065, 0.045
local mapYards = {}
local function yardScale(map)
    if not map then return nil end
    local cached = mapYards[map]
    if cached == nil then
        local w, h
        if C_Map and type(C_Map.GetMapWorldSize) == "function" then
            local ok, a, b = pcall(C_Map.GetMapWorldSize, map)
            if ok then w, h = a, b end
        end
        cached = (type(w) == "number" and w > 0 and type(h) == "number" and h > 0 and w < math.huge and h < math.huge)
            and { w, h } or false
        mapYards[map] = cached
    end
    return cached or nil
end
local catalog, route, selected, frameMap, playerPoint, plannedMap, loading, generation = {}, {}, 1, nil, nil, nil, false, 0
local selectionLocked = false
local panel, message, planScroll, planRows, planContent, emptyText, followButton, campsButton
local previousButton, nextButton, stepCounter, modeButton, lockButton, waypointButton, guidePosition, busyButton
local guideExpanded, guideLocked = true, false
local sessionActive, zoneQuestIDs, zoneOrder = false, {}, {}
local zoneScope = {}  -- per cached id list: the level it was scoped for (a level-up makes new quests reachable) and what it skipped
local buildGraph, buildRoute, render, selectStop, showPlanRows, stopIdentity, objectiveIsDone, scheduleRefresh, rebuildProgress
local targetLocation
local nextStopID = 0
local PLAN_ROW_HEIGHT, PLAN_LIST_HEIGHT, PLAN_WIDTH = 56, 280, 320
local panelDismissed, refreshQueued, refreshForce, refreshZoneEntry = false, false, false, false
local lastLogMembers, lastLogStructure, lastLogProgress = nil, nil, nil
local panelMoved, lastLevelStats = false, { localCount = 0, below = 0, above = 0, eligible = 0, unknown = 0 }
local lastPlanOptions

local function questie() return ns.questie end

-- What the guide says when Questie cannot list quests: what is wrong, what to do, and how to check.
local function questieProblem()
    local why = ns.questie and ns.questie.whyMissing and ns.questie.whyMissing()
    local check = " Type /qs questie to check."
    if not why then return "Update Questie: this version cannot list quests for the Quest guide." .. check end
    if why:find("^needs the Questie addon") then
        return "Install or enable Questie (both folders: Questie and QuestieDB), then /reload." .. check
    end
    return "The Quest guide cannot read Questie: " .. (why:gsub("%s*%- /qs questie.*$", "")) .. "." .. check
end

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
-- Classic-era XP needed to go from level i to i + 1. The current level uses UnitXPMax; later levels use this table,
-- so the route can count on quests that unlock a few levels ahead while you quest (Coldridge Valley: level 1 -> 4).
local XP_TO_NEXT = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000,
    17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500,
    58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100,
    135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }
local LEVEL_AHEAD = 3 -- quests at most this many levels above you can join the route when quest XP reaches them
-- The level reached after earning `gain` more XP from (level, xp of xpMax). Unknown XP: no level is assumed.
local function levelAfter(level, xp, xpMax, gain)
    if not (finite(level) and finite(xp) and finite(xpMax) and xpMax > 0) then return level end
    xp = xp + gain
    local need = xpMax
    while need and xp >= need do
        xp, level = xp - need, level + 1
        need = XP_TO_NEXT[level]
    end
    return level
end
local function distance(a, b)
    if not (a and b and a.x and a.y and b.x and b.y and a.map == b.map) then return math.huge end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
-- True when two points on one map are within `yards` (or `fraction` of the map when its size is unknown).
local function within(a, b, yards, fraction)
    if not (a and b and a.x and a.y and b.x and b.y and a.map == b.map) then return false end
    local scale = yardScale(a.map)
    if not scale then return distance(a, b) <= fraction end
    local dx, dy = (a.x - b.x) * scale[1], (a.y - b.y) * scale[2]
    return dx * dx + dy * dy <= yards * yards
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
    if not map then return nil, "Open the Quest guide outdoors, in a mapped zone." end
    local info = C_Map and U.call(C_Map.GetMapInfo, map)
    local isCity = C_Map and C_Map.IsCityMap and U.call(C_Map.IsCityMap, map)
    if isCity then return nil, "The Quest guide only works in outdoor zones, not towns or cities." end
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    if not info or info.mapType ~= zoneType then
        return nil, "Open the Quest guide in an outdoor zone, not on a town, dungeon, or continent map."
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

-- Questie files each quest under one zone (positive area ID) or a category (negative: class, profession,
-- event). That filing decides membership; a spawn that happens to be here does not. An unresolved filing
-- (no ZoneDB, unmapped area) is "unknown" and keeps the location rules.
local function zoneMembership(id, cache)
    local area = tonumber((questie().get("quest", id, "zoneOrSort")))
    if not area or area == 0 then return "unknown" end
    if area < 0 then
        -- Class quests are filed under the class, not a zone. One you can take (race/class gates ran already) is judged
        -- by where its giver and hand-in are, like an unfiled quest: the gnome mage's Glyphic Memorandum is in Anvilmar.
        if (tonumber((questie().get("quest", id, "requiredClasses"))) or 0) > 0 then return "unknown" end
        return "other", "Class, profession or event quest"
    end
    local map = questie().uiMapOf(area)
    if not map then return "unknown" end
    local known = cache and cache[map]
    if known then return known[1], known[2] end
    local result, reason, step = "other", nil, map
    for _ = 1, 12 do
        if step == frameMap then result = "here"; break end
        local info = U.call(C_Map and C_Map.GetMapInfo, step)
        step = info and info.parentMapID
        if not step or step == 0 then break end
    end
    if result == "other" then
        local info = U.call(C_Map and C_Map.GetMapInfo, map)
        reason = "Belongs to " .. (info and info.name or ("another zone (map " .. tostring(map) .. ")"))
    end
    if cache then cache[map] = { result, reason } end
    return result, reason
end

local SKIP_TEXT = { character = "other race, faction or class", level = "needs a higher level than the next one",
    overlevel = "past its maximum level", continent = "filed under a zone on another continent" }

local function continentOf(map, cache)
    if cache[map] ~= nil then return cache[map] or nil end
    local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
    local found, id = false, map
    for _ = 1, 12 do
        local info = U.call(C_Map and C_Map.GetMapInfo, id)
        if type(info) ~= "table" then break end
        if info.mapType == continentType then found = id; break end
        id = info.parentMapID
        if not id or id == 0 then break end
    end
    cache[map] = found
    return found or nil
end

-- One cheap read per quest, before any starter or spawn is read: ids this character, level or continent can't use
-- never get their big tables loaded. Unknown data keeps the quest. Quests in the log are never skipped.
local function scopeSkip(id, me, continents)
    local why = questie().questGate(id, { raceMask = me.raceMask, classMask = me.classMask, level = me.level, slack = LEVEL_AHEAD })
    if why then return why end
    local area = tonumber((questie().get("quest", id, "zoneOrSort")))
    if area and area > 0 then
        local map = questie().uiMapOf(area)
        local here, there = continentOf(frameMap, continents), map and continentOf(map, continents)
        if here and there and here ~= there then return "continent" end
    end
end

-- "412 other race, faction or class, 230 needs a higher level ...", or nil when nothing was skipped
local function skippedText()
    local parts = {}
    for _, reason in ipairs({ "character", "level", "overlevel", "continent" }) do
        local n = coverage.skipped[reason]
        if n and n > 0 then parts[#parts + 1] = n .. " " .. SKIP_TEXT[reason] end
    end
    if #parts > 0 then return "Not read (one cheap check each): " .. table.concat(parts, ", ") end
end

-- The game flags a finished quest complete; one with no objectives at all (a breadcrumb or delivery)
-- is ready as soon as it is in the log.
local function readyToHandIn(entry, data)
    if not entry then return false end
    if entry.complete then return true end
    return #(data.targets or {}) == 0 and #ns.compat.objectives(entry) == 0
end

local function newCandidate(id, starter, log, data, membership, zoneReason)
    local turnPoint = nearestSource(data.turnIns)
    local ready = readyToHandIn(log[id], data)
    if log[id] and not turnPoint and not nearestSource(data.starters) then
        -- A log quest with nothing on this map stays out of this zone's report.
        local associated = membership == "here"
        for _, target in ipairs(data.targets) do
            if not associated and nearestPoint(target.points) then associated = true; break end
        end
        if not associated then return end
    end
    if membership == "other" and not (log[id] and ready and turnPoint) then
        coverage.external[id] = (zoneReason or "Belongs to another zone")
            .. (log[id] and "; only its hand-in here, once ready, is planned" or "")
        return
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
            if not (level and data.requiredLevel > level and data.requiredLevel <= level + LEVEL_AHEAD and finite(currentXP) and
                finite(nextXP) and nextXP > currentXP and nextXP > 0) then
                coverage.blocked[id] = reason .. "; recheck on level-up"
                return
            end
            coverage.unknown[id] = reason .. "; the route counts on reaching that level with earlier quests"
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
                    coverage.blocked[id] = "No camp here for " .. (target.name or target.kind) .. ", only a few stray spawns"
                elseif #target.points > 0 then coverage.external[id] = "Objective outside this zone: " .. (target.name or target.kind)
                else coverage.unknown[id] = "Objective location unknown: " .. (target.name or target.kind) end
            end
        end
    end
    if not turnPoint then
        if #data.turnIns > 0 then
            local mapped
            for _,source in ipairs(data.turnIns) do if #(source.spawns or {}) > 0 then mapped=true end end
            if mapped then coverage.external[id] = "Hand-in is in another zone"
            else coverage.unknown[id] = "Hand-in location unknown" end
        else coverage.unknown[id] = "No known hand-in" end
    end
    data.canFinishHere = allWorkLocal and turnPoint ~= nil
    if data.entry then
        if not (ready and turnPoint) and not localWork then return end
    elseif not allWorkLocal or (#data.turnIns > 0 and not turnPoint) then
        return
    end
    if status ~= "ready" and status ~= "active" and status ~= "any" and status ~= "all" and status ~= "parent" and status ~= "level" and status ~= "reputation" then
        if status == nil or status == "unknown" then coverage.unknown[id] = "Not known whether you can take it"
        else coverage.blocked[id] = detail or (status == "exclusive" and "Exclusive quest already chosen"
            or status == "character" and "Class, race or faction requirement" or "A character or world requirement is unmet") end
        return
    end
    data.depth, data.prereqIDs, data.prereqKinds = 0, {}, {}
    return data
end

-- In a mine, cave, town or dungeon of the planned zone the plan stays on screen; it carries on back outside.
local plannedZoneName, pausedOutside
local function keepOutside(reason)
    pausedOutside = true
    if message then message:SetText((plannedZoneName or "Quest guide") .. " (paused: " .. tostring(reason or "not outdoors") .. ")") end
end

local function scan(rediscover)
    local zone, locationError, zoneMap = currentZone()
    if not zone and plannedMap and #route > 0 then keepOutside(locationError); return end
    -- A replan of the same zone keeps showing the current steps until the new route is ready (no blank list).
    local sameZone = zone and plannedMap == zoneMap and #route > 0
    if not sameZone then Guidance.clear() end
    if P.cancelEstimate then P.cancelEstimate() end
    coverage = emptyCoverage()
    generation = generation + 1
    Work.cancel("quest-plan")
    local thisGeneration = generation
    local q = questie()
    if not zone then
        clearPlan(locationError)
        return
    end
    pausedOutside, plannedZoneName = false, zone
    local log = ns.compat.entryMap()
    lastLogMembers, lastLogStructure, lastLogProgress = questLogState(log)
    if plannedMap ~= zoneMap then selectionLocked = false end
    local keepSelection = selectionLocked and plannedMap == zoneMap
    local oldSelected = selected
    local oldSelectedKey = keepSelection and route[selected] and stopIdentity(route[selected]) or nil
    local inZone, index = {}, 1
    local me, continents = q.me(), {}
    -- A zone's quest list is saved to disk per character scope (race, class, level), so a new session skips the scan.
    local savedKey = table.concat({ tostring(zoneMap), tostring(me.raceMask), tostring(me.classMask), tostring(me.level) }, "|")
    if rediscover or not (zoneScope[zoneMap] and zoneScope[zoneMap].level == me.level) then zoneQuestIDs[zoneMap] = nil end
    if not rediscover and not zoneQuestIDs[zoneMap] then
        local saved = Work.saved("guideZones", savedKey)
        if saved and type(saved.ids) == "table" then
            zoneQuestIDs[zoneMap], zoneScope[zoneMap] = saved.ids, { level = me.level, skipped = saved.skipped or {} }
        end
    end
    local discovered = zoneQuestIDs[zoneMap]
    if discovered then coverage.skipped = zoneScope[zoneMap].skipped end
    local discoveredIDs, sourceCache, zoneCache = {}, {}, {}
    local levelStats = { localCount = 0, below = 0, above = 0, eligible = 0, unknown = 0 }
    lastLevelStats = levelStats
    loading, catalog, plannedMap = true, {}, zoneMap
    if message then message:SetText(zone) end
    if not sameZone then
        route, selected = {}, 1
        if emptyText then emptyText:SetText("Checking quest locations…") end
        if planContent then planScroll:SetVerticalScroll(0); showPlanRows() end
    end

    Work.start("quest-plan", function()
        local ids
        if discovered then
            ids = {}; local seen = {}
            for _, id in ipairs(discovered) do ids[#ids + 1] = id; seen[id] = true end
            for id in pairs(log) do if not seen[id] then ids[#ids + 1] = id end end
        else
            ids = q.ids("quest")
        end
        if type(ids) ~= "table" then clearPlan(questieProblem()); return end
        while index <= #ids do
            if index % 20 == 1 then
                local currentName, locationError, currentMap = currentZone()
                if not currentName then clearPlan(locationError); return end
                if currentMap ~= zoneMap then scan(); return end
            end
            local id = ids[index]; index = index + 1
            local active = log[id] ~= nil
            local skip = not active and not discovered and scopeSkip(id, me, continents)
            if skip then
                coverage.skipped[skip] = (coverage.skipped[skip] or 0) + 1
            else
                local membership, zoneReason = zoneMembership(id, zoneCache)
                local starters, startPoint, zoneAssociated
                if not discovered or not active then
                    starters = q.plannerStarters(id, sourceCache)
                    startPoint = nearestSource(starters)
                    if not startPoint then zoneAssociated = membership == "here" end
                    if not discovered and (startPoint or zoneAssociated) then discoveredIDs[#discoveredIDs + 1] = id end
                end
                if startPoint and not active and membership == "other" then
                    coverage.external[id] = zoneReason
                elseif active or startPoint then
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
                        coverage.filtered[id] = "Not green or yellow for your level"
                    else
                        data.band = band
                        local candidate = newCandidate(id, starters or {}, log, data, membership, zoneReason)
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
            end
            Work.yield()
        end
        if not discovered then
            zoneQuestIDs[zoneMap], zoneScope[zoneMap] = discoveredIDs, { level = me.level, skipped = coverage.skipped }
            Work.save("guideZones", savedKey, { ids = discoveredIDs, skipped = coverage.skipped }, 40)
            for i = #zoneOrder, 1, -1 do if zoneOrder[i] == zoneMap then table.remove(zoneOrder, i) end end
            zoneOrder[#zoneOrder + 1] = zoneMap -- every zone's quest list is kept for the session (Purge frees them)
        end
        if thisGeneration ~= generation then return end
        local currentXP, nextXP = U.call(UnitXP, "player"), U.call(UnitXPMax, "player")
        local level = tonumber(U.call(UnitLevel, "player"))
        -- Quest XP opens later levels, whose quests add more XP: repeat until no new quest unlocks.
        local reached, reachable = level, {}
        repeat
            local earned, grew = 0, false
            for id, candidate in pairs(inZone) do
                if candidate.status ~= "level" or reachable[id] then earned = earned + (tonumber(candidate.xp) or 0) end
            end
            reached = levelAfter(level, currentXP, nextXP, earned)
            for id, candidate in pairs(inZone) do
                if candidate.status == "level" and not reachable[id] and finite(reached)
                    and (tonumber(candidate.requiredLevel) or 0) <= reached then reachable[id], grew = true, true end
            end
        until not grew
        for id, candidate in pairs(inZone) do
            if candidate.status == "level" and not reachable[id] then
                inZone[id] = nil
                coverage.unknown[id] = nil
                local need = finite(nextXP) and finite(currentXP) and nextXP > currentXP
                    and (" (" .. tostring(nextXP - currentXP) .. " XP to next level)") or ""
                coverage.blocked[id] = "Requires level " .. tostring(candidate.requiredLevel)
                    .. need .. "; the quests here do not give enough XP to reach it"
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
        if P.repGates then P.lastRepGates = P.repGates() end
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
        coverage.blocked[id] = "Needs an earlier quest that cannot be done in this zone"
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
local readSettings                      -- saved goal settings -> goal (defined with the other goal functions)
local goalLine, resolveChosen          -- "Quest XP/hour • Every level"; chosen quest names -> IDs (same place)
local report, previousPlan, previousMap, lastOrigin, plannedSpeed
local waitingAt = {}
-- Set by "Camp busy": { key = objective, point = busy camp, name = what is farmed there }. Printed once the new route
-- shows which camp the guide uses instead.
local busyNotice
-- The camp each objective (stop.key) last used, per map. A camp forced by "Camp busy" is never recorded, so the
-- camp chosen before the mark returns when the wait ends; "Clear camp wait" forgets them all.
local siteMemory = { map = nil, sites = {} }
-- The last completed background local search; it only runs again when the plan's inputs really change.
local refinedPlan
local REFINE_MOVE = 0.1 -- map units of movement after which the local search runs again
local function campKey(p)
    return string.format("%d/%.5f/%.5f", p.map, p.x, p.y)
end

function P.cancelEstimate()
    Work.cancel("quest-improve")
    report = nil
    lastPlanOptions = nil
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
    if target.kind == "loot" and source and source.kind == "object" then
        -- A world object (flower, chest, crate) gives the item outright: no drop chance, and
        -- "Heavenly Bloom from Heavenly Bloom" says nothing.
        text = "Pick up " .. (target.name or "item")
        if source.name and source.name ~= target.name then text = text .. " from " .. source.name end
    elseif target.kind == "loot" and source and source.name then
        text = text .. " from " .. source.name
        if probability then text = text .. string.format(" (%.2g%%)", probability * 100) end
    end
    return text
end

-- QuestieDB lists every spawn separately, and common mobs have lone spawns all over a zone. Spawns group into
-- camps: the densest spawn not yet taken seeds a camp of the free spawns within CLUSTER_DISTANCE, and the
-- member nearest the camp's centre marks it. Camps never depend on where the player stands.
local REAL_CAMP = 3
local MAX_CAMP_CHOICES = 4
local IMPROVE_STEPS = 250000 -- local-search budget in simulated actions (background, after the first route shows)
local function groupCamps(list)
    -- Work in yards when the spawns' map has a known size, so a camp is the same size on a small and a large map.
    local first = list[1] and list[1].point
    local scale = first and yardScale(first.map)
    local sx_, sy_, radius = 1, 1, CLUSTER_DISTANCE
    if scale then sx_, sy_, radius = scale[1], scale[2], CLUSTER_YARDS end
    local r2, cells = radius * radius, {}
    for i, s in ipairs(list) do
        s.ux, s.uy = s.x * sx_, s.y * sy_
        s.cx, s.cy = math.floor(s.ux / radius), math.floor(s.uy / radius)
        local key = s.cx .. ":" .. s.cy
        cells[key] = cells[key] or {}
        table.insert(cells[key], i)
    end
    local function around(s)
        local found = {}
        for cx = s.cx - 1, s.cx + 1 do
            for cy = s.cy - 1, s.cy + 1 do
                for _, j in ipairs(cells[cx .. ":" .. cy] or {}) do
                    local dx, dy = list[j].ux - s.ux, list[j].uy - s.uy
                    if dx * dx + dy * dy <= r2 then found[#found + 1] = j end
                end
            end
        end
        return found
    end
    local order = {}
    for i, s in ipairs(list) do
        s.density, order[i] = #around(s), i
        if i % 16 == 0 then Work.checkpoint() end
    end
    table.sort(order, function(a, b)
        if list[a].density ~= list[b].density then return list[a].density > list[b].density end
        return a < b
    end)
    local taken, camps = {}, {}
    for n, i in ipairs(order) do
        if not taken[i] then
            local members, sx, sy = {}, 0, 0
            for _, j in ipairs(around(list[i])) do
                if not taken[j] then
                    taken[j], members[#members + 1] = true, list[j]
                    sx, sy = sx + list[j].x, sy + list[j].y
                end
            end
            local cx, cy, mark, best = sx / #members, sy / #members, nil, nil
            for _, m in ipairs(members) do
                local d = (m.x - cx) * (m.x - cx) + (m.y - cy) * (m.y - cy)
                if not best or d < best then mark, best = m, d end
            end
            camps[#camps + 1] = { mark = mark, members = members }
        end
        if n % 16 == 0 then Work.checkpoint() end
    end
    return camps
end

-- An objective's default place is the nearest real local camp; the other real camps are returned as
-- alternatives the optimizer may pick from its route position. A camp is real when it has REAL_CAMP spawns,
-- or as many as the target's biggest camp on any map when the mob never gathers that many, so a lone stray
-- never outranks a camp. Camps are clustered per creature, so every quest on the same creature sees the
-- very same camp points and the optimizer can share their kills. Creatures that share one camp (2 + 2 spawns)
-- are also clustered together: a creature's camp inside such a real mixed area is real as well.
targetLocation = function(target)
    if #(target.sources or {}) == 0 then return nearestPoint(target.points) end
    if not target.camps then
        local largest, here, pooled, objects = 0, {}, {}, {}
        for _, source in ipairs(target.sources) do
            local probability = target.dropRates and target.dropRates[source.id]
            if source.kind == "object" then
                -- A world object gives the item outright and any one of them will do, so every local spawn is a
                -- destination. The camp rule below exists for creature grinds; it would drop a lone nearby flower
                -- in favour of a far cluster.
                for _, spawn in ipairs(source.spawns or {}) do
                    if not spawn.dungeon and finite(spawn.x) and finite(spawn.y) then
                        local point = pointForSpawn(spawn)
                        if point then objects[#objects + 1] = { point = point, source = source } end
                    end
                end
            elseif source.kind ~= "npc" or target.kind ~= "loot" or probability ~= 0 then
                local byMap = {}
                for _, spawn in ipairs(source.spawns or {}) do
                    if not spawn.dungeon and finite(spawn.x) and finite(spawn.y) then
                        local point = pointForSpawn(spawn)
                        -- Spawns elsewhere only size the biggest camp; local camps are the destinations.
                        local key = point and "here" or (spawn.map and ("m" .. spawn.map) or ("a" .. tostring(spawn.area)))
                        local x, y = point and point.x or spawn.x / 100, point and point.y or spawn.y / 100
                        byMap[key], pooled[key] = byMap[key] or {}, pooled[key] or {}
                        table.insert(byMap[key], { point = point, x = x, y = y })
                        table.insert(pooled[key], { point = point, x = x, y = y })
                    end
                end
                for key, list in pairs(byMap) do
                    for _, camp in ipairs(groupCamps(list)) do
                        largest = math.max(largest, #camp.members)
                        if key == "here" then here[#here + 1] = { camp = camp, source = source } end
                    end
                end
            end
        end
        local pooledLargest, areas, mixed = 0, {}, {}
        for key, list in pairs(pooled) do
            for _, camp in ipairs(groupCamps(list)) do
                pooledLargest = math.max(pooledLargest, #camp.members)
                if key == "here" then areas[#areas + 1] = camp end
            end
        end
        for _, camp in ipairs(areas) do
            if #camp.members >= math.min(REAL_CAMP, pooledLargest) then mixed[#mixed + 1] = camp.mark.point end
        end
        target.camps = {}
        for _, row in ipairs(here) do
            local real = #row.camp.members >= math.min(REAL_CAMP, largest)
            for _, mark in ipairs(mixed) do
                if real then break end
                real = within(mark, row.camp.mark.point, CLUSTER_YARDS, CLUSTER_DISTANCE)
            end
            if real then
                target.camps[#target.camps + 1] = { point = row.camp.mark.point, source = row.source }
            end
        end
        for _, object in ipairs(objects) do target.camps[#target.camps + 1] = object end
    end
    local ranked = {}
    for _, camp in ipairs(target.camps) do
        ranked[#ranked + 1] = { point = camp.point, source = camp.source, d = distance(playerPoint, camp.point) }
    end
    table.sort(ranked, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        if a.point.x ~= b.point.x then return a.point.x < b.point.x end
        return a.point.y < b.point.y
    end)
    if not ranked[1] then return nil end
    return ranked[1].point, ranked[1].source, ranked
end

-- Shared-camps view (Settings > Quest guide > "Show shared camps on the world map" and the camps table).
-- The planned quests' unfinished kill and collect objectives, their spawns on this map grouped into the guide's
-- 100-yard camps; a camp of at least CAMP_VIEW_MIN spawns is shown, "shared" when it serves 2+ quests.
-- Returns { map, camps = { { id, point, total, counts[col], quests[qid], questCount, shared } }, columns = { { name, quest, qid } } }.
local CAMP_VIEW_MIN = 5
local campCache
function P.campView()
    if not (sessionActive and frameMap and route and route[1]) then return nil end
    if campCache and campCache.route == route then return campCache.view end
    local planned, ids = (report and report.plannedIDs) or {}, {}
    for id in pairs(planned) do if catalog[id] then ids[#ids + 1] = id end end
    table.sort(ids)
    local list, columns = {}, {}
    for _, id in ipairs(ids) do
        local q = catalog[id]
        for _, target in ipairs(q.targets or {}) do
            if not objectiveIsDone(q.entry, target) then
                for _, source in ipairs(target.sources or {}) do
                    local col
                    for _, spawn in ipairs(source.spawns or {}) do
                        local point = pointForSpawn(spawn)
                        if point then
                            if not col then
                                columns[#columns + 1] = { name = source.name or "?", quest = q.name, qid = id }
                                col = #columns
                            end
                            list[#list + 1] = { point = point, x = point.x, y = point.y, col = col }
                        end
                    end
                end
            end
        end
    end
    local camps = {}
    for _, camp in ipairs(#list > 0 and groupCamps(list) or {}) do
        if #camp.members >= CAMP_VIEW_MIN then
            local row = { point = camp.mark.point, total = #camp.members, counts = {}, quests = {}, questCount = 0, members = camp.members }
            for _, m in ipairs(camp.members) do
                row.counts[m.col] = (row.counts[m.col] or 0) + 1
                local qid = columns[m.col].qid
                if not row.quests[qid] then row.quests[qid], row.questCount = true, row.questCount + 1 end
            end
            row.shared = row.questCount >= 2
            camps[#camps + 1] = row
        end
    end
    table.sort(camps, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        if a.point.x ~= b.point.x then return a.point.x < b.point.x end
        return a.point.y < b.point.y
    end)
    local points = {}
    for i, camp in ipairs(camps) do
        camp.id = "A" .. i
        for _, m in ipairs(camp.members or {}) do m.camp = camp.id end
    end
    for _, m in ipairs(list) do points[#points + 1] = { x = m.x, y = m.y, col = m.col, camp = m.camp } end
    -- quest givers on the route (pickups and hand-ins), one per name, for the window's map and camp names
    local givers, seen = {}, {}
    for _, group in ipairs(route) do
        for _, a in ipairs(group.atoms or {}) do
            local name = a.destination
            if (a.kind == "pickup" or a.kind == "turnin") and name and a.point and a.point.map == frameMap and not seen[name] then
                seen[name] = true
                givers[#givers + 1] = { name = name, x = a.point.x, y = a.point.y }
            end
        end
    end
    local view = { map = frameMap, camps = camps, columns = columns, points = points, givers = givers }
    campCache = { route = route, view = view }
    return view
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
                local point, source, camps = targetLocation(target)
                if point then
                    local required = need or target.required
                    local function describe(src)
                        local id = src and src.kind == "npc" and src.id or nil
                        local text = targetSummary(target, src, id and target.dropRates and target.dropRates[id])
                        if progress then text = text .. " (" .. progress .. ")"
                        elseif required then text = text .. " ×" .. required end
                        return text, id, src and src.kind
                    end
                    local text, npc, kind = describe(source)
                    local stop = atom(stops, "objective", point, q, text,
                        target.name and ("the " .. target.name .. " area"), i)
                    -- Other real camps of the same work; the optimizer may choose one that suits the route.
                    for n = 2, math.min(#(camps or {}), MAX_CAMP_CHOICES) do
                        local altText, altNPC, altKind = describe(camps[n].source)
                        stop.alternatives = stop.alternatives or {}
                        stop.alternatives[#stop.alternatives + 1] = { point = camps[n].point, sourceID = altNPC, sourceKind = altKind,
                            tasks = { altText }, questTasks = { [q.id] = { altText } } }
                    end
                    local sharing = npc and target.shareable ~= false and
                        ((target.kind == "kill" and target.creditID) or (target.kind == "loot" and target.itemID))
                    stop.objectives = { { questID = id, target = target, remaining = required and math.max(0, required - (have or 0)),
                        sourceID = npc, sourceKind = kind, shareable = sharing and true or false } }
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
        local yards, fraction = TAKEIN_YARDS, TAKEIN_DISTANCE
        if stop.kind == "objective" then yards, fraction = CLUSTER_YARDS, CLUSTER_DISTANCE end
        -- Only collapse consecutive instructions. Their physical actions still run in scheduled order.
        if not last or last.kind ~= stop.kind or not within(last.point, stop.point, yards, fraction) then
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

-- "Camp busy" marks the camp the player was sent to, which can be one of the objective's alternatives.
-- Busy alternatives are dropped; a busy default gives way to a free alternative; when every camp is busy,
-- the one that frees up first becomes the default. Returns the seconds until the stop's camp is free, and
-- whether any of its camps was busy (its camp choice was then forced, not chosen).
local function avoidBusyCamps(stop, now)
    local free, soonest, soonestAt = {}, nil, nil
    for _, alt in ipairs(stop.alternatives or {}) do
        local expires = waitingAt[campKey(alt.point)]
        if not expires then free[#free + 1] = alt
        elseif not soonestAt or expires < soonestAt then soonest, soonestAt = alt, expires end
    end
    local busyUntil, promote = waitingAt[campKey(stop.point)], nil
    local narrowed = busyUntil ~= nil or soonest ~= nil
    if busyUntil and free[1] then
        promote, busyUntil = table.remove(free, 1), nil
    elseif busyUntil and soonestAt and soonestAt < busyUntil then
        promote, busyUntil = soonest, soonestAt
    end
    if promote then
        stop.point, stop.tasks, stop.questTasks = promote.point, promote.tasks, promote.questTasks
        stop.objectives[1].sourceID, stop.objectives[1].sourceKind = promote.sourceID, promote.sourceKind
    end
    stop.alternatives = free[1] and free or nil
    return busyUntil and busyUntil - now, narrowed
end

local function planOptions(stops, origin)
    local width, height = U.call(C_Map and C_Map.GetMapWorldSize, origin.map)
    local estimatedScale = not (finite(width) and width > 0 and finite(height) and height > 0)
    if estimatedScale then width, height = 3000, 2000 end
    -- Straight-line travel only: the plan never depends on the optional Shortest Path Forever.
    local speed = runSpeed()
    local function travel(a, b)
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
    local availableAfter, byKey, preferred, forced = {}, {}, {}, {}
    local now = GetTime()
    for key, expires in pairs(waitingAt) do if expires <= now then waitingAt[key] = nil end end
    for _, stop in ipairs(stops) do
        byKey[stop.key] = stop.id
        if stop.kind == "objective" then
            local wait, narrowed = avoidBusyCamps(stop, now)
            availableAfter[stop.id] = wait
            if narrowed then forced[stop.key] = true end
        end
    end
    if previousMap == origin.map then
        for _, key in ipairs(previousPlan or {}) do if byKey[key] then preferred[#preferred + 1] = byKey[key] end end
    end
    -- Remembered camps stay unless another camp is clearly cheaper (the optimizer's switch margin).
    return { mode = goal.mode, selectedIDs = goal.selectedIDs, budgetSeconds = goal.budgetSeconds, origin = origin,
        checkpoint = Work.checkpoint, travelSeconds = travel,
        killSeconds = ns.questCalibration and ns.questCalibration.killSeconds() or 10,
        interactionSeconds = ns.questCalibration and ns.questCalibration.interactionSeconds() or 3,
        logCount = count, logCapacity = capacity, preferredIDs = preferred, stabilitySeconds = 10,
        preferredSites = siteMemory.map == origin.map and siteMemory.sites or nil,
        availableAfter = availableAfter, inventory = inventory,
        reputation = reputation,
        skillRanks = skillRanks,
        level = U.call(UnitLevel, "player"), currentXP = U.call(UnitXP, "player"),
        nextLevelXP = U.call(UnitXPMax, "player"), levelXPTable = XP_TO_NEXT }, estimatedScale, speed, forced
end

buildRoute = function()
    P.cancelEstimate()
    nextStopID = 0
    local stops, origin = questActions(), playerPoint
    if not origin then route = {}; return end
    if goal.mode == "selected" then resolveChosen() end
    local opts, estimatedScale, speed, forced = planOptions(stops, origin)
    local token = generation
    local keys, selection, busy = {}, {}, {}
    for i, stop in ipairs(stops) do keys[i] = stop.key end
    for id in pairs(goal.selectedIDs) do selection[#selection + 1] = id end
    table.sort(selection)
    for key in pairs(waitingAt) do busy[#busy + 1] = key end -- planOptions already dropped expired waits
    table.sort(busy)
    local inputs = { map = origin.map, origin = origin, stops = table.concat(keys, ";"),
        goal = table.concat({ goal.mode, tostring(goal.budgetSeconds), P.levelScope, table.concat(selection, ","),
            table.concat(busy, ",") }, "|") }
    -- Local search runs again only for a new stop set, goal or scope, or after real movement; otherwise solve(0)
    -- starts from the refined order (preferredIDs), so it runs as well when that order was discarded.
    local last = refinedPlan
    local refineNeeded = #opts.preferredIDs == 0 or not (last and last.map == inputs.map and last.stops == inputs.stops
        and last.goal == inputs.goal and distance(last.origin, origin) < REFINE_MOVE)
    local function current() return generation == token and sessionActive and not panelDismissed and ns.db.enabled end
    local function solve(improveSteps)
        opts.maxImproveSteps = improveSteps or 0
        local ordered, result = ns.questOptimizer.optimize(catalog, stops, opts)
        if generation ~= token then return end
        report = result or {}
        lastPlanOptions = opts
        report.estimatedScale = estimatedScale
        report.range = P.levelScope
        previousMap, previousPlan = origin.map, {}
        for _, stop in ipairs(ordered or {}) do previousPlan[#previousPlan + 1] = stop.key end
        lastOrigin, plannedSpeed = origin, speed
        -- Every plan records its camps, except a camp "Camp busy" forced: that stop keeps its earlier memory.
        if siteMemory.map ~= origin.map then siteMemory = { map = origin.map, sites = {} } end
        for _, stop in ipairs(ordered or {}) do
            if stop.kind == "objective" and not forced[stop.key] then
                siteMemory.sites[stop.key] = ns.questOptimizer.siteKey(stop.point)
            end
        end
        -- The step the player chose is read now, not when a background job started: the search takes many slices.
        local key = selectionLocked and route[selected] and stopIdentity(route[selected])
        route = visibleStops(ordered or {}, report.stepNotes)
        for _, group in ipairs(route) do
            for _, atom in ipairs(group.atoms) do if forced[atom.key] then group.busyCamp = true end end
        end
        if busyNotice then
            local notice, camp = busyNotice, nil
            busyNotice = nil
            for _, group in ipairs(route) do
                for _, atom in ipairs(group.atoms) do if atom.key == notice.key then camp = group.point end end
            end
            local line = "Quest guide: " .. notice.name .. " camp marked busy for 5 min; "
            if camp and campKey(camp) ~= campKey(notice.point) then
                line = line .. string.format("next free camp %.1f, %.1f", camp.x * 100, camp.y * 100)
            elseif camp then line = line .. "every camp is busy, so the route waits for this one"
            else line = line .. "the route leaves it out until then" end
            ns.print(line)
        end
        selected = 1
        if key then
            for i, stop in ipairs(route) do if stopIdentity(stop) == key then selected = i; break end end
        end
    end
    -- The fast schedule shows at once; local search refines it in the background and swaps it in. It is idle work:
    -- it runs only while no other data work (map search, dungeon scan) is waiting.
    local function refine()
        Work.start("quest-improve", function()
            solve(IMPROVE_STEPS)
            if token ~= generation then return end
            refinedPlan = inputs
            render()
        end, current, nil, nil, "idle")
    end
    solve(0)
    if refineNeeded then refine() end
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
    panel = S.window("QuestSharingPlannerPanel", PLAN_WIDTH, 380, "Quest guide", "hud")
    if not panel then return false end
    panel.title:ClearAllPoints()
    panel.title:SetPoint("TOP", panel, "TOP", 0, -8)
    panel.title:SetText(S.GOLD .. "QUEST GUIDE|r")
    panel.onMoved = function() panelMoved = true end
    panel:SetScript("OnDragStart", function(self) if not guideLocked then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self)
        if not guideLocked then self:StopMovingOrSizing(); panelMoved = true end
    end)
    panel:EnableMouse(true)
    -- Word buttons keep the classic button art; symbol buttons ("...", "?", arrows, minus) stay bare text.
    local function smallButton(label, width, x, y, action, tip, art)
        local b = S.button(panel, label, width, action, tip)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
        if not art then b.bg:Hide(); b.edge:Hide() end
        return b
    end
    smallButton("...", 20, 7, 6, function() ns.settingsTab("guide") end, "Quest guide settings")
    local planButton = smallButton("Plan", 38, 28, 6, function() P.options() end, nil, true)
    planButton:SetScript("OnEnter", function(self)
        self.label:SetText(S.WHITE .. tostring(self.text or "") .. "|r")
        U.tip(self, "Quest guide goal", { goalLine(), "Click: change the goal and see the report in Settings > Quest guide." })
    end)
    smallButton("?", 20, 68, 6, function(self)
        U.tip(self, "Quest guide", { "Follow the highlighted step, then use the arrows to review the next step.",
            "Quest progress updates the guide automatically. Click a step to set a waypoint there.",
            "Lock keeps the guide in place. Minus shows only the current step." })
    end, "How to use the Quest guide")
    busyButton = smallButton("Busy", 38, PLAN_WIDTH - 120, 6, function() P.markCampBusy() end,
        "Camp busy: other players are farming here. The route uses another camp for 5 minutes, then comes back.")
    busyButton:Hide()
    lockButton = smallButton("Lock", 46, PLAN_WIDTH - 80, 6, function(self)
        guideLocked = not guideLocked
        panel:SetMovable(not guideLocked)
        self:SetLabel(guideLocked and "Unlock" or "Lock")
    end, "Lock or unlock the guide position", true)
    local headerLine = S.fill(panel, "ARTWORK", 0.56, 0.39, 0.14, 1)
    headerLine:SetPoint("TOPLEFT", panel, "TOPLEFT", 7, -29)
    headerLine:SetWidth(PLAN_WIDTH - 14); headerLine:SetHeight(1)
    previousButton = smallButton("<", 20, 8, 34, function() P.navigate(-1) end, "Previous step")
    stepCounter = U.text(panel, "0/0", 32, 38, 40)
    nextButton = smallButton(">", 20, 74, 34, function() P.navigate(1) end, "Next step")
    message = U.text(panel, "", 100, 38, PLAN_WIDTH - 194)
    message:SetWordWrap(false)
    campsButton = smallButton("Camps", 52, PLAN_WIDTH - 88, 34, function() if ns.campMap then ns.campMap.openTable() end end,
        "Shared camps: which mobs of your route share a camp (network, map and matrix). Also /qs plan camps table.", true)
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
    panel:SetScript("OnShow", function() if sessionActive then Work.resume("quest-plan") end end)
    panel:SetScript("OnHide", function()
        -- The game hid the whole interface (Alt+Z, a cinematic): keep the session; the plan job waits until it shows.
        if not panelDismissed then return end
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

-- Pickup and hand-in steps name each giver once in a heading, then list the quests: "Pick up from X:" / "[1] Quest".
local function takeInText(stop, numbers)
    local giverOf = {}
    for _, a in ipairs(stop.atoms or {}) do
        for id in pairs(a.quests) do giverOf[id] = giverOf[id] or a.destination or false end
    end
    local groups, byGiver = {}, {}
    local verb = stop.kind == "pickup" and "Pick up from " or "Hand in to "
    for _, id in ipairs(sortedQuestIDs(stop)) do
        local giver = giverOf[id] or false
        local group = byGiver[giver]
        if not group then
            group = { giver and (verb .. giver .. ":") or (stop.kind == "pickup" and "Pick up these quests:" or "Hand in these quests:") }
            byGiver[giver] = group
            groups[#groups + 1] = group
        end
        group[#group + 1] = string.format("[%d] %s", numbers[id], stop.quests[id])
    end
    local out = {}
    for _, group in ipairs(groups) do
        for _, line in ipairs(group) do out[#out + 1] = line end
    end
    return out
end

local function rowDetailsText(stop, numbers)
    if stop.kind == "pickup" or stop.kind == "turnin" then
        local tasks = takeInText(stop, numbers)
        if stop.reasons and stop.reasons[1] then tasks[#tasks + 1] = stop.reasons[1] end
        return table.concat(tasks, "\n")
    end
    local tasks = { "Complete these quests here:" }
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
    if stop.busyCamp then tasks[#tasks + 1] = "A camp for this step is marked busy; the route uses this one for now." end
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
        -- One click action (any button, in or out of combat): select the step and set its waypoint.
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function()
            if selectStop(rowIndex) then P.pin() end
        end)
        row:SetScript("OnEnter", function(self)
            local lines = {}
            for _, id in ipairs(sortedQuestIDs(stop)) do
                lines[#lines + 1] = string.format("%s - Quest ID %d", tostring(stop.quests[id]), id)
            end
            lines[#lines + 1] = "Click: set a waypoint here."
            U.tip(self, "Quest location", lines)
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
    if busyButton then
        if route[selected] and route[selected].kind == "objective" then busyButton:Show() else busyButton:Hide() end
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
                local open = next(coverage.blocked) or next(coverage.unknown) or next(coverage.external)
                    or next(coverage.filtered)
                if (stats.localCount or 0) == 0 then reason = "Questie has no mapped quest givers here."
                elseif next(coverage.completed) and not open then
                    reason = "You have done every quest the guide knows in " .. (zone or "this zone") .. "."
                else reason = "No quest can be planned here yet - Plan > Show report says why." end
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
    local zone, _, map = currentZone()
    if not zone then zone = plannedZoneName
    elseif map ~= plannedMap then scan(); return false end
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
    if loading then return ns.print("the Quest guide is updating") end
    if not plannedMap and #route == 0 then return ns.print("the Quest guide has no route yet; use /qs plan") end
    local zone, _, map = currentZone()
    if zone and plannedMap and map ~= plannedMap then scan(); return ns.print("you changed zones; the Quest guide is planning the new zone") end
    local stop = route[selected]
    if not stop or not stop.point then return ns.print("this stop has no map location") end
    local p = stop.point
    if not ns.compat.setWaypoint(p.map, p.x, p.y) then
        ns.print("the game cannot set a waypoint here; " .. mapLine(stop))
    end
end

function P.follow()
    if loading then return ns.print("the Quest guide is updating") end
    local stop = route[selected]
    if not stop or not stop.point then return ns.print("this stop has no map location") end
    local zone, _, map = currentZone()
    if zone and plannedMap and map ~= plannedMap then
        scan()
        return ns.print("you changed zones; the Quest guide is planning the new zone")
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
    if not ns.db.questPlanner then return ns.print("turn on the Quest guide in Settings > Quest guide first") end
    if not panel or not panel:IsShown() then return P.open() end
    sessionActive = true
    scan(true)
end

function P.open()
    if not ns.db.questPlanner then ns.setSetting("questPlanner", true); return end
    panelDismissed = false
    sessionActive = true
    readSettings()
    if not ensurePanel() then return ns.print("this client cannot open the Quest guide") end
    dockPanel()
    panel:Show()
    -- No replan while walking: the route changes when a quest is accepted, progressed, done or abandoned, on a
    -- level-up or a new zone, and on Refresh (user, 2026-11-19: steps must not move or vanish by themselves).
    scan()
end

function P.settingChanged(enabled)
    if enabled then
        panelDismissed = false
        P.open()
    else
        panelDismissed = true
        sessionActive = false
        zoneQuestIDs, zoneOrder, zoneScope = {}, {}, {}
        generation = generation + 1
        loading = false
        clearPlan("Quest guide is off.")
        if panel then panel:Hide() end
    end
end

Work.onPurge("Quest guide zone lists", function() Work.forget("guideZones"); zoneQuestIDs, zoneScope, zoneOrder = {}, {}, {} end)

function P.masterChanged(enabled)
    if enabled then return end
    if panel then panel:SetScript("OnUpdate", nil) end
    Guidance.clear()
    sessionActive = false
    generation = generation + 1
    Work.cancel("quest-plan")
    P.cancelEstimate()
    loading = false
    if panel then panel:Hide() end
end

rebuildProgress = function(log, zone)
    Guidance.clear()
    local oldIndex, oldKey = selected, selectionLocked and route[selected] and stopIdentity(route[selected])
    generation = generation + 1
    local token = generation
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
    end, function(ok) if not ok and token == generation then clearPlan("Refresh the Quest guide to try again.") end end)
end

scheduleRefresh = function(force, zoneEntry)
    if not (ns.db and ns.db.enabled and ns.db.questPlanner and sessionActive)
        or panelDismissed or not (panel and panel:IsShown()) then return end
    if zoneEntry and plannedMap then
        local zone, reason, map = currentZone()
        if zone and map ~= plannedMap then
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
        if not zone then return end
        if pausedOutside and map == plannedMap then pausedOutside = false; if message then message:SetText(zone) end end
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
-- Which reputation requirements of the planned quests are met ("" when none has one). A rep gain replans only when it
-- crosses one of them, so a kill that gives reputation does not rebuild the guide.
local function repGates()
    local gates, factions = {}, {}
    for id, quest in pairs(catalog) do
        for _, key in ipairs({ "requiredMinRep", "requiredMaxRep" }) do
            local pair = quest[key]
            if type(pair) == "table" and pair[1] then gates[#gates + 1] = { id, key, pair[1], tonumber(pair[2]) or 0 }; factions[pair[1]] = true end
        end
    end
    if #gates == 0 then return "" end
    local values, parts = ns.compat.plannerReputation(factions) or {}, {}
    for _, g in ipairs(gates) do
        local v = tonumber(values[g[3]])
        local met = v == nil and "?" or (((g[2] == "requiredMinRep") == (v >= g[4])) and "1" or "0")
        parts[#parts + 1] = g[1] .. g[2] .. "=" .. met
    end
    table.sort(parts)
    return table.concat(parts, ",")
end
P.repGates = repGates

-- Loot, reputation, skill-ups and spells fire all the time; they replan only when the quest log changed with them
-- (reputation also when it crosses a planned quest's requirement).
ns.on("BAG_UPDATE_DELAYED", function() scheduleRefresh(false, false) end)
ns.on("SPELLS_CHANGED", function() scheduleRefresh(false, false) end)
ns.on("UPDATE_FACTION", function()
    local now = repGates()
    local crossed = P.lastRepGates ~= nil and now ~= P.lastRepGates
    P.lastRepGates = now
    scheduleRefresh(crossed, false)
end)
ns.on("SKILL_LINES_CHANGED", function() scheduleRefresh(false, false) end)
ns.on("QUEST_WATCH_UPDATE", function() scheduleRefresh(false, false) end)
ns.on("UNIT_QUEST_LOG_CHANGED", function() scheduleRefresh(false, false) end)

-- One name per goal and level choice: the labels in Settings > Quest guide, shared by the report, chat and tooltips.
P.goalNames = { all = "Complete zone", xp = "Quest XP/hour", selected = "Chosen quests", budget = "Time limit" }
P.scopeNames = { all = "Every level", ["green-yellow"] = "Green and yellow only" }
local modeNames = P.goalNames
function P.report() return report end

local function debugIDs(values, array)
    local ids = {}
    for key, value in pairs(values or {}) do
        local id = array and value or key
        if type(id) == "number" and (array or value) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    if #ids == 0 then return "none" end
    for i, id in ipairs(ids) do ids[i] = tostring(id) end
    return table.concat(ids, ",")
end

local function debugPoint(point)
    if not point then return "unknown" end
    return string.format("map %s (%.4f, %.4f)", tostring(point.map), tonumber(point.x) or 0,
        tonumber(point.y) or 0)
end

local function debugValues(values)
    local keys, parts = {}, {}
    for id in pairs(values or {}) do if type(id) == "number" then keys[#keys + 1] = id end end
    table.sort(keys)
    for _, id in ipairs(keys) do parts[#parts + 1] = tostring(id) .. "=" .. tostring(values[id]) end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

-- Explicit snapshot only: use the already planned candidate/action data, never enumerate QuestieDB.
function P.debugText()
    local lines, opts = {"Quest Sharing planner snapshot"}, lastPlanOptions or {}
    local function add(value) lines[#lines + 1] = value end
    local liveMap, liveX, liveY = ns.compat.playerPos()
    local liveLog = ns.compat.entryMap()
    local logIDs = {}
    for id in pairs(liveLog) do logIDs[id] = true end
    add("State: " .. (loading and "loading" or sessionActive and "open" or "closed") ..
        "; generation=" .. generation .. "; selected step=" .. selected .. "/" .. #route)
    add("Zone map: " .. tostring(plannedMap or "none") .. "; plan origin: " .. debugPoint(opts.origin) ..
        "; live position: " .. debugPoint(liveMap and {map=liveMap,x=liveX,y=liveY}))
    add("Goal: " .. tostring(goal.mode) .. "; level scope=" .. P.levelScope ..
        "; selected quests=" .. debugIDs(goal.selectedIDs) .. "; budget seconds=" .. tostring(goal.budgetSeconds))
    add("Character at plan: level=" .. tostring(opts.level or "unknown") ..
        "; XP=" .. tostring(opts.currentXP or "unknown") .. "/" .. tostring(opts.nextLevelXP or "unknown") ..
        "; quest log=" .. tostring(opts.logCount or "unknown") .. "/" .. tostring(opts.logCapacity or "unknown"))
    add("Live quest log IDs: " .. debugIDs(logIDs))
    add("Carried relevant items: " .. debugValues(opts.inventory and opts.inventory.counts) ..
        "; free bag slots=" .. tostring(opts.inventory and opts.inventory.freeSlots or "unknown"))
    add("Known reputation: " .. debugValues(opts.reputation))
    add("Known skill ranks: " .. debugValues(opts.skillRanks))
    if report then
        add(string.format("Forecast: %.1f sec total, %.1f travel, %.1f work, %.1f wait, %.2f kills, %.0f XP, %d hand-ins",
            report.expectedSeconds or 0, report.travelSeconds or 0, report.workSeconds or 0,
            report.waitSeconds or 0, report.expectedKills or 0, report.expectedXP or 0, report.coverage or 0))
        add("Search: checks=" .. tostring(report.searchChecks or "unknown") ..
            "; exhausted=" .. tostring(report.searchExhausted) .. "; uncertain=" .. tostring(report.uncertain) ..
            "; nearest=" .. tostring(report.nearestSeconds or "unknown") .. " sec/" ..
            tostring(report.nearestCoverage or "unknown") .. " hand-ins; same-work baseline=" ..
            tostring(report.baselineSeconds or "unknown") .. " sec; comparable=" .. tostring(report.baselineComparable) ..
            (report.estimatedScale and "; scale=estimated 3000x2000" or ""))
        add("Planned quest IDs: " .. debugIDs(report.plannedIDs) ..
            "; completed quest IDs: " .. debugIDs(report.completedIDs) ..
            "; missing quest IDs: " .. debugIDs(report.missingIDs))
    else add("No completed plan snapshot; open /qs plan and wait for its scan, then run /qs plan debug again.") end
    add("")
    add("ROUTE (actual atomic order)")
    if #route == 0 then add("none") end
    for step, group in ipairs(route) do
        add(string.format("Step %d%s: %s at %s", step, step == selected and " [selected]" or "",
            tostring(group.kind), debugPoint(group.point)))
        for _, atom in ipairs(group.atoms or {}) do
            local qid = next(atom.quests or {})
            add(string.format("  action %s quest %s %s; deps=%s; task=%s", tostring(atom.id),
                tostring(qid), tostring(atom.kind), debugIDs(atom.deps), table.concat(atom.tasks or {}, " | ")))
            for _, row in ipairs(atom.objectives or {}) do
                local target = row.target or {}
                add("    objective=" .. tostring(target.kind) .. " " .. tostring(target.name or "") ..
                    "; remaining=" .. tostring(row.remaining or "unknown") .. "; source NPC=" ..
                    tostring(row.sourceID or "unknown") .. "; item=" .. tostring(target.itemID or "none") ..
                    "; credit=" .. tostring(target.creditID or "none") ..
                    "; drop rates=" .. debugValues(target.dropRates))
            end
            if report and report.reasons and report.reasons[atom.id] then
                add("    reason: " .. report.reasons[atom.id])
            end
        end
    end
    add("")
    add("LOCAL QUEST CANDIDATES (including unscheduled)")
    local ids = {}
    for id in pairs(catalog) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids == 0 then add("none") end
    for _, id in ipairs(ids) do
        local q = catalog[id]
        add(string.format("%d %s | status=%s band=%s level=%s required=%s XP=%s active=%s finishHere=%s planned=%s completed=%s",
            id, tostring(q.name), tostring(q.status), tostring(q.band), tostring(q.level),
            tostring(q.requiredLevel), tostring(q.xp or "unknown"), tostring(q.entry ~= nil),
            tostring(q.canFinishHere), tostring(report and report.plannedIDs[id] or false),
            tostring(report and report.completedIDs[id] or false)))
        for _, gate in ipairs(q.gates or {}) do
            add("  gate " .. tostring(gate.kind) .. " one of [" .. debugIDs(gate.choices, true) ..
                "] initially satisfied=" .. tostring(gate.satisfied == true))
        end
        if q.requiredMinRep then add("  min reputation " .. table.concat(q.requiredMinRep, ":")) end
        if q.requiredMaxRep then add("  max reputation " .. table.concat(q.requiredMaxRep, ":")) end
        if q.requiredSkill then add("  skill " .. table.concat(q.requiredSkill, ":")) end
        for _, rank in ipairs(q.requiredRanks or {}) do add("  alternative rank " .. table.concat(rank, ":")) end
        if q.availableUntilCompleted then add("  available until quest " .. q.availableUntilCompleted .. " completed") end
        if q.exclusiveTo and #q.exclusiveTo > 0 then add("  exclusive with " .. debugIDs(q.exclusiveTo, true)) end
        for _, target in ipairs(q.targets or {}) do
            add("  target " .. tostring(target.kind) .. " " .. tostring(target.name or "") ..
                "; required=" .. tostring(target.required or "unknown") .. "; have=" ..
                tostring(target.have or "unknown") .. "; count source=" .. tostring(target.countSource or "unknown") ..
                "; item=" .. tostring(target.itemID or "none") .. "; credit=" ..
                tostring(target.creditID or "none") .. "; rates=" .. debugValues(target.dropRates))
        end
    end
    add("")
    add("EXCLUDED OR UNVERIFIED QUESTS")
    if skippedText() then add(skippedText()) end
    for _, category in ipairs({"external", "unknown", "blocked", "filtered", "repeatable", "completed"}) do
        local excluded = {}
        for id in pairs(coverage[category]) do excluded[#excluded + 1] = id end
        table.sort(excluded)
        for _, id in ipairs(excluded) do add(category .. " " .. id .. ": " .. tostring(coverage[category][id])) end
    end
    return table.concat(lines, "\n")
end

function P.debug()
    if ns.reportWindow then
        ns.reportWindow("Quest guide - debug", {P.debugText()}, "planner", nil, nil, P.debug)
    else ns.print("the Quest guide debug report is unavailable; try /reload.") end
end

-- "Green Quest (8100)": the name from this zone's quests, your log, or one name read; the ID alone if none is known.
local function questLabel(id, titles)
    local name = catalog[id] and catalog[id].name or titles and titles[id]
    if type(name) ~= "string" or name == "" then
        local q = questie()
        name = q and q.get and U.call(q.get, "quest", id, "name")
    end
    if type(name) ~= "string" or name == "" then return "Quest " .. tostring(id) end
    return name .. " (" .. tostring(id) .. ")"
end

-- Why a quest the goal wanted is not handed in on this route, when no zone check already said why.
local function missingReason(id, labelOf)
    if report.plannedIDs and report.plannedIDs[id] then return "taken on this route, but not handed in on it" end
    local q = catalog[id]
    if not q then return "not a quest the Quest guide can plan in this zone" end
    for _, other in ipairs(q.exclusiveTo or {}) do
        if report.plannedIDs and report.plannedIDs[other] then
            return "only one of it and " .. labelOf(other) .. " can be done; the route takes that one"
        end
    end
    if goal.mode == "xp" then return "left out: too little XP for the time it takes" end
    if goal.mode == "budget" then return "left out: it does not fit in the time limit" end
    if q.status == "future" then return "needs an earlier quest this route does not finish" end
    return "does not fit in this route (a full quest log can cause this)"
end

local function explainPlan()
    local lines = {modeNames[goal.mode] .. " • " .. P.scopeNames[P.levelScope]}
    local titles = {}
    for id, entry in pairs(ns.compat.entryMap()) do titles[id] = entry.title end
    local function labelOf(id) return questLabel(id, titles) end
    if report then
        local parts = { string.format("Estimated %.1f min", (report.expectedSeconds or 0)/60),
            string.format("travel %.1f min", (report.travelSeconds or 0)/60) }
        local kills = math.floor((report.expectedKills or 0) + 0.5)
        if kills > 0 then parts[#parts+1] = "about " .. kills .. (kills == 1 and " kill" or " kills") end
        parts[#parts+1] = (report.coverage or 0) .. ((report.coverage or 0) == 1 and " hand-in" or " hand-ins")
        lines[#lines+1] = table.concat(parts, " • ")
        lines[#lines+1] = "Times use estimated combat and interaction costs. Map distances approximate travel."
        if report.estimatedScale then lines[#lines+1] = "Travel times are rough guesses: this map's size is unknown." end
        if report.uncertain then lines[#lines+1] = "Some quantities, drop rates or task durations are unknown or estimated." end
        if report.baselineComparable then
            lines[#lines+1] = string.format("Always going to the nearest quest first would take %.1f min.",
                (report.baselineSeconds or 0)/60)
        end
    else lines[#lines+1] = "Open the guide and wait for the zone scan." end
    -- One reason per quest: the zone check's own reason first, then why the route leaves it out.
    local seen = {}
    for _, category in ipairs({"external","unknown","blocked","filtered","repeatable"}) do
        local ids = {}
        for id in pairs(coverage[category]) do if not seen[id] then ids[#ids+1]=id end end
        table.sort(ids)
        for _,id in ipairs(ids) do
            seen[id] = true
            local taken = report and report.plannedIDs and report.plannedIDs[id] and "taken on this route; " or ""
            local why = tostring(coverage[category][id])
            why = string.lower(why:sub(1, 1)) .. why:sub(2)
            lines[#lines+1] = labelOf(id) .. ": " .. taken .. why
        end
    end
    local pending = {}
    for id in pairs(report and report.missingIDs or {}) do if not seen[id] then pending[#pending+1]=id end end
    table.sort(pending)
    for _,id in ipairs(pending) do lines[#lines+1] = labelOf(id) .. ": " .. missingReason(id, labelOf) end
    if goal.mode == "selected" then
        for _, name in ipairs(goal.missingNames or {}) do
            lines[#lines+1] = string.format('"%s": no quest with this name in your quest log or this zone', name)
        end
    end
    local skipped = {}
    for _, reason in ipairs({ "character", "level", "overlevel", "continent" }) do
        local n = coverage.skipped[reason]
        if n and n > 0 then skipped[#skipped + 1] = n .. " " .. SKIP_TEXT[reason] end
    end
    if #skipped > 0 then lines[#lines+1] = "Quests left out at once: " .. table.concat(skipped, ", ") end
    local K = ns.questCalibration
    if K and K.describe then lines[#lines+1] = "Times used: " .. K.describe() .. "." end
    lines[#lines+1] = "Unknown future levels, inventory restrictions, flight routes and world conditions need live confirmation."
    return table.concat(lines,"\n\n")
end
P.reportText = explainPlan

-- Chosen quests: "9000, Local Harvest, 9001 9002" -> { [9000]=true, ... } and { "Local Harvest" }. Names are
-- separated by commas; "Name (9000)", as the guide prints it, counts as the ID.
local function parseQuestList(text)
    local ids, names = {}, {}
    for part in tostring(text or ""):gmatch("[^,;]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part:match("^[%d%s]+$") then
            for token in part:gmatch("%d+") do ids[tonumber(token)] = true end
        elseif part ~= "" then
            local id = tonumber(part:match("%((%d+)%)%s*$"))
            if id then ids[id] = true else names[#names + 1] = part end
        end
    end
    return ids, names
end

-- The text the Settings box keeps: IDs and names, comma-separated.
function P.cleanQuestList(text)
    local ids, names = parseQuestList(text)
    local out = {}
    for id in pairs(ids) do out[#out + 1] = id end
    table.sort(out)
    for i, id in ipairs(out) do out[i] = tostring(id) end
    for _, name in ipairs(names) do out[#out + 1] = name end
    return table.concat(out, ", ")
end

-- A quest name (any case) -> ID: your quest log, then the quests of the zones the guide planned (one name read each).
local function questByName(name)
    local want = string.lower(name)
    for _, entry in ipairs(ns.compat.entries()) do
        if type(entry.title) == "string" and string.lower(entry.title) == want then return entry.questID end
    end
    for id, q in pairs(catalog) do
        if type(q.name) == "string" and string.lower(q.name) == want then return id end
    end
    local q = questie()
    if not (q and q.get) then return nil end
    for _, ids in pairs(zoneQuestIDs) do
        for _, id in ipairs(ids) do
            local n = U.call(q.get, "quest", id, "name")
            if type(n) == "string" and string.lower(n) == want then return id end
        end
    end
end

-- Names typed for Chosen quests become IDs as soon as the guide knows them; the rest wait for the zone's quests.
resolveChosen = function()
    local missing = {}
    for _, name in ipairs(goal.selectedNames or {}) do
        local id = questByName(name)
        if id then goal.selectedIDs[id] = true else missing[#missing + 1] = name end
    end
    goal.missingNames = missing
end

local BUDGET_MIN, BUDGET_MAX = 5, 240 -- the Settings stepper's range, used everywhere
local function budgetMinutes(value)
    value = tonumber(value)
    if not finite(value) or value <= 0 then return nil end
    return math.max(BUDGET_MIN, math.min(BUDGET_MAX, math.floor(value + 0.5)))
end

-- "Quest XP/hour • Every level", "Time limit 45 min • Green and yellow only"
goalLine = function()
    local text = modeNames[goal.mode] or modeNames.all
    if goal.mode == "budget" then text = text .. " " .. math.floor(goal.budgetSeconds / 60 + 0.5) .. " min" end
    return text .. " • " .. (P.scopeNames[P.levelScope] or P.scopeNames.all)
end

-- Goal, time limit, chosen quests and level scope are saved settings (Settings > Quest guide). This reads them.
-- Returns false when the goal asks for chosen quests and none are typed; the previous goal then stays.
readSettings = function()
    local d = ns.db or {}
    local mode = d.questPlannerGoal
    if modeNames[mode] == nil then mode = "all" end
    local ids, names, hint = {}, {}, nil
    if mode == "selected" then
        ids, names = parseQuestList(d.questPlannerSelected)
        if not next(ids) and #names == 0 then
            mode, hint = goal.mode, "type quest names or IDs in Settings > Quest guide for the Chosen quests goal"
        end
    end
    if mode == "selected" then goal.selectedIDs, goal.selectedNames = ids, names; resolveChosen() end
    local minutes = budgetMinutes(d.questPlannerBudget)
    if minutes then goal.budgetSeconds = minutes * 60 end
    goal.mode = mode
    P.levelScope = d.questPlannerScope == "green-yellow" and "green-yellow" or "all"
    return hint == nil, hint
end

local function replan()
    selectionLocked = false
    previousPlan = nil
    if sessionActive then scan() end
end

-- Settings > Quest guide changed a goal, minutes, quest IDs or level scope: read them and replan at once.
function P.applySettings()
    local ok, hint = readSettings()
    if hint then ns.print(hint) end
    replan()
    return ok
end

-- A goal chosen by command is saved like one chosen in the settings, so both always agree.
local function saveGoal(mode, value)
    ns.db.questPlannerGoal = mode
    if mode == "selected" then ns.db.questPlannerSelected = P.cleanQuestList(value)
    elseif mode == "budget" then ns.db.questPlannerBudget = budgetMinutes(value) or 30 end
    if ns.refreshSettings then ns.refreshSettings() end
end

-- One chat line per goal change, naming what the guide now plans.
local function confirmGoal(note)
    local line = goalLine()
    if goal.mode == "selected" then
        local ids, labels = {}, {}
        for id in pairs(goal.selectedIDs) do ids[#ids + 1] = id end
        table.sort(ids)
        local titles = {}
        for id, entry in pairs(ns.compat.entryMap()) do titles[id] = entry.title end
        for _, id in ipairs(ids) do labels[#labels + 1] = questLabel(id, titles) end
        for _, name in ipairs(goal.missingNames or {}) do labels[#labels + 1] = '"' .. name .. '" (not found yet)' end
        line = modeNames.selected .. ": " .. table.concat(labels, ", ") .. " • " .. P.scopeNames[P.levelScope]
    end
    ns.print("Quest guide: " .. line .. (note or ""))
end

function P.setGoal(mode, value)
    if modeNames[mode] == nil then return false end
    local note
    if mode == "selected" then
        local ids, names = parseQuestList(value)
        if not next(ids) and #names == 0 then
            ns.print("enter quest names or IDs for the Chosen quests goal, e.g. /qs plan selected Local Harvest, 9001")
            return false
        end
        goal.selectedIDs, goal.selectedNames = ids, names
        resolveChosen()
    elseif mode == "budget" then
        local minutes = budgetMinutes(value)
        if not minutes then ns.print("enter a time limit from 5 to 240 minutes"); return false end
        if tonumber(value) > BUDGET_MAX then note = " (" .. BUDGET_MAX .. " min is the most it plans)"
        elseif tonumber(value) < BUDGET_MIN then note = " (" .. BUDGET_MIN .. " min is the least it plans)" end
        goal.budgetSeconds = minutes * 60
    end
    goal.mode = mode
    saveGoal(mode, value)
    confirmGoal(note)
    selectionLocked = false
    previousPlan = nil
    if sessionActive then scan() else P.open() end
    return true
end

-- The guide's options live in Settings > Quest guide.
function P.options() ns.settingsTab("guide") end

-- "Camp busy": the selected objective's camp is skipped for 5 minutes, then the route comes back to it.
function P.markCampBusy()
    local stop = route[selected]
    if stop and stop.kind == "objective" and stop.point then
        waitingAt[campKey(stop.point)] = GetTime() + 300
        local atom = stop.atoms and stop.atoms[1]
        local row = atom and atom.objectives and atom.objectives[1]
        local name = row and row.target and row.target.name
        busyNotice = { key = atom and atom.key, point = stop.point, name = type(name) == "string" and name or "This" }
        selectionLocked = false
        scan()
        return true
    end
    ns.print("select a kill or collect step in the Quest guide first, then mark its camp busy")
    return false
end

function P.clearCampWaits()
    waitingAt = {}
    siteMemory = { map = nil, sites = {} }
    selectionLocked = false
    if sessionActive then scan() end
end

function P.showReport()
    if ns.reportWindow then
        ns.reportWindow("Quest guide report", {explainPlan()}, "planner", nil, nil, P.showReport)
    else ns.print("the Quest guide report is unavailable; try /reload.") end
end

function P.active() return sessionActive end

local COMMANDS = "/qs plan (open), /qs plan on, /qs plan all, /qs plan xp, /qs plan selected <quest names or IDs>, "
    .. "/qs plan budget <5-240 minutes>, /qs plan range, /qs plan unrestricted, /qs plan next, /qs plan busy, "
    .. "/qs plan follow, /qs plan report, /qs plan options, /qs plan refresh, /qs plan debug, /qs plan hide (or close), /qs plan off"

function P.command(arg)
    local raw = tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    arg = string.lower(raw)
    local mode = arg:match("^(%S+)")
    local value = raw:match("^%S+%s*(.-)$") or ""
    if mode == "all" or mode == "xp" or mode == "selected" or mode == "budget" then P.setGoal(mode,value)
    elseif arg == "options" then P.options()
    elseif arg == "why" or arg == "report" then P.showReport()
    elseif arg == "debug" then P.debug()
    elseif arg == "range" or arg == "unrestricted" then
        P.levelScope=arg=="range" and "green-yellow" or "all"
        ns.db.questPlannerScope=P.levelScope
        if ns.refreshSettings then ns.refreshSettings() end
        ns.print("Quest guide: " .. goalLine())
        selectionLocked=false; previousPlan=nil
        if sessionActive then scan() else P.open() end
    elseif arg == "off" then ns.setSetting("questPlanner", false)
    elseif arg == "hide" or arg == "close" then
        Guidance.clear(); panelDismissed = true; sessionActive = false
        Work.cancel("quest-plan"); P.cancelEstimate(); generation = generation + 1; loading = false
        if panel then panel:SetScript("OnUpdate", nil); panel:Hide() end
    elseif arg == "on" then ns.setSetting("questPlanner", true); ns.print("Quest guide is on")
    elseif arg == "next" then
        if #route > 0 and selected >= #route then ns.print("this is the last step of the Quest guide")
        elseif selectStop(selected + 1) then P.pin() end
    elseif arg == "busy" then P.markCampBusy()
    elseif arg == "camps" or arg == "camps on" or arg == "camps off" then
        local on = arg == "camps on" or (arg == "camps" and not ns.db.campMap)
        ns.setSetting("campMap", on)
        ns.print("Shared camps on the world map: " .. (on and "on" or "off") .. " (Settings > Quest guide)")
    elseif arg == "camps table" then if ns.campMap then ns.campMap.openTable() end
    elseif arg == "follow" then P.follow()
    elseif arg == "refresh" then P.refresh()
    elseif arg == "" or arg == "open" or arg == "show" then P.open()
    else ns.print('no Quest guide command "' .. raw .. '". Try: ' .. COMMANDS) end
end
