-- World map overlay: every dungeon entrance, the boat / zeppelin / tram links, and (on hover) the lines between them.
-- Hover a transport pin to see where it goes; hover a dungeon to see the nearest town each faction can use.
-- Reads only addon data (TravelData.lua) and draws addon-owned frames over Blizzard's map canvas.
local ADDON, ns = ...
local U, S, D, V = ns.optionalUI, ns.style, ns.travelData, ns.vendorMap
local T = {}
ns.travelMap = T

local call = U.call
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function combat() return call(InCombatLockdown) end

-- Neutral (both factions) is white: white pin, white line, white label.
local COLORS = { Alliance = { 0.25, 0.5, 1 }, Horde = { 0.9, 0.2, 0.2 }, Both = { 1, 1, 1 } }
local WORDS = { Alliance = S.BLUE .. "Alliance|r", Horde = S.RED .. "Horde|r", Both = S.WHITE .. "Neutral|r" }
-- Settings > Map "Show": "mine" (your own faction, the default), "all", "Alliance" or "Horde".
-- Neutral routes and towns always count. "mine" falls back to both when the game has no faction yet.
local function shownFaction()
    local pick = ns.db.travelFaction
    if pick == "mine" then return call(UnitFactionGroup, "player") or "all" end
    return pick
end
local function allowed(faction)
    local pick = shownFaction()
    if pick == "Alliance" or pick == "Horde" then return faction == pick or faction == "Both" end
    return true
end
local LETTERS = { Boat = "B", Zeppelin = "Z", Tram = "T" }
local ASPECT = 2 / 3 -- continent maps are about 3:2, so a vertical step counts less than a horizontal one

