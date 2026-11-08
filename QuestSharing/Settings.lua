-- Settings.lua: the settings window.   /qs settings   (also: the minimap button, the "Settings" link on the quests-in-common
-- panel, and an entry under Game Menu > Options > AddOns)
--
-- Five tabs: General, Sharing, Tracker, Quick chat, Social. Every line is one click: on/off lines switch, choice lines cycle
-- (right click goes back), number lines count up (left click) or down (right click, Shift = 5 at a time). The Quick chat tab
-- also holds the editor for the messages on the ring: pick one, change its label and text, move it up or down, add, remove,
-- reset, and "Show the ring" to see it the way it looks in play.
-- It needs none of the game's UI templates: every control is a plain clickable frame, so it looks the same on every client.
local ADDON, ns = ...
local C = ns.compat

local ON, OFF = "|cff55ff55[ON] |r", "|cffff5555[OFF]|r"

ns.settingTabs = {
    { id = "general", title = "General" },
    { id = "sharing", title = "Sharing" },
    { id = "tracker", title = "Tracker" },
    { id = "quick",   title = "Quick chat" },
    { id = "social",  title = "Social" },
}

-- kind = bool | choice | number | action
ns.settingRows = {
    -- General
    { tab = "general", kind = "bool", key = "enabled", label = "Quest Sharing enabled", tip = "Master switch for the whole addon." },
    { tab = "general", kind = "bool", key = "minimap", label = "Minimap button (left click: settings, right click: panel)" },
    { tab = "general", kind = "bool", key = "panel", label = "Show the \"quests in common\" panel while in a party" },
    { tab = "general", kind = "bool", key = "verbose", label = "Show me who accepted / declined my shared quests" },
    { tab = "general", kind = "action", label = "Reset everything to the defaults", action = function() ns.resetSettings() end },
    -- Sharing
    { tab = "sharing", kind = "bool", key = "auto", label = "Share my quests when I join a party or someone joins",
      tip = "Once per member, never repeated, never to someone who declined." },
    { tab = "sharing", kind = "bool", key = "shareNew", label = "Share a quest when I accept it (in a party)",
      tip = "Offers just the new quest to the party, once." },
    { tab = "sharing", kind = "choice", key = "area", label = "Which quests to share", values = { "zone", "all" },
      names = { zone = "this zone only", all = "all my quests" } },
    { tab = "sharing", kind = "number", key = "gap", label = "Seconds between shared quests", min = 2, max = 30 },
    { tab = "sharing", kind = "bool", key = "chat", label = "Announce quests in common in party chat",
      tip = "\"Hey! Looks like we have these quests in common...\"" },
    { tab = "sharing", kind = "bool", key = "announce", label = "Announce when a quest we share is done" },
    { tab = "sharing", kind = "bool", key = "click", label = "Click a tracked quest to write its status in chat" },
    { tab = "sharing", kind = "bool", key = "link", label = "Shift-click quest links add the status" },
    { tab = "sharing", kind = "choice", key = "mode", label = "Clicking a quest...", values = { "box", "send", "print" },
      names = { box = "fills the chat box (press Enter)", send = "sends it at once", print = "shows it only to me" } },
    { tab = "sharing", kind = "bool", key = "sync", label = "Sync quest lists with other Quest Sharing users",
      tip = "Exact \"who has what\" for party members who also run the addon." },
    { tab = "sharing", kind = "bool", key = "markers", label = "Mark shared quests in the quest log" },
    -- Tracker
    { tab = "tracker", kind = "bool", key = "near", label = "Tracker follows me (shows the nearest quests)",
      tip = "Fills the quest tracker with the quests closest to you. Switching it off puts your old list back." },
    { tab = "tracker", kind = "number", key = "nearCount", label = "Quests the tracker keeps", min = 1, max = function() return C.maxWatch() end },
    { tab = "tracker", kind = "choice", key = "nearMode", label = "Tracker mode", values = { "auto", "distance", "zone" },
      names = { auto = "automatic", distance = "by distance", zone = "by zone" } },
    { tab = "tracker", kind = "number", key = "nearPause", label = "Seconds it waits after I change the tracker myself", min = 5, max = 300,
      tip = "When you add or remove a tracked quest by hand, the tracker and the pin leave your choice alone for this long." },
    { tab = "tracker", kind = "bool", key = "nearPin", label = "Pin the nearest quest in the world (the game's waypoint marker)",
      tip = "The game's own highlighted-quest marker follows the closest quest as you move." },
    { tab = "tracker", kind = "bool", key = "markMobs", label = "Quest icon above creatures that are part of my quests",
      tip = "On their nameplates. Needs enemy nameplates switched on in the game." },
    { tab = "tracker", kind = "bool", key = "highlightCVars", label = "Switch on the game settings the highlights need",
      tip = "Turns on enemy nameplates and icons over objects you can interact with. Switching this off puts your own values back." },
    -- Quick chat
    { tab = "quick", kind = "bool", key = "quick", label = "Quick chat ring (hold a key, point, release or click)",
      tip = "Hello / want to quest together? / what I need here... Pick the key with /qs key V or in Key Bindings." },
    { tab = "quick", kind = "choice", key = "quickMode", label = "The quick chat key", values = { "hold", "toggle" },
      names = { hold = "hold, point, release", toggle = "press to open, click a message" } },
    { tab = "quick", kind = "choice", key = "quickChannel", label = "Quick chat says it to", values = { "auto", "say", "party", "whisper" },
      names = { auto = "the party if I am in one, else my target (whisper), else nearby", say = "everybody nearby", party = "the party only", whisper = "the player I target" } },
    { tab = "quick", kind = "action", label = "Which key opens the ring? (set it with /qs key V)", action = function() ns.setQuickKey("") end },
    -- Social
    { tab = "social", kind = "bool", key = "friends", label = "(beta) Add people I group with to my friends list",
      tip = "Automatic. Off by default. Skips friends, ignored players and random-dungeon groups; /qs friends adds your party now." },
}

