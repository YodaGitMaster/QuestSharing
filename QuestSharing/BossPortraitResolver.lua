-- Finds a boss's creature display ID in the game client: one hidden PlayerModel (1x1, alpha 0, on UIParent, made on
-- the first lookup), SetCreature(npcID) -> GetDisplayInfo(), read on OnModelLoaded or after WAIT s (TRIES tries, then
-- given up for this session). One lookup at a time from a FIFO queue (at most MAX_QUEUE waiting); never in combat or
-- during a loading screen. Found IDs are kept in ns.db.bossDisplays[npcID] (saved); misses in a session table.
-- Used by DungeonBossesUI.lua for bosses with no journal art and no baked displayID. /qs bossdump prints the cache.
local ADDON, ns = ...
ns.inModule("dungeons")          -- Modules.lua: Settings > General > Tools can switch this off
local R = {}
ns.bossPortraitResolver = R

local WAIT, TRIES, MAX_QUEUE = 0.2, 5, 12
local queue = {}   -- npcIDs, oldest first (the active lookup is not in it)
local waiting = {} -- waiting[npcID] = { done, ... } for queued and active lookups
local failed = {}  -- this session: npcID -> true (given up)
local cur          -- the active lookup: { id, tries, timer }
local model
local loading = false
local last         -- the display ID of the last creature found (the model may still answer with it)

local function cache(create)
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.bossDisplays) ~= "table" then
        if not create then return nil end
        db.bossDisplays = {}
    end
    return db.bossDisplays
end

-- the cached display ID of this npc, or nil (0 / nil mean not known)
function R.displayFor(npcID)
    local id = tonumber(npcID)
    local t = id and cache(false)
    local d = t and tonumber(t[id])
    if d and d > 0 then return d end
    return nil
end

local function fighting()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, v = pcall(InCombatLockdown)
    return ok and v and true or false
end
local function paused() return loading or fighting() end

