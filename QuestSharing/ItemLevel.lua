-- ItemLevel.lua: the average item level of players, as far as the game lets an addon know it.
--   The party finder and the armory give an addon no gear of other players, so the numbers come from:
--   1. inspecting players you target or point at when they stand close (the game's inspect range, about 28 yards),
--   2. other Quest Sharing users: they answer "what is your item level?" and share the numbers they remember.
--   Numbers are remembered for 14 days (QuestSharingDB.ilvlSeen[name] = { i = level, at = time() }).
local ADDON, ns = ...
local C = ns.compat

local I = {}
ns.itemLevel = I

local PREFIX = "QSILVL"
local KEEP = 14 * 86400                 -- seconds a remembered number stays valid
local MAX_KEEP = 2000                   -- names kept at most (the oldest go first)
local FRESH = 3600                      -- no new inspect of a player inspected within the last hour
local INSPECT_GAP = 2                   -- seconds between two inspects (the game throttles them)
local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }   -- no shirt (4), no tabard (19)

local function now() return (time and time()) or math.floor(GetTime()) end

local function seen()
    ns.db.ilvlSeen = type(ns.db.ilvlSeen) == "table" and ns.db.ilvlSeen or {}
    return ns.db.ilvlSeen
end

-- one spelling per player: "Name" on my realm, "Name-Realm" elsewhere
function I.key(name, realm)
    if not name or name == "" then return nil end
    if realm and realm ~= "" then name = name .. "-" .. realm end
    local mine = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
    local base, r = string.match(name, "^([^%-]+)%-(.+)$")
    if base and mine and (r == mine or r == string.gsub(mine, "%s", "")) then return base end
    return name
end

local function levelOf(link)
    if not link then return nil end
    local lvl, loc
    if GetItemInfo then
        local ok, _, _, _, l, _, _, _, _, where = pcall(GetItemInfo, link)
        if ok then lvl, loc = l, where end
    end
    if GetDetailedItemLevelInfo then
        local ok, v = pcall(GetDetailedItemLevelInfo, link)
        if ok and type(v) == "number" and v > 0 then lvl = v end
    end
    if type(lvl) ~= "number" or lvl <= 0 then return nil end
    return lvl, loc
end

-- average level of the equipped items (a two-hand weapon with an empty off hand counts twice); nil while the
-- game has not sent enough of the items yet
function I.averageOf(unit)
    if not GetInventoryItemLink then return nil end
    local sum, n = 0, 0
    for _, slot in ipairs(SLOTS) do
        local ok, link = pcall(GetInventoryItemLink, unit, slot)
        local lvl, loc = levelOf(ok and link or nil)
        if lvl then
            sum, n = sum + lvl, n + 1
            if slot == 16 and loc == "INVTYPE_2HWEAPON" and not GetInventoryItemLink(unit, 17) then sum, n = sum + lvl, n + 1 end
        end
    end
    if n < 6 then return nil end
    return math.floor(sum / n + 0.5)
end

function I.mine() return I.averageOf("player") end

-- listeners[name] = function(level): told once when a number for that player arrives
local listeners = {}

function I.remember(name, level, at)
    name, level = I.key(name), tonumber(level)
    if not name or not level or level < 1 or level > 1000 then return end
    at = at or now()
    local s, old = seen(), seen()[name]
    if old and (old.at or 0) > at then return end
    s[name] = { i = math.floor(level + 0.5), at = at }
    local fn = listeners[name]
    listeners[name] = nil
    if fn then fn(s[name].i) end
end

-- level, seconds since it was seen (nil when unknown or older than 14 days)
function I.known(name)
    name = I.key(name)
    local e = name and seen()[name]
    if not e then return nil end
    local age = now() - (e.at or 0)
    if age > KEEP then return nil end
    return e.i, math.max(age, 0)
end

function I.count() local n = 0 for _ in pairs(seen()) do n = n + 1 end return n end

function I.forget() ns.db.ilvlSeen = {}; return true end