-- stops[id] = { id, name, zone, map, x, y, links = { { stop, kind, faction } }, kind, faction }
local stops, stopList = {}, {}
for id, s in pairs(D.stops) do
    stops[id] = { id = id, name = s.name, zone = s.zone, map = s.map, x = s.x, y = s.y, links = {} }
    stopList[#stopList + 1] = stops[id]
end
table.sort(stopList, function(a, b) return a.id < b.id end)
for _, route in ipairs(D.routes) do
    local a, b = stops[route.a], stops[route.b]
    if a and b then
        for _, pair in ipairs({ { a, b }, { b, a } }) do
            local from, to = pair[1], pair[2]
            from.links[#from.links + 1] = { stop = to, kind = route.kind, faction = route.faction }
            from.kind = from.kind or route.kind
            from.faction = (from.faction == nil or from.faction == route.faction) and route.faction or "Both"
        end
    end
end

local layer, layerParent, canvas, pins, lines, callouts, lastView, hovered = nil, nil, nil, {}, {}, {}, nil, nil

local function project(entry, target)
    if not (V and V.pointOnMap) then return nil end
    return V.pointOnMap(entry.map, entry.x / 100, entry.y / 100, target) -- two values
end

-- continent, x, y of an entry; static, so computed once
local flat = {}
local function continentOf(entry)
    local hit = flat[entry]
    if hit == nil then
        local c, x, y = nil, nil, nil
        if V and V.continentPoint then c, x, y = V.continentPoint(entry.map, entry.x / 100, entry.y / 100) end
        hit = c and { c, x, y } or false
        if hit then flat[entry] = hit end
    end
    return hit or nil
end

-- the closest town a faction may use, on the entrance's own continent
function T.nearestTown(entry, faction)
    local here = continentOf(entry)
    if not here then return nil end
    local best, bestDistance
    for _, town in ipairs(D.towns) do
        if town.faction == faction or town.faction == "Both" then
            local there = continentOf(town)
            if there and there[1] == here[1] then
                local dx, dy = there[2] - here[2], (there[3] - here[3]) * ASPECT
                local distance = dx * dx + dy * dy
                if not bestDistance or distance < bestDistance then best, bestDistance = town, distance end
            end
        end
    end
    return best
end

-- The player's own class and profession trainers (their faction only) on the shown zone or continent map, grouped
-- where they overlap. Starts the index the first time and returns nothing until it has finished.
local MAX_TRAINER_PINS, CELL = 300, 22
function T.trainerGroups(map, known, width, height, scale)
    local I = ns.trainerIndex
    local out = {}
    if not (I and ns.db.myTrainers) then return out end
    local info = call(C_Map and C_Map.GetMapInfo, map)
    local kind = info and info.mapType
    local types = Enum and Enum.UIMapType
    if not (types and (kind == types.Zone or kind == types.Continent)) then I.pause(); return out end
    I.start()
    if I.state() ~= "done" then return out end
    local faction, cells = I.faction(), {}
    for _, entry in ipairs(I.entries()) do
        if known[entry.kind] and I.usable(entry, faction) then
            for _, spawn in ipairs(entry.spawns or {}) do
                if spawn.map and not spawn.dungeon and spawn.x >= 0 and spawn.x <= 100 and spawn.y >= 0 and spawn.y <= 100 then
                    local x, y = V.pointOnMap(spawn.map, spawn.x / 100, spawn.y / 100, map)
                    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                        local key = math.floor(x * width * scale / CELL) .. ":" .. math.floor(y * height * scale / CELL)
                        local group = cells[key]
                        if not group and #out < MAX_TRAINER_PINS then
                            group = { kind = "trainer", x = x, y = y, members = {} }
                            cells[key] = group; out[#out + 1] = group
                        end
                        if group then group.members[#group.members + 1] = { entry = entry, spawn = spawn } end
                    end
                end
            end
        end
    end
    return out
end

local function placeLine(index, x1, y1, x2, y2, width, height, scale, color)
    local stroke = lines[index]
    if not stroke then
        local under = layer:CreateLine(nil, "BACKGROUND")
        under:SetColorTexture(0.02, 0.02, 0.02, 0.85)
        stroke = layer:CreateLine(nil, "ARTWORK")
        stroke:SetColorTexture(1, 1, 1, 1)
        stroke.under = under
        lines[index] = stroke
    end
    stroke.under:SetThickness(5 / scale)
    stroke.under:SetStartPoint("TOPLEFT", layer, x1 * width, -y1 * height)
    stroke.under:SetEndPoint("TOPLEFT", layer, x2 * width, -y2 * height)
    stroke.under:Show()
    stroke:SetThickness(2.5 / scale)
    stroke:SetVertexColor(color[1], color[2], color[3], 1)
    stroke:SetStartPoint("TOPLEFT", layer, x1 * width, -y1 * height)
    stroke:SetEndPoint("TOPLEFT", layer, x2 * width, -y2 * height)
    stroke:Show()
end

local function calloutFor(index)
    if callouts[index] then return callouts[index] end
    local c = CreateFrame("Frame", nil, layer)
    c:SetWidth(120); c:SetHeight(14); c:EnableMouse(false)
    c.dot = S.fill(c, "ARTWORK", 1, 1, 1, 1)
    c.dot:SetWidth(10); c.dot:SetHeight(10); c.dot:SetPoint("LEFT", c, "LEFT", 0, 0)
    c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.text:SetPoint("LEFT", c, "LEFT", 14, 0)
    callouts[index] = c
    return c
end

local function clearHover()
    for _, line in ipairs(lines) do line:Hide(); line.under:Hide() end
    for _, c in ipairs(callouts) do c:Hide() end
end

local function geometry()
    local width, height = call(canvas.GetWidth, canvas), call(canvas.GetHeight, canvas)
    local scale = call(canvas.GetScale, canvas) or 1
    if not (finite(width) and finite(height) and width > 0 and height > 0) then return nil end
    if not finite(scale) or scale <= 0 then scale = 1 end
    return width, height, scale
end

-- lines from `pin` to each target that is visible on the shown map; returns how many targets were off the map
local function connect(pin, targets)
    local wm = WorldMapFrame
    local shown = wm and call(wm.GetMapID, wm)
    local width, height, scale = geometry()
    if not (shown and width and type(layer.CreateLine) == "function") then return #targets end
    local x1, y1 = project(pin.entry, shown)
    local missing, used, notes = 0, 0, 0
    for _, target in ipairs(targets) do
        local x2, y2
        if x1 then x2, y2 = project(target.entry, shown) end
        if x2 then
            used = used + 1
            placeLine(used, x1, y1, x2, y2, width, height, scale, target.color)
            if target.label then
                notes = notes + 1
                local c = calloutFor(notes)
                c.dot:SetVertexColor(target.color[1], target.color[2], target.color[3], 1)
                c.text:SetText(target.label)
                c:ClearAllPoints(); c:SetScale(1 / scale)
                c:SetPoint("LEFT", layer, "TOPLEFT", x2 * width * scale + 8, -y2 * height * scale)
                c:Show()
            end
        else
            missing = missing + 1
        end
    end
    for i = used + 1, #lines do lines[i]:Hide(); lines[i].under:Hide() end
    for i = notes + 1, #callouts do callouts[i]:Hide() end
    return missing
end

local function stopTip(pin)
    local entry = pin.entry
    local lines_ = {}
    local targets = {}
    for _, link in ipairs(entry.links) do
        if allowed(link.faction) then
            lines_[#lines_ + 1] = link.kind .. " to " .. link.stop.name .. " (" .. link.stop.zone .. ") · " .. WORDS[link.faction]
            targets[#targets + 1] = { entry = link.stop, color = COLORS[link.faction] }
        end
    end
    local missing = connect(pin, targets)
    if missing > 0 then lines_[#lines_ + 1] = S.GREY .. "Open the Azeroth map to see the whole line.|r" end
    lines_[#lines_ + 1] = S.GREY .. "Click to set a waypoint.|r"
    U.tip(pin, entry.name .. " · " .. entry.zone, lines_)
end

local function dungeonTip(pin)
    local entry = pin.entry
    local lines_, targets = {}, {}
    for _, inside in ipairs(entry.inside) do
        lines_[#lines_ + 1] = inside[1] .. " · level " .. inside[2]
    end
    lines_[#lines_ + 1] = " "
    -- One faction shown: the towns it can use. Both shown: each side's town, so "you can use" would be wrong for one.
    local both = allowed("Alliance") and allowed("Horde")
    lines_[#lines_ + 1] = both and "Closest flight master towns:" or "Closest flight master town you can use:"
    for _, faction in ipairs({ "Alliance", "Horde" }) do
        local town = allowed(faction) and T.nearestTown(entry, faction)
        if town then
            local neutral = town.faction == "Both"
            lines_[#lines_ + 1] = WORDS[faction] .. ": " .. town.name .. " (" .. town.zone .. ")"
                .. (neutral and " · " .. WORDS.Both or "")
            targets[#targets + 1] = { entry = town, color = neutral and COLORS.Both or COLORS[faction], label = town.name }
        elseif allowed(faction) then
            lines_[#lines_ + 1] = WORDS[faction] .. ": none known on this continent"
        end
    end
    connect(pin, targets)
    lines_[#lines_ + 1] = S.GREY .. "Click to set a waypoint.|r"
    U.tip(pin, entry.name, lines_)
end

local function zoneName(area)
    local name = call(C_Map and C_Map.GetAreaInfo, area) or (GetAreaInfo and call(GetAreaInfo, area))
    return type(name) == "string" and name or "Unknown zone"
end

local function trainerTip(pin)
    local lines_ = {}
    for i, member in ipairs(pin.entry.members) do
        if i > 8 then lines_[#lines_ + 1] = "More trainers stand here."; break end
        local e, sp = member.entry, member.spawn
        lines_[#lines_ + 1] = e.name .. " · " .. e.title .. " (" .. zoneName(sp.area) .. string.format(" %.1f, %.1f", sp.x, sp.y) .. ")"
    end
    lines_[#lines_ + 1] = S.GREY .. "Click to set a waypoint.|r"
    U.tip(pin, "Your trainers", lines_)
end

local function makePin(kind)
    -- every pin is a button: a click puts the game's waypoint on it, as on vendor, gather and trainer pins
    local pin = CreateFrame("Button", nil, layer)
    pin:SetWidth(18); pin:SetHeight(18); pin:EnableMouse(true)
    pin:RegisterForClicks("LeftButtonUp")
    if kind == "trainer" then
        pin:SetWidth(20); pin:SetHeight(20)
        pin.ring = S.fill(pin, "BACKGROUND", 1, 0.82, 0, 1); pin.ring:SetAllPoints(pin) -- gold rim: this one is yours
        pin.icon = pin:CreateTexture(nil, "ARTWORK")
        pin.icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 2, -2); pin.icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -2, 2)
        pin:SetScript("OnClick", function(self)
            local sp = self.entry and self.entry.members[1].spawn
            if sp and not ns.compat.setWaypoint(sp.map, sp.x / 100, sp.y / 100) then
                ns.print("the game could not set a waypoint for this trainer")
            end
        end)
    else
        pin:SetScript("OnClick", function(self)
            local e = self.entry
            if e and not ns.compat.setWaypoint(e.map, e.x / 100, e.y / 100) then
                ns.print("the game could not set a waypoint here")
            end
        end)
    end
    if kind == "dungeon" then
        pin.icon = pin:CreateTexture(nil, "OVERLAY")
        pin.icon:SetAllPoints(pin)
        pin.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8") -- skull
    elseif kind ~= "trainer" then
        pin.border = S.fill(pin, "BACKGROUND", 0, 0, 0, 1); pin.border:SetAllPoints(pin)
        pin.face = S.fill(pin, "ARTWORK", 1, 1, 1, 1)
        pin.face:SetPoint("TOPLEFT", pin, "TOPLEFT", 2, -2); pin.face:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -2, 2)
        pin.text = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pin.text:SetAllPoints(pin)
    end
    pin.kind = kind
    pin:SetScript("OnEnter", function(self)
        hovered = self
        if self.kind == "dungeon" then dungeonTip(self)
        elseif self.kind == "trainer" then trainerTip(self)
        else stopTip(self) end
    end)
    pin:SetScript("OnLeave", function(self)
        if hovered == self then hovered = nil end
        clearHover(); U.hideTip()
    end)
    return pin
end

local function level(frame, base, strata)
    if strata and call(frame.GetFrameStrata, frame) ~= strata then frame:SetFrameStrata(strata) end
    call(frame.SetFrameLevel, frame, base)
end

local function hide()
    if layer then layer:Hide() end
    -- a hidden pin never gets OnLeave, so drop its tooltip and lines here
    if hovered then clearHover(); U.hideTip() end
    hovered, lastView = nil, nil
end

function T.draw()
    local wm = WorldMapFrame
    local child = wm and wm.ScrollContainer and wm.ScrollContainer.Child
    local on = ns.db.enabled and (ns.db.travelMap or ns.db.myTrainers) and not ns.isBlocked("travelmap")
    if not (on and child and call(wm.IsShown, wm)) or combat() or not (V and V.pointOnMap) then hide(); return end
    local map = call(wm.GetMapID, wm)
    local width, height, scale = nil, nil, nil
    canvas = canvas or child
    if canvas ~= child then canvas = child; lastView = nil end
    width, height, scale = geometry()
    if not (map and width) then hide(); return end
    if not layer then
        layer = CreateFrame("Frame", "QuestSharingTravelOverlay", UIParent)
        layer:EnableMouse(false)
    end
    if layerParent ~= child then layer:SetParent(child); layer:SetAllPoints(child); layerParent = child; lastView = nil end
    local I = ns.trainerIndex
    local known, knownKey = {}, ""
    if I and ns.db.myTrainers then known, knownKey = I.known() end
    local searching = V.querying and V.querying() or false
    if lastView and lastView.map == map and lastView.width == width and lastView.height == height
        and lastView.scale == scale and lastView.known == knownKey and lastView.searching == searching and lastView.travel == ns.db.travelMap
        and lastView.faction == shownFaction()
        and lastView.revision == (I and I.revision) then layer:Show(); return end
    ns.trying("drawing dungeon and travel pins on the world map", "travelmap") -- a failure here turns the overlay off
    layer:Show(); clearHover(); hovered = nil
    local strata = call(child.GetFrameStrata, child)
    -- Well above Blizzard's own map icons (a city icon must not sit over a zeppelin pin); transports on top of all.
    local base = math.min(9900, (call(child.GetFrameLevel, child) or 0) + 5000)
    level(layer, base, strata)
    local used = { dungeon = 0, stop = 0, trainer = 0 }
    local LEVELS = { trainer = 1, dungeon = 2, stop = 3 }
    local taken = {} -- where a dungeon or transport pin stands, so a trainer pin never hides one
    local function put(kind, entry)
        if kind == "stop" then
            local any = false
            for _, link in ipairs(entry.links) do if allowed(link.faction) then any = true; break end end
            if not any then return end
        end
        local x, y = project(entry, map)
        if not x then return end
        used[kind] = used[kind] + 1
        local list = pins[kind]
        local pin = list[used[kind]] or makePin(kind)
        list[used[kind]] = pin
        pin.entry = entry
        level(pin, base + LEVELS[kind], strata)
        if kind == "stop" then
            local c = COLORS[entry.faction] or COLORS.Both
            pin.face:SetVertexColor(c[1], c[2], c[3], 1)
            -- the letter must read on the pin: black on the white neutral pin, white on blue and red
            pin.text:SetText((entry.faction == "Both" and "|cff000000" or S.WHITE) .. (LETTERS[entry.kind] or "?") .. "|r")
        end
        taken[#taken + 1] = { x * width * scale, -y * height * scale }
        pin:ClearAllPoints(); pin:SetScale(1 / scale)
        pin:SetPoint("CENTER", layer, "TOPLEFT", x * width * scale, -y * height * scale)
        pin:Show()
    end
    pins.dungeon, pins.stop, pins.trainer = pins.dungeon or {}, pins.stop or {}, pins.trainer or {}
    if ns.db.travelMap then
        for _, dungeon in ipairs(D.dungeons) do put("dungeon", dungeon) end
        for _, stop in ipairs(stopList) do put("stop", stop) end
    end
    if not searching then
        for _, group in ipairs(T.trainerGroups(map, known, width, height, scale)) do
            used.trainer = used.trainer + 1
            local pin = pins.trainer[used.trainer] or makePin("trainer")
            pins.trainer[used.trainer] = pin
            pin.entry = group
            level(pin, base + LEVELS.trainer, strata)
            local first = group.members[1].entry
            local texture, coords = V.iconFor(first.title)
            pin.icon:SetTexture(texture)
            if coords then pin.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else pin.icon:SetTexCoord(0, 1, 0, 1) end
            pin:ClearAllPoints(); pin:SetScale(1 / scale)
            local ox, oy = group.x * width * scale, -group.y * height * scale
            for _, spot in ipairs(taken) do          -- stand beside a dungeon or transport pin, not under it
                if math.abs(ox - spot[1]) < 19 and math.abs(oy - spot[2]) < 19 then ox, oy = spot[1] + 20, spot[2] - 12; break end
            end
            pin:SetPoint("CENTER", layer, "TOPLEFT", ox, oy)
            pin:Show()
        end
    end
    for kind, list in pairs(pins) do
        for i = used[kind] + 1, #list do list[i]:Hide() end
    end
    lastView = { map = map, width = width, height = height, scale = scale, known = knownKey, searching = searching, travel = ns.db.travelMap,
        faction = shownFaction(), revision = I and I.revision }
end

function T.refresh() lastView = nil; T.draw() end

-- test hook: the pins currently shown
function T._pins()
    local out = {}
    for _, list in pairs(pins) do
        for _, pin in ipairs(list) do if pin:IsShown() then out[#out + 1] = pin end end
    end
    return out
end

local function tick()
    local wm = WorldMapFrame
    -- reschedule first: the timer is removed before it runs, so an error in draw must not end the loop
    ns.after(ns.db.enabled and (ns.db.travelMap or ns.db.myTrainers) and wm and call(wm.IsShown, wm) and 0.5 or 2, tick)
    T.draw()
end
ns.on("PLAYER_LOGIN", function() ns.after(1, tick) end)
ns.on("WORLD_MAP_UPDATE", T.refresh)
ns.on("PLAYER_REGEN_DISABLED", hide)
ns.on("PLAYER_REGEN_ENABLED", T.refresh)
