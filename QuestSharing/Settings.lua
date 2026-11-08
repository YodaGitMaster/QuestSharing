-- Settings.lua: the settings window.   /qs settings   (also: the minimap button, the "Settings" link on the Party quests
-- window, and an entry under Game Menu > Options > AddOns)
--
-- Six tabs, each about one thing you do: General (getting started), Sharing (when you group up), Party window, Tracker
-- (finding your quests), Quick chat (the ring and its messages), Social. Every line is one click: a check box switches,
-- a choice moves to the next value (right click goes back), a number counts up (left click) or down (right click, Shift
-- = bigger steps). The grey line under each setting says what it does. The Quick chat tab also holds the message editor.
local ADDON, ns = ...
local C = ns.compat
local S = ns.style

local ON, OFF = "|cff55ff55[ON] |r", "|cffff5555[OFF]|r"

ns.settingTabs = {
    { id = "general", title = "General",      intro = "Start here: set your quick chat key, check that everything works." },
    { id = "sharing", title = "Sharing",      intro = "What happens when you group up, and what a click on a quest does." },
    { id = "party",   title = "Party",        intro = "The Party quests window, and what a click on a quest posts." },
    { id = "tracker", title = "Tracker",      intro = "Keep the quests near you in sight, and find the creatures you need." },
    { id = "quick",   title = "Quick chat",   intro = "Hold your key, point at a message, let go. Pick a message below to edit it." },
    { id = "social",  title = "Social",       intro = "Keep in touch with the people you quest with." },
}

