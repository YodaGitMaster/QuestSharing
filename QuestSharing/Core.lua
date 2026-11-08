-- Core.lua: settings, timers, events, chat helpers and the /qs commands.
local ADDON, ns = ...
local C = ns.compat

ns.defaults = {
    dbVersion = 3,
    enabled = true,     -- master switch
    auto = true,        -- share automatically when you join / form a party, or a new member joins
    shareNew = true,    -- also share a quest once when you accept it while in a party
    area = "zone",      -- which quests to share: "zone" (the zone you are in) or "all"
    gap = 4,            -- seconds between two shared quests inside one round (so the party is not flooded with popups)
    settle = 5,         -- seconds to wait after the party forms before sharing
    chat = false,       -- (off) announce quests in common in party chat
    click = true,       -- clicking a tracked quest fills the chat box with a status message
    link = true,        -- shift-clicking a quest link in the chat box also appends the status
    mode = "box",       -- what a click does: "box" (fill the chat box), "send" (send now), "print" (only show it to you)
    sync = true,        -- talk to other players' Quest Sharing addons (exact quest lists and progress)
    announce = false,   -- (off) say in party chat when a quest we share has all its objectives done
    markers = true,     -- mark quests your party shares in the quest log
    panel = true,       -- show the "quests in common" panel while you are in a party
    minimap = true,     -- the minimap button
    quick = true,       -- the quick chat wheel (hold a key, point, release)
    quickMode = "hold", -- "hold" (open while the key is held) or "toggle" (press to open, click a slot)
    quickChannel = "auto", -- "auto" (party if grouped, else a whisper to your target, else say), "say", "party" or "whisper" (your target)
    friends = false,    -- (BETA, off) add the people you group with to your friends list automatically
    markMobs = true,    -- a quest icon above the nameplate of creatures that are part of your quests
    nearPin = true,     -- the game's own waypoint marker follows the nearest quest (with "near")
    highlightCVars = false, -- (off) also switch on the game settings these need (enemy nameplates, object icons)
    near = true,        -- keep the quest tracker filled with the quests closest to you
    nearCount = 5,      -- how many quests the tracker keeps while "near" is on
    nearPause = 10,     -- seconds the tracker and the pin leave your choice alone after you change the tracker yourself
    nearMode = "auto",  -- "auto" (distance if the client can measure it, else zone), "distance" or "zone"
    pickup = false,     -- (off) say in party chat when I pick up a quest someone in the party has ("let's do it together?")
    selfMark = true,    -- put the star raid icon over my head while in a party (not in dungeons), so people see where I am
    mapPins = true,     -- show party members who run Quest Sharing on my world map, and send them where I am
    teamWaypoint = true, -- put a map pin where a teammate says they found the quest items
    coords = true,      -- add where I found / used the quest items to my messages, when someone in the party still needs them
    ping = true,        -- the ping key / ring slot: Attack ping on the nearest quest creature, "look here" on quest objects
    pingGap = 10,       -- anti-spam: outside combat a new ping only after this many seconds (or once the last one died)
    pingObjects = true, -- with no quest creature in sight, ping the quest object you face ("look here")
    sound = true,       -- a soft sound for good news (someone accepted a quest I shared, a party member finished a shared quest)
    panelCombat = true, -- hide the Party quests window during combat
    panelScale = 100,   -- size of the Party quests window, in percent
    quickSize = "normal", -- size of the quick chat ring: "small", "normal" or "large"
}
ns.db = {}
for k, v in pairs(ns.defaults) do ns.db[k] = v end        -- until the saved variables are loaded

