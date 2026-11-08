-- Ping.lua: one key (or a click on the ring) pings the nearest creature one of your quests needs with the game's
-- Attack ping, so the party sees what to kill; with no such creature in sight it pings the quest object you are facing
-- (the gear / hand icon) with the game's "look here" ping.
--
-- What the game allows, and so how this works:
--   * An addon can never ping, or pick a target, by itself: both only happen as the direct result of YOUR key press or
--     click. So the addon prepares a hidden secure button (outside combat it keeps loading "/targetexact <nearest quest
--     creature>" + "/ping [@target] attack" into it) and your key clicks that button.
--   * During combat secure buttons cannot be changed: it keeps the creature it loaded last.
--   * Anti-spam: at most one ping every 10 seconds (the time is a setting), and a new one after each fight. A creature
--     you pinged: the next ping once it is dead (a small secure snippet checks that, also in combat, where the game
--     gives secure code no clock). A quest object you pinged: the next one once you picked it up / used it (your
--     quest counter goes up), so you collect one, then the next press shows you another. Shift + the key pings anyway.
--   * The game gives addons no distance to enemies, and nameplates may not be measured (restricted regions). So
--     "nearest" is: your target if it is a quest creature, then the creature the game soft-targets in front of you, then
--     your mouseover, then one within about 28 yards, then any quest creature in sight.
local ADDON, ns = ...
local C = ns.compat

local BUTTON = "QuestSharingPingButton"
local CLICK = "CLICK " .. BUTTON .. ":LeftButton"
local REFRESH = 1                 -- seconds between two looks for the nearest quest creature (outside combat)

-- the secure part: runs before the macro, in the game's restricted environment (no clock there: the time rule is kept
-- outside combat by the addon, which may change attributes then)
local GATE = [[
    if down then return end
    local kind = self:GetAttribute("qs-kind")
    if kind == "none" or kind == nil then return end               -- nothing loaded: nothing to hold back
    if self:GetAttribute("qs-gate") == 1 and not IsShiftKeyDown() then
        if kind ~= "unit" then return false end
        if SecureCmdOptionParse("[@target,harm,nodead] alive; free") == "alive" then return false end
    end
    self:SetAttribute("qs-gate", 1)
    self:SetAttribute("qs-count", (self:GetAttribute("qs-count") or 0) + 1)
]]

local btn
local state = { count = 0, lastAt = -1000, macro = nil, kind = nil, name = nil, saidAt = -1000 }
ns.ping = state

-- the game's ping system is here when its API, its own helper or its key bindings are (clients differ in what they show)
local function pingSystemSeen()
    return C_Ping ~= nil or _G.PingUtil ~= nil or _G.BINDING_HEADER_PING_SYSTEM ~= nil or _G.BINDING_NAME_PINGATTACK ~= nil
end
ns.pingSystemSeen = pingSystemSeen

function ns.pingSupported()
    if not (pingSystemSeen() and SecureHandlerWrapScript and SetBindingClick) then return false end
    if C_Ping and C_Ping.IsPingSystemEnabled then
        local ok, on = pcall(C_Ping.IsPingSystemEnabled)
        if ok and on == false then return false end
    end
    return true
end

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- The nearest quest creature: within ~28 yards if any, then the one closest to the middle of the screen ------------
local function unitOf(plate)
    return plate.namePlateUnitToken or plate.unitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

local function questCreature(unit)
    if not (unit and UnitExists and UnitExists(unit)) then return nil end
    if not C.isQuestCreature(unit) then return nil end
    if not (UnitCanAttack and UnitCanAttack("player", unit)) or (UnitIsDead and UnitIsDead(unit)) then return nil end
    return UnitName(unit)
end

function ns.nearestQuestCreature()
    for _, u in ipairs({ "target", "softenemy", "mouseover" }) do        -- what you are already looking at comes first
        local name = questCreature(u)
        if name then return name end
    end
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not (ok and plates) then return nil end
    local first
    local measure = CheckInteractDistance and not inCombat()   -- in a fight the game refuses distances to enemies
    for _, plate in ipairs(plates) do
        local unit = unitOf(plate)
        local name = questCreature(unit)
        if name then
            local okD, close = false, false
            if measure then okD, close = pcall(CheckInteractDistance, unit, 4) end
            if okD and close then return name end                            -- within ~28 yards
            first = first or name
        end
    end
    return first
end

-- What the button will do on the next press -------------------------------------------------------------------------------
local function macroFor()
    local name = ns.nearestQuestCreature()
    if name then
        return "/targetexact " .. name .. "\n/ping [@target] attack", "unit", name
    end
    if ns.db.pingObjects then
        return "/ping [@softinteract,exists]", "object", nil                  -- the game's contextual ping: "look here"
    end
    return "", "none", nil
