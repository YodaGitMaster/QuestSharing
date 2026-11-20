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
local focusTarget
-- L.bossesOf: a scan it started keeps running while the loot window is hidden; its callers wait in bossWaiters.
local background, bossWaiters, flushBosses = false, {}, nil
-- a cancelled background scan (L.purge, or a new L.scan generation) answers its waiting bossesOf callers now
local function cancelBosses(reason)
    background = false
    local list = bossWaiters; bossWaiters = {}
    for _, w in ipairs(list) do pcall(w.done, {}, nil, reason) end
end
-- Memory: the loot catalogue is read once and kept for the session. Hiding the window pauses a half-read scan or item
-- detail load; resumeLoot continues it on reopen. Purge (ns.dataWork.purge) frees it all.
local resumeLoot
local function resultKey(r) return r.key end
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

local function instance(key, name, instanceID)
    if not instances[key] then instances[key] = { key = key, name = name, count = 0, instanceID = instanceID } end
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

local function sourceLess(a,b)
    if a.instanceName~=b.instanceName then return a.instanceName<b.instanceName end
    if a.instanceKey~=b.instanceKey then return a.instanceKey<b.instanceKey end
    if a.who~=b.who then return a.who<b.who end
    if a.difficulty~=b.difficulty then return a.difficulty<b.difficulty end
    if a.itemID~=b.itemID then return a.itemID<b.itemID end
    return a.provider<b.provider
end

