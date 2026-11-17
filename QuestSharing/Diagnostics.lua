-- Diagnostics.lua: /qs log, /qs errors and /qs doctor open one complete copyable diagnostic snapshot.
local ADDON, ns = ...
local C = ns.compat

local MAX_ERRORS = 30
local lastNotice = -1000

local function stamp() return date and date("%H:%M:%S") or "?" end

-- detail: more lines for the copy window (what was running, the stack); the newest one is kept
function ns.logError(source, msg, detail)
    ns.db.errors = ns.db.errors or {}
    local list = ns.db.errors
    msg = tostring(msg)
    if type(detail) == "table" and #detail == 0 then detail = nil end
    if ns.logging() then                                         -- the debug log gets every error, with its details
        ns.log("ERROR " .. tostring(source), msg)
        for _, d in ipairs(detail or {}) do ns.log("", "    " .. tostring(d)) end
    end
    local last = list[#list]
    if last and last.msg == msg then
        last.count, last.at = (last.count or 1) + 1, stamp()
        if detail then last.detail = detail end
    else
        list[#list + 1] = { at = stamp(), source = tostring(source), msg = msg, count = 1, detail = detail }
        if #list > MAX_ERRORS then table.remove(list, 1) end
    end
    if GetTime() - lastNotice > 60 then                     -- at most one notice a minute: never spam the chat
        lastNotice = GetTime()
        ns.print("an error was recorded (" .. string.sub(string.match(msg, "[^\n]*"), 1, 80) .. ") - /qs errors shows it")
    end
end

-- Lua errors raised anywhere in our files (frame scripts, key bindings, ...) also end up in the log
if seterrorhandler and geterrorhandler then
    local previous = geterrorhandler()
    seterrorhandler(function(msg)
        if type(msg) == "string" and string.find(msg, "QuestSharing", 1, true) then
            local detail = ns.cleanStack(debugstack and debugstack(2, 14, 0), 12)
            for i = 1, #detail do detail[i] = "  " .. detail[i] end
            if #detail > 0 then table.insert(detail, 1, "stack (newest call first):") end
            pcall(ns.logError, "lua", msg, detail)
        end
        if previous then return previous(msg) end
    end)
end

-- Where a refused call came from. The game fires the event while the refused call is still running, so the stack the
-- event dispatcher caught (Core.lua) shows the line that made it and everything that led there. Returns the function's
-- real name when the stack has it (the game often only says "UNKNOWN()"), our first line ("QuestItems.lua:150 paint"),
-- and the lines for the copy window.
local function blockReport(event)
    local stack = ns.cleanStack(ns.blockedStack, 16)
    ns.blockedStack = nil
    local realFn, oursAt
    for _, line in ipairs(stack) do
        if not oursAt then
            local c = string.match(line, "^%[C%]: in function [`']([^'`]+)'")
            if c and not realFn and c ~= "pcall" and c ~= "xpcall" then realFn = c end
            local at = string.match(line, "^([%w_]+%.lua:%d+):")
            if at then
                local name = string.match(line, ":%d+: in [%a ]-[`']([^'`]+)'")
                oursAt = at .. (name and (" " .. name) or "")
            end
        end
    end
    local detail = { "the game's event: " .. tostring(event) }
    local running = ns.describeRun(ns.running)
    detail[#detail + 1] = "running: " .. (running or "no timer or event of the addon (a click, a key, a hook, or the game's own code)")
    if not running and ns.lastRan then
        detail[#detail + 1] = string.format("the addon last ran %s, %.1f s before", ns.describeRun(ns.lastRan),
            GetTime() - (ns.lastRan.at or GetTime()))
    end
    detail[#detail + 1] = "in combat: " .. ((InCombatLockdown and InCombatLockdown()) and "yes" or "no")
    if not oursAt then
        detail[#detail + 1] = "no Quest Sharing line on the stack: the game noticed it later, often \"taint\" (the game's own " ..
            "code ran into something the addon had changed)"
    end
    if #stack > 0 then
        detail[#detail + 1] = "stack (newest call first):"
        for i = 1, math.min(#stack, 12) do detail[#detail + 1] = "  " .. stack[i] end
    else
        detail[#detail + 1] = "stack: the game gave none"
    end
    return realFn, oursAt, detail
end

-- When the game blocks something we tried ("Interface action failed because of an AddOn") it fires these events
-- with the name of the protected function. Writing it down tells us exactly what was blocked.
local function blocked(event, addon, fn)
    if addon ~= ADDON then ns.blockedStack = nil; return end
    local realFn, oursAt, detail = blockReport(event)
    local name = tostring(fn)
    if realFn and (fn == nil or fn == "UNKNOWN()" or fn == "UNKNOWN") then name = realFn .. "()" end
    local ours, l
    if ns.quickBlocked then ours, l = ns.quickBlocked() end
    local what = ""
    if ours then
        -- only THIS channel: the game may refuse /s from addons and still allow /w and /p (remembered)
        local ch = l.channel
        if ch and ch ~= "INVITE" then
            ns.db.chatRefused = type(ns.db.chatRefused) == "table" and ns.db.chatRefused or {}
            if not ns.db.chatRefused[ch] then
                ns.db.chatRefused[ch] = true
                ns.print("quick chat: the game does not let addons send to " .. ch .. " here, so those messages go into " ..
                    "your chat box from now on (press Enter). Other channels are still sent at once.")
            end
        end
        what = " (while sending from the quick chat ring to " .. tostring(l.channel) .. (l.channel == "WHISPER" and (" " .. tostring(l.target)) or "") .. ")"
    else
        -- what did we just try? (noted by ns.trying right before every call the game may refuse)
        local now, recent = GetTime(), {}
        for _, c in ipairs(ns.recentCalls or {}) do if now - c.at <= 1 then recent[#recent + 1] = c end end
        if #recent > 0 then
            local names = {}
            for _, c in ipairs(recent) do names[#names + 1] = c.what end
            what = " (while " .. table.concat(names, ", then ") .. ")"
            local only = (#recent == 1) and recent[1] or nil
            if ns.sharePushing and GetTime() - (ns.sharePushing.at or 0) < 1 and ns.onShareRefused then
                ns.onShareRefused()                       -- a refused share: Share.lua decides (your clicks from now on)
            elseif only and only.feature == "chat" and not ns.blockedFeatures.chat then
                ns.blockedFeatures.chat = true
                ns.db.mode = "box"
                ns.print("this game does not let addons send chat messages: from now on your messages go into the " ..
                    "chat box - just press Enter. (The automatic party messages cannot work here.)")
            elseif only and only.feature == "share" then
                -- not while a share ran (that is caught exactly, above): something else the game refused, sharing stays
            elseif only and only.feature and not ns.blockedFeatures[only.feature] and only.retry then
                ns.blockedFeatures[only.feature] = true                   -- next time straight into the chat box
                if ChatFrame_OpenChat then pcall(ChatFrame_OpenChat, only.retry) end
                ns.print("the game does not let the addon do this here: " .. only.what .. ". It is in your chat box: press Enter.")
            elseif only and only.feature and not ns.blockedFeatures[only.feature] then
                ns.blockedFeatures[only.feature] = true                   -- no second try: no second error
                ns.print("the game does not let the addon do this here: " .. only.what ..
                    ". It is switched off until you reload (/reload); /qs errors has the details.")
            end
        end
    end
    ns.logError("BLOCKED by the game", "tried to call the protected function " .. name ..
        (oursAt and (" from " .. oursAt) or "") .. what, detail)
end
ns.on("ADDON_ACTION_FORBIDDEN", blocked)
ns.on("ADDON_ACTION_BLOCKED", blocked)

-- A window with text you can select and copy ---------------------------------------------------------------------
local win, box

local function reportView(details)
    win.showingDetails = details or win.overviewText == nil
    box.reportText = win.showingDetails and win.fullText or win.overviewText
    box:SetText(box.reportText)
    box:ClearFocus()
    if box.SetCursorPosition then box:SetCursorPosition(0) end
    win.scroll:SetVerticalScroll(0)
    win.details:SetText(win.showingDetails and "Show overview" or "Show full report")
    win.hint:SetText(win.kind == "planner"
        and "Copy all selects this plan snapshot. Then press Ctrl+C (Windows) or Cmd+C (Mac)."
        or "Copy all includes every issue, error stack, setting and log line. Then press Ctrl+C (Windows) or Cmd+C (Mac).")
end

-- kind: "diagnostics" shows Clear all; other reports keep their own snapshot and optional refresh.
local W_WIDTH, W_HEIGHT = 720, 500
function ns.reportWindow(title, lines, kind, overview, details, refreshAction)
    local text = table.concat(lines, "\n")
    if not win then
        if not (CreateFrame and UIParent) then return false end
        local ok, f = pcall(CreateFrame, "Frame", "QuestSharingReport", UIParent, "BackdropTemplate")
        if not (ok and f) then ok, f = pcall(CreateFrame, "Frame", "QuestSharingReport", UIParent) end
        if not (ok and f) then return false end
        f:SetWidth(W_WIDTH)
        f:SetHeight(W_HEIGHT)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        pcall(function()
            f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
                            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            f:SetBackdropColor(0, 0, 0, 0.95)
        end)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -30)
        f.hint:SetWidth(W_WIDTH - 28)
        f.hint:SetJustifyH("LEFT")
        -- the text scrolls inside the window, however long it is
        local okS, scroll = pcall(CreateFrame, "ScrollFrame", "QuestSharingReportScroll", f, "UIPanelScrollFrameTemplate")
        if not (okS and scroll) then scroll = CreateFrame("ScrollFrame", "QuestSharingReportScroll", f) end
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -64)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 42)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local max = (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
            local now = (self.GetVerticalScroll and self:GetVerticalScroll()) or 0
            self:SetVerticalScroll(math.max(0, math.min(max, now - delta * 60)))
        end)
        f.scroll = scroll
        box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetMaxLetters(0)
        box:SetWidth(W_WIDTH - 14 - 34 - 6)
        box:SetHeight(W_HEIGHT - 90)
        if ChatFontNormal then box:SetFontObject(ChatFontNormal) end
        if box.SetFont then box:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14, "") end
        if box.SetSpacing then box:SetSpacing(4) end
        box:SetAutoFocus(false)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.reportText or "") end end)   -- read only
        if ScrollingEdit_OnCursorChanged then                    -- the game's own helper: the view follows the cursor
            box:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
            if ScrollingEdit_OnUpdate then box:SetScript("OnUpdate", function(self, dt) ScrollingEdit_OnUpdate(self, dt, scroll) end) end
        end
        scroll:SetScrollChild(box)
        -- One snapshot stays selected until the player explicitly refreshes it.
        local S = ns.style
        local function button(label, w, fn, tip)
            local b = S.button(f, label, w, fn, tip)
            b:SetHeight(22)
            return b
        end
        f.selectAll = button("Copy all", 100, function()
            reportView(true)
            box:SetFocus()
            box:HighlightText()
            win.hint:SetText("Entire report selected - press Ctrl+C (Windows) or Cmd+C (Mac), then paste it into your message.")
            ns.print("entire report selected: press Cmd+C (Mac) or Ctrl+C (Windows) to copy it")
        end, "Selects everything in this window, so one Cmd+C / Ctrl+C copies it all (the game lets addons go no further)")
        f.selectAll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
        f.details = button("Show full report", 120, function() reportView(not win.showingDetails) end,
            "Switch between the readable overview and full technical details; Copy all always includes everything")
        f.details:SetPoint("LEFT", f.selectAll, "RIGHT", 8, 0)
        f.refresh = button("Refresh", 80, function()
            if win.refreshAction then win.refreshAction() else ns.diagnostics(win.showingDetails) end
        end, "Refresh this report from current information")
        f.refresh:SetPoint("LEFT", f.details, "RIGHT", 8, 0)
        f.clear = button("Clear records", 110, function()
            QuestSharingLog, ns.db.errors = {}, {}
            ns.logSession("logs and errors cleared")
            ns.diagnostics()
        end, "Empties both saved lists, then refreshes the combined report")
        f.clear:SetPoint("LEFT", f.refresh, "RIGHT", 8, 0)
        f.test = button("Test the ring", 110, function() ns.quickTest() end,
            "Runs every slot of every ring and shows what the game really did (/qs quick test). Emotes are seen by " ..
            "players near you; messages are whispered to yourself.")
        f.test:SetPoint("LEFT", f.clear, "RIGHT", 8, 0)
        f.close = button("Close", 70, function() f:Hide() end)
        f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
        if UISpecialFrames then table.insert(UISpecialFrames, "QuestSharingReport") end
        win = f
    end
    win.title:SetText(title)
    win.kind = kind
    win.refreshAction = refreshAction
    win.fullText = text
    win.overviewText = overview and table.concat(overview, "\n") or nil
    if kind == "diagnostics" then win.clear:Show() else win.clear:Hide() end
    if kind == "diagnostics" or refreshAction then win.refresh:Show() else win.refresh:Hide() end
    if overview then win.details:Show() else win.details:Hide() end
    reportView(details == true)
    win:Show()
    return true
end

function ns._reportWindow() return win, box end

-- /qs errors --------------------------------------------------------------------------------------------------------
-- full: also what was running and the stack (for the copy window; the chat gets the short lines)
function ns.errorLines(full, all)
    local list = ns.db.errors or {}
    local out = {}
    for i = all and 1 or math.max(1, #list - 9), #list do
        local e = list[i]
        out[#out + 1] = string.format("[%s] %s%s", e.at or "?", e.source and (e.source .. ": ") or "", e.msg)
        if (e.count or 1) > 1 then out[#out + 1] = string.format("    (happened %d times)", e.count) end
        if full and type(e.detail) == "table" then
            for _, d in ipairs(e.detail) do out[#out + 1] = "    " .. tostring(d) end
        end
    end
    return out
end

function ns.errorsCommand(arg)
    if arg == "clear" then
        ns.db.errors = {}
        return ns.print("error log cleared")
    end
    ns.diagnostics()
end

-- The debug log: what the game did around the addon, the session header, /qs log ---------------------------------------
local function plainText(s) return (string.gsub(string.gsub(tostring(s or ""), "|c%x%x%x%x%x%x%x%x", ""), "|r", "")) end

-- one line saying what this session is: version, game, language, Questie
function ns.logSession(why)
    if not ns.logging() then return end
    if type(QuestSharingLog) == "table" then QuestSharingLog.lastText = nil end
    local _, build, _, iface = GetBuildInfo()
    local who = (UnitName and UnitName("player")) or "?"
    local realm = GetRealmName and GetRealmName() or "?"
    ns.log("session", string.format("%s - Quest Sharing %s | game %s (%s) | %s quest API | language %s | Questie: %s | %s-%s",
        why, tostring(ns.version), tostring(iface), tostring(build), C.modern and "modern" or "classic",
        tostring(GetLocale and GetLocale() or "?"), tostring(ns.questie and (ns.questie.source() or ("none: " ..
        tostring(ns.questie.whyMissing()))) or "none"), who, realm))
end

local lastMembers, lastTarget = nil, nil
local function members()
    local names = {}
    for _, m in ipairs(C.members()) do names[#names + 1] = m.name end
    return table.concat(names, ", ")
end
local function questName(id)
    local e = id and C.findEntry and C.findEntry(id)
    return e and e.title and ('"' .. e.title .. '"') or ("quest " .. tostring(id))
end

ns.on("PLAYER_LOGIN", function() ns.logSession("login") end)
ns.on("PLAYER_REGEN_DISABLED", function() ns.log("event", "combat starts") end)
ns.on("PLAYER_REGEN_ENABLED", function() ns.log("event", "combat ends") end)
ns.on("ZONE_CHANGED_NEW_AREA", function() ns.log("event", "zone: " .. tostring(C.zone())) end)
ns.on("GROUP_ROSTER_UPDATE", function()
    if not ns.logging() then return end
    local now = C.inGroup() and members() or ""
    if now ~= lastMembers then
        lastMembers = now
        ns.log("event", now == "" and "no party" or ((C.inRaid() and "raid: " or "party: ") .. now))
    end
end)
ns.on("PLAYER_TARGET_CHANGED", function()
    if not ns.logging() then return end
    local t = "nothing"
    if UnitExists and UnitExists("target") then
        local n = UnitName("target") or "?"
        local kind = (UnitIsPlayer and UnitIsPlayer("target")) and "player" or "creature"
        local side = (UnitIsFriend and UnitIsFriend("player", "target")) and "friendly" or "not friendly"
        t = n .. " (" .. kind .. ", " .. side .. ")"
    end
    if t ~= lastTarget then lastTarget = t; ns.log("event", "target: " .. t) end
end)
ns.on("QUEST_ACCEPTED", function(_, a, b) ns.log("event", "quest accepted: " .. questName(b or a)) end)
ns.on("QUEST_TURNED_IN", function(_, id) ns.log("event", "quest turned in: " .. tostring(id)) end)
ns.on("QUEST_REMOVED", function(_, id) ns.log("event", "quest removed: " .. tostring(id)) end)
-- what the game really showed of your own chat: the proof that a message went out (and where)
local function mine(sender)
    local me = UnitName and UnitName("player")
    return me ~= nil and type(sender) == "string" and string.match(sender, "^[^-]+") == me
end
ns.on("CHAT_MSG_WHISPER_INFORM", function(_, msg, to) ns.log("game shows", "you whispered " .. tostring(to) .. ": " .. plainText(msg)) end)
for ev, what in pairs({ CHAT_MSG_SAY = "you said", CHAT_MSG_YELL = "you yelled", CHAT_MSG_PARTY = "you told the party",
                        CHAT_MSG_PARTY_LEADER = "you told the party", CHAT_MSG_RAID = "you told the raid",
                        CHAT_MSG_INSTANCE_CHAT = "you told the group", CHAT_MSG_EMOTE = "your emote" }) do
    ns.on(ev, function(_, msg, sender) if mine(sender) then ns.log("game shows", what .. ": " .. plainText(msg)) end end)
end
ns.on("CHAT_MSG_TEXT_EMOTE", function(_, msg, sender) if mine(sender) then ns.log("game shows", plainText(msg)) end end)
-- the game's own answers: "No player named ... is currently playing", share replies, "You can't do that yet"
ns.on("CHAT_MSG_SYSTEM", function(_, msg) ns.log("game says", plainText(msg)) end)
ns.on("UI_ERROR_MESSAGE", function(_, a, b) ns.log("game error", plainText(type(b) == "string" and b or a)) end)

-- All retained lines are included; copying the report never silently drops older context.
function ns.logLines()
    local L = type(QuestSharingLog) == "table" and QuestSharingLog or {}
    local out = { string.format("debug log (%s): all %d retained lines; saved to " ..
        "WTF/Account/<account>/SavedVariables/QuestSharing.lua after /reload or logout",
        ns.logging() and "on" or "off", #L) }
    if not ns.logging() then out[#out + 1] = "the debug log is off: /qs debug on resumes recording" end
    if #L == 0 then out[#out + 1] = "the debug log is empty so far" end
    for i = 1, #L do out[#out + 1] = L[i] end
    return out
end

function ns.logCommand(arg)
    if arg == "clear" then
        QuestSharingLog = {}
        ns.logSession("log cleared")
        return ns.print("debug log cleared")
    end
    ns.diagnostics()
end

-- /qs doctor ---------------------------------------------------------------------------------------------------------
local function version()
    local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return f and f(ADDON, "Version") or "?"
end

function ns.doctorLines()
    local d = ns.db
    local out = {}
    local function add(ok, text) out[#out + 1] = (ok and "[OK] " or "[--] ") .. text end
    local _, _, _, iface = GetBuildInfo()
    local entries = C.entries()
    local inZone = 0
    for _, e in ipairs(entries) do if C.inArea(e) then inZone = inZone + 1 end end
    out[#out + 1] = string.format("Quest Sharing %s | game interface %s | %s quest API | %d quests (%d in %s)", version(),
        tostring(iface), C.modern and "modern" or "classic", #entries, inZone, C.zone())
    out[#out + 1] = "[OK] = works here, [--] = not available on this client (the note says what still works)"
    add(QuestLogPushQuest ~= nil and ns.patternCount() > 0,
        "share quests: push call " .. (QuestLogPushQuest and "yes" or "NO") .. ", " .. ns.patternCount() .. " reply messages recognised")
    add(C.modern and (C_QuestLog.IsUnitOnQuest ~= nil) or (IsUnitOnQuest ~= nil), "ask the game who has a quest (otherwise the replies decide)")
    add(ns.prefixRegistered == true, "sync with other Quest Sharing users (addon message prefix registered)")
    add(ns.hooks.tracker or ns.hooks.watchframe,
        "click a tracked quest (tracker " .. (ns.hooks.tracker and "yes" or "no") .. ", watch frame " .. (ns.hooks.watchframe and "yes" or "no")
        .. ")" .. ((ns.hooks.tracker or ns.hooks.watchframe) and "" or " - shift-click links still work"))
    add(ns.hooks.insertlink, "shift-click a quest link into the chat box")
    add(ns.hooks.qlClassic or ns.hooks.qlModern, "quest log markers (classic " .. (ns.hooks.qlClassic and "yes" or "no") .. ", modern " .. (ns.hooks.qlModern and "yes" or "no")
        .. ")" .. ((ns.hooks.qlClassic or ns.hooks.qlModern) and "" or " - the panel still works"))
    add(C.canWatch(), "tracker follows you: " .. ns.nearMode() .. " mode" .. (C.hasDistance() and "" or " (this client cannot measure distance)"))
    add(C.canMarkMobs(), "quest icons above creatures that are part of your quests" ..
        (C.canMarkMobs() and (ns.enemyNameplatesOn() and "" or " - BUT enemy nameplates are off: /qs highlight cvars on") or ""))
    add(ns.canPin(), "pin the nearest quest in the world (the game's waypoint marker)" ..
        ((ns.canPin() and not C.hasDistance()) and " - needs quest distances, which this client lacks" or ""))
    add(C.canAddFriend(), "friends (beta): add call " .. (C.canAddFriend() and "yes" or "NO") .. ", " .. ns.friendPatternCount() .. " reply messages recognised")
    local key = GetBindingKey and GetBindingKey("QUESTSHARING_QUICKCHAT")
    add(key ~= nil, "quick chat wheel: key " .. tostring(key or "not set - type /qs key V"))
    add(C.canInvite(), "invite a player from the wheel")
    add(ns.hooks.optionsEntry, "entry in the game's options (/qs settings works anyway)")
    add(ns.hooks.minimap, "minimap button")
    -- the game's own sound settings, only READ: this addon never changes them (its one sound is the good-news ping)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local function cv(n) local ok, v = pcall(get or function() end, n); return ok and v or nil end
    local all, sfx = cv("Sound_EnableAllSound"), cv("Sound_EnableSFX")
    add(all ~= "0" and sfx ~= "0", string.format("game sound: %s, effects %s (Quest Sharing never changes these; its only sound is the good-news ping, %s)",
        all == "0" and "OFF" or "on", sfx == "0" and "OFF" or "on", d.sound and "on: /qs sound off" or "off"))
    add(ns.pingSupported and ns.pingSupported(), "pings: " .. ((ns.pingSupported and ns.pingSupported())
        and ("the game's ping system is here, ping key " .. tostring(ns.pingKeyName and ns.pingKeyName() or "not set - /qs pingkey <KEY>"))
        or "this client has no ping system for addons to use"))
    local src = ns.questie and ns.questie.source()
    add(src ~= nil, "Questie: " .. (src and ("found (" .. src .. ") - \"where to get it\" works; /qs questie tests it")
        or ("not found - " .. tostring(ns.questie and ns.questie.whyMissing() or "/qs questie says why"))))
    local errs = d.errors or {}
    out[#out + 1] = (#errs == 0) and "[OK] no errors recorded" or ("[--] " .. #errs .. " error(s) recorded - see below")
    local flags = {}
    for _, k in ipairs({ "enabled", "auto", "shareNew", "chat", "announce", "click", "link", "sync", "markers", "panel", "near", "quick", "minimap", "friends" }) do
        flags[#flags + 1] = k .. "=" .. (d[k] and "on" or "off")
    end
    out[#out + 1] = "settings: " .. table.concat(flags, " ") .. string.format(" area=%s gap=%s mode=%s channel=%s", d.area, tostring(d.gap), d.quickMode, d.quickChannel)
    local refused = {}
    for ch in pairs(type(d.chatRefused) == "table" and d.chatRefused or {}) do refused[#refused + 1] = ch end
    table.sort(refused)
    out[#out + 1] = "chat the game refused for addons: " .. (#refused > 0 and (table.concat(refused, ", ") ..
        " (into the chat box instead; tick Send the message at once again to retry)") or "none")
    out[#out + 1] = "debug log: " .. (ns.logging() and "on" or "off") .. ", " ..
        tostring(type(QuestSharingLog) == "table" and #QuestSharingLog or 0) .. " lines (/qs log)"
    return out
end

local function recordedErrors()
    return type(ns.db.errors) == "table" and ns.db.errors or {}
end

local function blockedNames()
    local names = {}
    for key, value in pairs(ns.blockedFeatures) do
        if value then names[#names + 1] = key end
    end
    table.sort(names)
    return names
end

local function issueTitle(e)
    if e.source == "BLOCKED by the game" then return "The game blocked an addon action" end
    if e.source == "timer" then return "A background task failed" end
    if e.source == "lua" then return "An addon action failed" end
    return "An error was recorded"
end

-- Keep the overview readable; the full message and every stack line remain in the copied report.
local function issueSummary(e)
    local first = string.match(tostring(e.msg or ""), "[^\r\n]+") or "No message was provided"
    if #first > 220 then first = string.sub(first, 1, 220) .. "... (full message in details)" end
    return first
end

local featureNames = {
    chat = "Sending chat messages", share = "Sharing quests", mappins = "Party members on the map",
    markers = "Quest enemy markers", cvars = "Changing game settings", waypoint = "Map waypoints",
    tracker = "Updating the quest list", pin = "Marking the nearest quest", hidetracker = "Hiding the quest list",
    items = "Quest item buttons", ping = "Pings", emote = "Quick chat emotes",
}

local function setupNote(line)
    if string.find(line, "BUT enemy nameplates are off", 1, true) then
        return "Enemy health bars are reported off. Check Quest markers settings to enable them."
    end
    if string.sub(line, 1, 5) ~= "[--] " or string.find(line, "error(s) recorded", 1, true) then return nil end
    local text = string.sub(line, 6)
    if string.find(text, "click a tracked quest", 1, true) == 1 then
        return "Quest tracker clicks are not active. Use the Party quests window or shift-click quest links."
    elseif string.find(text, "quest log markers", 1, true) == 1 then
        return "Shared-quest stars are not active in this quest log. The Party quests window still works."
    elseif string.find(text, "quick chat wheel: key not set", 1, true) == 1 then
        return "Quick chat has no shortcut. Set one in General > Quick chat key, or type /qs key V."
    elseif string.find(text, "Questie:", 1, true) == 1 then
        return "Extra quest information is unavailable. /qs questie explains the optional data source."
    end
    return text
end

function ns.diagnosticOverview(checks)
    checks = checks or ns.doctorLines()
    local errors, occurrences = recordedErrors(), 0
    for _, e in ipairs(errors) do occurrences = occurrences + (e.count or 1) end
    local logCount = type(QuestSharingLog) == "table" and #QuestSharingLog or 0
    local out = {
        "QUEST SHARING - ISSUE OVERVIEW", "",
        string.format("Version %s  |  %s", tostring(ns.version), tostring(C.zone())),
        string.format("Recorded errors: %d  |  Total occurrences: %d", #errors, occurrences),
        "Recording: " .. (ns.logging() and "On" or "Off - /qs debug on resumes recording"),
        string.format("Activity log: %d retained lines included with Copy all.", logCount), "",
        "SHARE A PROBLEM",
        "Click Copy all, then press Ctrl+C (Windows) or Cmd+C (Mac).",
        "Paste it into your message and describe what you clicked and what you expected.", "",
        "RECORDED ISSUES - newest first",
    }
    if #errors == 0 then
        out[#out + 1] = "No addon errors have been recorded."
        out[#out + 1] = "If something still looks wrong, reproduce it and copy this report."
    end
    for i = #errors, 1, -1 do
        local e = errors[i]
        out[#out + 1] = string.format("%d. %s", #errors - i + 1, issueTitle(e))
        out[#out + 1] = "   " .. issueSummary(e)
        out[#out + 1] = string.format("   Last seen: %s  |  Occurrences: %d  |  Source: %s",
            tostring(e.at or "unknown"), e.count or 1, tostring(e.source or "unknown"))
        out[#out + 1] = ""
    end
    local blocked = blockedNames()
    if #blocked > 0 then
        out[#out + 1] = "FEATURES PAUSED BY THE GAME"
        for _, key in ipairs(blocked) do out[#out + 1] = "  - " .. (featureNames[key] or key) end
        out[#out + 1] = "These features stay paused until /reload. Copy the report before reloading."
        out[#out + 1] = ""
    end
    out[#out + 1] = "SETUP NOTES"
    out[#out + 1] = "Setup or client limitations below are separate from recorded addon errors."
    if ns.db.enabled == false then out[#out + 1] = "  - Quest Sharing is switched off in General settings." end
    local notes = 0
    for _, line in ipairs(checks) do
        local note = setupNote(line)
        if note then
            out[#out + 1] = "  - " .. note
            notes = notes + 1
        end
    end
    if notes == 0 then out[#out + 1] = "  No client limitations reported by the setup check." end
    out[#out + 1] = ""
    out[#out + 1] = "Full messages, stacks, setup checks, settings and activity are available in Show full report."
    return out
end

function ns.diagnosticLines(checks, overview)
    checks = checks or ns.doctorLines()
    overview = overview or ns.diagnosticOverview(checks)
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    local function section(title) add(""); add("================ " .. title .. " ================"); add("") end
    for _, line in ipairs(overview) do add(line) end
    section("ERROR DETAILS - newest first")
    local errors = recordedErrors()
    if #errors == 0 then add("No addon errors have been recorded.") end
    for i = #errors, 1, -1 do
        local e = errors[i]
        add(string.format("ISSUE %d: %s", #errors - i + 1, issueTitle(e)))
        add("  Last seen: " .. tostring(e.at or "unknown"))
        add("  Source: " .. tostring(e.source or "unknown"))
        add("  Occurrences: " .. tostring(e.count or 1))
        add("  Message:")
        add(tostring(e.msg or ""))
        if type(e.detail) == "table" and #e.detail > 0 then
            add("  Technical context and stack:")
            for _, detail in ipairs(e.detail) do add("    " .. tostring(detail)) end
        end
        add("")
    end
    section("SETUP CHECK")
    for _, line in ipairs(checks) do
        -- The complete settings follow one per line, instead of repeating a dense flag paragraph here.
        if string.sub(line, 1, 10) ~= "settings: " then add(line) end
    end
    local blocked = blockedNames()
    add("features blocked this session: " .. (#blocked == 0 and "none" or ""))
    for _, key in ipairs(blocked) do add("  " .. key) end
    section("SETTINGS - one per line")
    local labels, keys = {}, {}
    for _, row in ipairs(ns.settingRows or {}) do
        if row.key then labels[row.key] = row.label end
    end
    for key in pairs(ns.defaults) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local value = ns.db[key]
        local readable = type(value) == "boolean" and (value and "On" or "Off") or tostring(value)
        add("  " .. (labels[key] or key) .. ": " .. readable .. " [" .. key .. "=" .. tostring(value) .. "]")
    end
    section("ACTIVITY LOG - oldest to newest")
    for _, line in ipairs(ns.logLines()) do add(line) end
    add("")
    add("END OF REPORT - all retained records included")
    return lines
end

function ns.diagnostics(details)
    local checks = ns.doctorLines()
    local overview = ns.diagnosticOverview(checks)
    ns.reportWindow("Quest Sharing - diagnostics", ns.diagnosticLines(checks, overview), "diagnostics", overview, details)
end

function ns.doctor()
    ns.diagnostics()
end