local function prune()
    local s, t, list = seen(), now(), {}
    for k, e in pairs(s) do
        if type(e) ~= "table" or t - (e.at or 0) > KEEP then s[k] = nil else list[#list + 1] = k end
    end
    if #list > MAX_KEEP then
        table.sort(list, function(a, b) return (s[a].at or 0) < (s[b].at or 0) end)
        for i = 1, #list - MAX_KEEP do s[list[i]] = nil end
    end
end

function I.ageText(age)
    if not age or age < 3600 then return nil end
    if age < 86400 then return string.format("seen %d h ago", math.floor(age / 3600)) end
    return string.format("seen %d d ago", math.floor(age / 86400))
end

-- Inspecting players nearby ------------------------------------------------------------------------------------
local pending, lastInspect = nil, -100

local function tryInspect(unit)
    if not (ns.db.enabled and ns.db.ilvlInspect and NotifyInspect and UnitExists and UnitExists(unit)) then return end
    if not (UnitIsPlayer and UnitIsPlayer(unit)) or (UnitIsUnit and UnitIsUnit(unit, "player")) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if _G.InspectFrame and _G.InspectFrame.IsShown and _G.InspectFrame:IsShown() then return end   -- the player is inspecting
    if CanInspect and not CanInspect(unit) then return end
    if CheckInteractDistance and not CheckInteractDistance(unit, 1) then return end
    local name = I.key(UnitName(unit))
    local _, age = I.known(name)
    if not name or (age and age < FRESH) or GetTime() - lastInspect < INSPECT_GAP then return end
    lastInspect = GetTime()
    pending = { name = name, unit = unit, guid = UnitGUID and UnitGUID(unit) }
    pcall(NotifyInspect, unit)
end
I.tryInspect = tryInspect

ns.on("INSPECT_READY", function(_, guid)
    local p = pending
    if not p or (guid and p.guid and guid ~= p.guid) then return end
    pending = nil
    if UnitGUID and p.guid and UnitGUID(p.unit) ~= p.guid then return end        -- the unit changed meanwhile
    local v = I.averageOf(p.unit)
    if v then I.remember(p.name, v); ns.log("ilvl", p.name .. " " .. v .. " (inspected)") end
end)
ns.on("PLAYER_TARGET_CHANGED", function() tryInspect("target") end)
ns.on("UPDATE_MOUSEOVER_UNIT", function() tryInspect("mouseover") end)

-- Asking other Quest Sharing users --------------------------------------------------------------------------------
--   "Q"            whispered to a player: what is your item level?   answer "M:<level>"
--   "Q:<name>"     to the party: does anyone remember <name>?          answer "S:<name>:<level>:<age seconds>"
local function send(text, channel, target)
    local f = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not f then return false end
    return (pcall(f, PREFIX, text, channel, target))
end

-- ask for a player's number; fn(level) is called if an answer arrives
function I.ask(name, fn)
    name = I.key(name)
    if not name then return end
    if fn then listeners[name] = fn end
    send("Q", "WHISPER", name)
    if C.inGroup() then send("Q:" .. name, "PARTY") end
end

function I.cancel(name) name = I.key(name); if name then listeners[name] = nil end end

ns.on("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
    if prefix ~= PREFIX or not text or not sender then return end
    sender = I.key(sender)
    if sender == I.key(C.player()) then return end
    if text == "Q" then
        local v = ns.db.ilvlShare and I.mine()
        if v then send("M:" .. v, "WHISPER", sender) end
    elseif string.sub(text, 1, 2) == "Q:" then
        local level, age = I.known(string.sub(text, 3))
        if ns.db.ilvlShare and level then send(string.format("S:%s:%d:%d", I.key(string.sub(text, 3)), level, age), "WHISPER", sender) end
    elseif string.sub(text, 1, 2) == "M:" then
        I.remember(sender, string.sub(text, 3))
    else
        local who, level, age = string.match(text, "^S:([^:]+):(%d+):(%d+)$")
        if who then I.remember(who, level, now() - tonumber(age)) end
    end
end)

local function register()
    local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if reg then pcall(reg, PREFIX) end
end
ns.on("PLAYER_LOGIN", register)
ns.on("ADDON_LOADED", function(_, name) if name == ADDON then prune() end end)
register()

function I.command()
    local v = I.mine()
    ns.print("my item level: " .. (v and tostring(v) or "unknown") .. string.format("; %d player(s) remembered", I.count()))
end

function I._reset() listeners, pending, lastInspect = {}, nil, -100 end     -- for the tests
