-- LFGInvite.lua: find players who list themselves in the game's party finder and invite the roles you want.
--   Prerequisite: you (or your party, as leader) are listed in the party finder with an activity (a dungeon).
--   Minimap spyglass -> small picker (roles, classes per role) -> Find, or the "Party finder: search and invite" key:
--   one press = one search of your listing's activities; when the results arrive, solo players listed for one of
--   those activities as a wanted role and class get an invite, highest level first, up to the free spots.
--   The game only lets a search start from a click or a key press (C_LFGList.Search is restricted), so there is
--   no timer that searches by itself. Reading the results and inviting need no click.
--   The party finder gives name, level, class, spec, roles and zone of a listed player, but no gear or item level:
--   the item level comes from ItemLevel.lua (players inspected nearby, or other Quest Sharing users answering).
--   Filters (Settings > Party finder): character level range, minimum item level, what to do when it is unknown.
local ADDON, ns = ...
local C = ns.compat

local L = {}
ns.lfgInvite = L

local RECENT = 300          -- seconds a player we invited is skipped (no repeat invites while they decide)
local PENDING = 60          -- seconds an invite still counts as a taken spot
local MAX_PARTY = 5
local DUNGEONS = 2          -- the game's "Dungeons" category, used when the Blizzard window has no choice
local ASK_WAIT = 2          -- seconds we wait for a Quest Sharing user to tell us their item level

local NEED = { healer = 1, tank = 1, damage = 3 }      -- a dungeon party: what each role needs at most
local SUPER_MAX = 10        -- supercharge: invites per click at most (chat and invite throttles)
local SEARCH_TIMEOUT = 6    -- seconds after which a search the game never answered no longer blocks the next one

local invited = {}          -- name -> GetTime() of our invite (not invited again for RECENT seconds)
local pending = {}          -- name -> GetTime(): invited, not joined/declined yet (holds a party spot for PENDING s)
local pendingRole = {}      -- name -> "healer" | "tank" | "damage": what we invited them as
local memberRole = {}       -- bare name -> role, for party members who joined through our invite
local skipped = {}          -- name -> GetTime() we decided not to invite (filters), checked again after RECENT
local deciding = {}         -- name -> match, while we wait for their item level
local searching = false
local searchStart = 0
local clickInvites = 0      -- invites the last click made before its search came back
local lastNote

local function api() return C_LFGList end

-- the name without its realm, to compare a chat line with a party finder name
local function bare(name) return name and (string.match(name, "^([^%-]+)") or name) or nil end

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
    if ns.lfgFinder then ns.lfgFinder.status(string.gsub(text, "^party finder: ", "")) end
end

-- how many more players we may invite now (0 = none: party full, or grouped without being the leader)
function L.freeSpots()
    if C.inGroup() and not C.isLeader() then return 0, "only the party leader can invite" end
    local taken = C.inGroup() and C.groupSize() or 1
    local now = GetTime()
    if not ns.db.lfgSupercharge then             -- supercharge sends more invites than spots on purpose
        for _, at in pairs(pending) do if now - at < PENDING then taken = taken + 1 end end
        for _ in pairs(deciding) do taken = taken + 1 end
    end
    if taken >= MAX_PARTY then return 0, "the party is full" end
    return MAX_PARTY - taken
end

-- the classes that can take each role (Classic); the picker window turns single classes off
L.ROLE_CLASSES = {
    healer = { "PRIEST", "PALADIN", "DRUID", "SHAMAN" },
    tank = { "WARRIOR", "DRUID", "PALADIN" },
    dps = { "WARRIOR", "ROGUE", "MAGE", "WARLOCK", "HUNTER", "PRIEST", "DRUID", "SHAMAN", "PALADIN" },
}

-- QuestSharingDB.lfgClassOff[role][CLASS] = true: that class is not invited for that role (nothing saved = all classes)
function L.classAllowed(role, class)
    local off = ns.db.lfgClassOff
    return not (class and type(off) == "table" and type(off[role]) == "table" and off[role][class])
end

function L.setClass(role, class, on)
    ns.db.lfgClassOff = type(ns.db.lfgClassOff) == "table" and ns.db.lfgClassOff or {}
    local off = ns.db.lfgClassOff
    off[role] = off[role] or {}
    off[role][class] = (not on) or nil
    if next(off[role]) == nil then off[role] = nil end
end

