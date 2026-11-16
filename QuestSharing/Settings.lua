-- Settings.lua: plain-language settings grouped by the thing the player wants to change.
-- Sidebar categories, visible explanations, direct choices, and explicit number controls.
local ADDON, ns = ...
local C = ns.compat
local S = ns.style

local ON, OFF = "|cff55ff55[ON] |r", "|cffff5555[OFF]|r"

ns.settingTabs = {
    { id = "general", title = "General", intro = "Start here: turn the addon on, choose how messages are sent, or check your setup." },
    { id = "objectives", title = "Quest markers", intro = "Add ! above quest enemies and help find your next quest objective." },
    { id = "tracker", title = "Quest list", intro = "Choose which quests appear in the game's quest list on the right of your screen." },
    { id = "dialogs", title = "Accept & turn in", intro = "Let the addon accept quest offers or finish ready quests when you talk to an NPC." },
    { id = "sharing", title = "Quest sharing", intro = "Offer your quests to party members and choose which updates go to party chat." },
    { id = "party", title = "Party window", intro = "Show who has each quest, choose what clicks do, and manage party friends." },
    { id = "actions", title = "Pings & quest items", intro = "Point out quest targets and use the items your quests need." },
    { id = "quick", title = "Quick chat", intro = "Send a saved message from a ring of choices. Set the key and edit messages below." },
    { id = "maps", title = "Map & search", intro = "Search for items, see zone levels, and show party locations on the world map." },
    { id = "optional", title = "Extra tools", intro = "Optional tools for quest planning, spell ranks, fishing, finding equipment, and invites." },
}

