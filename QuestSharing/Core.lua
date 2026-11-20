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
    panel = true,       -- show the Party quests window while you are in a party
    minimap = true,     -- the minimap button
    quick = true,       -- the quick chat wheel (hold a key, point, release)
    quickMode = "hold", -- "hold" (open while the key is held) or "toggle" (press to open, click a slot)
    quickSend = true,   -- a message picked on the ring is sent at once (off: it goes into the chat box, you press Enter)
    quickChannel = "auto", -- "auto" (party if grouped, else a whisper to your target, else say), "say", "party" or "whisper" (your target)
    friendsReserve = 5, -- friend slots the automatic friends mode always leaves free (0-20)
    friends = false,    -- (BETA, off) add the people you group with to your friends list automatically
    markMobs = true,    -- a quest icon above the nameplate of creatures that are part of your quests
    nearPin = true,     -- the game's own waypoint marker follows the nearest quest (with "near")
    highlightCVars = false, -- (off) also switch on the game settings these need (enemy nameplates, object icons)
    near = true,        -- keep the quest tracker filled with the quests closest to you
    nearCount = 5,      -- how many quests the tracker keeps while "near" is on
    nearPause = 10,     -- seconds the tracker and the pin leave your choice alone after you change the tracker yourself
    nearMode = "auto",  -- "auto" (distance if the client can measure it, else zone), "distance" or "zone"
    fishingMap = false, -- optional fishing notes on the world map
    professionGuide = true, -- explicitly requested cooking catalogue
    autoSpellRanks = false, -- opt-in: highest learned ranks on existing player spell buttons
    zoneLevels = false, -- opt-in: questing level ranges on the world map
    itemSources = false, -- opt-in: QuestieDB source hints on item tooltips
    vendorSearch = false, -- opt-in: vendor search on the world map
    myTrainers = true, -- your class and profession trainers on zone and continent maps (needs QuestieDB)
    travelFaction = "mine", -- travel map: "mine" (own faction), "all", "Alliance" or "Horde" (neutral routes always show)
    travelMap = true, -- dungeon entrances, boats, zeppelins and nearest towns on the world map
    questPlanner = false, -- opt-in: prerequisite-aware quest route suggestions
    questPlannerGoal = "all", -- quest guide aim: "all" (complete the zone), "xp", "selected" (questPlannerSelected) or "budget"
    questPlannerBudget = 30, -- minutes for the "budget" goal (5-240)
    questPlannerSelected = "", -- quest IDs for the "selected" goal, e.g. "123, 456"
    questPlannerScope = "all", -- quest levels the guide plans: "all" or "green-yellow"
    routeAllFlights = false, -- (off) dungeon "Get them all" route: plan as if every flight path were known
    campMap = false, -- opt-in: the Quest guide's shared camps as circles on the world map
    autoAcceptQuests = false, -- opt-in: accept quests when their offer is shown
    autoCompleteQuests = false, -- opt-in: finish safe quest turn-ins without a reward decision
    bagMarks = true,    -- quest items marked in the bags: gold = a quest of this zone, blue = a quest elsewhere
    hideTracker = false, -- hide the game's quest tracker (outside fights)
    bagBookmarks = true, -- point at a bag item and press Space: it is bookmarked and never sold by the addon
    autoSellGray = false, -- (off) sell every gray item when a vendor window opens (bookmarked and quest items stay)
    autoSortBags = false, -- (off) arrange all bags, backpack included, by topic once they have been quiet for a moment
    sortBy = "topic",   -- how bags are arranged: "topic", "quality" (best first) or "name" (A to Z)
    sortBags = "all",   -- which bags are arranged: "all", "bags" (all but the backpack) or "backpack"
    sortFrom = "start", -- where the items gather: "start" (empty slots at the end) or "end" (empty slots at the start)
    sortDelay = 3,      -- seconds the bags must stay quiet before the automatic arrangement starts (1-30)
    sortKeepBookmarked = false, -- (off) bookmarked items stay in their slot while the bags are arranged
    sortLayout = "packed", -- "packed" (items one after another) or "rows" (each group starts on a new row)
    sortView = "bags",  -- how the bags are shown, for the rows: "bags" (the game's bag windows, 4 a row) or "onebag"
    sortColumns = 8,    -- slots a row in a one-bag view (a bag addon or combined bags), 4-16
    sortCraftRows = true, -- crafting materials split into one group per kind (cloth, herbs, metal...)
    sortMergeStacks = true, -- partial stacks of the same item are joined before the bags are arranged
    chatLockNotice = 20, -- seconds between two "the chat box is locked" notes while you fight (5-120)
    chatLock = false,   -- (off) no chat typing box while you are in a fight
    aggroPlates = false, -- (off) tanks: my aggro % as a number on enemy nameplates while I fight
    debug = true,       -- diagnostic actions and outcomes, saved on /reload or logout
    shareByClick = false, -- share only on my clicks (set by itself when the game refuses an automatic share)
    pickup = false,     -- (off) say in party chat when I pick up a quest someone in the party has ("let's do it together?")
    mapPins = true,     -- show party members who run Quest Sharing on my world map, and send them where I am
    teamWaypoint = true, -- put a map pin where a teammate says they found the quest items
    coords = true,      -- add where I found / used the quest items to my messages, when someone in the party still needs them
    ping = true,        -- the ping key / ring slot: Attack ping on the nearest quest creature, "look here" on quest objects
    pingGap = 10,       -- anti-spam: outside combat a new ping only after this many seconds (or once the last one died)
    pingObjects = true, -- with no quest creature in sight, ping the quest object you face ("look here")
    questItems = true,  -- icons next to the quests in the tracker for usable quest items in your bags, and the item key
    sound = true,       -- a soft sound for good news (someone accepted a quest I shared, a party member finished a shared quest)
    panelCombat = true, -- hide the Party quests window during combat
    panelSolo = true,   -- show the Party quests window when you are not in a party too (your quests of the zone)
    panelScale = 100,   -- size of the Party quests window, in percent
    quickSize = "normal", -- size of the quick chat ring: "small", "normal" or "large"
    lfgHealer = true,   -- party finder button: invite solo players listed as healer
    lfgTank = false,    -- ... listed as tank
    lfgDps = false,     -- ... listed as damage
    lfgWatch = false,   -- (off) also invite from searches made in the game's own party finder window
    lfgSupercharge = false, -- (off) party finder: invite every match at once, the first to accept gets the spot
    lfgWhisper = true,  -- party finder: whisper each invited player which dungeon the invite is for
    lfgWhisperText = "Hi! I invited you to my group for {dungeon} as {role}.", -- {dungeon} and {role} are filled in
    lfgMinLevel = 1,    -- party finder: lowest character level to invite
    lfgMaxLevel = 60,   -- ... highest character level to invite
    lfgMinIlvl = 0,     -- ... lowest average item level to invite (0 = any)
    lfgUnknown = "invite", -- ... when the item level is unknown: "invite" or "skip" (only with a minimum)
    lfgAskIlvl = true,  -- ... ask Quest Sharing users for their item level first (waits up to 2 s)
    ilvlKeepDays = 14,  -- days a remembered item level stays valid (1-60)
    lfgReinvite = 5,    -- party finder: minutes before a player we invited (or skipped) is looked at again (1-30)
    ilvlInspect = true, -- remember the item level of players I target or point at nearby (inspect)
    ilvlShare = true,   -- tell other Quest Sharing users my item level and the ones I remember
}
ns.db = {}
for k, v in pairs(ns.defaults) do ns.db[k] = v end        -- until the saved variables are loaded

