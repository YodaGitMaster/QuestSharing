-- Quick.lua: a quick-chat wheel.
--   Bind a key (Game Menu > Options > Key Bindings > Quest Sharing, or  /qs key V ).
--   HOLD the key: a clean ring of up to 8 messages opens around the mouse. Point at one: its full text shows in the
--   middle. Release the key to say it, or click it. The messages and their short labels are yours to change
--   (/qs settings > Quick chat).
--
-- Where it goes:  a player targeted -> a whisper to them;  otherwise your party;  otherwise everybody nearby (/say).
--
-- The game only lets an addon say things to everybody nearby (/say, /yell, /emote) as the direct result of a key PRESS
-- or a mouse CLICK, never from a key RELEASE. So for those (and for @invite) a release keeps the ring open on your
-- choice and one click, or one more press of the key, sends it. Whispers and party chat are not restricted: they
-- send on release.
--
-- Messages may contain placeholders, filled in when you point at them (not before, so the ring costs nothing):
--   {name} the friendly player you target (or "there")      {here} your subzone / zone
--   {need} what you still have to do in this area            {common} quests you and your party have in common
--   {mine} links to your unfinished quests of this area       {quest} the nearest unfinished quest of this area
--   {shared} a sentence that fits the moment: with a party "we have these in common", with a stranger a QUESTION
--            that links your quests of this area (you cannot know theirs)     {zone} the zone
--   A message that starts with @invite invites your target to your party and whispers them the rest of the text.
local ADDON, ns = ...
local C = ns.compat

BINDING_HEADER_QUESTSHARING = "Quest Sharing"
BINDING_NAME_QUESTSHARING_QUICKCHAT = "Quick chat wheel (hold, point, release or click)"
local ACTION = "QUESTSHARING_QUICKCHAT"

local MAX_ITEMS, LABEL_MAX = 8, 14
local RADIUS, DEAD = 118, 30         -- ring radius and the empty middle, in UI units
local TAP = 0.25                     -- a release sooner than this is a "tap": the ring stays open
local CIRCLE = "Interface\\Minimap\\UI-Minimap-Background"

-- The messages ------------------------------------------------------------------------------------------------
local DEFAULT_ITEMS = {
    { label = "Hello",         text = "Hey {name}! o/" },
    { label = "Team up?",      text = "Want to quest together here? ({here})" },
    { label = "What I need",   text = "I need to: {need}" },
    { label = "Same quests?",  text = "{shared}" },
    { label = "Thanks",        text = "Thanks!" },
    { label = "Wait",          text = "Wait for me, one sec!" },
    { label = "Follow me",     text = "Follow me!" },
    { label = "Invite",        text = "@invite Sending you a party invite - let's quest together!" },
}

function ns.defaultQuickItems()
    local t = {}
    for i, v in ipairs(DEFAULT_ITEMS) do t[i] = { label = v.label, text = v.text } end
    return t
end

