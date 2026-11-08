-- Sync.lua: party members who also run Quest Sharing tell each other exactly which quests they have
-- and how far along they are, over the addon message channel (invisible to the players).
--
-- Messages (fields separated by "|", at most ~230 bytes):
--   H|1                   hello: "I run Quest Sharing"; answered with H and the full quest list
--   L|i|n|e1;e2;...       full quest list, part i of n.  entry = questID:complete(0/1):objectives
--   P|entry               one quest changed or was accepted
--   R|questID             a quest was removed (abandoned or turned in)
--   C|questID             all objectives of a quest are done
--   O|questID             I just offered this quest to the party (so the others do not offer it again)
-- objectives = comma separated  have/need  (counted)  or  f / u  (finished / unfinished, not counted)
local ADDON, ns = ...
local C = ns.compat

local PREFIX, VERSION = "QSHARE", 1
local key = ns.memberKey

ns.peers = {}              -- ns.peers[key] = { name, version, quests = { [id] = { complete, objs } }, listed }
local outbox, pumping = {}, false
local replied, members = {}, {}
local helloTimer, changedTimer

local function enabled() return ns.db.sync and C.inGroup() end

local function pump()
    local text = table.remove(outbox, 1)
    if not text then pumping = false; return end
    if enabled() then C.sendAddon(PREFIX, text, C.channel()) end
    ns.after(0.4, pump)                     -- stay far below the game's addon-message rate limit
end

