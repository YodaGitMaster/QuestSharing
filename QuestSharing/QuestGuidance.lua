-- Read-only guidance for the current quest-plan step; no database reads or terrain search.
local ADDON, ns = ...
local G, C, U, S = {}, ns.compat, ns.optionalUI, ns.style
ns.questGuidance = G
local route, selected, owner, choose, targetWorld, mapSize
local hud, layer, canvas, legend, lastView, hovered, pressed
local markers, lines, underlines, dots = {}, {}, {}, {}
local revision, elapsed, mapElapsed, metricWait = 0, 0, 0, 0
local drawMap
local PI = math.pi
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function call(fn, ...) return U.call(fn, ...) end
local function combat() return call(InCombatLockdown) end
local function visible(f) return f and call(f.IsShown, f) end
local function valid(p)
    return type(p) == "table" and finite(p.map) and p.map > 0 and finite(p.x) and finite(p.y)
        and p.x >= 0 and p.x <= 1 and p.y >= 0 and p.y <= 1
end
local function inZone(map, zone)
    local seen = {}
    for _ = 1, 12 do
        if map == zone then return true end
        if not map or seen[map] then return false end
        seen[map] = true
        local info = call(C_Map and C_Map.GetMapInfo, map)
        map = info and info.parentMapID
    end
    return false
end
local function world(p)
    if not (valid(p) and C_Map and type(C_Map.GetWorldPosFromMapPos) == "function" and CreateVector2D) then return end
    local continent, pos = call(C_Map.GetWorldPosFromMapPos, p.map, CreateVector2D(p.x, p.y))
    if not (continent and pos) then return end
    local north, west
    if type(pos.GetXY) == "function" then north, west = call(pos.GetXY, pos) else north, west = pos.x, pos.y end
    if finite(north) and finite(west) then return { map = continent, north = north, west = west } end
end
local function refreshMetrics(point)
    targetWorld = targetWorld or world(point)
    if not mapSize then
        local width, height = call(C_Map and C_Map.GetMapWorldSize, point.map)
        if finite(width) and finite(height) and width > 0 and height > 0 then mapSize = { width = width, height = height } end
    end
    metricWait = 1
end
local function atan2(y, x)
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and PI or -PI) end
    return y > 0 and PI / 2 or y < 0 and -PI / 2 or 0
end
local function direction(north, west)
    local a = atan2(west, north)
    local names = { "N", "NW", "W", "SW", "S", "SE", "E", "NE" }
    return names[math.floor((a % (2 * PI)) / (PI / 4) + 0.5) % 8 + 1], a
end
local function hideMap()
    if layer then layer:Hide() end
    hovered, pressed, lastView = nil, nil, nil
end
function G.clear()
    route, selected, owner, choose, targetWorld, mapSize = nil, nil, nil, nil, nil, nil
    elapsed, mapElapsed, metricWait = 0, 0, 0
    if hud then hud:Hide(); hud:SetScript("OnUpdate", nil) end
    for _, marker in ipairs(markers) do marker.steps = nil; marker:Hide() end
    hideMap()
end

-- The only projection fallback is a verified ancestor/descendant rectangle chain, never sibling maps.
local function ascend(p, target)
    local id, x, y, seen = p.map, p.x, p.y, {}
    for _ = 1, 12 do
        if id == target then return x, y end
        if seen[id] then return end
        seen[id] = true
        local info = call(C_Map and C_Map.GetMapInfo, id)
        local parent = info and info.parentMapID
        if not parent or parent == 0 then return end
        -- U.call intentionally returns only three values; map rectangles require all four.
        local fn = C_Map and C_Map.GetMapRectOnMap
        local ok, left, right, top, bottom
        if type(fn) == "function" then ok, left, right, top, bottom = pcall(fn, id, parent) end
        if not (ok and finite(left) and finite(right) and finite(top) and finite(bottom)
            and left >= 0 and right <= 1 and top >= 0 and bottom <= 1 and right > left and bottom > top) then return end
        x, y, id = left + x * (right - left), top + y * (bottom - top), parent
    end
end
local function project(p, map)
    if not valid(p) then return end
    local x, y = ascend(p, map)
    if not x then
        local left, top = ascend({ map = map, x = 0, y = 0 }, p.map)
        local right, bottom = ascend({ map = map, x = 1, y = 1 }, p.map)
        if left and right and right > left and bottom > top then
            x, y = (p.x - left) / (right - left), (p.y - top) / (bottom - top)
        end
    end
    if finite(x) and finite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

