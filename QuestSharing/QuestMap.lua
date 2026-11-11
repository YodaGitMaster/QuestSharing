-- QuestMap.lua: a light quest map. Where to do the objectives of YOUR quests (the creatures to kill, who or what drops
-- the items, the objects to use, the places to go) and, once a quest is done, where to turn it in: small icons on the
-- world map and the minimap, at most a few per objective (the ones nearest to you).
--   * The data comes from QuestieDB (Questie's quest data, its own folder since Questie 12).
--   * It draws only while the Questie addon itself is off: Questie draws its own, and two sets of icons would crowd
--     the maps. It says so once. To use this lighter map: switch Questie off at the character screen, keep QuestieDB.
--   * Our own small frames placed over the maps (like the party members' icons): never the game's own map pins,
--     which the game refuses to addons in part ("SetPassThroughButtons").
local ADDON, ns = ...
local C = ns.compat

local M = {}
ns.questMap = M

local PER_TARGET = 6                 -- icons per objective: the nearest ones
local TICK = 0.2                     -- seconds between two looks at the maps
local ICON = {
    kill = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",       -- the skull
    loot = "Interface\\Icons\\INV_Misc_Bag_08",
    object = "Interface\\Icons\\INV_Misc_Gear_01",
    explore = "Interface\\Icons\\INV_Misc_Map_01",
    turnin = "Interface\\GossipFrame\\ActiveQuestIcon",                -- the yellow "?"
}
-- the minimap's radius in yards for each zoom level (the game's own steps), outdoors and indoors
local RADIUS_OUT = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local RADIUS_IN = { [0] = 300, 240, 180, 120, 80, 50 }

local function questieAddonOn()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not f then return false end
    local ok, v = pcall(f, "Questie")
    return ok and v and true or false
end

-- may it draw? (true) or (false, why)
function M.state()
    local d = ns.db
    if not (d.enabled and d.questMap) then return false, "switched off (/qs questmap on)" end
    local q = ns.questie
    local src = q and q.source()
    if src ~= "QuestieDB" and src ~= "LibQuestieDB" then
        return false, "needs QuestieDB, Questie's quest data: " .. tostring(q and q.whyMissing() or "not found")
    end
    if questieAddonOn() then
        return false, "off while the Questie addon is on (it draws its own): switch Questie off at the character screen " ..
            "and keep QuestieDB to use this lighter one"
    end
    return true
end

-- The points: { map, x, y (0..1), kind, label, quest, cont, wa, wb (world position, for the minimap) } -----------------
local points, version = {}, 0

-- the objectives of a quest that the game does not count as finished yet
local function openTargets(e, q)
    local finished = {}
    for _, o in ipairs(C.objectives(e)) do
        if o.finished and o.text then finished[#finished + 1] = string.lower(o.text) end
    end
    local out = {}
    for _, tg in ipairs(q.targets(e.questID)) do
        local name, done = string.lower(tg.name or ""), false
        for _, txt in ipairs(finished) do if name ~= "" and string.find(txt, name, 1, true) then done = true end end
        if not done then out[#out + 1] = tg end
    end
    return out
end

local function addPoint(s, kind, label, e)
    if not (s and s.map and not s.dungeon and s.x and s.y) then return end
    local p = { map = s.map, x = s.x / 100, y = s.y / 100, kind = kind, label = label, quest = e.title }
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok, cont, w = pcall(C_Map.GetWorldPosFromMapPos, s.map, CreateVector2D(p.x, p.y))
        if ok and w and w.GetXY then p.cont = cont; p.wa, p.wb = w:GetXY() end
    end
    points[#points + 1] = p
end

function M.rebuild()
    points = {}
    version = version + 1
    if not M.state() then return end
    local q = ns.questie
    ns.trying("finding where your quests are done (quest map)", "questmap")
    for _, e in ipairs(C.entries()) do
        if e.complete then
            local t = q.turnIn(e.questID)
            if t then
                for _, s in ipairs(q.nearest(t.spawns, 2)) do addPoint(s, "turnin", "turn in at " .. t.who, e) end
            end
        else
            for _, tg in ipairs(openTargets(e, q)) do
                for _, s in ipairs(q.nearest(tg.spawns, PER_TARGET)) do addPoint(s, tg.kind, tg.label, e) end
            end
        end
    end
    ns.log("quest map", #points .. " places for your quests")
end
function M.points() return points end                            -- for the tests

-- The icons -------------------------------------------------------------------------------------------------------------
local function newPin(parent, size)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetWidth(size)
    pin:SetHeight(size)
    pin.icon = pin:CreateTexture(nil, "OVERLAY")
    pin.icon:SetAllPoints(pin)
    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self)
        if GameTooltip and self.qpoint then pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.qpoint.quest or "?")
            GameTooltip:AddLine(self.qpoint.label or "", 1, 1, 1)
            GameTooltip:Show()
        end) end
    end)
    pin:SetScript("OnLeave", function() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end)
    return pin
end

local function dress(pin, p)
    pin.qpoint = p                                             -- ("point" would clash with frame anchors in tests)
    pin.icon:SetTexture(ICON[p.kind] or ICON.object)
end

-- the world map: the points of the map it shows
local worldPins, lastWorld = {}, {}
local function canvas()
    local wm = WorldMapFrame
    if not (wm and wm.GetMapID and wm.ScrollContainer and wm.ScrollContainer.Child) then return nil end
    return wm, wm.ScrollContainer.Child
end

function M.drawWorld(force)
    local wm, cv = canvas()
    if not wm then return end
    local shown = wm:IsShown() and wm:GetMapID()
    local scale = (cv.GetScale and cv:GetScale()) or 1
    if not force and shown == lastWorld.map and version == lastWorld.version and scale == lastWorld.scale then return end
    lastWorld.map, lastWorld.version, lastWorld.scale = shown, version, scale
    local n = 0
    if shown and M.state() then
        for _, p in ipairs(points) do
            if p.map == shown then
                n = n + 1
                local pin = worldPins[n] or newPin(cv, 14)
                worldPins[n] = pin
                dress(pin, p)
                pin:SetScale(1 / ((scale > 0) and scale or 1))             -- the same size at every zoom level
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", cv, "TOPLEFT", p.x * cv:GetWidth() * scale, -p.y * cv:GetHeight() * scale)
                pin:Show()
            end
        end
    end
    for i = n + 1, #worldPins do worldPins[i]:Hide() end
end
function M._worldPins() return worldPins end                     -- for the tests

-- the minimap: the points around you, from the game's world positions (yards) and the minimap's zoom
local miniPins = {}
function M.drawMinimap()
    local n = 0
    if Minimap and #points > 0 and M.state() and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local map, px, py = C.playerPos()
        local ok, cont, w = false, nil, nil
        if map then ok, cont, w = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(px, py)) end
        if ok and w and w.GetXY then
            local pa, pb = w:GetXY()                              -- north, west (the game's world axes)
            local zoom = (Minimap.GetZoom and Minimap:GetZoom()) or 0
            local radius = ((IsIndoors and IsIndoors()) and RADIUS_IN or RADIUS_OUT)[zoom] or 300
            local half = ((Minimap.GetWidth and Minimap:GetWidth()) or 140) / 2
            local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
            local rotate = getCVar ~= nil and getCVar("rotateMinimap") == "1"
            local facing = (rotate and GetPlayerFacing and GetPlayerFacing()) or 0
            local cs, sn = math.cos(-facing), math.sin(-facing)
            for _, p in ipairs(points) do
                if p.cont == cont and p.wa then
                    local dx, dy = -(p.wb - pb), p.wa - pa               -- yards: right = east, up = north
                    if rotate then dx, dy = dx * cs - dy * sn, dx * sn + dy * cs end
                    if dx * dx + dy * dy < (radius * 0.92) ^ 2 then      -- inside the minimap's circle
                        n = n + 1
                        local pin = miniPins[n] or newPin(Minimap, 12)
                        miniPins[n] = pin
                        dress(pin, p)
                        pin:ClearAllPoints()
                        pin:SetPoint("CENTER", Minimap, "CENTER", dx / radius * half, dy / radius * half)
                        pin:Show()
                    end
                end
            end
        end
    end
    for i = n + 1, #miniPins do miniPins[i]:Hide() end
end
function M._miniPins() return miniPins end                       -- for the tests

-- Keeping it up to date -----------------------------------------------------------------------------------------------
local pending = false
local function soon()
    if pending then return end
    pending = true
    ns.after(1, function() pending = false; M.rebuild(); M.drawWorld(true); M.drawMinimap() end)
end
M.refresh = soon
for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
    ns.on(ev, soon)
end

local sinceRebuild = 0
local function tick()
    if not ns.isBlocked("questmap") then
        M.drawWorld()
        M.drawMinimap()
        sinceRebuild = sinceRebuild + TICK
        if sinceRebuild >= 15 then sinceRebuild = 0; soon() end   -- you moved: other spawns may be the nearest now
    end
    ns.after(TICK, tick)
end
ns.after(3, tick)

-- once a session: Questie is on, so this map stays off (and how to use it instead)
local told = false
ns.on("PLAYER_LOGIN", function()
    ns.after(6, function()
        local on, why = M.state()
        if on or told or not ns.db.questMap or not questieAddonOn() then return end
        local src = ns.questie and ns.questie.source()
        if src ~= "QuestieDB" and src ~= "LibQuestieDB" then return end
        told = true
        ns.print("quest map: " .. why)
    end)
end)
