-- "Get them all": the shortest route to pick up every open quest of one dungeon, across zones and continents.
-- Pure logic (no UI): a travel graph in world yards (walk, known flight paths, boats/zeppelins/tram, one hearthstone),
-- Dijkstra legs between the stops, then a stop order that respects "hand in the lead-in before taking what it unlocks",
-- improved with or-opt and 2-opt moves (the idea of QuestOptimizer.improve, on a much smaller model).
-- All times are estimates in seconds; TravelData coordinates are approximate.
local ADDON, ns = ...
ns.inModule("dungeons")          -- Modules.lua: Settings > General > Tools can switch this off
local R = {}
ns.dungeonRoute = R

R.HEARTHSTONE = 6948
-- Tunable estimates (seconds, yards per second).
R.COST = {
    run = 7, mount = 11.2, epicMount = 14, terrain = 1.25,   -- ground: straight line x terrain factor
    flight = 30, flightDetour = 1.3, flightStop = 10,         -- flight paths: straight line x detour, plus the flight master
    rideWait = 60, ride = 90,                                 -- boat / zeppelin / tram: average wait + ride when not given
    hearth = 30,                                              -- 10 s cast + loading screen
    talk = 5,                                                 -- accept or hand in one quest at an NPC
}

local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

-- map + x/y (0..100) -> {c = continent, x, y} in yards, or nil when the client cannot place it.
function R.world(map, x, y)
    if not (map and finite(x) and finite(y)) then return nil end
    if not (C_Map and type(C_Map.GetWorldPosFromMapPos) == "function" and CreateVector2D) then return nil end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
    if not (ok and continent and pos) then return nil end
    local a, b
    if type(pos.GetXY) == "function" then a, b = pos:GetXY() else a, b = pos.x, pos.y end
    if finite(a) and finite(b) then return { c = continent, x = a, y = b } end
end

-- "Stormwind City" / "Stormwind, Elwynn" / "Grom'gol Base Camp" -> comparable keys.
local function key(name)
    name = string.lower(tostring(name or ""))
    name = string.match(name, "^([^,]+)") or name
    name = string.gsub(name, " city$", "")
    return (string.gsub(name, "^%s+", ""))
