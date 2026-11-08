-- Highlight.lua: make quest objectives easier to find.
--   * a quest icon above the nameplate of every creature that is part of one of your quests
--     (the game says so itself: C_QuestLog.UnitIsRelatedToActiveQuest)
--   * (Track.lua) the game's own waypoint marker follows the nearest quest
--   * an optional helper that switches on the game settings these things need: enemy nameplates, and
--     icons over objects you can interact with. It remembers your settings and puts them back.
-- Every call into the game is wrapped, because the newest clients hide some values from addons in combat
-- and in instances.
local ADDON, ns = ...
local C = ns.compat

local TEXTURE = "Interface\\TargetingFrame\\PortraitQuestBadge"       -- the gold quest badge
local SIZE = 28

-- needs the nameplate calls; telling quest creatures apart works with the game's own answer or the names (Compat)
function C.canMarkMobs()
    return (C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlateForUnit) and true or false
end

local function isObjective(unit) return C.isQuestCreature(unit) end

local function tokenOf(plate)
    return plate.unitToken or plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

-- One icon per nameplate frame, kept in OUR table: nothing is ever written onto the game's nameplate (that would taint
-- it: "Lua Taint: QuestSharing"). The icon is our own frame (a child of UIParent), only placed over the nameplate, so
-- showing / hiding it is never a restricted action, also in combat.
local markers = setmetatable({}, { __mode = "k" })
function ns.markerFor(plate) return plate and markers[plate] end            -- for the tests

local function marker(plate)
    if markers[plate] then return markers[plate] end
    if InCombatLockdown and InCombatLockdown() then return nil end      -- placing it over a nameplate: outside combat
    ns.trying("placing a quest icon over a nameplate", "markers")
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetWidth(SIZE)
    f:SetHeight(SIZE)
    f:SetFrameStrata("HIGH")
    if not pcall(f.SetPoint, f, "BOTTOM", plate.UnitFrame or plate, "TOP", 0, 2) then return nil end
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(f)
    t:SetTexture(TEXTURE)
    f.texture = t
    f:Hide()
    markers[plate] = f
    return f
end

local function update(plate)
    if not plate or ns.isBlocked("markers") then return end
    local unit = tokenOf(plate)
    local show = ns.db.markMobs and unit and isObjective(unit)
    if show then
        local m = marker(plate)
        if m then m:Show() end
    elseif markers[plate] then
        markers[plate]:Hide()
    end
end

function ns.refreshMarkers()
    if not C.canMarkMobs() then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not (ok and plates) then return end
    for _, plate in ipairs(plates) do pcall(update, plate) end
end

ns.on("NAME_PLATE_UNIT_ADDED", function(_, unit)
    if not C.canMarkMobs() then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if ok then pcall(update, plate) end
end)

ns.on("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    if not C.canMarkMobs() then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if ok and plate and markers[plate] then markers[plate]:Hide() end
end)

-- a creature stops being an objective when the quest progresses: look again a moment after the quest log changes
local soon
local function refreshSoon()
    if soon then return end
    soon = ns.after(0.5, function() soon = nil; ns.refreshMarkers() end)
end
for _, e in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
    ns.on(e, refreshSoon)
end

local function tick()
    if ns.db.markMobs then ns.refreshMarkers() end
    ns.after(2, tick)                                   -- a safety net for anything the events miss
end
ns.on("PLAYER_ENTERING_WORLD", function() ns.after(2, tick) end)
ns.on("PLAYER_REGEN_ENABLED", function() ns.after(1, ns.refreshMarkers) end)        -- nameplates that came during the fight

-- Game settings helper ------------------------------------------------------------------------------------------
-- nameplateShowEnemies   enemy nameplates must be on for the markers to show at all
-- SoftTargetIconGameObject  an icon over objects you can interact with, when you are close
local CVARS = { nameplateShowEnemies = "1", SoftTargetIconGameObject = "1" }

local function getCVar(name)
    local f = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not f then return nil end
    local ok, v = pcall(f, name)
    return ok and v or nil
end

local function setCVar(name, value)
    ns.trying("changing a game setting (" .. tostring(name) .. ")", "cvars")
    local f = (C_CVar and C_CVar.SetCVar) or SetCVar
    return f and (pcall(f, name, value)) or false
end

function ns.enemyNameplatesOn() return getCVar("nameplateShowEnemies") == "1" end

function ns.setHighlightCVars(on)
    if InCombatLockdown and InCombatLockdown() then
        ns.db.highlightCVars = not on
        return ns.print("game settings cannot be changed in combat; try again afterwards")
    end
    local d = ns.db
    if on then
        d.cvarSaved = d.cvarSaved or {}
        local changed = {}
        for name, value in pairs(CVARS) do
            local current = getCVar(name)
            if current ~= nil then
                if d.cvarSaved[name] == nil then d.cvarSaved[name] = current end
                if current ~= value and setCVar(name, value) then changed[#changed + 1] = name .. "=" .. value end
            end
        end
        d.highlightCVars = true
        ns.print("game settings: " .. (#changed > 0 and table.concat(changed, ", ") or "already as needed")
                 .. " (switching this off puts your own values back)")
    else
        for name, value in pairs(d.cvarSaved or {}) do setCVar(name, value) end
        d.cvarSaved, d.highlightCVars = nil, false
        ns.print("game settings: your own values are back")
    end
end

ns.on("PLAYER_ENTERING_WORLD", function()
    if ns.db.highlightCVars and not (InCombatLockdown and InCombatLockdown()) then
        for name, value in pairs(CVARS) do
            if getCVar(name) ~= nil and getCVar(name) ~= value then setCVar(name, value) end
        end
    end
end)

-- /qs highlight ... ------------------------------------------------------------------------------------------------
function ns.highlightCommand(arg)
    local what, state = string.match(arg or "", "^(%S*)%s*(%S*)$")
    what = string.lower(what or "")
    local function flip(key, cur) if state == "on" then return true elseif state == "off" then return false end return not cur end
    if what == "mobs" then ns.setSetting("markMobs", flip("markMobs", ns.db.markMobs)); ns.refreshMarkers()
    elseif what == "pin" then ns.setSetting("nearPin", flip("nearPin", ns.db.nearPin))
    elseif what == "cvars" then ns.setSetting("highlightCVars", flip("highlightCVars", ns.db.highlightCVars))
    else
        local function f(v) return v and "on" or "off" end
        ns.print(string.format("highlight: quest creature markers %s%s | pin the nearest quest in the world %s | game settings helper %s",
            f(ns.db.markMobs), C.canMarkMobs() and "" or " (not available on this client)", f(ns.db.nearPin), f(ns.db.highlightCVars)))
        ns.print("/qs highlight mobs|pin|cvars [on|off]    enemy nameplates are " .. (ns.enemyNameplatesOn() and "ON" or "OFF (markers need them: /qs highlight cvars on)"))
    end
end
