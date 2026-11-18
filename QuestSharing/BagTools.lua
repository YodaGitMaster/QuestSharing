-- BagTools.lua: three small helpers for your bags, each with its own switch in Settings > Bags.
--   * Bookmarks (bagBookmarks): point at an item in your bags and press Space. A bookmarked item shows a note icon and
--     is never sold by the addon. The bookmark follows the item type (its item ID), so it survives moving the item.
--   * Sell gray items (autoSellGray): at a vendor, every gray item is sold except bookmarked ones and ones a quest needs.
--   * Arrange (autoSortBags, /qs sort): the chosen bags (sortBags) are treated as ONE long bag and ordered by
--     sortBy: topic (quest items, consumables, equipment, materials, recipes, other, gray items last), quality or name.
--     sortFrom "end" gathers the items at the end of the bags; sortKeepBookmarked leaves bookmarked items in their slot.
-- Only the game's own bags are handled (bag replacement addons use their own buttons).
local ADDON, ns = ...

local T = {}
ns.bagTools = T

local TICK = 0.4              -- how often the bookmark icons are refreshed
local STEP = 0.15             -- seconds between two moves while arranging (the game locks a slot until it answers)
local AUTO_DELAY = 3          -- seconds the bags must stay quiet before they are arranged by themselves
local MAX_WAIT = 40           -- locked-slot waits before an arrangement gives up
local MAX_MOVES = 400

-- The game's bag functions, old and new names ----------------------------------------------------------------------------
local function cont(name)
    return (C_Container and C_Container[name]) or _G[name]
end

local function numSlots(bag)
    local f = cont("GetContainerNumSlots")
    if not f then return 0 end
    local ok, n = pcall(f, bag)
    return ok and tonumber(n) or 0
end

-- 0 = anything fits; quivers, soul bags and profession bags only take their own items and are left alone
local function bagKind(bag)
    if bag == 0 then return 0 end
    local f = cont("GetContainerNumFreeSlots")
    if not f then return 0 end
    local ok, _, kind = pcall(f, bag)
    return ok and tonumber(kind) or 0
end

local function lastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end

-- { id, count, quality, locked, noValue, link } for the item in a slot, or nil when the slot is empty
local function slotInfo(bag, slot)
    local id, count, quality, locked, noValue, link
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, i = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and type(i) == "table" then
            id, count, quality, locked, noValue, link = i.itemID, i.stackCount, i.quality, i.isLocked, i.hasNoValue, i.hyperlink
        end
    elseif GetContainerItemInfo then
        local ok, _, n, lk, q, _, _, l, _, nv, iid = pcall(GetContainerItemInfo, bag, slot)
        if ok then id, count, quality, locked, noValue, link = iid, n, q, lk, nv, l end
    end
    if not id then return nil end
    return { id = id, count = tonumber(count) or 1, quality = quality, locked = locked and true or false,
             noValue = noValue and true or false, link = link }
end

local factMemo = {}
-- what the game says about an item type: name, quality, sell price, class and subclass
local function facts(id)
    local m = factMemo[id]
    if m then return m end
    m = {}
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if f then
        local ok, name, _, quality, _, _, _, _, _, _, _, sell, class, sub = pcall(f, id)
        if ok then m.name, m.quality, m.sell, m.class, m.sub = name, quality, sell, class, sub end
    end
    if m.class == nil then
        local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if inst then
            local ok, _, _, _, _, _, class, sub = pcall(inst, id)
            if ok then m.class, m.sub = class, sub end
        end
    end
    if m.name ~= nil then factMemo[id] = m end        -- an item the game has not told us about yet is asked again
    return m
end

local function itemText(id, info)
    return (info and info.link) or facts(id).name or ("item " .. tostring(id))
end

