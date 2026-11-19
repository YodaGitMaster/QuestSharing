-- Aggro.lua: for tanks (aggroPlates). Every enemy nameplate always shows how much of that enemy's aggro you hold (the
-- game's threat percent: 100 % = it is attacking you). The colour follows the fight, as a tank sees a room:
--   white  = nobody is fighting it yet (you walk into the room)
--   red    = it is on you, 100 % (with a small flame beside the number)
--   green  = below 50 %: someone's spell pulled it away, it is leaving you
--   orange = 50-99 %, medium: you hit it and it is coming back
-- In a fight, among the enemies right next to you (about 10 yards) the one with the LOWEST aggro, and every one within
-- 10 points of it (only below 50 %: orange means it is coming back), gets the one alarm: its portrait in a pulsing red ring, with "Losing aggro 20%" in grey under it.
-- That is the only mark (a marked enemy is never at 100 %, so the red ring and the red number never meet).
local ADDON, ns = ...

local A = {}
ns.aggro = A

local TICK, IDLE_TICK = 0.3, 1   -- distance changes fire no event: look again this often (fighting / not fighting)
local FLAME = "Interface\\Icons\\Spell_Fire_Fire"   -- beside the number while you hold 100 % aggro
local RING = "Interface\\Buttons\\UI-ActionButton-Border"   -- soft glow, tinted red, around the portrait of a marked one
local PULSE = 1.2                                     -- seconds for one pulse of the ring (dim -> bright -> dim)
local GREY = "|cff9d9d9d"
local NEAR_INDEX = 3      -- CheckInteractDistance index 3 = about 10 yards (duel range)
local BAND = 10           -- white: the lowest near enemy and every near one at most this many points above it

function A.supported()
    return (UnitDetailedThreatSituation and C_NamePlate and C_NamePlate.GetNamePlates) and true or false
end

local function fighting()
    return (UnitAffectingCombat and UnitAffectingCombat("player")) or (InCombatLockdown and InCombatLockdown()) or false
end

local function wanted() return ns.db.enabled and ns.db.aggroPlates and true or false end

function A.active()
    return wanted() and A.supported() and true or false
end

local function inFight(unit)                                  -- the enemy is fighting someone (a client without the call: yes)
    if not UnitAffectingCombat then return true end
    return UnitAffectingCombat(unit) and true or false
end

local function tokenOf(plate)
    return plate.unitToken or plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

-- my share of this enemy's aggro in percent (0-100+; 0 when it is not fighting), or nil when it is no living enemy
function A.threatOf(unit)
    local ok, attackable = pcall(UnitCanAttack, "player", unit)
    if not (ok and attackable) then return nil end
    if UnitIsDead and UnitIsDead(unit) then return nil end
    local okT, tanking, _, scaled = pcall(UnitDetailedThreatSituation, "player", unit)
    if not okT then return nil end
    if tanking then return 100 end
    return math.floor((tonumber(scaled) or 0) + 0.5)
end

-- right next to me; a client that refuses the distance question in combat counts every visible enemy as near
function A.near(unit)
    if not CheckInteractDistance then return true end
    local ok, near = pcall(CheckInteractDistance, unit, NEAR_INDEX)
    if not ok then return true end
    return near and true or false
end

-- labels: one per nameplate frame, kept in OUR table
local labels = setmetatable({}, { __mode = "k" })
function A.labelFor(plate) return plate and labels[plate] end            -- for the tests

