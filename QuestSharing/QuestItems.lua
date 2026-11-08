-- QuestItems.lua: quest items you can USE (a torch to light, a flare to throw...).
--   * An icon next to the quest in the game's tracker for a usable quest item in your bags, like the game's own button
--     for "special" quest items (the game only shows those; this adds the others). Click it to use the item.
--   * A "use quest item" key and a small movable button: the item of your nearest quest that has one.
-- Which item goes with which quest: the game's own special item, the bag's quest info, an objective or quest text that
-- names the item, and (with Questie) the item the quest gives you or needs.
-- Using an item is a protected action: these are secure item buttons, prepared outside combat (in combat they keep
-- what they had, and the tracker icons are put in place again when the fight is over).
local ADDON, ns = ...
local C = ns.compat

local MAX_ICONS = 8
local KEY_BUTTON = "QuestSharingItemButton"
local CLICK = "CLICK " .. KEY_BUTTON .. ":LeftButton"
local icons, keyBtn = {}, nil
local cache = { at = -100, map = nil }
ns.questItemState = { pending = false }

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- Item facts, through whichever calls this client has ------------------------------------------------------------------------
local function itemSpell(id)
    local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not f then return nil end
    local ok, v = pcall(f, id)
    return ok and v or nil
end
local function itemIcon(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if not f then return nil end
    local ok, v = pcall(f, id)
    return ok and v or nil
end
local function itemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return 0 end
    local ok, v = pcall(f, id)
    return (ok and v) or 0
end
local function itemName(id)
    local f = (C_Item and C_Item.GetItemNameByID) or (GetItemInfo and function(i) return (GetItemInfo(i)) end)
    if not f then return nil end
    local ok, v = pcall(f, id)
    return ok and v or nil
end

-- every item in the bags: { id, name, questID (when the bag says it belongs to a quest), isQuestItem }
local function bagItems()
    local out = {}
    local slotsOf = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if not slotsOf then return out end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local okN, n = pcall(slotsOf, bag)
        for slot = 1, (okN and n or 0) do
            local id, questID, isQuest
            if C_Container and C_Container.GetContainerItemInfo then
                local okI, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                id = okI and info and info.itemID
                if C_Container.GetContainerItemQuestInfo then
                    local okQ, q = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
                    if okQ and q then questID, isQuest = q.questID, q.isQuestItem end
                end
            elseif GetContainerItemID then
                local okI, v = pcall(GetContainerItemID, bag, slot)
                id = okI and v
                if GetContainerItemQuestInfo then
                    local okQ, isQ, qid = pcall(GetContainerItemQuestInfo, bag, slot)
                    if okQ then questID, isQuest = qid, isQ end
                end
            end
            if id then out[#out + 1] = { id = id, name = itemName(id), questID = questID, isQuestItem = isQuest } end
        end
    end
    return out
end

local function specialItem(e)
    if not GetQuestLogSpecialItemInfo then return nil end
    local index = e.index
    if C.modern and C_QuestLog.GetLogIndexForQuestID then index = C_QuestLog.GetLogIndexForQuestID(e.questID) or index end
    if not index then return nil end
    local ok, link, _, _, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, index)
    if not (ok and link) then return nil end
    if e.complete and not showWhenComplete then return nil end
    local id = tonumber(string.match(link, "item:(%d+)"))
    return id
end

-- questID -> { id = itemID, special = true when the game shows its own button for it }
function ns.questItems()
    local now = GetTime()
    if cache.map and now - cache.at < 0.5 then return cache.map, cache.entries end
    local map = {}
    local entries = C.entries()
    local usable = {}
    for _, it in ipairs(bagItems()) do
        if not usable[it.id] and itemSpell(it.id) then usable[it.id] = it end      -- only items with a "Use:" effect
    end
    for _, e in ipairs(entries) do
        local sp = specialItem(e)
        if sp then map[e.questID] = { id = sp, special = true } end
    end
    -- the bag says which quest the item belongs to
    for id, it in pairs(usable) do
        if it.questID and not map[it.questID] then
            for _, e in ipairs(entries) do if e.questID == it.questID then map[e.questID] = { id = id } end end
        end
    end
    -- Questie knows the item a quest hands out or needs
    if ns.questie and ns.questie.available() and ns.questie.questItemIds then
        for _, e in ipairs(entries) do
            if not map[e.questID] then
                for _, id in ipairs(ns.questie.questItemIds(e.questID)) do
                    if usable[id] then map[e.questID] = { id = id }; break end
                end
            end
        end
    end
    -- an objective that names the item
    for _, e in ipairs(entries) do
        if not map[e.questID] then
            for _, o in ipairs(C.objectives(e)) do
                for id, it in pairs(usable) do
                    if it.name and o.text and string.find(string.lower(o.text), string.lower(it.name), 1, true) then
                        map[e.questID] = { id = id }
                    end
                end
            end
        end
    end
    cache.at, cache.map, cache.entries = now, map, entries
    return map, entries
end

-- A secure item button: icon, count, cooldown, red when the target is out of range --------------------------------------------
local function paint(b)
    if not b.itemID then return end
    b.icon:SetTexture(itemIcon(b.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
    local n = itemCount(b.itemID)
    b.count:SetText(n > 1 and tostring(n) or "")
    local cdf = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if cdf and b.cooldown and b.cooldown.SetCooldown then
        local ok, start, duration = pcall(cdf, b.itemID)
        if ok and start and duration then b.cooldown:SetCooldown(start, duration) end
    end
    local rangef = (C_Item and C_Item.IsItemInRange) or IsItemInRange
    local inRange = true
    if rangef and UnitExists and UnitExists("target") then
        local ok, r = pcall(rangef, b.itemID, "target")
        if ok and r == false then inRange = false end
    end
    if inRange then b.icon:SetVertexColor(1, 1, 1) else b.icon:SetVertexColor(1, 0.3, 0.3) end
end

local function newButton(name, size)
    local ok, b = pcall(CreateFrame, "Button", name, UIParent, "SecureActionButtonTemplate")
    if not (ok and b) then return nil end
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    b:SetAttribute("useOnKeyDown", false)
    b:SetWidth(size)
    b:SetHeight(size)
    b:SetFrameStrata("MEDIUM")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    local okC, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    if okC and cd then cd:SetAllPoints(b); b.cooldown = cd end
    pcall(function() b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end)
    b:SetScript("OnEnter", function(self)
        if GameTooltip and self.itemID then pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) else GameTooltip:SetText(itemName(self.itemID) or "") end
            GameTooltip:Show()
        end) end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end)
    b:Hide()
    return b
end

local function setItem(b, id)
    if b.itemID ~= id or b:GetAttribute("item") ~= (id and ("item:" .. id) or nil) then
        ns.trying("preparing a quest item button", "items")        -- noted only when it really changes
        b:SetAttribute("item", id and ("item:" .. id) or nil)
    end
    b.itemID = id
    paint(b)
end

-- Icons next to the quests in the game's tracker (the WatchFrame) -----------------------------------------------------------
local function questIDAt(index)
    if not index then return nil end
    for _, e in ipairs(C.entries()) do if e.index == index then return e.questID end end
end

function ns.layoutTrackerItems()
    if inCombat() then ns.questItemState.pending = true; return end
    ns.questItemState.pending = false
    if ns.isBlocked("items") then return end
    for _, b in ipairs(icons) do b:Hide() end
    if not (ns.db.enabled and ns.db.questItems and type(WATCHFRAME_LINKBUTTONS) == "table") then return end
    local map, used = ns.questItems(), 0
    for _, lb in ipairs(WATCHFRAME_LINKBUTTONS) do
        if used >= MAX_ICONS then break end
        if lb.type == "QUEST" and lb.index and lb.IsShown and lb:IsShown() then
            local qid = questIDAt(lb.index)
            local it = qid and map[qid]
            if it and not it.special then                               -- the game shows its own button for these
                used = used + 1
                local b = icons[used] or newButton(nil, 22)
                if not b then break end
                icons[used] = b
                setItem(b, it.id)
                b.questID = qid
                b:ClearAllPoints()
                b:SetPoint("TOPRIGHT", lb, "TOPRIGHT", 10, -2)          -- where the game puts its own item button
                b:Show()
            end
        end
    end
end
function ns._trackerItemIcons() return icons end                 -- for the tests

-- The "use quest item" key and its little button: the nearest quest with an item ---------------------------------------------
function ns.nearestQuestItem()
    local map, entries = ns.questItems()
    local best, bestD
    for _, e in ipairs(entries or cache.entries or {}) do
        local it = map[e.questID]
        if it and not C.doneByMe(e) then
            local d = (C.hasDistance() and C.distanceSq(e)) or (C.inArea(e) and 1e9) or 1e12
            if not bestD or d < bestD then best, bestD = { id = it.id, questID = e.questID, title = e.title }, d end
        end
    end
    return best
end

local function buildKeyButton()
    if keyBtn or inCombat() then return keyBtn end
    keyBtn = newButton(KEY_BUTTON, 36)
    if not keyBtn then return nil end
    keyBtn:SetMovable(true)
    keyBtn:RegisterForDrag("LeftButton")
    keyBtn:SetScript("OnDragStart", function(self) if IsShiftKeyDown and IsShiftKeyDown() and not inCombat() then self:StartMoving() end end)
    keyBtn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ns.db.itemButtonPos = { point, x, y }
    end)
    local pos = ns.db.itemButtonPos
    keyBtn:ClearAllPoints()
    if pos then keyBtn:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else keyBtn:SetPoint("CENTER", UIParent, "CENTER", 0, -180) end
    return keyBtn
