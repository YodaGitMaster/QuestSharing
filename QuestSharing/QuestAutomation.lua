-- Optional quest dialog actions. Calls happen only in response to the game's own quest events.
local ADDON, ns = ...
ns.inModule("automation")          -- Modules.lua: Settings > General > Tools can switch this off

local function enabled(key, feature)
    return ns.db and ns.db.enabled and ns.db[key] and not ns.isBlocked(feature)
        and not (InCombatLockdown and InCombatLockdown())
end

local function read(fn)
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn)
    if not ok then return false end
    return true, result
end

local function act(label, feature, fn, ...)
    if type(fn) ~= "function" then return false end
    ns.trying(label, feature)
    fn(...)
    return true
end

ns.on("QUEST_DETAIL", function()
    if not enabled("autoAcceptQuests", "questAccept") then return end
    -- This is the same event the built-in quest offer panel handles; no synthetic button click is used.
    act("accepting an offered quest", "questAccept", AcceptQuest)
end)

ns.on("QUEST_PROGRESS", function()
    if not enabled("autoCompleteQuests", "questComplete") then return end
    local ok, ready = read(IsQuestCompletable)
    if ok and (ready == true or ready == 1) then
        -- Completes the progress stage; the resulting QUEST_COMPLETE event handles the reward safely.
        act("continuing a ready quest turn-in", "questComplete", CompleteQuest)
    end
end)

ns.on("QUEST_COMPLETE", function()
    if not enabled("autoCompleteQuests", "questComplete") then return end
    local ok, choices = read(GetNumQuestChoices)
    if not ok or type(choices) ~= "number" or choices < 0 or choices > 1 then return end

    -- The normal UI asks before a turn-in that costs money. Leave those quests for an explicit click.
    local moneyOK, money = read(GetQuestMoneyToGet)
    if not moneyOK or type(money) ~= "number" or money > 0 then return end

    if type(GetQuestReward) ~= "function" then return end
    act("claiming an unambiguous quest reward", "questComplete", GetQuestReward, choices == 1 and 1 or 0)
end)