local function label(plate)
    local f = labels[plate]
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetWidth(130)
        f:SetHeight(18)
        f:SetFrameStrata("HIGH")
        local t = f:CreateFontString(nil, "OVERLAY")
        t:SetFontObject("GameFontNormal")
        t:SetAllPoints(f)
        f.text = t
        local flame = f:CreateTexture(nil, "OVERLAY")
        flame:SetWidth(16)
        flame:SetHeight(16)
        flame:SetPoint("RIGHT", t, "CENTER", -20, 0)           -- just left of the number
        flame:SetTexture(FLAME)
        flame:SetTexCoord(0.08, 0.92, 0.08, 0.92)              -- trim the icon border
        flame:Hide()
        f.flame = flame
        -- the alarm: portrait in a pulsing red ring, just above the "Losing aggro" line
        local portrait = f:CreateTexture(nil, "ARTWORK")
        portrait:SetWidth(28)
        portrait:SetHeight(28)
        portrait:SetPoint("BOTTOM", t, "TOP", 0, 2)
        portrait:Hide()
        f.portrait = portrait
        local ring = f:CreateTexture(nil, "OVERLAY")
        ring:SetWidth(52)
        ring:SetHeight(52)
        ring:SetPoint("CENTER", portrait, "CENTER", 0, 0)
        ring:SetTexture(RING)
        ring:SetBlendMode("ADD")
        ring:SetVertexColor(1, 0.1, 0.1)
        ring:Hide()
        f.ring = ring
        f:Hide()
        labels[plate] = f
    end
    -- right on top of the nameplate; above the gold quest badge (Highlight.lua, 28 px) when that one shows
    local badge = ns.markerFor and ns.markerFor(plate)
    local y = (badge and badge:IsShown()) and 32 or 2
    if f.anchoredTo ~= plate or f.anchorY ~= y then
        f:ClearAllPoints()
        if not pcall(f.SetPoint, f, "BOTTOM", plate.UnitFrame or plate, "TOP", 0, y) then return nil end
        f.anchoredTo, f.anchorY = plate, y
    end
    return f
end

-- white = nobody is fighting it, red = I hold it, orange = medium, green = about to leave me
local MEDIUM = 50
local function color(pct, fightingIt)
    if not fightingIt then return "|cffffffff" end      -- idle: untouched
    if pct >= 100 then return "|cffff3030" end          -- attacking me
    if pct >= MEDIUM then return "|cffff9a1a" end       -- medium
    return "|cff33ff33"                                 -- about to leave me
end

-- the ring breathes while the alarm shows: our own frame's OnUpdate, nothing protected
local function pulse(f, elapsed)
    f.pulseT = ((f.pulseT or 0) + (elapsed or 0)) % PULSE
    local a = 0.35 + 0.65 * (0.5 - 0.5 * math.cos(2 * math.pi * f.pulseT / PULSE))
    f.ringAlpha = a
    f.ring:SetAlpha(a)
end

local function alarm(f, unit, on)
    if on then
        if SetPortraitTexture then pcall(SetPortraitTexture, f.portrait, unit) end
        f.portrait:Show()
        f.ring:Show()
        if not f.pulsing then f:SetScript("OnUpdate", pulse); f.pulsing = true end
    else
        f.portrait:Hide()
        f.ring:Hide()
        if f.pulsing then f:SetScript("OnUpdate", nil); f.pulsing = false end
    end
end

local function hideAll()
    for _, f in pairs(labels) do alarm(f, nil, false); f:Hide() end
    A.pick, A.picks = nil, {}
end

-- the enemies to mark (the alarm): the lowest-aggro one among the near ones in this fight and every near one within BAND points
-- of it (several equally urgent mobs show together; close numbers swapping places does not move the marks). Only when
-- I am fighting, two or more are near (a single one needs no pick), and only below MEDIUM (orange = coming back).
-- Returns a set { [entry] = true } (empty: no mark) and the lowest entry.
function A.choose(list)
    local marked = {}
    if not fighting() then return marked, nil end
    local best, nearCount = nil, 0
    for _, e in ipairs(list) do
        if e.near and e.fighting then
            nearCount = nearCount + 1
            if not best or e.pct < best.pct then best = e end
        end
    end
    if nearCount < 2 or best.pct >= MEDIUM then return marked, nil end         -- 50 %+ = orange, coming back: no alarm
    for _, e in ipairs(list) do
        if e.near and e.fighting and e.pct < MEDIUM and e.pct <= best.pct + BAND then marked[e] = true end
    end
    return marked, best
end

