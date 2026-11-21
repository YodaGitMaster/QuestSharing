-- Dungeon Journal look: the Map page. The client's own dungeon map art (C_Map art layers, else the 12 classic
-- Interface\WorldMap tiles), floor buttons, mouse-wheel zoom 1-4x and drag to pan. Client textures only.
-- Contract: context/dungeon-journal-contract.md
local ADDON, ns = ...
ns.inModule("dungeons")          -- Modules.lua: Settings > General > Tools can switch this off
local M = {}
ns.dungeonMapUI = M
local U, E = ns.optionalUI, ns.equipmentUI

local MIN_ZOOM, MAX_ZOOM, STEP = 1, 4, 0.5
local TILE_W, TILE_H, VIS_W, VIS_H = 256, 256, 1002, 668 -- the classic 4x3 tile set; its visible part
-- Classic dungeons: QuestieDB area -> first floor uiMapID (used when QuestieDB has no map for the area) and the
-- Interface\WorldMap folder + floor count of the old 12-tile maps. Values are from the client map tables (unverified
-- in game for every client build; a missing file is detected through GetFileIDFromPath where the client has it).
local CLASSIC = {
    [2437] = {map = 213, dir = "Ragefire", floors = 1},
    [718] = {map = 279, dir = "WailingCaverns", floors = 1},
    [1581] = {map = 291, dir = "TheDeadmines", floors = 2},
    [209] = {map = 310, dir = "ShadowfangKeep", floors = 7},
    [717] = {map = 225, dir = "TheStockade", floors = 1},
    [719] = {map = 221, dir = "BlackfathomDeeps", floors = 3},
    [721] = {map = 226, dir = "Gnomeregan", floors = 4},
    [796] = {map = 302, dir = "ScarletMonastery", floors = 4},
    [491] = {map = 301, dir = "RazorfenKraul", floors = 1},
    [722] = {map = 300, dir = "RazorfenDowns", floors = 1},
    [1337] = {map = 230, dir = "Uldaman", floors = 2},
    [1176] = {map = 219, dir = "ZulFarrak", floors = 1},
    [2100] = {map = 280, dir = "Maraudon", floors = 2},
    [1477] = {map = 220, dir = "TheTempleOfAtalHakkar", floors = 1},
    [1584] = {map = 242, dir = "BlackrockDepths", floors = 2},
    [1583] = {map = 250, dir = "BlackrockSpire", floors = 7},
    [2557] = {map = 234, dir = "DireMaul", floors = 6},
    [2057] = {map = 306, dir = "Scholomance", floors = 4},
    [2017] = {map = 317, dir = "Stratholme", floors = 2},
}
M.CLASSIC = CLASSIC

local page, view, canvas, tiles, floorButtons = nil, nil, nil, {}, {}
local state = {area = nil, name = nil, mode = "none", floors = {}, floor = 1, zoom = 1, panX = 0, panY = 0,
    cols = 0, rows = 0, tileW = 0, tileH = 0, mapW = 0, mapH = 0, base = 1}

local function theme() return ns.journalTheme or {} end
local function color(role, fallback)
    local c = theme().C and theme().C[role]
    return c or fallback
end
local function call(obj, method, ...)
    if obj and obj[method] then return pcall(obj[method], obj, ...) end
end
local function capi(name) return C_Map and type(C_Map[name]) == "function" and C_Map[name] or nil end

-- the uiMapID for a dungeon area: QuestieDB's table, then our classic list; outdoor zones are refused
local function uiMapFor(area)
    local map = ns.questie and ns.questie.uiMapOf and U.call(ns.questie.uiMapOf, area)
    local info = map and capi("GetMapInfo") and U.call(capi("GetMapInfo"), map)
    -- Enum.UIMapType: 0 cosmic .. 3 zone; dungeon/micro/orphan are 4+. A zone means QuestieDB gave the outside map.
    if type(info) == "table" and tonumber(info.mapType) and info.mapType < 4 then map = nil end
    return map or (CLASSIC[area] and CLASSIC[area].map) or nil
end
M._uiMapFor = uiMapFor

