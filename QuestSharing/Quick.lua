-- Quick.lua: a quick-chat wheel, like the one in Diablo 4.
--   Bind a key (Game Menu > Options > Key Bindings > Quest Sharing, or  /qs key V ).
--   Hold the key: a wheel of up to 8 messages opens around the mouse. Point at one and release the key to say it.
--   A quick tap keeps the wheel open so you can click a slot instead; Esc closes it.
-- The messages are a list you can change (/qs quick, or the editor in /qs settings). They may contain
-- placeholders that fill themselves in when you send them:
--   (a message starting with @invite invites your target to your party and whispers them the rest of the text)
--   {name} the friendly player you target (or "there")      {here} your subzone / zone
--   {need} what you still have to do in this area            {common} quests you and your party have in common
--   {mine} links to your unfinished quests of this area       {quest} the nearest unfinished quest of this area
--   {shared} a whole sentence that fits the moment: in a party "we have these in common", with a stranger a
--            QUESTION that links your quests of this area (you cannot know theirs)     {zone} the zone
local ADDON, ns = ...
local C = ns.compat

BINDING_HEADER_QUESTSHARING = "Quest Sharing"
BINDING_NAME_QUESTSHARING_QUICKCHAT = "Quick chat wheel (hold, point, release)"
local ACTION = "QUESTSHARING_QUICKCHAT"

local MAX_ITEMS = 8
local RADIUS, DEAD = 95, 28          -- wheel radius and the empty middle, in UI units
local TAP = 0.25                     -- a release sooner than this is a "tap": the wheel stays open
local DEFAULT_ITEMS = {
    "Hey {name}! o/",
    "Want to quest together here? ({here})",
    "I need to: {need}",
    "{shared}",
    "Thanks!",
    "Wait for me, one sec!",
    "Follow me!",
    "@invite Sending you a party invite - let's quest together!",
}

function ns.defaultQuickItems()
    local t = {}
    for i, v in ipairs(DEFAULT_ITEMS) do t[i] = v end
    return t
end

local function items()
    ns.db.quickItems = ns.db.quickItems or ns.defaultQuickItems()
    return ns.db.quickItems
end

ns.on("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    if not ns.db.quickItems then ns.db.quickItems = ns.defaultQuickItems() end
    for i, text in ipairs(ns.db.quickItems) do          -- the old default message 4, if the player never changed it
        if text == "We have these quests in common: {common}" then ns.db.quickItems[i] = "{shared}" end
    end
end)

-- Placeholders ---------------------------------------------------------------------------------------------
local function targetName()
    if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target")
       and not (UnitIsUnit and UnitIsUnit("target", "player")) then
        return UnitName("target")
    end
end

local function hereText()
    local sub = GetSubZoneText and GetSubZoneText() or ""
    if sub ~= "" then return sub end
    return C.zone()
end

