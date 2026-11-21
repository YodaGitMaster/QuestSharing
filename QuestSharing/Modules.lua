-- Modules.lua: every tool of the addon is a module the player can switch off (Settings > General > Tools).
-- A switched-off module keeps its code loaded (the game cannot unload Lua), but:
--   * its event handlers and timers do not run (Core.lua ns.on / ns.after check ns.moduleOn),
--   * its /qs commands and its open/command/toggle/refresh entry points say it is off,
--   * its settings rows are dimmed with "Has no effect until ... is on".
-- Hooks on game frames are installed from those event handlers, so after a /reload an off module installs nothing.
-- Each module file says which module it belongs to with ns.inModule("<id>") right after its first line;
-- files without it (Compat, Core, Style, Settings, shared UI and data) are the always-on core.
local ADDON, ns = ...

-- id, the Settings label, what it covers, the ns tables / ns functions that are its entry points, its /qs commands
ns.MODULES = {
    { id = "sharing", title = "Quest sharing & party window",
      desc = "Share quests with your party, the Party quests window, party progress messages, party map pins, quest invitations and party friends.",
      apis = { "adventure" }, fns = { "shareClick", "addPartyFriends", "refreshMapPins" },
      commands = { "share", "stop", "friends", "panel", "adventure" } },
    { id = "markers", title = "Quest markers & pings",
      desc = "The ! above quest enemies, object highlights and the ping key.",
      apis = { "ping" }, fns = { "highlightCommand", "setPingKey" },
      commands = { "highlight", "ping", "pingkey" } },
    { id = "tracker", title = "Quest list helper",
      desc = "Tracks your nearest quests automatically, the nearest-quest waypoint and hiding the game's quest list.",
      fns = { "nearCommand", "applyTrackerHidden" }, commands = { "near" } },
    { id = "automation", title = "Accept & turn in",
      desc = "Accepts quest offers and finishes safe turn-ins for you (each still has its own switch)." },
    { id = "items", title = "Quest items & item tips",
      desc = "Quest item buttons and key, quest item cleanup, item source and gathering tips on tooltips.",
      apis = { "questCleanup", "itemSources", "gatherSources" }, fns = { "refreshQuestItems", "setItemKey" },
      commands = { "cleanup", "itemkey", "gather" } },
    { id = "bags", title = "Bags",
      desc = "Quest marks in bags, bookmarks, selling gray items and arranging the bags.",
      apis = { "bagTools" }, fns = { "refreshBagMarks" }, commands = { "sort", "bookmarks" } },
    { id = "combat", title = "Fight tools",
      desc = "The chat box lock during fights and the tank aggro numbers on nameplates.",
      apis = { "chatLock", "aggro" } },
    { id = "guide", title = "Quest guide",
      desc = "The quest route guide, its learned pace and the shared camps on the map.",
      apis = { "questPlanner", "questGuidance", "campMap" }, commands = { "plan" } },
    { id = "maps", title = "World map tools",
      desc = "Zone levels, dungeon entrances and travel links, your trainers and the vendor search on the world map.",
      apis = { "vendorMap", "travelMap", "zoneLevels", "trainerIndex" }, commands = { "map" } },
    { id = "dungeons", title = "Dungeon journal & loot",
      desc = "Dungeon quests, bosses, maps, the get-them-all route and the instance loot search.",
      apis = { "dungeonQuests", "loot", "dungeonRoute", "bossPortraitResolver" },
      commands = { "dungeons", "dungeonquests", "loot", "bossdump" } },
    { id = "rewards", title = "Quest reward browser",
      desc = "The catalogue of quest reward equipment.", apis = { "rewards" }, commands = { "rewards" } },
    { id = "professions", title = "Professions, fishing & spell ranks",
      desc = "Cooking and profession views, fishing spots and upgrading spells on your action bars to learned ranks.",
      apis = { "professions", "professionUI", "fishing", "spellRanks" },
      commands = { "cooking", "professions", "fishing" } },
    { id = "finder", title = "Party finder & item level",
      desc = "Inviting players from the game's party finder and remembering item levels.",
      apis = { "lfgInvite", "lfgFinder", "itemLevel" }, commands = { "lfg", "finder", "ilvl" } },
    { id = "quick", title = "Quick chat ring",
      desc = "The quick chat ring and its key.", apis = { "quick" }, fns = { "quickCommand", "setQuickKey" },
      commands = { "quick", "key" } },
}