local function autoLabel(text)
    if string.sub(text, 1, 7) == "@invite" then return "Invite" end
    local clean = string.gsub(text, "{%a+}", "")
    clean = string.match(string.gsub(clean, "%s+", " "), "^%s*(.-)%s*$")
    if clean == "" then return "Message" end
    if #clean <= LABEL_MAX then return clean end
    local cut = string.sub(clean, 1, LABEL_MAX)
    local words = string.match(cut, "^(.*)%s%S*$")             -- cut at a word boundary when that leaves something sensible
    return (words and #words >= 4) and words or cut
end

local DEFAULT_LABEL = {}
for _, v in ipairs(DEFAULT_ITEMS) do DEFAULT_LABEL[v.text] = v.label end

-- earlier versions stored plain strings: turn them into {label, text}
local function normalise(list)
    for i, v in ipairs(list) do
        if type(v) == "string" then
            if v == "We have these quests in common: {common}" then v = "{shared}" end   -- the old fourth default
            list[i] = { label = DEFAULT_LABEL[v] or autoLabel(v), text = v }
        end
    end
    return list
end

local function items()
    ns.db.quickItems = normalise(ns.db.quickItems or ns.defaultQuickItems())
    return ns.db.quickItems
end
ns.quickItems = items

ns.on("ADDON_LOADED", function(_, name)
    if name == ADDON then items() end
end)

-- Placeholders ---------------------------------------------------------------------------------------------
local function targetName()
    if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target")
       and not (UnitIsUnit and UnitIsUnit("target", "player")) then
        return UnitName("target")
    end
end

-- the name to whisper (with the realm for players of another realm)
local function targetWhisperName()
    if not targetName() then return nil end
    local n, r = UnitName("target")
    if r and r ~= "" then return n .. "-" .. r end
    return n
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

local function commonLinks()
    local links = {}
    for _, e in ipairs(C.entries()) do
        if #ns.partyHas(e) > 0 and #links < 4 then links[#links + 1] = C.link(e) end
    end
    if #links == 0 then return nil end
    return table.concat(links, ", ")
end

local function mineLinks()
    local list = unfinishedHere()
    local links = {}
    for i = 1, math.min(3, #list) do links[#links + 1] = C.link(list[i].e) end
    if #links == 0 then return nil end
    return table.concat(links, ", ")
end

-- Before someone is in your party you cannot know which quests they have, so with a stranger it is a QUESTION
-- that links yours: they can click a link and tell you.
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
    common = function() return commonLinks() or "nothing yet" end,
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

-- Actions and channels ------------------------------------------------------------------------------------------
local function isInvite(text)
    return string.sub(text, 1, 7) == "@invite" and (#text == 7 or string.sub(text, 8, 8) == " ")
end
local function inviteRest(text) return (string.gsub(string.sub(text, 8), "^%s+", "")) end

-- channel, whisper target (or nil, reason). A targeted player always gets a whisper in "auto".
local function channelFor()
    local mode = ns.db.quickChannel
    local who = targetWhisperName()
    if mode == "say" then return "SAY" end
    if mode == "party" then
        if C.inGroup() then return C.channel() end
        return nil, nil, "you are not in a party"
    end
    if mode == "whisper" then
        if who then return "WHISPER", who end
        return nil, nil, "target a player first to whisper them"
    end
    if who then return "WHISPER", who end                 -- auto: you picked someone, so it is for them
    if C.inGroup() then return C.channel() end
    return "SAY"
end

-- Does sending this need a real key press / click (rather than a key release)?
local RESTRICTED = { SAY = true, YELL = true, EMOTE = true }
local function needsClick(i)
    local item = items()[i]
    if not item then return false end
    if isInvite(item.text) then return true end
    local channel = channelFor()
    return channel ~= nil and RESTRICTED[channel] == true
end

local q = { open = false, hover = nil, cx = 0, cy = 0, openedAt = 0, lastSend = -10, sticky = false, cache = {}, lastDx = nil, lastDy = nil }
ns.quick = q

-- What we last handed to the game. If the game answers with "blocked" (ADDON_ACTION_FORBIDDEN), we know which message
-- it was, and the sentence is put into the chat box so you only press Enter.
local SLASH = { SAY = "/s ", YELL = "/y ", EMOTE = "/e ", PARTY = "/p ", RAID = "/raid ", INSTANCE_CHAT = "/i ", GUILD = "/g " }

local function deliver(text, channel, target)
    q.last = { text = text, channel = channel, target = target, at = GetTime() }
    SendChatMessage(text, channel, nil, target)
end

-- called from Diagnostics when the game blocks one of our calls; true if it was a send from the ring
function ns.quickBlocked()
    local l = q.last
    if not (l and GetTime() - l.at < 1) then return false, nil end
    q.last = nil
    local line
    if l.channel == "INVITE" then line = "/invite " .. tostring(l.target)
    elseif l.channel == "WHISPER" then line = "/w " .. tostring(l.target) .. " " .. l.text
    else line = (SLASH[l.channel] or "/s ") .. l.text end
    if ChatFrame_OpenChat then pcall(ChatFrame_OpenChat, line) end
    ns.print("quick chat: the game did not let the addon send that. It is in your chat box - press Enter to send it.")
    return true, l
end

function ns.quickSend(i)
    local item = items()[i]
    if not item then return false end
    if GetTime() - q.lastSend < 1 then return false end      -- no accidental double sends
    if isInvite(item.text) then
        local who = targetWhisperName()
        if not who then ns.print("quick chat: target a player first to invite them"); return false end
        if not C.canInvite() then ns.print("quick chat: this client has no call to invite players"); return false end
        if C.inGroup() and not C.isLeader() then ns.print("quick chat: only the party leader can invite"); return false end
        if C.groupSize() >= 5 then ns.print("quick chat: your party is full"); return false end
        q.last = { text = "", channel = "INVITE", target = who, at = GetTime() }
        if not C.invite(who) then ns.print("quick chat: the invite did not go through"); return false end
        local rest = inviteRest(item.text)
        if rest ~= "" then deliver(ns.quickResolve(rest), "WHISPER", who) end
        q.lastSend = GetTime()
        return true
    end
    local channel, target, why = channelFor()
    if not channel then ns.print("quick chat: " .. tostring(why)); return false end
    deliver(ns.quickResolve(item.text), channel, target)
    q.lastSend = GetTime()
    return true
end

-- Ring geometry ------------------------------------------------------------------------------------------------------
-- Slot number (1 = top, clockwise) for a mouse offset (dx, dy) from the ring's centre, or nil in the middle.
function ns.quickSlotAt(dx, dy, n)
    if n < 1 or dx * dx + dy * dy < DEAD * DEAD then return nil end
    local a = math.atan2(dx, dy)                           -- 0 = straight up, clockwise
    if a < 0 then a = a + 2 * math.pi end
    local step = 2 * math.pi / n
    return math.floor((a + step / 2) / step) % n + 1
end

local frame, slots, disc, centerText, hintText

local function cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
end

local function shorten(s, n)
    if #s <= n then return s end
    return string.sub(s, 1, n - 3) .. "..."
end

-- what the middle of the ring shows for a slot (filled in once per slot per opening)
local function middleText(i)
    if q.cache[i] == nil then
        local item = items()[i]
        if isInvite(item.text) then
            local rest = inviteRest(item.text)
            q.cache[i] = "Invite to my party" .. (rest ~= "" and (" - " .. ns.quickResolve(rest)) or "")
        else
            q.cache[i] = ns.quickResolve(item.text)
        end
    end
    return q.cache[i]
end

local function paintSlot(i)
    local s, item = slots[i], items()[i]
    if not s then return end
    if not item then s.button:Hide(); return end
    local hot = (q.hover == i)
    s.button:Show()
    s.label:SetText((hot and "|cffffd100" or "|cffffffff") .. item.label .. "|r")
    if hot then s.node:SetVertexColor(1, 0.82, 0, 1) else s.node:SetVertexColor(0.5, 0.5, 0.55, 1) end
end

local function paintMiddle()
    if not centerText then return end
    if q.hover then
        centerText:SetText("|cffffd100" .. shorten(middleText(q.hover), 120) .. "|r")
        if q.sticky then hintText:SetText("click it (or press the key again) to say it")
        elseif needsClick(q.hover) then hintText:SetText("release: keeps it open - click to say it")
        else hintText:SetText("release or click to send") end
    else
        centerText:SetText("|cff888888point at a message|r")
        hintText:SetText(q.sticky and "click a message, or click outside to close" or "")
    end
end

function ns.quickUpdateHover()
    local x, y = cursor()
    local dx, dy = x - q.cx, y - q.cy
    if dx == q.lastDx and dy == q.lastDy then return end     -- the mouse has not moved: nothing to do
    q.lastDx, q.lastDy = dx, dy
    local new = ns.quickSlotAt(dx, dy, #items())
    if new == q.hover then return end                        -- still on the same slot: nothing to repaint
    local old = q.hover
    q.hover = new
    if old then paintSlot(old) end
    if new then paintSlot(new) end
    paintMiddle()
end

local function build()
    if frame then return frame end
    if not (CreateFrame and UIParent) then return nil end
    local ok, f = pcall(CreateFrame, "Frame", "QuestSharingQuickChat", UIParent)
    if not (ok and f) then return nil end
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)                                    -- a click outside the ring (or a right click) closes it
    f:SetScript("OnMouseUp", function() ns.quickClose() end)
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc >= 0.04 then acc = 0; if q.open then ns.quickUpdateHover() end end
    end)
    disc = f:CreateTexture(nil, "BACKGROUND")
    disc:SetTexture(CIRCLE)
    disc:SetVertexColor(0, 0, 0, 0.6)
    centerText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    centerText:SetWidth(2 * (RADIUS - 46))
    centerText:SetJustifyH("CENTER")
    hintText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintText:SetJustifyH("CENTER")
    slots = {}
    for i = 1, MAX_ITEMS do
        -- one button per slot: a click on it is the real mouse click the game wants for /say
        local b = CreateFrame("Button", nil, f)
        b:SetWidth(34)
        b:SetHeight(34)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, which)
            if which == "RightButton" then ns.quickClose() else ns.quickClick(i) end
        end)
        local node = b:CreateTexture(nil, "ARTWORK")
        node:SetTexture(CIRCLE)
        node:SetWidth(24)
        node:SetHeight(24)
        node:SetPoint("CENTER", b, "CENTER", 0, 0)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slots[i] = { button = b, node = node, label = label }
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestSharingQuickChat") end       -- Esc closes it
    frame = f
    f:Hide()
    return f