local function getModel()
    if model then return model end
    if type(CreateFrame) ~= "function" or not UIParent then return nil end
    local ok, m = pcall(CreateFrame, "PlayerModel", nil, UIParent)
    if not ok or not m then return nil end
    pcall(m.SetWidth, m, 1); pcall(m.SetHeight, m, 1)
    pcall(m.SetPoint, m, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    if m.SetAlpha then pcall(m.SetAlpha, m, 0) end
    if m.EnableMouse then pcall(m.EnableMouse, m, false) end
    m.jAlpha = 0 -- for tests (the mock has no GetAlpha)
    model = m
    m:SetScript("OnModelLoaded", function() R._onLoaded() end)
    m:Show()
    return m
end

local function clearModel()
    if model and model.ClearModel then pcall(model.ClearModel, model) end
end

local function readDisplay()
    if not (model and model.GetDisplayInfo) then return nil end
    local ok, d = pcall(model.GetDisplayInfo, model)
    d = ok and tonumber(d) or nil
    if d and d > 0 then return d end
    return nil
end

local pump

-- right after SetCreature the model can still answer with the previous creature's display: such a read counts only
-- once OnModelLoaded fired for this lookup (a wrong ID would stay in the saved cache for good)
local function fresh(c, d)
    if not d then return nil end
    if c.loaded or (d ~= last and d ~= c.before) then return d end
    return nil
end

local function stopTimer(c)
    if c and c.timer then
        if ns.cancel then ns.cancel(c.timer) end
        c.timer = nil
    end
end

local function finish(c, display)
    stopTimer(c)
    cur = nil
    clearModel()
    local list = waiting[c.id] or {}
    waiting[c.id] = nil
    if display then
        last = display
        local t = cache(true)
        if t then t[c.id] = display end
        for _, fn in ipairs(list) do pcall(fn, display) end
    else
        failed[c.id] = true
    end
    pump()
end

-- combat or a loading screen: the active lookup goes back to the front of the queue, its tries start over later
local function interrupt()
    local c = cur
    if not c then return end
    stopTimer(c)
    cur = nil
    clearModel()
    table.insert(queue, 1, c.id)
end

local function attempt()
    local c = cur
    if not c then return end
    if paused() then interrupt(); return end
    local m = getModel()
    if not (m and m.SetCreature) then finish(c, nil); return end
    c.tries = c.tries + 1
    c.before = readDisplay() -- what the model shows now, before this creature
    clearModel()
    pcall(m.SetCreature, m, c.id)
    if cur ~= c then return end -- OnModelLoaded fired inside SetCreature and finished it (the model may hold the next one)
    local d = fresh(c, readDisplay()) -- cached creatures answer at once
    if d then finish(c, d); return end
    local timer
    timer = ns.after(WAIT, function()
        if cur ~= c or c.timer ~= timer then return end -- finished or interrupted meanwhile
        c.timer = nil
        if paused() then interrupt(); return end
        local got = fresh(c, readDisplay())
        if got then finish(c, got)
        elseif c.tries >= TRIES then finish(c, nil)
        else attempt() end
    end)
    c.timer = timer
end

function R._onLoaded()
    local c = cur
    if not c or c.tries == 0 or paused() then return end
    c.loaded = true
    local d = readDisplay()
    if d then finish(c, d) end
end

pump = function()
    if cur or paused() or #queue == 0 then return end
    cur = { id = table.remove(queue, 1), tries = 0 }
    attempt()
end

-- Queue a lookup; done(displayID) is called once when found (at once when already cached), never on a miss.
-- Returns true when queued (or already queued / active / cached), false when given up this session, the queue
-- is full or the npcID is not a number.
function R.request(npcID, done)
    local id = tonumber(npcID)
    if not id or id <= 0 then return false end
    local known = R.displayFor(id)
    if known then
        if type(done) == "function" then pcall(done, known) end
        return true
    end
    if failed[id] then return false end
    local list = waiting[id]
    if not list then
        if #queue >= MAX_QUEUE then return false end
        list = {}
        waiting[id] = list
        queue[#queue + 1] = id
    end
    if type(done) == "function" then list[#list + 1] = done end
    pump()
    return true
end

-- drop every queued lookup (not the active one) and their callbacks: the page now shows another dungeon or none
function R.clear()
    for _, id in ipairs(queue) do waiting[id] = nil end
    for i = #queue, 1, -1 do queue[i] = nil end
    if cur and waiting[cur.id] then waiting[cur.id] = {} end
end

-- "npcID=displayID" lines of the cache, sorted by npcID (for baking into DungeonBossData.lua)
function R.dumpLines()
    local t, ids, out = cache(false) or {}, {}, {}
    for k, v in pairs(t) do
        if tonumber(k) and tonumber(v) and tonumber(v) > 0 then ids[#ids + 1] = tonumber(k) end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do out[#out + 1] = id .. "=" .. tonumber(t[id]) end
    return out
end

function R.dump()
    local lines = R.dumpLines()
    if #lines == 0 then
        ns.print("no boss display IDs found yet (open a dungeon's Bosses page first)")
    else
        ns.print(#lines .. " boss display ID" .. (#lines == 1 and "" or "s") .. " (npcID=displayID):")
        for _, l in ipairs(lines) do ns.print(l) end
    end
    local miss = {}
    for id in pairs(failed) do miss[#miss + 1] = id end
    if #miss > 0 then
        table.sort(miss)
        ns.print("not found this session: " .. table.concat(miss, ", "))
    end
end

-- for tests
function R._state() return { queue = queue, cur = cur, failed = failed, loading = loading, model = model } end

ns.on("PLAYER_LEAVING_WORLD", function() loading = true; interrupt() end)
ns.on("PLAYER_ENTERING_WORLD", function() loading = false; pump() end)
ns.on("PLAYER_REGEN_DISABLED", function() interrupt() end)
ns.on("PLAYER_REGEN_ENABLED", function() pump() end)

-- /qs bossdump: Core.lua's /qs handler stays as is; this one command is answered here first
do
    local slash = SlashCmdList and SlashCmdList["QUESTSHARING"]
    if type(slash) == "function" then
        SlashCmdList["QUESTSHARING"] = function(msg, ...)
            local cmd = string.lower(string.match(msg or "", "^%s*(%S*)") or "")
            if cmd == "bossdump" then
                if ns.commandAllowed and not ns.commandAllowed(cmd) then return end
                if ns.log then ns.log("command", "/qs " .. tostring(msg or "")) end
                R.dump()
                return
            end
            return slash(msg, ...)
        end
    end
end
