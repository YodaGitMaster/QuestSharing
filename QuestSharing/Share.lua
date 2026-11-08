-- Share.lua: notice a new party, push the quests of the area one by one, read the game's replies
-- (accepted / declined / already on it / ...) and tell the party which quests we have in common.
local ADDON, ns = ...
local C = ns.compat

ns.known = {}             -- ns.known[questID][lowercased member name] = "has" | "accepted" | "declined" | "done" | ...
ns.offered = {}           -- ns.offered[questID][lowercased member name] = true once a share has reached them
local run                 -- the share in progress (nil when idle)
local lastPush            -- { id = questID, at = time } of the most recent push
local group = { joined = false, names = {}, ready = false }
local pendingJoin
local decide                -- defined below (the push step needs it too)

local function key(name)
    name = tostring(name or "")
    return string.lower(string.match(name, "^([^-]+)") or name)
end
ns.memberKey = key

-- every current party member has been offered this quest (by us, or by another Quest Sharing user: "O|" message)
function ns.markOffered(questID)
    ns.offered[questID] = ns.offered[questID] or {}
    for _, m in ipairs(C.members()) do ns.offered[questID][key(m.name)] = true end
end

-- Quests that somebody else just named in party chat (a link in their message), so we do not say them again
ns.recentlySaid = {}
local SAID_FOR = 120
local function heard(_, text, sender)
    if not (text and sender) then return end
    if key(sender) == key(C.player()) then return end
    for id in string.gmatch(text, "|Hquest:(%d+)") do ns.recentlySaid[tonumber(id)] = GetTime() end
end
for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
    ns.on(ev, heard)
end
local function saidLately(id) return ns.recentlySaid[id] and GetTime() - ns.recentlySaid[id] < SAID_FOR end
ns.saidLately = saidLately

local function setKnown(questID, name, status)
    if not questID then return end
    ns.known[questID] = ns.known[questID] or {}
    ns.known[questID][key(name)] = status
end

-- Members who are on this quest from before we shared it ("has"), by what we learnt so far.
local function peerHas(m, e)
    return ns.peerHas and ns.peerHas(key(m.name), e.questID)       -- true / false / nil (nil = not a synced player)
end

