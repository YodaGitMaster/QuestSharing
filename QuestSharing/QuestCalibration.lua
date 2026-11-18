-- QuestCalibration.lua: learns how long the player really takes per kill and per quest giver visit, so the quest guide's
-- route times use their own pace. Watches only while the guide is open; no timers, nothing runs at login.
-- Public: get(), reset(), killSeconds(), interactionSeconds(), describe().
local ADDON, ns = ...

local K = {}
ns.questCalibration = K

local DEFAULT_KILL, DEFAULT_TALK = 10, 3
local KILL_MIN, KILL_MAX, TALK_MIN, TALK_MAX = 4, 40, 1, 15
local NEEDED, KEEP = 5, 40                 -- samples before the default is replaced; samples kept
local KILL_GAP_MIN, KILL_GAP_MAX, TALK_GAP_MAX = 1, 90, 60

local function store()
    if not ns.db then return { kill = {}, talk = {} } end
    local c = ns.db.plannerCalibration
    if type(c) ~= "table" then c = {}; ns.db.plannerCalibration = c end
    if type(c.kill) ~= "table" then c.kill = {} end
    if type(c.talk) ~= "table" then c.talk = {} end
    return c
end

local function median(list)
    local copy = {}
    for _, v in ipairs(list) do if type(v) == "number" then copy[#copy + 1] = v end end
    table.sort(copy)
    local n = #copy
    if n == 0 then return nil end
    if n % 2 == 1 then return copy[(n + 1) / 2] end
    return (copy[n / 2] + copy[n / 2 + 1]) / 2
end

local function add(list, value)
    list[#list + 1] = value
    while #list > KEEP do table.remove(list, 1) end
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function K.get()
    local c = store()
    local kill, talk = median(c.kill), median(c.talk)
    local killOK, talkOK = #c.kill >= NEEDED and kill ~= nil, #c.talk >= NEEDED and talk ~= nil
    return {
        killSeconds = killOK and clamp(kill, KILL_MIN, KILL_MAX) or DEFAULT_KILL,
        interactionSeconds = talkOK and clamp(talk, TALK_MIN, TALK_MAX) or DEFAULT_TALK,
        killSamples = #c.kill, interactionSamples = #c.talk,
        killCalibrated = killOK, interactionCalibrated = talkOK,
    }
end

function K.killSeconds() return K.get().killSeconds end
function K.interactionSeconds() return K.get().interactionSeconds end

local function seconds(v) return (string.gsub(string.format("%.1f", v), "%.0$", "")) end

function K.describe()
    local v = K.get()
    local kill = v.killCalibrated and string.format("%s s per kill, from %d kills", seconds(v.killSeconds), v.killSamples)
        or string.format("%s s per kill (default)", seconds(v.killSeconds))
    local talk = v.interactionCalibrated and string.format("%s s per quest giver, from %d visits", seconds(v.interactionSeconds), v.interactionSamples)
        or string.format("%s s per quest giver (default)", seconds(v.interactionSeconds))
    return kill .. "; " .. talk
end

function K.reset()
    ns.db.plannerCalibration = { kill = {}, talk = {} }
    K.lastTick, K.counts, K.shownAt = {}, nil, nil
end

-- Only watch while the quest guide is open.
local function watching() return ns.db and ns.questPlanner and ns.questPlanner.active and ns.questPlanner.active() end

K.lastTick = {}      -- objective key -> time its count last went up
K.counts = nil       -- objective key -> count at the last look

-- Kills and loot: each rise of an objective's count is a sample of the time since the previous rise.
function K.observe()
    if not watching() then K.counts = nil; return end
    local now = GetTime()
    local seen, fresh = {}, K.counts == nil
    K.counts = K.counts or {}
    for _, e in ipairs(ns.compat.entries()) do
        for j, o in ipairs(ns.compat.objectives(e)) do
            if (o.type == "monster" or o.type == "item") and type(o.have) == "number" then
                local key = tostring(e.questID or e.index) .. ":" .. j
                seen[key] = true
                local before = K.counts[key]
                if before and not fresh and o.have > before then
                    local n = o.have - before
                    local last = K.lastTick[key]
                    local gap = last and (now - last) or nil
                    if gap and gap >= KILL_GAP_MIN and gap <= KILL_GAP_MAX then
                        local list = store().kill
                        for _ = 1, n do add(list, gap / n) end
                    end
                    K.lastTick[key] = now
                elseif before and o.have < before then
                    K.lastTick[key] = nil
                end
                K.counts[key] = o.have
            end
        end
    end
    for key in pairs(K.counts) do if not seen[key] then K.counts[key], K.lastTick[key] = nil, nil end end
end

-- Quest givers: from the quest window opening to accepting or handing in.
local function opened() if watching() then K.shownAt = GetTime() end end
local function finished()
    local at = K.shownAt
    K.shownAt = nil
    if not (at and watching()) then return end
    local gap = GetTime() - at
    if gap >= 0 and gap <= TALK_GAP_MAX then add(store().talk, gap) end
end

ns.on("QUEST_LOG_UPDATE", function() K.observe() end)
ns.on("QUEST_DETAIL", opened)
ns.on("QUEST_COMPLETE", opened)
ns.on("QUEST_ACCEPTED", finished)
ns.on("QUEST_TURNED_IN", finished)
