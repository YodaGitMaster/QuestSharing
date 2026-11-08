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
        local name = UnitName(unit)
        if name then out[#out + 1] = { unit = unit, name = name } end
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

-- Area ----------------------------------------------------------------------------------------
function C.zone()
    return (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
end

-- is this quest "in the area" the player is standing in?
function C.inArea(e)
    if lower(e.header) == lower(C.zone()) and e.header then return true end
    if C_Map and C_Map.GetBestMapForUnit and C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local map = C_Map.GetBestMapForUnit("player")
        if map then
            for _, q in ipairs(C_QuestLog.GetQuestsOnMap(map) or {}) do
                if q.questID == e.questID then return true end
            end
        end
    end
    return false
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