local function commonNames(e)
    local names = {}
    for _, m in ipairs(C.members()) do
        local st = ns.known[e.questID] and ns.known[e.questID][key(m.name)]
        local ph = peerHas(m, e)
        if ph == true or (ph == nil and (st == "has" or C.unitOnQuest(m.unit, e) == true)) then
            names[#names + 1] = m.name
        end
    end
    return names
end

-- Members who have the quest now, either from before or because they just accepted ours.
function ns.partyHas(e)
    local names = {}
    for _, m in ipairs(C.members()) do
        local st = ns.known[e.questID] and ns.known[e.questID][key(m.name)]
        local ph = peerHas(m, e)
        if ph == true or (ph == nil and (st == "has" or st == "accepted" or C.unitOnQuest(m.unit, e) == true)) then
            names[#names + 1] = m.name
        end
    end
    return names
end

-- The game's replies to a push --------------------------------------------------------------------
-- The messages are the client's own ERR_QUEST_PUSH_*_S strings, turned into patterns, so this works
-- in every language.
local KIND = { ACCEPTED = "accepted", DECLINED = "declined", ONQUEST = "has", ALREADY_DONE = "done",
               BUSY = "busy", LOG_FULL = "full", DEAD = "dead", SUCCESS = "sent", TIMER_EXPIRED = "expired" }
local patterns

local function buildPatterns()
    patterns = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "string" then
            local suffix = string.match(k, "^ERR_QUEST_PUSH_(.+)_S$")
            if suffix then
                local pat = string.gsub(v, "([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
                pat = string.gsub(pat, "%%s", "(.+)")
                patterns[#patterns + 1] = { pat = "^" .. pat .. "$", kind = KIND[suffix] or "other" }
            end
        end
    end
end

function ns.patternCount()
    if not patterns then buildPatterns() end
    return #patterns
end

local WORDS = { accepted = "accepted", declined = "declined", done = "has already done", busy = "is busy",
                full = "has a full quest log", dead = "is dead", expired = "did not answer in time",
                other = "cannot take it" }

function ns.onPushReply(kind, name)
    if kind == "sent" then return end
    local id = (run and run.current) or (lastPush and GetTime() - lastPush.at < 15 and lastPush.id)
    if not id then return end
    local status = kind
    setKnown(id, name, status)
    if run then
        run.results[id] = run.results[id] or {}
        run.results[id][key(name)] = { name = name, kind = kind }
    end
    if kind == "accepted" and ns.goodNews then ns.goodNews() end            -- the round's summary says the rest
end

ns.on("CHAT_MSG_SYSTEM", function(_, msg)
    if not msg then return end
    if not patterns then buildPatterns() end
    for _, p in ipairs(patterns) do
        local name = string.match(msg, p.pat)
        if name then ns.onPushReply(p.kind, name); return end
    end
end)

-- Announcing quests in common ------------------------------------------------------------------------
local GREETINGS = { "Hey %s! Looks like we have these quests in common:",
                    "Hi %s! Seems like we share these quests:",
                    "Hey %s, we seem to have these quests in common:" }
local TAILS = { " Let's do them together :)", " Want to tackle them together? :)" }

local function joinNames(list)
    table.sort(list)
    if #list == 0 or #list > 3 then return "team" end
    if #list == 1 then return list[1] end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- at most two lines, whatever the number of quests: the rest is "and 6 more"
local MAX_LINES = 2
local function announce(links, names)
    if #links == 0 then return end
    local prefix = string.format(ns.pick(GREETINGS), joinNames(names)) .. " "
    local messages = ns.chunk(links, prefix, ", ", 225)
    if #messages > MAX_LINES then
        local kept = 0
        for i = 1, MAX_LINES do local _, n = string.gsub(messages[i], "|Hquest:", ""); kept = kept + n end
        messages = { messages[1], messages[2] .. " and " .. (#links - kept) .. " more" }
    end
    local tail = ns.pick(TAILS)
    local last = #messages
    if #messages[last] + #tail <= 255 then messages[last] = messages[last] .. tail end
    for _, m in ipairs(messages) do ns.say(m) end
end

-- The share ----------------------------------------------------------------------------------------
local finish

local function step()
    if not run then return end
    if not C.inGroup() then return ns.stopShare("you left the party") end
    local q = table.remove(run.queue, 1)
    if not q then
        run.finishing = true
        run.timer = ns.after(run.grace, finish)
        return
    end
    run.finishing = false
    local e = C.findEntry(q.questID)            -- it may have been abandoned or turned in meanwhile
    local delay = 0.1
    -- look again right before: another Quest Sharing user may have offered it meanwhile, or the player took it
    local still = e and decide(e, C.members(), run.force) == "push"
    if e and C.pushable(e) and still then
        run.current = e.questID
        lastPush = { id = e.questID, at = GetTime() }
        C.push(e)
        run.pushed = run.pushed + 1
        ns.markOffered(e.questID)
        if ns.syncUpdate then ns.syncUpdate("O|" .. e.questID) end      -- the others will not offer it again
        delay = ns.db.gap
    else
        run.skipped = run.skipped + 1
    end
    run.timer = ns.after(delay, step)
end

-- the quests in common worth saying now: not ones somebody else just named in party chat
local function inCommon(r)
    local links, names, seen = {}, {}, {}
    for _, e in ipairs(r.entries) do
        local with = commonNames(e)
        if #with > 0 and not saidLately(e.questID) then
            links[#links + 1] = C.link(e)
            for _, n in ipairs(with) do if not seen[n] then seen[n] = true; names[#names + 1] = n end end
        end
    end
    return links, names
end

-- one short line for you: who took what (only when something was shared, or when you asked for it)
local function summary(r)
    local took, said, missed = {}, {}, 0
    local MISSED = { busy = true, full = true, dead = true, expired = true, other = true }
    for _, per in pairs(r.results) do
        for _, res in pairs(per) do
            if res.kind == "accepted" then took[res.name] = (took[res.name] or 0) + 1
            elseif res.kind == "declined" then said[#said + 1] = res.name
            elseif MISSED[res.kind] then missed = missed + 1 end
        end
    end
    if r.pushed == 0 and r.reason ~= "manual" then return end
    local parts = {}
    local names = {}
    for n in pairs(took) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do parts[#parts + 1] = string.format("%s took %d", n, took[n]) end
    if #said > 0 then parts[#parts + 1] = #said .. " declined" end
    if missed > 0 then parts[#parts + 1] = missed .. " could not take it right now" end
    ns.print(string.format("shared %d quest%s with the party%s", r.pushed, r.pushed == 1 and "" or "s",
        #parts > 0 and (": " .. table.concat(parts, ", ")) or ""))
end

finish = function()
    local r = run
    run = nil
    if not r then return end
    summary(r)
    -- a quest you just accepted is no news to the party (they are usually the ones who gave it to you)
    if r.reason == "new quest" or not ns.db.chat then return end
    ns.after(ns.turnDelay and ns.turnDelay() or 0, function()        -- the first Quest Sharing user in line speaks first
        if not C.inGroup() then return end
        announce(inCommon(r))
    end)
end

function ns.stopShare(reason)
    if not run then return end
    if run.timer then ns.cancel(run.timer) end
    run = nil
    ns.print("sharing stopped (" .. (reason or "?") .. ")")
end

function ns.isSharing() return run ~= nil end

-- Does this quest need to be pushed? Returns "push", or why not:
--   "known"    everybody already has it
--   "offered"  everybody who lacks it was already offered it (we never repeat an offer)
--   "declined" someone who lacks it declined it before and a repeat would pop it up on them again
decide = function(e, members, force)
    local lacking, fresh, decliner = 0, 0, false
    for _, m in ipairs(members) do
        local st = ns.known[e.questID] and ns.known[e.questID][key(m.name)]
        local ph = peerHas(m, e)
        local has
        if ph == true or (ph == nil and C.unitOnQuest(m.unit, e) == true) then
            setKnown(e.questID, m.name, "has")
            has = true
        elseif ph == false then
            has = false                                   -- a synced player's list is exact
        else
            has = (st == "has" or st == "accepted")
        end
        if not has then
            lacking = lacking + 1
            if st == "declined" or st == "expired" then decliner = true end
            if force or not (ns.offered[e.questID] and ns.offered[e.questID][key(m.name)]) then fresh = fresh + 1 end
        end
    end
    if lacking == 0 then return "known" end
    if fresh == 0 then return "offered" end
    if decliner and not force then return "declined" end
    return "push"
end

-- opts.only = { [questID] = true } shares just those quests (a quest you just accepted).
-- Called with reason "manual" (/qs share) it repeats offers and ignores earlier declines; every automatic
-- round shares each quest with each member at most once and never nags someone who declined.
function ns.startShare(reason, opts)
    local d = ns.db
    opts = opts or {}
    local quiet = opts.only ~= nil
    if not d.enabled then return not quiet and ns.print("the addon is switched off (/qs on)") end
    if run then return not quiet and ns.print("already sharing (/qs stop to cancel)") end
    if not C.inGroup() then return not quiet and ns.print("you are not in a party") end
    if C.inRaid() then return not quiet and ns.print("quests can only be shared in a 5-player party, not a raid") end
    local members = C.members()
    if #members == 0 then return not quiet and ns.print("no party members found yet") end

    local entries = {}
    for _, e in ipairs(C.entries()) do
        if opts.only then
            if opts.only[e.questID] then entries[#entries + 1] = e end
        elseif d.area == "all" or C.inArea(e) then
            entries[#entries + 1] = e
        end
    end
    if #entries == 0 then
        if quiet then return end
        return ns.print(d.area == "all" and "you have no quests" or ("you have no quests in " .. C.zone() .. " (/qs area all)"))
    end

    local force = (reason == "manual")
    run = { queue = {}, entries = entries, entryIds = {}, results = {}, pushed = 0, skipped = 0, grace = 6, reason = reason, force = force }
    local why = { known = 0, offered = 0, declined = 0 }
    for _, e in ipairs(entries) do
        run.entryIds[e.questID] = true
        local verdict = decide(e, members, force)
        if verdict == "push" and not C.pushable(e) then verdict = "unshareable" end      -- a quest the game never lets you share
        if verdict == "push" then run.queue[#run.queue + 1] = { questID = e.questID } else why[verdict] = (why[verdict] or 0) + 1 end
    end
    local notes = {}
    if why.known > 0 then notes[#notes + 1] = why.known .. " already with everyone" end
    if why.offered > 0 then notes[#notes + 1] = why.offered .. " offered before" end
    if why.declined > 0 then notes[#notes + 1] = why.declined .. " skipped, someone declined them (/qs share forces it)" end
    if (why.unshareable or 0) > 0 then notes[#notes + 1] = why.unshareable .. " cannot be shared" end
    if force then                                                 -- only when you asked for it; automatic rounds stay quiet
        ns.print(string.format("sharing %d quest(s) with %d player(s), %d second(s) apart%s (/qs stop to cancel)",
            #run.queue, #members, d.gap, #notes > 0 and (" - " .. table.concat(notes, ", ")) or ""))
    end
    step()
end

-- A quest you just accepted ------------------------------------------------------------------------------
-- Offered once, to the party you are in. Accepts that come close together are batched into one round.
local newIds, newTimer = {}, nil

local function flushNew()
    newTimer = nil
    local ids = newIds
    newIds = {}
    local d = ns.db
    if not (d.enabled and d.auto and d.shareNew and C.inGroup() and not C.inRaid()) then return end
    if run then                                                   -- a round is running: add them to it
        local members = C.members()
        for _, id in ipairs(ids) do
            local e = C.findEntry(id)
            if e and not run.entryIds[id] then
                run.entryIds[id] = true
                run.entries[#run.entries + 1] = e
                if decide(e, members, false) == "push" then run.queue[#run.queue + 1] = { questID = id } end
            end
        end
        if run.finishing then                                     -- the queue had already drained: carry on
            ns.cancel(run.timer)
            step()
        end
        return
    end
    local only = {}
    for _, id in ipairs(ids) do only[id] = true end
    ns.startShare("new quest", { only = only })
end

function ns.shareNewQuest(id)
    if not (id and ns.db.enabled and ns.db.auto and ns.db.shareNew and C.inGroup()) then return end
    newIds[#newIds + 1] = id
    if not newTimer then newTimer = ns.after(3, flushNew) end
end

-- classic: QUEST_ACCEPTED(logIndex, questID), modern: QUEST_ACCEPTED(questID)
ns.on("QUEST_ACCEPTED", function(_, first, second) ns.shareNewQuest(second or first) end)

-- Noticing a new party -------------------------------------------------------------------------------
-- waited = the turn was already taken into account. The order among Quest Sharing users is only known once their addons
-- said hello (a couple of seconds after joining), so it is looked at when the round is about to start.
local function schedule(delay, reason, waited)
    if pendingJoin then ns.cancel(pendingJoin) end
    pendingJoin = ns.after(delay, function()
        pendingJoin = nil
        local turn = (not waited and ns.turnDelay) and ns.turnDelay() * 2 or 0
        if turn > 0 then return schedule(turn, reason, true) end   -- someone first in line goes first
        if run then schedule(5, reason, true) else ns.startShare(reason) end
    end)
end
local function scheduleTurn(reason) schedule(ns.db.settle, reason) end

local function snapshot()
    local set, n = {}, 0
    for _, m in ipairs(C.members()) do set[key(m.name)] = m.name; n = n + 1 end
    return set, n
end

local function onRoster()
    if not group.ready then return end
    local d = ns.db
    local set, n = snapshot()
    if not C.inGroup() or n == 0 then
        if group.joined then
            group.joined, group.names = false, {}
            ns.known, ns.offered = {}, {}
            if pendingJoin then ns.cancel(pendingJoin); pendingJoin = nil end
            ns.stopShare("you left the party")
        end
        return
    end
    if not group.joined then
        group.joined, group.names = true, set
        ns.known, ns.offered = {}, {}
        if d.enabled and d.auto then scheduleTurn("joined a party") end
        return
    end
    local fresh = false
    for k in pairs(set) do if not group.names[k] then fresh = true end end
    for _, tbl in ipairs({ ns.known, ns.offered }) do      -- forget what we knew about people who left
        for k in pairs(tbl) do
            for who in pairs(tbl[k]) do if not set[who] then tbl[k][who] = nil end end
        end
    end
    group.names = set
    if fresh and d.enabled and d.auto then scheduleTurn("a new member joined") end
end

ns.on("PLAYER_ENTERING_WORLD", function()
    -- at login / loading screen we are just looking: a party you were already in is not "new"
    local set, n = snapshot()
    group.ready = true
    group.joined = C.inGroup() and n > 0
    group.names = set
end)
ns.on("GROUP_ROSTER_UPDATE", onRoster)
ns.on("GROUP_JOINED", onRoster)
ns.on("PARTY_MEMBERS_CHANGED", onRoster)
