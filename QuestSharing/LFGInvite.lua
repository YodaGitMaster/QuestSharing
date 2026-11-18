-- LFGInvite.lua: find players who list themselves in the game's party finder and invite the roles you want.
--   Minimap button (magnifier) or the "Party finder: search and invite" key: one press = one search; when the
--   results arrive, every solo player who signed up as a wanted role (Settings > Party window) gets an invite,
--   up to the free spots of your party.
--   The game only lets a search start from a click or a key press (C_LFGList.Search is restricted), so there is
--   no timer that searches by itself. Reading the results and inviting need no click.
--   The party finder gives name, level, class, spec, roles and zone of a listed player, but no gear or item level:
--   the item level comes from ItemLevel.lua (players inspected nearby, or other Quest Sharing users answering).
--   Filters (Settings > Party window): character level range, minimum item level, what to do when it is unknown.
local ADDON, ns = ...
local C = ns.compat

local L = {}
ns.lfgInvite = L

local RECENT = 300          -- seconds a player we invited is skipped (no repeat invites while they decide)
local PENDING = 60          -- seconds an invite still counts as a taken spot
local MAX_PARTY = 5
local DUNGEONS = 2          -- the game's "Dungeons" category, used when the Blizzard window has no choice
local ASK_WAIT = 2          -- seconds we wait for a Quest Sharing user to tell us their item level

local invited = {}          -- name -> GetTime() of our invite
local skipped = {}          -- name -> GetTime() we decided not to invite (filters), checked again after RECENT
local deciding = {}         -- name -> match, while we wait for their item level
local searching = false
local lastNote

local function api() return C_LFGList end

-- the roles the player wants, as the game names them in lfgRoles
function L.wanted()
    local d = ns.db
    return { tank = d.lfgTank and true or false, healer = d.lfgHealer and true or false, dps = d.lfgDps and true or false }
end