local function money(c)
    c = math.floor(tonumber(c) or 0)
    local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "g" end
    if s > 0 then out[#out + 1] = s .. "s" end
    if k > 0 or #out == 0 then out[#out + 1] = k .. "c" end
    return table.concat(out, " ")
end

local function inFight()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end
local function holdingItem() return CursorHasItem and CursorHasItem() or false end

-- Bookmarks --------------------------------------------------------------------------------------------------------------
local function bookmarks()
    ns.db.bookmarks = type(ns.db.bookmarks) == "table" and ns.db.bookmarks or {}
    return ns.db.bookmarks
end

-- Kept even when the Space key is switched off: a bookmark you made still protects the item from being sold.
function T.isBookmarked(id)
    return id ~= nil and type(ns.db.bookmarks) == "table" and ns.db.bookmarks[id] == true
end

function T.toggleBookmark(bag, slot)
    local info = slotInfo(bag, slot)
    if not info then return false end
    local m = bookmarks()
    if m[info.id] then
        m[info.id] = nil
        ns.print("bookmark removed: " .. itemText(info.id, info) .. " can be sold again")
    else
        m[info.id] = true
        ns.print("bookmarked: " .. itemText(info.id, info) .. " - it will not be sold (press Space on it again to remove)")
    end
    ns.log("bookmark", tostring(info.id) .. " = " .. tostring(m[info.id] == true))
    if T.refreshIcons then pcall(T.refreshIcons) end
    return true
end

function T.clearBookmarks()
    local n = 0
    for _ in pairs(bookmarks()) do n = n + 1 end
    ns.db.bookmarks = {}
    if T.refreshIcons then pcall(T.refreshIcons) end
    return n
end

function T.listBookmarks()
    local out = {}
    for id in pairs(bookmarks()) do out[#out + 1] = itemText(id) end
    table.sort(out)
    return out
end

-- the bag slot the mouse is over: bag, slot (or nil)
function T.pointedSlot()
    local each = ns.bagEachSlot
    if not each then return nil end
    local bag, slot
    each(function(b, bg, sl)
        if not bag and bg and sl and b.IsVisible and b:IsVisible() and b.IsMouseOver and b:IsMouseOver() then bag, slot = bg, sl end
    end)
    return bag, slot
end

-- true when the key was used (the character then does not jump)
function T.keyDown(key)
    if key ~= "SPACE" or not (ns.db.enabled and ns.db.bagBookmarks) then return false end
    if holdingItem() then return false end
    local bag, slot = T.pointedSlot()
    if not bag then return false end
    return T.toggleBookmark(bag, slot)
end

local keys = CreateFrame("Frame", nil, UIParent)
keys:SetPropagateKeyboardInput(true)
keys:SetScript("OnKeyDown", function(self, key)
    local ok, taken = pcall(T.keyDown, key)
    if not ok then ns.logError("bookmark key", taken); taken = false end
    self:SetPropagateKeyboardInput(not taken)           -- every other key (and Space away from the bags) goes on to the game
end)

-- the note icon in a corner of bookmarked items
local icons = setmetatable({}, { __mode = "k" })
local function iconFor(b)
    local m = icons[b]
    if not m then
        ns.trying("marking bookmarked items in your bags", "bookmarks")
        m = CreateFrame("Frame", nil, UIParent)
        m:EnableMouse(false)
        m:SetWidth(14)
        m:SetHeight(14)
        m.tex = m:CreateTexture(nil, "OVERLAY")
        m.tex:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        m.tex:SetAllPoints(m)
        icons[b] = m
    end
    return m
end

function T.refreshIcons()
    local on = ns.db.enabled and ns.db.bagBookmarks and ns.bagEachSlot and not ns.isBlocked("bookmarks")
        and type(ns.db.bookmarks) == "table" and next(ns.db.bookmarks) ~= nil
    local used = {}
    if on then
        ns.bagEachSlot(function(b, bag, slot)
            if not (bag and slot and b.IsVisible and b:IsVisible()) then return end
            local info = slotInfo(bag, slot)
            if not (info and T.isBookmarked(info.id)) then return end
            local m = iconFor(b)
            m:ClearAllPoints()
            m:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
            if b.GetFrameStrata then m:SetFrameStrata(b:GetFrameStrata()) end
            if b.GetFrameLevel then m:SetFrameLevel((b:GetFrameLevel() or 1) + 4) end
            m:Show()
            used[b] = true
        end)
    end
    for b, m in pairs(icons) do if not used[b] then m:Hide() end end
end
function T.icons() return icons end                                    -- for the tests

local function iconTick()
    local ok, err = pcall(T.refreshIcons)
    if not ok then ns.logError("bookmark icons", err) end
    ns.after(TICK, iconTick)
end
ns.after(2, iconTick)

local hooked = false
local function hookTooltip()
    if hooked or not (GameTooltip and hooksecurefunc) then return end
    hooked = pcall(hooksecurefunc, GameTooltip, "SetBagItem", function(tip, bag, slot)
        if not ns.db.enabled then return end
        local info = slotInfo(bag, slot)
        if not (info and T.isBookmarked(info.id)) then return end
        pcall(function()
            tip:AddLine("Quest Sharing: bookmarked - never sold" .. (ns.db.bagBookmarks and " (Space removes it)" or ""), 0.9, 0.8, 0.4)
            tip:Show()
        end)
    end)
end
ns.on("PLAYER_LOGIN", hookTooltip)
hookTooltip()

-- Sell the gray items -----------------------------------------------------------------------------------------------------
local merchantOpen = false
local selling = false

local function merchantReady()
    if not merchantOpen then return false end
    return not (MerchantFrame and MerchantFrame.IsShown and not MerchantFrame:IsShown())
end

-- every gray item that may go: { bag, slot, id, price }
function T.grayItems()
    local list = {}
    for bag = 0, lastBag() do
        for slot = 1, numSlots(bag) do
            local info = slotInfo(bag, slot)
            if info then
                local f = facts(info.id)
                local quality = info.quality
                if quality == nil then quality = f.quality end
                if quality == 0 and not info.noValue and f.sell ~= 0 and not T.isBookmarked(info.id)
                    and not (ns.bagItemFor and ns.bagItemFor(bag, slot)) then          -- a quest still needs it
                    list[#list + 1] = { bag = bag, slot = slot, id = info.id, price = (tonumber(f.sell) or 0) * info.count }
                end
            end
        end
    end
    return list
end

local function sellNext(list, i, count, total)
    if not (merchantReady() and ns.db.enabled and ns.db.autoSellGray) then selling = false; return end
    local it = list[i]
    if not it then
        selling = false
        if count > 0 then
            ns.print(string.format("sold %d gray item%s for %s", count, count == 1 and "" or "s", money(total)))
            ns.log("sell", count .. " gray items, " .. total .. " copper")
        end
        return
    end
    local info = slotInfo(it.bag, it.slot)            -- still the same item, still not bookmarked?
    if info and info.id == it.id and not info.locked and not T.isBookmarked(it.id) then
        local use = cont("UseContainerItem")
        if use then
            ns.trying("selling gray items", "autosell")
            if pcall(use, it.bag, it.slot) then count, total = count + 1, total + it.price end
        end
    end
    ns.after(0.1, function() sellNext(list, i + 1, count, total) end)
end

function T.sellGray()
    if selling or not merchantReady() or ns.isBlocked("autosell") then return 0 end
    local list = T.grayItems()
    if #list == 0 then return 0 end
    selling = true
    sellNext(list, 1, 0, 0)
    return #list
end

local hinted = false                               -- the "selling is off" hint, once per session
ns.on("MERCHANT_SHOW", function()
    merchantOpen = true
    if not ns.db.enabled then return end
    if ns.db.autoSellGray then ns.after(0.2, T.sellGray); return end
    -- Off (the default): say once that the gray items could go, so a quiet vendor does not look like a broken feature.
    if hinted then return end
    ns.after(0.2, function()
        if hinted or not merchantReady() or ns.db.autoSellGray then return end
        local n = #T.grayItems()
        if n == 0 then return end
        hinted = true
        ns.print(string.format("%d gray item%s could be sold here - selling gray items is off: /qs sellgray on or Settings > Bags",
            n, n == 1 and "" or "s"))
    end)
end)
ns.on("MERCHANT_CLOSED", function() merchantOpen = false end)

-- Arrange by topic --------------------------------------------------------------------------------------------------------
local TOPICS = { "quest items", "consumables", "equipment", "materials", "recipes", "other", "gray items" }
T.topics = TOPICS
local TOPIC_OF_CLASS = {
    [0] = 2,                                   -- consumable
    [2] = 3, [4] = 3,                          -- weapon, armor
    [3] = 4, [5] = 4, [7] = 4, [8] = 4,        -- gem, reagent, trade goods, item enhancement
    [9] = 5,                                   -- recipe
    [12] = 1,                                  -- quest
}

local function describe(info, bag, slot, pos)
    local f = facts(info.id)
    local quality = info.quality
    if quality == nil then quality = f.quality end
    quality = quality or 1
    local topic = TOPIC_OF_CLASS[f.class or -1] or 6
    if f.class == 12 or (ns.bagItemFor and ns.bagItemFor(bag, slot)) then topic = 1
    elseif quality == 0 then topic = 7 end
    return { id = info.id, count = info.count, quality = quality, topic = topic, class = f.class or 99, sub = f.sub or 99,
             name = string.lower(f.name or ""), pos = pos }
end

local function byTopic(a, b)
    if a.topic ~= b.topic then return a.topic < b.topic end
    if a.class ~= b.class then return a.class < b.class end
    if a.sub ~= b.sub then return a.sub < b.sub end
    if a.quality ~= b.quality then return a.quality > b.quality end
    if a.name ~= b.name then return a.name < b.name end
    if a.id ~= b.id then return a.id < b.id end
    if a.count ~= b.count then return a.count > b.count end
    return a.pos < b.pos                       -- identical items keep their order, so a tidy bag needs no moves
end

local function byQuality(a, b)                 -- best first; the same quality falls back to the topic order
    if a.quality ~= b.quality then return a.quality > b.quality end
    return byTopic(a, b)
end

local function byName(a, b)                    -- A to Z; the same name falls back to the topic order
    if a.name ~= b.name then return a.name < b.name end
    return byTopic(a, b)
end

local ORDERS = { topic = byTopic, quality = byQuality, name = byName }
local ORDER_WORDS = { topic = "by topic", quality = "by quality", name = "by name" }
T.orders = { "topic", "quality", "name" }

-- the bags the player chose to arrange (Settings > Bags > Bags to arrange)
local function sortedBags()
    local which, list = ns.db.sortBags, {}
    local first = (which == "bags") and 1 or 0
    local last = (which == "backpack") and 0 or lastBag()
    for bag = first, last do list[#list + 1] = bag end
    return list
end

-- The moves that would put every item in its place: { { from = {bag, slot}, to = {bag, slot} }, ... } and the items in
-- their target order. The chosen bags are one list of slots: backpack first, then bag 1, 2, 3, 4 (reversed when
-- the items gather at the end). A bookmarked item kept in place takes its slot out of the list.
function T.plan(keepFacts)
    if not keepFacts then factMemo = {} end
    local keepMarked = ns.db.sortKeepBookmarked
    local raw = {}
    for _, bag in ipairs(sortedBags()) do
        if bagKind(bag) == 0 then
            for slot = 1, numSlots(bag) do
                local info = slotInfo(bag, slot)
                if not (keepMarked and info and T.isBookmarked(info.id)) then
                    raw[#raw + 1] = { bag = bag, slot = slot, info = info }
                end
            end
        end
    end
    if ns.db.sortFrom == "end" then
        for i = 1, math.floor(#raw / 2) do raw[i], raw[#raw + 1 - i] = raw[#raw + 1 - i], raw[i] end
    end
    local slots, items = {}, {}
    for pos, r in ipairs(raw) do
        slots[pos] = { bag = r.bag, slot = r.slot }
        if r.info then items[#items + 1] = describe(r.info, r.bag, r.slot, pos) end
    end
    local order = {}
    for i, it in ipairs(items) do order[i] = it end
    table.sort(order, ORDERS[ns.db.sortBy] or byTopic)
    local cur, where, moves = {}, {}, {}
    for _, it in ipairs(items) do cur[it.pos], where[it] = it, it.pos end
    for i, it in ipairs(order) do
        local j = where[it]
        if j ~= i then
            local other = cur[i]
            moves[#moves + 1] = { from = slots[j], to = slots[i] }
            cur[i], cur[j] = it, other
            where[it] = i
            if other then where[other] = j end
        end
    end
    return moves, order
end

local sorting, autoTimer = nil, nil

local function busyReason()
    if inFight() then return "you are in a fight" end
    if holdingItem() then return "you are holding an item" end
    if selling then return "items are being sold" end
end

local function pickup(bag, slot)
    local f = cont("PickupContainerItem")
    if f then return pcall(f, bag, slot) end
    return false
end

local function finishSort(job, why)
    sorting = nil
    if job.manual or why ~= "done" then
        ns.print(why == "done" and (job.moves == 0 and "your bags are already in order"
            or string.format("bags arranged %s (%d moves)", ORDER_WORDS[ns.db.sortBy] or ORDER_WORDS.topic, job.moves)) or ("bag arrangement stopped: " .. why))
    end
    ns.log("sort", why .. ", " .. job.moves .. " moves")
end

local function sortStep(job)
    if sorting ~= job then return end
    job.timer = nil
    if not ns.db.enabled then return finishSort(job, "the addon is off") end
    if inFight() then return finishSort(job, "you are in a fight") end
    if job.moves >= MAX_MOVES then return finishSort(job, "too many moves") end
    if holdingItem() then
        job.waits = job.waits + 1
        if job.waits > MAX_WAIT then return finishSort(job, "you are holding an item") end
        job.timer = ns.after(STEP, function() sortStep(job) end)
        return
    end
    local moves = T.plan(true)                               -- look again every time: new loot or your own moves never matter
    local m = moves[1]
    if not m then return finishSort(job, "done") end
    local a, b = slotInfo(m.from.bag, m.from.slot), slotInfo(m.to.bag, m.to.slot)
    if (a and a.locked) or (b and b.locked) then            -- the game has not finished the last move yet
        job.waits = job.waits + 1
        if job.waits > MAX_WAIT then return finishSort(job, "the game kept the slots locked") end
        job.timer = ns.after(STEP, function() sortStep(job) end)
        return
    end
    job.waits = 0
    local sig = m.from.bag .. ":" .. m.from.slot .. ">" .. m.to.bag .. ":" .. m.to.slot
    job.same = (job.last == sig) and (job.same + 1) or 0          -- the same move again and again: the game refuses it
    job.last = sig
    if job.same >= 3 then return finishSort(job, "the game would not move an item") end
    ns.trying("arranging the bags", "bagsort")
    pickup(m.from.bag, m.from.slot)
    pickup(m.to.bag, m.to.slot)
    if holdingItem() then pickup(m.from.bag, m.from.slot) end   -- swapped with another item: that one goes where ours was
    job.moves = job.moves + 1
    job.timer = ns.after(STEP, function() sortStep(job) end)
end

-- manual: the player asked (/qs sort, the settings button), so say why nothing happens
function T.sort(manual)
    if sorting then return false end
    if ns.isBlocked("bagsort") then
        if manual then ns.print("arranging bags is switched off until /reload: the game refused it") end
        return false
    end
    local why = busyReason()
    if why then
        if manual then ns.print("bags are not arranged: " .. why) end
        return false, why
    end
    factMemo = {}
    local job = { moves = 0, waits = 0, same = 0, manual = manual }
    sorting = job
    sortStep(job)
    return true
end

function T.isSorting() return sorting ~= nil end

local function schedule()
    if autoTimer then ns.cancel(autoTimer); autoTimer = nil end
    if sorting or not (ns.db.enabled and ns.db.autoSortBags) then return end
    autoTimer = ns.after(AUTO_DELAY, function()
        autoTimer = nil
        if inFight() then return end                         -- PLAYER_REGEN_ENABLED starts the wait again
        local started, why = T.sort(false)
        if not started and why and not inFight() then schedule() end   -- holding an item or selling: look again later
    end)
end
for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "MERCHANT_CLOSED" }) do
    ns.on(ev, schedule)
end
ns.on("PLAYER_REGEN_DISABLED", function()
    if autoTimer then ns.cancel(autoTimer); autoTimer = nil end
end)

-- a setting changed (Core.lua ns.setSetting)
function T.refresh()
    keys:EnableKeyboard((ns.db.enabled and ns.db.bagBookmarks) and true or false)
    pcall(T.refreshIcons)
    schedule()
end
ns.on("PLAYER_LOGIN", T.refresh)
ns.on("PLAYER_ENTERING_WORLD", T.refresh)
