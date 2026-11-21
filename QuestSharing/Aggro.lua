-- Aggro.lua: for tanks (aggroPlates). While you fight, every enemy nameplate shows your share of its aggro as a plain
-- number, "73%" (the game's threat percent; 100% = it is attacking you). Nothing else: no colours, icons or marks.
-- The number is our own frame placed over the nameplate; nothing is written onto the game's nameplate.
-- Needs enemy nameplates (the V key, or Settings > Quest markers > Turn on enemy health bars).
local ADDON, ns = ...
ns.inModule("combat")          -- Modules.lua: Settings > General > Tools can switch this off

local A = {}
ns.aggro = A

local TICK = 0.5          -- threat also changes without an event reaching us: look again this often in a fight

function A.supported()
    return (UnitDetailedThreatSituation and C_NamePlate and C_NamePlate.GetNamePlates) and true or false
end

local function fighting()
    return (UnitAffectingCombat and UnitAffectingCombat("player")) or (InCombatLockdown and InCombatLockdown()) or false
end

local function on() return ns.db.enabled and ns.db.aggroPlates and true or false end

local function tokenOf(plate)
    return plate.unitToken or plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

-- my share of this enemy's aggro in percent, or nil when it is no living enemy in a fight
function A.threatOf(unit)
    local ok, attackable = pcall(UnitCanAttack, "player", unit)
    if not (ok and attackable) then return nil end
    if UnitIsDead and UnitIsDead(unit) then return nil end
    if UnitAffectingCombat and not UnitAffectingCombat(unit) then return nil end
    local okT, tanking, _, scaled = pcall(UnitDetailedThreatSituation, "player", unit)
    if not okT then return nil end
    if tanking then return 100 end
    return math.floor((tonumber(scaled) or 0) + 0.5)
end

-- one number per nameplate frame, kept in OUR table
local labels = setmetatable({}, { __mode = "k" })
function A.labelFor(plate) return plate and labels[plate] end            -- for the tests

local function label(plate)
    local f = labels[plate]
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetWidth(60)
        f:SetHeight(16)
        f:SetFrameStrata("HIGH")
        local t = f:CreateFontString(nil, "OVERLAY")
        t:SetFontObject("GameFontHighlight")
        t:SetAllPoints(f)
        f.text = t
        f:Hide()
        labels[plate] = f
    end
    if f.anchoredTo ~= plate then
        f:ClearAllPoints()
        if not pcall(f.SetPoint, f, "BOTTOM", plate.UnitFrame or plate, "TOP", 0, 2) then return nil end
        f.anchoredTo = plate
    end
    return f
end

local function hideAll() for _, f in pairs(labels) do f:Hide() end end

function A.refresh()
    if not (on() and A.supported() and fighting()) then return hideAll() end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not (ok and plates) then return hideAll() end
    local seen = {}
    for _, plate in ipairs(plates) do
        local unit = tokenOf(plate)
        local pct = unit and A.threatOf(unit)
        local f = pct and label(plate)
        if f then
            f.text:SetText(pct .. "%")
            f:Show()
            seen[f] = true
        end
    end
    for _, f in pairs(labels) do if not seen[f] then f:Hide() end end
end

-- what the addon can see right now: printed when you switch it on
function A.status()
    local plates = 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, list = pcall(C_NamePlate.GetNamePlates)
        if ok and list then plates = #list end
    end
    local shown = ns.enemyNameplatesOn and ns.enemyNameplatesOn()
    return string.format("aggro numbers %s | threat data from the game: %s | enemy nameplates: %s | nameplates now: %d",
        on() and "on" or "off", UnitDetailedThreatSituation and "yes" or "NO (this client cannot show aggro)",
        shown and "on" or "OFF (press V)", plates)
end

-- events: threat changes and nameplates coming and going; a short tick while fighting
local soon
local function refreshSoon()
    if soon or not on() then return end
    soon = ns.after(0.1, function() soon = nil; A.refresh() end)
end
for _, e in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "NAME_PLATE_UNIT_ADDED",
                     "NAME_PLATE_UNIT_REMOVED" }) do
    ns.on(e, refreshSoon)
end

local ticking
local function tick()
    ticking = nil
    A.refresh()
    if on() and fighting() then ticking = ns.after(TICK, tick) end
end
local function start()
    if ticking or not on() then return end
    ticking = ns.after(0, tick)
end
ns.on("PLAYER_REGEN_DISABLED", start)
ns.on("PLAYER_REGEN_ENABLED", function()
    if ticking then ns.cancel(ticking); ticking = nil end
    hideAll()
end)

-- the earlier version switched enemy nameplates on and saved your own value: put it back once (outside a fight)
ns.on("PLAYER_ENTERING_WORLD", function()
    local d = ns.db
    if d.aggroCVarSaved == nil or (InCombatLockdown and InCombatLockdown()) then return end
    if not d.highlightCVars and ns.setCVar then ns.setCVar("nameplateShowEnemies", d.aggroCVarSaved) end
    d.aggroCVarSaved = nil
end)

-- switched on or off in Settings or with /qs aggro (also in the middle of a fight)
function A.settingChanged()
    if on() then ns.print(A.status()); start(); A.refresh() else hideAll() end
end
