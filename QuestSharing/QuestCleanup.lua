-- On-demand bag cleanup. Absence from the quest log is a review candidate, never proof an item is useless.
local ADDON, ns = ...
local C, U, S = ns.compat, ns.optionalUI, ns.style
local R = {}
ns.questCleanup = R
local window, results, pending, page = nil, {}, nil, 1
-- The bag our own Delete just emptied: its follow-up bag events keep the rescanned list (no extra scan).
local ownBag, ownUntil
local PAGE_SIZE = 6
local render

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
end

local function container(name)
    return (C_Container and C_Container[name]) or _G[name]
end

local function combat() return InCombatLockdown and InCombatLockdown() end
local function shown(frame, yes) if yes then frame:Show() else frame:Hide() end end

local function cursor()
    if not GetCursorInfo then return false end
    return pcall(GetCursorInfo)
end

local function slotInfo(bag, slot)
    local id, count, locked, link
    if C_Container and C_Container.GetContainerItemInfo then
        local info = call(C_Container.GetContainerItemInfo, bag, slot)
        if type(info) ~= "table" then return end
        id, count, locked, link = info.itemID, info.stackCount, info.isLocked, info.hyperlink
    else
        local _, n, lock = call(GetContainerItemInfo, bag, slot)
        id, count, locked = call(GetContainerItemID, bag, slot), n, lock
    end
    if not id then return end
    link = link or call(container("GetContainerItemLink"), bag, slot)
    local qi
    if C_Container and C_Container.GetContainerItemQuestInfo then
        qi = call(C_Container.GetContainerItemQuestInfo, bag, slot)
    elseif GetContainerItemQuestInfo then
        local isQuest, questID, isActive = call(GetContainerItemQuestInfo, bag, slot)
        if type(isQuest) == "boolean" then qi = { isQuestItem = isQuest, questID = questID, isActive = isActive } end
    end
    return { bag = bag, slot = slot, id = id, count = count, locked = locked, link = link, quest = qi }
end

local function addIDs(set, ids)
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        if type(id) == "number" and id > 0 then set[id] = true end
    end
end

local function snapshot()
    local Q = ns.questie
    if not (Q and Q.available() and Q.get) then return nil, "QuestieDB is required. Install or update QuestieDB (see /qs questie), then refresh." end
    local state = { active = {}, ids = {}, names = {}, q = Q }
    for _, e in ipairs(C.entries()) do
        -- Unknown/custom quests cannot be checked reliably against the provider.
        if not Q.get("quest", e.questID, "name") then
            return nil, "Some current quests are missing from QuestieDB. Cleanup is paused until their item requirements can be checked."
        end
        state.active[e.questID] = true
        addIDs(state.ids, Q.questItemIds and Q.questItemIds(e.questID))
        local objectives = Q.get("quest", e.questID, "objectives")
        local items = type(objectives) == "table" and objectives[3]
        for _, item in ipairs(type(items) == "table" and items or {}) do
            local id = type(item) == "table" and item[1] or item
            if type(id) == "number" then state.ids[id] = true end
        end
        for _, objective in ipairs(C.objectives(e)) do
            local name = objective.text and string.match(objective.text, "^(.-):%s*%d+%s*/%s*%d+")
            if name then state.names[string.lower(name)] = true end
        end
        local index = e.index
        if C.modern and C_QuestLog.GetLogIndexForQuestID then index = call(C_QuestLog.GetLogIndexForQuestID, e.questID) or index end
        local link = index and call(GetQuestLogSpecialItemInfo, index)
        local id = type(link) == "string" and tonumber(string.match(link, "item:(%d+)"))
        if id then state.ids[id] = true end
    end
    return state
end

