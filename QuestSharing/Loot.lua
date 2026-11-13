-- On-demand instance loot search. AtlasLoot supplies encounter tables; QuestieDB is a labelled partial fallback.
-- Provider tables are never edited here. Names are requested from the game in small batches while this window is open.
local ADDON, ns = ...
local L, U, S, Q = {}, ns.optionalUI, ns.style, ns.questie
ns.loot = L
local W, index, results, instances, items = nil, {}, {}, {}, {}
local generation, loading, ready, pending = 0, false, false, false
local source, note, skipped, progress = nil, "Open to load instance drops.", 0, 0
local chosen, encounter, query, instanceQuery = nil, nil, "", ""
local itemQueue, queueAt, page, instancePage = {}, 1, 1, 1
local deferredAtlas = false
local unresolved = 0
local PAGE, INSTANCE_PAGE = 8, 9
local paint, refresh
local function clean(s)
    return type(s) == "string" and (string.gsub(string.gsub(s, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")) or nil
end
local function positive(n) return type(n) == "number" and n > 0 and n < math.huge and n % 1 == 0 end
local function field(kind, id, key) return Q.get(kind, id, key) end
local function shown() return W and W.frame:IsShown() and ns.db.enabled end
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
        if (not chosen or chosen == r.instanceKey) and (not encounter or encounter == r.who)
            and (needle == "" or string.find(haystack, needle, 1, true)) then results[#results + 1] = r end
    end
    table.sort(results, function(a, b)
        if a.instanceName ~= b.instanceName then return a.instanceName < b.instanceName end
        if a.who ~= b.who then return a.who < b.who end
        if a.item.name ~= b.item.name then return a.item.name < b.item.name end
        if a.itemID ~= b.itemID then return a.itemID < b.itemID end
        return a.difficulty < b.difficulty
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
        if (not chosen or r.instanceKey == chosen) and not set[r.who] then list[#list + 1] = r.who; set[r.who] = true end
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
                if type(content) == "table" and positive(content.InstanceID) and type(content.items) == "table" then
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
                                original = target and target.items and target.items[boss.link[3]] or boss
                            end
                            for diff, rows in pairs(original) do
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
        if inside then
            local place = instance("area:" .. tostring(area), areaName(area))
            found[#found + 1] = { place = place, who = clean(field(kind, id, "name")) or (kind .. " " .. id),
                id = key, kind = kind }
        end
    end
    cache[key] = found
    return found
end

function L.scan()
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
        source, note = "AtlasLoot", "Encounter loot from the installed AtlasLoot catalogue."
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
        source, note = "QuestieDB", "Partial QuestieDB drop sources; install compatible AtlasLoot for encounter loot tables."
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
    W.instanceStatus:SetText(#places .. " instances — page " .. instancePage .. "/" .. math.max(1, math.ceil(#places / INSTANCE_PAGE)))
    for i, b in ipairs(W.instances) do
        local place = places[(instancePage - 1) * INSTANCE_PAGE + i]
        b.place = place
        if place then b:SetLabel((chosen == place.key and "> " or "") .. place.name); b:Show() else b:Hide() end
    end
    page = math.max(1, math.min(page, math.max(1, math.ceil(#results / PAGE))))
    local title = chosen and instances[chosen] and instances[chosen].name or "All instances"
    W.selection:SetText(S.GOLD .. title .. "|r")
    W.boss:SetLabel("Source: " .. (encounter or "All encounters"))
    W.status:SetText(loading and ("Reading " .. tostring(source or "loot") .. " tables: " .. progress)
        or (#results .. " drop sources — page " .. page .. "/" .. math.max(1, math.ceil(#results / PAGE))))
    W.note:SetText(note .. (skipped > 0 and (" " .. skipped .. " tables unavailable or not item lists.") or "")
        .. (queueAt <= #itemQueue and (" Loading item names " .. (queueAt - 1) .. "/" .. #itemQueue .. ".")
            or (unresolved > 0 and (" " .. unresolved .. " item details pending/unavailable; search by ID or source.") or "")))
    for i, row in ipairs(W.rows) do
        local r = results[(page - 1) * PAGE + i]
        row.result = r
        if r then
            row.item:SetText(r.item.name .. (r.item.info and ("  (iLvl " .. tostring(r.item.info.level or "?") .. ")") or ""))
            row.from:SetText(r.instanceName .. " — " .. r.who .. (r.difficulty ~= "" and (" — " .. r.difficulty) or ""))
            row.frame:Show()
        else row.frame:Hide() end
    end
end

refresh = function()
    if not shown() then return end
    L.search(query, chosen, encounter); paint()
end

local function schedule()
    if pending or not shown() then return end
    pending = true
    ns.after(0.2, function() pending = false; refresh() end)
end

local function build()
    if W then return true end
    local f = U.window("QuestSharingLoot", 920, 660, "Instance drops")
    if not f then return false end
    W = { frame = f, instances = {}, rows = {} }
    U.text(f, "Choose an instance or search an item, boss or creature. Hover an item to compare; click for its source.", 24, 32, 870)
    W.instanceSearch = U.box(f, "Find instance (Enter)", 24, 60, 220, "", 100)
    W.instanceSearch:SetScript("OnEnterPressed", function(self) instanceQuery = self:GetText(); instancePage = 1; paint(); self:ClearFocus() end)
    W.search = U.box(f, "Search item, ID, boss or instance (Enter)", 264, 60, 470, "", 100)
    W.search:SetScript("OnEnterPressed", function(self) query = self:GetText(); page = 1; refresh(); self:ClearFocus() end)
    local reload = S.button(f, "Refresh data", 150, function() L.scan() end)
    reload:SetPoint("TOPLEFT", f, "TOPLEFT", 744, -77)
    local all = S.button(f, "All instances", 220, function() chosen, encounter, page = nil, nil, 1; refresh() end)
    all:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -116)
    W.selection = U.text(f, "All instances", 264, 116, 630)
    W.boss = S.button(f, "Source: All encounters", 630, function()
        local list, at = bosses(), 0
        for i, who in ipairs(list) do if who == encounter then at = i end end
        encounter = at < #list and list[at + 1] or nil
        page = 1; refresh()
    end)
    W.boss:SetPoint("TOPLEFT", f, "TOPLEFT", 264, -140)
    W.instanceStatus = U.text(f, "", 24, 149, 220)
    for i = 1, INSTANCE_PAGE do
        local b = S.button(f, "", 220, function(self) chosen, encounter, page = self.place.key, nil, 1; refresh() end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -(177 + (i - 1) * 37))
        W.instances[i] = b
    end
    W.status = U.text(f, "", 264, 169, 630)
    for i = 1, PAGE do
        local row = {}
        row.frame = CreateFrame("Button", nil, f)
        row.frame:SetWidth(630); row.frame:SetHeight(43)
        row.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 264, -(198 + (i - 1) * 47))
        row.item, row.from = U.text(row.frame, "", 2, 1, 626), U.text(row.frame, "", 2, 21, 626)
        if row.item.SetWordWrap then row.item:SetWordWrap(false); row.from:SetWordWrap(false) end
        row.frame:RegisterForClicks("LeftButtonUp")
        row.frame:SetScript("OnEnter", function(self)
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
        row.frame:SetScript("OnLeave", U.hideTip)
        row.frame:SetScript("OnClick", function()
            local r = row.result
            if not r or not W.details then return end
            W.setDetails(r.item.name .. " (item " .. r.itemID .. ")\n\nInstance: " .. r.instanceName
                .. "\nSource: " .. r.who .. (r.difficulty ~= "" and ("\nDifficulty: " .. r.difficulty) or "")
                .. "\nCatalogue: " .. r.provider .. "\n\nDrop chance is not supplied by this browser."
                .. "\nEncounter groups such as Trash refer to a shared loot table, not a specific boss."
                .. (r.provider == "QuestieDB" and "\nQuestieDB lists known sources only; this is not a complete instance loot table." or ""))
            W.details:Show()
        end)
        W.rows[i] = row
    end
    local function pager(label, x, y, fn)
        local b = S.button(f, label, 100, fn); b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y); return b
    end
    W.instancePrev = pager("Previous", 24, 522, function() instancePage = math.max(1, instancePage - 1); paint() end)
    W.instanceNext = pager("Next", 134, 522, function() instancePage = instancePage + 1; paint() end)
    W.prev = pager("Previous", 264, 590, function() page = math.max(1, page - 1); paint() end)
    W.next = pager("Next", 374, 590, function() page = page + 1; paint() end)
    W.note = U.text(f, "", 24, 619, 870)
    W.details = U.window("QuestSharingLootSource", 650, 390, "Item drop source")
    if W.details then W.detailsText, W.setDetails = U.scrollText(W.details, 24, 40, 600, 310) end
    f:SetScript("OnHide", function()
        if loading or queueAt <= #itemQueue then generation = generation + 1; loading, ready = false, false end
        if W.details then W.details:Hide() end
    end)
    return true
end

function L.open(text)
    if not ns.db.enabled then ns.print("switch Quest Sharing on first (/qs on)"); return false end
    if not build() then return false end
    if text and text ~= "" then query, chosen, encounter, page = text, nil, nil, 1; W.search:SetText(text) end
    W.frame:Show()
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

function L.close() if W then W.frame:Hide() end end
function L._window() return W end
function L._results() return results end
function L._state() return ready, loading, source, #index end
ns.on("GET_ITEM_INFO_RECEIVED", function(_, id) if shown() and items[id] then readItem(id); schedule() end end)
ns.on("PLAYER_REGEN_ENABLED", function() if shown() and deferredAtlas and not loading then L.scan() end end)