-- Every setting explains the visible result; choices also explain the selected value.
ns.settingRows = {
    { tab = "general", kind = "header", label = "Start here" },
    { tab = "general", kind = "bool", key = "enabled", label = "Turn on Quest Sharing",
      desc = "Turn on to enable the addon. Each feature below still uses its own setting." },
    { tab = "general", kind = "bool", key = "minimap", label = "Show the minimap button",
      desc = "Turn on to add a button beside the minimap. Left-click: settings. Right-click: Party quests. Drag to move it." },
    { tab = "general", kind = "choice", key = "mode", label = "How to send quest progress messages", values = { "box", "send", "print" },
      names = { box = "Draft in chat", send = "Send immediately", print = "Only show me" },
      desc = "Choose what happens when you post quest progress. Quick chat has its own send setting.",
      help = { box = "Draft in chat: fills your chat box; you review it and press Enter to send.",
               send = "Send immediately: posts without Enter where the game allows it; otherwise leaves a draft.",
               print = "Only show me: prints the message for you. Nobody else receives it." } },
    { tab = "general", kind = "bool", key = "sound", label = "Play a sound when a shared quest is accepted or finished",
      desc = "Turn on for a soft sound when someone accepts your quest or a teammate finishes a shared quest. Silent during combat." },
    { tab = "general", kind = "header", label = "Try it and check your setup" },
    { tab = "general", kind = "key", label = "Quick chat key",
      desc = "Click Set key, then press a key. Hold it in game to open the message ring. Escape cancels." },
    { tab = "general", kind = "action", label = "Show the ring", button = "Preview ring",
      desc = "Click to preview the quick chat ring. Edit its messages under Quick chat.", action = function() ns.quickOpen(true) end },
    { tab = "general", kind = "action", label = "Check my setup", button = "Run check",
      desc = "Click for a report of working features, missing addons, and game settings that need attention.", action = function() ns.doctor() end },
    { tab = "general", kind = "header", label = "Troubleshooting and reset" },
    { tab = "general", kind = "bool", key = "debug", label = "Record addon actions for troubleshooting",
      desc = "Turn on to record what the addon tried and what happened. The record is saved when you reload or log out." },
    { tab = "general", kind = "action", label = "Show the debug log", button = "View log",
      desc = "Click to read or copy recent addon actions. Also available with /qs log.", action = function() ns.logCommand() end },
    { tab = "general", kind = "action", label = "Show the errors", button = "View errors",
      desc = "Click to read or copy recorded addon errors. Also available with /qs errors.", action = function() ns.errorsCommand(nil, true) end },
    { tab = "general", kind = "action", label = "Reset everything to the defaults", button = "Reset settings",
      desc = "Click to restore default settings and quick chat messages. Your saved fishing notes are kept.", action = function() ns.resetSettings() end },

    { tab = "objectives", kind = "header", label = "! above quest enemies" },
    { tab = "objectives", kind = "bool", key = "markMobs", label = "Show ! above quest enemies",
      desc = "Turn on to add a gold ! above enemies needed for your active quests. Enemy health bars (nameplates) must be visible." },
    { tab = "objectives", kind = "bool", key = "highlightCVars", label = "Turn on enemy health bars and nearby object icons",
      desc = "Turn on if quest ! marks are missing: enables enemy nameplates and game icons over nearby objects. Off restores your previous game settings." },
    { tab = "objectives", kind = "header", label = "Direction to the nearest quest" },
    { tab = "objectives", kind = "bool", key = "nearPin", label = "Follow my nearest quest with a waypoint",
      desc = "Turn on to point the game's waypoint at your nearest quest. Requires Quest list > Automatically track nearby quests, plus game distance and waypoint support." },

    { tab = "tracker", kind = "header", label = "The game's quest list" },
    { tab = "tracker", kind = "bool", key = "hideTracker", label = "Hide the game's quest list on the right",
      desc = "Turn on to hide the game's tracker outside combat. You can use the separate Party quests window instead." },
    { tab = "tracker", kind = "bool", key = "near", label = "Automatically track nearby quests",
      desc = "Turn on to keep nearby quests in the tracker as you move. Turn off to restore your previous tracked quests." },
    { tab = "tracker", kind = "number", key = "nearCount", label = "Maximum quests to track", min = 1, max = function() return C.maxWatch() end,
      desc = "Choose how many quests the addon keeps in your list when automatic tracking is on." },
    { tab = "tracker", kind = "choice", key = "nearMode", label = "Which quests count as nearby", values = { "auto", "distance", "zone" },
      names = { auto = "Automatic", distance = "Nearest first", zone = "Current zone" },
      desc = "Used when Automatically track nearby quests is on.",
      help = { auto = "Automatic: tracks the closest quests if the game supplies distances; otherwise uses your current zone.",
               distance = "Nearest first: tracks the closest quests. Falls back to your current zone if distances are unavailable.",
               zone = "Current zone: only tracks quests for the zone you are standing in." } },
    { tab = "tracker", kind = "number", key = "nearPause", label = "Pause after I edit the quest list (seconds)", min = 5, max = 300,
      desc = "After you manually track or untrack a quest, the addon waits this long before changing the list again." },

    { tab = "dialogs", kind = "header", label = "When a quest offer opens" },
    { tab = "dialogs", kind = "bool", key = "autoAcceptQuests", label = "Accept quest offers automatically",
      desc = "Turn on to accept a quest as soon as its offer opens, including offers from party members. You still choose which NPC to talk to." },
    { tab = "dialogs", kind = "header", label = "When I talk to a quest giver to turn in" },
    { tab = "dialogs", kind = "bool", key = "autoCompleteQuests", label = "Turn in completed quests automatically",
      desc = "Turn on to finish ready quests with no reward choice or one reward. Multiple rewards and quests costing money wait for your click." },

    { tab = "sharing", kind = "header", label = "Offering quests to your party" },
    { tab = "sharing", kind = "bool", key = "auto", label = "Share my quests when someone joins the party",
      desc = "Turn on to offer quests when you join a party or another player joins yours. Each offer is sent once per sharing round." },
    { tab = "sharing", kind = "choice", key = "area", label = "Which quests to share", values = { "zone", "all" },
      names = { zone = "Current zone only", all = "All my quests" },
      desc = "Choose whether sharing offers quests for your current zone or your whole quest log." },
    { tab = "sharing", kind = "number", key = "gap", label = "Seconds between shared quests", min = 2, max = 30,
      desc = "Wait this many seconds between quest offers so party members have time to read each one." },
    { tab = "sharing", kind = "bool", key = "shareNew", label = "Share new quests as I accept them",
      desc = "Turn on to offer each newly accepted quest to your current party." },
    { tab = "sharing", kind = "bool", key = "shareByClick", label = "Require a Share click for each quest offer",
      desc = "Turn on to prepare offers but send each only after you click Share. Overrides automatic offers; some clients require this." },
    { tab = "sharing", kind = "header", label = "Messages in party chat" },
    { tab = "sharing", kind = "bool", key = "chat", label = "Announce quests in common in party chat",
      desc = "Turn on to tell the party which quests you all have. Requires General > Send immediately." },
    { tab = "sharing", kind = "bool", key = "announce", label = "Tell the party when I finish a shared quest",
      desc = "Turn on to announce once when you finish all objectives of a quest you share with the party." },
    { tab = "sharing", kind = "bool", key = "pickup", label = "Tell the party when I accept a quest a teammate has",
      desc = "Turn on to suggest doing a quest together when you accept one a party member already has." },
    { tab = "sharing", kind = "bool", key = "coords", label = "Include where I found quest items in progress messages",
      desc = "Turn on to add the item location to your message when a party member still needs those quest items." },
    { tab = "sharing", kind = "header", label = "Quest information between addon users" },
    { tab = "sharing", kind = "bool", key = "sync", label = "Sync quest lists with other Quest Sharing users",
      desc = "Turn on to exchange quest lists and progress with party members using this addon. Needed for exact shared-quest information." },
    { tab = "sharing", kind = "bool", key = "markers", label = "Mark shared quests with a star in my quest log",
      desc = "Turn on to add a star and party members' names beside shared quests in the quest log. This does not add ! above enemies." },

    { tab = "party", kind = "header", label = "The separate Party quests window" },
    { tab = "party", kind = "bool", key = "panel", label = "Show the Party quests window",
      desc = "Turn on to show nearby quests and which party members have them. Left-click offers a quest; right-click opens its action menu." },
    { tab = "party", kind = "bool", key = "panelSolo", label = "Also show the Party quests window when playing alone",
      desc = "Turn on to show your nearby quests without a party. Requires Show the Party quests window to be on." },
    { tab = "party", kind = "bool", key = "panelCombat", label = "Hide the Party quests window during combat",
      desc = "Turn on to hide this window during fights and bring it back afterward." },
    { tab = "party", kind = "number", key = "panelScale", label = "Party quests window size (%)", min = 70, max = 150, step = 10,
      desc = "100 is the normal size. Increase to make the window and its text bigger." },
    { tab = "party", kind = "action", label = "Move the Party quests window back to its starting position", button = "Move back",
      desc = "Click if you dragged the window somewhere hard to find.", action = function() if ns.resetPanelPosition then ns.resetPanelPosition() end end },
    { tab = "party", kind = "header", label = "Posting progress by clicking" },
    { tab = "party", kind = "bool", key = "click", label = "Click tracked quests to prepare a progress message",
      desc = "Turn on to post progress by clicking a quest in the game's tracker or its progress in Party quests. Several clicks combine into one message." },
    { tab = "party", kind = "bool", key = "link", label = "Shift-click quest links in chat to post my progress",
      desc = "Turn on to add your progress when you Shift-click a quest link in chat." },
    { tab = "party", kind = "header", label = "Adding party members as friends" },
    { tab = "party", kind = "bool", key = "friends", label = "Automatically add party members as friends (beta)",
      desc = "Turn on to add people you group with to your friends list. Skips existing friends, ignored players, and random groups." },
    { tab = "party", kind = "action", label = "Add my current party to my friends list", button = "Add friends",
      desc = "Click to add your current party once, without enabling automatic friend requests.", action = function() ns.addPartyFriends(true) end },

    { tab = "actions", kind = "header", label = "Point out quest targets to the party" },
    { tab = "actions", kind = "key", which = "ping", label = "Key to target and ping a quest enemy",
      desc = "Click Set key, then press a key. Use it in game to target and ping the nearest quest enemy. Escape cancels." },
    { tab = "actions", kind = "choice", key = "pingGap", label = "Minimum time between pings", values = { 5, 10, 15 },
      names = { [5] = "5 seconds", [10] = "10 seconds", [15] = "15 seconds" },
      desc = "Choose the wait between pings. Hold Shift while pressing your ping key to bypass the wait." },
    { tab = "actions", kind = "bool", key = "pingObjects", label = "Also ping quest objects I am facing",
      desc = "Turn on to ping a quest object in front of you when no quest enemy is nearby." },
    { tab = "actions", kind = "header", label = "Find and use quest items" },
    { tab = "actions", kind = "bool", key = "bagMarks", label = "Mark quest items in my bags",
      desc = "Turn on for gold marks on items needed by nearby quests. Blue marks mean the quest is elsewhere." },
    { tab = "actions", kind = "bool", key = "questItems", label = "Show usable item buttons beside tracked quests",
      desc = "Turn on to add a clickable item icon beside a quest in the tracker. Click the icon to use the item." },
    { tab = "actions", kind = "key", which = "item", label = "Key to use my nearest quest's item",
      desc = "Click Set key, then press a key. Use it in game to activate the item for your closest quest. Escape cancels." },
    { tab = "actions", kind = "bool", key = "itemButton", label = "Show a separate button for my nearest quest's item",
      desc = "Turn on for a movable item button with a cooldown. Red means your target is out of range. Shift-drag to move it." },

    { tab = "quick", kind = "header", label = "Open the message ring" },
    { tab = "quick", kind = "bool", key = "quick", label = "Enable the quick chat ring",
      desc = "Turn on to use your key to open a ring of saved messages and emotes." },
    { tab = "quick", kind = "key", label = "Key that opens the ring",
      desc = "Click Set key, then press the key you want to use. Escape cancels." },
    { tab = "quick", kind = "choice", key = "quickMode", label = "How the quick chat key works", values = { "hold", "toggle" },
      names = { hold = "Hold key", toggle = "Press key" },
      desc = "Choose how to open the ring and select a message.",
      help = { hold = "Hold key: hold it down, point at a message, then release to select it.",
               toggle = "Press key: press once to open the ring, then click a message." } },
    { tab = "quick", kind = "bool", key = "quickSend", label = "Send quick chat messages without pressing Enter",
      desc = "Turn on to send your selected message immediately. Turn off to review it in chat first. Some clients require Enter." },
    { tab = "quick", kind = "choice", key = "quickSize", label = "Message ring size", values = { "small", "normal", "large" },
      names = { small = "Small", normal = "Normal", large = "Large" },
      desc = "Choose how far the message choices sit from the center of the ring." },
    { tab = "quick", kind = "choice", key = "quickChannel", label = "Who receives messages set to Automatic", values = { "auto", "say", "party", "whisper" },
      names = { auto = "Automatic", say = "Nearby (/say)", party = "Party", whisper = "Whisper player" },
      desc = "Applies to messages whose individual channel is Auto.",
      help = { auto = "Automatic: whispers a player you target or point at outside your party; otherwise uses party chat, or /say when alone.",
               say = "Nearby (/say): players near your character can read the message.",
               party = "Party: only your current party receives the message.",
               whisper = "Whisper player: sends privately to the player you target or point at when opening the ring." } },

    { tab = "maps", kind = "header", label = "Search items and vendors (requires Questie data)" },
    { tab = "maps", kind = "bool", key = "itemSources", label = "Show where items come from when I hover over them",
      desc = "Turn on for seller types and known Mining sources in bag and recipe tooltips. Requires Questie data." },
    { tab = "maps", kind = "bool", key = "vendorSearch", label = "Search items and vendors on the map",
      desc = "Show matching locations as map pins. Type an item or vendor type, like General Goods. Requires Questie data." },
    { tab = "maps", kind = "header", label = "Zone level guides" },
    { tab = "maps", kind = "bool", key = "zoneLevels", label = "Show zone questing level ranges",
      desc = "Turn on to display level ranges on the world map, such as 10-20. These are zone guides, not the level of every quest." },
    { tab = "maps", kind = "header", label = "Party locations" },
    { tab = "maps", kind = "bool", key = "mapPins", label = "Show Quest Sharing party members on my world map",
      desc = "Turn on for class icons showing teammates using this addon. Requires Quest sharing > Sync quest lists." },
    { tab = "maps", kind = "bool", key = "teamWaypoint", label = "Add a waypoint where a teammate found quest items",
      desc = "Turn on to mark a location a teammate shares for quest items you still need. Requires a client with waypoints." },

    { tab = "optional", kind = "header", label = "Plan nearby quests" },
    { tab = "optional", kind = "bool", key = "questPlanner", label = "Enable the quest planner",
      desc = "Turn on to plan quests for your zone. Requires Questie. Shortest Path Forever can add walk routes and walking-distance ordering." },
    { tab = "optional", kind = "action", label = "Plan my quests", button = "Open plan",
      desc = "Open the route panel beside the quest tracker. Click a stop to mark it; use Follow with SPF for a walk route when installed.",
      action = function() ns.questPlanner.open() end },
    { tab = "optional", kind = "header", label = "Spell ranks on my action bars" },
    { tab = "optional", kind = "bool", key = "autoSpellRanks", label = "Auto-update spells to highest learned rank",
      desc = "Turn on to replace old spell ranks on your action bars with the best rank you already learned. Waits during combat; leaves macros and pet bars alone." },
    { tab = "optional", kind = "action", label = "Check spell ranks now", button = "Update ranks",
      desc = "First turn on Auto-update spells above, then click to check your action bars now. Reports any update or reason it must wait.",
      action = function() ns.spellRanks.update(true) end },
    { tab = "optional", kind = "header", label = "Find equipment" },
    { tab = "optional", kind = "bool", key = "rewardBrowser", label = "Enable the quest reward equipment browser",
      desc = "Turn on to browse quest equipment for your class, level, and faction. Requires Questie data." },
    { tab = "optional", kind = "action", label = "Find quest rewards", button = "Browse rewards",
      desc = "Click to enable and open the reward browser. See quest gear and how to start each quest; hover over gear to compare it with yours.",
      action = function() ns.rewards.open() end },
    { tab = "optional", kind = "action", label = "Search instance loot and who drops it", button = "Browse drops",
      desc = "Click to find dungeon equipment by item, boss, or dungeon. AtlasLoot provides fuller data; Questie results may be incomplete.",
      action = function() ns.loot.open() end },
    { tab = "optional", kind = "header", label = "Saved fishing spots" },
    { tab = "optional", kind = "bool", key = "fishingMap", label = "Show fishing waters on the world map",
      desc = "Turn on to display fishing spots you saved. AnglerAtlas can also provide zone fishing information." },
    { tab = "optional", kind = "action", label = "Add or edit a fishing spot", button = "Edit spots",
      desc = "Click to save a water's location, fishing skill, fish, and notes. You enter this information yourself.",
      action = function() ns.fishing.open() end },
    { tab = "optional", kind = "header", label = "Find people to quest with" },
    { tab = "optional", kind = "action", label = "Seek fellow adventurers", button = "Write invite",
      desc = "Click to draft an invitation for an unfinished quest. Choose a chat, review the text, and press Enter to send.",
      action = function() ns.adventure.open() end },
}