function L.wantedText()
    local w, out = L.wanted(), {}
    if w.healer then out[#out + 1] = "healers" end
    if w.tank then out[#out + 1] = "tanks" end
    if w.dps then out[#out + 1] = "damage dealers" end
    return #out > 0 and table.concat(out, ", ") or nil
end

local function note(text)
    if text ~= lastNote then ns.print(text) end
    lastNote = text
end

-- how many more players we may invite now (0 = none: party full, or grouped without being the leader)
function L.freeSpots()
    if C.inGroup() and not C.isLeader() then return 0, "only the party leader can invite" end
    local taken = C.inGroup() and C.groupSize() or 1
    local now = GetTime()
    for _, at in pairs(invited) do if now - at < PENDING then taken = taken + 1 end end
    for _ in pairs(deciding) do taken = taken + 1 end
    if taken >= MAX_PARTY then return 0, "the party is full" end
    return MAX_PARTY - taken
end

local function rolesOf(p)
    local r = p and p.lfgRoles
    if type(r) ~= "table" then return nil end
    return { tank = r.tank and true or false, healer = r.healer and true or false, dps = (r.dps or r.damage) and true or false }
end

local function roleWord(roles, wanted)
    for _, k in ipairs({ "healer", "tank", "dps" }) do
        if roles[k] and wanted[k] then return k == "dps" and "damage" or k end
    end
end

-- the solo players in the current results who match a wanted role and were not invited recently
function L.matches()
    local A = api()
    if not (A and A.GetSearchResultInfo and A.GetSearchResultPlayerInfo) then return {} end
    local get = A.GetFilteredSearchResults or A.GetSearchResults
    if not get then return {} end
    local _, results = get()
    local wanted, now, out = L.wanted(), GetTime(), {}
    local me = UnitName and UnitName("player")
    local lo, hi = tonumber(ns.db.lfgMinLevel) or 1, tonumber(ns.db.lfgMaxLevel) or 1000
    local function recent(t, name) return t[name] and now - t[name] < RECENT end
    for _, id in ipairs(results or {}) do
        local ok, info = pcall(A.GetSearchResultInfo, id)
        if ok and type(info) == "table" and info.numMembers == 1 and not info.isDelisted and not info.hasSelf then
            local okP, p = pcall(A.GetSearchResultPlayerInfo, id, 1)
            local roles = okP and rolesOf(p)
            local name = (okP and p and p.name) or info.leaderName
            local role = roles and roleWord(roles, wanted)
            local level = okP and p and tonumber(p.level)
            local inRange = not level or (level >= lo and level <= hi)
            if role and name and name ~= me and inRange and not recent(invited, name) and not recent(skipped, name) and not deciding[name] then
                out[#out + 1] = { id = id, name = name, role = role, level = p.level, class = p.className, spec = p.specName }
            end
        end
    end
    return out
end

local function describe(m, level, age)
    local parts = { m.role, level and ("ilvl " .. level) or "ilvl ?" }
    local seenText = level and ns.itemLevel and ns.itemLevel.ageText(age)
    if seenText then parts[#parts + 1] = seenText end
    return m.name .. (m.level and (" " .. m.level) or "") .. (m.class and (" " .. m.class) or "") .. " (" .. table.concat(parts, ", ") .. ")"
end

local function doInvite(m, level, age)
    ns.log("lfg", "invite " .. m.name .. " (" .. m.role .. ", ilvl " .. tostring(level) .. ")")
    if not C.invite(m.name) then return false end
    invited[m.name] = GetTime()
    note("party finder: invited " .. describe(m, level, age))
    if ns.goodNews then ns.goodNews() end
    return true
end

local function skip(m, level, age, why)
    skipped[m.name] = GetTime()
    ns.log("lfg", "skip " .. m.name .. ": " .. why)
    note("party finder: skipped " .. describe(m, level, age) .. " - " .. why)
end

-- one player: invite, skip, or first ask for the item level; returns "invited", "skipped", "asking" or nil
local function decide(m)
    local I = ns.itemLevel
    local need = tonumber(ns.db.lfgMinIlvl) or 0
    local level, age
    if I then level, age = I.known(m.name) end
    if level then
        if need > 0 and level < need then skip(m, level, age, "below item level " .. need); return "skipped" end
        return doInvite(m, level, age) and "invited" or nil
    end
    if need > 0 and ns.db.lfgAskIlvl and I and not m.asked then
        m.asked = true
        deciding[m.name] = m
        local function finish()
            if deciding[m.name] ~= m then return end
            deciding[m.name] = nil
            I.cancel(m.name)
            if L.freeSpots() > 0 then decide(m) end
        end
        I.ask(m.name, finish)
        ns.after(ASK_WAIT, finish)
        return "asking"
    end
    if need > 0 and ns.db.lfgUnknown == "skip" then skip(m, nil, nil, "item level unknown"); return "skipped" end
    return doInvite(m) and "invited" or nil
end
L.decide = decide

-- invite the matches, as many as the party has room for; returns how many were invited or asked
function L.inviteMatches()
    if not L.wantedText() then return 0 end
    local spots, why = L.freeSpots()
    if spots <= 0 then
        if why then note("party finder: " .. why .. ", nobody invited") end
        return 0
    end
    local n = 0
    for _, m in ipairs(L.matches()) do
        if n >= spots then break end
        local r = decide(m)
        if r == "invited" or r == "asking" then n = n + 1 end
    end
    return n
end

-- the category and activities to search: the Blizzard window's choice when it has one, else Dungeons
local function searchArgs()
    local cat, acts
    local f = _G.LFGBrowseFrame
    if f and f.CategoryDropdown and f.CategoryDropdown.GetValue then
        local ok, v = pcall(f.CategoryDropdown.GetValue, f.CategoryDropdown)
        if ok and type(v) == "number" and v > 0 then cat = v end
        local sel = f.ActivityDropdown and f.ActivityDropdown.selectedValues
        if cat and type(sel) == "table" and #sel > 0 then acts = sel end
    end
    cat = cat or DUNGEONS
    if not acts and _G.LFGUtil_GetFilteredActivities then
        local ok, list = pcall(_G.LFGUtil_GetFilteredActivities, cat)
        if ok and type(list) == "table" then acts = list end
    end
    return cat, acts
end

-- one press of the button or the key: search, the invites follow when the results arrive
function L.scan()
    local A = api()
    if not (A and A.Search) then return ns.print("party finder: this game version has no party finder for addons") end
    if not L.wantedText() then return ns.print("party finder: choose who to invite first (Settings > Party window)") end
    local spots, why = L.freeSpots()
    if spots <= 0 then return ns.print("party finder: " .. (why or "no free spot")) end
    L.inviteMatches()                                           -- results already on hand count at once
    if searching then return end
    local cat, acts = searchArgs()
    searching = true
    lastNote = nil
    ns.log("lfg", "search category " .. tostring(cat))
    local ok, err = pcall(A.Search, cat, 0, 0, nil, false, nil, acts)
    if not ok then
        searching = false
        ns.log("lfg", "search refused: " .. tostring(err))
        ns.print("party finder: the game refused the search (press the button or key again)")
    end
end

ns.on("LFG_LIST_SEARCH_RESULTS_RECEIVED", function()
    local mine = searching
    searching = false
    if mine or ns.db.lfgWatch then L.inviteMatches() end
end)
ns.on("LFG_LIST_SEARCH_FAILED", function()
    if searching then ns.print("party finder: search failed (the game may want a short pause between searches)") end
    searching = false
end)
ns.on("LFG_LIST_SEARCH_RESULT_UPDATED", function()
    if ns.db.lfgWatch then L.inviteMatches() end
end)

-- the key binding (Bindings.xml)
BINDING_NAME_QUESTSHARING_LFGSCAN = "Party finder: search and invite"
function QuestSharing_LFGScan() L.scan() end

function L.tooltipLines()
    local S = ns.style
    local w = L.wantedText()
    local lines = { "Invites: " .. (w and (S.GOLD .. w .. "|r") or (S.RED .. "nobody chosen|r - right click")) }
    local d = ns.db
    local need = tonumber(d.lfgMinIlvl) or 0
    lines[#lines + 1] = string.format("Levels %d-%d, item level %s", d.lfgMinLevel or 1, d.lfgMaxLevel or 60,
        need > 0 and (need .. "+" .. (d.lfgUnknown == "skip" and " (unknown: skip)" or " (unknown: invite)")) or "any")
    local spots, why = L.freeSpots()
    lines[#lines + 1] = spots > 0 and string.format("%d free spot%s", spots, spots == 1 and "" or "s") or (S.GREY .. (why or "") .. "|r")
    lines[#lines + 1] = " "
    lines[#lines + 1] = S.GREY .. "Left click: search and invite (click again to search again)|r"
    lines[#lines + 1] = S.GREY .. "Right click: choose roles (Settings)|r"
    return lines
end

function L.command(arg)
    arg = string.lower(arg or "")
    local ROLE = { healer = "lfgHealer", healers = "lfgHealer", tank = "lfgTank", tanks = "lfgTank", dps = "lfgDps", damage = "lfgDps" }
    local word, val = string.match(arg, "^(%S+)%s*(.-)$")
    if arg == "" or arg == "scan" then L.scan()
    elseif word == "ilvl" and tonumber(val) then
        ns.setSetting("lfgMinIlvl", math.max(0, math.floor(tonumber(val))))
        ns.print("party finder: minimum item level " .. (ns.db.lfgMinIlvl > 0 and ns.db.lfgMinIlvl or "any"))
    elseif word == "level" then
        local a, b = string.match(arg, "^level%s+(%d+)%s+(%d+)$")
        if a then
            ns.setSetting("lfgMinLevel", math.min(tonumber(a), tonumber(b))); ns.setSetting("lfgMaxLevel", math.max(tonumber(a), tonumber(b)))
            ns.print(string.format("party finder: levels %d-%d", ns.db.lfgMinLevel, ns.db.lfgMaxLevel))
        else ns.print("usage: /qs lfg level <lowest> <highest>") end
    elseif word == "unknown" and (val == "invite" or val == "skip") then ns.setSetting("lfgUnknown", val)
    elseif word == "watch" and (val == "on" or val == "off") then ns.setSetting("lfgWatch", val == "on")
    elseif word and ROLE[word] and (val == "on" or val == "off") then
        ns.setSetting(ROLE[word], val == "on")
        ns.print("party finder invites: " .. (L.wantedText() or "nobody"))
    else ns.print("usage: /qs lfg [scan] | healer|tank|dps on|off | watch on|off | ilvl <n> | level <low> <high> | unknown invite|skip") end
end

function L._reset() invited, skipped, deciding, searching, lastNote = {}, {}, {}, false, nil end   -- for the tests
