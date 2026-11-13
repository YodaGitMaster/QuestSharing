-- A local, on-demand catalogue of quest reward equipment. QuestieDB owns reward links and quest restrictions;
-- the game supplies equipment slots, stats and comparison tooltips. No database scan happens at login.
local ADDON, ns = ...
local R, U, S, E = {}, ns.optionalUI, ns.style, ns.equipmentUI
ns.rewards = R
local index, results, quests, window = {}, {}, {}, nil
local loading, ready, generation, pending = false, false, 0, false
local page, PAGE, scanDone, scanTotal = 1, 7, 0, 0
local unknownItems = 0
local filters, selectedKey
local function resultKey(r) return r.itemID .. ":" .. r.questID end
local catalogueError = "Needs a recent QuestieDB with an enumerable item catalogue."
local function get(kind, id, key) return ns.questie.get(kind, id, key) end
local function num(v) return tonumber(v) or 0 end
local function enums() return type(LibQuestieDB) == "table" and LibQuestieDB.Enum or {} end
local function classKeys() return enums().classKeys or {} end
local function playerClass() local _, c = U.call(UnitClass, "player"); return c end
local function playerFaction() return U.call(UnitFactionGroup, "player") end

-- Arithmetic rather than bit.band: Forever race masks include bits above the 32-bit range.
local function overlaps(a, b)
    a, b = num(a), num(b)
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then return true end
        a, b = math.floor(a / 2), math.floor(b / 2)
    end
    return false
end
R.overlaps = overlaps

local function raceMask()
    local fn = UnitRace
    if not fn then return nil end
    local _, _, id = U.call(fn, "player")
    local map = enums().raceMaskById
    return map and map[id]
end