local function suppliers(r)
    local list,seen={},{}
    for _,s in ipairs(r.sources) do
        local key=table.concat({s.instanceKey,s.who,s.provider},"\031")
        local entry=seen[key]
        if not entry then
            entry={who=s.who,instanceName=s.instanceName,provider=s.provider,modes={},ids={},seenModes={},seenIDs={}}
            list[#list+1]=entry;seen[key]=entry
        end
        if s.difficulty~="" and not entry.seenModes[s.difficulty] then
            entry.modes[#entry.modes+1]=s.difficulty;entry.seenModes[s.difficulty]=true
        end
        if not entry.seenIDs[s.itemID] then entry.ids[#entry.ids+1]=s.itemID;entry.seenIDs[s.itemID]=true end
    end
    for _,entry in ipairs(list) do
        table.sort(entry.modes);table.sort(entry.ids)
        entry.label=entry.who.." — "..entry.instanceName..(#entry.modes>0 and (" · "..table.concat(entry.modes,", ")) or "")
    end
    return list
end

local function sourceSummary(r)
    local names,seen,places,placeCount={},{},{},0
    for _,s in ipairs(r.suppliers) do
        if not seen[s.who] then names[#names+1]=s.who;seen[s.who]=true end
        if not places[s.instanceName] then places[s.instanceName]=true;placeCount=placeCount+1 end
    end
    local total=#names
    while #names>3 do table.remove(names) end
    return table.concat(names,", ")..(total>3 and (" +"..(total-3).." more") or "")
        .." — "..(placeCount>1 and (placeCount.." dungeons") or r.instanceName)
        ..(#r.suppliers>1 and (" · "..#r.suppliers.." sources") or
            (#r.suppliers[1].modes>0 and (" · "..table.concat(r.suppliers[1].modes,", ")) or ""))
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
    results=E.groupItems(results,function(r) return r.item.name end,function(r) return r.item.info end,sourceLess)
    for _,r in ipairs(results) do r.suppliers=suppliers(r) end
    E.sortResults(results,function(r) return r.item.info end,function(r) return r.item.name end,sourceLess)
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

local function currentDungeon(text)
    local name,kind,id
    if type(GetInstanceInfo)=="function" then
        -- optionalUI.call deliberately returns only three values; instanceID is the eighth.
        local ok,n,k,_,_,_,_,_,instanceID=pcall(GetInstanceInfo)
        if ok then name,kind,id=clean(n),k,instanceID end
    end
    local inside,instanceType=U.call(IsInInstance)
    if inside==false or (kind or instanceType)~="party" then return end
    return {name=name or clean(U.call(GetRealZoneText)),subzone=clean(U.call(GetSubZoneText)),id=positive(id) and id or nil,text=text}
end

local function focusCurrentDungeon()
    local target=focusTarget
    if not target then return end
    focusTarget=nil
    if W.search.dirty or W.instanceSearch.dirty then return end
    local best,score,tied=nil,0,false
    for _,place in pairs(instances) do
        local sameID=target.id and place.instanceID==target.id
        local sameName=target.name and place.name==target.name
        local sameSubzone=target.subzone and place.name==target.subzone
        if target.subzone and place.subzones and place.subzones[target.subzone] then sameSubzone=true end
        local compatible=not target.id or not place.instanceID or sameID
        local rank=compatible and ((sameID and 100 or 0)+(sameName and 10 or 0)+(sameSubzone and 20 or 0)) or 0
        if rank>score then best,score,tied=place,rank,false elseif rank>0 and rank==score then tied=true end
    end
    -- A shared map/instance ID can cover several wings; never choose an arbitrary one.
    if not best or tied then return end
    chosen,encounter,query,instanceQuery,page,selectedKey=best.key,nil,target.text or "","",1,nil
    W.search:SetText(query);W.search.cancel();W.instanceSearch:SetText("");W.instanceSearch.cancel()
    for i,place in ipairs(L.instances()) do if place.key==chosen then instancePage=math.ceil(i/INSTANCE_PAGE);break end end
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
    if token ~= generation then return end
    if not shown() then resumeLoot = function() pumpNames(token) end; return end
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
    [796]=true,[722]=true,[1337]=true,[1176]=true,[2100]=true,[1477]=true,[1584]=true,[1583]=true,[2557]=true,[2057]=true,[2017]=true,
    [16611]=true,[16732]=true,[3002]=true,
    -- Forever instance areas (QuestieDB AreaTable 1.60.1): City of Dalaran, The Hall of Thanes, Manor Mistmantle
    [16544]=true,[16919]=true,[17191]=true,
    -- the other new Forever dungeons (Wowhead "Dungeons Overview for Forever"): The Drowned City, Krol'dok Stronghold,
    -- Alcaz Prison, Blackmaw Hold, The Shaper's Terrace
    [16550]=true,[16842]=true,[16620]=true,[16554]=true,[16667]=true }
-- Forever sub-areas of an instance (NPCs spawn there) -> the instance itself.
local subAreas = { [16558]=16544,[16559]=16544,[16560]=16544,[16562]=16544,
    [16612]=16611,[16614]=16611,[16615]=16611,[16617]=16611,
    [16877]=16732,[16878]=16732,[16879]=16732,[16880]=16732,
    [17803]=1584,[17804]=1583,
    [16985]=16667,[17780]=16842 } -- QuestieDB's ids for The Shaper's Terrace and Krol'dok Stronghold
-- Raids, battlegrounds and other non-dungeon instances in QuestieDB's list: never "dungeon quests".
local notDungeon = { [1977]=true,[2159]=true,[2257]=true,[2597]=true,[2677]=true,[2717]=true,[2917]=true,[2918]=true,[3277]=true,
    [3358]=true,[3428]=true,[3429]=true,[3456]=true,[3457]=true,[3606]=true,[5861]=true,[16394]=true,[16603]=true,[16653]=true }
local alias
-- The dungeon an area belongs to (its canonical area id), or nil. QuestieDB's instance list adds every 5-player
-- instance and its alternative ids (Uldaman's quests use 1517, Gnomeregan's 133, Dire Maul's wings 10022-10027).
function L.dungeonOf(area)
    area = tonumber(area)
    if not area then return nil end
    if dungeonAreas[area] then return area end
    if subAreas[area] then return subAreas[area] end
    if not alias then
        local list = ns.questie and ns.questie.dungeonList and ns.questie.dungeonList()
        if type(list) == "table" then
            alias = {}
            for key, entry in pairs(list) do
                key = tonumber(key)
                if key and not notDungeon[key] and type(entry) == "table" then
                    local canonical = subAreas[key] or key
                    alias[key] = alias[key] or canonical
                    for _, alt in ipairs(type(entry[2]) == "table" and entry[2] or {}) do
                        alt = tonumber(alt)
                        if alt and not notDungeon[alt] and not dungeonAreas[alt] then alias[alt] = alias[alt] or canonical end
                    end
                end
            end
        end
    end
    return alias and alias[area] or nil
end
function L.isDungeonArea(area) return L.dungeonOf(area) ~= nil end
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
                    -- Compatible Dire Maul tables omit InstanceID but retain its verified area ID.
                    local place = instance(moduleName .. ":" .. tostring(key), name, content.InstanceID or (content.MapID==2557 and 429 or nil))
                    place.subzones={}
                    for _,id in ipairs(type(content.SubAreaIDs)=="table" and content.SubAreaIDs or {}) do
                        local zone=clean(U.call(C_Map and C_Map.GetAreaInfo,id) or U.call(GetAreaInfo,id))
                        if zone then place.subzones[zone]=true end
                    end
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

-- full: read the whole item catalogue again (Refresh data); otherwise the IDs saved by the last full QuestieDB scan.
function L.scan(full)
    if loading then cancelBosses("The drop scan was restarted. Open the Bosses tab again.") end
    if not background then E.dismissMenu() end -- a bossesOf background scan leaves the user's menu alone
    generation = generation + 1
    local token = generation
    index, results, instances, items, seen, itemQueue = {}, {}, {}, {}, {}, {}
    queueAt, page, instancePage, progress, skipped, unresolved = 1, 1, 1, 0, 0, 0
    ready, loading, source = false, true, nil
    local jobs = atlasJobs()
    deferredAtlas = not jobs and atlas() and U.call(InCombatLockdown) and true or false
    if not jobs then loadAtlas(); jobs = atlasJobs() end
    local ids, saved
    local found = {} -- item IDs that gave at least one source (saved after a full QuestieDB scan)
    if jobs then
        source, note = "AtlasLoot", "Classic and Forever dungeon equipment from AtlasLoot. Raids and world bosses excluded."
    else
        local db = type(ItemDB) == "table" and type(ItemDB.GetAllIds) == "function" and ItemDB
            or (type(LibQuestieDB) == "table" and LibQuestieDB.Item)
        saved = db and full ~= true and ns.dataWork.saved("dungeonLoot")
        ids = saved or (db and U.call(db.GetAllIds))
        if type(ids) ~= "table" then
            loading = false
            note = "Install compatible AtlasLoot (with its dungeons and raids loot), or install or update QuestieDB for some drop sources (see /qs questie)."
            if atlas() and U.call(InCombatLockdown) then note = "Leave combat to load AtlasLoot's dungeon catalogue, then Refresh data." end
            if paint then paint() end
            return false
        end
        source, note = "QuestieDB", "Partial QuestieDB sources for known Classic/Forever dungeons; AtlasLoot supplies fuller loot tables."
        if deferredAtlas then note = note .. " AtlasLoot will be retried after combat." end
    end
    local jobAt, rowAt, rows, mode, cache = 1, 1, nil, nil, {}
    local function step()
        if token ~= generation then return end
        if not shown() and not background then resumeLoot = step; return end
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
                            for _, s in ipairs(questieSources(kind, from, cache)) do add(id, s.place, s.who, "", source, s.id, s.kind); found[id] = true end
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
            if flushBosses then flushBosses() end
            if not jobs and not saved then ns.dataWork.save("dungeonLoot", "", ns.dataWork.sortedKeys(found)) end
            if chosen and not instances[chosen] then chosen, encounter = nil, nil end
            focusCurrentDungeon()
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
        -- gold marks the chosen dungeon, as in the dropdowns ("> " there is the keyboard cursor)
        if place then b:SetLabel(chosen == place.key and (S.GOLD .. place.name .. "|r") or place.name); b:Show() else b:Hide() end
    end
    page = math.max(1, math.min(page, math.max(1, math.ceil(#results / PAGE))))
    local title = chosen and instances[chosen] and instances[chosen].name or "All dungeons"
    W.selection:SetText(S.GOLD .. title .. "|r")
    W.selection:SetWordWrap(false)
    W.boss.refresh()
    W.status:SetText(loading and ("Reading " .. tostring(source or "loot") .. " tables: " .. progress)
        or (not source and note ~= "" and note) -- no loot catalogue at all: say what to install, not "no matches"
        or E.pageStatus((page-1)*PAGE+1,PAGE,#results))
    E.pageButtons(W.prev,W.next,#results,page,PAGE)
    E.pageButtons(W.instancePrev,W.instanceNext,#places,instancePage,INSTANCE_PAGE)
    W.note:SetText(note .. ((skipped > 0 and ns.logging()) and (" " .. skipped .. (skipped == 1 and " table could not be read" or " tables could not be read") .. " (debug).") or "")
        .. (queueAt <= #itemQueue and (" Loading item details " .. (queueAt - 1) .. "/" .. #itemQueue .. ".")
            or (unresolved > 0 and (" " .. unresolved .. " items await equipment details and remain hidden.") or "")))
    for i, row in ipairs(W.rows) do
        local r = results[(page - 1) * PAGE + i]
        row.result = r
        if r then
            local req = r.item.info.required
            E.paintRow(row, r.item.info, r.item.name .. " · iLvl " .. tostring(r.item.info.level or "?")
                .. ((type(req) ~= "number" or req > 1) and (" · req " .. tostring(req or "?")) or ""),
                sourceSummary(r))
            row.frame:Show()
        else row.frame:Hide() end
    end
    if not E.focusRows(W.rows,selectedKey,resultKey) then
        selectedKey=nil
        W.setDetails((loading or unresolved>0) and "Loading dungeon equipment details… Eligible blue+ drops appear as the game supplies their data." or
            (#index==0 and note) or (E.RARE_ONLY.."; many dungeon drops are green.\n\nA search, slot, level or stat filter can also hide drops: try Clear filters, another dungeon, or a broader search."))
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
        focusTarget=nil
        instanceQuery=text;instancePage=1;paint()
    end)
    W.search,W.clearSearch=E.searchBox(f,"Search item, ID, boss or dungeon",210,0,450,"dungeons",function(text)
        focusTarget=nil
        query=text;page=1;refresh()
    end)
    local all = E.button(f, "All dungeons", 190, function() E.dismissMenu();focusTarget=nil;chosen, encounter, page = nil, nil, 1; refresh() end)
    W.all=all
    all:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -54)
    W.selection = E.text(f, "All dungeons", 0, 87, 190)
    W.boss=E.dropdown(f,"Source",210,54,450,function()
        local list={"All encounters"};for _,who in ipairs(bosses()) do list[#list+1]=who end;return list
    end,function() return encounter or "All encounters" end,function(value)
        focusTarget=nil
        encounter=value~="All encounters" and value or nil;page=1;refresh()
    end)
    W.instanceStatus = E.text(f, "", 0, 112, 190)
    W.dungeonList=CreateFrame("Frame",nil,f)
    W.dungeonList:SetPoint("TOPLEFT",f,"TOPLEFT",0,-145);W.dungeonList:SetWidth(190);W.dungeonList:SetHeight(324)
    E.wheel(W.dungeonList,L.goInstances)
    for i = 1, INSTANCE_PAGE do
        local b = E.listButton(W.dungeonList, "", 190, function(self) E.dismissMenu();focusTarget=nil;chosen, encounter, page = self.place.key, nil, 1; refresh() end)
        b:SetPoint("TOPLEFT", W.dungeonList, "TOPLEFT", 0, -((i - 1) * 36))
        E.wheel(b,L.goInstances)
        W.instances[i] = b
    end
    W.status = E.text(f, "", 210, 92, 450)
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
                    for i=1,math.min(6,#r.suppliers) do GameTooltip:AddLine(r.suppliers[i].label, 1, 0.82, 0, true) end
                    if #r.suppliers>6 then GameTooltip:AddLine("+"..(#r.suppliers-6).." more sources; click for all.",1,1,1) end
                    if #r.itemIDs>1 then GameTooltip:AddLine(#r.itemIDs.." item versions share this name; click for details.",1,1,1,true) end
                    GameTooltip:Show()
                    if GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
                end)
            else
                local lines={}
                for i=1,math.min(6,#r.suppliers) do lines[#lines+1]=r.suppliers[i].label end
                if #r.suppliers>6 then lines[#lines+1]="+"..(#r.suppliers-6).." more sources; click for all." end
                U.tip(self,r.item.name,lines)
            end
        end)
        row.frame:SetScript("OnLeave", function() local tint=row.selected and 1.15 or 1;row.bg:SetVertexColor(tint,tint,tint);U.hideTip() end)
        row.choose=function(auto)
            if auto~=true then E.dismissMenu() end
            local r = row.result
            if not r or not W.details then return end
            selectedKey=resultKey(r)
            E.select(W.rows, row)
            local lines=E.versionLines(r,function(v) return v.item.info end)
            lines[#lines+1]="\nSources ("..#r.suppliers.."):"
            for _,s in ipairs(r.suppliers) do
                lines[#lines+1]="\nInstance: "..s.instanceName.."\nSource: "..s.who
                    ..(#s.modes>0 and ("\nDifficulty: "..table.concat(s.modes,", ")) or "")
                    ..(#r.itemIDs>1 and ("\nItems: "..table.concat(s.ids,", ")) or "").."\nCatalogue: "..s.provider
            end
            W.setDetails(r.item.name .. " (item " .. r.itemID .. ")\n\nEquipment: " .. r.item.info.slot
                .. "\nItem level: " .. tostring(r.item.info.level or "unknown")
                .. "\nRequired level: " .. tostring(r.item.info.required or "unknown")
                .. "\n\n"..table.concat(lines,"\n").."\n\nDrop chances are not shown in the Adventurer's Journal."
                .. "\nEncounter groups such as Trash refer to a shared loot table, not a specific boss."
                .. (r.provider == "QuestieDB" and "\nQuestieDB lists known sources only; this is not a complete instance loot table." or ""))
        end
        row.frame:SetScript("OnClick",row.choose)
        W.rows[i] = row
    end
    local function pager(label, x, fn)
        local b = E.button(f, label, 90, fn); b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -500); return b
    end
    W.instancePrev = pager("Previous", 0, function() L.goInstances(-1) end)
    W.instanceNext = pager("Next", 100, function() L.goInstances(1) end)
    W.prev = pager("Previous", 210, function() L.go(-1) end)
    W.next = pager("Next", 310, function() L.go(1) end)
    W.reload = pager("Refresh data", 570, function() L.scan(true) end)
    W.note = E.text(f, "", 0, 536, 660)
    W.details, W.detailsText, W.setDetails = E.details(f, 684, 348, "Drop sources")
    E.navigation(W.search,W.rows,L.go)
    f.clear=function()
        focusTarget=nil
        query,chosen,encounter,instanceQuery="",nil,nil,"";page,instancePage=1,1
        W.search:SetText("");W.search.cancel();W.instanceSearch:SetText("");W.instanceSearch.cancel();refresh()
    end
    f.refresh = function() page=1; refresh() end
    f.suspend = function() focusTarget=nil end -- a running scan pauses by itself while hidden (resumeLoot)
    f:SetScript("OnHide", f.suspend)
    return true
end

function L.open(text)
    if not ns.db.enabled then ns.print("switch Quest Sharing on first (/qs on)"); return false end
    if not build() then return false end
    if text and text ~= "" then query, chosen, encounter, page = text, nil, nil, 1; W.search:SetText(text);W.search.cancel() end
    E.show("dungeons")
    for _,box in ipairs({W.search,W.instanceSearch}) do if box.dirty then box.flush() end end
    focusTarget=currentDungeon(text and text~="" and text or nil)
    if not ready and not loading then L.scan()
    elseif resumeLoot then
        local run = resumeLoot; resumeLoot = nil
        if ready then focusCurrentDungeon() end
        refresh(); run()
    else
        if ready then focusCurrentDungeon() end
        refresh()
        if not loading then
            itemQueue, queueAt = {}, 1
            for id, cached in pairs(items) do if not cached.cached then itemQueue[#itemQueue + 1] = id end end
            if #itemQueue > 0 then generation = generation + 1; pumpNames(generation) end
        end
    end
    return true
end

-- Dungeon Journal "Bosses & drops": the bosses of one dungeon in encounter order with their drop item IDs.
-- AtlasLoot is read directly (one dungeon's tables, synchronous, encounter order kept); without it the QuestieDB
-- scan above (L.scan) is used and finished in the background. Result: list, source, reason (see the contract).
local function plainName(s)
    s = string.lower(clean(s) or "")
    s = string.gsub(s, "^the ", "")
    return (string.gsub(s, "[^%w]", ""))
end
local function bossLevel(n) n = tonumber(n); return n and n > 0 and n < 999 and math.floor(n) or nil end
local function firstNumber(v)
    while type(v) == "table" do v = v[1] end
    return positive(v) and v or nil
end

local function atlasBosses(dungeonName, area)
    local a = atlas()
    local db = type(a) == "table" and a.ItemDB
    local storage = type(db) == "table" and db.Storage
    if type(storage) ~= "table" or type(db.GetItemTable) ~= "function" then return nil end
    local want = plainName(dungeonName)
    for moduleName, module in pairs(storage) do
        if type(moduleName) == "string" and string.find(moduleName, "DungeonsAndRaids", 1, true) and type(module) == "table" then
            for key, content in pairs(module) do
                if type(content) == "table" and type(content.items) == "table" and standardDungeon(content, module, a) then
                    local name = clean(content.name) or clean(U.call(content.GetName, content, true))
                    local map = tonumber(content.MapID or content.AreaID)
                    if (want ~= "" and plainName(name) == want) or (area and map and (map == area or L.dungeonOf(map) == area)) then
                        local list = {}
                        for bossID, boss in ipairs(content.items) do
                            if type(boss) == "table" and not boss.IgnoreAsSource and not boss.ExtraList then
                                local who = clean(boss.name) or clean(U.call(content.GetNameForItemTable, content, bossID, true))
                                    or (positive(boss.npcID) and clean(field("npc", boss.npcID, "name"))) or ("Encounter " .. bossID)
                                local original = boss
                                if type(boss.link) == "table" then
                                    local target = storage[boss.link[1]]
                                    target = target and target[boss.link[2]]
                                    original = target and target.items and target.items[boss.link[3]] or nil
                                end
                                local diffs, ids, seenIDs = {}, {}, {}
                                for diff in pairs(original or {}) do if type(diff) == "number" and diff > 0 then diffs[#diffs + 1] = diff end end
                                table.sort(diffs)
                                for _, diff in ipairs(diffs) do
                                    local rows, format = U.call(db.GetItemTable, db, moduleName, key, bossID, diff)
                                    if type(rows) == "table" and not (type(format) == "table" and format[1] and format[1] ~= "Item") then
                                        for _, r in ipairs(rows) do
                                            local id = type(r) == "table" and r[2]
                                            if positive(id) and not seenIDs[id] then seenIDs[id] = true; ids[#ids + 1] = id end
                                        end
                                    end
                                end
                                local npcID = firstNumber(boss.npcID)
                                if #ids > 0 or npcID then list[#list + 1] = { name = who, npcID = npcID,
                                    displayID = firstNumber(boss.DisplayIDs) or firstNumber(boss.displayID),
                                    level = bossLevel(boss.Level) or (npcID and bossLevel(field("npc", npcID, "maxLevel"))),
                                    items = ids } end
                            end
                        end
                        return list
                    end
                end
            end
        end
    end
    return false -- catalogue readable, but no table for this dungeon
end

local function questieBosses(dungeonName, area)
    local want, byNpc, list = plainName(dungeonName), {}, {}
    for _, r in ipairs(index) do
        if r.kind == "npc" and (plainName(r.instanceName) == want or (area and r.instanceKey == "area:" .. tostring(area))) then
            local boss = byNpc[r.sourceID]
            if not boss then
                local npcID = tonumber((string.match(tostring(r.sourceID), "^npc:(%d+)$")))
                boss = { name = r.who, npcID = npcID, level = npcID and bossLevel(field("npc", npcID, "maxLevel")), items = {}, seen = {} }
                byNpc[r.sourceID] = boss; list[#list + 1] = boss
            end
            if not boss.seen[r.itemID] then boss.seen[r.itemID] = true; boss.items[#boss.items + 1] = r.itemID end
        end
    end
    -- QuestieDB has no encounter order: lowest level first, then by name.
    table.sort(list, function(x, y)
        if (x.level or 0) ~= (y.level or 0) then return (x.level or 0) < (y.level or 0) end
        return x.name < y.name
    end)
    for _, boss in ipairs(list) do boss.seen = nil; table.sort(boss.items) end
    return list
end

flushBosses = function()
    background = false
    local list = bossWaiters; bossWaiters = {}
    for _, w in ipairs(list) do
        local bosses = source == "QuestieDB" and questieBosses(w.name, w.area)
            or source == "AtlasLoot" and atlasBosses(w.name, w.area) or {}
        local ok, err = pcall(w.done, bosses, source, #bosses == 0 and "No drops known for " .. tostring(w.name) .. "." or nil)
        if not ok and ns.logging and ns.logging() then ns.print("bosses: " .. tostring(err)) end
    end
end

-- dungeonName: the area name; done(list, source, reason) is called exactly once (now, or after the scan);
-- area (optional) also matches AtlasLoot's MapID. Returns list, source, reason now, or nil, nil, "loading".
function L.bossesOf(dungeonName, done, area)
    area = tonumber(area)
    local function reply(list, src, reason)
        if done then pcall(done, list, src, reason) end
        return list, src, reason
    end
    if atlas() then
        local list = atlasBosses(dungeonName, area)
        if list == nil then loadAtlas(); list = atlasBosses(dungeonName, area) end
        if list == false then return reply({}, "AtlasLoot", "AtlasLoot has no table for " .. tostring(dungeonName) .. ".") end
        if list then return reply(list, "AtlasLoot", #list == 0 and "AtlasLoot lists no encounters here." or nil) end
    end
    if ready and source == "QuestieDB" then
        local list = questieBosses(dungeonName, area)
        return reply(list, source, #list == 0 and "No drops known for " .. tostring(dungeonName) .. "." or nil)
    end
    -- got: our own answer, when the scan finishes inside the first synchronous step()
    local got
    bossWaiters[#bossWaiters + 1] = { name = dungeonName, area = area, done = function(list, src, reason)
        got = { list, src, reason }
        if done then done(list, src, reason) end
    end }
    background = true
    if loading then
        if resumeLoot then local run = resumeLoot; resumeLoot = nil; run() end
        if got then return got[1], got[2], got[3] end
        return nil, nil, "loading"
    end
    if not L.scan() then
        cancelBosses(note)
        return {}, nil, note
    end
    if got then return got[1], got[2], got[3] end
    return nil, nil, "loading" -- done is called by flushBosses when the scan finishes
end

function L.close() if W then E.close("dungeons") end end
function L.purge()
    ns.dataWork.forget("dungeonLoot")
    cancelBosses("The drop data was cleared. Open the Bosses tab again.")
    generation = generation + 1; resumeLoot = nil
    index, results, instances, items, itemQueue = {}, {}, {}, {}, {}
    queueAt, progress, skipped, unresolved, ready, loading = 1, 0, 0, 0, false, false
    if shown() then L.scan() end
end
ns.dataWork.onPurge("Dungeon loot", L.purge)
function L._window() return W end
function L._results() return results end
function L._state() return ready, loading, source, #index end
ns.on("GET_ITEM_INFO_RECEIVED", function(_, id) if shown() and items[id] then readItem(id); schedule() end end)
ns.on("PLAYER_REGEN_ENABLED", function() if shown() and deferredAtlas and not loading then L.scan() end end)