end
ns.questItemButton = function() return keyBtn end

function ns.refreshItemKey()
    if inCombat() or ns.isBlocked("items") then return end
    if not (ns.db.enabled and ns.db.questItems) then if keyBtn then keyBtn:Hide() end return end
    local b = buildKeyButton()
    if not b then return end
    local near = ns.nearestQuestItem()
    if near then
        if b.itemID ~= near.id then setItem(b, near.id) else paint(b) end
        b.questID = near.questID
        if ns.db.itemButton then b:Show() else b:Hide() end
    else
        if b.itemID then setItem(b, nil) end
        b:Hide()
    end
end

function ns.itemKeyName() return GetBindingKey and (GetBindingKey(CLICK)) or nil end

function ns.setItemKey(key)
    if inCombat() then return ns.print("key bindings cannot be changed in combat") end
    if not (SetBindingClick and buildKeyButton()) then return ns.print("this client does not allow it") end
    key = string.upper(key or "")
    if key == "" then return ns.print("quest item key: " .. (ns.itemKeyName() or "not set") .. "  (/qs itemkey <KEY>, /qs itemkey none)") end
    for _, k in ipairs({ GetBindingKey(CLICK) }) do SetBinding(k) end
    if key ~= "NONE" then
        local before = GetBindingAction and GetBindingAction(key) or ""
        if ns.PROTECTED_KEYS and ns.PROTECTED_KEYS[before] then
            return ns.print(key .. " is the game's \"" .. ns.PROTECTED_KEYS[before] .. "\" key - pick another one (nothing was changed)")
        end
        ns.trying("setting the quest item key")
        if not SetBindingClick(key, KEY_BUTTON, "LeftButton") then return ns.print("could not bind " .. key) end
    end
    local save = SaveBindings or AttemptToSaveBindings
    if save then save(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
    ns.print(key == "NONE" and "quest item key removed" or ("quest item key: " .. key .. " - uses the item of your nearest quest"))
    if ns.refreshSettings then ns.refreshSettings() end
end

-- When to look again ---------------------------------------------------------------------------------------------------------
local pending
local function soon()
    if pending then return end
    pending = ns.after(0.5, function()
        pending = nil
        cache.map = nil
        ns.layoutTrackerItems()
        ns.refreshItemKey()
    end)
end
ns.refreshQuestItems = soon
-- a switch in the settings: at once
function ns.applyQuestItems()
    cache.map = nil
    ns.layoutTrackerItems()
    ns.refreshItemKey()
end
for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "BAG_UPDATE", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
                      "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
    ns.on(ev, soon)
end
ns.on("PLAYER_REGEN_ENABLED", soon)                              -- put the icons in place again after the fight
local function hookTracker()
    ns.hooks = ns.hooks or {}
    if ns.hooks.watchItems or not WatchFrame_Update then return end
    ns.hooks.watchItems = pcall(hooksecurefunc, "WatchFrame_Update", function() soon() end)
end
ns.on("PLAYER_LOGIN", hookTracker)
ns.on("ADDON_LOADED", hookTracker)
hookTracker()

-- every second: cooldowns and range on what is shown (cheap: only painting)
local function tick()
    for _, b in ipairs(icons) do if b:IsShown() then paint(b) end end
    if keyBtn and keyBtn:IsShown() then paint(keyBtn) end
    -- you moved: maybe another quest is the nearest one with an item (only while there is an item to show at all)
    if not inCombat() and ns.db.questItems and keyBtn and keyBtn.itemID and GetTime() - cache.at > 5 then ns.refreshItemKey() end
    ns.after(1, tick)
end
ns.after(2, tick)
