-- LFGFinderUI.lua: the small picker the minimap spyglass opens.
--   Three columns (Healer, Tank, Damage): tick a role, untick the classes you do not want for it (healer: only
--   Paladin and Priest, damage: only Rogue and Warrior ...). Lowest item level -/+ . Find = one search of your
--   party finder listing and the invites (the game needs this click for every search).
local ADDON, ns = ...
local S = ns.style

local F = {}
ns.lfgFinder = F

local W                                         -- the window, built on first open
local COL_W, ROW_H, TOP = 118, 20, -62
local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local ROLES = { { key = "healer", setting = "lfgHealer", title = "Healer" },
                { key = "tank", setting = "lfgTank", title = "Tank" },
                { key = "dps", setting = "lfgDps", title = "Damage" } }
local CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
                      SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }

local function className(c)
    local loc = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[c]
    return loc or CLASS_NAMES[c] or c
end

-- a thin gold rule across the window
local function rule(f, y)
    local t = S.fill(f, "ARTWORK", 1, 0.82, 0, 0.35)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
    t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, y)
    t:SetHeight(1)
    return t
end

-- a check box with a label: refresh() reads the state, click runs onClick; class: a small class icon before the name
local function check(parent, x, y, width, small, onClick, class)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(width)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b.box, b.tick = S.checkBox(b)
    local size = small and 18 or 22
    b.box:SetWidth(size); b.box:SetHeight(size); b.tick:SetWidth(size); b.tick:SetHeight(size)
    b.box:SetPoint("LEFT", b, "LEFT", 0, 0)
    local textX = size + 2
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetTexture(CLASS_ICONS)
        b.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        b.icon:SetWidth(14); b.icon:SetHeight(14)
        b.icon:SetPoint("LEFT", b, "LEFT", textX, 0)
        textX = textX + 17
    end
    b.label = b:CreateFontString(nil, "OVERLAY", small and "GameFontHighlightSmall" or "GameFontNormal")
    b.label:SetPoint("LEFT", b, "LEFT", textX, 0)
    b.label:SetJustifyH("LEFT")
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() onClick(); F.refresh() end)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    return b
end

local function build()
    if W then return W end
    local L = ns.lfgInvite
    local f = S.window("QuestSharingFinder", COL_W * 3 + 24, 330, "Party finder", "hud")
    if not f then return nil end
    f:SetFrameStrata("DIALOG")
    if Minimap then f:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", -8, -8) else f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
    S.closeButton(f, function() f:Hide() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestSharingFinder") end       -- Esc closes it
    W = { win = f, roles = {}, classes = {} }

    W.listing = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.listing:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
    W.listing:SetWidth(COL_W * 3)
    W.listing:SetJustifyH("LEFT")
    if W.listing.SetWordWrap then W.listing:SetWordWrap(true) end
    rule(f, TOP + 6)

    local deepest = 0
    for i, r in ipairs(ROLES) do
        local x = 12 + (i - 1) * COL_W
        W.roles[r.key] = check(f, x, TOP, COL_W - 4, false, function() ns.setSetting(r.setting, not ns.db[r.setting]) end)
        W.roles[r.key].role = r
        W.classes[r.key] = {}
        for j, c in ipairs(L.ROLE_CLASSES[r.key]) do
            local b = check(f, x + 10, TOP - j * ROW_H - 2, COL_W - 14, true, function()
                L.setClass(r.key, c, not L.classAllowed(r.key, c))
            end, c)
            b.class = c
            W.classes[r.key][#W.classes[r.key] + 1] = b
        end
        deepest = math.max(deepest, #L.ROLE_CLASSES[r.key])
    end
    local y = TOP - (deepest + 1) * ROW_H - 10
    rule(f, y + 4)

    -- lowest item level: - value +
    W.ilvl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    W.ilvl:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y - 4)
    W.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.info:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y - 20)
    W.info:SetWidth(COL_W * 3)
    W.info:SetJustifyH("LEFT")
    local function step(delta)
        local v = (tonumber(ns.db.lfgMinIlvl) or 0) + delta * ((IsShiftKeyDown and IsShiftKeyDown()) and 5 or 1)
        ns.setSetting("lfgMinIlvl", math.max(0, math.min(300, v)))
        F.refresh()
    end
    W.minus = S.button(f, "-", 24, function() step(-1) end, "Lower (Shift: by 5)")
    W.minus:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, y)
    W.plus = S.button(f, "+", 24, function() step(1) end, "Higher (Shift: by 5)")
    W.plus:SetPoint("LEFT", W.minus, "RIGHT", 4, 0)
    y = y - 40

    W.super = check(f, 12, y, COL_W * 3 - 10, true, function() ns.setSetting("lfgSupercharge", not ns.db.lfgSupercharge) end)
    W.super:SetScript("OnEnter", function(self)
        if GameTooltip then pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Supercharge", 1, 0.82, 0)
            GameTooltip:AddLine("Off: per role only what is still open (1 healer, 1 tank, 3 damage), highest level first.", 1, 1, 1, true)
            GameTooltip:AddLine("On: fills every free spot at once with players who fit (the game counts open invites as spots). The first to accept gets the spot; extra players who accept may need to be removed.", 1, 1, 1, true)
            GameTooltip:Show()
        end) end
    end)
    W.super:SetScript("OnLeave", function() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end)
    y = y - 22
    W.whisper = check(f, 12, y, COL_W * 3 - 10, true, function() ns.setSetting("lfgWhisper", not ns.db.lfgWhisper) end)
    y = y - 24

    W.find = S.button(f, "Find", 130, function() L.scan(); F.refresh() end,
        "Search your listing's dungeon and invite players for the open roles (1 healer, 1 tank, 3 damage), highest level first - or every match with Supercharge. Click again to search again.")
    W.find:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
    W.more = S.button(f, "Settings", 90, function() ns.toggleSettings(true, "finder") end, "Party finder settings: level range, unknown item level, whisper text and more")
    W.more:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, y)
    y = y - 26

    W.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.status:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
    W.status:SetWidth(COL_W * 3)
    W.status:SetJustifyH("LEFT")
    if W.status.SetWordWrap then W.status:SetWordWrap(true) end
    W.status:SetHeight(28)
    f:SetHeight(-y + 40)
    f:Hide()
    return W