end
local function sameTown(a, b)
    a, b = key(a), key(b)
    if a == "" or b == "" then return false end
    return a == b or string.sub(a, 1, #b) == b or string.sub(b, 1, #a) == a
end

-- Flight paths the player knows, saved when a flight master opens (by node name).
function R.knowsFlight(townName, faction, assumeAll)
    if assumeAll then return true end
    local known = ns.db and ns.db.knownFlights and ns.db.knownFlights[faction or ""]
    if type(known) ~= "table" or next(known) == nil then return true end -- nothing learned yet: assume known
    for name in pairs(known) do if sameTown(name, townName) then return true end end
    return false
end
function R.learnFlights()
    local faction = call(UnitFactionGroup, "player")
    if not (faction and ns.db) then return 0 end
    local names = {}
    local nodes = C_TaxiMap and call(C_TaxiMap.GetAllTaxiNodes, call(C_Map and C_Map.GetBestMapForUnit, "player"))
    if type(nodes) == "table" then
        for _, node in ipairs(nodes) do
            -- state: 0 current, 1 reachable (known), 2 not reachable (not learned)
            if type(node) == "table" and node.name and (node.state == nil or node.state == 0 or node.state == 1) then names[#names + 1] = node.name end
        end
    else
        for i = 1, tonumber(call(NumTaxiNodes)) or 0 do
            local kind = call(TaxiNodeGetType, i)
            if kind == "CURRENT" or kind == "REACHABLE" then names[#names + 1] = call(TaxiNodeName, i) end
        end
    end
    if #names == 0 then return 0 end
    ns.db.knownFlights = ns.db.knownFlights or {}
    ns.db.knownFlights[faction] = ns.db.knownFlights[faction] or {}
    for _, name in ipairs(names) do ns.db.knownFlights[faction][name] = true end
    return #names
end
if ns.on then ns.on("TAXIMAP_OPENED", function() R.learnFlights() end) end

local function usable(faction, entry) return entry.faction == "Both" or entry.faction == faction end
local function groundSpeed(options)
    if finite(options.speed) and options.speed > 0 then return options.speed end
    local level = tonumber(options.level) or tonumber(call(UnitLevel, "player")) or 1
    if level >= 60 then return R.COST.epicMount elseif level >= 40 then return R.COST.mount end
    return R.COST.run
end
local function hearthReady(options)
    if options.hearth ~= nil then return options.hearth end
    if (tonumber(call(GetItemCount, R.HEARTHSTONE)) or 0) < 1 then return false, "no hearthstone in your bags" end
    local get = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    local start, duration = call(get, R.HEARTHSTONE)
    local now = tonumber(call(GetTime)) or 0
    if finite(start) and finite(duration) and start > 0 and start + duration > now then
        return false, string.format("hearthstone on cooldown (%d min left)", math.ceil((start + duration - now) / 60))
    end
    return true
end

-- Build the travel network: transit nodes plus the given stop nodes. Every node: {label, kind, point, w}.
local function network(stops, options)
    local D, faction = ns.travelData or {}, options.faction
    local nodes, edges = {}, {}
    local function add(node) if node.w then nodes[#nodes + 1] = node; node.index = #nodes; return node end end
    for _, s in ipairs(stops) do add(s) end
    local flights = {}
    for _, town in ipairs(D.towns or {}) do
        if usable(faction, town) and R.knowsFlight(town.name, faction, options.assumeAllFlights) then
            local node = add({ label = town.name, kind = "flight", zone = town.zone, point = { map = town.map, x = town.x, y = town.y },
                w = R.world(town.map, town.x, town.y) })
            if node then flights[#flights + 1] = node end
        end
    end
    local docks = {}
    for id, stop in pairs(D.stops or {}) do
        docks[id] = add({ label = stop.name, kind = "dock", zone = stop.zone, point = { map = stop.map, x = stop.x, y = stop.y },
            w = R.world(stop.map, stop.x, stop.y) })
    end
    for _, route in ipairs(D.routes or {}) do
        local a, b = docks[route.a], docks[route.b]
        if a and b and usable(faction, route) then
            local seconds = (route.seconds or R.COST.ride) + R.COST.rideWait
            edges[a.index] = edges[a.index] or {}; edges[b.index] = edges[b.index] or {}
            table.insert(edges[a.index], { to = b.index, cost = seconds, mode = route.kind })
            table.insert(edges[b.index], { to = a.index, cost = seconds, mode = route.kind })
        end
    end
    local speed = groundSpeed(options)
    local function distance(a, b) local dx, dy = a.w.x - b.w.x, a.w.y - b.w.y; return math.sqrt(dx * dx + dy * dy) end
    -- Dijkstra from one node; returns cost and previous-hop tables.
    local function from(sourceIndex)
        local cost, prev, mode, done = {}, {}, {}, {}
        cost[sourceIndex] = 0
        for _ = 1, #nodes do
            local u, best
            for i = 1, #nodes do if not done[i] and cost[i] and (not best or cost[i] < best) then u, best = i, cost[i] end end
            if not u then break end
            done[u] = true
            local a = nodes[u]
            for v = 1, #nodes do
                if not done[v] and v ~= u then
                    local b = nodes[v]
                    if a.w.c == b.w.c then
                        local d = distance(a, b)
                        local walk = best + d * R.COST.terrain / speed
                        if not cost[v] or walk < cost[v] then cost[v], prev[v], mode[v] = walk, u, "Walk" end
                        if a.kind == "flight" and b.kind == "flight" then
                            local fly = best + d * R.COST.flightDetour / R.COST.flight + R.COST.flightStop
                            if fly < cost[v] then cost[v], prev[v], mode[v] = fly, u, "Fly" end
                        end
                    end
                end
            end
            for _, e in ipairs(edges[u] or {}) do
                if not done[e.to] and (not cost[e.to] or best + e.cost < cost[e.to]) then
                    cost[e.to], prev[e.to], mode[e.to] = best + e.cost, u, e.mode
                end
            end
            if options.checkpoint then options.checkpoint() end
        end
        return cost, prev, mode
    end
    return nodes, from
end

-- Hops of one leg (merging walk hops), from a Dijkstra result.
local function hops(nodes, prev, mode, fromIndex, toIndex)
    local list, at = {}, toIndex
    while at and at ~= fromIndex do
        table.insert(list, 1, { mode = mode[at], to = nodes[at], from = nodes[prev[at]] })
        at = prev[at]
    end
    local merged = {}
    for _, h in ipairs(list) do
        local last = merged[#merged]
        if last and last.mode == "Walk" and h.mode == "Walk" then last.to = h.to else merged[#merged + 1] = h end
    end
    return merged
end

-- targets: {id, name, kind = "pickup" | "leadin", pickup = place, turnIn = place, unlocks = {questID, ...}}
--   place = {source = {name}, point = {map, x, y (0..100), dungeon}}
-- options: start = {map, x, y (0..100)}, faction, level, speed, assumeAllFlights, hearth (bool, testing),
--          bind = town name, finish = {label, point}, checkpoint = function
function R.plan(targets, options)
    options = options or {}
    options.faction = options.faction or call(UnitFactionGroup, "player") or "Alliance"
    local result = { steps = {}, totalSeconds = 0, unknown = {}, notes = {}, quests = 0 }
    local function place(p, label, kind)
        local pt = p and p.point
        if not pt or pt.dungeon or not pt.map then return nil end
        local w = R.world(pt.map, pt.x, pt.y)
        if not w then return nil end
        local npc = p.source and p.source.name
        local Q = ns.questie
        local zone = Q and Q.where and call(Q.where, pt)
        if not zone or string.sub(zone, 1, 1) == "?" then -- a point without an area (the dungeon entrance): use the map's name
            local info = C_Map and call(C_Map.GetMapInfo, pt.map)
            zone = info and info.name and string.format("%s %.1f, %.1f", info.name, pt.x, pt.y) or nil
        end
        return { label = npc or label, kind = kind, point = pt, w = w, npc = npc, zone = zone }
    end
    -- stop nodes with their precedence
    local stops, unlocker = {}, {}
    local startNode = options.start and { label = "You", kind = "start", point = options.start,
        w = R.world(options.start.map, options.start.x, options.start.y) }
    if not (startNode and startNode.w) then
        result.noStart = true
        result.notes[#result.notes + 1] = "Your position is unknown (inside a dungeon?): open the route outside."
        return result
    end
    stops[1] = startNode
    for _, t in ipairs(targets) do
        local pick = place(t.pickup, t.name, "pickup")
        if not pick then result.unknown[#result.unknown + 1] = t.name
        else
            pick.target = t;stops[#stops + 1] = pick
            if t.kind == "leadin" then
                local hand = place(t.turnIn, t.name, "handin")
                if hand then
                    hand.target, hand.after = t, { pick }
                    stops[#stops + 1] = hand
                    for _, id in ipairs(t.unlocks or {}) do unlocker[id] = hand end
                else
                    pick.kind = "pickup";result.notes[#result.notes + 1] = t.name .. ": hand-in location unknown, take it and follow it in game."
                end
            else result.quests = result.quests + 1 end
        end
    end
    for _, s in ipairs(stops) do
        if s.kind == "pickup" and s.target and unlocker[s.target.id] then s.after = { unlocker[s.target.id] } end
    end
    if #stops == 1 then result.nothing = true; return result end -- nothing to pick up: no route to the entrance either
    local finish = options.finish and place({ point = options.finish.point, source = { name = options.finish.label } }, options.finish.label, "finish")
    if options.finish and not finish then result.notes[#result.notes + 1] = "Dungeon entrance not placed on the map; the route ends at the last quest." end
    if finish then stops[#stops + 1] = finish end
    -- hearthstone home
    local ready, why = hearthReady(options)
    local home
    local bind = options.bind or call(GetBindLocation)
    if ready and bind then
        for _, town in ipairs((ns.travelData or {}).towns or {}) do
            if sameTown(town.name, bind) or sameTown(town.zone, bind) then
                home = { label = town.name, kind = "home", point = { map = town.map, x = town.x, y = town.y }, w = R.world(town.map, town.x, town.y) }
                if home.w then stops[#stops + 1] = home else home = nil end
                break
            end
        end
        if not home then result.notes[#result.notes + 1] = "Hearthstone not used: " .. tostring(bind) .. " is not a known town." end
    elseif not ready then result.notes[#result.notes + 1] = "Hearthstone not used: " .. tostring(why or "not ready") .. "." end

    local nodes, from = network(stops, options)
    -- leg costs between stop nodes
    local legs = {}
    for _, a in ipairs(stops) do
        if a.index then
            local cost, prev, mode = from(a.index)
            legs[a] = { cost = cost, prev = prev, mode = mode }
        end
    end
    local function leg(a, b) local l = legs[a]; return l and l.cost[b.index] or math.huge end

    -- order: start first, finish last, home is not a stop to visit (only a hearth target)
    local todo = {}
    for _, s in ipairs(stops) do if s ~= startNode and s ~= finish and s ~= home and s.index then todo[#todo + 1] = s end end
    local function valid(order)
        local seen = {}
        for _, s in ipairs(order) do
            for _, need in ipairs(s.after or {}) do if not seen[need] then return false end end
            seen[s] = true
        end
        return true
    end
    local function total(order)
        local sum, at = 0, startNode
        for _, s in ipairs(order) do sum = sum + leg(at, s); at = s end
        if finish then sum = sum + leg(at, finish) end
        return sum
    end
    -- nearest eligible first
    local order, used, at = {}, {}, startNode
    for _ = 1, #todo do
        local best, bestCost
        for _, s in ipairs(todo) do
            if not used[s] then
                local ok = true
                for _, need in ipairs(s.after or {}) do if not used[need] then ok = false end end
                local c = ok and leg(at, s) or math.huge
                if ok and (not bestCost or c < bestCost) then best, bestCost = s, c end
            end
        end
        if not best then break end
        used[best] = true;order[#order + 1] = best;at = best
    end
    -- improve: move one stop, or reverse a segment, while it gets shorter and stays valid
    local bestCost, improved, rounds = total(order), true, 0
    while improved and rounds < 50 do
        improved, rounds = false, rounds + 1
        for i = 1, #order do
            for j = 1, #order do
                if i ~= j then
                    local try = {}
                    for k, s in ipairs(order) do if k ~= i then try[#try + 1] = s end end
                    table.insert(try, j, order[i])
                    if valid(try) then
                        local c = total(try)
                        if c + 0.5 < bestCost then order, bestCost, improved = try, c, true end
                    end
                end
            end
            for j = i + 2, #order do
                local try = {}
                for k = 1, #order do try[k] = order[k] end
                for k = 0, math.floor((j - i) / 2) do try[i + k], try[j - k] = try[j - k], try[i + k] end
                if valid(try) then
                    local c = total(try)
                    if c + 0.5 < bestCost then order, bestCost, improved = try, c, true end
                end
            end
            if options.checkpoint then options.checkpoint() end
        end
    end
    -- the hearthstone: on the one leg where it saves the most
    local path = { startNode }
    for _, s in ipairs(order) do path[#path + 1] = s end
    if finish then path[#path + 1] = finish end
    local hearthLeg, saving = nil, 0
    if home then
        for i = 2, #path do
            local direct = leg(path[i - 1], path[i])
            local via = R.COST.hearth + leg(home, path[i])
            if direct - via > saving then hearthLeg, saving = i, direct - via end
        end
    end
    -- steps
    local function addHops(fromNode, toNode)
        local l = legs[fromNode]
        for _, h in ipairs(hops(nodes, l.prev, l.mode, fromNode.index, toNode.index)) do
            local seconds = l.cost[h.to.index] - (l.cost[h.from.index] or 0)
            if not (h.mode == "Walk" and seconds < 5) then result.steps[#result.steps + 1] = { kind = h.mode, from = h.from.label, to = h.to.label, zone = h.to.zone, npc = h.to.npc,
                point = h.to.point, seconds = seconds } end
        end
    end
    for i = 2, #path do
        local a, b = path[i - 1], path[i]
        if i == hearthLeg then
            result.steps[#result.steps + 1] = { kind = "Hearth", to = home.label, point = home.point, seconds = R.COST.hearth }
            addHops(home, b)
            result.totalSeconds = result.totalSeconds + R.COST.hearth + leg(home, b)
            result.hearthUsed = true
        else
            addHops(a, b)
            result.totalSeconds = result.totalSeconds + leg(a, b)
        end
        if b.kind == "pickup" or b.kind == "handin" then
            result.steps[#result.steps + 1] = { kind = b.kind == "pickup" and "Pick up" or "Hand in", quest = b.target.name,
                npc = b.npc, point = b.point, leadin = b.target.kind == "leadin", seconds = R.COST.talk }
            result.totalSeconds = result.totalSeconds + R.COST.talk
        elseif b.kind == "finish" then
            result.steps[#result.steps + 1] = { kind = "Enter", to = b.label, point = b.point, seconds = 0 }
        end
    end
    local grouped = {}
    for _, st in ipairs(result.steps) do
        local last = grouped[#grouped]
        if last and (st.kind == "Pick up" or st.kind == "Hand in") and last.kind == st.kind and last.npc and last.npc == st.npc then
            last.quests = last.quests or { last.quest }
            last.quests[#last.quests + 1] = st.quest
            last.leadin = last.leadin and st.leadin
            last.seconds = (last.seconds or 0) + (st.seconds or 0)
        else grouped[#grouped + 1] = st end
    end
    result.steps = grouped
    if home and not result.hearthUsed then result.notes[#result.notes + 1] = "Hearthstone not needed: it would not save time on this route." end
    return result
end