local function limit(v) if type(v) == "function" then return v() end return v end

local function keyName(row)
    if row and row.which == "ping" then return ns.pingKeyName and ns.pingKeyName() end
    if row and row.which == "item" then return ns.itemKeyName and ns.itemKeyName() end
    return ns.quickKeyName and ns.quickKeyName()
end

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
        return row.label .. ": |cff55ccff" .. (keyName(row) or "not set") .. "|r"
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
        ns.captureKey(row.which)
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
local WIDTH, HEIGHT, LEFT = 900, 650, 216
local CONTENT = WIDTH - LEFT - 28
local TOP, VIEW_H = 118, HEIGHT - 166
local ROW_H, HEADER_H = 26, 32
local MIN_ROWS = 18

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

function ns.captureKey(which)
    if InCombatLockdown and InCombatLockdown() then return ns.print("key bindings cannot be changed in combat") end
    W.captureFor = which
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
        if W.captureFor == "ping" then ns.setPingKey(prefix .. key)
        elseif W.captureFor == "item" then ns.setItemKey(prefix .. key)
        else ns.setQuickKey(prefix .. key) end
    end
    ns.refreshSettings()
end

-- the message editor (inside the Quick chat tab) -------------------------------------------------------------------
local ed = W.ed

local function edList() return ns.quickListFor(ed.page or 1) or ns.quickItems() end

