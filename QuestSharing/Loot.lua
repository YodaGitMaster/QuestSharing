-- On-demand instance loot search. AtlasLoot supplies encounter tables; QuestieDB is a labelled partial fallback.
-- Provider tables are never edited here. Names are requested from the game in small batches while this window is open.
local ADDON, ns = ...
local L, U, S, Q, E = {}, ns.optionalUI, ns.style, ns.questie, ns.equipmentUI
ns.loot = L
local W, index, results, instances, items = nil, {}, {}, {}, {}
local generation, loading, ready, pending = 0, false, false, false
local source, note, skipped, progress = nil, "Open to load instance drops.", 0, 0
local chosen, encounter, query, instanceQuery = nil, nil, "", ""
local itemQueue, queueAt, page, instancePage = {}, 1, 1, 1
local deferredAtlas = false
local unresolved, selectedKey = 0, nil
local function resultKey(r) return table.concat({r.itemID,r.instanceKey,r.who,r.difficulty},"\031") end
local PAGE, INSTANCE_PAGE = 7, 9
local paint, refresh
local function clean(s)
    return type(s) == "string" and (string.gsub(string.gsub(s, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")) or nil
end
local function positive(n) return type(n) == "number" and n > 0 and n < math.huge and n % 1 == 0 end
local function field(kind, id, key) return Q.get(kind, id, key) end
local function shown() return W and E.visible("dungeons") and ns.db.enabled end
local function atlas() return AtlasLoot or AtlasLootContinued end
local function areaName(id)
    return clean(U.call(C_Map and C_Map.GetAreaInfo, id) or U.call(GetAreaInfo, id)) or ("Instance area " .. tostring(id))
end

local function item(id)
    if not items[id] then
        items[id] = { id = id, name = clean(field("item", id, "name")) or ("Item " .. id), cached = false }
        unresolved = unresolved + 1
        itemQueue[#itemQueue + 1] = id
    end
    return items[id]
end

local function readItem(id)
    local cached = items[id]
    if not cached then return end
    local info = ns.rewards.itemInfo(id)
    if info then
        if not cached.cached then unresolved = unresolved - 1 end
        cached.name, cached.info, cached.cached = info.name, info, true
    end
end

local function instance(key, name)
    if not instances[key] then instances[key] = { key = key, name = name, count = 0 } end
    return instances[key]
end

local seen = {}
local function add(id, place, who, mode, provider, sourceID, kind)
    if not positive(id) then return end
    local key = table.concat({ id, place.key, sourceID or who, mode or "" }, "\031")
    if seen[key] then return end
    seen[key] = true
    index[#index + 1] = { itemID = id, item = item(id), instanceKey = place.key, instanceName = place.name,
        who = who, difficulty = mode or "", provider = provider, sourceID = sourceID, kind = kind or "encounter" }
    place.count = place.count + 1
end

function L.search(text, key, boss)
    if text ~= nil then query = text end
    chosen, encounter = key, boss
    local needle = string.lower(query)
    results = {}
    for _, r in ipairs(index) do
        local haystack = string.lower(r.item.name .. " " .. r.itemID .. " " .. r.instanceName .. " " .. r.who .. " " .. r.difficulty)
        -- Unclassified items stay hidden until the game confirms a weapon or wearable equipment slot.
        if r.item.info and r.item.info.slot and E.matches(r.item.info)
            and (not chosen or chosen == r.instanceKey) and (not encounter or encounter == r.who)
            and (needle == "" or string.find(haystack, needle, 1, true)) then results[#results + 1] = r end
    end
    E.sortResults(results,function(r) return r.item.info end,function(r) return r.item.name end,function(a,b)
        if a.instanceName~=b.instanceName then return a.instanceName<b.instanceName end
        if a.who~=b.who then return a.who<b.who end
        if a.itemID~=b.itemID then return a.itemID<b.itemID end
        return a.difficulty<b.difficulty
    end)
    return results
end

function L.instances(text)
    local list, needle = {}, string.lower(text or "")
    for _, place in pairs(instances) do
        if needle == "" or string.find(string.lower(place.name), needle, 1, true) then list[#list + 1] = place end
    end
    table.sort(list, function(a, b) if a.name == b.name then return a.key < b.key end; return a.name < b.name end)
    return list
end

local function bosses()
    local set, list = {}, {}
    for _, r in ipairs(index) do
        if r.item.info and r.item.info.slot and E.matches(r.item.info) and (not chosen or r.instanceKey == chosen) and not set[r.who] then
            list[#list + 1] = r.who; set[r.who] = true
        end
    end
    table.sort(list)
    return list
end

local function pumpNames(token)
    if token ~= generation or not shown() then return end
    for _ = 1, 10 do
        local id = itemQueue[queueAt]
        if not id then refresh(); return end
        queueAt = queueAt + 1
        readItem(id)
        if not items[id].cached and C_Item and C_Item.RequestLoadItemDataByID then U.call(C_Item.RequestLoadItemDataByID, id) end
    end
    refresh()
    ns.after(0.1, function() pumpNames(token) end)
end

-- Known Classic/Forever dungeon instance and area IDs also cover partial QuestieDB sources;
-- UIMapType.Dungeon alone cannot distinguish a dungeon from a raid interior.
local dungeonIDs = { [389]=true,[43]=true,[36]=true,[33]=true,[48]=true,[34]=true,[90]=true,[47]=true,
    [189]=true,[129]=true,[70]=true,[209]=true,[349]=true,[109]=true,[230]=true,[229]=true,[429]=true,[289]=true,[329]=true,[3065]=true,[2999]=true,[2998]=true,[2959]=true,[3002]=true }
local dungeonAreas = { [2437]=true,[718]=true,[1581]=true,[209]=true,[719]=true,[717]=true,[721]=true,[491]=true,
    [796]=true,[722]=true,[1337]=true,[1176]=true,[2100]=true,[1477]=true,[1584]=true,[1583]=true,[2557]=true,[2057]=true,[2017]=true,[16611]=true,[16732]=true,[16560]=true,[3002]=true }
local function standardDungeon(content, module, owner)
    if content.IsRaid or (tonumber(content.MaxPlayers) or 0) > 10 then return false end
    local types = U.call(module.GetContentTypes, module)
    local kind = type(types) == "table" and types[content.ContentType]
    local category = type(kind) == "table" and kind[1] or U.call(content.GetContentType, content)
    local dungeonName = owner.Locales and owner.Locales["Dungeons"] or "Dungeons"
    if category and category ~= dungeonName then return false end
    if content.InstanceID ~= nil then
        return positive(content.InstanceID) and (category == dungeonName or dungeonIDs[content.InstanceID] == true)
    end
    return dungeonAreas[content.MapID] == true -- Dire Maul wings omit InstanceID in some compatible catalogues.
end

-- Use AtlasLoot's public reader so inherited difficulty tables and cross-encounter links resolve correctly.
local function atlasJobs()
    local a = atlas()
    local db = type(a) == "table" and a.ItemDB
    local storage = type(db) == "table" and db.Storage
    if type(storage) ~= "table" or type(db.GetItemTable) ~= "function" then return nil end
    local jobs = {}
    for moduleName, module in pairs(storage) do
        if type(moduleName) == "string" and string.find(moduleName, "DungeonsAndRaids", 1, true) and type(module) == "table" then
            for key, content in pairs(module) do
                if type(content) == "table" and type(content.items) == "table" and standardDungeon(content, module, a) then
                    local name = clean(content.name) or clean(U.call(content.GetName, content, true))
                        or areaName(content.MapID or content.AreaID or content.InstanceID)
                    local place = instance(moduleName .. ":" .. tostring(key), name)
                    for bossID, boss in pairs(content.items) do
                        if type(bossID) == "number" and type(boss) == "table" and not boss.IgnoreAsSource then
                            local who = clean(boss.name) or clean(U.call(content.GetNameForItemTable, content, bossID, true))
                                or (positive(boss.npcID) and clean(field("npc", boss.npcID, "name"))) or ("Encounter " .. bossID)
                            local original = boss
                            if type(boss.link) == "table" then
                                local target = storage[boss.link[1]]
                                target = target and target[boss.link[2]]
                                original = target and standardDungeon(target, storage[boss.link[1]], a)
                                    and target.items and target.items[boss.link[3]] or nil
                            end
                            for diff, rows in pairs(original or {}) do
                                if type(diff) == "number" and diff > 0 and (type(rows) == "table" or type(rows) == "string" or type(rows) == "number") then
                                    jobs[#jobs + 1] = { module = moduleName, content = key, boss = bossID,
                                        diff = diff, place = place, who = who, sourceID = bossID, db = db, owner = module }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if not next(instances) then return nil end
    return jobs
end

local function loadAtlas()
    if not atlas() then return end
    if U.call(InCombatLockdown) then return end
    local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if not loader then return end
    for _, name in ipairs({ "AtlasLootClassic_DungeonsAndRaids", "AtlasLootContinued_DungeonsAndRaids" }) do
        U.call(loader, name) -- only on a player-requested scan, never at login
    end
end

local function questieSources(kind, id, cache)
    local key = kind .. ":" .. tostring(id)
    if cache[key] then return cache[key] end
    local found = {}
    local spawns = field(kind, id, "spawns")
    for area, points in pairs(type(spawns) == "table" and spawns or {}) do
        local inside = false
        for _, p in pairs(type(points) == "table" and points or {}) do
            if type(p) == "table" and p[1] == -1 and p[2] == -1 then inside = true; break end
        end
        if not inside then
            local map = Q.uiMapOf(area)
            local info = map and U.call(C_Map and C_Map.GetMapInfo, map)
            local dungeonType = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
            inside = type(info) == "table" and info.mapType == dungeonType
        end
        if inside and dungeonAreas[tonumber(area)] then
            local place = instance("area:" .. tostring(area), areaName(area))
            found[#found + 1] = { place = place, who = clean(field(kind, id, "name")) or (kind .. " " .. id),
                id = key, kind = kind }
        end
    end
    cache[key] = found
    return found
end

function L.scan()
    E.dismissMenu()
    generation = generation + 1
    local token = generation
    index, results, instances, items, seen, itemQueue = {}, {}, {}, {}, {}, {}
    queueAt, page, instancePage, progress, skipped, unresolved = 1, 1, 1, 0, 0, 0
    ready, loading, source = false, true, nil
    local jobs = atlasJobs()
    deferredAtlas = not jobs and atlas() and U.call(InCombatLockdown) and true or false
    if not jobs then loadAtlas(); jobs = atlasJobs() end
    local ids
    if jobs then
        source, note = "AtlasLoot", "Classic and Forever dungeon equipment from AtlasLoot. Raids and world bosses excluded."
    else
        local db = type(ItemDB) == "table" and type(ItemDB.GetAllIds) == "function" and ItemDB
            or (type(LibQuestieDB) == "table" and LibQuestieDB.Item)
        ids = db and U.call(db.GetAllIds)
        if type(ids) ~= "table" then
            loading = false
            note = "Install compatible AtlasLoot with DungeonsAndRaids, or QuestieDB for partial drop sources."
            if atlas() and U.call(InCombatLockdown) then note = "Leave combat to load AtlasLoot's dungeon catalogue, then Refresh data." end
            if paint then paint() end
            return false
        end
        source, note = "QuestieDB", "Partial QuestieDB sources for known Classic/Forever dungeons; AtlasLoot supplies fuller loot tables."
        if deferredAtlas then note = note .. " AtlasLoot will be retried after combat." end
    end
    local jobAt, rowAt, rows, mode, cache = 1, 1, nil, nil, {}
    local function step()
        if token ~= generation or not shown() then return end
        local budget = 100
        while budget > 0 do
            if jobs then
                local job = jobs[jobAt]
                if not job then break end
                if not rows then
                    local list, format, difficulty = U.call(job.db.GetItemTable, job.db, job.module, job.content, job.boss, job.diff)
                    if type(list) ~= "table" or (type(format) == "table" and format[1] and format[1] ~= "Item") then
                        skipped = skipped + 1; jobAt = jobAt + 1; budget = budget - 1
                    else
                        rows, rowAt = list, 1
                        mode = clean(type(difficulty) == "table" and difficulty.name)
                            or clean(U.call(job.owner.GetDifficultyName, job.owner, job.diff)) or ("Difficulty " .. job.diff)
                    end
                else
                    local r = rows[rowAt]
                    if not r then rows = nil; jobAt = jobAt + 1
                    else
                        if type(r) == "table" then add(r[2], job.place, job.who, mode, source, job.sourceID) end
                        rowAt = rowAt + 1; budget = budget - 1
                    end
                end
            else
                local id = ids[jobAt]
                if not id then break end
                for _, kind in ipairs({ "npc", "object" }) do
                    local drops = field("item", id, kind == "npc" and "npcDrops" or "objectDrops")
                    for _, from in ipairs(type(drops) == "table" and drops or {}) do
                        if positive(from) then
                            for _, s in ipairs(questieSources(kind, from, cache)) do add(id, s.place, s.who, "", source, s.id, s.kind) end
                        end
                    end
                end
                jobAt = jobAt + 1; budget = budget - 1
            end
        end
        progress = jobAt - 1
        local done = jobs and not jobs[jobAt] or not jobs and not ids[jobAt]
        if done then
            loading, ready = false, true
            if chosen and not instances[chosen] then chosen, encounter = nil, nil end
            refresh(); pumpNames(token)
        else
            paint(); ns.after(0.01, step)
        end
    end
    step()
    return true
end

paint = function()
    if not W then return end
    local places = L.instances(instanceQuery)
    instancePage = math.max(1, math.min(instancePage, math.max(1, math.ceil(#places / INSTANCE_PAGE))))
    W.instanceStatus:SetText(#places .. " dungeons — page " .. instancePage .. "/" .. math.max(1, math.ceil(#places / INSTANCE_PAGE)))
    for i, b in ipairs(W.instances) do
        local place = places[(instancePage - 1) * INSTANCE_PAGE + i]
        b.place = place
        if place then b:SetLabel((chosen == place.key and "> " or "") .. place.name); b:Show() else b:Hide() end
    end
    page = math.max(1, math.min(page, math.max(1, math.ceil(#results / PAGE))))
    local title = chosen and instances[chosen] and instances[chosen].name or "All dungeons"
    W.selection:SetText(S.GOLD .. title .. "|r")
    W.selection:SetWordWrap(false)
    W.boss.refresh()
    W.status:SetText(loading and ("Reading " .. tostring(source or "loot") .. " tables: " .. progress)
        or E.pageStatus((page-1)*PAGE+1,PAGE,#results))
    E.pageButtons(W.prev,W.next,#results,page,PAGE)
    E.pageButtons(W.instancePrev,W.instanceNext,#places,instancePage,INSTANCE_PAGE)
    W.note:SetText(note .. (skipped > 0 and (" " .. skipped .. " tables unavailable or not item lists.") or "")
        .. (queueAt <= #itemQueue and (" Loading item details " .. (queueAt - 1) .. "/" .. #itemQueue .. ".")
            or (unresolved > 0 and (" " .. unresolved .. " items await equipment details and remain hidden.") or "")))
    for i, row in ipairs(W.rows) do
        local r = results[(page - 1) * PAGE + i]
        row.result = r
        if r then
            E.paintRow(row, r.item.info, r.item.name .. " · iLvl " .. tostring(r.item.info.level or "?") .. " · req " .. tostring(r.item.info.required or "?"),
                r.who .. " — " .. r.instanceName .. (r.difficulty~="" and (" · "..r.difficulty) or ""))
            row.frame:Show()
        else row.frame:Hide() end
    end
    if not E.focusRows(W.rows,selectedKey,resultKey) then
        selectedKey=nil
        W.setDetails((loading or unresolved>0) and "Loading dungeon equipment details… Eligible blue+ drops appear as the game supplies their data." or
            (#index==0 and note) or "No matching blue-or-better equipment.\n\nTry Clear filters, another dungeon, or a broader search.")
    end
end

function L.go(delta)
    local nextPage=math.max(1,math.min(math.max(1,math.ceil(#results/PAGE)),page+delta))
    if nextPage==page then return false end
    page=nextPage;paint();return true
end
function L.goInstances(delta)
    local total=#L.instances(instanceQuery)
    local nextPage=math.max(1,math.min(math.max(1,math.ceil(total/INSTANCE_PAGE)),instancePage+delta))
    if nextPage==instancePage then return false end
    instancePage=nextPage;paint();return true
end

refresh = function()
    if not shown() then return end
    if encounter then
        local valid=false;for _,who in ipairs(bosses()) do if who==encounter then valid=true;break end end
        if not valid then encounter=nil end
    end
    L.search(query, chosen, encounter); paint()
end

local function schedule()
    if pending or not shown() then return end
    pending = true
    ns.after(0.2, function() pending = false; refresh() end)
end

local function build()
    if W then return true end
    local f = E.page("dungeons")
    if not f then return false end
    W = { frame = f, instances = {}, rows = {} }
    W.instanceSearch,W.clearInstanceSearch=E.searchBox(f,"Find dungeon",0,0,190,"dungeons",function(text)
        instanceQuery=text;instancePage=1;paint()
    end)
    W.search,W.clearSearch=E.searchBox(f,"Search item, ID, boss or dungeon",210,0,450,"dungeons",function(text)
        query=text;page=1;refresh()
    end)
    local all = S.button(f, "All dungeons", 190, function() E.dismissMenu();chosen, encounter, page = nil, nil, 1; refresh() end)
    all:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -54)
    W.selection = U.text(f, "All dungeons", 0, 87, 190)
    W.boss=E.dropdown(f,"Source",210,54,450,function()
        local list={"All encounters"};for _,who in ipairs(bosses()) do list[#list+1]=who end;return list
    end,function() return encounter or "All encounters" end,function(value)
        encounter=value~="All encounters" and value or nil;page=1;refresh()
    end)
    W.instanceStatus = U.text(f, "", 0, 112, 190)
    W.dungeonList=CreateFrame("Frame",nil,f)
    W.dungeonList:SetPoint("TOPLEFT",f,"TOPLEFT",0,-145);W.dungeonList:SetWidth(190);W.dungeonList:SetHeight(324)
    E.wheel(W.dungeonList,L.goInstances)
    for i = 1, INSTANCE_PAGE do
        local b = S.button(W.dungeonList, "", 190, function(self) E.dismissMenu();chosen, encounter, page = self.place.key, nil, 1; refresh() end)
        b:SetPoint("TOPLEFT", W.dungeonList, "TOPLEFT", 0, -((i - 1) * 36))
        E.wheel(b,L.goInstances)
        W.instances[i] = b
    end
    W.status = U.text(f, "", 210, 92, 450)
    W.list=CreateFrame("Frame",nil,f)
    W.list:SetPoint("TOPLEFT",f,"TOPLEFT",210,-120);W.list:SetWidth(450);W.list:SetHeight(371)
    E.wheel(W.list,L.go)
    for i = 1, PAGE do
        local row = E.row(W.list, 0, (i-1)*53, 450, i)
        E.wheel(row.frame,L.go)
        row.frame:SetScript("OnEnter", function(self)
            row.bg:SetVertexColor(1.3,1.3,1.3)
            local r = row.result
            if not r then return end
            if GameTooltip and GameTooltip.SetHyperlink then
                pcall(function()
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. r.itemID)
                    GameTooltip:AddLine(r.instanceName .. " — " .. r.who, 1, 0.82, 0, true)
                    if r.difficulty ~= "" then GameTooltip:AddLine(r.difficulty, 1, 1, 1) end
                    GameTooltip:Show()
                    if GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
                end)
            else U.tip(self, r.item.name, { r.instanceName, "Source: " .. r.who, r.difficulty, "Data: " .. r.provider }) end
        end)
        row.frame:SetScript("OnLeave", function() local tint=row.selected and 1.15 or 1;row.bg:SetVertexColor(tint,tint,tint);U.hideTip() end)
        row.choose=function(auto)
            if auto~=true then E.dismissMenu() end
            local r = row.result
            if not r or not W.details then return end
            selectedKey=resultKey(r)
            E.select(W.rows, row)
            W.setDetails(r.item.name .. " (item " .. r.itemID .. ")\n\nEquipment: " .. r.item.info.slot
                .. "\nItem level: " .. tostring(r.item.info.level or "unknown")
                .. "\nRequired level: " .. tostring(r.item.info.required or "unknown")
                .. "\n\nInstance: " .. r.instanceName
                .. "\nSource: " .. r.who .. (r.difficulty ~= "" and ("\nDifficulty: " .. r.difficulty) or "")
                .. "\nCatalogue: " .. r.provider .. "\n\nDrop chance is not supplied by this browser."
                .. "\nEncounter groups such as Trash refer to a shared loot table, not a specific boss."
                .. (r.provider == "QuestieDB" and "\nQuestieDB lists known sources only; this is not a complete instance loot table." or ""))
        end
        row.frame:SetScript("OnClick",row.choose)
        W.rows[i] = row
    end
    local function pager(label, x, fn)
        local b = S.button(f, label, 90, fn); b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -500); return b
    end
    W.instancePrev = pager("Previous", 0, function() L.goInstances(-1) end)
    W.instanceNext = pager("Next", 100, function() L.goInstances(1) end)
    W.prev = pager("Previous", 210, function() L.go(-1) end)
    W.next = pager("Next", 310, function() L.go(1) end)
    W.reload = pager("Refresh data", 570, function() L.scan() end)
    W.note = U.text(f, "", 0, 536, 660)
    W.details, W.detailsText, W.setDetails = E.details(f, 684, 348, "Drop source")
    E.navigation(W.search,W.rows,L.go)
    f.clear=function()
        query,chosen,encounter,instanceQuery="",nil,nil,"";page,instancePage=1,1
        W.search:SetText("");W.search.cancel();W.instanceSearch:SetText("");W.instanceSearch.cancel();refresh()
    end
    f.refresh = function() page=1; refresh() end
    f.suspend = function()
        if loading or queueAt <= #itemQueue then generation = generation + 1; loading, ready = false, false end
    end
    f:SetScript("OnHide", f.suspend)
    return true
end

function L.open(text)
    if not ns.db.enabled then ns.print("switch Quest Sharing on first (/qs on)"); return false end
    if not build() then return false end
    if text and text ~= "" then query, chosen, encounter, page = text, nil, nil, 1; W.search:SetText(text);W.search.cancel() end
    E.show("dungeons")
    for _,box in ipairs({W.search,W.instanceSearch}) do if box.dirty then box.flush() end end
    if not ready and not loading then L.scan()
    else
        refresh()
        if not loading then
            itemQueue, queueAt = {}, 1
            for id, cached in pairs(items) do if not cached.cached then itemQueue[#itemQueue + 1] = id end end
            if #itemQueue > 0 then generation = generation + 1; pumpNames(generation) end
        end
    end
    return true
end

function L.close() if W then E.close("dungeons") end end
function L._window() return W end
function L._results() return results end
function L._state() return ready, loading, source, #index end
ns.on("GET_ITEM_INFO_RECEIVED", function(_, id) if shown() and items[id] then readItem(id); schedule() end end)
ns.on("PLAYER_REGEN_ENABLED", function() if shown() and deferredAtlas and not loading then L.scan() end end)
