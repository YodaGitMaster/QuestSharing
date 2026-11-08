-- Ping.lua: one key (or a click on the ring) pings the nearest creature one of your quests needs with the game's
-- Attack ping, so the party sees what to kill; with no such creature in sight it pings the quest object you are facing
-- (the gear / hand icon) with the game's "look here" ping.
--
-- What the game allows, and so how this works:
--   * An addon can never ping, or pick a target, by itself: both only happen as the direct result of YOUR key press or
--     click. So the addon prepares a hidden secure button (outside combat it keeps loading "/targetexact <nearest quest
--     creature>" + "/ping [@target] attack" into it) and your key clicks that button.
--   * During combat secure buttons cannot be changed: it keeps the creature it loaded last.
--   * Anti-spam: a new ping only once the creature you pinged last is dead or no longer your target. A small secure
--     snippet checks that, so it also works during combat. Outside combat the ping also unlocks after the time chosen
--     in the settings (5 / 10 / 15 seconds). Shift + the key pings anyway.
--   * The game gives addons no distance to enemies: "nearest" is a quest creature within about 28 yards, the one
--     closest to the middle of your screen.
local ADDON, ns = ...
local C = ns.compat

local BUTTON = "QuestSharingPingButton"
local CLICK = "CLICK " .. BUTTON .. ":LeftButton"
local REFRESH = 1                 -- seconds between two looks for the nearest quest creature (outside combat)

-- the secure part: runs before the macro, in the game's restricted environment (no clock there: the time rule is kept
-- outside combat by the addon, which may change attributes then)
local GATE = [[
    if down then return end
    if self:GetAttribute("qs-gate") == 1 and not IsShiftKeyDown() then
        if self:GetAttribute("qs-kind") ~= "unit" then return false end
        if SecureCmdOptionParse("[@target,harm,nodead] alive; free") == "alive" then return false end
    end
    self:SetAttribute("qs-gate", 1)
    self:SetAttribute("qs-count", (self:GetAttribute("qs-count") or 0) + 1)
]]

local btn
local state = { count = 0, lastAt = -1000, macro = nil, kind = nil, name = nil, saidAt = -1000 }
ns.ping = state

function ns.pingSupported()
    if not (C_Ping and SecureHandlerWrapScript and SetBindingClick) then return false end
    if C_Ping.IsPingSystemEnabled then
        local ok, on = pcall(C_Ping.IsPingSystemEnabled)
        return ok and on and true or false
    end
    return true
end

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- The nearest quest creature: within ~28 yards if any, then the one closest to the middle of the screen ------------
local function unitOf(plate)
    return plate.namePlateUnitToken or plate.unitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

function ns.nearestQuestCreature()
    if not (C_NamePlate and C_NamePlate.GetNamePlates and C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest) then return nil end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not (ok and plates) then return nil end
    local cx, cy = 0, 0
    if UIParent then cx, cy = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2 end
    local best, bestScore
    for _, plate in ipairs(plates) do
        local unit = unitOf(plate)
        if unit then
            local okR, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
            local hostile = UnitCanAttack and UnitCanAttack("player", unit)
            local dead = UnitIsDead and UnitIsDead(unit)
            if okR and related == true and hostile and not dead then
                local name = UnitName(unit)
                if name then
                    local px, py = cx, cy
                    if plate.GetCenter then px, py = plate:GetCenter() end
                    local score = (px - cx) ^ 2 + (py - cy) ^ 2
                    local okD, close = pcall(CheckInteractDistance or function() return false end, unit, 4)
                    if okD and close then score = score - 1e9 end              -- within ~28 yards comes first
                    if not bestScore or score < bestScore then best, bestScore = name, score end
                end
            end
        end
    end
    return best
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

-- after every click (insecure: only looks and talks): did it ping, or did the anti-spam hold it back?
local function afterClick(self, _, down)
    if down then return end
    local count = self:GetAttribute("qs-count") or 0
    if count ~= state.count then
        state.count, state.lastAt = count, GetTime()
        local gap = ns.db.pingGap or 10
        ns.after(gap, function() if GetTime() - state.lastAt >= gap - 0.05 then resetGate() end end)
        if ns.quick and ns.quick.open and ns.quickClose then ns.quickClose() end
        ns.after(0.3, ns.pingRefresh)                          -- the next nearest one, once this press is over
    elseif GetTime() - state.saidAt > 5 then
        state.saidAt = GetTime()
        ns.print(string.format("ping held back: the one you pinged is still alive%s - hold Shift to ping anyway",
            inCombat() and "" or (" (or wait " .. (ns.db.pingGap or 10) .. " seconds)")))
    end
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
ns.on("PLAYER_REGEN_ENABLED", function() resetGate(); ns.pingRefresh() end)
ns.on("PLAYER_REGEN_DISABLED", function() ns.pingRefresh() end)            -- the last chance before combat locks it

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
