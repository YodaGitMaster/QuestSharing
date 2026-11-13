-- Menu.lua: the small menu a right click on a quest in the Party quests window opens.
--   Tell the party how I am doing    "I still need Wolf Pelt 2/4 (Wolf Pelt at 42.3, 61.8). What about you?"
--   Offer it to the party            the quest popup, for whoever does not have it (the same as a left click)
--   Tell them where to get it        with Questie: "Bob: [quest] starts at Marshal Dughan in Elwynn Forest (42.1, 65.9)"
--   Trace back the chain             with Questie, one line: every quest before it, where the first and this one start
--   How to do it                     with Questie, one line: what is still open and where, then where to turn it in
--   Focus it on my map               the game's quest marker and arrow on this quest
--   Open it in the quest log
-- A line that cannot be used right now is grey and says why. Our own small frame (not the game's dropdown menus,
-- which are known to cause "action blocked" problems for addons). Esc, a choice, or moving away closes it.
local ADDON, ns = ...
local C = ns.compat
local S = ns.style

local menu, lines
local WIDTH, LINE_H = 240, 20

-- who in the party does not have quest e (by the same rules as the grid)
local function lacking(e)
    local out = {}
    for _, m in ipairs(C.members()) do
        local st = ns.memberStatus and ns.memberStatus(m, e) or "unknown"
        if st == "no" or st == "cant" or st == "unknown" then out[#out + 1] = m.name end
    end
    return out
end

-- "Bob and Cy: [Wolves Among Us] starts at Marshal Dughan in Elwynn Forest (42.1, 65.9), after "A Threat Within"."
function ns.whereMessage(e)
    local where = ns.questie and ns.questie.available() and ns.questie.whereText(e.questID)
    if not where then return nil end
    local names = lacking(e)
    local who = (#names == 1 and names[1]) or (#names > 1 and (table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names])) or nil
    local msg = (who and (who .. ": ") or "") .. C.link(e) .. " " .. where .. "."
    return C.safeCut(msg, 255)
end

function ns.tellWhere(e)
    local msg = ns.whereMessage(e)
    if not msg then ns.print("Questie does not know where this quest starts (or Questie is not installed)"); return false end
    if not C.inGroup() then ns.print(msg .. "  (not sent: you are not in a party)"); return false end
    if ns.db.mode == "send" and ns.chatAllowed(C.channel()) then
        ns.trying("telling the party where to get a quest", "chat")
        SendChatMessage(msg, C.channel())
    else
        ns.addToChatBox(msg, C.link(e))                       -- typed into the chat box for you: press Enter
    end
    return true
end

-- "[Wolves Among Us] (level 5+): 2 quests before it: "A Threat Within" at ... > ... > then this one at ..." (one line)
function ns.chainMessage(e)
    local q = ns.questie
    local text = q and q.available() and q.chainText and q.chainText(e.questID, C.link(e))
    return text and C.safeCut(text, 255) or nil
end

-- In a party: to the party (sent at once or into the chat box, like the other messages); alone: only shown to you
function ns.traceBack(e)
    local msg = ns.chainMessage(e)
    if not msg then ns.print("Questie does not know this quest (or Questie is not installed)"); return false end
    ns.log("trace", msg)
    if not C.inGroup() then ns.print(msg); return true end
    if ns.db.mode == "send" and ns.chatAllowed(C.channel()) then
        ns.trying("telling the party the chain of a quest", "chat")
        SendChatMessage(msg, C.channel())
    else
        ns.addToChatBox(msg, C.link(e))
    end
    return true
end

-- "[Wolves Among Us]: kill Kobold Vermin (Elwynn Forest 40.1, 80.2); ...; then turn in at ..." (one line). Objectives
-- the game already counts as finished are left out.
function ns.howMessage(e)
    local q = ns.questie
    if not (q and q.available() and q.howText) then return nil end
    local finished = {}
    for _, o in ipairs(C.objectives(e)) do
        if o.finished and o.text then finished[#finished + 1] = string.lower(o.text) end
    end
    local function done(name)
        name = string.lower(name or "")
        for _, txt in ipairs(finished) do if name ~= "" and string.find(txt, name, 1, true) then return true end end
        return false
    end
    local text = q.howText(e.questID, C.link(e), done, e.complete)
    return text and C.safeCut(text, 255) or nil
end

-- In a party: to the party (sent at once or into the chat box, like the other messages); alone: only shown to you
function ns.howTo(e)
    local msg = ns.howMessage(e)
    if not msg then ns.print("Questie does not know this quest (or Questie's data is not loaded)"); return false end
    ns.log("how", msg)
    if not C.inGroup() then ns.print(msg); return true end
    if ns.db.mode == "send" and ns.chatAllowed(C.channel()) then
        ns.trying("telling the party how to do a quest", "chat")
        SendChatMessage(msg, C.channel())
    else
        ns.addToChatBox(msg, C.link(e))
    end
    return true
end

function ns.focusQuest(e)
    if not (ns.canPin and ns.canPin()) then ns.print("this client cannot focus a quest on the map"); return false end
    ns.trying("focusing the quest on your map")
    local ok = pcall(C_SuperTrack.SetSuperTrackedQuestID, e.questID)
    if ok then
        if ns.pinPauseFor then ns.pinPauseFor(60) end           -- your choice: the "nearest quest" pin waits a minute
        ns.print(C.link(e) .. " is now the focus on your map")
    end
    return ok
end

-- The old quest log window is opened at the quest. A quest log that lives inside the WORLD MAP is never opened from
-- addon code: the map would then build its pins in the addon's name and the game refuses part of that
-- ("tried to call the protected function SetPassThroughButtons()"). There the quest is selected and you open it.
function ns.mapQuestLog() return QuestLogFrame == nil end

function ns.openInLog(e)
    if QuestLogFrame and ShowUIPanel then
        ns.trying("opening the quest log")
        pcall(ShowUIPanel, QuestLogFrame)
        if QuestLog_SetSelection and e.index then pcall(QuestLog_SetSelection, e.index) end
        if QuestLog_Update then pcall(QuestLog_Update) end
        return true
    end
    if C_QuestLog and C_QuestLog.SetSelectedQuest then
        pcall(C_QuestLog.SetSelectedQuest, e.questID)
        ns.print(C.link(e) .. " is selected: open your quest log (L) or the map (M) to see it")
        return true
    end
    ns.print("this client has no quest log to open")
    return false
end

-- the lines of the menu for quest e: { text, run, why (nil = usable) }
function ns.questMenuItems(e)
    local inParty, raid = C.inGroup(), C.inRaid()
    local missing = lacking(e)
    local items = {}
    local function add(text, run, why) items[#items + 1] = { text = text, run = run, why = why } end
    add("Tell the party how I am doing", function() ns.askParty(e) end, (not inParty) and "you are not in a party" or nil)
    add("Seek fellow adventurers", function() ns.adventure.open(e) end,
        C.doneByMe(e) and "you have finished this quest" or nil)
    add("Offer it to the party", function() ns.offerQuest(e) end,
        (not inParty and "you are not in a party") or (raid and "not in a raid") or (not C.pushable(e) and "the game does not let this quest be shared")
        or (#missing == 0 and "everybody has it") or nil)
    local qOk = ns.questie and ns.questie.available()
    add("Tell them where to get it", function() ns.tellWhere(e) end,
        (not qOk and ns.questie.whyMissing()) or (not inParty and "you are not in a party") or (#missing == 0 and "everybody has it")
        or (not ns.whereMessage(e) and "Questie does not know where it starts") or nil)
    add("How to do it", function() ns.howTo(e) end,
        (not qOk and ns.questie.whyMissing()) or (not ns.howMessage(e) and "Questie does not know this quest") or nil)
    add("Trace back the chain", function() ns.traceBack(e) end,
        (not qOk and ns.questie.whyMissing()) or (not ns.chainMessage(e) and "Questie does not know this quest") or nil)
    add("Focus it on my map", function() ns.focusQuest(e) end, (not (ns.canPin and ns.canPin())) and "not on this client" or nil)
    add(ns.mapQuestLog() and "Select it in the quest log" or "Open it in the quest log", function() ns.openInLog(e) end, nil)
    return items
end

local function close() if menu then menu:Hide() end end
ns.closeQuestMenu = close

local function build()
    if menu then return menu end
    local f = S.window("QuestSharingMenu", WIDTH, 40, "", "hud")
    if not f then return nil end
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    lines = {}
    for i = 1, 8 do
        local b = S.button(f, "", WIDTH - 16, function() ns.questMenuPick(i) end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -26 - (i - 1) * (LINE_H + 2))
        lines[i] = b
    end
    local away = 0
    f:SetScript("OnUpdate", function(self, dt)                   -- the mouse went elsewhere for a while: close it
        if MouseIsOver and not MouseIsOver(self) then
            away = away + (dt or 0)
            if away > 2.5 then away = 0; self:Hide() end
        else
            away = 0
        end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestSharingMenu") end          -- Esc closes it
    f:Hide()
    menu = f
    return f
end

function ns.openQuestMenu(e)
    if not e then return end
    local f = build()
    if not f then return end
    f.entry, f.items = e, ns.questMenuItems(e)
    f.title:SetText(S.GOLD .. e.title .. "|r")
    for i, b in ipairs(lines) do
        local it = f.items[i]
        if it then
            b:SetLabel(it.why and (S.GREY .. it.text .. "|r") or it.text)
            b.tipText = it.why
            b:Show()
        else
            b:Hide()
        end
    end
    f:SetHeight(32 + #f.items * (LINE_H + 2))
    local x, y = 400, 400
    if GetCursorPosition and UIParent then
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        x, y = cx / s, cy / s
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + 8, y + 8)
    f:Show()
end

function ns.questMenuPick(i)
    local it = menu and menu.items and menu.items[i]
    if not it then return end
    if it.why then ns.print(it.text .. ": " .. it.why); return end
    close()
    it.run()
end

function ns._questMenu() return menu, lines end                -- for the tests