end

function F.refresh()
    if not W then return end
    local L, d = ns.lfgInvite, ns.db
    local listing = L.listing()
    W.listing:SetText(listing and ("Listed for: " .. S.GREEN .. listing.name .. "|r")
        or (S.RED .. "Not listed.|r List your group in the party finder with a dungeon first."))
    for _, r in ipairs(ROLES) do
        local on = d[r.setting] and true or false
        local b = W.roles[r.key]
        b.label:SetText((on and S.GOLD or S.GREY) .. r.title .. "|r")
        if on then b.tick:Show() else b.tick:Hide() end
        for _, cb in ipairs(W.classes[r.key]) do
            local allowed = L.classAllowed(r.key, cb.class)
            cb.label:SetText(((on and allowed) and S.classHex(cb.class) or S.GREY) .. className(cb.class) .. "|r")
            if allowed then cb.tick:Show() else cb.tick:Hide() end
        end
    end
    local need = tonumber(d.lfgMinIlvl) or 0
    W.ilvl:SetText("Lowest item level: " .. S.WHITE .. (need > 0 and tostring(need) or "any") .. "|r")
    W.super.label:SetText((d.lfgSupercharge and (S.GOLD .. "Supercharge: invite every match at once") or (S.GREY .. "Supercharge: invite every match at once (off: only what each role needs)")) .. "|r")
    if d.lfgSupercharge then W.super.tick:Show() else W.super.tick:Hide() end
    W.whisper.label:SetText((d.lfgWhisper and S.GOLD or S.GREY) .. "Whisper them which dungeon the invite is for|r")
    if d.lfgWhisper then W.whisper.tick:Show() else W.whisper.tick:Hide() end
    local spots = L.freeSpots()
    local open = d.lfgSupercharge and "every match" or string.format("open: %d healer, %d tank, %d damage",
        L.roleOpen("healer"), L.roleOpen("tank"), L.roleOpen("damage"))
    W.info:SetText(string.format("%sLevels %d-%d, highest first. %d free spot%s, %s.|r", S.GREY, d.lfgMinLevel or 1,
        d.lfgMaxLevel or 60, spots, spots == 1 and "" or "s", open))
    -- Find stays clickable (it says why it cannot search), but looks off while something is missing
    local blocker = L.blocker()
    W.find:SetLabel(blocker and (S.GREY .. "Find|r") or "Find")
    W.find.blocked = blocker
    -- the status keeps the last thing that happened (an invite, "searching ...") with the blocker under it
    local last = W.lastAction
    if blocker then W.status:SetText((last and (last .. "\n") or "") .. S.RED .. blocker .. "|r")
    else W.status:SetText(last or "Ready: click Find.") end
end

function F.status(text)
    if not W then return end
    W.lastAction = text
    F.refresh()
end

-- keep the picker true while it is open: the party, the listing or a setting changed
local function live() if W and W.win:IsShown() then F.refresh() end end
ns.on("GROUP_ROSTER_UPDATE", live)
ns.on("PARTY_LEADER_CHANGED", live)
ns.on("LFG_LIST_ACTIVE_ENTRY_UPDATE", live)

function F.toggle(show)
    local w = build()
    if not w then return ns.print("party finder: this client does not allow the window") end
    if show == nil then show = not w.win:IsShown() end
    if show then F.refresh(); w.win:Show() else w.win:Hide() end
end

function F._window() return W end                -- for the tests