-- settings rows / tabs that belong to one module (Settings.lua dims them while it is off)
ns.MODULE_TABS = { objectives = "markers", actions = "markers", tracker = "tracker", dialogs = "automation",
                   items = "items", bags = "bags", sharing = "sharing", party = "sharing", finder = "finder",
                   quick = "quick", maps = "maps", guide = "guide" }
ns.MODULE_KEYS = { chatLock = "combat", chatLockNotice = "combat", aggroPlates = "combat",
                   itemSources = "items", vendorSearch = "maps", fishingMap = "professions", professionGuide = "professions",
                   autoSpellRanks = "professions", routeAllFlights = "dungeons", nearPin = "tracker" }

ns.moduleById, ns.moduleCommand = {}, {}
for _, m in ipairs(ns.MODULES) do
    m.key = "module_" .. m.id
    ns.moduleById[m.id] = m
    for _, c in ipairs(m.commands or {}) do ns.moduleCommand[c] = m.id end
    ns.defaults[m.key] = true          -- every tool is on by default
    if ns.db[m.key] == nil then ns.db[m.key] = true end
end

-- the module the file being loaded (or the handler / timer running now) belongs to; nil = core
function ns.inModule(id) ns.currentModule = id end

-- unknown ids and the core (nil) are always on
function ns.moduleOn(id)
    if id == nil or not ns.moduleById[id] then return true end
    return ns.db[ns.moduleById[id].key] ~= false
end

function ns.moduleOffText(id)
    local m = ns.moduleById[id]
    return string.format("%s is switched off (Settings > General > Tools). Switch it on, then /reload.", m and m.title or tostring(id))
end

-- /qs <cmd>: false (and a message) when the command belongs to a module that is off
function ns.commandAllowed(cmd)
    local id = ns.moduleCommand[cmd]
    if id and not ns.moduleOn(id) then ns.print(ns.moduleOffText(id)); return false end
    return true
end

-- Entry points of an off module: what the player asked for says it is off; background refreshes do nothing.
local LOUD = { open = true, toggle = true, command = true, show = true }
local QUIET = { refresh = true, settingChanged = true, applySettings = true, masterChanged = true }
local function gate(id, fn, loud)
    return function(...)
        if not ns.moduleOn(id) then
            if loud then ns.print(ns.moduleOffText(id)) end
            return nil
        end
        return fn(...)
    end
end
local wrapped = false
function ns.wrapModuleEntryPoints()
    if wrapped then return end
    wrapped = true
    for _, m in ipairs(ns.MODULES) do
        for _, name in ipairs(m.apis or {}) do
            local t = ns[name]
            if type(t) == "table" then
                for fname in pairs(LOUD) do if type(t[fname]) == "function" then t[fname] = gate(m.id, t[fname], true) end end
                for fname in pairs(QUIET) do if type(t[fname]) == "function" then t[fname] = gate(m.id, t[fname], false) end end
            end
        end
        for _, name in ipairs(m.fns or {}) do
            if type(ns[name]) == "function" then ns[name] = gate(m.id, ns[name], name ~= "refreshBagMarks"
                and name ~= "refreshQuestItems" and name ~= "applyTrackerHidden" and name ~= "refreshMapPins") end
        end
    end
end

-- Settings > General > Tools: one switch per module. Off takes effect at once for events and commands;
-- what the module already drew or hooked goes away with /reload.
function ns.moduleChanged(key, value)
    for _, m in ipairs(ns.MODULES) do
        if m.key == key then
            ns.print(string.format("%s %s. Type /reload to apply it fully.", m.title, value and "switched on" or "switched off"))
            return true
        end
    end
    return false
end
