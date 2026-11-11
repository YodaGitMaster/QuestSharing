-- Bags.lua: quest items marked in your bags, so you only carry what this zone needs.
--   * gold border: an item for a quest of the zone you are in
--   * blue border: an item for one of your quests somewhere else (the bank can keep it); the tooltip says which
-- Which quest an item is for: its name in an objective ("Wolf Pelt: 2/4"), the quest the bag says it belongs to, and
-- (with QuestieDB) the exact items a quest asks for, hands out or needs to start.
-- The game's own bags and the bank's main slots. Our own frames laid over the slots (never fields written onto the
-- game's buttons), clicks go through to the item. Bag replacement addons use their own buttons and are not marked.
local ADDON, ns = ...
local C = ns.compat

local TICK = 0.4
local HERE = { 1, 0.82, 0, 0.95 }          -- gold
local ELSEWHERE = { 0.35, 0.6, 1, 0.75 }   -- blue

-- Which of your quests need which items ------------------------------------------------------------------------------
local needs                                  -- { byId = { [itemID] = { entries } }, byName = { [lower name] = { entries } } }
local function add(t, k, e)
    if k == nil then return end
    t[k] = t[k] or {}
    table.insert(t[k], e)
end

local function buildNeeds()
    local byId, byName, byQuest = {}, {}, {}
    local q = ns.questie
    local withQuestie = q and q.available()
    for _, e in ipairs(C.entries()) do
        byQuest[e.questID] = e
        for _, o in ipairs(C.objectives(e)) do                          -- "Wolf Pelt: 2/4" -> "wolf pelt"
            local n = o.text and string.match(o.text, "^(.-):%s*%d+%s*/%s*%d+")
            if n and n ~= "" then add(byName, string.lower(n), e) end
        end
        if withQuestie then
            for _, id in ipairs(q.questItemIds and q.questItemIds(e.questID) or {}) do add(byId, id, e) end
            local objs = q.get and q.get("quest", e.questID, "objectives")
            local items = type(objs) == "table" and objs[3]
            for _, o in ipairs(type(items) == "table" and items or {}) do add(byId, type(o) == "table" and o[1] or o, e) end
        end
    end
    needs = { byId = byId, byName = byName, byQuest = byQuest }
end

local function itemFacts(bag, slot)
    local id, questID
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        id = ok and info and info.itemID
        if C_Container.GetContainerItemQuestInfo then
            local okQ, qi = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
            if okQ and qi then questID = qi.questID end
        end
    elseif GetContainerItemID then
        local ok, v = pcall(GetContainerItemID, bag, slot)
        id = ok and v
        if GetContainerItemQuestInfo then
            local okQ, _, qid = pcall(GetContainerItemQuestInfo, bag, slot)
            if okQ then questID = qid end
        end
    end
    return id, questID
end

local function itemName(id)
    local f = (C_Item and C_Item.GetItemNameByID) or (GetItemInfo and function(i) return (GetItemInfo(i)) end)
    if not f then return nil end
    local ok, v = pcall(f, id)
    return ok and v or nil
end

-- "here" / "elsewhere" (and the quests) for the item in a slot, or nil
local memo = {}
function ns.bagItemFor(bag, slot)
    if not needs then buildNeeds() end
    local id, questID = itemFacts(bag, slot)
    if not id then return nil end
    local key = id .. ":" .. tostring(questID)
    if memo[key] ~= nil then return memo[key] or nil end
    local list = needs.byId[id]
    if not list then
        local n = itemName(id)
        list = n and needs.byName[string.lower(n)]
    end
    if not list and questID and needs.byQuest[questID] then list = { needs.byQuest[questID] } end
    local res = false
    if list and #list > 0 then
        local here
        for _, e in ipairs(list) do if C.inArea(e) then here = e end end
        res = { here = here ~= nil, quest = here or list[1] }
    end
    memo[key] = res
    return res or nil
end

local function dirty() needs, memo = nil, {} end
for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "ZONE_CHANGED_NEW_AREA",
                      "ZONE_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" }) do
    ns.on(ev, dirty)