end

-- put the ring on the screen, around (cx, cy) but never off the edge
local function layout()
    local n = #items()
    local w, h = UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080
    local margin = RADIUS + 70
    q.cx = math.max(margin, math.min(w - margin, q.cx))
    q.cy = math.max(margin, math.min(h - margin, q.cy))
    disc:ClearAllPoints()
    disc:SetPoint("CENTER", UIParent, "BOTTOMLEFT", q.cx, q.cy)
    disc:SetWidth(2 * (RADIUS - 20))
    disc:SetHeight(2 * (RADIUS - 20))
    centerText:ClearAllPoints()
    centerText:SetPoint("CENTER", UIParent, "BOTTOMLEFT", q.cx, q.cy + 8)
    hintText:ClearAllPoints()
    hintText:SetPoint("CENTER", UIParent, "BOTTOMLEFT", q.cx, q.cy - 38)
    for i = 1, MAX_ITEMS do
        local s = slots[i]
        local a = (i - 1) * 2 * math.pi / math.max(n, 1)
        local sx, sy = math.sin(a), math.cos(a)
        s.button:ClearAllPoints()
        s.button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", q.cx + RADIUS * sx, q.cy + RADIUS * sy)
        s.label:ClearAllPoints()
        -- the label sits OUTSIDE the ring, on the side away from the middle, so neighbours never overlap
        if math.abs(sx) < 0.3 then
            if sy > 0 then s.label:SetPoint("BOTTOM", s.button, "TOP", 0, 2) else s.label:SetPoint("TOP", s.button, "BOTTOM", 0, -2) end
        elseif sx > 0 then
            s.label:SetPoint("LEFT", s.button, "RIGHT", 2, 0)
        else
            s.label:SetPoint("RIGHT", s.button, "LEFT", -2, 0)
        end
    end