-- Native/addon map pins use levels hundreds above the canvas, and the map can re-level its canvas later:
-- restate strata and levels on every draw and map show, touching only values that differ.
local function setLevel(frame, level, strata)
    if strata and call(frame.GetFrameStrata, frame) ~= strata then frame:SetFrameStrata(strata) end
    if call(frame.GetFrameLevel, frame) ~= level then frame:SetFrameLevel(level) end
end
local function stack()
    if not (layer and canvas) then return end
    local strata = call(canvas.GetFrameStrata, canvas)
    local level = math.min(9900, (call(canvas.GetFrameLevel, canvas) or 0) + 2000)
    setLevel(layer, level, strata); setLevel(legend, level + 1, strata)
    for _, pin in ipairs(markers) do setLevel(pin, level + (pin.selectedStop and 3 or 2), strata) end
end
-- A step number is a round gold-ringed coin: a dark outline, a gold ring and a deep-brown face, built from the
-- addon's own proven round disc texture (Quick chat uses it too). A label wider than the coin stretches it into a
-- pill with round ends: two discs for the ends and a flat rectangle between them. The selected step is larger.
local DISC = "Interface\\Minimap\\UI-Minimap-Background"
local COIN, COIN_SELECTED = 28, 32
local function badgeWidth(chars) return math.max(COIN, chars * 8 + 12) end
local function newShape(pin, sub)
    local shape = { left = pin:CreateTexture(nil, "ARTWORK"), right = pin:CreateTexture(nil, "ARTWORK"),
        mid = S.fill(pin, "ARTWORK", 1, 1, 1, 1) }
    shape.left:SetTexture(DISC); shape.right:SetTexture(DISC)
    for _, part in pairs(shape) do if part.SetDrawLayer then part:SetDrawLayer("ARTWORK", sub) end end
    return shape
end
-- Fit one shape inside the pin frame, `inset` px from every edge: full-circle ends, flat middle.
local function fitShape(shape, pin, height, inset)
    local d = height - 2 * inset
    for _, end_ in ipairs({ { shape.left, "LEFT", inset }, { shape.right, "RIGHT", -inset } }) do
        local part = end_[1]
        part:ClearAllPoints(); part:SetWidth(d); part:SetHeight(d); part:SetPoint(end_[2], pin, end_[2], end_[3], 0)
    end
    shape.mid:ClearAllPoints()
    shape.mid:SetPoint("TOPLEFT", pin, "TOPLEFT", inset + d / 2, -inset)
    shape.mid:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -(inset + d / 2), inset)
end
local function tintShape(shape, r, g, b)
    for _, part in pairs(shape) do part:SetVertexColor(r, g, b, 1) end
