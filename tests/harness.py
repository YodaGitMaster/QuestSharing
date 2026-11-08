"""A mock of the WoW API (modern and classic quest styles) plus a loader for the real addon files,
run in a Lua 5.1 interpreter (the same Lua version the game uses).   Needs:  pip install lupa"""
import pathlib

from lupa.lua51 import LuaRuntime

ADDON_DIR = pathlib.Path(__file__).resolve().parent.parent / "QuestSharing"
# the load order is read from the .toc, exactly as the game does it
FILES = [line.strip() for line in (ADDON_DIR / "QuestSharing.toc").read_text().splitlines()
         if line.strip().endswith(".lua")]

MOCK = r'''
NOW = 1000
FRAMES, SENT, PRINTED, OPENED, PUSHED = {}, {}, {}, {}, {}
UNKNOWN_EVENTS = {}
SELECTED = 0
ON_QUEST = {}                  -- ON_QUEST["party1"][questID] = true
SHIFT, CTRL, ALT = false, false, false
GROUP = { members = {} }
INSTANCE_GROUP, RAID = false, false
ZONE = "Elwynn Forest"
QUESTS = {}

ERR_QUEST_PUSH_SUCCESS_S = "Sharing quest with %s."
ERR_QUEST_PUSH_ACCEPTED_S = "%s has accepted your quest."
ERR_QUEST_PUSH_DECLINED_S = "%s has declined your quest."
ERR_QUEST_PUSH_ONQUEST_S = "%s is already on that quest."
ERR_QUEST_PUSH_ALREADY_DONE_S = "%s has already completed that quest."
ERR_QUEST_PUSH_BUSY_S = "%s is busy."
ERR_QUEST_PUSH_LOG_FULL_S = "%s's quest log is full."
ERR_QUEST_PUSH_DEAD_S = "%s is dead."
ERR_QUEST_PUSH_TIMER_EXPIRED_S = "%s did not respond."
LE_PARTY_CATEGORY_INSTANCE = 2

UIParent = {}
UISpecialFrames = {}
OPTIONS_ADDED = {}
TOOLTIP = {}
GameTooltip = {
    SetOwner = function() end,
    SetText = function(_, t) TOOLTIP.text = t end,
    Show = function() TOOLTIP.shown = true end,
    Hide = function() TOOLTIP.shown = false end,
}
function GetTime() return NOW end

ADDON_SENT, PREFIXES = {}, {}

local function newObject()
    local o = { scripts = {}, events = {}, shown = true, text = "", point = { "CENTER", nil, "CENTER", 0, 0 } }
    function o:SetScript(n, fn) self.scripts[n] = fn end
    function o:RegisterEvent(e)
        if UNKNOWN_EVENTS[e] then error("unknown event " .. e) end
        self.events[e] = true
    end
    function o:Show() self.shown = true end
    function o:Hide() self.shown = false end
    function o:IsShown() return self.shown end
    function o:SetText(t) self.text = t end
    function o:GetText() return self.text end
    function o:CreateFontString() return newObject() end
    function o:SetPoint(p, rel, rp, x, y) self.point = { p, rel, rp, x or 0, y or 0 } end
    function o:GetPoint() return unpack(self.point) end
    function o:SetHeight(h) self.height = h end
    function o:SetWidth(w) self.width = w end
    for _, name in ipairs({ "SetBackdrop", "SetBackdropColor", "SetFrameStrata", "SetMovable", "EnableMouse",
                            "RegisterForDrag", "SetJustifyH", "StartMoving", "StopMovingOrSizing" }) do
        o[name] = function() end
    end
    return o
end

function CreateFrame()
    local f = newObject()
    FRAMES[#FRAMES + 1] = f
    return f
end

function FIRE(event, ...)
    for _, f in ipairs(FRAMES) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

function ADVANCE(seconds)
    for _ = 1, math.floor(seconds * 10 + 0.5) do
        NOW = NOW + 0.1
        for _, f in ipairs(FRAMES) do
            if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.1) end
        end
    end
end

function hooksecurefunc(a, b, c)
    local tbl, name, fn
    if type(a) == "string" then tbl, name, fn = _G, a, b else tbl, name, fn = a, b, c end
    local orig = tbl[name]
    assert(orig, "cannot hook missing function " .. tostring(name))
    tbl[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end

function SendChatMessage(msg, channel) SENT[#SENT + 1] = { msg = msg, channel = channel } end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) PRINTED[#PRINTED + 1] = m end }
function ChatFrame_OpenChat(text) OPENED[#OPENED + 1] = text end
SlashCmdList = {}
function IsShiftKeyDown() return SHIFT end
function IsControlKeyDown() return CTRL end
function IsAltKeyDown() return ALT end
function GetBuildInfo() return "1.60.1", "70862", "Nov 6 2026", 16001 end

function IsInGroup(cat) if cat == 2 then return INSTANCE_GROUP end return #GROUP.members > 0 end
function IsInRaid() return RAID end
function GetNumSubgroupMembers() return #GROUP.members end
function UnitName(unit)
    local i = tonumber(string.match(unit, "^party(%d)$") or "")
    if i then return GROUP.members[i] end
    if unit == "player" then return "Me" end
end
function GetRealZoneText() return ZONE end

-- chat edit box for the shift-click link hook
EDITBOX = { text = "" }
function EDITBOX:Insert(t) self.text = self.text .. t end
ACTIVE_BOX = nil
function ChatEdit_GetActiveWindow() return ACTIVE_BOX end
function ChatEdit_InsertLink(text) if ACTIVE_BOX then ACTIVE_BOX:Insert(text) end return true end

function BYID(id) for _, q in ipairs(QUESTS) do if q.id == id then return q end end end
function SET_PARTY(list) GROUP.members = list end
function LINK(q) return "|cffffff00|Hquest:" .. q.id .. ":" .. (q.level or 1) .. "|h[" .. q.title .. "]|h|r" end

function DEFAULT_QUESTS()
    QUESTS = {
        { header = "Elwynn Forest" },
        { id = 100, title = "Wolves Among Us", level = 3, objectives = {
            { text = "Wolf slain: 3/8", finished = false, numFulfilled = 3, numRequired = 8 },
            { text = "Wolf Pelt: 0/4", finished = false, numFulfilled = 0, numRequired = 4 } } },
        { id = 101, title = "Report to Goldshire", level = 2, complete = true, objectives = {
            { text = "Speak with Marshal Dughan", finished = true } } },
        { id = 102, title = "A Personal Quest", level = 2, pushable = false, objectives = {} },
        { header = "Westfall" },
        { id = 200, title = "The Defias Brotherhood", level = 10, objectives = {
            { text = "Defias Thief slain: 1/5", finished = false, numFulfilled = 1, numRequired = 5 } } },
    }
end

function MODERN_API()
    C_QuestLog = {
        GetNumQuestLogEntries = function() return #QUESTS end,
        GetInfo = function(i)
            local q = QUESTS[i]
            if not q then return nil end
            if q.header then return { title = q.header, isHeader = true } end
            return { title = q.title, questID = q.id, level = q.level, isHeader = false, isHidden = q.hidden or false }
        end,
        IsComplete = function(id) local q = BYID(id); return q and q.complete or false end,
        GetQuestObjectives = function(id) local q = BYID(id); return q and q.objectives or {} end,
        IsPushableQuest = function(id) local q = BYID(id); return q ~= nil and q.pushable ~= false end,
        SetSelectedQuest = function(id) SELECTED = id end,
        GetSelectedQuest = function() return SELECTED end,
        IsUnitOnQuest = function(unit, id) return (ON_QUEST[unit] and ON_QUEST[unit][id]) and true or false end,
    }
    function QuestLogPushQuest() PUSHED[#PUSHED + 1] = SELECTED end
    function GetQuestLink(id) return LINK(BYID(id)) end
    Settings = {
        RegisterCanvasLayoutCategory = function(f, name) return { frame = f, name = name } end,
        RegisterAddOnCategory = function(cat) OPTIONS_ADDED[#OPTIONS_ADDED + 1] = cat end,
    }
    C_ChatInfo = {
        RegisterAddonMessagePrefix = function(p) PREFIXES[p] = true; return true end,
        SendAddonMessage = function(prefix, text, channel) ADDON_SENT[#ADDON_SENT + 1] = { prefix = prefix, text = text, channel = channel } end,
    }
end

-- The quest tracker and quest distances -------------------------------------------------------------------
IN_COMBAT, IN_INSTANCE = false, false
WATCHED, WATCH_LOG, DIST, OFF_CONTINENT, DISTANCE_CALLS = {}, {}, {}, {}, 0
function InCombatLockdown() return IN_COMBAT end
function IsInInstance() return IN_INSTANCE, "party" end

function TRACKER_MODERN()
    Constants = { QuestWatchConsts = { MAX_QUEST_WATCHES = 25 } }
    C_QuestLog.GetQuestWatchType = function(id) return WATCHED[id] and 0 or nil end
    C_QuestLog.AddQuestWatch = function(id) WATCHED[id] = true; WATCH_LOG[#WATCH_LOG + 1] = "+" .. id end
    C_QuestLog.RemoveQuestWatch = function(id) WATCHED[id] = nil; WATCH_LOG[#WATCH_LOG + 1] = "-" .. id end
    C_QuestLog.GetDistanceSqToQuest = function(id)
        DISTANCE_CALLS = DISTANCE_CALLS + 1
        local d = DIST[id]
        if d == nil then return nil end
        return d, not OFF_CONTINENT[id]
    end
end

function TRACKER_CLASSIC()                       -- no distance information on this client
    MAX_WATCHABLE_QUESTS = 5
    function IsQuestWatched(i) return WATCHED[QUESTS[i].id] and true or false end
    function AddQuestWatch(i) WATCHED[QUESTS[i].id] = true; WATCH_LOG[#WATCH_LOG + 1] = "+" .. QUESTS[i].id end
    function RemoveQuestWatch(i) WATCHED[QUESTS[i].id] = nil; WATCH_LOG[#WATCH_LOG + 1] = "-" .. QUESTS[i].id end
end

function CLASSIC_API()
    function GetNumQuestLogEntries() return #QUESTS end
    function GetQuestLogTitle(i)
        local q = QUESTS[i]
        if not q then return nil end
        if q.header then return q.header, 0, nil, true, false, nil, nil, nil end
        return q.title, q.level, nil, false, false, q.complete and 1 or nil, nil, q.id
    end
    function GetNumQuestLeaderBoards(i) return #(QUESTS[i].objectives or {}) end
    function GetQuestLogLeaderBoard(j, i) local o = QUESTS[i].objectives[j]; return o.text, "monster", o.finished end
    function SelectQuestLogEntry(i) SELECTED = i end
    function GetQuestLogSelection() return SELECTED end
    function GetQuestLogPushable() local q = QUESTS[SELECTED]; return q ~= nil and q.pushable ~= false end
    function IsUnitOnQuest(index, unit)
        local q = QUESTS[index]
        return (q and ON_QUEST[unit] and ON_QUEST[unit][q.id]) and 1 or nil
    end
    function QuestLogPushQuest() PUSHED[#PUSHED + 1] = QUESTS[SELECTED].id end
    function GetQuestLink(i) return LINK(QUESTS[i]) end
    function InterfaceOptions_AddCategory(f) OPTIONS_ADDED[#OPTIONS_ADDED + 1] = f end
    function RegisterAddonMessagePrefix(p) PREFIXES[p] = true end                 -- returns nothing, like the old API
    function SendAddonMessage(prefix, text, channel) ADDON_SENT[#ADDON_SENT + 1] = { prefix = prefix, text = text, channel = channel } end
end

-- Fake quest logs, shaped like the real ones ---------------------------------------------------------------
function CLASSIC_QUESTLOG(slots)
    QUESTS_DISPLAYED = slots or 6
    QuestLogFrame = newObject()
    for i = 1, QUESTS_DISPLAYED do
        local b = newObject()
        b.id = i
        function b:GetID() return self.id end
        _G["QuestLogTitle" .. i] = b
    end
    function QuestLog_Update()                       -- what Blizzard's function does: titles from the log
        for i = 1, QUESTS_DISPLAYED do
            local b, q = _G["QuestLogTitle" .. i], QUESTS[i]
            if q then
                b.shown, b.isHeader, b.id = true, q.header ~= nil, i
                b:SetText(" " .. (q.header or q.title))
            else b.shown = false end
        end
    end
end

function MODERN_QUESTLOG()
    QuestScrollFrame = { titleFramePool = { active = {} } }
    function QuestScrollFrame.titleFramePool:EnumerateActive() return pairs(self.active) end
    function QuestLogQuests_Update()
        local pool = QuestScrollFrame.titleFramePool
        pool.active = {}
        for _, q in ipairs(QUESTS) do
            if q.id then
                local b = { questID = q.id, Text = newObject() }
                b.Text:SetText(q.title)
                pool.active[b] = true
            end
        end
    end
end
'''


