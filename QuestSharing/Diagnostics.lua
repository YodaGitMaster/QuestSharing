-- Diagnostics.lua: an error log and a "doctor" report, so problems on a real game client are easy to report.
--   /qs errors        show the errors this addon has caused (and open them in a window you can copy from)
--   /qs doctor        a report of what works on this client; opens in a window: Ctrl+A, Ctrl+C, paste it to the author
local ADDON, ns = ...
local C = ns.compat

local MAX_ERRORS = 30
local lastNotice = -1000

local function stamp() return date and date("%H:%M:%S") or "?" end

function ns.logError(source, msg)
    ns.db.errors = ns.db.errors or {}
    local list = ns.db.errors
    msg = tostring(msg)
    local last = list[#list]
    if last and last.msg == msg then
        last.count, last.at = (last.count or 1) + 1, stamp()
    else
        list[#list + 1] = { at = stamp(), source = tostring(source), msg = msg, count = 1 }
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
        if type(msg) == "string" and string.find(msg, "QuestSharing", 1, true) then pcall(ns.logError, "lua", msg) end
        if previous then return previous(msg) end
    end)
end

-- When the game blocks something we tried ("Interface action failed because of an AddOn") it fires these events
-- with the name of the protected function. Writing it down tells us exactly what was blocked.
local function blocked(_, addon, fn)
    if addon == ADDON then ns.logError("BLOCKED by the game", "tried to call the protected function " .. tostring(fn)) end
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
function ns.errorLines()
    local list = ns.db.errors or {}
    local out = {}
    for i = math.max(1, #list - 9), #list do
        local e = list[i]
        out[#out + 1] = string.format("[%s] %s%s", e.at or "?", e.source and (e.source .. ": ") or "", e.msg)
        if (e.count or 1) > 1 then out[#out + 1] = string.format("    (happened %d times)", e.count) end
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
    ns.reportWindow("Quest Sharing - errors", lines)
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
    local errs = d.errors or {}
    out[#out + 1] = (#errs == 0) and "[OK] no errors recorded" or ("[--] " .. #errs .. " error(s) recorded - see below")
    local flags = {}
    for _, k in ipairs({ "enabled", "auto", "shareNew", "chat", "announce", "click", "link", "sync", "markers", "panel", "near", "quick", "minimap", "friends" }) do
        flags[#flags + 1] = k .. "=" .. (d[k] and "on" or "off")
    end
    out[#out + 1] = "settings: " .. table.concat(flags, " ") .. string.format(" area=%s gap=%s mode=%s channel=%s", d.area, tostring(d.gap), d.quickMode, d.quickChannel)
    for _, l in ipairs(ns.errorLines()) do out[#out + 1] = "error: " .. l end
    return out
end

function ns.doctor()
    local lines = ns.doctorLines()
    for _, l in ipairs(lines) do ns.print(l) end
    ns.reportWindow("Quest Sharing - doctor", lines)
end