-- the floors of a map (its map group, sorted by height), else just that map
local function floorsOf(map)
    local list = {}
    local group = capi("GetMapGroupID") and U.call(capi("GetMapGroupID"), map)
    local members = group and capi("GetMapGroupMembersInfo") and U.call(capi("GetMapGroupMembersInfo"), group)
    if type(members) == "table" then
        for _, m in ipairs(members) do
            if type(m) == "table" and m.mapID then list[#list + 1] = {map = m.mapID, name = m.name, order = m.relativeHeightIndex or #list} end
        end
        table.sort(list, function(a, b) return a.order < b.order end)
    end
    if #list == 0 then
        local info = capi("GetMapInfo") and U.call(capi("GetMapInfo"), map)
        list[1] = {map = map, name = type(info) == "table" and info.name or nil}
    end
    return list
end

-- the art of one floor: {cols, rows, tileW, tileH, w, h, textures} or nil
local function artOf(map)
    local getLayers, getTextures = capi("GetMapArtLayers"), capi("GetMapArtLayerTextures")
    if not map or not getLayers or not getTextures then return nil end
    local layers = U.call(getLayers, map)
    local layer = type(layers) == "table" and layers[1]
    if type(layer) ~= "table" then return nil end
    local textures = U.call(getTextures, map, 1)
    local tw, th = tonumber(layer.tileWidth) or TILE_W, tonumber(layer.tileHeight) or TILE_H
    local w, h = tonumber(layer.layerWidth), tonumber(layer.layerHeight)
    if type(textures) ~= "table" or #textures == 0 or not w or not h or w <= 0 or h <= 0 then return nil end
    return {cols = math.ceil(w / tw), rows = math.ceil(h / th), tileW = tw, tileH = th, w = w, h = h, textures = textures}
end

-- the old 12-tile set: Interface\WorldMap\<Dir>\<Dir><floor>_1..12
function M.tilePaths(dir, floor)
    local out = {}
    for i = 1, 12 do out[i] = "Interface\\WorldMap\\" .. dir .. "\\" .. dir .. (floor or 1) .. "_" .. i end
    return out
end
local function tilesOf(area, floor)
    local c = CLASSIC[area]
    if not c then return nil end
    local paths = M.tilePaths(c.dir, floor)
    if type(GetFileIDFromPath) == "function" then
        local ok, id = pcall(GetFileIDFromPath, paths[1])
        if ok and not id then return nil end -- the client has no such file
    end
    return {cols = 4, rows = 3, tileW = TILE_W, tileH = TILE_H, w = VIS_W, h = VIS_H, textures = paths}
end

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

local function viewSize() return state.mapW * state.base, state.mapH * state.base end

-- place the canvas and every tile for the current zoom and pan
local function layout()
    if not canvas then return end
    local vw, vh = viewSize()
    local z = state.zoom
    state.panX = clamp(state.panX, 0, math.max(0, vw * z - vw))
    state.panY = clamp(state.panY, 0, math.max(0, vh * z - vh))
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", view, "TOPLEFT", -state.panX, state.panY)
    canvas:SetWidth(vw * z); canvas:SetHeight(vh * z)
    local tw, th = state.tileW * state.base * z, state.tileH * state.base * z
    local i = 0
    for row = 0, state.rows - 1 do
        for col = 0, state.cols - 1 do
            i = i + 1
            local t = tiles[i]
            if t and t:IsShown() then
                t:SetWidth(tw); t:SetHeight(th)
                t:ClearAllPoints(); t:SetPoint("TOPLEFT", canvas, "TOPLEFT", col * tw, -row * th)
            end
        end
    end
    if page and page.zoomText then page.zoomText:SetText(math.floor(z * 100 + 0.5) .. "%") end
end

function M.setZoom(z)
    local old = state.zoom
    z = clamp(tonumber(z) or 1, MIN_ZOOM, MAX_ZOOM)
    local vw, vh = viewSize()
    -- keep the middle of the view where it is
    state.panX = (state.panX + vw / 2) * (z / old) - vw / 2
    state.panY = (state.panY + vh / 2) * (z / old) - vh / 2
    state.zoom = z
    layout()
    return z
end
function M.zoomBy(delta) return M.setZoom(state.zoom + (delta or 0) * STEP) end
function M.pan(dx, dy) state.panX, state.panY = state.panX - (dx or 0), state.panY + (dy or 0); layout() end

local function hideAll()
    for _, t in ipairs(tiles) do t:Hide() end
    for _, b in ipairs(floorButtons) do b:Hide() end
end

local function setLabel(b, label)
    if b.SetLabel then b:SetLabel(label) elseif b.label then b.label:SetText(label) elseif b.SetText then b:SetText(label) end
end

local function showNoMap()
    -- hide only the tiles: with several floors the user must still reach the other floors
    for _, t in ipairs(tiles) do t:Hide() end
    for i, b in ipairs(floorButtons) do
        if i <= #state.floors and #state.floors > 1 then
            if b.SetSelected then b:SetSelected(i == state.floor) end
            b:Show()
        else b:Hide() end
    end
    state.mode, state.cols, state.rows = "none", 0, 0
    view:Hide(); page.zoomBox:Hide()
    page.empty:SetText("No map for this dungeon in the game files.")
    page.empty:Show()
    local D = ns.dungeonQuests
    local entrance = D and D.entranceOf and U.call(D.entranceOf, state.area)
    page.pin.entrance = entrance
    setLabel(page.pin, entrance and "Pin the entrance on my map" or "Entrance unknown")
    page.pin:Show()
end

local function pinEntrance()
    local e = page and page.pin.entrance
    if not e then
        local D = ns.dungeonQuests
        e = D and D.entranceOf and U.call(D.entranceOf, state.area)
    end
    if not e then ns.print("The entrance of this dungeon is not in the quest data."); return false end
    local place = {source = {name = e.label}, point = e.point}
    local D = ns.dungeonQuests
    if D and D.pinPlace then return D.pinPlace(place) end
    -- stream B has not exported pinPlace yet: set the pin directly
    local pt = e.point
    if pt and pt.map and ns.compat and ns.compat.setWaypoint then
        ns.compat.setWaypoint(pt.map, pt.x / 100, pt.y / 100); ns.print("map pin: " .. tostring(e.label)); return true
    end
    return false
end

local function drawFloor(index)
    state.floor = index
    local f = state.floors[index]
    local art = f and f.map and artOf(f.map)
    local mode = "art"
    if not art then art, mode = tilesOf(state.area, f and f.tileFloor or index), "tiles" end
    if not art then return showNoMap() end
    hideAll()
    page.empty:Hide(); page.pin:Hide(); view:Show(); page.zoomBox:Show()
    state.mode, state.cols, state.rows, state.tileW, state.tileH = mode, art.cols, art.rows, art.tileW, art.tileH
    state.mapW, state.mapH = art.w, art.h
    state.base = math.min(page.areaW / art.w, page.areaH / art.h)
    local vw, vh = viewSize()
    view:SetWidth(vw); view:SetHeight(vh)
    view:ClearAllPoints(); view:SetPoint("CENTER", page, "CENTER", 0, 0)
    for i = 1, art.cols * art.rows do
        local t = tiles[i]
        if not t then t = canvas:CreateTexture(nil, "ARTWORK"); tiles[i] = t end
        local tex = art.textures[i]
        if tex then t:SetTexture(tex); t:Show() else t:Hide() end
    end
    state.zoom, state.panX, state.panY = 1, 0, 0
    layout()
    for i, b in ipairs(floorButtons) do
        if b.SetSelected then b:SetSelected(i == index) end
        if i <= #state.floors and #state.floors > 1 then b:Show() end
    end
end
-- a floor you pick (button or M.setFloor) is kept when the page is shown again for the same dungeon
function M.setFloor(i) if state.floors[i] then state.picked = {area = state.area, floor = i}; drawFloor(i) end end

local function floorButton(i, label)
    local b = floorButtons[i]
    if b then return b end
    local T = theme()
    local onClick = function() M.setFloor(i) end
    if T.tab then b = T.tab(page, label, nil, 96, onClick)
    else b = (T.button or ns.style.button)(page, label, 96, onClick) end
    b:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -8 - (i - 1) * 26)
    local function tip(self)
        local f = state.floors[i]
        U.tip(self, (f and f.name) or ("Floor " .. i), {"Floor " .. i .. " of " .. #state.floors .. ". Click: show it.",
            "Mouse wheel on the map: zoom. Drag: move it."})
    end
    -- keep a hover the button already has (T.button tips); a plain tab gets this one
    local had = b.GetScript and b:GetScript("OnEnter")
    if had and b.HookScript then b:HookScript("OnEnter", tip); b:HookScript("OnLeave", U.hideTip)
    else b:SetScript("OnEnter", tip); b:SetScript("OnLeave", U.hideTip) end
    floorButtons[i] = b
    return b