local function unfinishedHere()
    local list = {}
    for _, e in ipairs(C.entries()) do
        if not e.complete and C.inArea(e) then
            list[#list + 1] = { e = e, d = C.hasDistance() and C.distanceSq(e) or nil }
        end
    end
    table.sort(list, function(a, b)                      -- nearest first when the client can measure it, else log order
        if (a.d ~= nil) ~= (b.d ~= nil) then return a.d ~= nil end
        if a.d and a.d ~= b.d then return a.d < b.d end
        return a.e.index < b.e.index
    end)
    return list
end

local function needText()
    local list = unfinishedHere()
    if #list == 0 then return "nothing special, just looking around" end
    local parts = {}
    for i = 1, math.min(2, #list) do
        local e = list[i].e
        local left = {}
        for _, o in ipairs(C.objectives(e)) do
            if not o.finished then
                left[#left + 1] = (o.have and o.need) and string.format("%s %d/%d", o.name or o.text, o.have, o.need) or o.text
            end
        end
        parts[#parts + 1] = (#left > 0 and (table.concat(left, ", ") .. " ") or "") .. "[" .. e.title .. "]"
    end
    return table.concat(parts, " and ")
end

-- links to the quests you and the party both have (nil if none)
local function commonLinks()
    local links = {}
    for _, e in ipairs(C.entries()) do
        if #ns.partyHas(e) > 0 and #links < 4 then links[#links + 1] = C.link(e) end
    end
    if #links == 0 then return nil end
    return table.concat(links, ", ")
end

local function commonText() return commonLinks() or "nothing yet" end

-- links to your own unfinished quests of this area, nearest first (nil if none)
local function mineLinks()
    local list = unfinishedHere()
    local links = {}
    for i = 1, math.min(3, #list) do links[#links + 1] = C.link(list[i].e) end
    if #links == 0 then return nil end
    return table.concat(links, ", ")
end

-- A whole sentence that fits the moment. Before someone is in your party you cannot know which quests they
-- have, so with a stranger it is a QUESTION that links yours: they can click a link and tell you.
local function sharedText()
    local mine = mineLinks()
    if C.inGroup() then
        local common = commonLinks()
        if common then return "We have these quests in common: " .. common end
        if mine then return "No quest in common yet - I'm on " .. mine .. ". Any of these yours?" end
        return "No quest in common yet - what are you working on here?"
    end
    if mine then return "Are you doing any of these quests here? " .. mine .. " Want to do them together?" end
    return "Are you questing around here? Want to team up?"
end

local FILL = {
    name = function() return targetName() or "there" end,
    here = hereText,
    zone = function() return C.zone() end,
    need = needText,
    common = commonText,
    mine = function() return mineLinks() or "my quests" end,
    shared = sharedText,
    quest = function()
        local list = unfinishedHere()
        return list[1] and C.link(list[1].e) or "my quests"
    end,
}

-- Fill in the placeholders; unknown ones are left as typed. Always fits one chat message.
function ns.quickResolve(text)
    local out = string.gsub(text or "", "{(%a+)}", function(word)
        local f = FILL[string.lower(word)]
        return f and tostring(f()) or nil
    end)
    if #out > 255 then out = string.sub(out, 1, 252) .. "..." end
    return out
end

-- Where the message goes ------------------------------------------------------------------------------------
local function pickChannel()
    local mode = ns.db.quickChannel
    if mode == "say" then return "SAY" end
    if mode == "party" then
        if C.inGroup() then return C.channel() end
        ns.print("quick chat: you are not in a party")
        return nil
    end
    if mode == "whisper" then
        local who = targetName()
        if who then return "WHISPER", who end
        ns.print("quick chat: target a player first to whisper them")
        return nil
    end
    if C.inGroup() then return C.channel() end            -- auto: the party if you are in one, else everybody nearby
    return "SAY"
end

local function isInvite(text)
    return string.sub(text, 1, 7) == "@invite" and (#text == 7 or string.sub(text, 8, 8) == " ")
end

local function inviteRest(text) return (string.gsub(string.sub(text, 8), "^%s+", "")) end

-- what the wheel shows for a message
local function displayText(text)
    if isInvite(text) then
        local rest = inviteRest(text)
        return "Invite: " .. (rest ~= "" and ns.quickResolve(rest) or "party invite")
    end
    return ns.quickResolve(text)
end

local q = { open = false, hover = nil, cx = 0, cy = 0, openedAt = 0, lastSend = -10, sticky = false }
ns.quick = q

function ns.quickSend(i)
    local text = items()[i]
    if not text then return false end
    if GetTime() - q.lastSend < 1 then return false end   -- no accidental double sends
    if isInvite(text) then
        local who = targetName()
        if not who then ns.print("quick chat: target a player first to invite them"); return false end
        if not C.canInvite() then ns.print("quick chat: this client has no call to invite players"); return false end
        if C.inGroup() and not C.isLeader() then ns.print("quick chat: only the party leader can invite"); return false end
        if C.groupSize() >= 5 then ns.print("quick chat: your party is full"); return false end
        if not C.invite(who) then ns.print("quick chat: the invite did not go through"); return false end
        local rest = inviteRest(text)
        if rest ~= "" then SendChatMessage(ns.quickResolve(rest), "WHISPER", nil, who) end
        q.lastSend = GetTime()
        return true
    end
    local channel, target = pickChannel()
    if not channel then return false end
    SendChatMessage(ns.quickResolve(text), channel, nil, target)
    q.lastSend = GetTime()
    return true
end

-- Wheel geometry ----------------------------------------------------------------------------------------------
-- Slot number (1 = top, clockwise) for a mouse offset (dx, dy) from the wheel's centre, or nil in the middle.
function ns.quickSlotAt(dx, dy, n)
    if n < 1 or dx * dx + dy * dy < DEAD * DEAD then return nil end
    local a = math.atan2(dx, dy)                           -- 0 = straight up, clockwise
    if a < 0 then a = a + 2 * math.pi end
    local step = 2 * math.pi / n
    return math.floor((a + step / 2) / step) % n + 1
end

local frame, labels, preview

local function cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
end

local function shorten(s, n)
    if #s <= n then return s end
    return string.sub(s, 1, n - 3) .. "..."
end

local function paint()
    if not labels then return end
    local list = items()
    for i = 1, MAX_ITEMS do
        local fs = labels[i]
        if list[i] then
            local text = shorten(displayText(list[i]), 30)
            fs:SetText((q.hover == i and "|cffffd100> " or "|cffffffff") .. text .. "|r")
            fs:Show()
        else
            fs:Hide()
        end
    end
    preview:SetText(q.hover and ("|cffffd100" .. shorten(displayText(list[q.hover] or ""), 110) .. "|r") or "|cff888888point and release|r")
end

function ns.quickUpdateHover()
    local x, y = cursor()
    q.hover = ns.quickSlotAt(x - q.cx, y - q.cy, #items())
    paint()
end

local function build()
    if frame then return frame end
    if not (CreateFrame and UIParent) then return nil end
    local ok, f = pcall(CreateFrame, "Frame", "QuestSharingQuickChat", UIParent)
    if not (ok and f) then return nil end
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)                                    -- it catches the click that picks a slot
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ns.quickClose(); return end
        ns.quickUpdateHover()
        local i = q.hover
        ns.quickClose()
        if i then ns.quickSend(i) end
    end)
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc >= 0.03 then acc = 0; if q.open then ns.quickUpdateHover() end end
    end)
    labels = {}
    for i = 1, MAX_ITEMS do
        labels[i] = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    end
    preview = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestSharingQuickChat") end       -- Esc closes it
    frame = f
    f:Hide()
    return f
end

function ns.quickOpen()
    local f = build()
    if not f then return ns.print("this client does not allow the quick chat wheel (frame creation failed)") end
    local list = items()
    if #list == 0 then return ns.print("quick chat has no messages: /qs quick add <text>") end
    q.cx, q.cy = cursor()
    q.open, q.openedAt, q.hover = true, GetTime(), nil
    local n = #list
    for i = 1, MAX_ITEMS do
        local a = (i - 1) * 2 * math.pi / math.max(n, 1)
        labels[i]:ClearAllPoints()
        labels[i]:SetPoint("CENTER", UIParent, "BOTTOMLEFT", q.cx + RADIUS * math.sin(a) * 1.35, q.cy + RADIUS * math.cos(a))
    end
    preview:ClearAllPoints()
    preview:SetPoint("CENTER", UIParent, "BOTTOMLEFT", q.cx, q.cy)
    paint()
    f:Show()
end

function ns.quickClose()
    q.open, q.hover = false, nil
    if frame then frame:Hide() end
end

-- The key. Held: the wheel is open; released: the pointed slot is said. A quick tap leaves it open. -----------
function ns.quickKey(state)
    local d = ns.db
    if not (d.enabled and d.quick) then
        if state == "down" then ns.print("quick chat is switched off (/qs quick on)") end
        return
    end
    if state == "down" then
        if q.open then ns.quickClose() else ns.quickOpen() end            -- pressing again closes it
        return
    end
    if d.quickMode == "toggle" or not q.open then return end              -- toggle mode ignores the release
    if GetTime() - q.openedAt < TAP then return end                       -- a tap: the wheel stays open for a click
    ns.quickUpdateHover()
    local i = q.hover
    ns.quickClose()
    if i then ns.quickSend(i) end
end

function QuestSharing_QuickDown() ns.quickKey("down") end
function QuestSharing_QuickUp() ns.quickKey("up") end

-- Choosing the key ------------------------------------------------------------------------------------------------
function ns.setQuickKey(key)
    if InCombatLockdown and InCombatLockdown() then return ns.print("key bindings cannot be changed in combat") end
    if not (SetBinding and GetBindingKey) then return ns.print("this client does not let an addon set a key; use Options > Key Bindings") end
    key = string.upper(key or "")
    if key == "" then
        local k1, k2 = GetBindingKey(ACTION)
        return ns.print("quick chat key: " .. (k1 and (k1 .. (k2 and (" and " .. k2) or "")) or "none yet")
                        .. "  (/qs key <KEY> to set it, e.g. /qs key V or /qs key ALT-E; /qs key none to remove)")
    end
    if key == "NONE" then
        for _, k in ipairs({ GetBindingKey(ACTION) }) do SetBinding(k) end
    else
        local before = GetBindingAction and GetBindingAction(key) or ""
        if not SetBinding(key, ACTION) then return ns.print("could not bind " .. key .. " (is that a valid key name?)") end
        if before ~= "" and before ~= ACTION then
            ns.print(key .. " used to do: " .. before .. " (it now opens the quick chat wheel; /qs key none and rebind it in Key Bindings to undo)")
        end
    end
    local save = SaveBindings or AttemptToSaveBindings
    if save then save(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
    ns.print(key == "NONE" and "quick chat key removed" or ("quick chat key: " .. key .. " (hold it, point, release)"))
end

-- Editing the messages ----------------------------------------------------------------------------------------------
local function listItems()
    local list = items()
    if #list == 0 then ns.print("quick chat: no messages (/qs quick add <text>)") end
    for i, t in ipairs(list) do ns.print(string.format("%d. %s", i, t)) end
    ns.print("placeholders: {name} {here} {zone} {need} {mine} {common} {shared} {quest}   |   '@invite <text>' invites your target and whispers <text>")
end

function ns.quickAdd(text)
    local list = items()
    text = string.match(text or "", "^%s*(.-)%s*$")
    if text == "" then return ns.print("quick chat: write the message after 'add'") end
    if #text > 200 then return ns.print("quick chat: that message is too long (200 characters at most)") end
    if #list >= MAX_ITEMS then return ns.print("quick chat: the wheel holds " .. MAX_ITEMS .. " messages; remove one first") end
    list[#list + 1] = text
    return #list
end

function ns.quickEdit(i, text)
    local list = items()
    text = string.match(text or "", "^%s*(.-)%s*$")
    if not list[i] then return ns.print("quick chat: there is no message " .. tostring(i)) end
    if text == "" or #text > 200 then return ns.print("quick chat: the message must be 1 to 200 characters") end
    list[i] = text
    return i
end

function ns.quickRemove(i)
    local list = items()
    if not list[i] then return ns.print("quick chat: there is no message " .. tostring(i)) end
    table.remove(list, i)
    return true
end

function ns.quickMove(from, to)
    local list = items()
    if not (list[from] and to and to >= 1 and to <= #list) then return ns.print("quick chat: use /qs quick move <from> <to> with numbers from the list") end
    local v = table.remove(list, from)
    table.insert(list, to, v)
    return true
end

function ns.quickCommand(arg)
    arg = arg or ""
    local sub, rest = string.match(arg, "^(%S*)%s*(.-)%s*$")
    sub = string.lower(sub or "")
    local n1, n2 = string.match(rest, "^(%d+)%s*(.-)$")
    if sub == "" or sub == "list" then listItems()
    elseif sub == "on" or sub == "off" then ns.setSetting("quick", sub == "on")
    elseif sub == "open" then ns.quickOpen()
    elseif sub == "add" then if ns.quickAdd(rest) then listItems() end
    elseif sub == "edit" and n1 then if ns.quickEdit(tonumber(n1), n2) then listItems() end
    elseif sub == "remove" and n1 then if ns.quickRemove(tonumber(n1)) then listItems() end
    elseif sub == "move" and n1 then if ns.quickMove(tonumber(n1), tonumber(n2)) then listItems() end
    elseif sub == "reset" then ns.db.quickItems = ns.defaultQuickItems(); listItems()
    elseif sub == "mode" and (rest == "hold" or rest == "toggle") then ns.setSetting("quickMode", rest)
    elseif sub == "channel" and (rest == "auto" or rest == "say" or rest == "party" or rest == "whisper") then ns.setSetting("quickChannel", rest)
    elseif sub == "editor" then ns.openQuickEditor()
    else
        ns.print("/qs quick [list] | add <text> | edit N <text> | remove N | move N M | reset | on|off | mode hold|toggle | channel auto|say|party|whisper | editor | open")
    end
    if ns.refreshSettings then ns.refreshSettings() end
end

-- The editor window ----------------------------------------------------------------------------------------------------
local ed = { win = nil, rows = nil, box = nil, selected = nil }

function ns.editorRefresh()
    if not ed.win then return end
    local list = items()
    for i = 1, MAX_ITEMS do
        local row = ed.rows[i]
        if list[i] then
            row.text:SetText(string.format("%s%d. %s|r", ed.selected == i and "|cffffd100" or "|cffffffff", i, shorten(list[i], 52)))
            row.frame:Show()
        else
            row.frame:Hide()
        end
    end
    ed.box:SetText(ed.selected and list[ed.selected] or "")
end

function ns.editorSelect(i) ed.selected = (items()[i] and i) or nil; ns.editorRefresh() end
function ns.editorMove(delta)
    if ed.selected and ns.quickMove(ed.selected, ed.selected + delta) then ed.selected = ed.selected + delta end
    ns.editorRefresh()
end
function ns.editorDelete()
    if ed.selected and ns.quickRemove(ed.selected) then ed.selected = nil end
    ns.editorRefresh()
end
function ns.editorAdd()
    local n = ns.quickAdd("New message")
    if n then ed.selected = n end
    ns.editorRefresh()
end
function ns.editorSave(text)
    if ed.selected then ns.quickEdit(ed.selected, text) end
    ns.editorRefresh()
end

local function button(parent, label, x, onClick)
    local b = CreateFrame("Frame", nil, parent)
    b:SetWidth(70)
    b:SetHeight(16)
    b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 12)
    b:EnableMouse(true)
    b:SetScript("OnMouseUp", onClick)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("LEFT", b, "LEFT", 0, 0)
    t:SetText("|cff55ccff[" .. label .. "]|r")
    return b
end

function ns.openQuickEditor()
    if not ed.win then
        if not (CreateFrame and UIParent) then return ns.print("this client does not allow the editor window") end
        local ok, f = pcall(CreateFrame, "Frame", "QuestSharingQuickEditor", UIParent, "BackdropTemplate")
        if not (ok and f) then ok, f = pcall(CreateFrame, "Frame", "QuestSharingQuickEditor", UIParent) end
        if not (ok and f) then return ns.print("this client does not allow the editor window") end
        f:SetWidth(440)
        f:SetHeight(48 + MAX_ITEMS * 18 + 70)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
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
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
        title:SetText("Quick chat messages")
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -28)
        hint:SetText("Click a line, edit the text below and press Enter. Placeholders: {name} {here} {need} {mine} {common} {shared} {quest} {zone}")
        ed.rows = {}
        for i = 1, MAX_ITEMS do
            local r = CreateFrame("Frame", nil, f)
            r:SetWidth(410)
            r:SetHeight(18)
            r:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -46 - (i - 1) * 18)
            r:EnableMouse(true)
            r:SetScript("OnMouseUp", function() ns.editorSelect(i) end)
            local t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            t:SetPoint("LEFT", r, "LEFT", 0, 0)
            ed.rows[i] = { frame = r, text = t }
        end
        local box = CreateFrame("EditBox", nil, f)
        box:SetWidth(410)
        box:SetHeight(20)
        box:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 40)
        if ChatFontNormal then box:SetFontObject(ChatFontNormal) end
        box:SetAutoFocus(false)
        box:SetMaxLetters(200)
        box:SetScript("OnEnterPressed", function(self) ns.editorSave(self:GetText()); self:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        ed.box = box
        button(f, "Up", 14, function() ns.editorMove(-1) end)
        button(f, "Down", 84, function() ns.editorMove(1) end)
        button(f, "Delete", 154, function() ns.editorDelete() end)
        button(f, "Add", 224, function() ns.editorAdd() end)
        button(f, "Reset", 294, function() ns.db.quickItems = ns.defaultQuickItems(); ed.selected = nil; ns.editorRefresh() end)
        button(f, "Close", 364, function() f:Hide() end)
        if UISpecialFrames then table.insert(UISpecialFrames, "QuestSharingQuickEditor") end
        ed.win = f
    end
    ns.editorRefresh()
    ed.win:Show()
end

function ns._quickEditor() return ed end              -- for the tests
function ns._quickWheel() return frame, labels, preview end
