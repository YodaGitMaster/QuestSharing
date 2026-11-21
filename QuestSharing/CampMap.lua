-- Shared camps: the Quest guide's planned kill and collect objectives, grouped into its 100-yard camps.
-- World map: a circle per camp (blue = serves 2 or more quests, grey = one), a small "A1" label to hover
-- (mobs, spawns and quests) and click (waypoint). Shared camps window: network, map and matrix (camps x objectives).
-- Optional (Settings > Quest guide, off by default). Reads ns.questPlanner.campView(); draws addon-owned frames only.
local ADDON, ns = ...
ns.inModule("guide")          -- Modules.lua: Settings > General > Tools can switch this off
local U, S = ns.optionalUI, ns.style
local C = {}
ns.campMap = C

local call = U.call
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function combat() return call(InCombatLockdown) end

local CAMP_YARDS, FALLBACK = 100, 0.065    -- the guide's camp radius; map fraction when the map size is unknown
local SHARED = { 0.16, 0.47, 0.84 }         -- blue: one visit helps several quests
local SINGLE = { 0.6, 0.6, 0.58 }           -- grey: one quest
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local layer, layerParent, lastView
local circles, labels = {}, {}

local function view()
    local P = ns.questPlanner
    return P and type(P.campView) == "function" and P.campView() or nil
end

