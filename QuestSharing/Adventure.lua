-- Player-triggered quest invitations: a direct chat question, plus an optional role-play editor.
-- Never sends chat itself, even when the other features use immediate sending.
local ADDON, ns = ...
ns.inModule("sharing")          -- Modules.lua: Settings > General > Tools can switch this off
local A, C, U, S = {}, ns.compat, ns.optionalUI, ns.style
ns.adventure = A
local W, selected, wording = nil, nil, 1
local TEMPLATES = {
    { "Hail, fellow adventurers! I seek brave companions for ", ". Who will join me and share the adventure?" },
    { "A call to willing hearts! I am setting out on ", ". Who will lend a hand and share the tale?" },
    { "The road is better with company! Seeking fellow adventurers for ", ". Who wishes to face this challenge together?" },
}
local function trim(s) return (string.gsub(string.gsub(tostring(s or ""), "^%s+", ""), "%s+$", "")) end
local function literal(s) return (string.gsub(string.gsub(s or "", "[%c]", " "), "|", "||")) end

function A.entries()
    local list = {}
    for _, e in ipairs(C.entries()) do if not C.doneByMe(e) then list[#list + 1] = e end end
    return list
end

local function live(e)
    local now = e and C.findEntry(e.questID)
    return now and not C.doneByMe(now) and now or nil
end

function A.message(e, style)
    e = live(e)
    if not e then return nil end
    local t = TEMPLATES[((tonumber(style) or 1) - 1) % #TEMPLATES + 1]
    local link = C.link(e)
    local zone = C.inArea(e) and (" in " .. literal(C.zone())) or ""
    local text = t[1] .. link .. zone .. t[2]
    if #text > 255 then text = t[1] .. link .. t[2] end
    if #text > 255 then
        local before, after = "Seeking fellow adventurers for ", ". Who will join me?"
        if #before + #link + #after > 255 then
            link = "[" .. C.safeCut(literal(e.title), 255 - #before - #after - 2) .. "]"
        end
        text = before .. link .. after
    end
    return text
end

-- Keep the quest link intact unless an unusually long title exceeds the chat limit.
function A.question(e)
    e = live(e)
    if not e then return nil end
    local before, after = "Anyone need ", "? Wanna group up?"
    local link = C.link(e)
    if #before + #link + #after > 255 then
        link = "[" .. C.safeCut(literal(e.title), 255 - #before - #after - 2) .. "]"
    end
    return before .. link .. after
end

local ROUTES = { say = "/s ", s = "/s ", yell = "/y ", y = "/y ", party = "/p ", p = "/p ",
    raid = "/raid ", guild = "/g ", g = "/g ", officer = "/o ", o = "/o ",
    instance = "/i ", i = "/i ", emote = "/e ", e = "/e " }

function A.route(input)
    local text = trim(input)
    text = string.gsub(text, "^/", "")
    if text == "" or string.lower(text) == "current" then return "", true end
    if string.lower(text) == "target" then                      -- "Whisper target": the player you have targeted
        local name, realm
        if UnitIsPlayer and UnitIsPlayer("target") and UnitName then name, realm = UnitName("target") end
        if not name or name == "" then return nil, "Target a player first to whisper them." end
        return "/w " .. name .. ((realm and realm ~= "") and ("-" .. realm) or "") .. " ", false
    end
    local route = ROUTES[string.lower(text)]
    if route then return route, false end
    local cmd, who = string.match(text, "^(%S+)%s+(.+)$")
    if cmd and (string.lower(cmd) == "w" or string.lower(cmd) == "whisper") then
        if string.find(who, "[%s|/%c]") then return nil, "Whisper needs one player name, optionally Name-Realm." end
        return "/w " .. who .. " ", false
    end
    local id = tonumber(text)
    if id and (id < 1 or id % 1 ~= 0 or id > 999) then return nil, "Enter a joined channel number, such as 1." end
    if GetChannelName then
        local ok, joined = pcall(GetChannelName, id or text)
        if ok and type(joined) == "number" and joined > 0 then return "/" .. joined .. " ", false end
        return nil, "That channel is not joined; use its current number or join it first."
    end
    if id then return "/" .. id .. " ", false end
    return nil, "Choose current, say, yell, party, raid, guild, officer, instance, whisper Name or a joined channel number."
end

function A.prepare(e, text, route)
    if not ns.db.enabled then return false, "Switch Quest Sharing on first (/qs on)." end
    e = live(e)
    if not e then return false, "Choose an unfinished quest from your quest log." end
    text = trim(text)
    if text == "" or #text > 255 then return false, "Your invitation must be 1–255 letters; shorten it before preparing chat." end
    if string.find(text, "[%c]") then return false, "Use a single line for the invitation." end
    local prefix, current = A.route(route)
    if not prefix then return false, current end
    local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    local old = box and box.GetText and box:GetText() or ""
    local usedBox
    if old ~= "" then
        if not current then return false, "Your chat already contains a draft; send or clear it before changing channels." end
        if string.find(old, C.link(e), 1, true) or string.find(old, text, 1, true) then return false, "That quest is already in the chat box." end
        if #old + 1 + #text > 255 then return false, "Your current draft plus the invitation exceeds 255 letters; send or clear the draft first." end
        if not box.SetText then return false, "This client cannot edit the active chat box." end
        box:SetText(old .. " " .. text)
        usedBox = box
    elseif current and box and box.SetText then
        box:SetText(text) -- keep its channel, whisper target and custom-channel attributes untouched
        usedBox = box
    else
        if not ChatFrame_OpenChat then return false, "This client cannot open the chat box." end
        ChatFrame_OpenChat(prefix .. text) -- an empty prefix retains the game's current/sticky chat selection
    end
    if usedBox and usedBox.SetFocus then usedBox:SetFocus() end
    ns.log("adventure", "prepared quest " .. e.questID .. " invitation; player presses Enter")
    return true
end

function A.ask(e)
    local ok, why = A.prepare(e, A.question(e), "current")
    if not ok then ns.print(why) end
    return ok, why
end

local function refresh()
    local e = selected and live({ questID = selected })
    if not e then
        local list = A.entries()
        for _, q in ipairs(list) do if C.inArea(q) then e = q; break end end
        e = e or list[1]
    end
    selected = e and e.questID or nil
    W.quest:SetText(e and ("Quest: " .. e.title) or "No unfinished quests in your quest log.")
    W.preview:SetText(e and A.message(e, wording) or "")
end

-- the chat buttons of the window: label, route (as A.route reads it), width
local CHANNELS = { { "Current chat", "current", 100 }, { "Say", "say", 56 }, { "Party", "party", 60 }, { "Raid", "raid", 56 },
                   { "Guild", "guild", 60 }, { "Channel 1", "1", 80 }, { "Whisper target", "target", 110 } }

-- the picked chat is lit with a gold rule; the others are dimmed
local function showChannel()
    for _, b in ipairs(W.channels) do
        local on = b.route == W.route
        local lit = on and 1 or 0.55
        b.bg:SetVertexColor(lit, lit, lit)
        if on then b.edge:Show() else b.edge:Hide() end
    end
end

local function build()
    if W then return true end
    local f = U.window("QuestSharingAdventure", 670, 340, "Quest invitation")
    if not f then return false end
    W = { frame = f }
    U.text(f, "Choose your quest and chat, then edit the invitation if you wish.", 24, 34, 620)
    W.quest = U.text(f, "", 24, 65, 620)
    local nextQuest = S.button(f, "Next quest", 130, function()
        local list, at = A.entries(), 0
        for i, e in ipairs(list) do if e.questID == selected then at = i end end
        selected = #list > 0 and list[at % #list + 1].questID or nil
        refresh()
    end)
    nextQuest:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -88)
    local another = S.button(f, "Another wording", 150, function() wording = wording % #TEMPLATES + 1; refresh() end)
    another:SetPoint("LEFT", nextQuest, "RIGHT", 10, 0)
    -- the chat: picked from buttons, nothing to type (A.route still takes any channel for prepare)
    U.text(f, "Chat", 24, 122, 610)
    W.route, W.channels = "current", {}
    local x = 0
    for i, c in ipairs(CHANNELS) do
        local b = S.button(f, c[1], c[3], function() W.route = c[2]; showChannel() end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 24 + x, -139)
        b.route = c[2]
        W.channels[i] = b
        x = x + c[3] + 6
    end
    showChannel()
    U.text(f, "Current chat uses whatever your chat box is set to (a whisper, World...). Channel 1 is usually General. Whisper target whispers the player you target.", 24, 165, 610)
    W.preview = U.box(f, "Your invitation (editable)", 24, 193, 610, "", 255)
    local prepare = S.button(f, "Prepare chat", 150, function()
        local ok, why = A.prepare({ questID = selected }, W.preview:GetText(), W.route)
        if ok then W.frame:Hide() else W.status:SetText(S.RED .. why .. "|r") end
    end)
    prepare:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -250)
    W.status = U.text(f, "Prepare fills the chat box; you press Enter to send.", 24, 284, 610)
    return true
end

function A.open(e)
    if not ns.db.enabled then ns.print("switch Quest Sharing on first (/qs on)"); return false end
    if e and not live(e) then ns.print("choose an unfinished quest from your quest log"); return false end
    if not build() then return false end
    selected, wording = e and e.questID or nil, 1
    refresh()
    W.status:SetText("Prepare fills the chat box; you press Enter to send.")
    W.frame:Show()
    return true
end

function A.command(arg)
    arg = trim(arg)
    if arg == "" then return A.open() end
    local id = tonumber(arg) or tonumber(string.match(arg, "|Hquest:(%d+):"))
    local found
    for _, e in ipairs(A.entries()) do
        if (id and e.questID == id) or (not id and string.lower(e.title) == string.lower(arg)) then found = e; break end
    end
    if not found then ns.print("that unfinished quest is not in your log; use /qs adventure to choose one"); return false end
    return A.open(found)
end

function A._window() return W end
function A.close() if W then W.frame:Hide() end end
ns.on("QUEST_LOG_UPDATE", function()
    if W and W.frame:IsShown() and selected and not live({ questID = selected }) then
        W.quest:SetText("Selected quest finished or left your log; choose Next quest.")
        W.status:SetText("Choose another unfinished quest before preparing an invitation.")
    end
end)