-- kind = header | bool | choice | number | action | key.   desc = the grey line under the label (also its tooltip)
ns.settingRows = {
    -- General
    { tab = "general", kind = "header", label = "Getting started" },
    { tab = "general", kind = "key", label = "Quick chat key",
      desc = "Click, then press the key you want (Esc cancels). Hold it in game to open the ring of messages." },
    { tab = "general", kind = "action", label = "Show the ring", button = "Show",
      desc = "See your quick chat messages the way they look in play.", action = function() ns.quickOpen(true) end },
    { tab = "general", kind = "action", label = "Check my setup", button = "Check",
      desc = "A short report: what works on this game client, and what to switch on.", action = function() ns.doctor() end },
    { tab = "general", kind = "header", label = "Basics" },
    { tab = "general", kind = "bool", key = "enabled", label = "Quest Sharing enabled", desc = "The master switch for everything below." },
    { tab = "general", kind = "bool", key = "minimap", label = "Minimap button",
      desc = "Left click: this window. Right click: the Party quests window. Drag it around the map." },
    { tab = "general", kind = "bool", key = "sound", label = "A soft sound for good news",
      desc = "When someone accepts a quest you shared, or a party member finishes one you share. Never in combat." },
    { tab = "general", kind = "action", label = "Reset everything to the defaults", button = "Reset",
      desc = "Every setting and your quick chat messages.", action = function() ns.resetSettings() end },
    -- Sharing
    { tab = "sharing", kind = "header", label = "When I join a party" },
    { tab = "sharing", kind = "bool", key = "auto", label = "Share my quests when I join a party or someone joins",
      desc = "Once per member, never repeated, never again to someone who declined." },
    { tab = "sharing", kind = "choice", key = "area", label = "Which quests to share", values = { "zone", "all" },
      names = { zone = "this zone only", all = "all my quests" } },
    { tab = "sharing", kind = "number", key = "gap", label = "Seconds between shared quests", min = 2, max = 30,
      desc = "So nobody gets a pile of popups at once." },
    { tab = "sharing", kind = "bool", key = "shareNew", label = "Share a quest when I accept it (in a party)",
      desc = "Offers just the new quest, once." },
    { tab = "sharing", kind = "header", label = "Party chat" },
    { tab = "sharing", kind = "bool", key = "chat", label = "Announce quests in common in party chat",
      desc = "\"Hey! Looks like we have these quests in common...\"" },
    { tab = "sharing", kind = "bool", key = "announce", label = "Announce when a quest we share is done",
      desc = "Once for the whole party, even when you finish together." },
    { tab = "sharing", kind = "bool", key = "pickup", label = "Say when I pick up a quest someone in the party has",
      desc = "\"Picked up [quest] - Anna has it too. Want to do it together?\" Once per quest, never for shared ones." },
    { tab = "sharing", kind = "bool", key = "coords", label = "Tell where I found the quest items",
      desc = "Map coordinates in my done / progress message, only when someone in the party still needs them." },
    { tab = "sharing", kind = "header", label = "Behind the scenes" },
    { tab = "sharing", kind = "bool", key = "sync", label = "Sync quest lists with other Quest Sharing users",
      desc = "Exact \"who has what\" and progress for party members who also run the addon." },
    { tab = "sharing", kind = "bool", key = "markers", label = "Mark shared quests in the quest log", desc = "A star and the names." },
    -- Party
    { tab = "party", kind = "header", label = "The Party quests window" },
    { tab = "party", kind = "bool", key = "panel", label = "Show the \"quests in common\" panel while in a party",
      desc = "Class icons of who has each quest, and your own progress. Click a row to post your progress." },
    { tab = "party", kind = "bool", key = "panelCombat", label = "Hide it during combat", desc = "It comes back when the fight is over." },
    { tab = "party", kind = "number", key = "panelScale", label = "Size (%)", min = 70, max = 150, step = 10 },
    { tab = "party", kind = "action", label = "Put it back where it started", button = "Move back",
      desc = "If you dragged it somewhere you cannot find it.", action = function() if ns.resetPanelPosition then ns.resetPanelPosition() end end },
    { tab = "party", kind = "header", label = "Clicking a quest" },
    { tab = "party", kind = "bool", key = "click", label = "Click a tracked quest to write its status in chat",
      desc = "In the game's tracker or the Party quests window. Click more quests to add them to the same message." },
    { tab = "party", kind = "choice", key = "mode", label = "Clicking a quest...", values = { "box", "send", "print" },
      names = { box = "fills the chat box (press Enter)", send = "sends it at once", print = "shows it only to me" } },
    { tab = "party", kind = "bool", key = "link", label = "Shift-click quest links add the status" },
    -- Tracker
    { tab = "tracker", kind = "header", label = "The quest list on the right" },
    { tab = "tracker", kind = "bool", key = "near", label = "Tracker follows me (shows the nearest quests)",
      desc = "Fills the quest tracker with the quests closest to you. Switching it off puts your old list back." },
    { tab = "tracker", kind = "number", key = "nearCount", label = "Quests the tracker keeps", min = 1, max = function() return C.maxWatch() end },
    { tab = "tracker", kind = "choice", key = "nearMode", label = "Tracker mode", values = { "auto", "distance", "zone" },
      names = { auto = "automatic", distance = "by distance", zone = "by zone" } },
    { tab = "tracker", kind = "number", key = "nearPause", label = "Seconds it waits after I change the tracker myself", min = 5, max = 300,
      desc = "When you add or remove a tracked quest by hand, the tracker and the pin leave your choice alone for this long." },
    { tab = "tracker", kind = "header", label = "Finding objectives" },
    { tab = "tracker", kind = "bool", key = "nearPin", label = "Pin the nearest quest in the world",
      desc = "The game's own quest marker follows the closest quest as you move." },
    { tab = "tracker", kind = "bool", key = "markMobs", label = "Quest icon above creatures that are part of my quests",
      desc = "On their nameplates. Needs enemy nameplates switched on in the game." },
    { tab = "tracker", kind = "bool", key = "highlightCVars", label = "Switch on the game settings the highlights need",
      desc = "Enemy nameplates and icons over objects. Switching this off puts your own values back." },
    -- Quick chat
    { tab = "quick", kind = "bool", key = "quick", label = "Quick chat ring (hold a key, point, release or click)" },
    { tab = "quick", kind = "key", label = "Key that opens the ring", desc = "Click, then press a key (Esc cancels)." },
    { tab = "quick", kind = "choice", key = "quickMode", label = "The quick chat key", values = { "hold", "toggle" },
      names = { hold = "hold, point, release", toggle = "press to open, click a message" } },
    { tab = "quick", kind = "choice", key = "quickSize", label = "Ring size", values = { "small", "normal", "large" },
      names = { small = "small", normal = "normal", large = "large" } },
    { tab = "quick", kind = "choice", key = "quickChannel", label = "Auto messages go to", values = { "auto", "say", "party", "whisper" },
      names = { auto = "the party if I am in one, else my target (whisper), else nearby", say = "everybody nearby", party = "the party only", whisper = "the player I target" } },
    -- Social
    { tab = "social", kind = "bool", key = "friends", label = "(beta) Add people I group with to my friends list",
      desc = "Automatic. Skips friends, ignored players and random-dungeon groups." },
    { tab = "social", kind = "action", label = "Add my party to my friends now", button = "Add",
      desc = "Once, for the party you are in (the same as /qs friends).", action = function() ns.addPartyFriends(true) end },
}

