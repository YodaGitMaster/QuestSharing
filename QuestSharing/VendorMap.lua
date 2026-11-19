-- Optional QuestieDB vendor lookup on Blizzard's existing world map. Only reads QuestieDB and draws addon-owned pins.
local ADDON, ns = ...
local Q, U, S, Work = ns.questie, ns.optionalUI, ns.style, ns.dataWork
local V = {}
ns.vendorMap = V

local items, vendors, ready, loading = {}, {}, false, false
local itemIDs, npcIDs, itemCursor, npcCursor, itemsReady, mask = nil, nil, 1, 1, false, nil
-- Items are searched, not catalogued: itemWords are the typed words the item scan was made for, items holds only the
-- sellable items whose name has them, and itemRows remembers the vendor links already read (false = none that matter).
local itemWords, itemRows, playerFaction = nil, {}, nil
local wordsByTitle, resolved, hydrated, searchTimer = {}, nil, {}, nil
local generation, currentQuery, currentOnly, currentKind = 0, "", true, nil
local mapUI, hookedScroll, pins, lastRender = nil, nil, {}, nil
-- Typing gets a larger slice; DataWork runs nothing in combat and the jobs pause while the map is hidden.
-- Locations read for earlier keystrokes stay cached, up to SPAWN_CACHE NPCs besides the current matches.
local FOREGROUND_MS, SPAWN_CACHE = 8, 2000
local cached, cachedCount, typed, wantItems, waiting, failed = {}, 0, false, false, nil, nil
local indexToken, indexBudget, scan, progress = 0, nil, nil, nil
local function call(fn, ...) return U.call(fn, ...) end
local function trim(s) return (string.gsub(string.gsub(tostring(s or ""), "^%s+", ""), "%s+$", "")) end
local function lower(s) return string.lower(type(s) == "string" and s or "") end
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
-- Speed: scans call this once per item name with the same query, so the query is split once and the words reused.
local lastQuery, lastWords = nil, {}
local function matchesWords(text, query)
    if query ~= lastQuery then
        lastQuery, lastWords = query, {}
        for word in string.gmatch(lower(query), "%S+") do lastWords[#lastWords + 1] = word end
    end
    local words = lastWords
    if #words == 0 then return false end
    local hay, find = lower(text), string.find
    for i = 1, #words do
        if not find(hay, words[i], 1, true) then return false end
    end
    return true
end

local sellerWords = { vendor = true, vendors = true, seller = true, sellers = true,
    merchant = true, merchants = true }

local roleAliases = {
    skinner = "skinning", miner = "mining", blacksmith = "blacksmithing",
    leatherworker = "leatherworking", herbalist = "herbalism", alchemist = "alchemy",
    engineer = "engineering", enchanter = "enchanting", fisherman = "fishing",
    fisher = "fishing", fishermen = "fishing", tailor = "tailoring", cook = "cooking",
    instructor = "trainer", teacher = "trainer", training = "trainer",
    supplies = "supply", vender = "vendor",
}
local roleForms = {}
for word, canonical in pairs(roleAliases) do
    roleForms[canonical] = roleForms[canonical] or {}
    table.insert(roleForms[canonical], word)
end

local function roleWords(text)
    local out = {}
    for word in string.gmatch(string.gsub(lower(text), "[%p%c]", " "), "%S+") do
        if word ~= "the" and word ~= "of" and word ~= "for" and word ~= "a" and word ~= "an" then
            local singular = word
            if #word >= 5 and string.sub(word, -1) == "s" and string.sub(word, -2) ~= "ss" then
                singular = string.sub(word, 1, -2)
            end
            out[#out + 1] = roleAliases[word] or roleAliases[singular] or singular
        end
    end
    return out
end

-- One insertion, deletion, replacement or adjacent swap; keep short/localized tokens literal.
local function oneTypo(a, b)
    local n, m = #a, #b
    if n < 5 or m < 5 or math.abs(n - m) > 1
        or string.find(a, "[^a-z]") or string.find(b, "[^a-z]") then return false end
    local i = 1
    while i <= n and i <= m and string.sub(a, i, i) == string.sub(b, i, i) do i = i + 1 end
    if n == m then
        if string.sub(a, i + 1) == string.sub(b, i + 1) then return true end
        return i < n and string.sub(a, i, i) == string.sub(b, i + 1, i + 1)
            and string.sub(a, i + 1, i + 1) == string.sub(b, i, i)
            and string.sub(a, i + 2) == string.sub(b, i + 2)
    end
    if n < m then return string.sub(a, i) == string.sub(b, i + 1) end
    return string.sub(a, i + 1) == string.sub(b, i)
end

local function roleMatch(words, query, allowTypo)
    if #query == 0 then return nil end
    local errors = 0
    for _, needle in ipairs(query) do
        local found = false
        for _, word in ipairs(words) do
            if string.find(word, needle, 1, true) then found = true; break end
        end
        if not found and allowTypo and errors == 0 then
            for _, word in ipairs(words) do
                local close = oneTypo(word, needle)
                for _, alias in ipairs(roleForms[word] or {}) do
                    if close then break end
                    close = oneTypo(alias, needle)
                end
                if close then found = true; errors = errors + 1; break end
            end
        end
        if not found then return nil end
    end
    return errors
end

local function sellerQuery(query)
    local words, isSellerQuery = {}, false
    for _, word in ipairs(roleWords(query)) do
        if sellerWords[word] or oneTypo(word, "vendor") or oneTypo(word, "seller") or oneTypo(word, "merchant") then
            isSellerQuery = true
        elseif word ~= "all" then words[#words + 1] = word end
    end
    return isSellerQuery, table.concat(words, " ")
end

local function sellerTitle(title)
    for word in string.gmatch(lower(title), "%a+") do
        if sellerWords[word] or word == "goods" or word == "supplies" or word == "store" then return true end
    end
    return false
end

local function vendorMask()
    local db = LibQuestieDB
    if type(db) ~= "table" or call(db.RequireContract, 4) ~= true then return nil end
    local flags = type(db.Enum) == "table" and db.Enum.npcFlags
    local mask = type(flags) == "table" and flags.VENDOR
    if finite(mask) and mask > 0 then return mask end
end

local function metadata(id, linked)
    local row = vendors[id]
    if not row then
        if not Q.npcFriendly(id, playerFaction) then return end -- the other faction's NPCs never get a row
        local title = Q.get("npc", id, "subName")
        local flags = mask and Q.get("npc", id, "npcFlags")
        local flagged = mask and finite(flags) and flags % (2 * mask) >= mask
        if not (linked or flagged or (type(title) == "string" and trim(title) ~= "")) then return end
        title = type(title) == "string" and trim(title) ~= "" and trim(title) or "Vendor"
        wordsByTitle[title] = wordsByTitle[title] or roleWords(title)
        row = { id = id, title = title, roleWords = wordsByTitle[title], isSeller = flagged or sellerTitle(title) }
        vendors[id] = row
    end
    if row and linked then row.isSeller = true end
end

-- Keep only role/name/link metadata; a query reads locations for its matching NPCs later.
-- Saved list (ns.dataWork.saved) "mapSearchNPCs": the NPC IDs that got a role row; later sessions read only those.
-- Items are not saved: their scan reads one name per item and a vendor list only for names with the typed words.
local savedNPCs, savedScope
local function indexRoles()
    if ready then return end
    if not npcIDs then
        playerFaction = Q.me().faction
        -- The cache is account-wide and the list skips the other faction's NPCs, so each faction keeps its own.
        savedScope = playerFaction or "any"
        savedNPCs = Work.saved("mapSearchNPCs", savedScope)
        npcIDs = savedNPCs or (Q and Q.ids and Q.ids("npc")) or {}
        mask = vendorMask()
    end
    while npcIDs[npcCursor] do
        metadata(npcIDs[npcCursor])
        npcCursor = npcCursor + 1
        if npcCursor % 500 == 1 then progress() end
        Work.yield()
    end
    if not savedNPCs then Work.save("mapSearchNPCs", savedScope, Work.sortedKeys(vendors)) end
    ready, npcIDs, savedNPCs = true, nil, nil
end

local function wordsOf(query)
    local out = {}
    for word in string.gmatch(lower(query), "%S+") do out[#out + 1] = word end
    return out
end

-- An item matches when every word is inside its name, so an item scan made for the words `have` holds every item that
-- a scan for `want` would (each have-word sits inside some want-word: typing on). No words = every item.
local function wordsCover(have, want)
    if not have then return false end
    for _, word in ipairs(have) do
        local found = false
        for _, other in ipairs(want) do
            if string.find(other, word, 1, true) then found = true; break end
        end
        if not found then return false end
    end
    return true
end

-- The words the item scan needs for this query, or nil when it needs none. A seller query ("vendor", "general
-- vendor") is answered by the vendor flag and the NPC titles; items matter only for the rest of its words, and for
-- linking every seller when the provider has no vendor flag.
local function scanWords(query)
    local sellers, rest = sellerQuery(query)
    if (sellers or currentKind == "seller") and currentKind ~= "item" then
        local words = wordsOf(rest)
        if #words == 0 and mask then return nil end
        return words
    end
    return wordsOf(query)
end

local function itemsCover(query)
    local want = scanWords(query)
    return want == nil or (itemsReady and wordsCover(itemWords, want))
end

local function beginItemScan(words)
    indexToken = indexToken + 1 -- the job being replaced must not report its stop as a failure
    Work.cancel("vendor-index")
    itemWords, items, itemIDs, itemCursor, itemsReady = words, {}, nil, 1, false
end

local function dropItems()
    indexToken = indexToken + 1
    Work.cancel("vendor-index")
    itemWords, items, itemRows, itemIDs, itemCursor, itemsReady, wantItems, loading = nil, {}, {}, nil, 1, false, false, false
end

-- Names are single reads; the vendor links (a table per item) are read only for the items whose name has the typed words.
local function indexItems()
    if itemsReady then return end
    if not itemIDs then itemIDs = Q and Q.ids and Q.ids("item") or {} end
    local text = table.concat(itemWords, " ")
    while itemIDs[itemCursor] do
        local id = itemIDs[itemCursor]
        local name = Q.get("item", id, "name")
        if type(name) == "string" and (text == "" or matchesWords(name, text)) then
            local row = itemRows[id]
            if row == nil then
                row = false
                local list = Q.get("item", id, "vendors")
                if type(list) == "table" and #list > 0 then
                    local found, seen = { id = id, name = name, key = lower(name), vendorIDs = {} }, {}
                    for _, vendorID in ipairs(list) do
                        if finite(vendorID) and not seen[vendorID] and Q.npcFriendly(vendorID, playerFaction) then
                            seen[vendorID] = true
                            found.vendorIDs[#found.vendorIDs + 1] = vendorID
                            metadata(vendorID, true)
                            Work.checkpoint()
                        end
                    end
                    if #found.vendorIDs > 0 then row = found end
                end
                itemRows[id] = row
            end
            if row then items[#items + 1] = row end
        end
        itemCursor = itemCursor + 1
        if itemCursor % 500 == 1 then progress() end
        Work.yield()
    end
    itemsReady, itemIDs = true, nil
end

-- keep: ids whose cached locations stay (the current matches); nil drops every cached location.
local function dropSpawns(keep)
    for id in pairs(cached) do
        if not (keep and keep[id]) then
            if vendors[id] then vendors[id].spawns = nil end
            cached[id], cachedCount = nil, cachedCount - 1
        end
    end
end

local function readSpawns(id)
    if cached[id] then return end
    vendors[id].spawns = Q.spawnList("npc", id)
    cached[id], cachedCount = true, cachedCount + 1
end

-- A new query: forget its results and pins; cached locations and visible suggestions stay until replaced.
local function clearResults()
    hydrated, resolved, lastRender, waiting, scan = {}, nil, nil, nil, nil
    for _, pin in ipairs(pins) do pin.result = nil; pin:Hide() end
end

local function clearLocations()
    clearResults()
    dropSpawns(nil)
    if mapUI then mapUI.suggestions = {}; mapUI.suggestionBox:Hide() end
end

local function resetIndex()
    generation, indexToken = generation + 1, indexToken + 1
    if searchTimer then ns.cancel(searchTimer); searchTimer = nil end
    Work.cancel("vendor-search"); Work.cancel("vendor-index")
    clearLocations()
    loading, ready, itemsReady, wantItems, typed, failed, indexBudget = false, false, false, false, false, nil, nil
    items, vendors, wordsByTitle, itemWords, itemRows, playerFaction = {}, {}, {}, nil, {}, nil
    npcIDs, itemIDs, npcCursor, itemCursor = nil, nil, 1, 1
end

local function thousands(n)
    local s, k = tostring(n), 1
    while k > 0 do s, k = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2") end
    return s
end

local function progressText()
    -- DataWork runs nothing in combat: say so, instead of a progress line that does not move
    if Work.fighting and Work.fighting() then
        return "Search waits until the fight ends.\nResults appear as soon as you leave combat."
    end
    local line
    if not ready then
        line = npcIDs and ("Reading the NPC list: " .. thousands(npcCursor - 1) .. " / " .. thousands(#npcIDs) .. "…")
            or "Reading the NPC list…"
    elseif waiting == generation and not itemsReady then
        line = itemIDs and ("Searching items: " .. thousands(itemCursor - 1) .. " / " .. thousands(#itemIDs) .. "…")
            or "Searching items…"
    elseif scan then
        line = "Finding locations: " .. thousands(scan.done) .. " / " .. thousands(scan.total) .. " matches…"
    else
        line = "Searching vendor data…"
    end
    return line .. "\nSuggestions appear as soon as matches are found."
end

progress = function()
    if mapUI and currentQuery ~= "" and not resolved and failed ~= generation then
        mapUI.status:SetText(progressText())
    end
end

-- The catalogue index (NPC roles, then items once a query needs them) is one job that keystrokes never cancel. It
-- starts on the first typed character (never on login or a blank map) and runs only while the map shows a query.
local function startIndex(withItems)
    if withItems then wantItems = true end
    local want = wantItems and scanWords(currentQuery) or nil
    if want and not wordsCover(itemWords, want) then beginItemScan(want) end
    if ready and not (want and not itemsReady) then return end
    loading = true
    local budget = typed and FOREGROUND_MS or nil
    if Work.busy("vendor-index") and (indexBudget == budget or not budget) then Work.resume("vendor-index"); return end
    -- Start, or restart with the typing slice: the cursors keep the progress, an interrupted item is read again.
    indexBudget = budget
    local token = indexToken
    Work.start("vendor-index", function()
        indexRoles()
        if wantItems and itemWords then indexItems() end
    end, function()
        return token == indexToken and ns.db.enabled and ns.db.vendorSearch and currentQuery ~= ""
            and WorldMapFrame and call(WorldMapFrame.IsShown, WorldMapFrame)
    end, function(ok)
        if token ~= indexToken then return end
        if ok then V.draw(); return end
        loading, failed = false, generation
        if mapUI then mapUI.status:SetText("Vendor search stopped; try the search again.") end
    end, budget)
end

local function mapInfo(map)
    local info = call(C_Map and C_Map.GetMapInfo, map)
    return type(info) == "table" and info or nil
end

-- Transform a Questie spawn's local 0..1 position through parent maps to the currently shown map.
local function pointOnMap(map, x, y, target)
    if not (map and target and finite(x) and finite(y)) then return nil end
    if map == target then return x, y end
    local id, seen = map, {}
    for _ = 1, 12 do
        if seen[id] then return nil end
        seen[id] = true
        local info = mapInfo(id)
        local parent = info and info.parentMapID
        if not parent or parent == 0 then return nil end
        local fn = C_Map and C_Map.GetMapRectOnMap
        if type(fn) ~= "function" then return nil end
        local ok, x1, x2, y1, y2 = pcall(fn, id, parent)
        if not (ok and finite(x1) and finite(x2) and finite(y1) and finite(y2)) then return nil end
        x, y, id = x1 + x * (x2 - x1), y1 + y * (y2 - y1), parent
        if id == target then return x, y end
    end
end

local function continentPoint(map, x, y)
    local id = map
    local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent
    for _ = 1, 12 do
        local info = mapInfo(id)
        if not info then return nil end
        if continentType and info.mapType == continentType then return id, x, y end
        local parent = info.parentMapID
        if not parent or parent == 0 then return nil end
        local px, py = pointOnMap(id, x, y, parent)
        if not px then return nil end
        id, x, y = parent, px, py
    end
end

V.pointOnMap, V.continentPoint = pointOnMap, continentPoint -- shared with TravelMap.lua

local function zoneName(area)
    local name = call(C_Map and C_Map.GetAreaInfo, area) or (GetAreaInfo and call(GetAreaInfo, area))
    return type(name) == "string" and name or "Unknown zone"
end

local function category(v)
    return type(v.title) == "string" and trim(v.title) ~= "" and trim(v.title) or "Vendor"
end

-- What a suggested NPC title is, for its label: "Trainer: Paladin Trainer", "Vendor: General Goods", "NPC: Innkeeper"
local function titleKind(v)
    for _, word in ipairs(v.roleWords or {}) do if word == "trainer" then return "Trainer: " end end
    return v.isSeller and "Vendor: " or "NPC: "
end

-- One icon per kind of NPC, chosen from its title ("Druid Trainer", "Mining Trainer", "Innkeeper"...). The first
-- matching rule wins: a class trainer shows its class, a profession NPC its tool, the rest a shared look.
local CLASS_WORDS = { druid = "DRUID", hunter = "HUNTER", mage = "MAGE", paladin = "PALADIN", priest = "PRIEST",
    rogue = "ROGUE", shaman = "SHAMAN", warlock = "WARLOCK", warrior = "WARRIOR" }
local ICON_RULES = {
    { "alchem", "Trade_Alchemy" }, { "blacksmith", "Trade_BlackSmithing" }, { "enchant", "Trade_Engraving" },
    { "engineer", "Trade_Engineering" }, { "herbal", "Trade_Herbalism" }, { "leatherwork", "Trade_LeatherWorking" },
    { "mining", "Trade_Mining" }, { "miner", "Trade_Mining" }, { "skinn", "INV_Misc_Pelt_Wolf_01" },
    { "tailor", "Trade_Tailoring" }, { "first aid", "INV_Misc_Bandage_15" }, { "fish", "Trade_Fishing" },
    { "cook", "INV_Misc_Food_15" }, { "chef", "INV_Misc_Food_15" }, -- food and drink vendors keep the bag, so cooking stands out
    { "innkeeper", "INV_Misc_Rune_01" }, { "stable", "Ability_Hunter_BeastCall" }, { "flight", "INV_Misc_Map_01" },
    { "bank", "INV_Misc_Coin_01" }, { "auction", "INV_Misc_Coin_01" }, { "weapon", "INV_Sword_04" },
    { "armor", "INV_Shield_06" }, { "trainer", "INV_Misc_Book_09" },
}
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local iconCache = {}
-- texture path, texcoord table or nil (whole texture)
function V.querying() return currentQuery ~= "" end
function V.iconFor(title)
    local key = lower(title)
    local hit = iconCache[key]
    if not hit then
        hit = { "Interface\\Icons\\INV_Misc_Bag_10" }
        for word, class in pairs(CLASS_WORDS) do
            local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
            if string.find(key, word, 1, true) and coords then hit = { CLASS_SHEET, coords }; break end
        end
        if hit[1] ~= CLASS_SHEET then
            for _, rule in ipairs(ICON_RULES) do
                if string.find(key, rule[1], 1, true) then hit = { "Interface\\Icons\\" .. rule[2] }; break end
            end
        end
        iconCache[key] = hit
    end
    return hit[1], hit[2]
end

local function mappedPoint(spawn, map)
    if not spawn.map or spawn.dungeon or not (finite(spawn.x) and finite(spawn.y))
        or spawn.x < 0 or spawn.x > 100 or spawn.y < 0 or spawn.y > 100 then return nil end
    local x, y = pointOnMap(spawn.map, spawn.x / 100, spawn.y / 100, map)
    if finite(x) and finite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

local function vendorsOnMap(map)
    local out = {}
    for id in pairs(hydrated) do
        local vendor = vendors[id]
        Work.checkpoint()
        for _, spawn in ipairs(vendor.spawns or {}) do
            if mappedPoint(spawn, map) then out[id] = true; break end
        end
    end
    return out
end

local function matchVendors(query)
    local needle, selected, fuzzy, candidates = lower(query), {}, {}, {}
    local sellersOnly, roleQuery = sellerQuery(query)
    sellersOnly = (sellersOnly or currentKind == "seller") and currentKind ~= "item"
    local parsed, scores = roleWords(sellersOnly and roleQuery or query), {}
    for _, item in ipairs(items) do
        if matchesWords(item.key, needle) then
            -- Item suggestions can still disambiguate an item whose name contains "Vendor".
            for _, id in ipairs(item.vendorIDs) do candidates[id] = true end
        end
        if not sellersOnly and currentKind ~= "vendor" and ((currentKind == "item" and item.key == needle)
            or (not currentKind and matchesWords(item.key, needle))) then
            for _, id in ipairs(item.vendorIDs) do selected[id] = true end
        end
        Work.checkpoint()
    end
    local checked = 0
    for id, vendor in pairs(vendors) do
        if currentKind ~= "item" and (not sellersOnly or vendor.isSeller) then
            local score = scores[vendor.title]
            if score == nil then
                score = sellersOnly and roleQuery == "" and 0 or roleMatch(vendor.roleWords, parsed, true)
                scores[vendor.title] = score or false
            end
            if score == 0 then selected[id] = true
            elseif score == 1 then fuzzy[id] = true end
        end
        checked = checked + 1
        if checked % 64 == 0 then Work.checkpoint() end
    end
    for id in pairs(selected) do candidates[id] = true end
    for id in pairs(fuzzy) do candidates[id] = true end
    return selected, fuzzy, candidates
end

local function mapSearch(map)
    local selected, fuzzy = {}, resolved.fuzzy
    for id in pairs(resolved.exact) do selected[id] = true end
    local function hasLocal(ids)
        for id in pairs(ids) do
            for _, spawn in ipairs(vendors[id].spawns or {}) do
                if mappedPoint(spawn, map) then return true end
                Work.checkpoint()
            end
        end
        return false
    end
    if not hasLocal(selected) and (next(selected) == nil or hasLocal(fuzzy)) then
        for id in pairs(fuzzy) do selected[id] = true end
    end
    return selected
end

-- Read locations for the current matches. Suggestions update at the first local match and whenever the number of
-- local matches doubles, so they appear before the whole list is read.
local function hydrate(candidates, query)
    local map = call(WorldMapFrame.GetMapID, WorldMapFrame)
    local localCount, nextRefresh = 0, 1
    -- Bounded cache: past SPAWN_CACHE, keep only what this query needs (at most SPAWN_CACHE + one query's matches).
    if cachedCount > SPAWN_CACHE then dropSpawns(candidates) end
    scan = { done = 0, total = 0 }
    for _ in pairs(candidates) do scan.total = scan.total + 1 end
    for id in pairs(candidates) do
        if not hydrated[id] then
            readSpawns(id)
            hydrated[id] = true
            for _, spawn in ipairs(vendors[id].spawns) do
                if mappedPoint(spawn, map) then localCount = localCount + 1; break end
            end
            if localCount >= nextRefresh and mapUI and mapUI.suggesting then
                nextRefresh = localCount * 2
                mapUI.refreshSuggestions(query)
            end
            Work.yield()
        end
        scan.done = scan.done + 1
        if scan.done % 256 == 0 then progress() end
    end
end

-- Per query: match the in-memory index and read locations. The index job supplies roles and, on request, items.
local function startSearch(query)
    if Work.busy("vendor-search") then Work.resume("vendor-search"); return end
    loading, waiting, scan = true, nil, nil
    local token, kind = generation, currentKind
    Work.start("vendor-search", function()
        local selected, fuzzy, candidates = matchVendors(query)
        local sellers = sellerQuery(query) or kind == "seller"
        -- Explicit roles never need the item catalogue. Otherwise try roles before item fallback.
        local needItems = not itemsCover(query) and (kind == "item" or (kind ~= "vendor" and (next(selected) == nil or sellers)))
        hydrate(candidates, query)
        if needItems then
            if not itemsCover(query) then
                -- Role matches are suggested already; V.draw searches again when the item index is complete.
                waiting = token
                startIndex(true)
                progress()
                return
            end
            -- The item index finished while these locations were read.
            selected, fuzzy, candidates = matchVendors(query)
            hydrate(candidates, query)
        end
        resolved = { query = query, kind = kind, exact = selected, fuzzy = fuzzy }
        loading, scan = false, nil
        V.draw()
        if mapUI then mapUI.refreshSuggestions(query, true) end
    end, function()
        return token == generation and ns.db.enabled and ns.db.vendorSearch and currentQuery ~= ""
            and WorldMapFrame and call(WorldMapFrame.IsShown, WorldMapFrame)
    end, function(ok)
        if not ok then
            loading, resolved, failed = false, nil, token
            if mapUI then mapUI.status:SetText("Vendor search stopped; try the search again.") end
        end
    end, typed and FOREGROUND_MS or nil)
end

local function nearestVendor(selected)
    local playerMap, px, py = ns.compat.playerPos()
    if not (playerMap and px and py) then return nil end
    local playerContinent, wx, wy = continentPoint(playerMap, px, py)
    if not playerContinent then return nil end
    local best
    for id in pairs(selected) do
        local vendor = vendors[id]
        for _, spawn in ipairs(vendor and vendor.spawns or {}) do
            if spawn.map and not spawn.dungeon then
                local cx, x, y = continentPoint(spawn.map, spawn.x / 100, spawn.y / 100)
                if cx == playerContinent then
                    local distance = (x - wx) ^ 2 + (y - wy) ^ 2
                    if not best or distance < best.distance then
                        best = { vendor = vendor, spawn = spawn, distance = distance }
                    end
                end
            end
        end
    end
    return best
end

local function pinFor(parent)
    local p = CreateFrame("Button", nil, parent)
    p:SetWidth(20); p:SetHeight(20)
    p.icon = p:CreateTexture(nil, "OVERLAY")
    p.icon:SetAllPoints(p)
    p:RegisterForClicks("LeftButtonUp")
    p:SetScript("OnEnter", function(self)
        local r = self.result
        U.tip(self, category(r.vendor), { "Matches: " .. currentQuery,
            zoneName(r.spawn.area) .. string.format(" (%.1f, %.1f)", r.spawn.x, r.spawn.y),
            "Click to set a waypoint." })
    end)
    p:SetScript("OnLeave", U.hideTip)
    p:SetScript("OnClick", function(self)
        local s = self.result.spawn
        if not ns.compat.setWaypoint(s.map, s.x / 100, s.y / 100) then
            ns.print("the game could not set a waypoint for this vendor")
        end
    end)
    return p
end

local function ensureUI(wm)
    if mapUI then return mapUI end
    local panel = CreateFrame("Frame", nil, wm, "BackdropTemplate")
    panel:SetWidth(400); panel:SetHeight(122); panel:SetPoint("BOTTOMRIGHT", wm, "BOTTOMRIGHT", -20, 24)
    S.panel(panel)
    local heading = U.text(panel, S.GOLD .. "Search this map|r", 8, 5, 384)
    heading:SetWordWrap(false)
    local edit = CreateFrame("EditBox", nil, panel)
    edit:SetWidth(316); edit:SetHeight(22); edit:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -22)
    if ChatFontNormal then edit:SetFontObject(ChatFontNormal) end
    edit:SetAutoFocus(false); edit:SetMaxLetters(70)
    if edit.SetTextInsets then edit:SetTextInsets(5, 28, 0, 0) end
    S.inset(edit)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); V.search(self:GetText(), true, currentKind) end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus(); mapUI.suggesting = false; mapUI.suggestionBox:Hide()
    end)
    local searchIcon = CreateFrame("Button", nil, edit)
    searchIcon:SetWidth(22); searchIcon:SetHeight(22); searchIcon:SetPoint("RIGHT", edit, "RIGHT", -2, 0)
    searchIcon.icon = searchIcon:CreateTexture(nil, "OVERLAY")
    searchIcon.icon:SetAllPoints(searchIcon)
    searchIcon.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetScript("OnClick", function() edit:ClearFocus(); V.search(edit:GetText(), true, currentKind) end)
    local clearButton = S.button(panel, "Clear", 54, function()
        edit:ClearFocus()
        V.search("", true)
    end)
    clearButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 336, -22)
    local status = U.text(panel, "", 8, 51, 298)
    status:SetWordWrap(true); status:SetHeight(66)
    local waypoint = S.button(panel, "Waypoint", 78, function()
        local r = mapUI and mapUI.closest
        if not r then                                  -- Elsewhere: find the closest one and set the waypoint at once
            currentOnly, lastRender = false, nil
            V.draw()
            r = mapUI.closest
            if not r then return end
        end
        if not ns.compat.setWaypoint(r.spawn.map, r.spawn.x / 100, r.spawn.y / 100) then
            ns.print("the game could not set a waypoint for this vendor")
        elseif mapUI.closestText then
            mapUI.status:SetText("Waypoint set. " .. mapUI.closestText)
        end
    end)
    waypoint:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 4)
    waypoint:Hide()
    local suggestionBox = CreateFrame("Frame", nil, wm, "BackdropTemplate")
    suggestionBox:SetWidth(316); suggestionBox:SetHeight(142)
    suggestionBox:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 8, 2)
    -- Map artwork can cover a sibling frame's background while its overlay text remains visible.
    suggestionBox:SetFrameStrata("TOOLTIP")
    suggestionBox:SetFrameLevel((call(wm.GetFrameLevel, wm) or 0) + 40)
    suggestionBox:EnableMouse(true); suggestionBox:SetClampedToScreen(true)
    S.panel(suggestionBox)                             -- the same stone and bronze rim as the other map panels
    suggestionBox:Hide()
    mapUI = { frame = panel, heading = heading, edit = edit, status = status, waypoint = waypoint,
        searchIcon = searchIcon, clearButton = clearButton,
        suggestionBox = suggestionBox, suggestionRows = {}, suggestions = {}, settingText = false }

    local function showSuggestions(list)
        local state = mapUI
        state.suggestions = list
        for i = 1, 6 do
            local row = state.suggestionRows[i]
            if not row then
                row = CreateFrame("Button", nil, state.suggestionBox)
                row:SetHeight(22); row:SetWidth(300)
                row:SetPoint("TOPLEFT", state.suggestionBox, "TOPLEFT", 8, -(5 + (i - 1) * 22))
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.text:SetWidth(296); row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
                row.highlight = S.fill(row, "BACKGROUND", 1, 1, 1, 0.12); row.highlight:SetAllPoints(row); row.highlight:Hide()
                row:SetScript("OnEnter", function(self) self.highlight:Show() end)
                row:SetScript("OnLeave", function(self) self.highlight:Hide() end)
                row:SetScript("OnClick", function(self)
                    local suggestion = self.suggestion
                    if suggestion then
                        state.settingText = true; state.edit:SetText(suggestion.value); state.settingText = false
                        state.suggestionBox:Hide()
                        V.search(suggestion.value, true, suggestion.kind)
                    end
                end)
                state.suggestionRows[i] = row
            end
            local suggestion = list[i]
            if suggestion then
                row.suggestion = suggestion
                row.text:SetText(S.WHITE .. suggestion.label .. "|r")
                row:Show()
            else
                row.suggestion = nil; row:Hide()
            end
        end
        if #list > 0 then state.suggestionBox:Show() else state.suggestionBox:Hide() end
    end

    -- final: the whole result is known. A partial result with nothing local yet keeps the shown suggestions.
    local function refreshSuggestions(text, final)
        local state = mapUI
        local query = trim(text)
        if not state.suggesting or #query < 2 then showSuggestions({}); return end
        local map = call(wm.GetMapID, wm)
        local list, found = {}, {}
        local localIDs = vendorsOnMap(map)
        local sellersOnly, roleQuery = sellerQuery(query)
        local roleNeedle = sellersOnly and roleQuery or query
        local parsed = roleWords(roleNeedle)
        local roleKind = sellersOnly and "seller" or "vendor"
        local function roleScore(words)
            return sellersOnly and roleNeedle == "" and 0 or roleMatch(words, parsed, true)
        end
        local function add(value, label, rank, kind)
            local key = lower(value)
            if key == "" or key == lower(query) or found[key] then return end
            found[key] = true
            list[#list + 1] = { value = value, label = label, rank = rank, kind = kind }
        end
        -- Offer the useful role word first: typing "tail" can complete to "Tailor", which still matches
        -- every role containing Tailor, including "Senior Master Tailor".
        -- ...but only while the last typed word is unfinished: "vendor" or "general" get whole titles, not their words.
        local typedWords = roleWords(roleNeedle)
        local last = typedWords[#typedWords]
        local finished = last == nil
        local suggestionWords = {}
        for id in pairs(hydrated) do
            local vendor = vendors[id]
            Work.checkpoint()
            local title = category(vendor)
            local eligible = localIDs[id] and (not sellersOnly or vendor.isSeller)
            for raw in string.gmatch(eligible and title or "", "%S+") do
                local word = string.gsub(string.gsub(raw, "^%p+", ""), "%p+$", "")
                local forms = roleWords(word)
                if forms[1] == last then finished = true end
                local score = roleScore(forms)
                if score then suggestionWords[lower(word)] = { value = word, score = score } end
            end
        end
        if not finished then
            for _, word in pairs(suggestionWords) do
                add(word.value, word.value .. " (all matches)", 1 + word.score * 3, roleKind)
            end
        end
        for id in pairs(hydrated) do
            local vendor = vendors[id]
            Work.checkpoint()
            local title = category(vendor)
            local score = roleScore(vendor.roleWords)
            if localIDs[id] and (not sellersOnly or vendor.isSeller) and score then
                add(title, titleKind(vendor) .. title, 2 + score * 3, roleKind)
            end
        end
        local itemCount = 0
        for _, item in ipairs(items) do
            Work.checkpoint()
            local localSeller = false
            for _, id in ipairs(item.vendorIDs) do if localIDs[id] then localSeller = true; break end end
            if localSeller and matchesWords(item.name, query) then
                add(item.name, "Item: " .. item.name, 3, "item")
                itemCount = itemCount + 1
                if itemCount >= 80 then break end
            end
        end
        table.sort(list, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return lower(a.value) < lower(b.value)
        end)
        -- This can yield inside the search job: a keystroke or map change meanwhile makes the list stale.
        if query ~= currentQuery or not state.suggesting or call(wm.GetMapID, wm) ~= map then return end
        if final or #list > 0 then showSuggestions(list) end
    end
    mapUI.refreshSuggestions = refreshSuggestions

    -- A keystroke keeps the shown suggestions that the new text still matches by the rules above, until replaced.
    local function keepMatching(query)
        local kept = {}
        local sellersOnly, roleQuery = sellerQuery(query)
        local roleNeedle = sellersOnly and roleQuery or query
        local parsed, roleKind = roleWords(roleNeedle), sellersOnly and "seller" or "vendor"
        for _, s in ipairs(#query >= 2 and mapUI.suggestions or {}) do
            local match
            if s.kind == "item" then match = matchesWords(s.value, query)
            else match = s.kind == roleKind and (sellersOnly and roleNeedle == "" or roleMatch(roleWords(s.value), parsed, true)) end
            if match and lower(s.value) ~= lower(query) then kept[#kept + 1] = s end
        end
        showSuggestions(kept)
    end
    edit:SetScript("OnTextChanged", function(self)
        if mapUI.settingText then return end
        if searchTimer then ns.cancel(searchTimer); searchTimer = nil end
        generation = generation + 1
        Work.cancel("vendor-search"); loading = false
        currentQuery, currentOnly, currentKind = trim(self:GetText()), true, nil
        mapUI.suggesting = true
        if currentQuery == "" then typed = false; dropItems(); clearLocations(); V.draw(); return end
        -- Keystrokes keep the catalogue index and cached locations; the first typed character starts the index.
        clearResults()
        keepMatching(currentQuery)
        typed = true
        if ns.db.enabled and ns.db.vendorSearch and not ns.isBlocked("vendormap")
            and (Q.canEnumerate("npc") or Q.canEnumerate("item")) then startIndex() end
        searchTimer = ns.after(0.18, function() searchTimer = nil; V.draw() end)
    end)
    edit:SetScript("OnTabPressed", function()
        local suggestion = mapUI.suggestions[1]
        if suggestion then
            mapUI.settingText = true; edit:SetText(suggestion.value); mapUI.settingText = false
            mapUI.suggestionBox:Hide()
            V.search(suggestion.value, true, suggestion.kind)
        end
    end)
    return mapUI
end

function V.search(query, mapOnly, kind)
    if searchTimer then ns.cancel(searchTimer); searchTimer = nil end
    query = trim(query)
    -- An explicit search after a failed vendor job retries it, also with the same text and kind.
    if query ~= currentQuery or kind ~= currentKind or failed == generation then
        generation = generation + 1
        Work.cancel("vendor-search"); loading = false
        if query == "" then typed = false; clearLocations() else clearResults() end
    end
    currentQuery, currentOnly, currentKind = query, mapOnly ~= false, kind
    if not mapUI then return end
    lastRender = nil
    mapUI.suggesting, mapUI.suggestions = false, {}
    mapUI.suggestionBox:Hide()
    mapUI.settingText = true
    mapUI.edit:SetText(currentQuery)
    mapUI.settingText = false
    V.draw()
end

function V.draw()
    local wm, query = WorldMapFrame, currentQuery
    local scroll = wm and wm.ScrollContainer
    local canvas = scroll and scroll.Child
    local on = ns.db.enabled and ns.db.vendorSearch and not ns.isBlocked("vendormap")
    if not (on and wm and canvas and call(wm.IsShown, wm)) then
        Work.pause("vendor-search"); Work.pause("vendor-index")
        if mapUI and call(mapUI.frame.IsShown, mapUI.frame) then
            mapUI.frame:Hide(); mapUI.suggestionBox:Hide()
            for _, p in ipairs(pins) do p:Hide() end
        end
        lastRender = nil
        return
    end
    local ui = ensureUI(wm); ui.frame:Show()
    local map = call(wm.GetMapID, wm)
    local info = mapInfo(map)
    local mapName = info and info.name or "this map"
    ui.heading:SetText(S.GOLD .. "Search this map: " .. mapName .. "|r")
    if ui.map ~= map then
        ui.map, currentOnly, lastRender = map, true, nil
        -- Suggestions and cached locations belong to the shown map; only the current matches keep theirs.
        dropSpawns(hydrated)
        ui.suggestions = {}; ui.suggestionBox:Hide()
        if resolved or next(hydrated) then ui.refreshSuggestions(query, resolved ~= nil) end
    end
    if scroll ~= hookedScroll and scroll.HookScript then
        scroll:HookScript("OnMouseDown", function(_, button)
            if button == "RightButton" and IsControlKeyDown and IsControlKeyDown()
                and ns.db.enabled and ns.db.vendorSearch then
                ui.edit:SetFocus()
                V.search(ui.edit:GetText(), true, currentKind)
            end
        end)
        hookedScroll = scroll
    end
    if not Q.canEnumerate("npc") and not Q.canEnumerate("item") then
        if ready or itemsReady or loading or next(hydrated) or next(cached) or Work.busy("vendor-index") then
            resetIndex()
        end
        ui.closest = nil; ui.waypoint:Hide(); ui.suggestionBox:Hide()
        if Q.available() then
            ui.status:SetText("Map search needs a newer QuestieDB.\nUpdate/enable QuestieDB, then /reload.\nCheck loaded data: /qs questie")
        else
            ui.status:SetText("Map search requires QuestieDB data.\nInstall/enable QuestieDB; /reload.\nQuestie is optional. Check: /qs questie")
        end
        return
    end
    if query == "" then
        Work.pause("vendor-search"); Work.pause("vendor-index")
        if lastRender and lastRender.empty and lastRender.map == map then return end
        ui.closest = nil; ui.waypoint:Hide(); ui.suggestionBox:Hide()
        for _, p in ipairs(pins) do p.result = nil; p:Hide() end
        lastRender = { empty = true, map = map }
        ui.status:SetText("Uses QuestieDB: type vendor, general vendor,\na trainer role or an item sold by vendors.\nSuggestions and pins use only this map.")
        return
    end
    if searchTimer then return end
    Work.resume("vendor-search")
    if not resolved then
        ui.closest = nil; ui.waypoint:Hide()
        if failed == generation then return end
        if not ready or (waiting == generation and not itemsCover(query)) then startIndex(waiting == generation)
        else startSearch(query) end
        progress()
        return
    end

    local width, height = call(canvas.GetWidth, canvas), call(canvas.GetHeight, canvas)
    local scale = call(canvas.GetScale, canvas) or 1
    if lastRender and lastRender.canvas == canvas and lastRender.query == query and lastRender.map == map
        and lastRender.only == currentOnly
        and lastRender.kind == currentKind
        and lastRender.width == width and lastRender.height == height
        and lastRender.scale == scale and lastRender.ready == ready then return end
    lastRender = { canvas = canvas, query = query, map = map, only = currentOnly, kind = currentKind, width = width, height = height,
        scale = scale, ready = ready }
    ui.closest = nil; ui.waypoint:Hide()
    local selected = mapSearch(map)
    local results, selectedIDs = {}, {}
    for id in pairs(selected) do selectedIDs[#selectedIDs + 1] = id end
    table.sort(selectedIDs)
    for _, id in ipairs(selectedIDs) do
        local vendor = vendors[id]
        for _, spawn in ipairs(vendor and vendor.spawns or {}) do
            Work.checkpoint()
            if call(wm.GetMapID, wm) ~= map then lastRender = nil; return end
            local x, y = mappedPoint(spawn, map)
            if x then results[#results + 1] = { vendor = vendor, spawn = spawn, x = x, y = y } end
        end
    end
    local localResults = results
    table.sort(localResults, function(a, b)
        local at, bt = lower(category(a.vendor)), lower(category(b.vendor))
        if at ~= bt then return at < bt end
        if a.spawn.area ~= b.spawn.area then return a.spawn.area < b.spawn.area end
        if a.spawn.x ~= b.spawn.x then return a.spawn.x < b.spawn.x end
        return a.spawn.y < b.spawn.y
    end)
    local n = 0
    if not finite(scale) or scale <= 0 then scale = 1 end
    for _, result in ipairs(localResults) do
        Work.checkpoint()
        if call(wm.GetMapID, wm) ~= map then lastRender = nil; return end
        n = n + 1
        local p = pins[n] or pinFor(canvas)
        pins[n], p.result = p, result
        local texture, coords = V.iconFor(category(result.vendor))
        p.icon:SetTexture(texture)
        if coords then p.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else p.icon:SetTexCoord(0, 1, 0, 1) end
        p:ClearAllPoints(); p:SetScale(1 / scale)
        p:SetPoint("CENTER", canvas, "TOPLEFT", result.x * canvas:GetWidth() * scale, -result.y * canvas:GetHeight() * scale)
        p:Show()
    end
    for i = n + 1, #pins do pins[i]:Hide() end
    if n > 0 then
        ui.status:SetText(n .. " location" .. (n == 1 and "" or "s") .. " for \"" .. query .. "\"\nKnown Questie locations in " .. mapName .. ".")
    elseif next(selected) == nil then
        ui.status:SetText("No known seller for \"" .. query .. "\".\nQuestie may have no vendor link; drops and crafting are not searched.")
    elseif currentOnly then
        ui.status:SetText("0 locations for \"" .. query .. "\" in " .. mapName .. ".\nKnown matches are elsewhere or have no map spot.\n"
            .. "Click Elsewhere to find the closest one.")
        ui.waypoint:SetLabel("Elsewhere"); ui.waypoint:Show()
    else
        local nearest = nearestVendor(selected)
        if not nearest then
            ui.status:SetText("No matching location is on this map or nearby.")
        else
            local s, v = nearest.spawn, nearest.vendor
            ui.closest = nearest
            ui.waypoint:SetLabel("Waypoint")
            ui.waypoint:Show()
            local zone = (mapInfo(s.map) or {}).name or zoneName(s.area)
            ui.closestText = "Closest one is in " .. zone .. ":\n" .. category(v) .. string.format(" (%.1f, %.1f)", s.x, s.y)
            ui.status:SetText(ui.closestText)
        end
    end
end

-- Memory: the NPC/item index is read once and kept for the session (closing the map pauses it); Purge frees it.
function V.purge() Work.forget("mapSearchNPCs"); resetIndex(); V.draw() end
V._release = resetIndex -- tests: free memory only, the saved lists stay
ns.dataWork.onPurge("Map search", V.purge)
function V._state() return ready, itemsReady, next(vendors) ~= nil end

local function tick()
    V.draw()
    local mapShown = ns.db.vendorSearch and WorldMapFrame and call(WorldMapFrame.IsShown, WorldMapFrame)
    ns.after(mapShown and 0.5 or 2, tick)
end

function V.refresh()
    if not ns.db.enabled or not ns.db.vendorSearch then
        resetIndex()
    end
    V.draw()
end

ns.on("PLAYER_LOGIN", function() ns.after(1, tick) end)
ns.on("WORLD_MAP_UPDATE", V.refresh)