-- Classic equipment families. Unknown classes are left visible with a warning, rather than guessed.
-- Item-specific class restrictions remain in the game's tooltip; QuestieDB has no item allowed-class field.
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18, 20 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8, 20 }, HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 18, 20 },
    ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18, 20 }, PRIEST = { 4, 10, 15, 19, 20 },
    SHAMAN = { 0, 1, 4, 5, 10, 13, 15, 20 }, MAGE = { 7, 10, 15, 19, 20 },
    WARLOCK = { 7, 10, 15, 19, 20 }, DRUID = { 4, 5, 10, 15, 20 },
}
local ARMOR = { WARRIOR = 4, PALADIN = 4, HUNTER = 3, ROGUE = 2, PRIEST = 1, SHAMAN = 3, MAGE = 1, WARLOCK = 1, DRUID = 2 }
local SHIELDS = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local function canEquip(item, class, level)
    if item.kind == 2 then
        local list = WEAPONS[class]
        if not list then return true end
        for _, sub in ipairs(list) do if sub == item.sub then return true end end
        return false
    end
    if item.kind ~= 4 then return false end
    if item.sub == 6 then return SHIELDS[class] == true end
    if item.sub >= 7 and item.sub <= 10 then
        return ({ [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN", [10] = "DEATHKNIGHT" })[item.sub] == class
    end
    if item.sub == 0 then return true end -- rings, cloaks, necks, trinkets and held-in-offhand
    local max = ARMOR[class]
    if not max then return true end
    if level < 40 and (class == "HUNTER" or class == "SHAMAN") then max = 2 end
    if level < 40 and (class == "WARRIOR" or class == "PALADIN") then max = 3 end
    return item.sub >= 1 and item.sub <= max
end

local SLOTS = { "All slots", "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "Finger", "Trinket", "Weapon", "Offhand", "Ranged" }
local SLOT = { INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back",
    INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest", INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist",
    INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Trinket",
    INVTYPE_WEAPON = "Weapon", INVTYPE_2HWEAPON = "Weapon", INVTYPE_WEAPONMAINHAND = "Weapon",
    INVTYPE_WEAPONOFFHAND = "Offhand", INVTYPE_SHIELD = "Offhand", INVTYPE_HOLDABLE = "Offhand",
    INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged", INVTYPE_THROWN = "Ranged", INVTYPE_RELIC = "Ranged" }

local function info(id)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not fn then return nil end
    local ok, name, link, quality, level, required, _, _, _, loc, texture, _, kind, sub = pcall(fn, id)
    if not ok or not name then return nil end
    local dbKind = tonumber((get("item", id, "class")))
    kind = tonumber(kind) or dbKind
    sub = tonumber(sub)
    if sub == nil and (dbKind == 2 or dbKind == 4) then sub = tonumber((get("item", id, "subClass"))) end
    if (not kind or kind == 0) and SLOT[loc] then
        kind = (SLOT[loc] == "Weapon" or (SLOT[loc] == "Ranged" and loc ~= "INVTYPE_RELIC")) and 2 or 4
    end
    return { name = name, link = link, quality = quality, level = level, required = required, slot = SLOT[loc], texture = texture, kind = kind, sub = sub }
end
R.itemInfo = info -- shared native item metadata reader for the instance loot browser

local function quest(id)
    if quests[id] then return quests[id] end
    local q = { id = id, name = get("quest", id, "name"), required = num(get("quest", id, "requiredLevel")),
        level = num(get("quest", id, "questLevel")), max = num(get("quest", id, "requiredMaxLevel")),
        classes = num(get("quest", id, "requiredClasses")), races = num(get("quest", id, "requiredRaces")) }
    quests[id] = q
    return q
end

local function completed(id)
    return U.call((C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted, id)
end

local function eligible(q, f)
    if not q.name or q.name == "" or q.required > f.level or (q.max > 0 and q.max < f.level) then return false end
    if f.near and q.level > 0 and (q.level < f.level - 10 or q.level > f.level + 3) then return false end
    local class = classKeys()[f.class]
    if q.classes ~= 0 and (not class or not overlaps(q.classes, class)) then return false end
    if q.races ~= 0 then
        local factionMask = enums().factionRaceMasks and enums().factionRaceMasks[f.faction]
        if not factionMask or not overlaps(q.races, factionMask) then return false end
        local mine = raceMask()
        if f.faction == playerFaction() and mine and not overlaps(q.races, mine) then return false end
    end
    if not f.completed and completed(q.id) == true then return false end
    return true
end

local function defaults()
    return { class = playerClass(), level = math.max(1, num(U.call(UnitLevel, "player"))), faction = playerFaction(),
        slot = "All slots", near = true, completed = false, text = "" }
end

local function detail(r)
    local q = ns.questie
    local starter = q.starter(r.questID)
    local before, any = q.before(r.questID)
    local lines = { r.name .. " — item level " .. r.itemLevel,
        "Equipment: " .. r.slot .. "; requires character level " .. tostring(r.info and r.info.required or "unknown"),
        r.questName .. " (quest " .. r.questLevel .. ", requires level " .. r.requiredLevel .. ")",
        q.whereText(r.questID) or "Quest starting location unknown." }
    if #before > 0 then lines[#lines + 1] = "Prerequisites (" .. (any and "any" or "all") .. "): " .. table.concat(before, ", ") end
    for _, key in ipairs({ "requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredSpell" }) do
        local v = get("quest", r.questID, key)
        if (type(v) == "table" and next(v)) or (type(v) == "number" and v ~= 0) then
            lines[#lines + 1] = "Additional " .. key .. " requirement; check the quest before travelling."
        end
    end
    lines[#lines + 1] = "Quest chains and other requirements may still block acceptance."
    lines[#lines + 1] = "Reward choices are alternatives; not every listed item is guaranteed together."
    return lines, starter
end
R.detail = detail

function R.search(f)
    filters = f or filters or defaults()
    results = {}
    unknownItems=0
    local waiting={}
    local f = filters
    local needle = string.lower(f.text or "")
    local level = num(f.level)
    if level < 1 or level > 1000 or level % 1 ~= 0 or not f.class or not f.faction then return results end
    for _, item in ipairs(index) do
        if item.required <= level and canEquip(item, f.class, level) then
            local itemInfo -- request game info only for eligible rewards, not every item in the database
            for _, qid in ipairs(item.quests) do
                local q = quest(qid)
                if eligible(q, f) then
                    itemInfo = itemInfo or info(item.id)
                    if (not itemInfo or type(itemInfo.quality)~="number") and not waiting[item.id] then
                        unknownItems=unknownItems+1;waiting[item.id]=true
                    end
                    local name = itemInfo and itemInfo.name or item.name or ("Item " .. item.id)
                    local slot = itemInfo and itemInfo.slot
                    local starter = ns.questie.starter(qid)
                    local text = string.lower(name .. " " .. q.name .. " " .. (starter and starter.zone or ""))
                    if (not itemInfo or (slot and num(itemInfo.required) <= level))
                        and E.matches(itemInfo, item)
                        and (f.slot == "All slots" or f.slot == slot) and (needle == "" or string.find(text, needle, 1, true)) then
                        results[#results + 1] = { itemID = item.id, name = name, info = itemInfo, link = itemInfo and itemInfo.link,
                            itemLevel = itemInfo and num(itemInfo.level) > 0 and itemInfo.level or item.level,
                            slot = slot or "Details loading", questID = qid, questName = q.name, questLevel = q.level,
                            requiredLevel = q.required, zone = starter and starter.zone or "Unknown start", cached = itemInfo ~= nil }
                    end
                end
            end
        end
    end
    E.sortResults(results,function(r) return r.info end,function(r) return r.name end,function(a,b)
        if a.questID~=b.questID then return a.questID<b.questID end
        return a.itemID<b.itemID
    end)
    return results
end

local function paint()
    if not window then return end
    page = math.max(1, math.min(page, math.max(1, math.ceil(#results / PAGE))))
    window.status:SetText(window.levelError or (loading and ("Reading QuestieDB items: " .. scanDone .. "/" .. scanTotal)
        or (not ready and catalogueError)
        or E.pageStatus((page-1)*PAGE+1,PAGE,#results))
        .. (unknownItems>0 and (" • "..unknownItems.." item details loading") or ""))
    E.pageButtons(window.prev,window.next,#results,page,PAGE)
    for i, row in ipairs(window.rows) do
        local r = results[(page - 1) * PAGE + i]
        row.result = r
        if r then
            E.paintRow(row, r.info, r.name .. " · iLvl " .. r.itemLevel .. " · req " .. tostring(r.info and r.info.required or "?"),
                r.questName .. " — " .. r.zone)
            row.frame:Show()
        else row.frame:Hide() end
    end
    if not E.focusRows(window.rows,selectedKey,resultKey) then
        selectedKey,window.routeMap=nil,nil
        window.setRoute((loading or unknownItems>0) and "Loading equipment details… Eligible blue+ items appear as the game supplies their data." or (not ready and catalogueError)
            or "No matching blue-or-better equipment.\n\nClear filters or broaden your search. Your character's class, faction and quest requirements still apply.")
    end
end

function R.go(delta)
    local nextPage=math.max(1,math.min(math.max(1,math.ceil(#results/PAGE)),page+delta))
    if nextPage==page then return false end
    page=nextPage;paint();return true
end

function R.refresh()
    if not (window and E.visible("quests") and ns.db.enabled and ns.db.rewardBrowser) then return end
    R.search(); paint()
end

local function schedule()
    if pending or not (window and E.visible("quests")) then return end
    pending = true
    ns.after(0.2, function() pending = false; R.refresh() end)
end

function R.scan()
    E.dismissMenu()
    generation = generation + 1
    local token = generation
    index, quests, results = {}, {}, {}
    loading, ready, scanDone = false, false, 0
    local db = type(ItemDB) == "table" and type(ItemDB.GetAllIds) == "function" and ItemDB
        or (type(LibQuestieDB) == "table" and LibQuestieDB.Item)
    local ids = db and U.call(db.GetAllIds)
    catalogueError = "Needs a recent QuestieDB with an enumerable item catalogue."
    if type(ids) ~= "table" then paint(); return false end
    local e = enums()
    if type(e.classKeys) ~= "table" or type(e.factionRaceMasks) ~= "table" or type(e.raceMaskById) ~= "table" then
        catalogueError = "Update QuestieDB: class, faction or race mappings are unavailable."
        paint(); return false
    end
    loading, scanTotal = true, #ids
    local cursor = 1
    local function batch()
        if token ~= generation then return end
        if not ns.db.enabled or not ns.db.rewardBrowser or not E.visible("quests") then loading = false; return end
        for _ = 1, 100 do
            local id = ids[cursor]
            if not id then
                loading, ready = false, true
                R.refresh(); paint()
                return
            end
            cursor = cursor + 1
            local kind = num(get("item", id, "class"))
            if kind == 2 or kind == 4 then
                local list = get("item", id, "questRewards")
                if type(list) == "table" and #list > 0 then
                    index[#index + 1] = { id = id, kind = kind, sub = num(get("item", id, "subClass")),
                        quests = list, name = get("item", id, "name"), level = num(get("item", id, "itemLevel")),
                        required = num(get("item", id, "requiredLevel")) }
                end
            end
            scanDone = scanDone + 1
        end
        paint(); ns.after(0.01, batch)
    end
    batch()
    return true
end

local function choice(parent,label,x,y,width,choices,key)
    return E.dropdown(parent,label,x,y,width,choices,function() return filters[key] end,function(value)
        filters[key]=value;page=1;R.updateControls();R.refresh()
    end)
end

function R.updateControls()
    if not window then return end
    for _, b in ipairs(window.controls) do b.refresh() end
    window.near:SetLabel("Quest levels: " .. (filters.near and ("near "..filters.level) or "all"))
    window.completed:SetLabel(filters.completed and "Showing completed quests" or "Hiding completed quests")
end

local function build()
    if window then return true end
    local f = E.page("quests")
    if not f then return false end
    window = { frame = f, rows = {}, controls = {} }
    local classes = {}
    for k, v in pairs(classKeys()) do if type(v) == "number" and v > 0 and not string.find(k, "ALL", 1, true) and k ~= "NONE" then classes[#classes + 1] = k end end
    if #classes == 0 then for k in pairs(WEAPONS) do classes[#classes + 1] = k end end
    table.sort(classes)
    local names=LOCALIZED_CLASS_NAMES_MALE or {}
    for i,key in ipairs(classes) do
        local label=names[key] or (key=="DEATHKNIGHT" and "Death Knight") or (string.upper(string.sub(key,1,1))..string.lower(string.sub(key,2)))
        classes[i]={value=key,label=label}
    end
    window.controls[1] = choice(f, "Class", 0, 8, 165, classes, "class")
    window.controls[2] = choice(f, "Faction", 175, 8, 165, { "Alliance", "Horde" }, "faction")
    window.level = U.box(f, "Character level", 350, 0, 110, filters.level, 4)
    E.liveBox(window.level,"quests",function(text)
        local n=tonumber(text)
        if n and n>=1 and n<=1000 and n%1==0 then
            filters.level=n;window.levelError=nil;page=1;R.updateControls();R.refresh()
        else
            window.levelError=S.RED.."Character level must be a whole number from 1 to 1000.|r";paint()
        end
    end)
    window.level:SetScript("OnEscapePressed",function(self)
        self:SetText(tostring(filters.level));self.cancel();window.levelError=nil;self:ClearFocus();R.refresh()
    end)
    local mine = S.button(f, "My character", 180, function()
        E.dismissMenu()
        filters = defaults();window.levelError=nil;window.level:SetText(tostring(filters.level));window.level.cancel();window.search:SetText("");window.search.cancel()
        page = 1; R.updateControls(); R.refresh()
    end)
    mine:SetPoint("TOPLEFT", f, "TOPLEFT", 470, -18)
    window.near = S.button(f, "", 165, function() E.dismissMenu();filters.near = not filters.near; page = 1; R.updateControls(); R.refresh() end)
    window.near:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -54)
    window.completed = S.button(f, "", 165, function() E.dismissMenu();filters.completed = not filters.completed; page = 1; R.updateControls(); R.refresh() end)
    window.completed:SetPoint("TOPLEFT", f, "TOPLEFT", 175, -54)
    window.search,window.clearSearch = E.searchBox(f,"Search item, quest or zone",350,42,300,"quests",function(text)
        filters.text=text;page=1;R.refresh()
    end)
    window.status = U.text(f, "", 0, 92, 650)
    window.list=CreateFrame("Frame",nil,f)
    window.list:SetPoint("TOPLEFT",f,"TOPLEFT",0,-120);window.list:SetWidth(650);window.list:SetHeight(371)
    E.wheel(window.list,R.go)
    for i = 1, PAGE do
        local row = E.row(window.list, 0, (i-1)*53, 650, i)
        E.wheel(row.frame,R.go)
        local b = row.frame
        row.quest = row.from
        b:SetScript("OnEnter", function(self)
            row.bg:SetVertexColor(1.3,1.3,1.3)
            local r = row.result
            if not r then return end
            if GameTooltip and GameTooltip.SetHyperlink then
                pcall(function()
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. r.itemID)
                    GameTooltip:AddLine("Quest: " .. r.questName, 1, 0.82, 0)
                    GameTooltip:AddLine("Click for location and prerequisites.", 1, 1, 1)
                    GameTooltip:Show()
                    if GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
                end)
            else U.tip(self, r.name, (detail(r))) end
        end)
        b:SetScript("OnLeave", function() local tint=row.selected and 1.15 or 1;row.bg:SetVertexColor(tint,tint,tint);U.hideTip() end)
        row.choose=function(auto)
            if auto~=true then E.dismissMenu() end
            local r = row.result
            if not r then return end
            local lines, starter = detail(r)
            selectedKey=resultKey(r)
            E.select(window.rows, row)
            window.setRoute(table.concat(lines, "\n"))
            window.routeMap = starter and starter.area and ns.questie.uiMapOf(starter.area)
        end
        b:SetScript("OnClick",row.choose)
        window.rows[i] = row
    end
    window.prev = S.button(f, "Previous", 100, function() R.go(-1) end)
    window.prev:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -500)
    window.next = S.button(f, "Next", 100, function() R.go(1) end)
    window.next:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -500)
    window.reload = S.button(f, "Refresh data", 120, function() R.scan() end)
    window.reload:SetPoint("TOPLEFT", f, "TOPLEFT", 530, -500)
    U.text(f, "Compare stats for your build. Quest chains, reputation and skills may affect availability.", 0, 536, 650)
    window.routeFrame, window.route, window.setRoute = E.details(f, 674, 358, "Quest route")
    local map = S.button(window.routeFrame, "Map directions (open M)", 260, function()
        if not U.mapHint(window.routeMap) then ns.print("this quest has no known map for its starting zone") end
    end)
    map:SetPoint("BOTTOMLEFT", window.routeFrame, "BOTTOMLEFT", 14, 18)
    E.navigation(window.search,window.rows,R.go)
    f.clear=function()
        filters.text,filters.near,filters.completed="",false,false
        window.search:SetText("");window.search.cancel()
        window.levelError=nil;window.level:SetText(tostring(filters.level));window.level.cancel()
        page=1;R.updateControls();R.refresh()
    end
    f.refresh = function() page=1; R.refresh() end
    f.suspend = function()
        generation = generation + 1
        if loading then loading, ready = false, false end
    end
    f:SetScript("OnHide", f.suspend)
    return true
end

function R.open()
    if not ns.db.enabled then ns.print("switch Quest Sharing on first (/qs on)"); return end
    if not ns.db.rewardBrowser then ns.setSetting("rewardBrowser", true) end
    filters = filters or defaults()
    if not build() then return end
    R.updateControls(); E.show("quests")
    for _,box in ipairs({window.search,window.level}) do if box.dirty then box.flush() end end
    if not ready and not loading then R.scan() else R.refresh() end
end

function R.settingChanged()
    if not ns.db.enabled or not ns.db.rewardBrowser then
        generation = generation + 1; loading = false
        if window then E.close("quests") end
    end
end

function R._window() return window end
function R._results() return results end
function R._state() return ready, loading, #index end
for _, ev in ipairs({ "GET_ITEM_INFO_RECEIVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP" }) do ns.on(ev, schedule) end
