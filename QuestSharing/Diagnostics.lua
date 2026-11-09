-- Diagnostics.lua: an error log and a "doctor" report, so problems on a real game client are easy to report.
--   /qs errors        show the errors this addon has caused (and open them in a window you can copy from)
--   /qs doctor        a report of what works on this client; opens in a window: Ctrl+A, Ctrl+C, paste it to the author
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
        if not ns.blockedFeatures.chat then
            ns.blockedFeatures.chat = true
            ns.db.mode = "box"                                      -- the next ones go straight into the chat box
        end
        if ns.db.quickSend and l.channel ~= "INVITE" then           -- and the ring stops sending at once (remembered)
            ns.db.quickSend = false
            ns.print("quick chat: the game does not let the addon send from the ring, so its messages go into the chat " ..
                "box from now on (to try again: Settings > Quick chat > Send the message at once, then /reload)")
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

function ns.reportWindow(title, lines)
    local text = table.concat(lines, "\n")
    if not win then
        if not (CreateFrame and UIParent) then return false end
        local ok, f = pcall(CreateFrame, "Frame", "QuestSharingReport", UIParent, "BackdropTemplate")
        if not (ok and f) then ok, f = pcall(CreateFrame, "Frame", "QuestSharingReport", UIParent) end
        if not (ok and f) then return false end
        f:SetWidth(620)
        f:SetHeight(440)
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
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -30)
        hint:SetText("The text is selected: press Ctrl+C to copy it, then paste it where you need it. Esc closes this window.")
        box = CreateFrame("EditBox", nil, f)
        box:SetMultiLine(true)
        box:SetWidth(590)
        box:SetHeight(380)
        box:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -48)
        if ChatFontNormal then box:SetFontObject(ChatFontNormal) end
        box:SetAutoFocus(false)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.reportText or "") end end)   -- read only
        if UISpecialFrames then table.insert(UISpecialFrames, "QuestSharingReport") end
        win = f
    end
    win.title:SetText(title)
    box.reportText = text
    box:SetText(text)
    win:Show()
    box:HighlightText()
    box:SetFocus()
    return true
end

function ns._reportWindow() return win, box end

-- /qs errors --------------------------------------------------------------------------------------------------------
-- full: also what was running and the stack (for the copy window; the chat gets the short lines)
function ns.errorLines(full)
    local list = ns.db.errors or {}
    local out = {}
    for i = math.max(1, #list - 9), #list do
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
    local lines = ns.errorLines()
    if #lines == 0 then return ns.print("no errors recorded - good") end
    for _, l in ipairs(lines) do ns.print(l) end
    ns.print("the window has the details (what was running, the stack): Ctrl+A, Ctrl+C and send it")
    local full = { "Quest Sharing " .. tostring(ns.version) .. " | game interface " ..
        tostring(GetBuildInfo and select(4, GetBuildInfo()) or "?"), "" }
    for _, l in ipairs(ns.errorLines(true)) do full[#full + 1] = l end
    ns.reportWindow("Quest Sharing - errors", full)
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
        tostring(GetLocale and GetLocale() or "?"), tostring(ns.questie and ns.questie.source() or "none"), who, realm))
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
-- the game's own answers: "No player named ... is currently playing", share replies, "You can't do that yet"
ns.on("CHAT_MSG_SYSTEM", function(_, msg) ns.log("game says", plainText(msg)) end)
ns.on("UI_ERROR_MESSAGE", function(_, a, b) ns.log("game error", plainText(type(b) == "string" and b or a)) end)

-- /qs log: the newest lines in a window you can copy from; the whole log is in the file
local SHOW = 600
function ns.logCommand(arg)
    if arg == "clear" then
        QuestSharingLog = {}
        ns.logSession("log cleared")
        return ns.print("debug log cleared")
    end
    local L = type(QuestSharingLog) == "table" and QuestSharingLog or {}
    if #L == 0 then
        return ns.print(ns.logging() and "the debug log is empty so far" or
            "the debug log is off: Settings > General > Debug log, or /qs debug on")
    end
    local out = { string.format("Quest Sharing %s - debug log (%s): the newest %d of %d lines; all of them are in " ..
        "WTF/Account/<account>/SavedVariables/QuestSharing.lua after /reload or logout", tostring(ns.version),
        ns.logging() and "on" or "off", math.min(SHOW, #L), #L), "" }
    for i = math.max(1, #L - SHOW + 1), #L do out[#out + 1] = L[i] end
    ns.print(string.format("debug log: %d lines (%s) - the window has them: Ctrl+A, Ctrl+C", #L, ns.logging() and "on" or "off"))
    ns.reportWindow("Quest Sharing - debug log", out)
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
    add(src ~= nil, "Questie: " .. (src and ("found (" .. src .. ") - \"where to get it\" works; /qs questie tests it") or "not found - \"where to get it\" needs it; /qs questie says why"))
    local errs = d.errors or {}
    out[#out + 1] = (#errs == 0) and "[OK] no errors recorded" or ("[--] " .. #errs .. " error(s) recorded - see below")
    local flags = {}
    for _, k in ipairs({ "enabled", "auto", "shareNew", "chat", "announce", "click", "link", "sync", "markers", "panel", "near", "quick", "minimap", "friends" }) do
        flags[#flags + 1] = k .. "=" .. (d[k] and "on" or "off")
    end
    out[#out + 1] = "settings: " .. table.concat(flags, " ") .. string.format(" area=%s gap=%s mode=%s channel=%s", d.area, tostring(d.gap), d.quickMode, d.quickChannel)
    out[#out + 1] = "debug log: " .. (ns.logging() and "on" or "off") .. ", " ..
        tostring(type(QuestSharingLog) == "table" and #QuestSharingLog or 0) .. " lines (/qs log)"
    for _, l in ipairs(ns.errorLines(true)) do out[#out + 1] = "error: " .. l end
    return out
end

function ns.doctor()
    local lines = ns.doctorLines()
    for _, l in ipairs(lines) do ns.print(l) end
    ns.reportWindow("Quest Sharing - doctor", lines)
end