local function limit(v) if type(v) == "function" then return v() end return v end

local function keyName() return ns.quickKeyName and ns.quickKeyName() end

-- a one-line text version of a row (used by the tests and anywhere a plain line is enough)
function ns.rowText(row)
    local d = ns.db
    if row.kind == "bool" then
        return (d[row.key] and ON or OFF) .. " " .. row.label
    elseif row.kind == "choice" then
        local v = d[row.key]
        return row.label .. ": |cff55ccff" .. ((row.names and row.names[v]) or tostring(v)) .. "|r"
    elseif row.kind == "number" then
        return string.format("%s: |cff55ccff%d|r", row.label, d[row.key] or 0)
    elseif row.kind == "key" then
        return row.label .. ": |cff55ccff" .. (keyName() or "not set") .. "|r"
    end
    return "|cffffd100" .. row.label .. "|r"
end

-- What a click on row i (an index into ns.settingRows) does. Used by the window and by the tests.
function ns.settingsClick(i, button)
    local row = ns.settingRows[i]
    if not row then return end
    local d = ns.db
    local back = (button == "RightButton")
    if row.kind == "bool" then
        ns.setSetting(row.key, not d[row.key])
    elseif row.kind == "choice" then
        local idx = 1
        for j, v in ipairs(row.values) do if v == d[row.key] then idx = j end end
        idx = back and (idx - 2) % #row.values + 1 or idx % #row.values + 1
        ns.setSetting(row.key, row.values[idx])
    elseif row.kind == "number" then
        local base = row.step or 1
        local step = (IsShiftKeyDown and IsShiftKeyDown()) and base * 5 or base
        local v = (d[row.key] or 0) + (back and -step or step)
        ns.setSetting(row.key, math.max(row.min, math.min(limit(row.max), v)))
    elseif row.kind == "action" then
        row.action()
    elseif row.kind == "key" then
        ns.captureKey()
    end
    if ns.refreshSettings then ns.refreshSettings() end
end

local function rowsOf(tab)
    local out = {}
    for i, row in ipairs(ns.settingRows) do if row.tab == tab then out[#out + 1] = i end end
    return out
end

-- The window -----------------------------------------------------------------------------------------------------
local W = { win = nil, tab = "general", rows = {}, tabs = {}, ed = { selected = nil }, capturing = false }
local WIDTH, HEIGHT, LEFT = 660, 600, 24
local TOP = 98                     -- where the first row starts (below the title, the tabs and the intro line)
local ROW_H, HEADER_H, DESC_H = 22, 24, 12
local MAX_ROWS = 18

local function shorten(s, n) if #s <= n then return s end return string.sub(s, 1, n - 3) .. "..." end

local function clickable(parent, w, h, onClick)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(w)
    f:SetHeight(h)
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", onClick)
    return f
end

-- Press-a-key capture for the quick chat key ------------------------------------------------------------------------
local capture
local MODIFIER = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true }

local function stopCapture()
    W.capturing = false
    if capture then capture:EnableKeyboard(false); capture:Hide() end
end