-- Output -----------------------------------------------------------------------------------------
-- Calls the game may refuse ("Interface action failed because of an AddOn", "protected function UNKNOWN()") ----------
-- Right before such a call we note what we are doing. If the game then blocks something, the error log says what it
-- was, and that one feature switches itself off until /reload, so the message cannot keep coming back.
ns.recentCalls, ns.blockedFeatures = {}, {}
function ns.trying(what, feature)
    local now = GetTime and GetTime() or 0
    local list = ns.recentCalls
    list[#list + 1] = { what = what, feature = feature, at = now }
    while #list > 6 or (list[1] and now - list[1].at > 2) do table.remove(list, 1) end
end
function ns.isBlocked(feature) return feature ~= nil and ns.blockedFeatures[feature] == true end

-- the version from the .toc file
do
    local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, v = pcall(function() return f and f(ADDON, "Version") end)
    ns.version = (ok and v) or "?"
end

function ns.print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local msg = "|cff55ccffQuest Sharing:|r " .. table.concat(parts, " ")
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(msg) else print(msg) end
end

function ns.pick(list) return list[math.random(#list)] end

-- Timers: one frame, no dependency on C_Timer (older clients do not have it) -----------------------
local timers = {}
local frame = CreateFrame("Frame")
ns.frame = frame

function ns.after(delay, fn)
    local t = { at = GetTime() + delay, fn = fn }
    timers[#timers + 1] = t
    return t
end

function ns.cancel(t)
    for i = #timers, 1, -1 do if timers[i] == t then table.remove(timers, i) end end
end

local acc = 0
frame:SetScript("OnUpdate", function(_, dt)
    acc = acc + (dt or 0)
    if acc < 0.1 then return end
    acc = 0
    local now = GetTime()
    for i = #timers, 1, -1 do
        local t = timers[i]
        if t and now >= t.at then
            table.remove(timers, i)
            local ok, err = pcall(t.fn)
            if not ok then if ns.logError then ns.logError("timer", err) else ns.print("error: " .. tostring(err)) end end
        end
    end
end)

-- Events -----------------------------------------------------------------------------------------
local handlers = {}
function ns.on(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    pcall(frame.RegisterEvent, frame, event)        -- an event this client does not know must not break us
end

frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, event, ...)
        if not ok then if ns.logError then ns.logError(event, err) else ns.print("error in " .. event .. ": " .. tostring(err)) end end
    end
end)

ns.on("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    ns.newInstall = (QuestSharingDB == nil) or (next(QuestSharingDB) == nil)
    QuestSharingDB = QuestSharingDB or {}
    local savedVersion = QuestSharingDB.dbVersion or 0            -- read before the defaults fill the gaps
    for k, v in pairs(ns.defaults) do
        if QuestSharingDB[k] == nil then QuestSharingDB[k] = v end
    end
    if savedVersion < 2 then
        -- earlier versions saved "near" and "panel" as off; the new defaults have them on
        QuestSharingDB.near, QuestSharingDB.panel = true, true
    end
    if savedVersion < 3 then
        -- the automatic party chat is off now: you speak when you want to (right click a quest in the Party quests window)
        QuestSharingDB.chat, QuestSharingDB.announce, QuestSharingDB.pickup = false, false, false
    end
    QuestSharingDB.dbVersion = ns.defaults.dbVersion
    ns.db = QuestSharingDB
    if ns.refreshSettings then ns.refreshSettings() end
end)

-- A friendly hello the first time (and a short "what's new" after an update). Once per version, a few seconds after
-- login so it is not buried under the login messages.
local WHATS_NEW = "your messages now go into the chat box - just press Enter (this game does not let addons send them), and anything the game refuses is written in /qs errors and switched off"
local greeted = false
local function welcome()
    local d = ns.db
    if d.welcomed == ns.version then return end
    local S = ns.style
    local key = ns.quickKeyName and ns.quickKeyName()
    if ns.newInstall or not d.welcomed then
        ns.print(S.GOLD .. "Welcome to Quest Sharing " .. tostring(ns.version) .. "!|r Everything is on and ready for your next party.")
        ns.print("Left-click the map button (or type /qs settings) to change anything.")
        if key then ns.print("Hold " .. S.GOLD .. key .. "|r for the quick chat ring.")
        else ns.print("Tip: give the quick chat ring a key in " .. S.GOLD .. "Settings > General > Quick chat key|r.") end
    else
        ns.print(S.GOLD .. "Quest Sharing updated to " .. tostring(ns.version) .. "|r: " .. WHATS_NEW .. ". /qs settings")
    end
    d.welcomed = ns.version
end
ns.on("PLAYER_ENTERING_WORLD", function()
    if greeted then return end
    greeted = true
    ns.after(5, welcome)
end)

-- Party chat -------------------------------------------------------------------------------------
-- Splits a list of strings into messages of at most `limit` characters (the game cuts at 255).
function ns.chunk(parts, prefix, sep, limit)
    local out, cur = {}, prefix
    local first = true
    for _, p in ipairs(parts) do
        local add = (first and "" or sep) .. p
        if #cur + #add > limit and not first then
            out[#out + 1] = cur
            cur, first = prefix .. p, false
        else
            cur, first = cur .. add, false
        end
    end
    if not first then out[#out + 1] = cur end
    return out
end

-- queue of outgoing group messages, one every 2 seconds, so a burst never trips the chat throttle
local outbox, sending = {}, false
local function pump()
    local msg = table.remove(outbox, 1)
    if not msg then sending = false; return end
    if C.inGroup() and not ns.isBlocked("chat") then
        ns.trying("sending an automatic party message", "chat")
        SendChatMessage(msg, C.channel())
    end
    ns.after(2, pump)
end

-- Automatic messages (not the ones you send yourself) have a budget: at most 4 a minute, whatever happens. Better to
-- miss a line than to flood the party.
local BUDGET, WINDOW = 4, 60
local spent = {}
ns.dropped = 0
function ns.say(msg, always)
    if not always and not ns.db.chat then return false end
    -- an automatic message cannot be typed into your chat box (that would take your keys while you play): it needs
    -- "My messages: sent at once", and a game that allows it
    if ns.db.mode ~= "send" or ns.isBlocked("chat") then return false end
    local now = GetTime()
    while spent[1] and now - spent[1] > WINDOW do table.remove(spent, 1) end
    if #spent >= BUDGET then ns.dropped = ns.dropped + 1; return false end
    spent[#spent + 1] = now
    outbox[#outbox + 1] = msg
    if not sending then sending = true; pump() end
    return true
end

function ns.clearOutbox() outbox = {}; sending = false end

-- Settings: one place that changes a setting and does whatever that setting needs ---------------------------
function ns.setSetting(key, value)
    local d = ns.db
    if key == "near" then
        ns.setNear(value)                         -- saves / restores the tracker list itself
    else
        d[key] = value
        if key == "enabled" and not value then ns.stopShare("switched off") end
        if key == "markers" and ns.refreshQuestLog then ns.refreshQuestLog() end
        if (key == "panel" or key == "panelCombat") and ns.syncPanelVisibility then ns.syncPanelVisibility() end
        if key == "panelScale" and ns.applyPanelScale then ns.applyPanelScale() end
        if (key == "selfMark" or key == "enabled") and ns.syncSelfMark then ns.syncSelfMark() end
        if key == "mapPins" and ns.refreshMapPins then ns.refreshMapPins() end
        if key == "minimap" and ns.syncMinimapButton then ns.syncMinimapButton() end
        if key == "markMobs" and ns.refreshMarkers then ns.refreshMarkers() end
        if key == "nearPin" and not value and ns.releasePin then ns.releasePin() end
        if key == "highlightCVars" and ns.setHighlightCVars then ns.setHighlightCVars(value) end
        if (key == "nearMode" or key == "nearCount") and d.near and ns.nearEvaluate then ns.nearEvaluate(true) end
    end
    if ns.refreshSettings then ns.refreshSettings() end
end

function ns.resetSettings()
    for k, v in pairs(ns.defaults) do
        if k ~= "dbVersion" and ns.db[k] ~= v then ns.setSetting(k, v) end
    end
    ns.db.panelPos, ns.db.panelCollapsed = nil, nil
    if ns.resetPanelPosition then ns.resetPanelPosition(true) end
    if ns.defaultQuickItems then ns.db.quickItems = ns.defaultQuickItems() end
    ns.print("all settings are back to their defaults (everything on)")
    if ns.refreshSettings then ns.refreshSettings() end
end

-- Commands ---------------------------------------------------------------------------------------
local function onoff(arg, current)
    if arg == "on" then return true elseif arg == "off" then return false end
    return not current
end

local function status()
    local d = ns.db
    local function f(v) return v and "on" or "off" end
    ns.print(string.format("%s | auto-share %s | new-quest %s | area %s | gap %ds | chat %s | announce %s | click %s | link %s | mode %s | sync %s | markers %s | panel %s | near %s | quick %s | minimap %s | friends(beta) %s",
        d.enabled and "ON" or "OFF", f(d.auto), f(d.shareNew), d.area, d.gap, f(d.chat), f(d.announce), f(d.click), f(d.link),
        d.mode, f(d.sync), f(d.markers), f(d.panel), f(d.near), f(d.quick), f(d.minimap), f(d.friends)))
end

local help = {
    "/qs settings         open the settings window (click a line to switch it on or off)",
    "/qs share            share your quests in this area with the party now",
    "/qs stop             cancel a share that is in progress",
    "/qs on | off         switch the addon on / off",
    "/qs auto on|off      share automatically when you join a party or someone new joins",
    "/qs new on|off       share a quest once when you accept it while in a party",
    "/qs area zone|all    share only this zone's quests, or every quest",
    "/qs gap N            seconds between two shared quests (default 4)",
    "/qs chat on|off      announce quests in common in party chat",
    "/qs click on|off     clicking a tracked quest fills the chat box with a status",
    "/qs link on|off      shift-click links in the chat box get the status appended",
    "/qs mode box|send|print   what a click does: fill the chat box, send now, or only show you",
    "/qs sync on|off      exchange exact quest lists with other Quest Sharing users in the party",
    "/qs announce on|off  say in party chat when a quest we share has all its objectives done",
    "/qs pickup on|off    say when I pick up a quest someone in the party has (let's do it together?)",
    "/qs coords on|off    add where I found the quest items to my messages, when someone still needs them",
    "/qs star on|off      the star over my head while in a party, so people see where I am",
    "/qs pingkey <KEY>    the key that pings the nearest quest creature (Attack) or quest object (look here); none removes it",
    "/qs ping on|off      the ping key and the ring's ping slot",
    "/qs mappins on|off   party members running Quest Sharing on my world map (and my position to them)",
    "/qs waypoint on|off  a map pin where a teammate found the quest items",
    "/qs markers on|off   mark shared quests in the quest log",
    "/qs panel [on|off]   show / hide the \"quests in common\" panel (drag it to move it)",
    "/qs near [on|off]    keep the tracker (right-hand list) filled with the quests closest to you",
    "/qs near N           how many quests it keeps  |  /qs near mode auto|distance|zone  |  now  |  resume",
    "/qs friends          (beta) add everybody in your party to your friends list now; /qs friends on|off = automatically",
    "/qs quick            the quick chat wheel: list / add / edit / remove / move / reset the messages (see /qs quick help)",
    "/qs key [KEY]        bind the quick chat wheel to a key, e.g. /qs key V   (/qs key none removes it)",
    "/qs highlight        quest creature markers / pin the nearest quest / game settings helper (mobs|pin|cvars [on|off])",
    "/qs doctor           a report of what works on this client (opens in a window you can copy from)",
    "/qs errors [clear]   errors this addon has caused",
    "/qs minimap on|off   the minimap button",
    "/qs reset            put every setting back to its default (everything on)",
    "/qs probe            show what this game client supports (send this to the author if something fails)",
}

local BOOLS = { minimap = "minimap", auto = "auto", new = "shareNew", chat = "chat", click = "click", link = "link", pickup = "pickup", coords = "coords", star = "selfMark", mappins = "mapPins", waypoint = "teamWaypoint", sound = "sound", ping = "ping", pingobjects = "pingObjects",
                sync = "sync", announce = "announce", markers = "markers", panel = "panel" }

SLASH_QUESTSHARING1, SLASH_QUESTSHARING2 = "/qs", "/questsharing"
SlashCmdList["QUESTSHARING"] = function(msg)
    local cmd, arg = string.match(msg or "", "^(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    local d = ns.db
    if cmd == "share" then ns.startShare("manual")
    elseif cmd == "stop" then ns.stopShare("stopped by you")
    elseif cmd == "on" or cmd == "off" then ns.setSetting("enabled", cmd == "on"); status()
    elseif BOOLS[cmd] then ns.setSetting(BOOLS[cmd], onoff(arg, d[BOOLS[cmd]])); status()
    elseif cmd == "area" and (arg == "zone" or arg == "all") then ns.setSetting("area", arg); status()
    elseif cmd == "gap" and tonumber(arg) then ns.setSetting("gap", math.max(2, tonumber(arg))); status()
    elseif cmd == "mode" and (arg == "box" or arg == "send" or arg == "print") then ns.setSetting("mode", arg); status()
    elseif cmd == "near" then ns.nearCommand(arg); if arg == "" or arg == "on" or arg == "off" then status() end
    elseif cmd == "settings" or cmd == "config" or cmd == "options" then ns.toggleSettings()
    elseif cmd == "quick" then ns.quickCommand(arg)
    elseif cmd == "key" then ns.setQuickKey(arg)
    elseif cmd == "friends" then
        if arg == "on" or arg == "off" then ns.setSetting("friends", arg == "on"); status() else ns.addPartyFriends(true) end
    elseif cmd == "highlight" then ns.highlightCommand(arg)
    elseif cmd == "pingkey" then ns.setPingKey(arg)
    elseif cmd == "doctor" then ns.doctor()
    elseif cmd == "errors" then ns.errorsCommand(arg)
    elseif cmd == "reset" then ns.resetSettings()
    elseif cmd == "probe" then ns.probe()
    elseif cmd == "" or cmd == "status" then status()
    else
        for _, line in ipairs(help) do ns.print(line) end
    end
end
