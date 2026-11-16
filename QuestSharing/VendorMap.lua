-- Optional QuestieDB vendor lookup on Blizzard's existing world map. Only reads QuestieDB and draws addon-owned pins.
local ADDON, ns = ...
local Q, U, S = ns.questie, ns.optionalUI, ns.style
local V = {}
ns.vendorMap = V

local items, vendors, ready, loading = {}, {}, false, false
local generation, currentQuery, currentOnly = 0, "", false
local mapUI, hookedScroll, pins, lastRender, lastRenderAt = nil, nil, {}, nil, 0
local activeView = "map"
local function call(fn, ...) return U.call(fn, ...) end
local function trim(s) return (string.gsub(string.gsub(tostring(s or ""), "^%s+", ""), "%s+$", "")) end
local function lower(s) return string.lower(type(s) == "string" and s or "") end
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function matchesWords(text, query)
    local hay = lower(text)
    local any = false
    for word in string.gmatch(lower(query), "%S+") do
        any = true
        if not string.find(hay, word, 1, true) then return false end
    end
    return any
end

local function buildIndex()
    if ready or loading then return end
    local ids = Q and Q.ids and Q.ids("item")
    if type(ids) ~= "table" then
        if mapUI then mapUI.status:SetText("Search needs a recent QuestieDB item list.") end
        return
    end
    generation = generation + 1
    local token, cursor = generation, 1
    loading, items, vendors = true, {}, {}
    local function batch()
        if token ~= generation or not (ns.db.enabled and ns.db.vendorSearch) then loading = false; return end
        for _ = 1, 120 do
            local id = ids[cursor]
            if not id then
                loading, ready = false, true
                for vendorID in pairs(vendors) do
                    vendors[vendorID].title = Q.get("npc", vendorID, "subName")
                    vendors[vendorID].spawns = Q.spawnList("npc", vendorID)
                end
                V.search(currentQuery, currentOnly)
                if mapUI and U.call(mapUI.edit.HasFocus, mapUI.edit) then
                    mapUI.refreshSuggestions(currentQuery)
                end
                return
            end
            cursor = cursor + 1
            local name = Q.get("item", id, "name")
            local list = Q.get("item", id, "vendors")
            if type(name) == "string" and type(list) == "table" and #list > 0 then
                local row, seen = { id = id, name = name, key = lower(name), vendorIDs = {} }, {}
                for _, vendorID in ipairs(list) do
                    if finite(vendorID) and not seen[vendorID] then
                        seen[vendorID] = true
                        row.vendorIDs[#row.vendorIDs + 1] = vendorID
                        vendors[vendorID] = vendors[vendorID] or { id = vendorID }
                    end
                end
                if #row.vendorIDs > 0 then items[#items + 1] = row end
            end
        end
        ns.after(0.02, batch)
    end
    batch()
end

local function mapInfo(map)
    local info = call(C_Map and C_Map.GetMapInfo, map)
    return type(info) == "table" and info or nil
end

-- Transform a Questie spawn's local 0..1 position through parent maps to the currently shown map.
local function pointOnMap(map, x, y, target)
    if not (map and target and finite(x) and finite(y)) then return nil end
    if map == target then return x, y end
    local id, seen = map, {}
    for _ = 1, 12 do
        if seen[id] then return nil end
        seen[id] = true
        local info = mapInfo(id)
        local parent = info and info.parentMapID
        if not parent or parent == 0 then return nil end
        local fn = C_Map and C_Map.GetMapRectOnMap
        if type(fn) ~= "function" then return nil end
        local ok, x1, x2, y1, y2 = pcall(fn, id, parent)
        if not (ok and finite(x1) and finite(x2) and finite(y1) and finite(y2)) then return nil end
        x, y, id = x1 + x * (x2 - x1), y1 + y * (y2 - y1), parent
        if id == target then return x, y end
    end
end

local function continentPoint(map, x, y)
    local id = map
    local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent
    for _ = 1, 12 do
        local info = mapInfo(id)
        if not info then return nil end
        if continentType and info.mapType == continentType then return id, x, y end
        local parent = info.parentMapID
        if not parent or parent == 0 then return nil end
        local px, py = pointOnMap(id, x, y, parent)
        if not px then return nil end
        id, x, y = parent, px, py
    end
end

local function zoneName(area)
    local name = call(C_Map and C_Map.GetAreaInfo, area) or (GetAreaInfo and call(GetAreaInfo, area))
    return type(name) == "string" and name or "Unknown zone"
end

local function category(v)
    return type(v.title) == "string" and trim(v.title) ~= "" and trim(v.title) or "Vendor"
end

local function mapSearch(query)
    local needle, selected = lower(query), {}
    if needle == "" then return selected end
    for _, item in ipairs(items) do
        if matchesWords(item.key, needle) then
            for _, id in ipairs(item.vendorIDs) do selected[id] = true end
        end
    end
    for id, vendor in pairs(vendors) do
        if matchesWords(category(vendor), needle) then selected[id] = true end
    end
    return selected
end

local function nearestVendor(selected)
    local playerMap, px, py = ns.compat.playerPos()
    if not (playerMap and px and py) then return nil end
    local playerContinent, wx, wy = continentPoint(playerMap, px, py)
    if not playerContinent then return nil end
    local best
    for id in pairs(selected) do
        local vendor = vendors[id]
        for _, spawn in ipairs(vendor and vendor.spawns or {}) do
            if spawn.map and not spawn.dungeon then
                local cx, x, y = continentPoint(spawn.map, spawn.x / 100, spawn.y / 100)
                if cx == playerContinent then
                    local distance = (x - wx) ^ 2 + (y - wy) ^ 2
                    if not best or distance < best.distance then
                        best = { vendor = vendor, spawn = spawn, distance = distance }
                    end
                end
            end
        end
    end
    return best
end

local function pinFor(parent)
    local p = CreateFrame("Button", nil, parent)
    p:SetWidth(20); p:SetHeight(20)
    p.icon = p:CreateTexture(nil, "OVERLAY")
    p.icon:SetAllPoints(p); p.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    p:RegisterForClicks("LeftButtonUp")
    p:SetScript("OnEnter", function(self)
        local r = self.result
        U.tip(self, category(r.vendor), { zoneName(r.spawn.area) .. string.format(" (%.1f, %.1f)", r.spawn.x, r.spawn.y),
            "Click to set a waypoint." })
    end)
    p:SetScript("OnLeave", U.hideTip)
    p:SetScript("OnClick", function(self)
        local s = self.result.spawn
        if not ns.compat.setWaypoint(s.map, s.x / 100, s.y / 100) then
            ns.print("the game could not set a waypoint for this vendor")
        end
    end)
    return p
end

local function ensureUI(wm)
    if mapUI then return mapUI end
    local panel = CreateFrame("Frame", nil, wm, "BackdropTemplate")
    panel:SetWidth(420); panel:SetHeight(78); panel:SetPoint("TOPLEFT", wm, "TOPLEFT", 12, -54)
    S.fill(panel, "BACKGROUND", 0.025, 0.04, 0.065, 0.94):SetAllPoints(panel)
    U.text(panel, "Find items sold on this map", 8, 6, 252)
    local mapTab = S.button(panel, "Map", 56, function() V.setView("map") end)
    mapTab:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -94, -2)
    local sellersTab = S.button(panel, "Sellers", 80, function() V.setView("sellers") end)
    sellersTab:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -2)
    local edit = CreateFrame("EditBox", nil, panel)
    edit:SetWidth(284); edit:SetHeight(22); edit:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -23)
    if ChatFontNormal then edit:SetFontObject(ChatFontNormal) end
    edit:SetAutoFocus(false); edit:SetMaxLetters(70)
    if edit.SetTextInsets then edit:SetTextInsets(5, 5, 0, 0) end
    S.fill(edit, "BACKGROUND", 0, 0, 0, 0.8):SetAllPoints(edit)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); V.search(self:GetText(), false) end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local go = S.button(panel, "Search", 104, function() edit:ClearFocus(); V.search(edit:GetText(), false) end)
    go:SetPoint("TOPLEFT", panel, "TOPLEFT", 300, -22)
    local status = U.text(panel, "", 8, 47, 314)
    local waypoint = S.button(panel, "Waypoint", 78, function()
        local r = mapUI and mapUI.closest
        if r and not ns.compat.setWaypoint(r.spawn.map, r.spawn.x / 100, r.spawn.y / 100) then
            ns.print("the game could not set a waypoint for this vendor")
        end
    end)
    waypoint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -42)
    waypoint:Hide()
    local suggestionBox = CreateFrame("Frame", nil, wm, "BackdropTemplate")
    suggestionBox:SetWidth(284); suggestionBox:SetHeight(124)
    suggestionBox:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 8, -2)
    S.fill(suggestionBox, "BACKGROUND", 0.025, 0.04, 0.065, 0.98):SetAllPoints(suggestionBox)
    suggestionBox:Hide()
    local listFrame = CreateFrame("Frame", nil, wm, "BackdropTemplate")
    listFrame:SetWidth(380); listFrame:SetHeight(320)
    listFrame:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -2)
    S.fill(listFrame, "BACKGROUND", 0.025, 0.04, 0.065, 0.96):SetAllPoints(listFrame)
    U.text(listFrame, "Seller locations on this map", 8, 8, 364)
    local _, setList = U.scrollText(listFrame, 8, 30, 364, 280)
    listFrame:Hide()
    mapUI = { frame = panel, edit = edit, status = status, waypoint = waypoint,
        suggestionBox = suggestionBox, suggestionRows = {}, suggestions = {}, settingText = false,
        mapTab = mapTab, sellersTab = sellersTab, listFrame = listFrame, setList = setList }

    local function refreshSuggestions(text)
        local state = mapUI
        local query = trim(text)
        state.suggestions = {}
        if not ready or #query < 2 then
            state.suggestionBox:Hide()
            return
        end
        local found = {}
        local function add(value, label, rank, kind)
            local key = lower(value)
            if key == "" or key == lower(query) or found[key] then return end
            found[key] = true
            state.suggestions[#state.suggestions + 1] = { value = value, label = label, rank = rank, kind = kind }
        end
        -- Offer the useful role word first: typing "tail" can complete to "Tailor", which still matches
        -- every role containing Tailor, including "Senior Master Tailor".
        local roleWords = {}
        for _, vendor in pairs(vendors) do
            local title = category(vendor)
            for raw in string.gmatch(title, "%S+") do
                local word = string.gsub(string.gsub(raw, "^%p+", ""), "%p+$", "")
                if matchesWords(word, query) then roleWords[lower(word)] = word end
            end
        end
        for _, word in pairs(roleWords) do add(word, "Vendor type: " .. word, 1, "vendor") end
        for _, vendor in pairs(vendors) do
            local title = category(vendor)
            if matchesWords(title, query) then add(title, "Vendor: " .. title, 2, "vendor") end
        end
        local itemCount = 0
        for _, item in ipairs(items) do
            if matchesWords(item.name, query) then
                add(item.name, "Item: " .. item.name, 3, "item")
                itemCount = itemCount + 1
                if itemCount >= 80 then break end
            end
        end
        table.sort(state.suggestions, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return lower(a.value) < lower(b.value)
        end)
        local count = math.min(6, #state.suggestions)
        for i = 1, 6 do
            local row = state.suggestionRows[i]
            if not row then
                row = CreateFrame("Button", nil, state.suggestionBox)
                row:SetHeight(19); row:SetWidth(268)
                row:SetPoint("TOPLEFT", state.suggestionBox, "TOPLEFT", 8, -(5 + (i - 1) * 19))
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.text:SetWidth(264); row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
                row.highlight = S.fill(row, "BACKGROUND", 1, 1, 1, 0.12); row.highlight:SetAllPoints(row); row.highlight:Hide()
                row:SetScript("OnEnter", function(self) self.highlight:Show() end)
                row:SetScript("OnLeave", function(self) self.highlight:Hide() end)
                row:SetScript("OnClick", function(self)
                    local suggestion = self.suggestion
                    if suggestion then
                        state.settingText = true; state.edit:SetText(suggestion.value); state.settingText = false
                        state.suggestionBox:Hide()
                        V.search(suggestion.value, false, suggestion.kind == "item" and "sellers" or "map")
                    end
                end)
                state.suggestionRows[i] = row
            end
            local suggestion = state.suggestions[i]
            if suggestion then
                row.suggestion = suggestion
                row.text:SetText(suggestion.label)
                row:Show()
            else
                row.suggestion = nil; row:Hide()
            end
        end
        if count > 0 then state.suggestionBox:Show() else state.suggestionBox:Hide() end
    end
    mapUI.refreshSuggestions = refreshSuggestions
    edit:SetScript("OnTextChanged", function(self)
        if mapUI.settingText then return end
        currentQuery, currentOnly = trim(self:GetText()), false
        refreshSuggestions(currentQuery)
        V.draw()
    end)
    edit:SetScript("OnTabPressed", function()
        local suggestion = mapUI.suggestions[1]
        if suggestion then
            mapUI.settingText = true; edit:SetText(suggestion.value); mapUI.settingText = false
            mapUI.suggestionBox:Hide()
            V.search(suggestion.value, false, suggestion.kind == "item" and "sellers" or "map")
        end
    end)
    return mapUI
end

function V.setView(view)
    if view ~= "map" and view ~= "sellers" then return end
    activeView = view
    lastRender = nil
    V.draw()
end

local function exactItem(query)
    local needle = lower(trim(query))
    if needle == "" then return false end
    for _, item in ipairs(items) do
        if item.key == needle then return true end
    end
    return false
end

function V.search(query, mapOnly, view)
    currentQuery, currentOnly = trim(query), mapOnly == true
    if not mapUI then return end
    activeView = view or (exactItem(currentQuery) and "sellers" or "map")
    lastRender = nil
    mapUI.suggestionBox:Hide()
    mapUI.settingText = true
    mapUI.edit:SetText(currentQuery)
    mapUI.settingText = false
    if not ready then
        mapUI.status:SetText(loading and "Loading vendor data…" or "Loading Questie vendor data…")
        buildIndex(); return
    end
    V.draw()
end

function V.draw()
    local wm, query = WorldMapFrame, currentQuery
    local scroll = wm and wm.ScrollContainer
    local canvas = scroll and scroll.Child
    local on = ns.db.enabled and ns.db.vendorSearch and not ns.isBlocked("vendormap")
    if not (on and wm and canvas and call(wm.IsShown, wm)) then
        if mapUI then mapUI.frame:Hide(); mapUI.suggestionBox:Hide(); mapUI.listFrame:Hide() end
        for _, p in ipairs(pins) do p:Hide() end
        lastRender = nil
        return
    end
    local ui = ensureUI(wm); ui.frame:Show()
    ui.mapTab:SetLabel(activeView == "map" and "[Map]" or "Map")
    ui.sellersTab:SetLabel(activeView == "sellers" and "[Sellers]" or "Sellers")
    if scroll ~= hookedScroll and scroll.HookScript then
        scroll:HookScript("OnMouseDown", function(_, button)
            if button == "RightButton" and IsControlKeyDown and IsControlKeyDown()
                and ns.db.enabled and ns.db.vendorSearch then
                ui.edit:SetFocus()
                V.search(ui.edit:GetText(), true, "map")
            end
        end)
        hookedScroll = scroll
    end
    if query == "" then
        ui.closest = nil; ui.waypoint:Hide(); ui.listFrame:Hide()
        ui.status:SetText("Search an item or vendor type, like General Goods.")
        ui.setList("Search to see seller locations.")
        return
    end
    if not ready then
        ui.closest = nil; ui.waypoint:Hide()
        if activeView == "sellers" then ui.listFrame:Show() else ui.listFrame:Hide() end
        ui.status:SetText(loading and "Loading vendor data…" or "Loading Questie vendor data…")
        ui.setList("Loading vendor data…")
        buildIndex(); return
    end

    local selected, map = mapSearch(query), call(wm.GetMapID, wm)
    local width, height = call(canvas.GetWidth, canvas), call(canvas.GetHeight, canvas)
    local scale = call(canvas.GetScale, canvas) or 1
    local now = GetTime and GetTime() or 0
    if lastRender and lastRender.canvas == canvas and lastRender.query == query and lastRender.map == map
        and lastRender.only == currentOnly and lastRender.view == activeView
        and lastRender.width == width and lastRender.height == height
        and lastRender.scale == scale and lastRender.ready == ready and now - lastRenderAt < 3 then return end
    lastRender = { canvas = canvas, query = query, map = map, only = currentOnly, width = width, height = height,
        view = activeView, scale = scale, ready = ready }
    lastRenderAt = now
    ui.closest = nil; ui.waypoint:Hide()
    local results, selectedIDs = {}, {}
    for id in pairs(selected) do selectedIDs[#selectedIDs + 1] = id end
    table.sort(selectedIDs)
    for _, id in ipairs(selectedIDs) do
        local vendor = vendors[id]
        for _, spawn in ipairs(vendor and vendor.spawns or {}) do
            if spawn.map and not spawn.dungeon then
                local x, y = pointOnMap(spawn.map, spawn.x / 100, spawn.y / 100, map)
                if x then results[#results + 1] = { vendor = vendor, spawn = spawn, x = x, y = y } end
            end
        end
    end
    local localResults = results
    table.sort(localResults, function(a, b)
        local at, bt = lower(category(a.vendor)), lower(category(b.vendor))
        if at ~= bt then return at < bt end
        if a.spawn.area ~= b.spawn.area then return a.spawn.area < b.spawn.area end
        if a.spawn.x ~= b.spawn.x then return a.spawn.x < b.spawn.x end
        return a.spawn.y < b.spawn.y
    end)
    local n = 0
    if not finite(scale) or scale <= 0 then scale = 1 end
    for _, result in ipairs(localResults) do
        n = n + 1
        local p = pins[n] or pinFor(canvas)
        pins[n], p.result = p, result
        p:ClearAllPoints(); p:SetScale(1 / scale)
        p:SetPoint("CENTER", canvas, "TOPLEFT", result.x * canvas:GetWidth() * scale, -result.y * canvas:GetHeight() * scale)
        p:Show()
    end
    for i = n + 1, #pins do pins[i]:Hide() end
    if activeView == "sellers" then ui.listFrame:Show() else ui.listFrame:Hide() end
    local lines = {}
    if n > 0 then
        ui.status:SetText(n .. " seller location" .. (n == 1 and "" or "s") .. " on this map")
        lines[#lines + 1] = n .. " matching seller location" .. (n == 1 and "" or "s") .. ":"
        lines[#lines + 1] = ""
        for i, result in ipairs(localResults) do
            lines[#lines + 1] = string.format("%d. %s — %s (%.1f, %.1f)", i, category(result.vendor),
                zoneName(result.spawn.area), result.spawn.x, result.spawn.y)
        end
    elseif next(selected) == nil then
        ui.status:SetText("No known vendor sells an item or type matching that search.")
        lines[#lines + 1] = "No known vendor sells an item or type matching that search."
    elseif currentOnly then
        ui.status:SetText("No matching vendor is on this map.")
        lines[#lines + 1] = "No matching seller locations are on this map."
    else
        local nearest = nearestVendor(selected)
        if not nearest then
            ui.status:SetText("No matching vendor is on this map; no nearby seller location is known.")
            lines[#lines + 1] = "No matching seller is on this map; no nearby mapped seller is known."
        else
            local s, v = nearest.spawn, nearest.vendor
            ui.closest = nearest
            ui.waypoint:Show()
            local label = category(v) .. " · " .. zoneName(s.area) .. string.format(" (%.1f, %.1f)", s.x, s.y)
            ui.status:SetText("Closest: " .. label)
            lines[#lines + 1] = "No matching seller is on this map."
            lines[#lines + 1] = "Closest by map distance: " .. label
            lines[#lines + 1] = "Use the Waypoint button to mark this location."
        end
    end
    ui.setList(table.concat(lines, "\n"))
end

local function tick()
    V.draw()
    ns.after(0.5, tick)
end

function V.refresh()
    if not ns.db.vendorSearch then generation = generation + 1; loading = false end
    V.draw()
    if ns.db.vendorSearch then buildIndex() end
end

ns.on("PLAYER_LOGIN", function() ns.after(1, tick) end)
ns.on("WORLD_MAP_UPDATE", V.refresh)