end
-- The game draws its own ! and ? icon centred on a quest giver or turn-in NPC. A step number for that spot hangs
-- off it instead: its bottom-left corner sits NATIVE_DX px right and NATIVE_DY px up on screen (zoom-constant),
-- so the icon cannot hide the number. Camps have no native icon and stay centred on their exact spot.
local NATIVE_DX, NATIVE_DY = 8, 6
local function makeMarker()
    -- Avoid map pin pools/data providers and click scripts traversed by the client's secure gamepad cursor.
    local pin = CreateFrame("Frame", nil, layer)
    pin:SetWidth(COIN); pin:SetHeight(COIN); pin:EnableMouse(true)
    -- Outline, gold ring (coloured per draw) and face stack in that order: readable on light and dark map art.
    pin.edge, pin.rim, pin.face = newShape(pin, -3), newShape(pin, -2), newShape(pin, -1)
    pin.text = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pin.text:SetAllPoints(pin)
    -- FontString flags must never be nil; keep the template's (locale) font file, only larger and outlined.
    pin.text:SetFont(call(pin.text.GetFont, pin.text) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    call(pin.text.SetShadowOffset, pin.text, 1, -1); call(pin.text.SetShadowColor, pin.text, 0, 0, 0, 1)
    pin:SetScript("OnEnter", function(self)
        hovered = self
        local details = { "Click to select; repeated clicks cycle stops at this location." }
        for i, index in ipairs(self.steps or {}) do
            if i > 12 then details[#details + 1] = "More steps share this location."; break end
            local stop = route and route[index]
            details[#details + 1] = index .. ". " .. (stop and stop.destination or "Quest stop")
        end
        U.tip(self, "Quest route stops", details)
    end)
    pin:SetScript("OnLeave", function(self) if hovered == self then hovered = nil end; U.hideTip() end)
    return pin
end
local function segment(index, x1, y1, x2, y2, width, height, scale, active)
    local dx, dy = (x2 - x1) * width, (y2 - y1) * height
    local length = math.sqrt(dx * dx + dy * dy) * scale
    if length < 2 then return index end
    if type(layer.CreateLine) == "function" then
        index = index + 1
        local stroke = lines[index]
        if not stroke then
            local under = layer:CreateLine(nil, "BACKGROUND"); underlines[index] = under
            under:SetColorTexture(0.025, 0.025, 0.02, 0.8)
            stroke = layer:CreateLine(nil, "ARTWORK"); lines[index] = stroke
            stroke:SetColorTexture(1, 1, 1, 1)
        end
        local under = underlines[index]
        under:SetThickness(4 / scale)
        under:SetStartPoint("TOPLEFT", layer, x1 * width, -y1 * height)
        under:SetEndPoint("TOPLEFT", layer, x2 * width, -y2 * height); under:Show()
        stroke:SetThickness(2 / scale)
        stroke:SetVertexColor(active and 1 or 0.7, active and 0.77 or 0.76, active and 0.3 or 0.8, active and 1 or 0.55)
        stroke:SetStartPoint("TOPLEFT", layer, x1 * width, -y1 * height)
        stroke:SetEndPoint("TOPLEFT", layer, x2 * width, -y2 * height)
        stroke:Show()
    else
        -- Older clients: a bounded reusable breadcrumb pool, never a per-update texture allocation.
        local count = math.min(40, math.max(2, math.ceil(length / 12)))
        for i = 1, count do
            if index >= 800 then break end
            index = index + 1
            local dot = dots[index]
            if not dot then dot = S.fill(layer, "ARTWORK", 1, 1, 1, 1); dots[index] = dot end
            local t = i / (count + 1)
            dot:ClearAllPoints(); dot:SetWidth(3 / scale); dot:SetHeight(3 / scale)
            dot:SetPoint("CENTER", layer, "TOPLEFT", (x1 + (x2 - x1) * t) * width, -(y1 + (y2 - y1) * t) * height)
            dot:SetVertexColor(active and 1 or 0.7, active and 0.77 or 0.76, active and 0.3 or 0.8, active and 1 or 0.55)
            dot:Show()
        end
    end
    return index
end

drawMap = function()
    local wm = WorldMapFrame
    local child = wm and wm.ScrollContainer and wm.ScrollContainer.Child
    if not (route and owner and visible(owner) and visible(wm) and child) or combat() then hideMap(); return end
    local map = call(wm.GetMapID, wm)
    local width, height, scale = call(child.GetWidth, child), call(child.GetHeight, child), call(child.GetScale, child) or 1
    if not (finite(width) and finite(height) and width > 0 and height > 0 and finite(scale) and scale > 0) then hideMap(); return end
    if lastView and lastView.map == map and lastView.width == width and lastView.height == height
        and lastView.scale == scale and lastView.revision == revision and canvas == child then stack(); return end
    if not layer then
        layer = CreateFrame("Frame", "QuestSharingRouteOverlay", UIParent)
        layer:EnableMouse(false)
        legend = CreateFrame("Frame", nil, layer)
        legend:SetWidth(246); legend:SetHeight(20); legend:EnableMouse(false)
        S.panel(legend)
        legend.text = legend:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        legend.text:SetAllPoints(legend)
        legend:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 8, 8)
        legend.text:SetText("Quest stops · straight connections")
        if wm.HookScript then pcall(wm.HookScript, wm, "OnShow", stack) end
    end
    if canvas ~= child then
        layer:SetParent(child); layer:SetAllPoints(child)
        canvas = child
    end
    layer:Show(); hovered, pressed = nil, nil
    local points, groups, cells = {}, {}, {}
    for i, stop in ipairs(route) do
        local x, y = project(stop.point, map)
        if x then
            points[i] = { x = x, y = y }
            local group
            local gx, gy = math.floor(x * width * scale / 26), math.floor(y * height * scale / 22)
            for cx = gx - 1, gx + 1 do
                for cy = gy - 1, gy + 1 do
                    for _, other in ipairs(cells[cx .. ":" .. cy] or {}) do
                        if math.abs(x - other.x) * width * scale < 26 and math.abs(y - other.y) * height * scale < 22 then
                            group = other; break
                        end
                    end
                    if group then break end
                end
                if group then break end
            end
            if not group then
                group = { x = x, y = y, steps = {} }; groups[#groups + 1] = group
                local key = gx .. ":" .. gy
                cells[key] = cells[key] or {}; cells[key][#cells[key] + 1] = group
            end
            group.steps[#group.steps + 1] = i
            if stop.kind == "pickup" or stop.kind == "turnin" then group.native = true end
        end
    end
    -- Markers are wider than the grouping cell (multi-number labels, 32 px minimum), so merge any two groups
    -- whose drawn markers would overlap; one combined label stays readable where two overlapping ones do not.
    local function footprint(steps)
        local count = math.min(3, #steps)
        local chars = count - 1 + (#steps > 3 and 1 or 0)
        for j = 1, count do chars = chars + #tostring(steps[j]) end
        return badgeWidth(chars) + 8 -- slack: the selected step may replace the third number
    end
    local merged = true
    while merged do
        merged = false
        for a = 1, #groups - 1 do
            local A = groups[a]
            for b = a + 1, #groups do
                local B = groups[b]
                if math.abs(A.x - B.x) * width * scale < (footprint(A.steps) + footprint(B.steps)) / 2
                    and math.abs(A.y - B.y) * height * scale < COIN then
                    for _, step in ipairs(B.steps) do A.steps[#A.steps + 1] = step end
                    A.native = A.native or B.native
                    table.sort(A.steps)
                    table.remove(groups, b)
                    merged = true
                    break
                end
            end
            if merged then break end
        end
    end
    local used = 0
    for i = 2, #route do
        local a, b = points[i - 1], points[i]
        if a and b then used = segment(used, a.x, a.y, b.x, b.y, width, height, scale, i == selected) end
    end
    for i = used + 1, #lines do lines[i]:Hide(); underlines[i]:Hide() end
    for i = used + 1, #dots do dots[i]:Hide() end
    for i, group in ipairs(groups) do
        local pin = markers[i] or makeMarker(); markers[i] = pin
        local labels, active = {}, false
        for j, index in ipairs(group.steps) do
            if index == selected then active = true end
            if j <= 3 then labels[#labels + 1] = tostring(index) end
        end
        if active and #group.steps > 3 and selected ~= group.steps[1] and selected ~= group.steps[2]
            and selected ~= group.steps[3] then labels[3] = tostring(selected) end
        local label = table.concat(labels, "/") .. (#group.steps > 3 and "+" or "")
        pin.steps, pin.selectedStop = group.steps, active and selected or nil
        pin.text:SetText((active and S.GOLD or S.hex(1, 0.96, 0.82)) .. label .. "|r")
        local size = active and COIN_SELECTED or COIN -- not `height`: that is the canvas height used below
        pin:SetWidth(badgeWidth(#label)); pin:SetHeight(size); pin:ClearAllPoints(); pin:SetScale(1 / scale)
        fitShape(pin.edge, pin, size, 0); fitShape(pin.rim, pin, size, 2); fitShape(pin.face, pin, size, 5)
        tintShape(pin.edge, 0.03, 0.02, 0.02)
        if active then tintShape(pin.rim, 1, 0.82, 0); tintShape(pin.face, 0.2, 0.12, 0.03)
        else tintShape(pin.rim, 0.8, 0.64, 0.24); tintShape(pin.face, 0.1, 0.07, 0.04) end
        local position = active and points[selected] or group
        local ox, oy = position.x * width * scale, -position.y * height * scale
        if group.native then pin:SetPoint("BOTTOMLEFT", layer, "TOPLEFT", ox + NATIVE_DX, oy + NATIVE_DY)
        else pin:SetPoint("CENTER", layer, "TOPLEFT", ox, oy) end
        pin:Show()
    end
    for i = #groups + 1, #markers do markers[i].steps = nil; markers[i]:Hide() end
    stack(); legend:SetScale(1 / scale)
    if #groups > 0 then legend:Show() else legend:Hide(); layer:Hide() end
    lastView = { map = map, width = width, height = height, scale = scale, revision = revision }
end

local function updateArrow()
    if not (route and ns.db.enabled and ns.db.questPlanner and visible(owner)) then G.clear(); return end
    local stop = route[selected]
    local map, px, py = C.playerPos()
    if not (stop and valid(stop.point)) or (map and not inZone(map, stop.point.map)) then G.clear(); return end
    hud:Show()
    if not map then
        hud.arrow:Hide(); hud.distance:SetText("Position unavailable"); hideMap(); return
    end
    if not targetWorld and (not mapSize or map ~= stop.point.map) and metricWait <= 0 then refreshMetrics(stop.point) end
    local player = targetWorld and world({ map = map, x = px, y = py })
    local north, west
    if targetWorld and player and targetWorld.map == player.map then
        north, west = targetWorld.north - player.north, targetWorld.west - player.west
    elseif mapSize and map == stop.point.map and finite(px) and finite(py) then
        north, west = (py - stop.point.y) * mapSize.height, (px - stop.point.x) * mapSize.width
    end
    hud.arrow:Hide()
    if not (finite(north) and finite(west)) then
        hud.distance:SetText("Distance unavailable · " .. string.format("%.1f, %.1f", stop.point.x * 100, stop.point.y * 100))
        return
    end
    local yards = math.sqrt(north * north + west * west)
    if yards <= 10 then hud.distance:SetText("At destination · follow the quest step"); return end
    local compass, bearing = direction(north, west)
    local facing = call(GetPlayerFacing)
    if finite(facing) and type(hud.arrow.SetRotation) == "function" then
        hud.arrow:SetRotation(bearing - facing); hud.arrow:Show()
    end
    hud.distance:SetText(compass .. " · " .. string.format("%.0f yd", yards) .. " direct")
end
local function update(_, dt)
    metricWait = math.max(0, metricWait - (dt or 0))
    elapsed, mapElapsed = elapsed + (dt or 0), mapElapsed + (dt or 0)
    if elapsed >= 0.1 then elapsed = 0; updateArrow() end
    if mapElapsed >= 0.25 then mapElapsed = 0; drawMap() end
end
function G.set(stops, index, anchor, onSelect, caption)
    if not (stops and stops[index] and valid(stops[index].point) and visible(anchor)) then G.clear(); return end
    local changed = route ~= stops or selected ~= index or owner ~= anchor
    route, selected, owner, choose = stops, index, anchor, onSelect
    if not hud then
        hud = CreateFrame("Frame", "QuestSharingDirection", UIParent)
        hud:SetWidth(300); hud:SetHeight(90); hud:EnableMouse(false)
        hud.arrow = hud:CreateTexture(nil, "ARTWORK")
        hud.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
        hud.arrow:SetVertexColor(0.45, 1, 0.27, 1)
        hud.arrow:SetWidth(40); hud.arrow:SetHeight(40); hud.arrow:SetPoint("TOP", hud, "TOP", 0, 0)
        hud.bg = S.fill(hud, "BACKGROUND", 0.055, 0.05, 0.045, 1)
        hud.bg:SetPoint("TOPLEFT", hud, "TOPLEFT", 0, -42); hud.bg:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT", 0, 0)
        hud.title = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        hud.title:SetPoint("TOPLEFT", hud, "TOPLEFT", 6, -45); hud.title:SetWidth(288); hud.title:SetWordWrap(true)
        hud.distance = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hud.distance:SetPoint("BOTTOM", hud, "BOTTOM", 0, 4)
    end
    hud:ClearAllPoints(); hud:SetPoint("BOTTOM", anchor, "TOP", 0, 7)
    hud.title:SetText(caption or "Go to the selected quest stop")
    local textHeight = call(hud.title.GetStringHeight, hud.title) or 24
    hud:SetHeight(math.max(90, textHeight + 66))
    if changed then
        revision, lastView = revision + 1, nil
        targetWorld, mapSize = nil, nil
        refreshMetrics(stops[index].point)
    end
    hud:SetScript("OnUpdate", update)
    updateArrow(); drawMap()
end
ns.on("WORLD_MAP_UPDATE", function() if route then drawMap() end end)
ns.on("PLAYER_REGEN_DISABLED", hideMap)
ns.on("PLAYER_REGEN_ENABLED", function() if route then drawMap() end end)
ns.on("GLOBAL_MOUSE_DOWN", function(_, button) if button == "LeftButton" and not combat() then pressed = hovered end end)
ns.on("GLOBAL_MOUSE_UP", function(_, button)
    local pin = pressed; pressed = nil
    if button ~= "LeftButton" or not pin or pin ~= hovered or combat() or not visible(layer) or not choose then return end
    local steps = pin.steps or {}
    local index = steps[1]
    for i, step in ipairs(steps) do if step == selected then index = steps[i % #steps + 1]; break end end
    if index then choose(index) end
end)