class Game:
    """One Lua world with the mock API and the real addon loaded into it."""

    def __init__(self, style="modern", pre="", fresh=False):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.execute("DEFAULT_QUESTS()")
        self.lua.execute("MODERN_API()" if style == "modern" else "CLASSIC_API()")
        self.lua.execute("TRACKER_MODERN()" if style == "modern" else "TRACKER_CLASSIC()")
        if pre:
            self.lua.execute(pre)
        self.style, self.fresh = style, fresh
        self.load()

    def load(self):
        self.lua.execute("NS = {}")
        loader = self.lua.eval("function(name, code) local f = assert(loadstring(code, name)); f('QuestSharing', NS) end")
        for name in FILES:
            loader(name, (ADDON_DIR / name).read_text())
        self.lua.execute("NS.pick = function(list) return list[1] end")        # no randomness in tests

    # -- helpers -----------------------------------------------------------------------------
    def run(self, code):
        return self.lua.execute(code)

    def eval(self, code):
        return self.lua.eval(code)

    def fire(self, event, *args):
        self.lua.eval("FIRE")(event, *args)

    def advance(self, seconds):
        self.lua.eval("ADVANCE")(seconds)

    def sent(self):
        return [(m["msg"], m["channel"]) for m in self.lua.eval("SENT").values()]

    def printed(self):
        return list(self.lua.eval("PRINTED").values())

    def opened(self):
        return list(self.lua.eval("OPENED").values())

    def pushed(self):
        return list(self.lua.eval("PUSHED").values())

    def watched(self):
        return sorted(int(k) for k in self.lua.eval("WATCHED").keys())

    def watch_log(self):
        return list(self.lua.eval("WATCH_LOG").values())

    def set_dist(self, **kw):
        """set_dist(q100=400, q101=900): squared distances in yards; None removes the entry."""
        self.run("DIST = {%s}" % ", ".join(f"[{k[1:]}] = {v}" for k, v in kw.items()))

    def peer(self, sender, text, prefix="QSHARE", channel="PARTY"):
        """Another player's Quest Sharing addon sends us a message."""
        self.fire("CHAT_MSG_ADDON", prefix, text, channel, sender)

    def addon_sent(self):
        return [m["text"] for m in self.lua.eval("ADDON_SENT").values()]

    def slash(self, text):
        self.lua.eval('function(t) SlashCmdList["QUESTSHARING"](t) end')(text)

    def start(self):
        """World entered, not grouped yet. Unless fresh=True the saved settings start with the tracker and the
        panel off, as in the first versions, so the older tests keep testing what they were written for."""
        if not self.fresh:
            self.run("QuestSharingDB = { near = false, panel = false, dbVersion = 2 }")
        self.fire("ADDON_LOADED", "QuestSharing")
        self.fire("PLAYER_ENTERING_WORLD")

    def join_party(self, names):
        self.run("SET_PARTY({%s})" % ", ".join('"%s"' % n for n in names))
        self.fire("GROUP_ROSTER_UPDATE")

    def leave_party(self):
        self.run("SET_PARTY({})")
        self.fire("GROUP_ROSTER_UPDATE")

    def reply(self, text):
        self.fire("CHAT_MSG_SYSTEM", text)