function ns.editorRefresh()
    if not ed.frame then return end
    local pages = ns.quickPageList()
    ed.page = math.max(1, math.min(ed.page or 1, #pages))
    for i, b in ipairs(ed.pageButtons or {}) do
        local pg = pages[i]
        if pg then
            b.text:SetText((i == ed.page and "|cffffd100[" or "|cff55ccff ") .. pg.title .. (i == ed.page and "]|r" or " |r"))
            b.frame:Show()
        else
            b.frame:Hide()
        end
    end
    local list = edList()
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
    local isEmote = item and ns.quickIsEmote(item.text)
    ed.routeText:SetText((isEmote and "|cffffd100An emote: everybody around sees (and hears) it.|r")
        or (item and ("Goes to: |cffffd100" .. ns.QUICK_ROUTE_INFO[route] .. "|r")) or "")
    for _, c in ipairs(ed.routeButtons) do
        if item and not isEmote then
            local hot = (c.route == route)
            c.text:SetText((hot and "|cffffd100[" or "|cff55ccff ") .. c.title .. (hot and "]|r" or " |r"))
            c.frame:Show()
        else
            c.frame:Hide()
        end
    end
    if item and not isEmote then ed.channelCaption:Show() else ed.channelCaption:Hide() end
    local looks = item and (isEmote and ("/" .. string.lower(string.match(item.text, "^@emote%s+(%S+)") or "") .. "  (an emote)")
        or ns.quickResolve(item.text))
    ed.preview:SetText(item and ("|cff888888Looks like:|r " .. shorten(looks, 110)) or "|cff888888Click a message above to edit it.|r")
end

-- which ring the editor shows (1 = your messages, then the emote rings)
function ns.editorPage(n) ed.page, ed.selected = n, nil; ns.editorRefresh() end
function ns.editorSelect(i) ed.selected = (edList()[i] and i) or nil; ns.editorRefresh() end
function ns.editorMove(delta)
    if ed.selected and ns.quickMove(ed.selected, ed.selected + delta, ed.page) then ed.selected = ed.selected + delta end
    ns.editorRefresh()
end
function ns.editorDelete()
    if ed.selected and ns.quickRemove(ed.selected, ed.page) then ed.selected = nil end
    ns.editorRefresh()
end
function ns.editorAdd()
    local n
    if (ed.page or 1) == 1 then n = ns.quickAdd("New message", "New", ed.page) else n = ns.quickAdd("/wave", "Wave", ed.page) end
    if n then ed.selected = n end
    ns.editorRefresh()
end
function ns.editorSave(label, text)
    if ed.selected then
        ns.quickEdit(ed.selected, text, ed.page)
        if label and label ~= "" then ns.quickLabel(ed.selected, label, ed.page) end
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
        ns.quickRoute(ed.selected, route, ed.page)
    end
    ns.editorRefresh()
end
function ns.editorReset() ns.quickReset(ed.page); ed.selected = nil; ns.editorRefresh() end
function ns.editorShowRing() ns.db.quickPage = ed.page or 1; ns.quickOpen(true) end

local function buildEditor(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(CONTENT)
    f:SetHeight(448)
    ed.frame, ed.lines = f, {}
    -- which ring to edit: your messages, or one of the emote rings (the mouse wheel flips them in play)
    local ringCap = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ringCap:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
    ringCap:SetText("Ring:")
    ed.pageButtons = {}
    for i = 1, 6 do
        local btn = clickable(f, 100, 16, function() ns.editorPage(i) end)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 40 + ((i - 1) % 3) * 190, -math.floor((i - 1) / 3) * 20)
        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("LEFT", btn, "LEFT", 0, 0)
        ed.pageButtons[i] = { frame = btn, text = t }
    end
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -40)
    title:SetText("1. Choose a message to edit (up to 8, clockwise from the top)")
    for i = 1, 8 do
        local line = clickable(f, CONTENT, 18, function() ns.editorSelect(i) end)
        line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -62 - (i - 1) * 18)
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
    cap1:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -216)
    cap1:SetText("2. Short label (14 letters)")
    local cap2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cap2:SetPoint("TOPLEFT", f, "TOPLEFT", 170, -216)
    cap2:SetText("3. Message or emote (press Enter to save)")
    local function box(width, x, max)
        local b = CreateFrame("EditBox", nil, f)
        b:SetWidth(width)
        b:SetHeight(20)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -234)
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
    ed.labelBox, ed.textBox = box(150, 0, 14), box(CONTENT - 170, 170, 200)
    local examples = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    examples:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -262)
    examples:SetWidth(CONTENT); examples:SetWordWrap(true)
    examples:SetText("Examples: Hello {name}!   {quest} = your quest, {here} = your location. For an emote, type /wave.")
    ed.preview = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ed.preview:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -298)
    ed.preview:SetWidth(CONTENT)
    ed.preview:SetWordWrap(true)
    local x = 0
    ed.buttons = {}
    for _, b in ipairs({
        { "Up", function() ns.editorMove(-1) end }, { "Down", function() ns.editorMove(1) end },
        { "Remove", function() ns.editorDelete() end }, { "Add", function() ns.editorAdd() end },
        { "Reset", function() ns.editorReset() end }, { "Show the ring", function() ns.editorShowRing() end },
    }) do
        local w = (b[1] == "Show the ring") and 110 or 70
        local btn = S.button(f, b[1], w, b[2])
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, -340)
        ed.buttons[b[1]] = btn
        x = x + w + 6
    end
    -- the channel of the selected message: one click on a choice
    ed.channelCaption = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ed.channelCaption:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -380)
    ed.channelCaption:SetText("Channel:")
    ed.routeButtons = {}
    local TITLES = { auto = "Auto", nearby = "Nearby", say = "/s Say", yell = "/y Yell", party = "/p Party", whisper = "/w Whisper" }
    local rx = 56
    for _, r in ipairs(ns.QUICK_ROUTES) do
        local btn = clickable(f, 80, 16, function() ns.editorRoute(r) end)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", rx, -378)
        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("LEFT", btn, "LEFT", 0, 0)
        ed.routeButtons[#ed.routeButtons + 1] = { route = r, title = TITLES[r], frame = btn, text = t }
        rx = rx + 84
    end
    ed.routeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ed.routeText:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -404)
    ed.routeText:SetWidth(CONTENT)
    ed.routeText:SetWordWrap(true)
    return f