function ns.captureKey()
    if InCombatLockdown and InCombatLockdown() then return ns.print("key bindings cannot be changed in combat") end
    if not capture then
        local ok, f = pcall(CreateFrame, "Frame", "QuestSharingKeyCapture", UIParent)
        if not (ok and f) then return ns.print("this client does not allow it: use /qs key E") end
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetScript("OnKeyDown", function(_, key) ns.captureKeyPressed(key) end)
        f:Hide()
        capture = f
    end
    W.capturing = true
    capture:Show()
    capture:EnableKeyboard(true)
    if capture.SetPropagateKeyboardInput then pcall(capture.SetPropagateKeyboardInput, capture, false) end
    if ns.refreshSettings then ns.refreshSettings() end
end

function ns.captureKeyPressed(key)
    if not W.capturing or MODIFIER[key] then return end      -- wait for the real key after Shift / Ctrl / Alt
    stopCapture()
    if key ~= "ESCAPE" then
        local prefix = ((IsAltKeyDown and IsAltKeyDown()) and "ALT-" or "") .. ((IsControlKeyDown and IsControlKeyDown()) and "CTRL-" or "")
                    .. ((IsShiftKeyDown and IsShiftKeyDown()) and "SHIFT-" or "")
        ns.setQuickKey(prefix .. key)
    end
    ns.refreshSettings()
end

-- the message editor (inside the Quick chat tab) -------------------------------------------------------------------
local ed = W.ed

function ns.editorRefresh()
    if not ed.frame then return end
    local list = ns.quickItems()
    for i = 1, 8 do
        local line = ed.lines[i]
        if list[i] then
            local hot = (ed.selected == i)
            line.text:SetText(string.format("%s%d.  [%s]  %s%s|r", hot and "|cffffd100" or "|cffffffff", i, list[i].label,
                shorten(list[i].text, 50), "  |cff88ccff" .. (ns.QUICK_ROUTE_TAG[list[i].channel or "auto"] or "auto") .. "|r"))
            if hot then line.mark:Show() else line.mark:Hide() end
            line.frame:Show()
        else
            line.frame:Hide()
        end
    end
    local item = ed.selected and list[ed.selected]
    ed.labelBox:SetText(item and item.label or "")
    ed.textBox:SetText(item and item.text or "")
    local route = item and (item.channel or "auto")
    ed.routeText:SetText(item and ("Goes to: |cffffd100" .. ns.QUICK_ROUTE_INFO[route] .. "|r") or "")
    for _, c in ipairs(ed.routeButtons) do
        if item then
            local hot = (c.route == route)
            c.text:SetText((hot and "|cffffd100[" or "|cff55ccff ") .. c.title .. (hot and "]|r" or " |r"))
            c.frame:Show()
        else
            c.frame:Hide()
        end
    end
    if item then ed.channelCaption:Show() else ed.channelCaption:Hide() end
    ed.preview:SetText(item and ("|cff888888Looks like:|r " .. shorten(ns.quickResolve(item.text), 110)) or "|cff888888Click a message above to edit it.|r")
end

function ns.editorSelect(i) ed.selected = (ns.quickItems()[i] and i) or nil; ns.editorRefresh() end
function ns.editorMove(delta)
    if ed.selected and ns.quickMove(ed.selected, ed.selected + delta) then ed.selected = ed.selected + delta end
    ns.editorRefresh()
end
function ns.editorDelete()
    if ed.selected and ns.quickRemove(ed.selected) then ed.selected = nil end
    ns.editorRefresh()
end
function ns.editorAdd()
    local n = ns.quickAdd("New message", "New")
    if n then ed.selected = n end
    ns.editorRefresh()
end
function ns.editorSave(label, text)
    if ed.selected then
        ns.quickEdit(ed.selected, text)
        if label and label ~= "" then ns.quickLabel(ed.selected, label) end
    end
    ns.editorRefresh()