end

function ns.pingRefresh()
    if not btn or inCombat() then return end
    local macro, kind, name = macroFor()
    if macro ~= state.macro then
        ns.trying("preparing the ping button", "ping")
        btn:SetAttribute("macrotext", macro)
        btn:SetAttribute("qs-kind", kind)
        state.macro = macro
    end
    state.kind, state.name = kind, name
end

local function resetGate()
    if btn and not inCombat() then btn:SetAttribute("qs-gate", 0) end
end

-- after every click (insecure: only looks and talks): did it ping, or did the anti-spam hold it back? Always one short
-- line (at most every 3 seconds), so a press is never a mystery.
local function say(text)
    if text == state.lastSaid and GetTime() - state.saidAt < 3 then return end     -- the same line: not again so soon
    state.saidAt, state.lastSaid = GetTime(), text
    ns.print(text)
end

local function afterClick(self, _, down)
    if down then return end
    state.presses = (state.presses or 0) + 1
    local count = self:GetAttribute("qs-count") or 0
    if state.kind == "none" or not state.kind then
        say("nothing to ping: no quest creature in sight (enemy nameplates on?) - /qs ping checks everything")
    elseif count ~= state.count then
        state.count, state.lastAt, state.lastPinged = count, GetTime(), state.kind
        if state.kind == "unit" then say("ping: " .. tostring(state.name) .. " (attack)")
        elseif state.kind == "object" then say("ping: the quest object in front of you, if there is one (look here)")
        else say("nothing to ping: no quest creature in sight (enemy nameplates on?) - /qs ping checks everything") end
        local gap = ns.db.pingGap or 10
        ns.after(gap, function() if GetTime() - state.lastAt >= gap - 0.05 then resetGate() end end)
        if ns.quick and ns.quick.open and ns.quickClose then ns.quickClose() end
        ns.after(0.3, ns.pingRefresh)                          -- the next nearest one, once this press is over
    else
        say(string.format("ping held back: the one you pinged is still alive%s - hold Shift to ping anyway",
            inCombat() and "" or (" (or wait " .. (ns.db.pingGap or 10) .. " seconds)")))
    end
end

-- the game tells why a ping failed ("pings are disabled", "too many pings"...): pass it on
-- you picked up / used a quest object: the next press may point at the next one
function ns.onPickProgress()
    if state.kind == "object" or state.lastPinged == "object" then resetGate() end
end

ns.on("PING_SYSTEM_ERROR", function(_, err)
    state.lastError = tostring(err)
    ns.print("the game did not send the ping: " .. tostring(err))
end)

