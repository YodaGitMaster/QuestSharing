-- Friends.lua (BETA): add the people you group with to your friends list.
--   /qs friends        add everybody in your party now
--   /qs friends on     also do it automatically when a party forms or someone joins (off by default)
--
-- Careful by design: skips people who are already friends or ignored, players from another realm where the
-- client cannot add them, and random dungeon-finder groups; never fills the last 5 friend slots on its own;
-- one add every 1.5 seconds. The game answers each add with a system message, which is read here.
local ADDON, ns = ...
local C = ns.compat
local key = ns.memberKey

local GAP = 1.5          -- seconds between two adds
local RESERVE = 5        -- friend slots the automatic mode never uses
local SETTLE = 8         -- seconds to wait after the party changes

local run                -- the adding in progress
local group = { ready = false, joined = false, names = {} }
local pending

-- The game's replies (its own ERR_FRIEND_* strings, so every language works) ------------------------------
local WHITELIST = { ADDED_S = "added", ALREADY_S = "already", NOT_FOUND = "notfound", LIST_FULL = "full",
                    SELF = "self", WRONG_FACTION = "faction", ERROR = "error" }
local patterns

local function buildPatterns()
    patterns = {}
    for suffix, kind in pairs(WHITELIST) do
        local fmt = _G["ERR_FRIEND_" .. suffix]
        if type(fmt) == "string" then
            local pat = string.gsub(fmt, "([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
            local hasName = string.find(pat, "%s", 1, true) ~= nil
            pat = string.gsub(pat, "%%s", "(.+)")
            patterns[#patterns + 1] = { pat = "^" .. pat .. "$", kind = kind, hasName = hasName }
        end
    end
end

function ns.friendPatternCount()
    if not patterns then buildPatterns() end
    return #patterns
end

local lastReply = { text = "", at = -10 }

local function onReply(kind, name)
    if not run then return end
    local who
    if name then
        for _, m in ipairs(run.members) do if key(m.name) == key(name) then who = m end end
    end
    who = who or run.current
    if not who then return end
    run.results[key(who.name)] = kind
    if kind == "full" then run.queue = {} end                 -- no point in trying more
end

local function handleText(text)
    if not text then return end
    if not patterns then buildPatterns() end
    if text == lastReply.text and GetTime() - lastReply.at < 0.5 then return end      -- the same message from two events
    for _, p in ipairs(patterns) do
        local name = string.match(text, p.pat)
        if name or (not p.hasName and text == (string.gsub(p.pat, "[%^%$]", ""))) then
            lastReply = { text = text, at = GetTime() }
            onReply(p.kind, p.hasName and name or nil)
            return
        end
    end
end

ns.on("CHAT_MSG_SYSTEM", function(_, text) handleText(text) end)
ns.on("UI_ERROR_MESSAGE", function(_, a, b) handleText((type(b) == "string") and b or a) end)

-- The adding -------------------------------------------------------------------------------------------------
local LABEL = { added = "added", already = "already friends", notfound = "not found", full = "your list is full",
                self = "that is you", faction = "other faction", error = "the game refused" }

-- "added: Anna, Bob | already friends: Cy | no room: Dee"
local function describe(r)
    local groups, order = {}, {}
    local function put(label, name)
        if not groups[label] then groups[label] = {}; order[#order + 1] = label end
        table.insert(groups[label], name)
    end
    for _, m in ipairs(r.members) do
        local k = key(m.name)
        local kind = r.results[k]
        if r.skipped[k] then
            put(r.skipped[k], m.name)
        elseif kind then
            put(LABEL[kind] or kind, m.name)
        elseif r.sent[k] then
            if C.isFriend(C.fullName(m)) then put("added", m.name) else put("no answer", m.name) end
        end
    end
    local parts = {}
    for _, label in ipairs(order) do parts[#parts + 1] = label .. ": " .. table.concat(groups[label], ", ") end
    return parts
end

local function finish()
    local r = run
    run = nil
    if not r then return end
    for _, m in ipairs(r.members) do
        local kind = r.results[key(m.name)]
        if kind == "added" or kind == "already" or (r.sent[key(m.name)] and not kind and C.isFriend(C.fullName(m))) then
            ns.friended[key(m.name)] = true
        end
    end
    local parts = describe(r)
    ns.print("friends (beta): " .. (#parts > 0 and table.concat(parts, " | ") or "nobody to add"))
end

local function step()
    if not run then return end
    local m = table.remove(run.queue, 1)
    if not m then
        run.timer = ns.after(3, finish)
        return
    end
    run.current = m
    run.sent[key(m.name)] = true
    local note = string.sub("Quest Sharing: " .. (C.zone() or ""), 1, 48)
    if ns.isBlocked("friends") then return ns.stopFriends() end
    ns.trying("adding a friend", "friends")
    if not C.addFriend(C.fullName(m), note) then run.results[key(m.name)] = "error" end
    run.timer = ns.after(GAP, step)
end

ns.friended = {}         -- people handled in this party

function ns.stopFriends() if run then if run.timer then ns.cancel(run.timer) end run = nil end end

function ns.addPartyFriends(manual)
    local d = ns.db
    local say = manual and ns.print or function() end
    if not d.enabled then return say("the addon is switched off (/qs on)") end
    if not C.canAddFriend() then return say("this client has no call to add friends") end
    if run then return say("already adding friends") end
    if not C.inGroup() then return say("you are not in a party") end
    if C.inRaid() then return say("adding friends works in a 5-player party, not a raid") end
    if not manual and C.inInstanceGroup() then
        return ns.print("friends (beta): not adding people from a random / instance group (type /qs friends to do it anyway)")
    end
    local members = C.members()
    if #members == 0 then return say("no party members found yet") end

    run = { members = members, queue = {}, results = {}, skipped = {}, sent = {} }
    for _, m in ipairs(members) do
        local k = key(m.name)
        local full = C.fullName(m)
        if not manual and ns.friended[k] then
            run.skipped[k] = nil                                      -- handled earlier in this party: stay quiet
        elseif C.isFriend(full) then
            run.skipped[k] = "already friends"
            ns.friended[k] = true
        elseif C.isIgnored(full) then
            run.skipped[k] = "ignored"
        elseif m.realm and m.realm ~= "" and not C.modern then
            run.skipped[k] = "other realm"
        else
            run.queue[#run.queue + 1] = m
        end
    end

    local room = C.maxFriends() - C.friendCount() - (manual and 0 or RESERVE)
    if #run.queue > math.max(room, 0) then
        for i = #run.queue, math.max(room, 0) + 1, -1 do
            run.skipped[key(run.queue[i].name)] = "no room"
            run.queue[i] = nil
        end
        ns.print(string.format("friends (beta): your list has %d of %d friends, not adding more than fits", C.friendCount(), C.maxFriends()))
    end
    if #run.queue == 0 then
        local r = run
        run = nil
        local parts = describe(r)
        if manual or #parts > 0 then
            ns.print("friends (beta): nobody to add" .. (#parts > 0 and (" - " .. table.concat(parts, " | ")) or ""))
        end
        return
    end
    ns.print(string.format("friends (beta): adding %d player(s), one every %.1f seconds", #run.queue, GAP))
    step()
end

-- Automatic mode (beta, off by default) ---------------------------------------------------------------------------
local function schedule()
    if pending then ns.cancel(pending) end
    pending = ns.after(SETTLE, function()
        pending = nil
        if run then schedule() else ns.addPartyFriends(false) end
    end)
end

local function snapshot()
    local set, n = {}, 0
    for _, m in ipairs(C.members()) do set[key(m.name)] = true; n = n + 1 end
    return set, n
end

local function onRoster()
    if not group.ready then return end
    local set, n = snapshot()
    if not C.inGroup() or n == 0 then
        if group.joined then
            group.joined, group.names, ns.friended = false, {}, {}
            if pending then ns.cancel(pending); pending = nil end
            ns.stopFriends()
        end
        return
    end
    local fresh = not group.joined
    for k in pairs(set) do if not group.names[k] then fresh = true end end
    group.joined, group.names = true, set
    if fresh and ns.db.enabled and ns.db.friends then schedule() end
end

ns.on("PLAYER_ENTERING_WORLD", function()
    local set, n = snapshot()                                     -- a party you were already in is not "new"
    group.ready, group.joined, group.names = true, C.inGroup() and n > 0, set
end)
ns.on("GROUP_ROSTER_UPDATE", onRoster)
ns.on("GROUP_JOINED", onRoster)
ns.on("PARTY_MEMBERS_CHANGED", onRoster)