end
-- choose the channel of the selected message (no argument: the next one in the list)
function ns.editorRoute(route)
    local item = ed.selected and ns.quickItems()[ed.selected]
    if item then
        if not route then
            local cur, list = item.channel or "auto", ns.QUICK_ROUTES
            for k, r in ipairs(list) do if r == cur then route = list[k % #list + 1] end end
            route = route or "auto"
        end
        ns.quickRoute(ed.selected, route)
    end
    ns.editorRefresh()
end
function ns.editorReset() ns.quickReset(); ed.selected = nil; ns.editorRefresh() end

local function buildEditor(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(WIDTH - 2 * LEFT)
    f:SetHeight(300)
    ed.frame, ed.lines = f, {}
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    title:SetText("Messages on the ring (up to 8, clockwise from the top)")
    for i = 1, 8 do
        local line = clickable(f, WIDTH - 2 * LEFT, 18, function() ns.editorSelect(i) end)
        line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -20 - (i - 1) * 18)
        local mark = S.fill(line, "BACKGROUND", 1, 0.82, 0, 0.12)            -- the selected message is lit
        mark:SetAllPoints(line)
        mark:Hide()
        local hover = S.fill(line, "BACKGROUND", 1, 1, 1, 0.05)
        hover:SetAllPoints(line)
        hover:Hide()
        line:SetScript("OnEnter", function() hover:Show() end)
        line:SetScript("OnLeave", function() hover:Hide() end)
        local t = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        t:SetPoint("LEFT", line, "LEFT", 4, 0)
        ed.lines[i] = { frame = line, text = t, mark = mark }
    end
    local cap1 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cap1:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -172)
    cap1:SetText("Label (on the ring, 14 letters)")
    local cap2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cap2:SetPoint("TOPLEFT", f, "TOPLEFT", 170, -172)
    cap2:SetText("Message (Enter saves) - {name} {here} {need} {mine} {common} {shared} {quest} {zone}, or start with @invite")
    local function box(width, x, max)
        local b = CreateFrame("EditBox", nil, f)
        b:SetWidth(width)
        b:SetHeight(20)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -186)
        local bg = S.fill(b, "BACKGROUND", 0, 0, 0, 0.6)
        bg:SetAllPoints(b)
        if ChatFontNormal then b:SetFontObject(ChatFontNormal) end
        b:SetAutoFocus(false)
        b:SetMaxLetters(max)
        if b.SetTextInsets then b:SetTextInsets(4, 4, 0, 0) end
        b:SetScript("OnEnterPressed", function() ns.editorSave(ed.labelBox:GetText(), ed.textBox:GetText()); b:ClearFocus() end)
        b:SetScript("OnEscapePressed", function() b:ClearFocus() end)
        return b
    end
    ed.labelBox, ed.textBox = box(150, 0, 14), box(WIDTH - 2 * LEFT - 170, 170, 200)
    ed.preview = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ed.preview:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -212)
    local x = 0
    ed.buttons = {}
    for _, b in ipairs({
        { "Up", function() ns.editorMove(-1) end }, { "Down", function() ns.editorMove(1) end },
        { "Remove", function() ns.editorDelete() end }, { "Add", function() ns.editorAdd() end },
        { "Reset", function() ns.editorReset() end }, { "Show the ring", function() ns.quickOpen(true) end },
    }) do
        local w = (b[1] == "Show the ring") and 110 or 70
        local btn = S.button(f, b[1], w, b[2])
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, -232)
        ed.buttons[b[1]] = btn
        x = x + w + 6
    end
    -- the channel of the selected message: one click on a choice
    ed.channelCaption = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ed.channelCaption:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -262)
    ed.channelCaption:SetText("Channel:")
    ed.routeButtons = {}
    local TITLES = { auto = "Auto", nearby = "Nearby", say = "/s Say", yell = "/y Yell", party = "/p Party", whisper = "/w Whisper" }
    local rx = 56
    for _, r in ipairs(ns.QUICK_ROUTES) do
        local btn = clickable(f, 80, 16, function() ns.editorRoute(r) end)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", rx, -260)
        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("LEFT", btn, "LEFT", 0, 0)
        ed.routeButtons[#ed.routeButtons + 1] = { route = r, title = TITLES[r], frame = btn, text = t }
        rx = rx + 84
    end
    ed.routeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ed.routeText:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -280)
    return f
end