local function classify(state, item)
    if not item or item.locked or type(item.count) ~= "number" or item.count < 1 or not item.link then return end
    local qi, Q = item.quest, state.q
    if type(qi) ~= "table" or type(qi.isQuestItem) ~= "boolean" then return end
    -- A positive questID can be an unaccepted quest starter; keep those as well as active items.
    if qi.isActive or (type(qi.questID) == "number" and qi.questID > 0) or state.ids[item.id] then return end
    local name = call((C_Item and C_Item.GetItemNameByID) or GetItemInfo, item.id)
    if not name or state.names[string.lower(name)] then return end
    if not Q.get("item", item.id, "name") then return end
    local starter = Q.get("item", item.id, "startQuest")
    if starter ~= nil and starter ~= 0 then return end
    local related = Q.get("item", item.id, "relatedQuests")
    for _, questID in ipairs(type(related) == "table" and related or {}) do
        if state.active[questID] or call(C_QuestLog and C_QuestLog.IsOnQuest, questID) then return end
    end
    local _, _, _, _, _, classID = call((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant, item.id)
    classID = classID or Q.get("item", item.id, "class")
    if classID ~= 12 and not qi.isQuestItem then return end
    item.name = name
    return item
end

local function candidate(state, bag, slot) return classify(state, slotInfo(bag, slot)) end

function R.scan()
    results, pending = {}, nil
    if not ns.db.enabled then return results, "Turn on Quest Sharing to use cleanup." end
    if combat() then return results, "Wait until combat ends, then refresh." end
    local state, reason = snapshot()
    if not state then return results, reason end
    if not container("GetContainerNumSlots") then return results, "Bag scanning is unavailable on this client." end
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, call(container("GetContainerNumSlots"), bag) or 0 do
            local item = candidate(state, bag, slot)
            if item then results[#results + 1] = item end
        end
    end
    return results, #results .. (#results == 1 and " possible leftover stack." or " possible leftover stacks.") .. " Active quest matches and quest starters are kept. Unknown or locked items are skipped."
end

local function message(text)
    if window then window.status:SetText(text) end
end

function R.refresh()
    local _, text = R.scan()
    message(text)
    if render then render() end
end

function R.review(item)
    pending = nil
    if not ns.db.enabled or combat() then message("Wait until combat ends and ensure Quest Sharing is on."); return end
    for _, row in ipairs(results) do if row == item then pending = item end end
    if render then render() end
end

function R.cancel()
    pending = nil
    if render then render() end
end

function R.confirm()
    local chosen = pending
    pending = nil
    if render then render() end
    if not chosen or not ns.db.enabled or combat() then return false end
    local readable, kind = cursor()
    if not readable or kind ~= nil then message("Empty the cursor, then review the item again."); return false end
    local state, reason = snapshot()
    local fresh = state and candidate(state, chosen.bag, chosen.slot)
    if not fresh or fresh.id ~= chosen.id or fresh.count ~= chosen.count or fresh.link ~= chosen.link then
        R.refresh()
        message(reason or "This stack or its quest status changed. Refresh and review it again.")
        return false
    end
    local pickup = container("PickupContainerItem")
    if not (pickup and DeleteCursorItem and ClearCursor) then
        message("Item deletion is unavailable on this client; delete this stack from your bags manually.")
        return false
    end
    call(pickup, fresh.bag, fresh.slot)
    local cursorOK, cursorKind, cursorID, cursorLink = cursor()
    if not cursorOK or cursorKind ~= "item" or cursorID ~= fresh.id or (cursorLink and cursorLink ~= fresh.link) then
        call(ClearCursor)
        message("Could not pick up the reviewed item. Nothing was deleted.")
        return false
    end
    -- Pickup can run other bag/quest callbacks synchronously. Recheck before crossing the destructive boundary.
    local latest = snapshot()
    if not ns.db.enabled or combat() or not latest or not classify(latest, fresh) then
        call(ClearCursor)
        R.refresh()
        message("Quest or player state changed during pickup. Nothing was deleted; review the stack again.")
        return false
    end
    -- Never destroy whatever happened to be on the cursor: only the freshly rechecked stack.
    ns.trying("deleting a confirmed leftover quest item")
    cursorOK, cursorKind, cursorID, cursorLink = cursor()
    if not cursorOK or cursorKind ~= "item" or cursorID ~= fresh.id or (cursorLink and cursorLink ~= fresh.link) then
        call(ClearCursor)
        message("The cursor changed during the check. Nothing was deleted.")
        return false
    end
    local ok = pcall(DeleteCursorItem)
    local afterOK, remains = cursor()
    if not ok or not afterOK or remains ~= nil then
        call(ClearCursor)
        R.refresh()
        message("The client refused deletion. Delete the reviewed stack from your bags manually.")
        return false
    end
    R.refresh()
    ownBag, ownUntil = fresh.bag, (GetTime and GetTime() or 0) + 2
    ns.print("deleted " .. fresh.name .. " x" .. fresh.count)
    return true
end

local function build()
    if window then return window end
    window = U.window("QuestSharingQuestCleanup", 570, 470, "Leftover quest items")
    if not window then return end
    U.text(window, "Review possible leftovers with no current quest match. These items may still be useful for future quests. Delete removes the whole stack permanently.", 22, 38, 526)
    window.status = U.text(window, "", 22, 91, 526)
    window.rows = {}
    for i = 1, PAGE_SIZE do
        local row = CreateFrame("Frame", nil, window)
        row:SetPoint("TOPLEFT", window, "TOPLEFT", 22, -(145 + (i - 1) * 33))
        row:SetWidth(526); row:SetHeight(31)
        row.text = U.text(row, "", 0, 0, 414)
        row.text:SetWordWrap(false)
        row.text:SetHeight(28)
        row.button = S.button(row, "Review", 86, function() R.review(row.item) end)
        row.button:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        row.button:HookScript("OnEnter", function(self)
            if GameTooltip and row.item then
                call(GameTooltip.SetOwner, GameTooltip, self, "ANCHOR_RIGHT")
                call(GameTooltip.SetBagItem, GameTooltip, row.item.bag, row.item.slot)
                call(GameTooltip.Show, GameTooltip)
            end
        end)
        window.rows[i] = row
    end
    window.previous = S.button(window, "Previous", 80, function() page = page - 1; render() end)
    window.previous:SetPoint("TOPLEFT", window, "TOPLEFT", 22, -349)
    window.next = S.button(window, "Next", 80, function() page = page + 1; render() end)
    window.next:SetPoint("TOPLEFT", window, "TOPLEFT", 108, -349)
    window.refresh = S.button(window, "Refresh bags", 104, R.refresh)
    window.refresh:SetPoint("TOPRIGHT", window, "TOPRIGHT", -22, -349)
    window.confirmText = U.text(window, "", 22, 381, 526)
    window.confirm = S.button(window, "Delete stack", 108, R.confirm)
    window.confirm:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 22, 18)
    window.cancel = S.button(window, "Cancel", 80, R.cancel)
    window.cancel:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 138, 18)
    window:SetScript("OnHide", function() results, pending, page = {}, nil, 1 end)
    return window