-- one line per objective in the camp, most spawns first: "Ragged Young Wolf x29 - Dwarven Outfitters"
local function campLines(v, camp)
    local rows = {}
    for col, n in pairs(camp.counts) do rows[#rows + 1] = { col = col, n = n } end
    table.sort(rows, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.col < b.col end)
    local lines = {}
    for _, r in ipairs(rows) do
        local c = v.columns[r.col]
        lines[#lines + 1] = string.format("%s x%d %s- %s|r", c.name, r.n, S.GREY, c.quest)
    end
    lines[#lines + 1] = S.GREY .. "Click to set a waypoint. /qs plan camps table lists every camp.|r"
    return lines
end
C._campLines = campLines

local function campTitle(camp)
    return string.format("Camp %s - %s", camp.id,
        camp.shared and (camp.questCount .. " quests share it") or "1 quest")
end

local function hide()
    if layer then layer:Hide() end
    lastView = nil
end

local function circle(i)
    local t = circles[i]
    if not t then
        t = layer:CreateTexture(nil, "ARTWORK")
        t:SetTexture(CIRCLE)
        circles[i] = t
    end
    return t
end

local function label(i)
    local b = labels[i]
    if not b then
        b = CreateFrame("Button", nil, layer)
        b:SetWidth(26); b:SetHeight(16); b:EnableMouse(true)
        b:RegisterForClicks("LeftButtonUp")
        b.bg = S.fill(b, "BACKGROUND", 0, 0, 0, 0.7); b.bg:SetAllPoints(b)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetAllPoints(b)
        b:SetScript("OnEnter", function(self)
            if self.camp and self.view then U.tip(self, campTitle(self.camp), campLines(self.view, self.camp)) end
        end)
        b:SetScript("OnLeave", function() U.hideTip() end)
        b:SetScript("OnClick", function(self)
            local p = self.camp and self.camp.point
            if p and not ns.compat.setWaypoint(p.map, p.x, p.y) then ns.print("the game could not set a waypoint here") end
        end)
        labels[i] = b
    end
    return b
end

function C.draw()
    local wm = WorldMapFrame
    local child = wm and wm.ScrollContainer and wm.ScrollContainer.Child
    if not (ns.db.enabled and ns.db.campMap and child and call(wm.IsShown, wm)) or combat() or ns.isBlocked("campmap") then
        hide(); return
    end
    local v = view()
    local map = call(wm.GetMapID, wm)
    if not (v and map == v.map and v.camps[1]) then hide(); return end
    local width, height = call(child.GetWidth, child), call(child.GetHeight, child)
    local scale = call(child.GetScale, child) or 1
    if not (finite(width) and finite(height) and width > 0 and height > 0) then hide(); return end
    if not finite(scale) or scale <= 0 then scale = 1 end
    if not layer then
        layer = CreateFrame("Frame", "QuestSharingCampOverlay", UIParent)
        layer:EnableMouse(false)                 -- the circles never take map clicks; only the small labels do
    end
    if layerParent ~= child then layer:SetParent(child); layer:SetAllPoints(child); layerParent = child; lastView = nil end
    if lastView and lastView.v == v and lastView.width == width and lastView.height == height and lastView.scale == scale then
        layer:Show(); return
    end
    ns.trying("drawing shared camps on the world map", "campmap") -- a failure here turns the layer off
    layer:Show()
    call(layer.SetFrameStrata, layer, call(child.GetFrameStrata, child))
    call(layer.SetFrameLevel, layer, math.min(9800, (call(child.GetFrameLevel, child) or 0) + 4000))
    local ww, wh = call(C_Map and C_Map.GetMapWorldSize, map)
    local rx, ry = FALLBACK, FALLBACK
    if finite(ww) and ww > 0 and finite(wh) and wh > 0 then rx, ry = CAMP_YARDS / ww, CAMP_YARDS / wh end
    for i, camp in ipairs(v.camps) do
        local p, color = camp.point, camp.shared and SHARED or SINGLE
        local ox, oy = p.x * width * scale, -p.y * height * scale
        local t = circle(i)
        t:ClearAllPoints()
        t:SetWidth(2 * rx * width * scale); t:SetHeight(2 * ry * height * scale)
        t:SetPoint("CENTER", layer, "TOPLEFT", ox, oy)
        t:SetVertexColor(color[1], color[2], color[3], camp.shared and 0.32 or 0.22)
        t:Show()
        local b = label(i)
        b.camp, b.view = camp, v
        b.text:SetText(camp.id)
        b:ClearAllPoints(); b:SetPoint("CENTER", layer, "TOPLEFT", ox, oy)
        b:Show()
    end
    for i = #v.camps + 1, #circles do circles[i]:Hide() end
    for i = #v.camps + 1, #labels do labels[i]:Hide() end
    lastView = { v = v, width = width, height = height, scale = scale }
end

function C.refresh() lastView = nil; C.draw(); if C.tableShown() then C.fillTable() end end

-- test hook: shown circles and labels
function C._shown()
    local out = { circles = {}, labels = {} }
    for _, t in ipairs(circles) do if t:IsShown() then out.circles[#out.circles + 1] = t end end
    for _, b in ipairs(labels) do if b:IsShown() then out.labels[#out.labels + 1] = b end end
    return out
end

-- ---- Shared camps window: objective buttons, network (quest -> mob or object -> camp), map, matrix ----------
-- The same three views as tools/coldridge-network.html, in the classic stone-and-gold look.
local WIN_W, WIN_H = 990, 718
local NET_X, NET_Y, NET_W, NET_H = 16, -118, 540, 300      -- panels, relative to the window's top left
local MAP_X, MAP_W = 568, 406
local MAT_Y, CELL_W, CELL_H, NAME_W, MAX_ROWS, MAX_COLS = -440, 62, 18, 190, 11, 10
local RAMP = { { 0.80, 0.89, 0.98 }, { 0.62, 0.77, 0.96 }, { 0.43, 0.65, 0.93 }, { 0.22, 0.53, 0.90 },
    { 0.15, 0.42, 0.75 }, { 0.09, 0.31, 0.58 }, { 0.05, 0.21, 0.42 } }       -- one hue, light -> dark = few -> many
local win
local focus                                  -- column index of the highlighted objective, or nil for all

function C.tableShown() return win and win:IsShown() or false end

local function setTexColor(t, r, g, b, a)
    if t.SetColorTexture then t:SetColorTexture(r, g, b, a) else t:SetVertexColor(r, g, b, a) end
end

-- reusable pools per panel, hidden in bulk before each redraw
local function pool(owner, make)
    local p = { items = {}, used = 0 }
    function p.get() p.used = p.used + 1; local it = p.items[p.used]; if not it then it = make(owner); p.items[p.used] = it end; it:Show(); return it end
    function p.reset() for i = 1, #p.items do p.items[i]:Hide() end; p.used = 0 end
    return p
end
local function newText(owner, font) return owner:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall") end
local function newLine(owner) return owner.CreateLine and owner:CreateLine(nil, "ARTWORK") or owner:CreateTexture(nil, "ARTWORK") end
local function newDot(owner) local t = owner:CreateTexture(nil, "OVERLAY"); t:SetTexture(CIRCLE); return t end
local function newBox(owner) return S.fill(owner, "OVERLAY", 1, 1, 1, 1) end
local function newHit(owner)
    local b = CreateFrame("Button", nil, owner)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnEnter", function(self) if self.tipTitle then U.tip(self, self.tipTitle, self.tipLines or {}) end end)
    b:SetScript("OnLeave", function() U.hideTip() end)
    b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    return b
end

local function line(p, x1, y1, x2, y2, width, r, g, b, a)
    local l = p.lines.get()
    if l.SetStartPoint then
        l:SetThickness(width)
        l:SetStartPoint("TOPLEFT", p, x1, y1); l:SetEndPoint("TOPLEFT", p, x2, y2)
    end
    setTexColor(l, r, g, b, a)
    return l
end

-- a smooth link from (x1, y1) to (x2, y2): a cubic curve with horizontal ends, as 8 straight pieces
local function curve(p, x1, y1, x2, y2, width, r, g, b, a)
    local cx = (x2 - x1) * 0.45
    local px, py = x1, y1
    for i = 1, 8 do
        local t = i / 8
        local u = 1 - t
        local x = u * u * u * x1 + 3 * u * u * t * (x1 + cx) + 3 * u * t * t * (x2 - cx) + t * t * t * x2
        local y = u * u * u * y1 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y2
        line(p, px, py, x, y, width, r, g, b, a)
        px, py = x, y
    end
end

local function panel(parent, x, y, w, h, title, note)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(w); f:SetHeight(h)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    S.inset(f)
    f.title = newText(parent, "GameFontNormal")                 -- gold = heading
    f.title:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 2, 16); f.title:SetText(title)
    f.note = newText(parent, "GameFontDisableSmall")
    f.note:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 2, 3); f.note:SetText(note)
    f.lines, f.texts, f.dots, f.boxes, f.hits = pool(f, newLine), pool(f, newText), pool(f, newDot), pool(f, newBox), pool(f, newHit)
    return f
end

local function nearestGiver(v, camp)
    local ww, wh = call(C_Map and C_Map.GetMapWorldSize, v.map)
    if not (finite(ww) and ww > 0 and finite(wh) and wh > 0) then return nil end
    local best, bd, bdx, bdy
    for _, g in ipairs(v.givers or {}) do
        local dx, dy = (camp.point.x - g.x) * ww, (camp.point.y - g.y) * wh
        local d = math.sqrt(dx * dx + dy * dy)
        if not bd or d < bd then best, bd, bdx, bdy = g, d, dx, dy end
    end
    if not best then return nil end
    local first = best.name:match("^(%S+)") or best.name
    if first == "Mountaineer" then first = best.name:match("(%S+)$") or first end
    if bd < 40 then return "by " .. first end
    local ang = math.deg(math.atan2(-bdy, bdx)) % 360
    local dirs = { "E", "NE", "N", "NW", "W", "SW", "S", "SE" }
    return string.format("%d yd %s of %s", math.floor(bd / 10 + 0.5) * 10, dirs[math.floor(((ang + 22.5) % 360) / 45) + 1], first)
end

local function waypointTo(p)
    if p and not ns.compat.setWaypoint(p.map, p.x, p.y) then ns.print("the game could not set a waypoint here") end
end

local function buildTable()
    win = S.window("QuestSharingCampTable", WIN_W, WIN_H, "Shared camps", "dialog")
    if not win then return nil end
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    local uiH = call(UIParent.GetHeight, UIParent)
    if finite(uiH) and uiH > 0 and uiH < WIN_H + 40 then win:SetScale((uiH - 40) / WIN_H) end   -- fits small screens
    win.close = S.closeButton(win, function() win:Hide() end, -4, -4)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestSharingCampTable") end      -- Esc closes it
    win.hint = newText(win)
    win.hint:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -26)
    win.hint:SetWidth(WIN_W - 32); win.hint:SetJustifyH("LEFT")
    win.filters = {}
    win.net = panel(win, NET_X, NET_Y, NET_W, NET_H, "Network: quest -> mob or object -> camp",
        "Line width = spawns of that mob in that camp. Hover a node; click a mob to highlight it.")
    win.map = panel(win, MAP_X, NET_Y, MAP_W, NET_H, "Map: spawns and camps",
        "Dots = spawns; circles = 100-yard camps; squares = quest givers. Click a camp for a waypoint.")
    if win.map.SetClipsChildren then win.map:SetClipsChildren(true) end
    win.map.art = {}
    win.matTitle = newText(win, "GameFontNormal")
    win.matTitle:SetPoint("TOPLEFT", win, "TOPLEFT", 18, MAT_Y + 14)
    win.matTitle:SetText("Intersection matrix: spawns per camp and objective")
    win.heads, win.rows = {}, {}
    for c = 1, MAX_COLS do
        local h = CreateFrame("Button", nil, win)
        h:SetWidth(CELL_W); h:SetHeight(34)
        h.text = newText(h, "GameFontNormalSmall"); h.text:SetAllPoints(h); h.text:SetJustifyV("BOTTOM")
        h:SetPoint("TOPLEFT", win, "TOPLEFT", 16 + NAME_W + 50 + (c - 1) * (CELL_W + 2), MAT_Y - 2)
        h:SetScript("OnEnter", function(self) if self.col then U.tip(self, self.col.name, { "Quest: " .. self.col.quest }) end end)
        h:SetScript("OnLeave", function() U.hideTip() end)
        win.heads[c] = h
    end
    win.questHead = newText(win, "GameFontNormalSmall")
    win.questHead:SetPoint("BOTTOMLEFT", win.heads[1], "BOTTOMLEFT", -48, 0)
    win.questHead:SetText("Quests")
    for r = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, win)
        row:SetHeight(CELL_H); row:SetWidth(NAME_W + 50 + MAX_COLS * (CELL_W + 2))
        row:SetPoint("TOPLEFT", win, "TOPLEFT", 16, MAT_Y - 40 - (r - 1) * (CELL_H + 2))
        row:RegisterForClicks("LeftButtonUp")
        row.name = newText(row); row.name:SetPoint("LEFT", row, "LEFT", 0, 0); row.name:SetWidth(NAME_W); row.name:SetJustifyH("LEFT")
        row.quests = newText(row); row.quests:SetPoint("LEFT", row, "LEFT", NAME_W, 0); row.quests:SetWidth(44)
        row.cells = {}
        for c = 1, MAX_COLS do
            local cell = { bg = S.fill(row, "ARTWORK", 1, 1, 1, 1) }
            cell.bg:SetWidth(CELL_W); cell.bg:SetHeight(CELL_H)
            cell.bg:SetPoint("LEFT", row, "LEFT", NAME_W + 50 + (c - 1) * (CELL_W + 2), 0)
            cell.text = newText(row); cell.text:SetAllPoints(cell.bg)
            row.cells[c] = cell
        end
        row:SetScript("OnEnter", function(self) if self.camp then U.tip(self, campTitle(self.camp), campLines(self.view, self.camp)) end end)
        row:SetScript("OnLeave", function() U.hideTip() end)
        row:SetScript("OnClick", function(self) waypointTo(self.camp and self.camp.point) end)
        win.rows[r] = row
    end
    return win
end

local function setFocus(col) focus = col; C.fillTable() end

local function drawFilters(v)
    for _, b in ipairs(win.filters) do b:Hide() end
    local items = { { label = "All objectives" } }
    for i, col in ipairs(v and v.columns or {}) do items[#items + 1] = { label = col.name, col = i, quest = col.quest } end
    local x, y = 16, -42
    for i, it in ipairs(items) do
        local w = math.max(70, math.min(190, 14 + 6 * string.len(it.label)))
        if x + w > WIN_W - 16 then x, y = 16, y - 24 end
        local b = win.filters[i]
        if not b then
            b = S.button(win, "", w, function(self) setFocus(self.col) end)
            win.filters[i] = b
        end
        b.col = it.col
        b:SetWidth(w); b:SetLabel(it.label)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", win, "TOPLEFT", x, y)
        b.selected = (focus == it.col)
        if b.selected then b.edge:Show() else b.edge:Hide() end   -- gold underline = selected, as on other tab buttons
        b:Show()
        x = x + w + 4
    end
end

local function drawNetwork(v)
    local p = win.net
    p.lines.reset(); p.texts.reset(); p.dots.reset(); p.boxes.reset(); p.hits.reset()
    local quests, qIndex = {}, {}
    for _, col in ipairs(v.columns) do
        if not qIndex[col.qid] then quests[#quests + 1] = col; qIndex[col.qid] = #quests end
    end
    local camps = {}
    for i, camp in ipairs(v.camps) do if i <= MAX_ROWS then camps[#camps + 1] = camp end end
    local qx, mx, cx = 150, 300, 372
    local function yOf(i, n) return -(26 + (NET_H - 36) * (i - 0.5) / n) end
    local function live(col) return not focus or focus == col end
    local function header(text, x, justify)
        local t = p.texts.get(); t:SetFontObject("GameFontNormalSmall"); t:SetText(text); t:ClearAllPoints()
        t:SetPoint(justify == "LEFT" and "TOPLEFT" or "TOP", p, "TOPLEFT", x, -6)
    end
    header("Quest", qx - 40); header("Mob or object", mx); header("Camp", cx, "LEFT")
    -- camp links first, so nodes draw over them
    for ci, camp in ipairs(camps) do
        local color = camp.shared and SHARED or SINGLE
        for col, n in pairs(camp.counts) do
            local a = live(col) and 0.75 or 0.08
            curve(p, mx + 6, yOf(col, #v.columns), cx - 6, yOf(ci, #camps), math.max(1, math.sqrt(n) * 1.1), color[1], color[2], color[3], a)
        end
    end
    for ci, col in ipairs(v.columns) do
        local a = live(ci) and 0.9 or 0.12
        line(p, qx + 6, yOf(qIndex[col.qid], #quests), mx - 6, yOf(ci, #v.columns), 1.5, 0.55, 0.55, 0.52, a)
    end
    for qi, col in ipairs(quests) do
        local on = not focus or v.columns[focus].qid == col.qid
        local d = p.dots.get(); d:SetWidth(10); d:SetHeight(10); d:ClearAllPoints()
        d:SetPoint("CENTER", p, "TOPLEFT", qx, yOf(qi, #quests)); d:SetVertexColor(1, 0.82, 0, on and 1 or 0.3)
        local t = p.texts.get(); t:SetFontObject("GameFontHighlightSmall"); t:SetText(col.quest); t:ClearAllPoints()
        t:SetPoint("RIGHT", p, "TOPLEFT", qx - 9, yOf(qi, #quests)); t:SetAlpha(on and 1 or 0.4)
    end
    for ci, col in ipairs(v.columns) do
        local on = live(ci)
        local b = p.boxes.get(); setTexColor(b, 0.85, 0.85, 0.8, on and 1 or 0.3); b:SetWidth(10); b:SetHeight(10)
        b:ClearAllPoints(); b:SetPoint("CENTER", p, "TOPLEFT", mx, yOf(ci, #v.columns))
        local t = p.texts.get(); t:SetFontObject("GameFontHighlightSmall"); t:SetText(col.name); t:ClearAllPoints()
        t:SetPoint("BOTTOM", p, "TOPLEFT", mx, yOf(ci, #v.columns) + 6); t:SetAlpha(on and 1 or 0.4)
        local h = p.hits.get(); h:SetWidth(18); h:SetHeight(18); h:ClearAllPoints()
        h:SetPoint("CENTER", p, "TOPLEFT", mx, yOf(ci, #v.columns))
        local where = 0
        for _, camp in ipairs(v.camps) do if camp.counts[ci] then where = where + 1 end end
        h.tipTitle, h.tipLines = col.name, { "Quest: " .. col.quest, "Spawns in " .. where .. " camps", "Click to highlight it." }
        h.onClick = function() setFocus(focus == ci and nil or ci) end
    end
    for ci, camp in ipairs(camps) do
        local on = not focus or camp.counts[focus]
        local color = camp.shared and SHARED or SINGLE
        local b = p.boxes.get(); setTexColor(b, color[1], color[2], color[3], on and 1 or 0.3); b:SetWidth(10); b:SetHeight(10)
        b:ClearAllPoints(); b:SetPoint("CENTER", p, "TOPLEFT", cx, yOf(ci, #camps))
        local t = p.texts.get(); t:SetFontObject("GameFontHighlightSmall"); t:ClearAllPoints()
        local near = nearestGiver(v, camp)
        t:SetText(camp.id .. (near and (" - " .. near) or string.format(" - %.1f, %.1f", camp.point.x * 100, camp.point.y * 100)))
        t:SetPoint("LEFT", p, "TOPLEFT", cx + 10, yOf(ci, #camps)); t:SetAlpha(on and 1 or 0.4)
        local h = p.hits.get(); h:SetWidth(150); h:SetHeight(16); h:ClearAllPoints()
        h:SetPoint("LEFT", p, "TOPLEFT", cx - 6, yOf(ci, #camps))
        h.tipTitle, h.tipLines = campTitle(camp), campLines(v, camp)
        h.onClick = function() waypointTo(camp.point) end
    end
end

-- The map crop: every spawn plus a margin, widened to the panel's shape so a yard is as long across as down.
local function drawMap(v)
    local p = win.map
    p.lines.reset(); p.texts.reset(); p.dots.reset(); p.boxes.reset(); p.hits.reset()
    for _, t in ipairs(p.art) do t:Hide() end
    local ww, wh = call(C_Map and C_Map.GetMapWorldSize, v.map)
    if not (finite(ww) and ww > 0 and finite(wh) and wh > 0) then ww, wh = 1, 1 end
    local x0, x1, y0, y1 = 1, 0, 1, 0
    for _, pt in ipairs(v.points) do x0, x1, y0, y1 = math.min(x0, pt.x), math.max(x1, pt.x), math.min(y0, pt.y), math.max(y1, pt.y) end
    for _, g in ipairs(v.givers or {}) do
        if g.x > x0 - 0.04 and g.x < x1 + 0.04 and g.y > y0 - 0.04 and g.y < y1 + 0.04 then
            x0, x1, y0, y1 = math.min(x0, g.x), math.max(x1, g.x), math.min(y0, g.y), math.max(y1, g.y)
        end
    end
    local pad = CAMP_YARDS / ww
    x0, x1, y0, y1 = x0 - pad, x1 + pad, y0 - pad * ww / wh, y1 + pad * ww / wh
    local perYard = math.min(MAP_W / ((x1 - x0) * ww), NET_H / ((y1 - y0) * wh))
    local sx, sy = perYard * ww, perYard * wh                    -- pixels for the whole map's width and height
    local ox = (MAP_W - (x1 - x0) * sx) / 2 - x0 * sx
    local oy = (NET_H - (y1 - y0) * sy) / 2 - y0 * sy
    local function at(x, y) return ox + x * sx, -(oy + y * sy) end
    -- the zone's own map art, dimmed, when the client can name its tiles
    local layers = call(C_Map and C_Map.GetMapArtLayers, v.map)
    local files = call(C_Map and C_Map.GetMapArtLayerTextures, v.map, 1)
    local L1 = type(layers) == "table" and layers[1]
    if L1 and type(files) == "table" and files[1] and finite(L1.layerWidth) and L1.layerWidth > 0 and finite(L1.tileWidth) and L1.tileWidth > 0 then
        local cols = math.ceil(L1.layerWidth / L1.tileWidth)
        local tw, th = L1.tileWidth / L1.layerWidth * sx, L1.tileHeight / L1.layerHeight * sy
        for i, file in ipairs(files) do
            local t = p.art[i]
            if not t then t = p:CreateTexture(nil, "BORDER"); p.art[i] = t end
            t:SetTexture(file); t:SetVertexColor(0.55, 0.55, 0.55, 1)
            t:SetWidth(tw); t:SetHeight(th); t:ClearAllPoints()
            t:SetPoint("TOPLEFT", p, "TOPLEFT", ox + ((i - 1) % cols) * tw, -(oy + math.floor((i - 1) / cols) * th))
            t:Show()
        end
    end
    local rx, ry = CAMP_YARDS * perYard, CAMP_YARDS * perYard
    for _, camp in ipairs(v.camps) do
        local on = not focus or camp.counts[focus]
        local color = camp.shared and SHARED or SINGLE
        local x, y = at(camp.point.x, camp.point.y)
        local d = p.dots.get(); d:SetWidth(2 * rx); d:SetHeight(2 * ry); d:ClearAllPoints(); d:SetPoint("CENTER", p, "TOPLEFT", x, y)
        d:SetVertexColor(color[1], color[2], color[3], on and 0.3 or 0.08)
        local t = p.texts.get(); t:SetFontObject("GameFontNormalSmall"); t:SetText(camp.id); t:ClearAllPoints()
        t:SetPoint("CENTER", p, "TOPLEFT", x, y); t:SetAlpha(on and 1 or 0.35)
        local h = p.hits.get(); h:SetWidth(24); h:SetHeight(16); h:ClearAllPoints(); h:SetPoint("CENTER", p, "TOPLEFT", x, y)
        h.tipTitle, h.tipLines = campTitle(camp), campLines(v, camp)
        h.onClick = function() waypointTo(camp.point) end
    end
    for _, pt in ipairs(v.points) do
        local on = focus == pt.col
        local x, y = at(pt.x, pt.y)
        local d = p.dots.get(); local size = on and 7 or 5
        d:SetWidth(size); d:SetHeight(size); d:ClearAllPoints(); d:SetPoint("CENTER", p, "TOPLEFT", x, y)
        if on then d:SetVertexColor(SHARED[1] + 0.25, SHARED[2] + 0.25, 1, 1)
        else d:SetVertexColor(0.85, 0.85, 0.8, focus and 0.25 or 0.85) end
    end
    -- givers standing together (Sten and Balir, Durnan and Marryk) share one square: "Sten, Balir"
    local spots = {}
    for _, g in ipairs(v.givers or {}) do
        local first = g.name:match("^(%S+)") or g.name
        if first == "Mountaineer" then first = g.name:match("(%S+)$") or first end   -- a title, not a name
        local x, y = at(g.x, g.y)
        local joined
        for _, s in ipairs(spots) do
            if math.abs(s.x - x) < 14 and math.abs(s.y - y) < 14 then s.names[#s.names + 1] = first; joined = true; break end
        end
        if not joined then spots[#spots + 1] = { x = x, y = y, names = { first } } end
    end
    for _, g in ipairs(spots) do
        local x, y = g.x, g.y
        if x > 0 and x < MAP_W and -y > 0 and -y < NET_H then
            local b = p.boxes.get(); setTexColor(b, 1, 0.82, 0, 1); b:SetWidth(8); b:SetHeight(8)
            b:ClearAllPoints(); b:SetPoint("CENTER", p, "TOPLEFT", x, y)
            local t = p.texts.get(); t:SetFontObject("GameFontHighlightSmall"); t:SetText(table.concat(g.names, ", "))
            t:ClearAllPoints()
            if x > MAP_W - 90 then t:SetPoint("RIGHT", p, "TOPLEFT", x - 7, y) else t:SetPoint("LEFT", p, "TOPLEFT", x + 7, y) end
            t:SetAlpha(1)
        end
    end
end

-- Columns past MAX_COLS fold into the last one ("Other"), so no spawn is dropped.
local function drawMatrix(v)
    local cols, fold = {}, {}
    for i, col in ipairs(v.columns) do
        if i < MAX_COLS or #v.columns == MAX_COLS then cols[#cols + 1] = { name = col.name, quest = col.quest, ids = { i } }
        else
            if not fold.ids then fold = { name = "Other", quest = (#v.columns - MAX_COLS + 1) .. " more objectives", ids = {} }; cols[#cols + 1] = fold end
            fold.ids[#fold.ids + 1] = i
        end
    end
    local most = 1
    for _, camp in ipairs(v.camps) do for _, n in pairs(camp.counts) do if n > most then most = n end end end
    win.questHead:Show(); win.matTitle:Show()
    for c, h in ipairs(win.heads) do
        local col = cols[c]
        h.col = col
        if col then h.text:SetText(col.name); h:Show() else h:Hide() end
    end
    for r, row in ipairs(win.rows) do
        local camp = v.camps[r]
        row.camp, row.view = camp, v
        if camp then
            local near = nearestGiver(v, camp)
            row.name:SetText(camp.id .. "  " .. (near or string.format("%.1f, %.1f", camp.point.x * 100, camp.point.y * 100)))
            row.quests:SetText((camp.shared and S.BLUE or S.GREY) .. camp.questCount .. "|r")
            for c, cell in ipairs(row.cells) do
                local col, n, lit = cols[c], 0, not focus
                for _, id in ipairs(col and col.ids or {}) do n = n + (camp.counts[id] or 0); if id == focus then lit = true end end
                if col and n > 0 then
                    local step = math.min(#RAMP, math.max(1, math.ceil(math.sqrt(n / most) * #RAMP)))
                    local rgb = RAMP[step]
                    setTexColor(cell.bg, rgb[1], rgb[2], rgb[3], lit and 1 or 0.3)
                    cell.text:SetText((step >= 4 and S.WHITE or "|cff101010") .. n .. "|r")
                    cell.bg:Show()
                else
                    cell.bg:Hide(); cell.text:SetText("")
                end
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

function C.fillTable()
    if not win then return end
    local v = view()
    local any = v ~= nil and v.camps[1] ~= nil
    if any then win.net:Show(); win.map:Show() else win.net:Hide(); win.map:Hide() end
    if not (v and v.camps[1]) then
        win.hint:SetText("No shared camps yet: open the Quest guide in a zone with kill or collect quests.")
        for _, b in ipairs(win.filters) do b:Hide() end
        for _, h in ipairs(win.heads) do h:Hide() end
        for _, row in ipairs(win.rows) do row:Hide() end
        win.questHead:Hide(); win.matTitle:Hide()
        win.net.title:Hide(); win.net.note:Hide(); win.map.title:Hide(); win.map.note:Hide()
        win:SetHeight(80)
        return
    end
    win:SetHeight(WIN_H)
    win.net.title:Show(); win.net.note:Show(); win.map.title:Show(); win.map.note:Show()
    if focus and not v.columns[focus] then focus = nil end
    local shared = 0
    for _, camp in ipairs(v.camps) do if camp.shared then shared = shared + 1 end end
    win.hint:SetText(string.format("%d camps (5+ spawns within %d yards); %s%d serve 2 or more quests|r: one visit there helps several quests.%s",
        #v.camps, CAMP_YARDS, S.BLUE, shared, #v.camps > MAX_ROWS and string.format(" Showing the %d biggest.", MAX_ROWS) or ""))
    drawFilters(v)
    drawNetwork(v)
    drawMap(v)
    drawMatrix(v)
end

function C.openTable()
    if not ns.db.enabled then ns.print("switch Quest Sharing on first (/qs on)"); return end
    if not (win or buildTable()) then return end
    C.fillTable()
    win:Show()
    if win.Raise then win:Raise() end
end
C.open = C.openTable

function C._table() return win end
function C._focus(col) setFocus(col) end

local function tick()
    local wm = WorldMapFrame
    -- reschedule first, so an error in draw cannot end the loop
    ns.after(ns.db.enabled and ns.db.campMap and wm and call(wm.IsShown, wm) and 0.5 or 2, tick)
    C.draw()
end
ns.on("PLAYER_LOGIN", function() ns.after(1, tick) end)
ns.on("PLAYER_REGEN_DISABLED", hide)
ns.on("PLAYER_REGEN_ENABLED", C.refresh)