-- tabs and rows ---------------------------------------------------------------------------------------------------------
local function paintRow(r, row)
    local d = ns.db
    r.box:Hide(); r.tick:Hide(); r.value:SetText(""); r.button:Hide(); r.line:Hide()
    r.text:ClearAllPoints()
    r.desc:SetText(row.desc and (S.GREY .. row.desc .. "|r") or "")
    if row.kind == "header" then
        r.text:SetPoint("BOTTOMLEFT", r.frame, "BOTTOMLEFT", 0, 6)
        r.text:SetText(S.GOLD .. row.label .. "|r")
        r.line:Show()
        return HEADER_H
    end
    r.text:SetPoint("TOPLEFT", r.frame, "TOPLEFT", 30, -4)
    r.text:SetText(row.label)
    if row.kind == "bool" then
        r.box:Show()
        if d[row.key] then r.tick:Show() end
        if d.enabled == false and row.key ~= "enabled" then r.text:SetText(S.GREY .. row.label .. "|r") end   -- greyed: master switch off
    elseif row.kind == "choice" then
        r.value:SetText(S.BLUE .. "< " .. ((row.names and row.names[d[row.key]]) or tostring(d[row.key])) .. " >|r")
    elseif row.kind == "number" then
        r.value:SetText(S.BLUE .. "-  " .. tostring(d[row.key] or 0) .. "  +|r")
    elseif row.kind == "key" then
        r.button:SetLabel(W.capturing and (S.GOLD .. "press a key...|r") or (keyName() or (S.RED .. "not set|r")))
        r.button:Show()
    elseif row.kind == "action" then
        r.button:SetLabel(row.button or "Do it")
        r.button:Show()
    end
    return ROW_H + (row.desc and DESC_H or 0)
end

function ns.refreshSettings()
    if not W.win then return end
    local list = rowsOf(W.tab)
    local y = TOP
    for n = 1, MAX_ROWS do
        local r = W.rows[n]
        local idx = list[n]
        if idx then
            r.index = idx
            local h = paintRow(r, ns.settingRows[idx])
            r.frame:ClearAllPoints()
            r.frame:SetPoint("TOPLEFT", W.win, "TOPLEFT", LEFT, -y)
            r.frame:SetHeight(h)
            r.frame:Show()
            y = y + h + 2
        else
            r.index = nil
            r.frame:Hide()
        end
    end
    for _, t in ipairs(ns.settingTabs) do
        local tab = W.tabs[t.id]
        local open = (t.id == W.tab)
        tab.text:SetText((open and "|cffffd100" or "|cff55ccff") .. t.title .. "|r")
        if open then tab.under:Show(); tab.bg:SetVertexColor(1.6, 1.6, 1.6) else tab.under:Hide(); tab.bg:SetVertexColor(1, 1, 1) end
        if open then W.intro:SetText(S.GREY .. t.intro .. "|r") end
    end
    if W.tab == "quick" then
        ed.frame:ClearAllPoints()
        ed.frame:SetPoint("TOPLEFT", W.win, "TOPLEFT", LEFT, -(y + 10))
        ed.frame:Show()
        ns.editorRefresh()
    else
        ed.frame:Hide()
    end
    W.bottom = y
end

function ns.settingsTab(id)
    for _, t in ipairs(ns.settingTabs) do if t.id == id then W.tab = id end end
    if W.capturing then stopCapture() end
    ns.refreshSettings()
end

local function tooltip(owner, text)
    if not (text and GameTooltip) then return end
    pcall(function()
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
end

local function buildRow(f, n)
    local r = {}
    local frame = clickable(f, WIDTH - 2 * LEFT, ROW_H, nil)
    r.frame = frame
    r.hover = S.fill(frame, "BACKGROUND", 1, 1, 1, 0.06)
    r.hover:SetAllPoints(frame)
    r.hover:Hide()
    r.box, r.tick = S.checkBox(frame)
    r.box:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 1)
    r.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetJustifyH("LEFT")
    r.desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.desc:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -19)
    r.desc:SetJustifyH("LEFT")
    r.desc:SetWidth(WIDTH - 2 * LEFT - 150)
    r.value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.value:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -4)
    r.value:SetJustifyH("RIGHT")
    r.line = S.fill(frame, "ARTWORK", 1, 0.82, 0, 0.35)                  -- the thin gold line under a section title
    r.line:SetHeight(1)
    r.line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 2)
    r.line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 2)
    r.button = S.button(frame, "", 120, function(_, which) if r.index then ns.settingsClick(r.index, which) end end)
    r.button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -1)
    frame:SetScript("OnMouseUp", function(_, button)
        local row = r.index and ns.settingRows[r.index]
        if row and row.kind ~= "header" and row.kind ~= "action" and row.kind ~= "key" then ns.settingsClick(r.index, button) end
    end)
    frame:SetScript("OnEnter", function(self)
        local row = r.index and ns.settingRows[r.index]
        if not row or row.kind == "header" then return end
        r.hover:Show()
        local tip = row.desc
        if row.kind == "choice" then tip = (tip and (tip .. "\n") or "") .. "Click: next choice. Right click: back."
        elseif row.kind == "number" then tip = (tip and (tip .. "\n") or "") .. "Click: more. Right click: less. Shift: bigger steps." end
        tooltip(self, tip)
    end)
    frame:SetScript("OnLeave", function()
        r.hover:Hide()
        if GameTooltip then pcall(function() GameTooltip:Hide() end) end
    end)
    W.rows[n] = r