end

render = function()
    if not window then return end
    page = math.max(1, math.min(page, math.max(1, math.ceil(#results / PAGE_SIZE))))
    for i, row in ipairs(window.rows) do
        row.item = results[(page - 1) * PAGE_SIZE + i]
        if row.item then
            -- Bag 0 is the backpack; equipped bags are numbered 1-4 as on the bag bar.
            local where = row.item.bag == 0 and "Backpack" or ("Bag " .. row.item.bag)
            row.text:SetText(string.format("%s x%d  (%s, slot %d)", row.item.name, row.item.count, where, row.item.slot))
            row:Show()
        else row:Hide() end
    end
    shown(window.previous, page > 1)
    shown(window.next, page * PAGE_SIZE < #results)
    shown(window.confirm, pending ~= nil)
    shown(window.cancel, pending ~= nil)
    window.confirmText:SetText(pending and ("Permanently delete " .. pending.name .. " x" .. pending.count .. "?") or "Choose Review beside a stack to check it before deletion.")
end

function R.open()
    local f = build()
    if not f then return end
    f:Show()
    R.refresh()
end

local function ownChange(event, bag)
    if ownBag == nil then return false end
    if (GetTime and GetTime() or 0) > ownUntil then ownBag = nil; return false end
    if event == "BAG_UPDATE_DELAYED" then ownBag = nil; return true end
    return event == "BAG_UPDATE" and bag == ownBag
end

local function invalidate(event, bag)
    if not (window and window:IsShown()) then return end
    if ownChange(event, bag) then return end
    ownBag = nil
    results, pending = {}, nil
    render()
    message("Bags or quests changed. Click Refresh bags to check again.")
end
for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
                         "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD" }) do ns.on(event, invalidate) end
function R._results() return results end
function R._window() return window end