local function activityName(id)
    local A = api()
    if A and A.GetActivityFullName then
        local ok, n = pcall(A.GetActivityFullName, id)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    if A and A.GetActivityInfoTable then
        local ok, info = pcall(A.GetActivityInfoTable, id)
        if ok and type(info) == "table" and info.fullName then return info.fullName end
    end
    return "activity " .. tostring(id)
end

-- my own listing in the party finder: { activities = {ids}, set = {[id] = true}, name = first activity's name }
-- nil when I (or my party) am not listed: then nobody is searched or invited
function L.listing()
    local A = api()
    if not (A and A.HasActiveEntryInfo and A.GetActiveEntryInfo) then return nil end
    local ok, has = pcall(A.HasActiveEntryInfo)
    if not (ok and has) then return nil end
    local okE, e = pcall(A.GetActiveEntryInfo)
    if not (okE and type(e) == "table") then return nil end
    local acts, set = {}, {}
    for _, id in ipairs(e.activityIDs or { e.activityID }) do       -- older clients: one activityID
        if id and id ~= 0 then acts[#acts + 1] = id; set[id] = true end
    end
    if #acts == 0 then return nil end
    return { activities = acts, set = set, name = activityName(acts[1]) .. (#acts > 1 and string.format(" (+%d)", #acts - 1) or "") }
end

local NOT_LISTED = "list your group in the party finder first (with the dungeon you want), then search"

local function rolesOf(p)
    local r = p and p.lfgRoles
    if type(r) ~= "table" then return nil end
    return { tank = r.tank and true or false, healer = r.healer and true or false, dps = (r.dps or r.damage) and true or false }
end

-- every role this player may be invited as (wanted, signed up for, class allowed), the hardest to find first,
-- so a druid listed as healer and damage can still take a damage spot once the healer spot is filled
local ROLE_ORDER = { "tank", "healer", "dps" }
local function rolesFor(roles, wanted, class)
    local out = {}
    for _, k in ipairs(ROLE_ORDER) do
        if roles[k] and wanted[k] and L.classAllowed(k, class) then out[#out + 1] = (k == "dps") and "damage" or k end
    end
    return out
end

-- the first of their activities that is also in my listing
local function shared(info, listing)
    for _, id in ipairs(info.activityIDs or { info.activityID }) do   -- older clients: one activityID
        if listing.set[id] then return id end
    end
end

-- the listed player (a solo result: its only member is its leader)
local function playerOf(A, id)
    for _, key in ipairs({ "GetSearchResultPlayerInfo", "GetSearchResultLeaderInfo" }) do   -- names, not functions:
        local f = A[key]                                                                     -- a nil would end ipairs
        if f then
            local ok, p = pcall(f, id, 1)
            if ok and type(p) == "table" then return p end
        end
    end
end

-- the solo players in the current results who listed for one of my listing's activities, as a wanted role and
-- class, inside the level range, not invited recently; highest level first (then the highest known item level)
function L.matches()
    local listing = L.listing()
    if not listing then return {} end
    local A = api()
    if not (A and A.GetSearchResultInfo and (A.GetSearchResultPlayerInfo or A.GetSearchResultLeaderInfo)) then return {} end
    local get = A.GetFilteredSearchResults or A.GetSearchResults
    if not get then return {} end
    local _, results = get()
    local wanted, now, out = L.wanted(), GetTime(), {}
    local me = UnitName and UnitName("player")
    local lo, hi = tonumber(ns.db.lfgMinLevel) or 1, tonumber(ns.db.lfgMaxLevel) or 1000
    local function recent(t, name) return t[name] and now - t[name] < (tonumber(ns.db.lfgReinvite) or RECENT / 60) * 60 end
    for _, id in ipairs(results or {}) do
        local ok, info = pcall(A.GetSearchResultInfo, id)
        local act = ok and type(info) == "table" and shared(info, listing)
        if act and info.numMembers == 1 and not info.isDelisted and not info.hasSelf then
            local p = playerOf(A, id) or {}
            local roles = rolesOf(p)
            local name = p.name or info.leaderName
            local class = p.classFilename and string.upper(p.classFilename) or nil
            local can = roles and rolesFor(roles, wanted, class) or {}
            local level = tonumber(p.level)
            local inRange = not level or (level >= lo and level <= hi)
            if #can > 0 and name and name ~= me and inRange and not recent(invited, name) and not recent(skipped, name) and not deciding[name] then
                local known = ns.itemLevel and ns.itemLevel.known(name)
                out[#out + 1] = { id = id, name = name, roles = can, role = can[1], level = level, class = p.className,
                                  classFile = class, spec = p.specName, activity = act, ilvl = known }
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
        return a.name < b.name
    end)
    return out
end

local function describe(m, level, age)
    local parts = { m.role, level and ("item level " .. level) or "item level unknown" }
    local seenText = level and ns.itemLevel and ns.itemLevel.ageText(age)
    if seenText then parts[#parts + 1] = seenText end
    return m.name .. (m.level and (" " .. m.level) or "") .. (m.class and (" " .. m.class) or "") .. " (" .. table.concat(parts, ", ") .. ")"
        .. (m.activity and (" for " .. activityName(m.activity)) or "")
end

-- the whisper that goes with an invite: {dungeon} and {role} are filled in
local ROLE_WORDS = { healer = "healer", tank = "tank", damage = "damage dealer" }
L.DEFAULT_WHISPER = "Hi! I invited you to my group for {dungeon} as {role}."
function L.whisperText(m)
    local t = ns.db.lfgWhisperText
    if type(t) ~= "string" or not string.find(t, "%S") then t = L.DEFAULT_WHISPER end
    local dungeon = m.activity and activityName(m.activity) or "a dungeon"
    t = string.gsub(t, "{dungeon}", (string.gsub(dungeon, "%%", "%%%%")))
    t = string.gsub(t, "{role}", ROLE_WORDS[m.role] or m.role or "")
    if ns.db.lfgSupercharge then t = t .. " First to accept gets the spot." end
    return string.sub(t, 1, 255)
end

local function whisper(m)
    if not ns.db.lfgWhisper or not SendChatMessage then return false end
    if not ns.chatAllowed("WHISPER") then ns.log("lfg", "whisper skipped: the game refused chat before"); return false end
    local text = L.whisperText(m)
    ns.trying("whispering " .. m.name .. " about the invite", "chat", "/w " .. m.name .. " " .. text)
    ns.log("chat", "whisper to " .. m.name .. ": " .. text)
    return (pcall(SendChatMessage, text, "WHISPER", nil, m.name))
end

local function doInvite(m, level, age)
    ns.log("lfg", "invite " .. m.name .. " (" .. m.role .. ", item level " .. tostring(level or "unknown") .. ")")
    if not C.invite(m.name) then return false end
    invited[m.name], pending[m.name], pendingRole[m.name] = GetTime(), GetTime(), m.role
    note("party finder: invited " .. describe(m, level, age))
    whisper(m)
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
            -- meanwhile someone may have filled the spot or the role
            if L.freeSpots() > 0 and (ns.db.lfgSupercharge or L.roleOpen(m.role) > 0) then decide(m) end
        end
        I.ask(m.name, finish)
        ns.after(ASK_WAIT, finish)
        return "asking"
    end
    if need > 0 and ns.db.lfgUnknown == "skip" then skip(m, nil, nil, "item level unknown"); return "skipped" end
    return doInvite(m) and "invited" or nil
end
L.decide = decide

-- how many of a role the party has or is waiting for: members who joined as it (or whom the game knows as it),
-- open invites and players we are still asking about
local GAME_ROLE = { HEALER = "healer", TANK = "tank", DAMAGER = "damage" }
local PURE_DAMAGE = { ROGUE = true, MAGE = true, WARLOCK = true, HUNTER = true }
-- a party member's role: as we invited them, else as the game knows it, else from a class that can only do damage
local function memberRoleOf(m)
    local r = memberRole[bare(m.name)]
    if not r and UnitGroupRolesAssigned then
        local ok, g = pcall(UnitGroupRolesAssigned, m.unit)
        r = ok and GAME_ROLE[g] or nil
    end
    if not r and UnitClass then
        local ok, _, file = pcall(UnitClass, m.unit)
        if ok and file and PURE_DAMAGE[file] then r = "damage" end
    end
    return r
end

-- membersOnly: only who is in the party (supercharge ignores open invites on purpose)
function L.roleTaken(role, membersOnly)
    local n, now = 0, GetTime()
    for _, m in ipairs(C.members()) do if memberRoleOf(m) == role then n = n + 1 end end
    if membersOnly then return n end
    for k, at in pairs(pending) do if pendingRole[k] == role and now - at < PENDING then n = n + 1 end end
    for _, m in pairs(deciding) do if m.role == role then n = n + 1 end end
    return n
end

function L.roleOpen(role, membersOnly) return math.max(0, (NEED[role] or 0) - L.roleTaken(role, membersOnly)) end

-- normal: per role only what is still open (healer 1, tank 1, damage 3), within the free spots.
-- supercharge: every match at once (at most SUPER_MAX), the first to accept gets the spot.
function L.inviteMatches()
    if not L.wantedText() then return 0 end
    if not L.listing() then note("party finder: " .. NOT_LISTED); return 0 end
    local spots, why = L.freeSpots()
    if spots <= 0 then
        if why then note("party finder: " .. why .. ", nobody invited") end
        return 0
    end
    local super = ns.db.lfgSupercharge
    local n = 0
    for _, m in ipairs(L.matches()) do
        if n >= (super and SUPER_MAX or spots) then break end
        -- the first of their roles still open; supercharge only skips roles the party members already fill
        local pick
        for _, r in ipairs(m.roles) do
            if not pick and L.roleOpen(r, super) > 0 then pick = r end
        end
        if pick then
            m.role = pick
            local r = decide(m)
            if r == "invited" or r == "asking" then n = n + 1 end
        end
    end
    return n
end

-- the category and activities to search: those of my listing (as the game's own "search my listing" does), the
-- category of its first activity, only the activities of that category
local function searchArgs(listing)
    local A, cat, acts = api(), nil, {}
    for _, id in ipairs(listing.activities) do
        local ok, info = pcall(A.GetActivityInfoTable or function() end, id)
        local c = ok and type(info) == "table" and info.categoryID or nil
        cat = cat or c or DUNGEONS
        if (c or DUNGEONS) == cat then acts[#acts + 1] = id end
    end
    return cat, acts
end

-- one press of the button or the key: search, the invites follow when the results arrive
function L.scan()
    local A = api()
    if not (A and A.Search) then return ns.print("party finder: this game version has no party finder for addons") end
    if not L.wantedText() then return note("party finder: choose who to invite first (tick a role)") end
    local listing = L.listing()
    if not listing then lastNote = nil; return note("party finder: " .. NOT_LISTED) end
    local spots, why = L.freeSpots()
    if spots <= 0 then lastNote = nil; return note("party finder: " .. (why or "no free spot")) end
    local early = L.inviteMatches()                             -- results already on hand count at once
    if searching and GetTime() - searchStart < SEARCH_TIMEOUT then return end
    local cat, acts = searchArgs(listing)
    searching, searchStart = true, GetTime()
    lastNote = nil
    ns.log("lfg", "search category " .. tostring(cat) .. " for " .. listing.name)
    clickInvites = early
    if ns.lfgFinder and early == 0 then ns.lfgFinder.status("Searching for " .. listing.name .. "...") end
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
    if mine or (ns.db.lfgWatch and L.listing()) then
        local n = L.inviteMatches()
        if mine and n == 0 and clickInvites == 0 and L.freeSpots() > 0 then note("party finder: nobody new who matches, click Find again in a moment") end
    end
end)
ns.on("LFG_LIST_SEARCH_FAILED", function()
    if searching then ns.print("party finder: search failed (the game may want a short pause between searches)") end
    searching = false
end)
ns.on("LFG_LIST_SEARCH_RESULT_UPDATED", function()
    if ns.db.lfgWatch and L.listing() then L.inviteMatches() end
end)

local function release(name, why, joined)
    for k in pairs(pending) do
        if bare(k) == bare(name) then
            if joined and pendingRole[k] then memberRole[bare(k)] = pendingRole[k] end
            pending[k], pendingRole[k] = nil, nil
            if why then note("party finder: " .. k .. " " .. why .. ", the spot is free again") end
        end
    end
    if ns.lfgFinder then ns.lfgFinder.refresh() end
end

-- someone we invited joined: the party counts them now, the invite no longer holds a spot
local function onRoster()
    local here = {}
    for _, m in ipairs(C.members()) do here[bare(m.name)] = true; release(m.name, nil, true) end
    for k in pairs(memberRole) do if not here[k] then memberRole[k] = nil end end
end
ns.on("GROUP_ROSTER_UPDATE", onRoster)
ns.on("PARTY_MEMBERS_CHANGED", onRoster)

-- the game's own lines for a refused invite, turned into patterns ("%s declines your group invitation.")
local function pattern(s)
    if type(s) ~= "string" then return nil end
    s = string.gsub(s, "([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. (string.gsub(s, "%%s", "(.+)")) .. "$"
end
local REFUSED = {
    { _G.ERR_DECLINE_GROUP_S or "%s declines your group invitation.", "declined" },
    { _G.ERR_ALREADY_IN_GROUP_S or "%s is already in a group.", "is already in a group" },
    { _G.ERR_BAD_PLAYER_NAME_S or "Cannot find player '%s'.", "could not be found" },
}
ns.on("CHAT_MSG_SYSTEM", function(_, msg)
    if type(msg) ~= "string" or next(pending) == nil then return end
    for _, r in ipairs(REFUSED) do
        local p = pattern(r[1])
        local who = p and string.match(msg, p)
        if who then return release(who, r[2]) end
    end
end)

-- my listing changed or ended: an ended listing drops the players we were still asking about
ns.on("LFG_LIST_ACTIVE_ENTRY_UPDATE", function()
    if not L.listing() then
        for name in pairs(deciding) do if ns.itemLevel then ns.itemLevel.cancel(name) end end
        deciding = {}
    end
    if ns.lfgFinder then ns.lfgFinder.refresh() end
end)

-- the key binding (Bindings.xml)
BINDING_NAME_QUESTSHARING_LFGSCAN = "Party finder: search and invite"
function QuestSharing_LFGScan() L.scan() end

local BINDING = "QUESTSHARING_LFGSCAN"
function ns.lfgKeyName() return GetBindingKey and (GetBindingKey(BINDING)) or nil end
function ns.setLfgKey(key)
    if InCombatLockdown and InCombatLockdown() then return ns.print("key bindings cannot be changed in combat") end
    if not (SetBinding and GetBindingKey) then return ns.print("this client does not allow it") end
    key = string.upper(key or "")
    if key == "" then return ns.print("party finder key: " .. (ns.lfgKeyName() or "not set")) end
    -- a refused key changes nothing: checked before the old key is unbound
    local refused = key ~= "NONE" and ns.keyRefused and ns.keyRefused(key)
    if refused then return ns.print(refused) end
    local before = key ~= "NONE" and GetBindingAction and GetBindingAction(key) or ""
    for _, k in ipairs({ GetBindingKey(BINDING) }) do SetBinding(k) end
    if key ~= "NONE" then
        if not SetBinding(key, BINDING) then return ns.print("could not bind " .. key) end
        local was = ns.keyUsedToDo and ns.keyUsedToDo(key, before, BINDING)
        if was then ns.print(was .. " (it now searches the party finder; rebind it in Key Bindings to undo)") end
    end
    local save = SaveBindings or AttemptToSaveBindings
    if save then save(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
    ns.print(key == "NONE" and "party finder key removed" or ("party finder key: " .. key .. " - searches and invites at once"))
    if ns.refreshSettings then ns.refreshSettings() end
end

function L.tooltipLines()
    local S = ns.style
    local w = L.wantedText()
    local listing = L.listing()
    local lines = { listing and ("Listed: " .. S.GREEN .. listing.name .. "|r") or (S.RED .. "Not listed|r - list your group in the party finder first"),
                    "Invites: " .. (w and (S.GOLD .. w .. "|r") or (S.RED .. "nobody chosen|r")) .. ", highest level first" }
    if ns.db.lfgSupercharge then lines[#lines + 1] = S.GOLD .. "Supercharge on|r: every match is invited at once" end
    local d = ns.db
    local need = tonumber(d.lfgMinIlvl) or 0
    lines[#lines + 1] = string.format("Levels %d-%d, item level %s", d.lfgMinLevel or 1, d.lfgMaxLevel or 60,
        need > 0 and (need .. "+" .. (d.lfgUnknown == "skip" and " (unknown: skip)" or " (unknown: invite)")) or "any")
    local spots, why = L.freeSpots()
    lines[#lines + 1] = spots > 0 and string.format("%d free spot%s", spots, spots == 1 and "" or "s") or (S.GREY .. (why or "") .. "|r")
    lines[#lines + 1] = " "
    lines[#lines + 1] = S.GREY .. "Left click: choose roles and classes, then Find|r"
    lines[#lines + 1] = S.GREY .. "Right click: all party finder settings|r"
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

-- why Find cannot work right now (nil = it can): shown on the picker
function L.blocker()
    local A = api()
    if not (A and A.Search) then return "This game version has no party finder for addons." end
    if not L.listing() then return "Not listed. Open the game's party finder, list your group for a dungeon, then Find." end
    if not L.wantedText() then return "Tick at least one role." end
    local spots, why = L.freeSpots()
    if spots <= 0 then return "Cannot invite: " .. (why or "no free spot") .. "." end
end

function L._reset() invited, pending, pendingRole, memberRole, skipped, deciding, searching, lastNote = {}, {}, {}, {}, {}, {}, false, nil end   -- for the tests