end

local function build()
    if W.win then return W.win end
    if not (CreateFrame and UIParent) then return nil end
    local f = S.window("QuestSharingSettings", WIDTH, HEIGHT, "Quest Sharing", "dialog")
    if not f then return nil end
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    W.win = f
    local version = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, -22)
    version:SetText(S.GREY .. "version " .. tostring(ns.version or "?") .. "|r")
    W.close = S.closeButton(f, function() f:Hide() end, -6, -6)

    local x = LEFT
    for _, t in ipairs(ns.settingTabs) do
        local width = (t.id == "party" or t.id == "quick") and 112 or 92
        local b = clickable(f, width, 24, function() ns.settingsTab(t.id) end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -42)
        local bg = S.fill(b, "BACKGROUND", 0.12, 0.14, 0.2, 0.9)
        bg:SetAllPoints(b)
        local under = S.fill(b, "ARTWORK", 1, 0.82, 0, 0.9)
        under:SetHeight(2)
        under:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
        under:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
        local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER", b, "CENTER", 0, 0)
        W.tabs[t.id] = { frame = b, text = text, under = under, bg = bg }
        x = x + width + 4
    end
    W.intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    W.intro:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, -76)

    for n = 1, MAX_ROWS do buildRow(f, n) end
    buildEditor(f)
    local foot = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LEFT, 16)
    foot:SetText(S.GREY .. "Type /qs for all commands.  /qs doctor checks your setup.  /qs errors shows problems.|r")
    f:SetScript("OnHide", function() if W.capturing then stopCapture() end end)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestSharingSettings") end       -- Esc closes it
    f:Hide()
    return f
end

function ns.toggleSettings(show, tab)
    local f = build()
    if not f then return ns.print("this client does not allow the settings window (frame creation failed)") end
    if show == nil then show = not f:IsShown() end
    if tab then ns.settingsTab(tab) end
    if show then ns.refreshSettings(); f:Show() else f:Hide() end
end

function ns._settingsWindow() return W end              -- for the tests

-- An entry in the game's own options (Game Menu > Options > AddOns) that opens this window ---------------------
local function registerOptionsEntry()
    if ns.hooks and ns.hooks.optionsEntry then return end
    local ok, f = pcall(CreateFrame, "Frame", "QuestSharingOptionsEntry", UIParent)
    if not (ok and f) then return end
    f.name = "Quest Sharing"
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    text:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    text:SetText("Quest Sharing")
    local open = S.button(f, "Open the Quest Sharing settings", 240, function() ns.toggleSettings(true) end)
    open:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -44)
    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -72)
    hint:SetText("or type /qs settings, or left-click the minimap button")
    ns.hooks = ns.hooks or {}
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local good, category = pcall(Settings.RegisterCanvasLayoutCategory, f, "Quest Sharing")
        if good and category then
            Settings.RegisterAddOnCategory(category)
            ns.hooks.optionsEntry = true
        end
    elseif InterfaceOptions_AddCategory then
        ns.hooks.optionsEntry = pcall(InterfaceOptions_AddCategory, f)
    end
end

ns.on("PLAYER_LOGIN", registerOptionsEntry)
ns.on("PLAYER_ENTERING_WORLD", registerOptionsEntry)
