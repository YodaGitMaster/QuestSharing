-- Compat.lua: one place that knows the differences between the classic and the modern quest APIs.
-- Everything else in the addon talks to ns.compat only.
local ADDON, ns = ...
local C = {}
ns.compat = C

C.modern = (C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries) and true or false

local function lower(s) return string.lower(s or "") end

-- parse "Kobold Worker slain: 3/8" and "3/8 Kobold Worker slain" -> name, have, need
function C.parseObjective(text)
    text = text or ""
    local name, have, need = string.match(text, "^(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
    if not name then
        have, need, name = string.match(text, "^(%d+)%s*/%s*(%d+)%s+(.+)$")
    end
    if name then return name, tonumber(have), tonumber(need) end
    return text, nil, nil
end

-- All quests in the log, in order: { index, questID, title, level, header, complete }
function C.entries()
    local out, header = {}, nil
    if C.modern then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info then
                if info.isHeader then
                    header = info.title
                elseif info.questID and not info.isHidden then
                    local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false
                    out[#out + 1] = { index = i, questID = info.questID, title = info.title,
                                      level = info.level, header = header, complete = done and true or false }
                end
            end
        end
    else
        for i = 1, GetNumQuestLogEntries() do
            local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
            if title then
                if isHeader then
                    header = title
                else
                    local done = (type(isComplete) == "number") and isComplete > 0 or (isComplete == true)
                    out[#out + 1] = { index = i, questID = questID, title = title, level = level,
                                      header = header, complete = done }
                end
            end
        end
    end
    return out
end

-- questID -> entry, for code that has to look up many quests: one scan instead of one per lookup
function C.entryMap()
    local m = {}
    for _, e in ipairs(C.entries()) do m[e.questID] = e end
    return m
end

function C.findEntry(questID, index)
    for _, e in ipairs(C.entries()) do
        if (questID and e.questID == questID) or (not questID and index and e.index == index) then return e end
    end
end

-- objectives: { text, name, have, need, finished }
function C.objectives(e)
    local out = {}
    if C.modern then
        for _, o in ipairs(C_QuestLog.GetQuestObjectives(e.questID) or {}) do
            local name, have, need = C.parseObjective(o.text)
            out[#out + 1] = { text = o.text or "", name = name, finished = o.finished and true or false,
                              have = o.numFulfilled or have, need = o.numRequired or need }
        end
    else
        for j = 1, (GetNumQuestLeaderBoards(e.index) or 0) do
            local text, _, done = GetQuestLogLeaderBoard(j, e.index)
            local name, have, need = C.parseObjective(text)
            out[#out + 1] = { text = text or "", name = name, finished = done and true or false,
                              have = have, need = need }
        end
    end
    return out
end

function C.link(e)
    local l
    if GetQuestLink then l = GetQuestLink(C.modern and e.questID or e.index) end
    return l or string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", e.questID or 0, e.level or 0, e.title or "?")
end

-- Sharing -------------------------------------------------------------------------------------
-- Selecting a quest changes which quest the player has open in the quest log, so every call that
-- needs a selection puts the player's own selection back afterwards.
local function getSelection()
    if C.modern and C_QuestLog.GetSelectedQuest then return C_QuestLog.GetSelectedQuest() end
    if GetQuestLogSelection then return GetQuestLogSelection() end
end

local function select_(e)
    if C.modern and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(e.questID)
    elseif SelectQuestLogEntry then SelectQuestLogEntry(e.index) end
end

local function restoreSelection(previous)
    if previous == nil or previous == 0 then return end
    if C.modern and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(previous)
    elseif SelectQuestLogEntry then SelectQuestLogEntry(previous) end
end

function C.pushable(e)
    if C.modern and C_QuestLog.IsPushableQuest then
        return C_QuestLog.IsPushableQuest(e.questID) and true or false
    end
    if SelectQuestLogEntry and GetQuestLogPushable then
        local previous = getSelection()
        SelectQuestLogEntry(e.index)
        local ok = GetQuestLogPushable()
        restoreSelection(previous)
        return ok and true or false
    end
    return true
end

function C.push(e)
    local previous = getSelection()
    select_(e)
    QuestLogPushQuest()
    restoreSelection(previous)
end

-- true / false / nil (nil = this client cannot tell). Only true is reliable: false can also mean
-- "no data for that player yet".
function C.unitOnQuest(unit, e)
    if C_QuestLog and C_QuestLog.IsUnitOnQuest and e.questID then
        local ok, r = pcall(C_QuestLog.IsUnitOnQuest, unit, e.questID)
        if ok then return r and true or false end
    end
    if IsUnitOnQuest and e.index then
        local ok, r = pcall(IsUnitOnQuest, e.index, unit)
        if ok then return (r == true or r == 1) end
    end
    return nil
end

-- Group ---------------------------------------------------------------------------------------
function C.inGroup()
    if IsInGroup then return IsInGroup() and true or false end
    return (GetNumPartyMembers and GetNumPartyMembers() > 0) and true or false
end

function C.inRaid() return IsInRaid and IsInRaid() and true or false end

-- party units other than the player: { unit, name } (name without realm)
function C.members()
    local out = {}
    if C.inRaid() then return out end           -- quests can only be pushed inside a 5-player party
    local n = (GetNumSubgroupMembers and GetNumSubgroupMembers()) or (GetNumPartyMembers and GetNumPartyMembers()) or 0
    for i = 1, n do
        local unit = "party" .. i
        local name, realm = UnitName(unit)
        if name then out[#out + 1] = { unit = unit, name = name, realm = realm } end
    end
    return out
end

function C.channel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if C.inRaid() then return "RAID" end
    return "PARTY"
end

function C.slashFor(channel)
    return ({ INSTANCE_CHAT = "/i ", RAID = "/raid ", PARTY = "/p " })[channel] or "/p "
end

-- Cut a chat message to at most `max` bytes without breaking it: never in the middle of a quest link (the game refuses
-- a message with half a link), of a letter like "è" (two bytes), or of an escaped "||".
function C.safeCut(s, max, tail)
    tail = tail or "..."
    if #s <= max then return s end
    local cut = max - #tail
    while cut > 0 do                                          -- step back off the middle of a multi-byte letter
        local b = string.byte(s, cut + 1)
        if not b or b < 128 or b >= 192 then break end
        cut = cut - 1
    end
    local head = string.sub(s, 1, cut)
    local lastOpen, pos = nil, 1
    while true do
        local a = string.find(head, "|c%x%x%x%x%x%x%x%x|H", pos)
        if not a then break end
        lastOpen, pos = a, a + 1
    end
    if lastOpen and not string.find(head, "|h|r", lastOpen, true) then head = string.sub(head, 1, lastOpen - 1) end
    local pipes = string.match(head, "|+$")                   -- an odd number of pipes at the end is half an escape
    if pipes and #pipes % 2 == 1 then head = string.sub(head, 1, -2) end
    head = string.gsub(head, "%s+$", "")
    return head .. tail
end

-- Area ----------------------------------------------------------------------------------------
function C.zone()
    return (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
end

-- The quests the game puts on the map the player is on. Asking the game for this list once per quest would be
-- slow, so it is kept for one second (it is only ever asked about a whole quest log at a time).
local areaCache = { at = -10, set = nil }
local function onMapSet()
    if not (C_Map and C_Map.GetBestMapForUnit and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return nil end
    local now = GetTime()
    if areaCache.set and now - areaCache.at < 1 then return areaCache.set end
    local set = {}
    local map = C_Map.GetBestMapForUnit("player")
    if map then
        for _, q in ipairs(C_QuestLog.GetQuestsOnMap(map) or {}) do set[q.questID] = true end
    end
    areaCache = { at = now, set = set }
    return set
end

-- is this quest "in the area" the player is standing in?
function C.inArea(e)
    if e.header and lower(e.header) == lower(C.zone()) then return true end
    local set = onMapSet()
    return set ~= nil and set[e.questID] == true
end

-- Addon-to-addon messages -----------------------------------------------------------------------
function C.player() return UnitName and UnitName("player") or "" end

function C.registerPrefix(prefix)
    local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if not reg then return false end
    local ok, r = pcall(reg, prefix)
    return ok and (r == nil or r == true or r == 0)        -- retail returns a boolean, old clients nothing
end

function C.sendAddon(prefix, text, channel)
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not send then return false end
    return (pcall(send, prefix, text, channel))
end

-- The quest tracker (the list on the right) and distances ---------------------------------------------
function C.canWatch()
    return ((C.modern and C_QuestLog.AddQuestWatch) or AddQuestWatch) and true or false
end

-- set of questIDs currently shown in the tracker (pass the entries you already read to save a second scan)
function C.watchedSet(entries)
    local set = {}
    for _, e in ipairs(entries or C.entries()) do
        local watched
        if C.modern and C_QuestLog.GetQuestWatchType then
            watched = (C_QuestLog.GetQuestWatchType(e.questID) ~= nil)       -- nil = not tracked (0 / 1 = automatic / manual)
        elseif IsQuestWatched then
            watched = IsQuestWatched(e.index) and true or false
        end
        if watched then set[e.questID] = true end
    end
    return set
end

function C.setWatched(e, on)
    if C.modern and C_QuestLog.AddQuestWatch then
        if on then C_QuestLog.AddQuestWatch(e.questID) else C_QuestLog.RemoveQuestWatch(e.questID) end
    elseif AddQuestWatch then
        if on then AddQuestWatch(e.index) else RemoveQuestWatch(e.index) end
    end
end

-- how many quests the tracker can hold
function C.maxWatch()
    return (Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES)
        or MAX_WATCHABLE_QUESTS or 25
end

-- Does this client tell us how far away a quest is?
function C.hasDistance()
    return (C_QuestLog and C_QuestLog.GetDistanceSqToQuest) and true or false
end

-- squared distance in yards to the quest's next objective / turn-in, or nil when unknown or on
-- another continent
function C.distanceSq(e)
    local ok, d, onContinent = pcall(C_QuestLog.GetDistanceSqToQuest, e.questID)
    if ok and d and onContinent ~= false then return d end
end

-- Friends list ----------------------------------------------------------------------------------------
function C.canAddFriend()
    return ((C_FriendList and C_FriendList.AddFriend) or AddFriend) and true or false
end

-- "Name" for players on your realm, "Name-Realm" for the others
function C.fullName(m)
    if m.realm and m.realm ~= "" then return m.name .. "-" .. m.realm end
    return m.name
end

-- true if the call went through (the game answers later with a system message)
function C.addFriend(name, note)
    local add = (C_FriendList and C_FriendList.AddFriend) or AddFriend
    if not add then return false end
    if pcall(add, name, note) then return true end
    return (pcall(add, name))
end

function C.friendCount()
    if C_FriendList and C_FriendList.GetNumFriends then return C_FriendList.GetNumFriends() or 0 end
    return (GetNumFriends and GetNumFriends()) or 0
end

function C.maxFriends() return MAX_FRIENDS or 100 end

local function shortName(n) return string.lower(string.match(tostring(n or ""), "^([^-]+)") or "") end

function C.isFriend(name)
    if C_FriendList and C_FriendList.GetFriendInfo then          -- modern: look up by name
        local ok, r = pcall(C_FriendList.GetFriendInfo, name)
        return ok and r ~= nil and r ~= false
    end
    if GetFriendInfo and GetNumFriends then                       -- classic: the list is read by position
        local want = shortName(name)
        for i = 1, GetNumFriends() do
            local n = GetFriendInfo(i)
            if n and shortName(n) == want then return true end
        end
    end
    return false
end

function C.isIgnored(name)
    local f = (C_FriendList and C_FriendList.IsIgnored) or IsIgnored
    if not f then return false end
    local ok, r = pcall(f, name)
    return ok and r and true or false
end

function C.inInstanceGroup()
    return (IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) and true or false
end

-- Inviting players ---------------------------------------------------------------------------------------
function C.groupSize()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or (GetNumPartyMembers and (GetNumPartyMembers() + 1)) or 1
    return math.max(n, 1)
end

function C.isLeader()
    if not C.inGroup() then return true end
    if UnitIsGroupLeader then return UnitIsGroupLeader("player") and true or false end
    return (IsPartyLeader and IsPartyLeader()) and true or false
end

function C.canInvite() return ((C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit) and true or false end

function C.invite(name)
    local f = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if not f then return false end
    return (pcall(f, name))
end