local function limit(v) if type(v) == "function" then return v() end return v end

function ns.rowText(row)
    local d = ns.db
    if row.kind == "bool" then
        return (d[row.key] and ON or OFF) .. " " .. row.label
    elseif row.kind == "choice" then
        local v = d[row.key]
        return row.label .. ": |cff55ccff" .. ((row.names and row.names[v]) or tostring(v)) .. "|r"
    elseif row.kind == "number" then
        return string.format("%s: |cff55ccff%d|r  |cff888888(left click +, right click -)|r", row.label, d[row.key] or 0)
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
        local step = (IsShiftKeyDown and IsShiftKeyDown()) and 5 or 1
        local v = (d[row.key] or 0) + (back and -step or step)
        ns.setSetting(row.key, math.max(row.min, math.min(limit(row.max), v)))
    elseif row.kind == "action" then
        row.action()
    end
end

local function rowsOf(tab)
    local out = {}
    for i, row in ipairs(ns.settingRows) do if row.tab == tab then out[#out + 1] = i end end
    return out
end

-- The window -----------------------------------------------------------------------------------------------------
local W = { win = nil, tab = "general", rows = {}, tabs = {}, ed = { selected = nil } }
local ROW_H, MAX_ROWS, TOP = 20, 14, 78

local function solid(frame, r, g, b, a)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(frame)
    if t.SetColorTexture then t:SetColorTexture(r, g, b, a) else t:SetTexture(r, g, b, a) end
    return t
end

local function clickable(parent, w, h, onClick)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(w)
    f:SetHeight(h)
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", onClick)
    return f
end

local function shorten(s, n) if #s <= n then return s end return string.sub(s, 1, n - 3) .. "..." end

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
                shorten(list[i].text, 52), list[i].channel == "nearby" and "  |cff88ccff/s|r" or ""))
            line.frame:Show()
        else
            line.frame:Hide()
        end
    end
    local item = ed.selected and list[ed.selected]
    ed.labelBox:SetText(item and item.label or "")
    ed.textBox:SetText(item and item.text or "")
    if ed.routeText then
        ed.routeText:SetText(item and (item.channel == "nearby" and "|cff55ccff[Goes to: nearby (/w target, else /s)]|r" or "|cff55ccff[Goes to: auto (party, else /w, else /s)]|r") or "")
    end
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
function ns.editorRoute()
    local item = ed.selected and ns.quickItems()[ed.selected]
    if item then ns.quickRoute(ed.selected, item.channel == "nearby" and "auto" or "nearby") end
    ns.editorRefresh()
end
function ns.editorReset() ns.quickReset(); ed.selected = nil; ns.editorRefresh() end