end

-- tabs and rows ---------------------------------------------------------------------------------------------------------
local function description(row)
    local help = row.help and row.help[ns.db[row.key]]
    return help or row.desc or ""
end

local function textHeight(font, text, width, size)
    -- The actual font measurement handles wrapping and localized game fonts.
    font:SetWidth(width)
    font:SetText(text)
    local h = font.GetStringHeight and font:GetStringHeight()
    return math.max(size, h or math.ceil(#text / math.max(1, math.floor(width / (size * 0.55)))) * size)
end

local function paintRow(r, row)
    local d = ns.db
    r.box:Hide(); r.tick:Hide(); r.value:SetText(""); r.button:Hide(); r.line:Hide()
    r.less:Hide(); r.more:Hide()
    for _, b in ipairs(r.choices) do b:Hide() end
    r.text:ClearAllPoints()
    r.desc:ClearAllPoints()
    if row.kind == "header" then
        r.desc:SetText("")
        r.text:SetPoint("BOTTOMLEFT", r.frame, "BOTTOMLEFT", 0, 8)
        r.text:SetWidth(CONTENT)
        r.text:SetText(S.GOLD .. row.label .. "|r")
        r.line:Show()
        return HEADER_H
    end
    local inset = row.kind == "bool" and 30 or 0
    local reserved = (row.kind == "bool" and 56) or ((row.kind == "number" or row.kind == "action" or row.kind == "key") and 150) or 0
    r.text:SetPoint("TOPLEFT", r.frame, "TOPLEFT", inset, -4)
    local labelH = textHeight(r.text, row.label, CONTENT - inset - reserved, 14)
    local y = math.max(ROW_H, labelH + 10)
    if row.kind == "bool" then
        r.box:Show()
        if d[row.key] then r.tick:Show() end
        r.value:SetText(d[row.key] and (S.GREEN .. "On|r") or (S.GREY .. "Off|r"))
        if d.enabled == false and row.key ~= "enabled" then r.text:SetText(S.GREY .. row.label .. "|r") end
    elseif row.kind == "choice" then
        local w = (CONTENT - (#row.values - 1) * 6) / #row.values
        for i, value in ipairs(row.values) do
            local b = r.choices[i]
            local selected = d[row.key] == value
            b.value = value
            b:SetWidth(w)
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", r.frame, "TOPLEFT", (i - 1) * (w + 6), -y)
            b:SetLabel((selected and S.GOLD or S.WHITE) .. (selected and "[x] " or "[ ] ") .. ((row.names and row.names[value]) or tostring(value)) .. "|r")
            b:Show()
        end
        y = y + 30
    elseif row.kind == "number" then
        r.value:SetText(S.BLUE .. tostring(d[row.key] or 0) .. "|r")
        r.value:ClearAllPoints(); r.value:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT", -52, -5)
        r.less:Show(); r.more:Show()
    elseif row.kind == "key" then
        local mine = W.capturing and (W.captureFor == row.which)
        r.button:SetLabel(mine and (S.GOLD .. "press a key...|r") or (keyName(row) or "Set key"))
        r.button:Show()
    elseif row.kind == "action" then
        r.button:SetLabel(row.button or "Open")
        r.button:Show()
    end
    if row.kind ~= "number" then
        r.value:ClearAllPoints(); r.value:SetPoint("TOPRIGHT", r.frame, "TOPRIGHT", -6, -5)
    end
    local desc = description(row)
    r.desc:SetPoint("TOPLEFT", r.frame, "TOPLEFT", inset, -y)
    local h = textHeight(r.desc, desc, CONTENT - inset, 13)
    r.desc:SetText("|cffbbc2cf" .. desc .. "|r")
    return y + h + 12
end

local buildRow

function ns.settingsScroll(delta)
    if not W.rowScroll then return end
    local maximum = math.max(0, (W.contentHeight or 0) - VIEW_H)
    local offset = math.max(0, math.min(maximum, W.rowScroll:GetVerticalScroll() + delta))
    W.rowScroll:SetVerticalScroll(offset)
    W.scrollHint:SetText(maximum > 0 and (offset >= maximum and "End of page" or "More options below - scroll") or "All options shown")
    if maximum > 0 then W.scrollUp:Show(); W.scrollDown:Show() else W.scrollUp:Hide(); W.scrollDown:Hide() end
end

function ns.refreshSettings()
    if not W.win then return end
    local list = rowsOf(W.tab)
    local y = 0
    for n = 1, math.max(MIN_ROWS, #list, #W.rows) do
        if not W.rows[n] then buildRow(W.rowBody, n) end
        local r = W.rows[n]
        local idx = list[n]
        r.hover:Hide()
        if idx then
            r.index = idx
            local h = paintRow(r, ns.settingRows[idx])
            r.frame:ClearAllPoints()
            r.frame:SetPoint("TOPLEFT", W.rowBody, "TOPLEFT", 0, -y)
            r.frame:SetHeight(h)
            r.frame:Show()
            y = y + h + 4
        else
            r.index = nil
            r.frame:Hide()
        end
    end
    for _, t in ipairs(ns.settingTabs) do
        local tab = W.tabs[t.id]
        local open = (t.id == W.tab)
        tab.text:SetText((open and S.GOLD or S.BLUE) .. t.title .. "|r")
        if open then tab.under:Show(); tab.bg:SetVertexColor(1.6, 1.6, 1.6) else tab.under:Hide(); tab.bg:SetVertexColor(1, 1, 1) end
        if open then W.heading:SetText(t.title); W.intro:SetText("|cffbbc2cf" .. t.intro .. "|r") end
    end
    if W.tab == "quick" then
        ed.frame:ClearAllPoints()
        ed.frame:SetPoint("TOPLEFT", W.rowBody, "TOPLEFT", 0, -(y + 12))
        ed.frame:Show()
        ns.editorRefresh()
        y = y + 12 + ed.frame:GetHeight()
    else
        ed.frame:Hide()
    end
    W.bottom, W.contentHeight = TOP + y, y
    W.rowBody:SetHeight(math.max(VIEW_H, y))
    ns.settingsScroll(0) -- Keep the reading position when a setting changes.
end

function ns.settingsTab(id)
    for _, t in ipairs(ns.settingTabs) do
        if t.id == id then
            if W.tab ~= id and W.rowScroll then W.rowScroll:SetVerticalScroll(0) end
            W.tab = id
        end
    end
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

buildRow = function(f, n)
    local r = { choices = {} }
    local frame = clickable(f, CONTENT, ROW_H, nil)
    r.frame = frame
    r.hover = S.fill(frame, "BACKGROUND", 1, 1, 1, 0.06)
    r.hover:SetAllPoints(frame); r.hover:Hide()
    r.box, r.tick = S.checkBox(frame)
    r.box:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 1)
    r.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(true)
    r.desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.desc:SetJustifyH("LEFT"); r.desc:SetWordWrap(true)
    r.value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.value:SetJustifyH("RIGHT")
    r.line = S.fill(frame, "ARTWORK", 1, 0.82, 0, 0.35)
    r.line:SetHeight(1)
    r.line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 2)
    r.line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 2)
    r.button = S.button(frame, "", 140, function(_, which) if r.index then ns.settingsClick(r.index, which) end end)
    r.button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -1)
    r.less = S.button(frame, "-", 32, function() if r.index then ns.settingsClick(r.index, "RightButton") end end)
    r.less:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -100, -1)
    r.more = S.button(frame, "+", 32, function() if r.index then ns.settingsClick(r.index, "LeftButton") end end)
    r.more:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -1)
    for i = 1, 4 do
        local b = S.button(frame, "", 100, function(self)
            local row = r.index and ns.settingRows[r.index]
            if row and row.kind == "choice" then ns.setSetting(row.key, self.value); ns.refreshSettings() end
        end)
        r.choices[i] = b
    end
    frame:SetScript("OnMouseUp", function(_, button)
        local row = r.index and ns.settingRows[r.index]
        if row and row.kind == "bool" then ns.settingsClick(r.index, button) end
    end)
    frame:SetScript("OnEnter", function(self)
        local row = r.index and ns.settingRows[r.index]
        if not row or row.kind == "header" then return end
        r.hover:Show()
        tooltip(self, description(row))
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

    local sidebar = S.fill(f, "BACKGROUND", 0.08, 0.1, 0.15, 0.9)
    sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -48)
    sidebar:SetWidth(180); sidebar:SetHeight(HEIGHT - 72)
    local navTitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    navTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -60)
    navTitle:SetText("WHAT DO YOU WANT TO CHANGE?")
    navTitle:SetWidth(154); navTitle:SetWordWrap(true)
    for i, t in ipairs(ns.settingTabs) do
        local b = clickable(f, 164, 36, function() ns.settingsTab(t.id) end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 26, -(100 + (i - 1) * 40))
        local bg = S.fill(b, "BACKGROUND", 0.12, 0.14, 0.2, 0.9)
        bg:SetAllPoints(b)
        local under = S.fill(b, "ARTWORK", 1, 0.82, 0, 0.9)
        under:SetWidth(3); under:SetHeight(36)
        under:SetPoint("LEFT", b, "LEFT", 0, 0)
        local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", b, "LEFT", 10, 0)
        text:SetWidth(150); text:SetJustifyH("LEFT"); text:SetWordWrap(true)
        W.tabs[t.id] = { frame = b, text = text, under = under, bg = bg }
    end
    W.heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    W.heading:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, -52)
    W.intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    W.intro:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, -78)
    W.intro:SetWidth(CONTENT); W.intro:SetWordWrap(true)

    W.rowScroll = CreateFrame("ScrollFrame", nil, f)
    W.rowScroll:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, -TOP)
    W.rowScroll:SetWidth(CONTENT); W.rowScroll:SetHeight(VIEW_H)
    W.rowScroll:EnableMouseWheel(true)
    W.rowScroll:SetScript("OnMouseWheel", function(_, delta) ns.settingsScroll(-delta * 64) end)
    W.rowBody = CreateFrame("Frame", nil, W.rowScroll)
    W.rowBody:SetWidth(CONTENT); W.rowBody:SetHeight(VIEW_H)
    W.rowScroll:SetScrollChild(W.rowBody)
    for n = 1, MIN_ROWS do buildRow(W.rowBody, n) end
    buildEditor(W.rowBody)
    W.scrollHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.scrollHint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LEFT, 24)
    W.scrollUp = S.button(f, "Scroll up", 92, function() ns.settingsScroll(-VIEW_H * 0.75) end)
    W.scrollUp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -128, 16)
    W.scrollDown = S.button(f, "Scroll down", 92, function() ns.settingsScroll(VIEW_H * 0.75) end)
    W.scrollDown:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 16)
    local saved = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    saved:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 30, 32)
    saved:SetText("Changes save automatically.")
    saved:SetWidth(150); saved:SetWordWrap(true)
    -- Keep this wider layout usable on short or narrow screens.
    if UIParent.GetWidth and UIParent.GetHeight then
        local scale = math.min(1, (UIParent:GetWidth() - 24) / WIDTH, (UIParent:GetHeight() - 48) / HEIGHT)
        if scale > 0 then f:SetScale(scale) end
    end
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
