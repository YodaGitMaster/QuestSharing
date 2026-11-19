-- Gathering items (hides, leather, cloth, meat, herbs, ore...): hover one in your bags or in the Professions window to see
-- the three best places to get it, and Ctrl+right-click it to mark those places on the world map with the item's icon.
-- "Best" = fits your level and faction, then the most items per visit (known spawns x chance) of one creature or node in
-- one zone; one zone is listed once. Each tooltip line: name · zone · chance. The map pins add level and spawn count.
local ADDON, ns = ...
local Q, U, S, V, W = ns.questie, ns.optionalUI, ns.style, ns.vendorMap, ns.dataWork
local G = {}
ns.gatherSources = G

local call = U.call
local TOP, MAX_SOURCES, MAX_POINTS = 3, 400, 40
-- trade-goods subclasses that are gathered rather than crafted: cloth, leather, metal & stone, meat, herb, elemental
local GATHERED = { [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true }
local cache, running, active, layer, layerParent, pins, hovered = {}, {}, nil, nil, nil, {}, nil
local lastClick = { time = -1 }

local function enabled() return ns.db and ns.db.enabled and ns.db.itemSources and not ns.isBlocked("itemsources") end
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end

local function itemID(link)
    if type(link) ~= "string" then return nil end
    return tonumber(string.match(link, "|Hitem:(%d+)")) or tonumber(string.match(link, "^item:(%d+)"))
end

local function itemFacts(id)
    -- not U.call: it hands back only three values and the class is the sixth
    local ok, _, _, _, _, icon, class, sub = pcall(GetItemInfoInstant or function() end, id)
    if not ok then return nil end
    return class, sub, icon or call(GetItemIcon, id)
end

-- Classic item data files leather, hides, cloth, ore, stone and meat under 7/0 "Trade Goods" (only herbs get their own
-- subclass) and elementals under 5 "Reagent": those count too, and anything the bundled skinning table knows.
-- A crafted trade good (a bar, a bolt) has no creature or node, so it simply shows nothing.
function G.isGathering(id)
    if type(id) ~= "number" then return false end
    if ns.skinningData and ns.skinningData[id] then return true end
    local class, sub = itemFacts(id)
    if class == 7 then return sub == 0 or GATHERED[sub] == true end
    return class == 5 and sub == 0
end

-- objectDrops also lists chests, crates and lockboxes that happen to hold the item: those are not places to gather
local CONTAINER_WORDS = { "chest", "strongbox", "crate", "box", "lockbox", "locker", "footlocker", "coffer", "cache",
    "barrel", "sack", "bag", "trunk" }
local function isContainer(name)
    if type(name) ~= "string" then return true end
    local lower = string.lower(name)
    for _, w in ipairs(CONTAINER_WORDS) do
        if string.find(lower, "%f[%a]" .. w .. "%f[%A]") then return true end
    end
    return false
end
G._isContainer = isContainer                                            -- for the tests

local function zoneName(area)
    local name = call(C_Map and C_Map.GetAreaInfo, area) or (GetAreaInfo and call(GetAreaInfo, area))
    return type(name) == "string" and name or "Unknown zone"
end

-- One group per (name, zone): the spawn points of every creature of that name in that zone. Runs inside a DataWork job.
local function collect(id)
    local faction = Q.me().faction
    local byKey, groups = {}, {}
    local function add(kind, sourceID, skinChance)
        local name = Q.get(kind, sourceID, "name")
        if type(name) ~= "string" or name == "" then return end
        if kind == "npc" then
            local friendly = Q.get("npc", sourceID, "friendlyToFaction")
            if faction and type(friendly) == "string" and string.find(friendly, faction, 1, true) then return end -- not prey
        end
        local lo, hi = Q.get(kind, sourceID, "minLevel"), Q.get(kind, sourceID, "maxLevel")
        for _, s in ipairs(Q.spawnList(kind, sourceID)) do
            if s.map and not s.dungeon and finite(s.x) and finite(s.y) then
                local key = name .. "\0" .. s.area
                local g = byKey[key]
                if not g then
                    g = { kind = kind, id = sourceID, name = name, area = s.area, map = s.map, points = {},
                        skin = skinChance ~= nil, rate = skinChance }
                    byKey[key] = g; groups[#groups + 1] = g
                end
                g.points[#g.points + 1] = s
                if type(lo) == "number" and (not g.lo or lo < g.lo) then g.lo = lo end
                if type(hi) == "number" and (not g.hi or hi > g.hi) then g.hi = hi end
            end
        end
        W.checkpoint()
    end
    local mobs, nodes = Q.get("item", id, "npcDrops"), Q.get("item", id, "objectDrops")
    for i, sourceID in ipairs(type(mobs) == "table" and mobs or {}) do
        if i > MAX_SOURCES then break end
        add("npc", sourceID)
    end
    -- QuestieDB has no skinning loot, so hides and leather come from the bundled table (SkinningData.lua):
    -- { creature, tenths of a percent, ... }
    local skins = ns.skinningData and ns.skinningData[id]
    for i = 1, math.min(#(skins or {}), MAX_SOURCES * 2), 2 do add("npc", skins[i], skins[i + 1] / 10) end
    -- only real nodes (veins, deposits, herbs) count: by the object's name, not the item subclass (Classic files ore under 0)
    for i, sourceID in ipairs(type(nodes) == "table" and nodes or {}) do
        if i > MAX_SOURCES then break end
        if not isContainer(Q.get("object", sourceID, "name")) then add("object", sourceID) end
    end
    return groups
end

-- Ranking: what fits me first (creatures at most LEVEL_SLACK levels above me, not in the other faction's home zones),
-- then the most items per visit (spawns x chance). Only zones that fit are shown, unless none does.
local LEVEL_SLACK = 3
local UNKNOWN_DROP, NODE_CHANCE = 0.1, 1
-- UI map ids of the faction home zones (starting zones and the zones right after them); everything else counts as open
local HOME = { [1429] = "A", [1426] = "A", [1438] = "A", [1436] = "A", [1432] = "A", [1439] = "A",
    [1411] = "H", [1412] = "H", [1420] = "H", [1413] = "H", [1421] = "H" }
G._HOME = HOME

local function fits(g, me)
    if me.level and g.lo and g.lo > me.level + LEVEL_SLACK then return false end
    local owner = HOME[g.map]
    return not (me.faction and owner and owner ~= me.faction)
end

local function better(a, b)
    if a.fits ~= b.fits then return a.fits end
    if a.score ~= b.score then return a.score > b.score end
    if a.name ~= b.name then return a.name < b.name end
    return a.area < b.area
end

local function rank(groups, itemID)
    local me = Q.me()
    for _, g in ipairs(groups) do
        if g.kind == "npc" and not g.rate then g.rate = Q.itemDropRate(itemID, g.id) end
        local chance = g.rate and g.rate / 100 or (g.kind == "object" and NODE_CHANCE or UNKNOWN_DROP)
        g.score, g.fits = #g.points * chance, fits(g, me)
        W.checkpoint()
    end
    local bestInZone = {}
    for _, g in ipairs(groups) do
        local cur = bestInZone[g.area]
        if not cur or better(g, cur) then bestInZone[g.area] = g end
    end
    local list = {}
    for _, g in pairs(bestInZone) do list[#list + 1] = g end
    table.sort(list, better)
    -- out.fallback: nothing fits me, these are the best known anyway; out.leftOut: zones skipped, for /qs gather
    local out = { fallback = list[1] ~= nil and not list[1].fits, leftOut = { level = 0, faction = 0 } }
    for _, g in ipairs(list) do
        if not g.fits then
            if me.level and g.lo and g.lo > me.level + LEVEL_SLACK then out.leftOut.level = out.leftOut.level + 1
            else out.leftOut.faction = out.leftOut.faction + 1 end
        end
    end
    for i = 1, math.min(TOP, #list) do
        local g = list[i]
        if not g.fits and list[1].fits then break end          -- never pad the fitting zones with ones that do not fit
        g.count = #g.points
        while #g.points > MAX_POINTS do table.remove(g.points) end
        out[#out + 1] = g
    end
    return out
end

-- Fills the cache for one item (a cooperative job: hundreds of creatures can drop a common hide), then calls done().
function G.load(id, done)
    if cache[id] then if done then done(cache[id]) end return end
    if running[id] then running[id][#running[id] + 1] = done; return end
    running[id] = { done }
    local result = {}
    W.start("gather-sources:" .. id, function()
        result = rank(collect(id), id)
    end, nil, function(ok, err)
        cache[id] = ok and result or {}
        if not ok then ns.logError("gather sources", err) end
        local waiting = running[id]; running[id] = nil
        for _, fn in ipairs(waiting or {}) do if fn then pcall(fn, cache[id]) end end
    end, 6)
end

local function levelText(g)
    if not g.lo then return "" end
    return " (level " .. g.lo .. ((g.hi and g.hi ~= g.lo) and ("-" .. g.hi) or "") .. ")"
end

local function percent(rate)
    return (rate >= 10 and string.format("%.0f", rate) or string.format("%.1f", rate)) .. "%"
end

-- Cmd stands in for Ctrl on a Mac: name the key the player actually has
local function clickKey() return ((IsMacClient and IsMacClient()) and "Cmd" or "Ctrl") .. "+right-click" end

function G.lines(sources)
    local out = {}
    for i, g in ipairs(sources) do
        local chance = g.rate and percent(g.rate) or (g.kind == "object" and "node" or "chance unknown")
        out[i] = i .. ". " .. g.name .. " · " .. zoneName(g.area) .. " · " .. chance
    end
    return out
end

local function addToTooltip(tooltip, sources)
    if #sources == 0 then return end
    tooltip:AddLine(sources.fallback and "Where to gather (none for your level and faction; best known)"
        or "Where to gather (for your level and faction)", 0.95, 0.78, 0.30)
    for _, line in ipairs(G.lines(sources)) do tooltip:AddLine(line, 1, 1, 1, true) end
    tooltip:AddLine(clickKey() .. " this item to mark them on the map", 0.62, 0.62, 0.62, true)
    tooltip:Show()
end

local function onTooltip(tooltip, data)
    if tooltip ~= GameTooltip or not enabled() or not Q.available() then return end
    local _, link = call(tooltip.GetItem, tooltip)
    local id = itemID(link) or (type(data) == "table" and tonumber(data.id)) or nil
    if id then G.lastItem = id end
    if not id or tooltip.questSharingGatherID == id or not G.isGathering(id) then return end
    tooltip.questSharingGatherID = id
    G.load(id, function(sources)
        if tooltip.questSharingGatherID == id and call(tooltip.IsShown, tooltip) then addToTooltip(tooltip, sources) end
    end)
end

-- Map marks --------------------------------------------------------------------------------------------------------------
local function pinTip(pin)
    local g = pin.source
    if not g then return end
    local lines = { zoneName(g.area) .. " · " .. g.count .. " known spawn" .. (g.count == 1 and "" or "s"),
        (g.kind == "object" and "Gather it here for " or g.skin and "Skin it for " or "Drops ") .. (active and active.name or "the item")
            .. (g.rate and (" (" .. percent(g.rate) .. ")") or ""),
        S.GREY .. "Click to set a waypoint.|r" }
    U.tip(pin, g.name .. levelText(g), lines)
end

local function makePin()
    local pin = CreateFrame("Button", nil, layer)
    pin:SetWidth(20); pin:SetHeight(20); pin:EnableMouse(true)
    pin.ring = S.fill(pin, "BACKGROUND", 1, 0.82, 0, 1); pin.ring:SetAllPoints(pin)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 2, -2); pin.icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -2, 2)
    pin:RegisterForClicks("LeftButtonUp")
    pin:SetScript("OnEnter", function(self) hovered = self; pinTip(self) end)
    pin:SetScript("OnLeave", function(self) if hovered == self then hovered = nil end; U.hideTip() end)
    pin:SetScript("OnClick", function(self)
        local p = self.point
        if p and not ns.compat.setWaypoint(p.map, p.x / 100, p.y / 100) then ns.print("the game could not set a waypoint here") end
    end)
    return pin
end

local function hidePins()
    for _, p in ipairs(pins) do p:Hide() end
    if hovered then hovered = nil; U.hideTip() end
end

function G.draw()
    local wm = WorldMapFrame
    local child = wm and wm.ScrollContainer and wm.ScrollContainer.Child
    if not (active and enabled() and child and call(wm.IsShown, wm)) or call(InCombatLockdown) or not (V and V.pointOnMap) then
        hidePins(); if layer then layer:Hide() end
        return
    end
    local map = call(wm.GetMapID, wm)
    local width, height = call(child.GetWidth, child), call(child.GetHeight, child)
    local scale = call(child.GetScale, child) or 1
    if not (map and finite(width) and finite(height) and width > 0 and height > 0) then hidePins(); return end
    if not finite(scale) or scale <= 0 then scale = 1 end
    if not layer then
        layer = CreateFrame("Frame", "QuestSharingGatherOverlay", UIParent)
        layer:EnableMouse(false)
    end
    if layerParent ~= child then layer:SetParent(child); layer:SetAllPoints(child); layerParent = child end
    layer:Show()
    local strata = call(child.GetFrameStrata, child)
    local base = math.min(9800, (call(child.GetFrameLevel, child) or 0) + 1600)
    if strata then layer:SetFrameStrata(strata) end
    layer:SetFrameLevel(base)
    local n = 0
    for _, g in ipairs(active.sources) do
        for _, s in ipairs(g.points) do
            local x, y = V.pointOnMap(s.map, s.x / 100, s.y / 100, map)
            if finite(x) and finite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                n = n + 1
                local pin = pins[n] or makePin()
                pins[n] = pin
                pin.source, pin.point = g, s
                if strata then pin:SetFrameStrata(strata) end
                pin:SetFrameLevel(base + 1)
                pin.icon:SetTexture(active.icon)
                pin:ClearAllPoints(); pin:SetScale(1 / scale)
                pin:SetPoint("CENTER", layer, "TOPLEFT", x * width * scale, -y * height * scale)
                pin:Show()
            end
        end
    end
    for i = n + 1, #pins do pins[i]:Hide() end
end

local function tick()
    if not active then return end
    ns.after(0.5, tick)
    G.draw()
end

function G.clear()
    active = nil
    hidePins(); if layer then layer:Hide() end
end

-- the point of a group closest to the middle of its spawns: where a waypoint is most likely to put you among them
local function heart(g)
    local sx, sy = 0, 0
    for _, s in ipairs(g.points) do sx, sy = sx + s.x, sy + s.y end
    sx, sy = sx / #g.points, sy / #g.points
    local best, bestD
    for _, s in ipairs(g.points) do
        local d = (s.x - sx) ^ 2 + (s.y - sy) ^ 2
        if not bestD or d < bestD then best, bestD = s, d end
    end
    return best
end

function G.mark(id)
    if active and active.id == id then
        local name = active.name
        G.clear(); ns.print("removed the map marks for " .. name)
        return
    end
    G.load(id, function(sources)
        local name = call(GetItemInfo, id) or ("item " .. id)
        if #sources == 0 then ns.print("QuestieDB knows no creature or node that gives " .. name .. "."); return end
        local _, _, icon = itemFacts(id)
        active = { id = id, name = name, icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark", sources = sources }
        ns.print("marked " .. name .. " (zoom the world map out to see every zone):")
        for _, line in ipairs(G.lines(sources)) do ns.print(line) end
        local first = sources[1]
        local p = heart(first)
        if p then ns.compat.setWaypoint(p.map, p.x / 100, p.y / 100) end
        ns.print("open your world map (M); the first zone is " .. zoneName(first.area))   -- addon code must not open the map itself
        ns.after(0.2, tick)
        G.draw()
    end)
end

-- Ctrl+right-click on whatever item the tooltip is showing: bags, the Professions window, anywhere --------------------------
local hinted = {}
local function hintOnce(key, text)
    if hinted[key] then return end
    hinted[key] = true; ns.print(text)
end
local function modifierDown()
    return (IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown()) -- Cmd stands in for Ctrl on a Mac
end
local function onMouseDown(_, button)
    if button ~= "RightButton" or not modifierDown() or not ns.db or not ns.db.enabled then return end
    if not (GameTooltip and call(GameTooltip.IsShown, GameTooltip)) then return end
    local _, link = call(GameTooltip.GetItem, GameTooltip)
    local id = itemID(link)
    if not id or not G.isGathering(id) then return end
    if not ns.db.itemSources then
        hintOnce("setting", "turn on " .. (ns.settingPath and ns.settingPath("itemSources") or "Settings") .. " to see where this is gathered")
        return
    end
    if not enabled() then return end
    if not Q.available() then hintOnce("questie", "where-to-gather needs QuestieDB: install or enable it, then /reload (check with /qs questie)"); return end
    local now = call(GetTime) or 0
    if lastClick.id == id and now - lastClick.time < 0.3 then return end   -- one click, not two events
    lastClick.id, lastClick.time = id, now
    G.mark(id)
end

-- /qs gather [item id or link]: one plain sentence on why an item does or does not show places (defaults to the last
-- item you hovered). The item class, subclass and drop counts go to the debug log (/qs log, /qs doctor), not to chat.
function G.command(arg)
    local id = tonumber(arg) or itemID(arg) or G.lastItem
    if not ns.db.itemSources then
        ns.print("where to gather is off: turn on " .. (ns.settingPath and ns.settingPath("itemSources") or "Settings") .. ".")
        return
    end
    if not Q.available() then ns.print("where to gather needs QuestieDB: install or enable it, then /reload."); return end
    if not id then ns.print("hover an item first, or type /qs gather followed by the item number or a shift-clicked item"); return end
    local name = call(GetItemInfo, id) or Q.get("item", id, "name") or ("Item " .. id)
    local class, sub = itemFacts(id)
    if ns.log then
        ns.log("gather", "item " .. id .. ": class " .. tostring(class) .. ", subclass " .. tostring(sub) .. ", "
            .. #(Q.get("item", id, "npcDrops") or {}) .. " creature drops, " .. #(Q.get("item", id, "objectDrops") or {})
            .. " object drops, " .. math.floor(#((ns.skinningData or {})[id] or {}) / 2) .. " skinned creatures")
    end
    if not G.isGathering(id) then ns.print(name .. " is not something you gather, so no places are listed."); return end
    G.load(id, function(sources)
        if #sources == 0 then ns.print(name .. ": no known creature or node gives it, so no places are listed."); return end
        ns.print(name .. ": shown. " .. #sources .. (#sources == 1 and " zone" or " zones") .. " known.")
        for _, line in ipairs(G.lines(sources)) do ns.print(line) end
        local left = sources.leftOut
        if left and (left.level > 0 or left.faction > 0) then
            local other = Q.me().faction == "H" and "Alliance" or "Horde"
            ns.print("left out: " .. left.level .. " zone(s) with creatures more than " .. LEVEL_SLACK .. " levels above you, "
                .. left.faction .. " in " .. other .. " home zones" .. (sources.fallback and " (nothing fits, so the best known are shown)" or ""))
        end
    end)
end

local hooked
local function install()
    if hooked or not GameTooltip then return end
    hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltip)
    else
        GameTooltip:HookScript("OnTooltipSetItem", onTooltip)
    end
    GameTooltip:HookScript("OnTooltipCleared", function(self) self.questSharingGatherID = nil end)
end

function G.refresh()
    install()
    if not enabled() then G.clear() end
end

-- true when this tooltip will carry the ranked "Where to gather" block (the Professions tooltip then leaves its drops out)
function G.covers(id) return enabled() and Q.available() and G.isGathering(id) or false end
function G._active() return active end
function G._reset() cache, running = {}, {}; G.clear() end

ns.on("PLAYER_LOGIN", install)
ns.on("ADDON_LOADED", install)
ns.on("GLOBAL_MOUSE_DOWN", onMouseDown)
ns.on("PLAYER_LEVEL_UP", function() cache = {} end)                    -- the ranking depends on my level
W.onPurge("Where to gather", function() cache = {} end)
ns.on("WORLD_MAP_UPDATE", function() if active then G.draw() end end)
ns.on("PLAYER_REGEN_DISABLED", function() if active then G.draw() end end)