local function buildEditor(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(540)
    f:SetHeight(250)
    ed.frame, ed.lines = f, {}
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    title:SetText("Messages on the ring (up to 8, clockwise from the top)")
    for i = 1, 8 do
        local line = clickable(f, 540, 18, function() ns.editorSelect(i) end)
        line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -20 - (i - 1) * 18)
        local t = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        t:SetPoint("LEFT", line, "LEFT", 0, 0)
        ed.lines[i] = { frame = line, text = t }
    end
    local route = clickable(f, 250, 16, function() ns.editorRoute() end)
    route:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    ed.routeText = route:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ed.routeText:SetPoint("RIGHT", route, "RIGHT", 0, 0)
    ed.route = route
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
        if ChatFontNormal then b:SetFontObject(ChatFontNormal) end
        b:SetAutoFocus(false)
        b:SetMaxLetters(max)
        b:SetScript("OnEnterPressed", function() ns.editorSave(ed.labelBox:GetText(), ed.textBox:GetText()); b:ClearFocus() end)
        b:SetScript("OnEscapePressed", function() b:ClearFocus() end)
        return b
    end
    ed.labelBox, ed.textBox = box(150, 0, 14), box(360, 170, 200)
    ed.preview = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ed.preview:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -212)
    local x = 0
    for _, b in ipairs({
        { "Up", function() ns.editorMove(-1) end }, { "Down", function() ns.editorMove(1) end },
        { "Remove", function() ns.editorDelete() end }, { "Add", function() ns.editorAdd() end },
        { "Reset", function() ns.editorReset() end }, { "Show the ring", function() ns.quickOpen(true) end },
    }) do
        local btn = clickable(f, 84, 16, b[2])
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, -232)
        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("LEFT", btn, "LEFT", 0, 0)
        t:SetText("|cff55ccff[" .. b[1] .. "]|r")
        x = x + 88
    end
    return f
end

-- tabs and rows ---------------------------------------------------------------------------------------------------------
function ns.refreshSettings()
    if not W.win then return end
    local list = rowsOf(W.tab)
    for n = 1, MAX_ROWS do
        local r = W.rows[n]
        local idx = list[n]
        if idx then
            r.index = idx
            r.text:SetText(ns.rowText(ns.settingRows[idx]))
            r.frame:Show()
        else
            r.index = nil
            r.frame:Hide()
        end
    end
    for _, t in ipairs(ns.settingTabs) do
        W.tabs[t.id].text:SetText((t.id == W.tab and "|cffffd100" or "|cff55ccff") .. t.title .. "|r")
    end
    if W.tab == "quick" then
        ed.frame:ClearAllPoints()
        ed.frame:SetPoint("TOPLEFT", W.win, "TOPLEFT", 16, -(TOP + #list * ROW_H + 16))
        ed.frame:Show()
        ns.editorRefresh()
    else
        ed.frame:Hide()
    end
end

function ns.settingsTab(id)
    for _, t in ipairs(ns.settingTabs) do if t.id == id then W.tab = id end end
    ns.refreshSettings()
end

local function build()
    if W.win then return W.win end
    if not (CreateFrame and UIParent) then return nil end
    local ok, f = pcall(CreateFrame, "Frame", "QuestSharingSettings", UIParent, "BackdropTemplate")
    if not (ok and f) then ok, f = pcall(CreateFrame, "Frame", "QuestSharingSettings", UIParent) end
    if not (ok and f) then return nil end
    f:SetWidth(580)
    f:SetHeight(480)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    pcall(function()
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0, 0, 0, 0.92)
    end)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    W.win = f

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -12)
    title:SetText("Quest Sharing")
    local close = clickable(f, 60, 16, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -10)
    local ct = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ct:SetPoint("RIGHT", close, "RIGHT", 0, 0)
    ct:SetText("|cffff8080Close|r")

    local x = 16
    for _, t in ipairs(ns.settingTabs) do
        local b = clickable(f, 100, 20, function() ns.settingsTab(t.id) end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -36)
        local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", b, "LEFT", 0, 0)
        W.tabs[t.id] = { frame = b, text = text }
        x = x + 104
    end

    for n = 1, MAX_ROWS do
        local r = clickable(f, 540, ROW_H, nil)
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -TOP - (n - 1) * ROW_H)
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", r, "LEFT", 0, 0)
        W.rows[n] = { frame = r, text = fs }
        r:SetScript("OnMouseUp", function(_, button) if W.rows[n].index then ns.settingsClick(W.rows[n].index, button) end end)
        r:SetScript("OnEnter", function(self)
            local row = W.rows[n].index and ns.settingRows[W.rows[n].index]
            if row and row.tip and GameTooltip then
                pcall(function()
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(row.tip, 1, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
            end
        end)
        r:SetScript("OnLeave", function() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end)
    end
    buildEditor(f)
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
    local open = CreateFrame("Frame", nil, f)
    open:SetWidth(300)
    open:SetHeight(20)
    open:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -44)
    open:EnableMouse(true)
    open:SetScript("OnMouseUp", function() ns.toggleSettings(true) end)
    local ot = open:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    ot:SetPoint("LEFT", open, "LEFT", 0, 0)
    ot:SetText("|cff55ccffClick here to open the settings window|r  (or type /qs settings)")
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