end

function ns.quickOpen(atCenter)
    local f = build()
    if not f then return ns.print("this client does not allow the quick chat wheel (frame creation failed)") end
    if #items() == 0 then return ns.print("quick chat has no messages: /qs settings > Quick chat, or /qs quick add <text>") end
    if atCenter then q.cx, q.cy = (UIParent:GetWidth() or 1920) / 2, (UIParent:GetHeight() or 1080) / 2 else q.cx, q.cy = cursor() end
    q.open, q.openedAt, q.hover, q.sticky, q.cache, q.lastDx, q.lastDy = true, GetTime(), nil, atCenter and true or false, {}, nil, nil
    layout()
    for i = 1, MAX_ITEMS do paintSlot(i) end
    paintMiddle()
    f:Show()
end

function ns.quickClose()
    q.open, q.hover, q.sticky = false, nil, false
    if frame then frame:Hide() end
end

-- a click on a slot: a real mouse click, so even /say is allowed
function ns.quickClick(i)
    ns.quickClose()
    ns.quickSend(i)
end

-- The key. -----------------------------------------------------------------------------------------------------------------
function ns.quickKey(state)
    local d = ns.db
    if not (d.enabled and d.quick) then
        if state == "down" then ns.print("quick chat is switched off (/qs quick on)") end
        return
    end
    if state == "down" then
        if q.open then                                    -- a key PRESS is a real input: it may send what is pointed at
            ns.quickUpdateHover()
            local i = q.hover
            ns.quickClose()
            if i then ns.quickSend(i) end
        else
            ns.quickOpen()
        end
        return
    end
    if d.quickMode == "toggle" or not q.open then return end                -- toggle mode waits for a click
    if GetTime() - q.openedAt < TAP then q.sticky = true; paintMiddle(); return end   -- a tap: stay open for a click
    ns.quickUpdateHover()
    local i = q.hover
    if not i then ns.quickClose(); return end
    if needsClick(i) then                                 -- /say, /yell, /emote, invite: not allowed from a release
        q.sticky = true
        paintMiddle()
        return
    end
    ns.quickClose()
    ns.quickSend(i)
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
    ns.print(key == "NONE" and "quick chat key removed" or ("quick chat key: " .. key .. " (hold it, point, release or click)"))