local function queue(text)
    if not enabled() then return end
    outbox[#outbox + 1] = text
    if not pumping then pumping = true; pump() end
end

-- changes we make are only worth sending when someone is listening
function ns.syncUpdate(text)
    if next(ns.peers) then queue(text) end
end

-- When several people in the party run Quest Sharing, they take turns instead of all talking at once. The order is
-- simply the names in alphabetical order: 1 = first. Everyone works it out the same way, without asking.
function ns.addonRank()
    local mine = key(C.player())
    local list = { mine }
    for k in pairs(ns.peers) do list[#list + 1] = k end
    table.sort(list)
    for i, k in ipairs(list) do if k == mine then return i, #list end end
    return 1, #list
end

-- seconds to wait before saying something the others might say too (0 for the first in line)
function ns.turnDelay()
    local rank = ns.addonRank()
    return (rank - 1) * 1.5
end

ns.recentDone = {}         -- ns.recentDone[questID] = time a party member running the addon finished its objectives

-- Encoding -----------------------------------------------------------------------------------------
local function encodeObjectives(objs)
    local t = {}
    for _, o in ipairs(objs) do
        if o.have and o.need then t[#t + 1] = o.have .. "/" .. o.need else t[#t + 1] = o.finished and "f" or "u" end
    end
    return table.concat(t, ",")
end

ns.encodeObjectives = encodeObjectives

function ns.encodeEntry(e)
    return string.format("%d:%d:%s", e.questID, e.complete and 1 or 0, encodeObjectives(C.objectives(e)))
end

local function parseEntry(s)
    local id, c, objs = string.match(s, "^(%d+):([01]):(.*)$")
    if id then return tonumber(id), { complete = (c == "1"), objs = objs } end
end

local function sendFull()
    local chunks, cur = {}, ""
    for _, e in ipairs(C.entries()) do
        local en = ns.encodeEntry(e)
        if cur ~= "" and #cur + #en + 1 > 200 then
            chunks[#chunks + 1] = cur
            cur = en
        else
            cur = (cur == "") and en or (cur .. ";" .. en)
        end
    end
    if cur ~= "" or #chunks == 0 then chunks[#chunks + 1] = cur end      -- an empty log is still an answer
    for i, c in ipairs(chunks) do queue(string.format("L|%d|%d|%s", i, #chunks, c)) end
end

-- Receiving ----------------------------------------------------------------------------------------
function ns.peerHas(k, questID)
    local peer = ns.peers[k]
    if not (peer and peer.listed) then return nil end
    return peer.quests[questID] ~= nil
end

local function changed()
    if changedTimer then return end
    changedTimer = ns.after(0.5, function()
        changedTimer = nil
        if ns.refreshPanel then ns.refreshPanel() end
        if ns.refreshQuestLog then ns.refreshQuestLog() end
    end)
end

local function memberByKey(k)
    for _, m in ipairs(C.members()) do if key(m.name) == k then return m end end
end

local function handle(sender, text)
    local k = key(sender)
    if k == key(C.player()) then return end
    local m = memberByKey(k)
    if not m then return end                                       -- only people in our party
    local kind, rest = string.match(text, "^(%a)|(.*)$")
    if not kind then return end
    local peer = ns.peers[k]
    if kind == "H" then
        peer = peer or { name = m.name, quests = {}, listed = false }
        peer.version = tonumber(rest) or 1
        ns.peers[k] = peer
        if GetTime() - (replied[k] or -1000) > 30 then            -- answer once, no ping-pong
            replied[k] = GetTime()
            queue("H|" .. VERSION)
            sendFull()
        end
        changed()
        return
    end
    if not peer then return end                                    -- no hello yet: ignore
    if kind == "L" then
        local i, n, entries = string.match(rest, "^(%d+)|(%d+)|(.*)$")
        i, n = tonumber(i), tonumber(n)
        if not (i and n and n > 0) then return end
        if i == 1 or not peer.chunks or peer.chunks.n ~= n then peer.chunks = { n = n } end
        peer.chunks[i] = entries
        local got = 0
        for j = 1, n do if peer.chunks[j] then got = got + 1 end end
        if got == n then
            local quests = {}
            for j = 1, n do
                for en in string.gmatch(peer.chunks[j], "[^;]+") do
                    local id, rec = parseEntry(en)
                    if id then quests[id] = rec end
                end
            end
            peer.quests, peer.listed, peer.chunks = quests, true, nil
            changed()
        end
    elseif kind == "P" then
        local id, rec = parseEntry(rest)
        if id then peer.quests[id] = rec; changed() end
    elseif kind == "R" then
        local id = tonumber(rest)
        if id then peer.quests[id] = nil; changed() end
    elseif kind == "O" then                                       -- they offered it: nobody else needs to
        local id = tonumber(rest)
        if id and ns.markOffered then ns.markOffered(id) end
        if id and ns.offeredBy then ns.offeredBy[id] = GetTime() end          -- if I take it now, it came from them
    elseif kind == "C" then
        local id = tonumber(rest)
        if not id then return end
        local rec = peer.quests[id] or { objs = "" }
        rec.complete = true
        peer.quests[id] = rec
        local e = C.findEntry(id)
        ns.recentDone[id] = GetTime()
        if e and ns.goodNews then ns.goodNews() end           -- no chat line: the Party quests window shows a check
        changed()
    end
end

ns.on("CHAT_MSG_ADDON", function(_, prefix, text, _, sender)
    if prefix == PREFIX and ns.db.sync and text and sender then handle(sender, text) end
end)

-- Party membership: say hello to newcomers, forget people who left ----------------------------------------
local function onRoster()
    local set, n = {}, 0
    for _, m in ipairs(C.members()) do set[key(m.name)] = true; n = n + 1 end
    if n == 0 then
        ns.peers, replied, members, outbox, pumping = {}, {}, {}, {}, false
        if helloTimer then ns.cancel(helloTimer); helloTimer = nil end
        return
    end
    local fresh = false
    for k in pairs(set) do if not members[k] then fresh = true end end
    for k in pairs(ns.peers) do if not set[k] then ns.peers[k] = nil; replied[k] = nil end end
    members = set
    if fresh and ns.db.sync then
        if helloTimer then ns.cancel(helloTimer) end
        helloTimer = ns.after(2, function() helloTimer = nil; queue("H|" .. VERSION) end)
    end
end

ns.on("GROUP_ROSTER_UPDATE", onRoster)
ns.on("GROUP_JOINED", onRoster)
ns.on("PARTY_MEMBERS_CHANGED", onRoster)

local function register()
    ns.prefixRegistered = C.registerPrefix(PREFIX)
end
ns.on("PLAYER_LOGIN", register)
ns.on("PLAYER_ENTERING_WORLD", register)
register()