function A.refresh()
    if not A.active() then return hideAll() end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not (ok and plates) then return hideAll() end
    local list, seen = {}, {}
    for _, plate in ipairs(plates) do
        local unit = tokenOf(plate)
        local pct = unit and A.threatOf(unit)
        if pct then
            list[#list + 1] = { plate = plate, unit = unit, pct = pct, near = A.near(unit), fighting = inFight(unit) }
        end
    end
    local marked, lowest = A.choose(list)
    local picks = {}
    for _, e in ipairs(list) do
        local f = label(e.plate)
        if f then
            seen[f] = true
            f.text:SetFontObject("GameFontNormal")
            if marked[e] then
                picks[#picks + 1] = e.unit
                f.text:SetText(string.format("%sLosing aggro %d%%|r", GREY, e.pct))
            else
                f.text:SetText(string.format("%s%d%%|r", color(e.pct, e.fighting), e.pct))
            end
            alarm(f, e.unit, marked[e] == true)
            if e.pct >= 100 and e.fighting then f.flame:Show() else f.flame:Hide() end
            f:Show()
        end
    end
    for _, f in pairs(labels) do if not seen[f] then alarm(f, nil, false); f:Hide() end end
    A.pick = lowest and lowest.unit or nil         -- the lowest one
    A.picks = picks                                -- every white one (the lowest included)
end

-- events: threat changes and nameplates coming and going; a short tick while fighting for distance changes
local soon
local function refreshSoon()
    if soon or not wanted() then return end
    soon = ns.after(0.1, function() soon = nil; A.refresh() end)
end
for _, e in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "NAME_PLATE_UNIT_ADDED",
                     "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED" }) do
    ns.on(e, refreshSoon)
end

local ticking
local function tick()
    if not A.active() then ticking = nil; return hideAll() end
    A.refresh()
    ticking = ns.after(fighting() and TICK or IDLE_TICK, tick)
end
local function start()
    if ticking or not A.active() then return end
    ticking = ns.after(0, tick)
end
-- Enemy nameplates: the only way an addon sees every enemy around you. While the setting is on they are switched on
-- for you; your own value is saved in ns.db.aggroCVarSaved and put back when you switch it off. The game refuses this
-- change in combat, so it waits for the fight to end. Highlight.lua's helper (highlightCVars) keeps its own saved copy.
local CVAR = "nameplateShowEnemies"

local function getCVar() return ns.getCVar(CVAR) end           -- shared with Highlight.lua
local function setCVar(value) return ns.setCVar(CVAR, value) end

local function inLockdown() return (InCombatLockdown and InCombatLockdown()) and true or false end

-- make the game's nameplate setting match the aggro setting; true when nothing is left to do
function A.applyNameplates()
    local d = ns.db
    if inLockdown() then return false end
    local want = wanted()
    if want then
        local current = getCVar()
        if current == nil then return true end                 -- this client has no such setting
        if current ~= "1" then
            if d.aggroCVarSaved == nil then d.aggroCVarSaved = current end
            if setCVar("1") then ns.print("enemy nameplates switched on for the aggro marks (switching aggro off puts yours back)") end
        end
    elseif d.aggroCVarSaved ~= nil then
        local saved = d.aggroCVarSaved
        d.aggroCVarSaved = nil
        if d.highlightCVars and type(d.cvarSaved) == "table" then
            d.cvarSaved[CVAR] = saved                          -- the quest-marker helper still needs them: it restores later
        elseif getCVar() ~= saved then
            setCVar(saved)
            ns.print("enemy nameplates: your own value is back")
        end
    end
    return true
end

local pendingCVar = false
local function applySoon()
    pendingCVar = not A.applyNameplates()
    if pendingCVar then ns.print("enemy nameplates change after this fight (the game does not allow it in combat)") end
end

local function restart()                                     -- the fight started or ended: switch to the other pace now
    if ticking then ns.cancel(ticking); ticking = nil end
    start()
end
ns.on("PLAYER_REGEN_DISABLED", restart)
ns.on("PLAYER_REGEN_ENABLED", function()
    restart()
    if pendingCVar then ns.after(0.5, applySoon) end
end)
ns.on("PLAYER_ENTERING_WORLD", function()                     -- the game may have reset it (another addon, a new client)
    if wanted() and not inLockdown() then A.applyNameplates() end
    start()
end)

-- switched on or off in Settings (also in the middle of a fight); also after the quest-marker helper put its values back
local toldUnsupported
function A.settingChanged()
    if wanted() and not A.supported() and not toldUnsupported then
        toldUnsupported = true
        ns.print("aggro marks: this game client does not tell addons the threat of enemies, so nothing can be shown")
    end
    applySoon()
    if A.active() then start(); A.refresh() else hideAll() end
end