-- Output -----------------------------------------------------------------------------------------
-- Calls the game may refuse ("Interface action failed because of an AddOn", "protected function UNKNOWN()") ----------
-- Right before such a call we note what we are doing. If the game then blocks something, the error log says what it
-- was, and that one feature switches itself off until /reload, so the message cannot keep coming back.
-- The debug log (Settings > Errors & logs > Record addon actions, /qs debug on|off) -------------------------------------------------
-- Every action and its outcome, errors or not, one line each: "12:34:56 ring: "Thanks!" -> WHISPER Lia (sent)".
-- Kept in QuestSharingLog, which the game writes to WTF/Account/<account>/SavedVariables/QuestSharing.lua when you
-- /reload or log out. On by default; /qs debug off stops recording. The same line again becomes one line
-- with a count ("(x5)"); the oldest lines go once there are more than LOG_MAX.
local LOG_MAX = 1000
ns.LOG_MAX = LOG_MAX
function ns.logging() return ns.db ~= nil and ns.db.debug == true end
-- the visible text of game markup: links as their [name], no colours or icons
local function visible(s)
    if not string.find(s, "|", 1, true) then return s end
    s = string.gsub(s, "|H.-|h(.-)|h", "%1")
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    s = string.gsub(s, "|T.-|t", "")
    return s
end