end

function M.build(parent, width, height)
    if page then return page end
    local T = theme()
    width, height = width or 1000, height or 560
    page = CreateFrame("Frame", nil, parent)
    page:SetWidth(width); page:SetHeight(height)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    if T.panel then T.panel(page, "content") end
    page.areaW, page.areaH = width - 2 * 110, height - 16 -- room for the floor column and the zoom box
    view = CreateFrame("Frame", nil, page)
    call(view, "SetClipsChildren", true)
    view:EnableMouse(true); view:EnableMouseWheel(true)
    canvas = CreateFrame("Frame", nil, view)
    view:SetScript("OnMouseWheel", function(_, delta) M.zoomBy(delta) end)
    view:SetScript("OnMouseDown", function(self, button)
        if button and button ~= "LeftButton" then return end
        local x, y = GetCursorPosition()
        local s = (self.GetEffectiveScale and self:GetEffectiveScale()) or 1
        self.drag = {x = x / s, y = y / s}
    end)
    view:SetScript("OnMouseUp", function(self) self.drag = nil end)
    view:SetScript("OnHide", function(self) self.drag = nil end)
    view:SetScript("OnUpdate", function(self)
        if not self.drag then return end
        local x, y = GetCursorPosition()
        local s = (self.GetEffectiveScale and self:GetEffectiveScale()) or 1
        x, y = x / s, y / s
        M.pan(x - self.drag.x, y - self.drag.y)
        self.drag.x, self.drag.y = x, y
    end)
    -- zoom box, bottom left (as in the screenshot: "- 100% +")
    local box = CreateFrame("Frame", nil, page)
    box:SetWidth(96); box:SetHeight(48); box:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 8, 8)
    if T.panel then T.panel(box, "frame") end
    box.label = U.text(box, "Zoom", 0, 5, 96); box.label:SetJustifyH("CENTER")
    local minus = (T.button or ns.style.button)(box, "-", 22, function() M.zoomBy(-1) end, "Zoom out (or the mouse wheel)")
    minus:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 6, 6)
    local plus = (T.button or ns.style.button)(box, "+", 22, function() M.zoomBy(1) end, "Zoom in (or the mouse wheel). Drag the map to move it.")
    plus:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 6)
    page.zoomText = U.text(box, "100%", 28, 30, 40); page.zoomText:SetJustifyH("CENTER")
    page.zoomBox, page.minus, page.plus = box, minus, plus
    -- no map: a message and the entrance pin
    local muted = color("muted", {.82, .74, .60})
    page.empty = U.text(page, "", 0, 0, width - 80)
    page.empty:ClearAllPoints(); page.empty:SetPoint("CENTER", page, "CENTER", 0, 24); page.empty:SetJustifyH("CENTER")
    if E and E.font then E.font(page.empty, 16, muted[1], muted[2], muted[3]) end
    page.pin = (T.button or ns.style.button)(page, "Pin the entrance on my map", 220, pinEntrance,
        "Put a pin on your world map at the dungeon entrance (open it with M).")
    page.pin:SetPoint("CENTER", page, "CENTER", 0, -14)
    page.empty:Hide(); page.pin:Hide(); view:Hide()
    page:Hide()
    return page
