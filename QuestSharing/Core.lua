-- Core.lua: settings, timers, events, chat helpers and the /qs commands.
local ADDON, ns = ...
local C = ns.compat

ns.defaults = {
    dbVersion = 2,
    enabled = true,     -- master switch
    auto = true,        -- share automatically when you join / form a party, or a new member joins
    shareNew = true,    -- also share a quest once when you accept it while in a party
    area = "zone",      -- which quests to share: "zone" (the zone you are in) or "all"
    gap = 4,            -- seconds between two shared quests inside one round (so the party is not flooded with popups)
    settle = 5,         -- seconds to wait after the party forms before sharing
    chat = true,        -- announce quests in common in party chat
    verbose = true,     -- print accepted / declined results to your own chat window
    click = true,       -- clicking a tracked quest fills the chat box with a status message
    link = true,        -- shift-clicking a quest link in the chat box also appends the status
    mode = "box",       -- what a click does: "box" (fill the chat box), "send" (send now), "print" (only show it to you)
    sync = true,        -- talk to other players' Quest Sharing addons (exact quest lists and progress)
    announce = true,    -- say in party chat when a quest we share has all its objectives done
    markers = true,     -- mark quests your party shares in the quest log
    panel = true,       -- show the "quests in common" panel while you are in a party
    near = true,        -- keep the quest tracker filled with the quests closest to you
    nearCount = 5,      -- how many quests the tracker keeps while "near" is on
    nearMode = "auto",  -- "auto" (distance if the client can measure it, else zone), "distance" or "zone"
}
ns.db = {}
for k, v in pairs(ns.defaults) do ns.db[k] = v end        -- until the saved variables are loaded

-- Output -----------------------------------------------------------------------------------------
function ns.print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local msg = "|cff55ccffQuestSharing:|r " .. table.concat(parts, " ")
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
            if not ok then ns.print("error: " .. tostring(err)) end
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
        if not ok then ns.print("error in " .. event .. ": " .. tostring(err)) end
    end
end)

ns.on("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    QuestSharingDB = QuestSharingDB or {}
    local savedVersion = QuestSharingDB.dbVersion or 0            -- read before the defaults fill the gaps
    for k, v in pairs(ns.defaults) do
        if QuestSharingDB[k] == nil then QuestSharingDB[k] = v end
    end
    if savedVersion < ns.defaults.dbVersion then
        -- earlier versions saved "near" and "panel" as off; the new defaults have them on
        QuestSharingDB.near, QuestSharingDB.panel = true, true
        QuestSharingDB.dbVersion = ns.defaults.dbVersion
    end
    ns.db = QuestSharingDB
    if ns.refreshSettings then ns.refreshSettings() end
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
    if C.inGroup() then SendChatMessage(msg, C.channel()) end
    ns.after(2, pump)
end

function ns.say(msg)
    if not ns.db.chat then return false end
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
        if key == "panel" and ns.syncPanelVisibility then ns.syncPanelVisibility() end
        if (key == "nearMode" or key == "nearCount") and d.near and ns.nearEvaluate then ns.nearEvaluate(true) end
    end
    if ns.refreshSettings then ns.refreshSettings() end
end

function ns.resetSettings()
    for k, v in pairs(ns.defaults) do
        if k ~= "dbVersion" and ns.db[k] ~= v then ns.setSetting(k, v) end
    end
    ns.db.panelPos = nil
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
    ns.print(string.format("%s | auto-share %s | new-quest %s | area %s | gap %ds | chat %s | announce %s | click %s | link %s | mode %s | sync %s | markers %s | panel %s | near %s",
        d.enabled and "ON" or "OFF", f(d.auto), f(d.shareNew), d.area, d.gap, f(d.chat), f(d.announce), f(d.click), f(d.link),
        d.mode, f(d.sync), f(d.markers), f(d.panel), f(d.near)))
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
    "/qs markers on|off   mark shared quests in the quest log",
    "/qs panel [on|off]   show / hide the \"quests in common\" panel (drag it to move it)",
    "/qs near [on|off]    keep the tracker (right-hand list) filled with the quests closest to you",
    "/qs near N           how many quests it keeps  |  /qs near mode auto|distance|zone  |  now  |  resume",
    "/qs reset            put every setting back to its default (everything on)",
    "/qs probe            show what this game client supports (send this to the author if something fails)",
}

local BOOLS = { auto = "auto", new = "shareNew", chat = "chat", click = "click", link = "link", verbose = "verbose",
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
    elseif cmd == "reset" then ns.resetSettings()
    elseif cmd == "probe" then ns.probe()
    elseif cmd == "" or cmd == "status" then status()
    else
        for _, line in ipairs(help) do ns.print(line) end
    end
end