end

-- Editing the messages ---------------------------------------------------------------------------------------------------
local function clean(s) return (string.match(s or "", "^%s*(.-)%s*$")) end

function ns.quickAdd(text, label)
    local list = items()
    text, label = clean(text), clean(label)
    if text == "" then return ns.print("quick chat: write the message after 'add'") end
    if #text > 200 then return ns.print("quick chat: that message is too long (200 characters at most)") end
    if #list >= MAX_ITEMS then return ns.print("quick chat: the ring holds " .. MAX_ITEMS .. " messages; remove one first") end
    list[#list + 1] = { label = (label ~= "" and string.sub(label, 1, LABEL_MAX)) or autoLabel(text), text = text }
    return #list
end

function ns.quickEdit(i, text)
    local list = items()
    text = clean(text)
    if not list[i] then return ns.print("quick chat: there is no message " .. tostring(i)) end
    if text == "" or #text > 200 then return ns.print("quick chat: the message must be 1 to 200 characters") end
    list[i].text = text
    return i
end

function ns.quickLabel(i, label)
    local list = items()
    label = clean(label)
    if not list[i] then return ns.print("quick chat: there is no message " .. tostring(i)) end
    if label == "" then return ns.print("quick chat: the label cannot be empty") end
    list[i].label = string.sub(label, 1, LABEL_MAX)
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
    table.insert(list, to, table.remove(list, from))
    return true
end

function ns.quickReset() ns.db.quickItems = ns.defaultQuickItems() end

local function listItems()
    local list = items()
    if #list == 0 then ns.print("quick chat: no messages (/qs quick add <text>)") end
    for i, it in ipairs(list) do ns.print(string.format("%d. [%s] %s", i, it.label, it.text)) end
    ns.print("placeholders: {name} {here} {zone} {need} {mine} {common} {shared} {quest}   |   '@invite <text>' invites your target and whispers <text>")
end

function ns.quickCommand(arg)
    arg = arg or ""
    local sub, rest = string.match(arg, "^(%S*)%s*(.-)%s*$")
    sub = string.lower(sub or "")
    local n1, n2 = string.match(rest, "^(%d+)%s*(.-)$")
    if sub == "" or sub == "list" then listItems()
    elseif sub == "on" or sub == "off" then ns.setSetting("quick", sub == "on")
    elseif sub == "open" then ns.quickOpen()
    elseif sub == "add" then
        local label, text = string.match(rest, "^(.-)%s*|%s*(.+)$")         -- "label | text" or just "text"
        if ns.quickAdd(text or rest, label) then listItems() end
    elseif sub == "edit" and n1 then if ns.quickEdit(tonumber(n1), n2) then listItems() end
    elseif sub == "label" and n1 then if ns.quickLabel(tonumber(n1), n2) then listItems() end
    elseif sub == "remove" and n1 then if ns.quickRemove(tonumber(n1)) then listItems() end
    elseif sub == "move" and n1 then if ns.quickMove(tonumber(n1), tonumber(n2)) then listItems() end
    elseif sub == "reset" then ns.quickReset(); listItems()
    elseif sub == "mode" and (rest == "hold" or rest == "toggle") then ns.setSetting("quickMode", rest)
    elseif sub == "channel" and (rest == "auto" or rest == "say" or rest == "party" or rest == "whisper") then ns.setSetting("quickChannel", rest)
    elseif sub == "editor" then ns.toggleSettings(true, "quick")
    else
        ns.print("/qs quick [list] | add [label |] <text> | edit N <text> | label N <label> | remove N | move N M | reset | on|off | mode hold|toggle | channel auto|say|party|whisper | editor | open")
    end
    if ns.refreshSettings then ns.refreshSettings() end
end

function ns._quickWheel() return frame, slots, centerText, hintText end         -- for the tests