end

function M.show(area, name)
    if not page then return end
    local kept = state.picked and state.picked.area == area and state.picked.floor or nil -- your pick, same dungeon
    if not kept then state.picked = nil end
    state.area, state.name = area, name
    page:Show()
    local map = uiMapFor(area)
    state.floors = map and floorsOf(map) or {}
    local classic = CLASSIC[area]
    if #state.floors <= 1 and classic and classic.floors > 1 and not (map and artOf(map)) then
        -- no client map group: the old tile set still has every floor
        state.floors = {}
        for i = 1, classic.floors do state.floors[i] = {map = nil, tileFloor = i} end
    end
    if #state.floors == 0 then state.floors = {{map = nil, tileFloor = 1}} end
    for i, f in ipairs(state.floors) do
        local label = f.name or ("Floor " .. i)
        local b = floorButton(i, label)
        setLabel(b, label)
        b:Hide()
    end
    for i = #state.floors + 1, #floorButtons do floorButtons[i]:Hide() end
    drawFloor((kept and state.floors[kept]) and kept or M.floorOfPlayer() or 1)
end

-- "which floor am I on": inside the dungeon the page opens on the floor you stand on (the client's map for you)
function M.floorOfPlayer()
    local best = capi("GetBestMapForUnit") and U.call(capi("GetBestMapForUnit"), "player")
    if not best then return nil end
    for i, f in ipairs(state.floors) do if f.map and f.map == best then return i end end
end

function M.hide()
    if page then page:Hide() end
    if view then view.drag = nil end
end
function M.refresh() if page and page:IsShown() and state.area then M.show(state.area, state.name) end end

-- tests: what the page shows now
function M._state()
    local shown = {}
    for _, t in ipairs(tiles) do if t:IsShown() and (#shown < state.cols * state.rows) then shown[#shown + 1] = t end end
    return {mode = state.mode, zoom = state.zoom, panX = state.panX, panY = state.panY, cols = state.cols, rows = state.rows,
        floors = #state.floors, floor = state.floor, tiles = shown, page = page, view = view,
        floorButtons = floorButtons, message = page and page.empty:IsShown() and page.empty:GetText() or nil}
end