-- /qs ping: every link of the chain, so you can see where it stops
function ns.pingReport()
    local out = {}
    local function line(ok, text) out[#out + 1] = (ok and "[OK] " or "[--] ") .. text end
    local hasPing = pingSystemSeen()
    local enabled = hasPing and not (C_Ping and C_Ping.IsPingSystemEnabled and select(2, pcall(C_Ping.IsPingSystemEnabled)) == false)
    line(hasPing, "the game's ping system: " .. (hasPing and ("here" .. (C_Ping and "" or " (seen through its key bindings)")) or "NOT on this client - pings cannot work"))
    if hasPing then line(enabled, "pings switched on in the game: " .. (enabled and "yes" or "NO (game options > pings, or the party leader turned them off)")) end
    line(SecureHandlerWrapScript ~= nil and SetBindingClick ~= nil, "secure buttons and click bindings: " .. ((SecureHandlerWrapScript and SetBindingClick) and "yes" or "NO"))
    line(ns.db.ping and not ns.isBlocked("ping"), "the ping feature: " .. (ns.isBlocked("ping") and "switched off after the game refused it (/reload)" or (ns.db.ping and "on" or "off (/qs ping on)")))
    line(btn ~= nil, "the ping button: " .. (btn and "ready" or "not made (needs the ping system, outside combat)"))
    local key = ns.pingKeyName()
    line(key ~= nil, "ping key: " .. (key or "NOT SET - Settings > Pings & items > Ping key, or /qs pingkey G"))
    local api = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
    local names = 0
    for _ in pairs(C.questMobNames()) do names = names + 1 end
    local qs = ns.questie and ns.questie.available()
    local qsNote = qs and ns.questie.languageNote()                     -- Questie in another language: its names are not used
    line(api ~= nil or names > 0, "telling quest creatures apart: " .. (api and "yes (the game says)" or
        (names > 0 and ("by name, from your quest log" .. ((qs and not qsNote) and " and Questie" or "") .. ": " .. names .. " creature(s)")
         or ("NO - no creature names in your quest log" .. (qs and "" or " (Questie would help)")))))
    if qsNote and not api then line(false, qsNote) end
    line(ns.enemyNameplatesOn and ns.enemyNameplatesOn(), "enemy nameplates: " .. ((ns.enemyNameplatesOn and ns.enemyNameplatesOn()) and "on" or "OFF - press V (the addon finds quest creatures through them)"))
    local name = ns.nearestQuestCreature()
    line(name ~= nil, "nearest quest creature right now: " .. (name or "none in sight"))
    local macro = btn and btn:GetAttribute("macrotext") or ""
    out[#out + 1] = "next press does: " .. ((macro == "" and "nothing") or (string.gsub(macro, "\n", "  +  ")))
    out[#out + 1] = string.format("presses so far: %d, pings sent: %d%s", state.presses or 0, state.count or 0,
        state.lastError and (" | the game's last answer: " .. state.lastError) or "")
    return out
end

local function build()
    if btn then return btn end
    if inCombat() or not ns.pingSupported() then return nil end
    local ok, b = pcall(CreateFrame, "Button", BUTTON, UIParent, "SecureActionButtonTemplate")
    if not (ok and b) then return nil end
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b:SetAttribute("useOnKeyDown", false)          -- act on the release only: one press = one ping
    b:SetAttribute("macrotext", "")
    b:SetAttribute("qs-gate", 0)
    b:SetAttribute("qs-count", 0)
    b:SetWidth(34)
    b:SetHeight(34)
    b:SetFrameStrata("TOOLTIP")
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 200)          -- off screen until the ring needs it
    b:Show()
    local okH, header = pcall(CreateFrame, "Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    if okH and header then
        ns.trying("setting up the ping button", "ping")
        pcall(SecureHandlerWrapScript, b, "OnClick", header, GATE)
    end
    b:HookScript("OnClick", afterClick)
    btn = b
    ns.pingRefresh()
    return b
end
ns.pingButton = function() return btn end

-- Outside combat: look again every second. Combat: keep what was loaded; the anti-spam gate opens again afterwards.
local function tick()
    if ns.db.enabled and ns.db.ping and not ns.isBlocked("ping") then
        if not btn then build() end
        ns.pingRefresh()
    end
    ns.after(REFRESH, tick)
end
ns.after(2, tick)
-- after a fight: open the gate and look again a moment later (right at the edge of combat the game restricts a lot)
ns.on("PLAYER_REGEN_ENABLED", function() ns.after(1, function() resetGate(); ns.pingRefresh() end) end)

-- The key --------------------------------------------------------------------------------------------------------------------
function ns.pingKeyName()
    if not GetBindingKey then return nil end
    return (GetBindingKey(CLICK))
end

function ns.setPingKey(key)
    if inCombat() then return ns.print("key bindings cannot be changed in combat") end
    if not ns.pingSupported() then return ns.print("this game client has no ping system for addons to use") end
    if not build() then return ns.print("the ping button could not be made") end
    key = string.upper(key or "")
    if key == "" then return ns.print("ping key: " .. (ns.pingKeyName() or "not set") .. "  (/qs pingkey <KEY>, /qs pingkey none)") end
    for _, k in ipairs({ GetBindingKey(CLICK) }) do SetBinding(k) end
    if key ~= "NONE" then
        local before = GetBindingAction and GetBindingAction(key) or ""
        if ns.PROTECTED_KEYS and ns.PROTECTED_KEYS[before] then
            return ns.print(key .. " is the game's \"" .. ns.PROTECTED_KEYS[before] .. "\" key - pick another one (nothing was changed)")
        end
        ns.trying("setting the ping key")
        if not SetBindingClick(key, BUTTON, "LeftButton") then return ns.print("could not bind " .. key) end
    end
    local save = SaveBindings or AttemptToSaveBindings
    if save then save(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
    ns.print(key == "NONE" and "ping key removed" or ("ping key: " .. key .. " - pings the nearest creature your quests need"))
    if ns.refreshSettings then ns.refreshSettings() end
end

-- The ring: a "@ping" message becomes a ping slot. The secure button is laid over it while the ring is open (outside
-- combat only: in combat use the key).
function ns.pingOverlay(slotButton)
    if not btn or inCombat() then return false end
    btn:ClearAllPoints()
    if slotButton then btn:SetPoint("CENTER", slotButton, "CENTER", 0, 0)
    else btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 200) end
    return true
end