-- kind "" : a line of its own (the details under an error)
function ns.log(kind, text)
    if not (ns.db and ns.db.debug) then return end
    if type(QuestSharingLog) ~= "table" then QuestSharingLog = {} end
    local L = QuestSharingLog
    local line = visible((kind and kind ~= "") and (tostring(kind) .. ": " .. tostring(text)) or tostring(text))
    if L.lastText == line and #L > 0 then
        L.repeats = (L.repeats or 1) + 1
        L[#L] = L.lastStamp .. " " .. line .. " (x" .. L.repeats .. ")"
        return
    end
    local stamp = date and date("%H:%M:%S") or "?"
    L[#L + 1] = stamp .. " " .. line
    L.lastText, L.lastStamp, L.repeats = line, stamp, 1
    if #L > LOG_MAX + 300 then                                   -- drop the oldest in one go, not one by one
        local keep, n = {}, #L
        for i = n - LOG_MAX + 1, n do keep[#keep + 1] = L[i] end
        for i = n, 1, -1 do L[i] = nil end
        for i = 1, #keep do L[i] = keep[i] end
    end
end

ns.recentCalls, ns.blockedFeatures = {}, {}
function ns.trying(what, feature, retry)          -- retry: what to type into the chat box if the game refuses
    ns.log("call", what)
    local now = GetTime and GetTime() or 0
    local list = ns.recentCalls
    list[#list + 1] = { what = what, feature = feature, at = now, retry = retry }
    while #list > 6 or (list[1] and now - list[1].at > 2) do table.remove(list, 1) end
end
function ns.isBlocked(feature) return feature ~= nil and ns.blockedFeatures[feature] == true end
-- may the addon send to this channel at once? (not after the game refused chat, or refused this channel from the ring)
function ns.chatAllowed(channel)
    if ns.isBlocked("chat") then return false end
    local r = ns.db and ns.db.chatRefused
    return not (channel and type(r) == "table" and r[channel])
end

-- the version from the .toc file
do
    local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, v = pcall(function() return f and f(ADDON, "Version") end)
    ns.version = (ok and v) or "?"
end

function ns.print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    -- gold (S.GOLD; Style.lua loads after this file): blue is kept for "quest elsewhere" in the bag marks
    local msg = "|cffffd100Quest Sharing:|r " .. table.concat(parts, " ")
    if ns.db and ns.db.debug then ns.log("shown", table.concat(parts, " ")) end   -- what you were told goes in too
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(msg) else print(msg) end
end

function ns.pick(list) return list[math.random(#list)] end

-- "1 bookmark removed" / "3 bookmarks removed" (the chat line after removing every bag bookmark)
function ns.bookmarksRemovedText(n)
    n = tonumber(n) or 0
    if n == 0 then return "no bookmarks to remove" end
    return string.format("%d bookmark%s removed", n, n == 1 and "" or "s")
end

-- Stacks, for the error log: what called what ------------------------------------------------------------------------
-- The game's debugstack() lines, readable: our files as "QuestItems.lua:150: in function 'paint'", other addons and the
-- game's own code with their folder ("Blizzard_ObjectiveTracker/...", "FrameXML/...").
function ns.cleanStack(raw, max)
    local out = {}
    if type(raw) ~= "string" then return out end
    for line in string.gmatch(raw, "[^\n]+") do
        line = string.gsub(line, '%[string "@?([^"]*)"%]', "%1")
        line = string.gsub(line, "^%[([^%]]+%.lua)%]", "%1")              -- "[Quick.lua]:382:" (newer clients)
        line = string.gsub(line, "^=?%[C%]:?%-?%d*:", "[C]:")              -- "=[C]:-1: in function ..." -> "[C]: in ..."
        line = string.gsub(line, "Interface[/\\]AddOns[/\\]", "")
        line = string.gsub(line, "Interface[/\\]FrameXML[/\\]", "FrameXML/")
        line = string.gsub(line, ADDON .. "[/\\]", "")
        line = string.gsub(line, "^%s+", "")
        if line ~= "" and line ~= "stack traceback:" and line ~= "..." then out[#out + 1] = line end
        if max and #out >= max then break end
    end
    return out
end

-- What the addon is running right now (a timer or an event; nil for clicks, keys, hooks and the game's own code), and
-- what it ran last: when the game refuses something, this says which part of the addon was at work.
ns.running, ns.lastRan = nil, nil

-- "a timer set at QuestItems.lua:342" / "the event QUEST_LOG_UPDATE"
function ns.describeRun(r)
    if not r then return nil end
    if r.event then return "the event " .. r.event end
    local at = r.from and ns.cleanStack(r.from, 1)[1]
    at = at and string.match(at, "^(.-:%d+):") or at
    return "a timer" .. (at and (" set at " .. at) or "")
end

-- Lua errors in timers and events keep their stack (pcall would lose it)
local function withStack(err)
    return { msg = err, stack = debugstack and debugstack(2, 14, 0) or nil }
end

local function logFailure(source, err)
    local msg, detail = err, nil
    if type(err) == "table" then
        msg, detail = err.msg, ns.cleanStack(err.stack, 12)
        for i = 1, #detail do detail[i] = "  " .. detail[i] end
        if #detail > 0 then table.insert(detail, 1, "stack (newest call first):") end
    end
    if ns.logError then ns.logError(source, msg, detail) else ns.print("error in " .. tostring(source) .. ": " .. tostring(msg)) end
end

-- Timers: one frame, no dependency on C_Timer (older clients do not have it) -----------------------
local timers = {}
local frame = CreateFrame("Frame")
ns.frame = frame

function ns.after(delay, fn)
    -- from: the line that set it, kept raw (made readable only when an error needs it)
    local t = { at = GetTime() + delay, fn = fn, from = debugstack and debugstack(2, 1, 0) or nil }
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
            local run = { from = t.from }
            ns.running = run
            local ok, err = xpcall(t.fn, withStack)
            ns.running = nil
            run.at, ns.lastRan = GetTime(), run
            if not ok then logFailure("timer", err) end
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

local BLOCK_EVENTS = { ADDON_ACTION_BLOCKED = true, ADDON_ACTION_FORBIDDEN = true }

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    local outer = ns.running
    if BLOCK_EVENTS[event] then
        -- the game refuses a call right as it is made: everything above this function is what made it
        ns.blockedStack = debugstack and debugstack(2, 24, 0) or nil
    else
        ns.running = { event = event }
    end
    local n, args = select("#", ...), { ... }
    for _, fn in ipairs(list) do
        local ok, err = xpcall(function() return fn(event, unpack(args, 1, n)) end, withStack)
        if not ok then logFailure(event, err) end
    end
    if not BLOCK_EVENTS[event] then
        local run = ns.running
        ns.running = outer
        if run then run.at, ns.lastRan = GetTime(), run end
    end
end)

ns.on("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    ns.newInstall = (QuestSharingDB == nil) or (next(QuestSharingDB) == nil)
    QuestSharingDB = QuestSharingDB or {}
    for k, v in pairs(ns.defaults) do
        if QuestSharingDB[k] == nil then QuestSharingDB[k] = v end
    end
    QuestSharingDB.dbVersion = ns.defaults.dbVersion
    QuestSharingDB.itemButton, QuestSharingDB.itemButtonPos = nil, nil     -- the on-screen item button was removed
    ns.db = QuestSharingDB
    if ns.refreshSettings then ns.refreshSettings() end
end)

-- A friendly hello the first time (and a short "what's new" after an update). Once per version, a few seconds after
-- login so it is not buried under the login messages.
-- RELEASE CHECKLIST: before each release, rewrite WHATS_NEW as one short line about the newest features of that
-- release (the top of CHANGELOG.md), in the words the Settings window uses.
local WHATS_NEW = "new Bags and Party finder pages, a search box at the top of the settings, and tank aggro on enemy nameplates (General > During a fight)"
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
        else ns.print("Tip: give the quick chat ring a key in " .. S.GOLD .. "Settings > Quick chat > Quick chat key|r.") end
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
    if C.inGroup() and ns.chatAllowed(C.channel()) then
        ns.trying("sending an automatic party message", "chat")
        ns.log("chat", "automatic message to " .. tostring(C.channel()) .. ": " .. msg)
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
    if ns.db.mode ~= "send" or not ns.chatAllowed(C.channel()) then return false end
    local now = GetTime()
    while spent[1] and now - spent[1] > WINDOW do table.remove(spent, 1) end
    if #spent >= BUDGET then ns.dropped = ns.dropped + 1; return false end
    spent[#spent + 1] = now
    outbox[#outbox + 1] = msg
    if not sending then sending = true; pump() end
    return true
end

-- Settings: one place that changes a setting and does whatever that setting needs ---------------------------
-- A setting as players read it: its Settings label, its value and where it is.
-- "Sell gray items when I open a vendor: on (Settings > Bags)"
local function settingRow(key)
    for _, r in ipairs(ns.settingRows or {}) do if r.key == key then return r end end
end
function ns.settingLine(key)
    local v, row = ns.db[key], settingRow(key)
    local path = ns.settingPath and ns.settingPath(key) or "Settings"
    local where, label = string.match(path, "^(Settings > .-) > (.+)$")
    local shown = (type(v) == "boolean" and (v and "on" or "off")) or (row and row.names and row.names[v]) or tostring(v)
    return (label or (row and row.label) or tostring(key)) .. ": " .. shown .. " (" .. (where or path) .. ")"
end

-- The automatic party messages go out only with "Send immediately" (ns.say): switching one on says so.
local PARTY_CHAT = { chat = true, announce = true, pickup = true }
local function sendNote(key)
    local row, mode = settingRow(key), settingRow("mode")
    local modeName = mode and mode.names and mode.names[ns.db.mode] or tostring(ns.db.mode)
    return string.format("%s: nothing is sent to the party while \"How to send quest progress messages\" is %s - " ..
        "choose Send immediately in Settings > General, or type /qs mode send", row and row.label or key, modeName)
end

function ns.setSetting(key, value)
    local d = ns.db
    if key == "debug" and not value then ns.log("setting", "debug = false (the log stops here)") end
    ns.log("setting", tostring(key) .. " = " .. tostring(value))
    if key == "near" then
        ns.setNear(value)                         -- saves / restores the tracker list itself
    else
        d[key] = value
        if key == "debug" and value and ns.logSession then ns.logSession("debug log on") end
        if PARTY_CHAT[key] and value and d.mode ~= "send" then ns.print(sendNote(key)) end
        if (key == "fishingMap" or key == "enabled") and ns.fishing then ns.fishing.refresh() end
        if (key == "professionGuide" or key == "enabled") and ns.professions then ns.professions.settingChanged() end
        if key == "enabled" and ns.rewards then ns.rewards.settingChanged() end
        if (key == "autoSpellRanks" or key == "enabled") and ns.spellRanks then ns.spellRanks.settingChanged() end
        if (key == "zoneLevels" or key == "enabled") and ns.zoneLevels then ns.zoneLevels.refresh() end
        if (key == "itemSources" or key == "enabled") and ns.itemSources then ns.itemSources.refresh() end
        if (key == "itemSources" or key == "enabled") and ns.gatherSources then ns.gatherSources.refresh() end
        if (key == "vendorSearch" or key == "enabled") and ns.vendorMap then ns.vendorMap.refresh() end
        if (key == "travelMap" or key == "travelFaction" or key == "myTrainers" or key == "enabled") and ns.travelMap then ns.travelMap.refresh() end
        if key == "questPlanner" and ns.questPlanner then ns.questPlanner.settingChanged(value) end
        -- Goal, time limit, quest IDs and level scope (Settings > Quest guide): the planner rereads them and replans.
        if type(key) == "string" and key ~= "questPlanner" and string.sub(key, 1, 12) == "questPlanner"
            and ns.questPlanner and type(ns.questPlanner.applySettings) == "function" then ns.questPlanner.applySettings() end
        if key == "enabled" and ns.questPlanner then ns.questPlanner.masterChanged(value) end
        if (key == "campMap" or key == "enabled") and ns.campMap then ns.campMap.refresh() end
        if key == "enabled" and not value and ns.adventure then ns.adventure.close() end
        if key == "enabled" and not value and ns.loot then ns.loot.close() end
        if key == "enabled" and not value and ns.dungeonQuests then ns.dungeonQuests.close() end
        if (key == "bagMarks" or key == "enabled") and ns.refreshBagMarks then ns.refreshBagMarks() end
        if (key == "bagBookmarks" or key == "autoSortBags" or key == "enabled" or (type(key) == "string" and string.sub(key, 1, 4) == "sort")) and ns.bagTools then ns.bagTools.refresh() end
        if (key == "chatLock" or key == "enabled") and ns.chatLock then ns.chatLock.refresh() end
        if (key == "aggroPlates" or key == "enabled") and ns.aggro then ns.aggro.settingChanged() end
        if (key == "hideTracker" or key == "enabled") and ns.applyTrackerHidden then ns.applyTrackerHidden() end
        if key == "quickSend" and value then               -- you ask for it again: refused channels get another try
            if type(d.chatRefused) == "table" and next(d.chatRefused) then
                d.chatRefused = {}
                ns.print("quick chat: channels the game refused before get another try")
            end
            ns.blockedFeatures.chat = nil
        end
        if key == "enabled" and not value then ns.stopShare("switched off") end
        if key == "markers" and ns.refreshQuestLog then ns.refreshQuestLog() end
        if (key == "panel" or key == "panelCombat" or key == "panelSolo") and ns.syncPanelVisibility then ns.syncPanelVisibility() end
        if key == "panelScale" and ns.applyPanelScale then ns.applyPanelScale() end
        if key == "mapPins" and ns.refreshMapPins then ns.refreshMapPins() end
        if key == "questItems" and ns.applyQuestItems then ns.applyQuestItems() end
        if key == "minimap" and ns.syncMinimapButton then ns.syncMinimapButton() end
        if string.sub(key, 1, 3) == "lfg" and ns.lfgFinder then ns.lfgFinder.refresh() end
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
    ns.db.quickPages, ns.db.quickPage = nil, nil
    ns.print("all settings and the quick chat messages are back to their defaults")
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
    "/qs loot [search]    search instance drops and the boss or creature that drops each item",
    "/qs dungeons [search]  browse dungeon quests, pickup locations and prerequisites",
    "/qs lfg              party finder: search your listing's dungeon and invite (also: healer|tank|dps on|off, ilvl <n>, level <low> <high>, unknown invite|skip, watch on|off)",
    "/qs ilvl             your item level and how many players' item levels are remembered",
    "/qs adventure [quest ID or title]  open the Quest invitation window (any chat)",
    "/qs fishing [on|off]  Fishing spots on the world map; no argument opens the Fishing spots window",
    "/qs cooking          recipes, acquisition sources and ingredient farming hints",
    "/qs professions [on|off]  cooking recipe list in the profession window; no argument opens it, on/off toggles it",
    "/qs rewards          browse quest reward equipment for your class, level and faction",
    "/qs plan [refresh|next|follow|busy|hide|on|off]  open the Quest guide, replan, waypoint to the next stop, walk there with Shortest Path Forever, mark the selected camp busy, close it",
    "/qs plan camps [on|off|table]  shared camps on the world map (blue = 2+ quests), or the camps table",
    "/qs plan all|xp|budget <minutes>|selected <quest IDs or names>  what the route aims for: complete zone, quest XP/hour, time limit, chosen quests",
    "/qs plan range|unrestricted   only green and yellow quests, or every level  |  /qs plan why|options|debug   report, Quest guide settings, full details",
    "/qs settings         open the settings window (click a line to switch it on or off)",
    "/qs status           the main switches in one line  |  /qs help   this list",
    "/qs map              the world map switches and where they are in the settings",
    "/qs share            share your quests in this area with the party now",
    "/qs stop             cancel a share that is in progress",
    "/qs on | off         switch the addon on / off",
    "/qs auto on|off      share automatically when you join a party or someone new joins",
    "/qs new on|off       share a quest once when you accept it while in a party",
    "/qs area zone|all    share only this zone's quests, or every quest",
    "/qs gap N            seconds between two shared quests, 2-30 (default 4)",
    "/qs chat on|off      announce quests in common in party chat",
    "/qs click on|off     clicking a tracked quest fills the chat box with a status",
    "/qs link on|off      shift-click links in the chat box get the status appended",
    "/qs mode box|send|print   what a click does: fill the chat box, send now, or only show you",
    "/qs sync on|off      exchange exact quest lists with other Quest Sharing users in the party",
    "/qs announce on|off  say in party chat when a quest we share has all its objectives done",
    "/qs pickup on|off    say when I pick up a quest someone in the party has (let's do it together?)",
    "/qs coords on|off    add where I found the quest items to my messages, when someone still needs them",
    "/qs shareclick on|off share only when I click Share (on by itself where the game refuses automatic sharing)",
    "/qs bagmarks on|off  mark quest items in your bags: gold for quests here, blue for quests elsewhere (the bank can keep them)",
    "/qs hidetracker on|off hide the game's quest tracker (outside fights)",
    "/qs bookmarks [on|off|list|clear]  Space on a bag item bookmarks it (never sold); list or clear the bookmarks",
    "/qs sellgray on|off  sell the gray items when a vendor opens (bookmarked and quest items stay)",
    "/qs sort [on|off]    arrange your bags now; on/off = do it by itself when the bags change",
    "/qs sort by topic|quality|name, bags all|bags|backpack, from start|end, keep on|off   how and what to arrange",
    "/qs chatlock on|off  no chat typing box while you are in a fight",
    "/qs sound on|off     a soft sound when someone accepts your quest or a teammate finishes a shared quest",
    "/qs aggro on|off     tanks: my aggro % as a number on enemy nameplates while I fight",
    "/qs debug on|off     the debug log: every action and its outcome, saved to the addon's file on /reload or logout",
    "/qs log [clear]      all diagnostics in one copyable window (clear empties the debug log)",
    "/qs memory           how much memory Quest Sharing and QuestieDB use, and which catalogues are loaded",
    "/qs memory purge     free every catalogue read from QuestieDB (each reads again when next used)",
    "/qs pingkey <KEY>    the key that pings the nearest quest creature (Attack) or quest object (look here); none removes it",
    "/qs itemkey <KEY>    the key that uses the item of your nearest quest (a torch, a flare...); none removes it",
    "/qs items on|off     item icons next to the quests in the tracker, and the quest item key",
    "/qs cleanup         review leftover quest items in your bags and delete confirmed stacks",
    "/qs gather [item]    why an item does or does not show where to gather it (default: the last item you hovered)",
    "/qs questie          does Quest Sharing read Questie's quest database? (with a real lookup from your quest log)",
    "/qs ping             checks every step of the ping key (and says where it stops); /qs ping on|off switches it",
    "/qs pingobjects on|off  also ping the quest object you face when no quest enemy is near",
    "/qs mappins on|off   party members running Quest Sharing on my world map (and my position to them)",
    "/qs waypoint on|off  a map pin where a teammate found the quest items",
    "/qs markers on|off   mark shared quests in the quest log",
    "/qs panel [on|off]   show the Party quests window (off hides it; drag it to move it)",
    "/qs solo on|off      also show the Party quests window when you play alone",
    "/qs near [on|off]    keep the tracker (right-hand list) filled with the quests closest to you",
    "/qs near N           how many quests it keeps  |  /qs near mode auto|distance|zone  |  now  |  resume",
    "/qs friends          (beta) add everybody in your party to your friends list now; /qs friends on|off = automatically",
    "/qs quick            the quick chat wheel: list / add / edit / remove / move / reset the messages (see /qs quick help)",
    "/qs key [KEY]        bind the quick chat wheel to a key, e.g. /qs key V   (/qs key none removes it)",
    "/qs highlight        quest creature markers / pin the nearest quest / game settings helper (mobs|pin|cvars [on|off])",
    "/qs doctor           setup, errors and debug log in one copyable report",
    "/qs errors [clear]   open all diagnostics (clear empties recorded errors)",
    "/qs minimap on|off   the minimap button",
    "/qs reset            put every setting and the quick chat messages back to their defaults",
    "/qs probe            show what this game client supports (send this to the author if something fails)",
}

local BOOLS = { minimap = "minimap", auto = "auto", new = "shareNew", chat = "chat", click = "click", link = "link", solo = "panelSolo", pickup = "pickup", coords = "coords", shareclick = "shareByClick", debug = "debug", bagmarks = "bagMarks", hidetracker = "hideTracker", sellgray = "autoSellGray", chatlock = "chatLock", aggro = "aggroPlates", mappins = "mapPins", waypoint = "teamWaypoint", sound = "sound", ping = "ping", pingobjects = "pingObjects", items = "questItems",
                sync = "sync", announce = "announce", markers = "markers", panel = "panel" }

-- /qs map: the world map switches, wherever they are in the settings
local MAP_SWITCHES = { "zoneLevels", "travelMap", "travelFaction", "myTrainers", "mapPins", "teamWaypoint", "vendorSearch",
                       "itemSources", "fishingMap" }
-- after a command changed a setting: one line naming it as the Settings window does
local function said(key) ns.print(ns.settingLine(key)) end
local SORT_USAGE = "usage: /qs sort by topic|quality|name, bags all|bags|backpack, from start|end, layout packed|rows, " ..
    "view bags|onebag, columns 4-16, crafts on|off, merge on|off, keep on|off"

SLASH_QUESTSHARING1, SLASH_QUESTSHARING2 = "/qs", "/questsharing"
SlashCmdList["QUESTSHARING"] = function(msg)
    ns.log("command", "/qs " .. tostring(msg or ""))
    local cmd, arg = string.match(msg or "", "^(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    local d = ns.db
    if cmd == "share" then ns.shareClick()
    elseif cmd == "loot" then ns.loot.open(arg)
    elseif cmd == "dungeons" or cmd == "dungeonquests" then ns.dungeonQuests.open(arg)
    elseif cmd == "plan" then ns.questPlanner.command(arg)
    elseif cmd == "cleanup" then ns.questCleanup.open()
    elseif cmd == "sort" then
        local what, val = string.match(string.lower(arg or ""), "^(%S+)%s*(%S*)$")
        local SORT_OPTS = { by = { "sortBy", topic = 1, quality = 1, name = 1 }, bags = { "sortBags", all = 1, bags = 1, backpack = 1 },
                            from = { "sortFrom", start = 1, ["end"] = 1 }, layout = { "sortLayout", packed = 1, rows = 1 },
                            view = { "sortView", bags = 1, onebag = 1 } }
        local SORT_SWITCHES = { keep = "sortKeepBookmarked", crafts = "sortCraftRows", merge = "sortMergeStacks" }
        local cols = what == "columns" and tonumber(val)
        if arg == "on" or arg == "off" then ns.setSetting("autoSortBags", arg == "on"); said("autoSortBags")
        elseif what and SORT_SWITCHES[what] and (val == "on" or val == "off") then
            ns.setSetting(SORT_SWITCHES[what], val == "on"); said(SORT_SWITCHES[what])
        elseif cols and cols >= 4 and cols <= 16 and cols == math.floor(cols) then
            ns.setSetting("sortColumns", cols); said("sortColumns")
        elseif what and SORT_OPTS[what] then
            local o = SORT_OPTS[what]
            if o[val] then ns.setSetting(o[1], val); said(o[1])
            else ns.print(SORT_USAGE) end
        elseif what == "columns" or (what and SORT_SWITCHES[what]) then ns.print(SORT_USAGE)
        else ns.bagTools.sort(true) end
    elseif cmd == "lfg" or cmd == "finder" then ns.lfgInvite.command(arg)
    elseif cmd == "ilvl" then ns.itemLevel.command(arg)
    elseif cmd == "bookmarks" then
        if arg == "on" or arg == "off" then ns.setSetting("bagBookmarks", arg == "on"); said("bagBookmarks")
        elseif arg == "clear" then ns.print(ns.bookmarksRemovedText(ns.bagTools.clearBookmarks()))
        elseif arg == "list" then
            local l = ns.bagTools.listBookmarks()
            ns.print(#l == 0 and "no bookmarked items (point at a bag item and press Space)" or ("bookmarked: " .. table.concat(l, ", ")))
        else ns.setSetting("bagBookmarks", not d.bagBookmarks); said("bagBookmarks") end
    elseif cmd == "questmap" then ns.print("quest symbols on the world map and minimap have been removed")
    elseif cmd == "adventure" then ns.adventure.command(arg)
    elseif cmd == "gather" then ns.gatherSources.command(arg)
    elseif cmd == "cooking" then ns.professions.open()
    elseif cmd == "professions" then
        if arg == "on" or arg == "off" then ns.setSetting("professionGuide", arg == "on"); said("professionGuide")
        else ns.professions.open() end
    elseif cmd == "rewards" then ns.rewards.open()
    elseif cmd == "fishing" then
        if arg == "on" or arg == "off" then ns.setSetting("fishingMap", arg == "on"); said("fishingMap")
        else ns.fishing.open() end
    elseif cmd == "stop" then ns.stopShare("stopped by you")
    elseif cmd == "on" or cmd == "off" then ns.setSetting("enabled", cmd == "on"); said("enabled")
    elseif cmd == "ping" and (arg == "" or arg == "test" or arg == "status") then
        for _, l in ipairs(ns.pingReport()) do ns.print(l) end
    elseif cmd == "panel" and arg == "" then ns.setSetting("panel", true); said("panel") -- no argument shows it; the x hides it
    elseif BOOLS[cmd] and (arg == "" or arg == "on" or arg == "off") then ns.setSetting(BOOLS[cmd], onoff(arg, d[BOOLS[cmd]])); said(BOOLS[cmd])
    elseif cmd == "area" and (arg == "zone" or arg == "all") then ns.setSetting("area", arg); said("area")
    elseif cmd == "gap" and tonumber(arg) then
        local row, n = settingRow("gap"), tonumber(arg)          -- the same range as the Settings row
        local lo, hi = row and row.min or 2, row and row.max or 30
        local v = math.min(hi, math.max(lo, n))
        if v ~= n then ns.print(string.format("The time between shared quests is kept between %d and %d seconds.", lo, hi)) end
        ns.setSetting("gap", v); said("gap")
    elseif cmd == "mode" and (arg == "box" or arg == "send" or arg == "print") then ns.setSetting("mode", arg); said("mode")
    elseif cmd == "near" then ns.nearCommand(arg); if arg == "" or arg == "on" or arg == "off" then said("near") end
    elseif cmd == "settings" or cmd == "config" or cmd == "options" then ns.toggleSettings()
    elseif cmd == "quick" then ns.quickCommand(arg)
    elseif cmd == "key" then ns.setQuickKey(arg)
    elseif cmd == "friends" then
        if arg == "on" or arg == "off" then ns.setSetting("friends", arg == "on"); said("friends") else ns.addPartyFriends(true) end
    elseif cmd == "highlight" then ns.highlightCommand(arg)
    elseif cmd == "pingkey" then ns.setPingKey(arg)
    elseif cmd == "itemkey" then ns.setItemKey(arg)
    elseif cmd == "questie" then for _, l in ipairs((ns.questie.report())) do ns.print(l) end
    elseif cmd == "doctor" then ns.doctor()
    elseif cmd == "memory" then ns.memoryCommand(arg)
    elseif cmd == "errors" then ns.errorsCommand(arg)
    elseif cmd == "log" then ns.logCommand(arg)
    elseif cmd == "reset" then ns.resetSettings()
    elseif cmd == "probe" then ns.probe()
    elseif cmd == "status" then status()
    elseif cmd == "" then
        ns.print("Version " .. tostring(ns.version) .. " is " .. (d.enabled and "on" or "off") ..
            ". Type /qs settings (or left-click the minimap button) to change anything.")
        ns.print("/qs help lists every command; /qs status shows the main switches in one line.")
    elseif cmd == "help" then for _, line in ipairs(help) do ns.print(line) end
    elseif cmd == "map" then
        for _, key in ipairs(MAP_SWITCHES) do ns.print(ns.settingLine(key)) end
    else
        -- a known command with a value it does not take: its own help line; anything else: one line, not the whole list
        local usage
        for _, line in ipairs(help) do
            if string.find(line, "/qs " .. cmd .. " ", 1, true) == 1 then usage = line; break end
        end
        ns.print(usage and ("usage: " .. usage) or ("unknown command \"" .. cmd .. "\" - /qs help lists them"))
    end
end