end
ns.bagMarksDirty = dirty

-- The slots on screen: the game's bags and the bank's own slots: fn(button, bag, slot) -------------------------------
local function eachSlot(fn)
    for f = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. f]
        if frame and frame.IsShown and frame:IsShown() then
            local bag = frame.GetID and frame:GetID()
            if type(frame.Items) == "table" then
                for _, b in ipairs(frame.Items) do fn(b, bag, b:GetID()) end
            elseif frame.GetName and frame:GetName() then
                for i = 1, (frame.size or 36) do
                    local b = _G[frame:GetName() .. "Item" .. i]
                    if b then fn(b, bag, b:GetID()) end
                end
            end
        end
    end
    if BankFrame and BankFrame.IsShown and BankFrame:IsShown() then
        for i = 1, (NUM_BANKGENERIC_SLOTS or 28) do
            local b = _G["BankFrameItem" .. i]
            if b then fn(b, BANK_CONTAINER or -1, i) end
        end
    end
end

-- The borders ------------------------------------------------------------------------------------------------------------
local marks = setmetatable({}, { __mode = "k" })       -- the game's button -> our border frame
local function markFor(b)
    local m = marks[b]
    if not m then
        ns.trying("marking quest items in your bags", "bagmarks")
        m = CreateFrame("Frame", nil, UIParent)
        m:EnableMouse(false)                               -- clicks go through to the item
        m.tex = m:CreateTexture(nil, "OVERLAY")
        m.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        m.tex:SetBlendMode("ADD")
        m.tex:SetPoint("CENTER", m, "CENTER", 0, 0)
        marks[b] = m
    end
    return m
end

function ns.refreshBagMarks()
    local on = ns.db.enabled and ns.db.bagMarks and not ns.isBlocked("bagmarks")
    local used = {}
    if on then
        eachSlot(function(b, bag, slot)
            if not (bag and slot and b.IsVisible and b:IsVisible()) then return end
            local r = ns.bagItemFor(bag, slot)
            if not r then return end
            local m = markFor(b)
            local w = (b.GetWidth and b:GetWidth()) or 37
            local col = r.here and HERE or ELSEWHERE
            m:ClearAllPoints()
            m:SetAllPoints(b)
            if b.GetFrameStrata then m:SetFrameStrata(b:GetFrameStrata()) end
            if b.GetFrameLevel then m:SetFrameLevel((b:GetFrameLevel() or 1) + 3) end
            m.tex:SetWidth(w * 1.8)
            m.tex:SetHeight(w * 1.8)
            m.tex:SetVertexColor(col[1], col[2], col[3], col[4])
            m.here, m.quest = r.here, r.quest
            m:Show()
            used[b] = true
        end)
    end
    for b, m in pairs(marks) do if not used[b] then m:Hide() end end
end
function ns._bagMarks() return marks end                          -- for the tests

local function tick()
    if ns.db.bagMarks then
        local ok, err = pcall(ns.refreshBagMarks)
        if not ok then ns.logError("bag marks", err) end
    end
    ns.after(TICK, tick)
end
ns.after(2, tick)

-- The tooltip of a bag item says which quest it is for, and where -------------------------------------------------------
local hooked = false
local function hookTooltip()
    if hooked or not (GameTooltip and hooksecurefunc) then return end
    hooked = pcall(hooksecurefunc, GameTooltip, "SetBagItem", function(tip, bag, slot)
        if not (ns.db.enabled and ns.db.bagMarks) then return end
        local r = ns.bagItemFor(bag, slot)
        if not r then return end
        local where = r.here and "here" or ("in " .. tostring(r.quest.header or "another zone") .. " - the bank can keep it")
        pcall(function()
            tip:AddLine("Quest Sharing: for \"" .. tostring(r.quest.title) .. "\" (" .. where .. ")",
                r.here and 1 or 0.45, r.here and 0.82 or 0.7, r.here and 0 or 1)
            tip:Show()
        end)
    end)
end
ns.on("PLAYER_LOGIN", hookTooltip)
hookTooltip()
