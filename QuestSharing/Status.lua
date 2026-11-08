-- Status.lua: what to say about a quest you click in the tracker, and the hooks that notice the click.
local ADDON, ns = ...
local C = ns.compat

local ICON = "{rt1}"        -- the star raid icon; the only picture a chat message can carry
local LOCAL_ICON = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14|t"
local DONE_TEXT = { "I'm done with this one, ready to turn in!",
                    "All done here, I just need to hand it in :)",
                    "Finished this one, only the turn-in is left!" }

-- Returns text, isDone
function ns.statusText(e)
    local objs = C.objectives(e)
    local allDone = #objs > 0
    for _, o in ipairs(objs) do if not o.finished then allDone = false end end
    if e.complete or allDone then return ns.pick(DONE_TEXT), true end

    local parts = {}
    for _, o in ipairs(objs) do
        if not o.finished then
            if o.have and o.need then
                parts[#parts + 1] = string.format("%s %d/%d", o.name or o.text, o.have, o.need)
            else
                parts[#parts + 1] = o.text
            end
        end
    end
    if #parts == 0 then return "still working on it", false end
    return "still need: " .. table.concat(parts, ", "), false
end

local function haveSuffix(names)
    if #names == 0 then return "" end
    if #names == 1 then return " (" .. names[1] .. " has it too!)" end
    return " (" .. table.concat(names, ", ") .. " have it too!)"
end

-- icon + quest link + status + who else has it; always fits in one chat message.
-- forBox: for the chat box, without the {rt1} code (the game only turns it into a star once sent; in the box it is
-- just odd text)
function ns.statusMessage(e, forBox)
    local names = ns.partyHas(e)
    local icon = (#names > 0 and not forBox) and (ICON .. " ") or ""
    local link = C.link(e)
    local text, done = ns.statusText(e)
    local suffix = (done and "" or haveSuffix(names)) .. (ns.spotText and ns.spotText(e) or "")   -- and where the items were
    local msg = icon .. link .. " - " .. text .. suffix
    if #msg > 250 then                      -- too many objectives: cut the list, keep the link and the suffix
        local room = 250 - #(icon .. link .. " - ") - #suffix - 3
        msg = icon .. link .. " - " .. C.safeCut(text, math.max(room, 0) + 3) .. suffix
    end
    return msg
end

-- Delivery ------------------------------------------------------------------------------------------
function ns.deliver(msg)
    local mode = ns.db.mode
    if mode == "send" and C.inGroup() then
        SendChatMessage(msg, C.channel())
    elseif mode == "box" and ChatFrame_OpenChat then
        ChatFrame_OpenChat((C.inGroup() and C.slashFor(C.channel()) or "") .. msg)
    else
        ns.print((string.gsub(msg, "{rt1}", LOCAL_ICON)))
    end
end

-- Put a status in the chat box. If the box is already open with text (an earlier quest, or something you typed), the
-- new one is ADDED after it instead of replacing it, so you can click several quests and send them as one message.
local SEP = " + "
function ns.addToChatBox(msg, link)
    local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    local old = (box and box.GetText and box:GetText()) or ""
    if box and box.SetText and old ~= "" then
        if link and string.find(old, link, 1, true) then
            ns.print("that quest is already in the chat box")
            return false
        end
        local new = old .. SEP .. msg
        if #new > 255 then
            ns.print("the chat box is full (255 letters): press Enter to send it, then click the next quest")
            return false
        end
        box:SetText(new)
        return true
    end
    if not ChatFrame_OpenChat then return false end
    ChatFrame_OpenChat((C.inGroup() and C.slashFor(C.channel()) or "") .. msg)
    return true
end

-- What a click on a quest does (the game's tracker and our Party quests window): by default it goes into the chat box
local lastShare = { id = nil, at = -10 }
function ns.shareStatus(e)
    if not e then return false end
    local mode = ns.db.mode
    if mode == "box" and ChatFrame_OpenChat then return ns.addToChatBox(ns.statusMessage(e, true), C.link(e)) end
    if mode == "send" and lastShare.id == e.questID and GetTime() - lastShare.at < 1 then return false end   -- a double click
    lastShare.id, lastShare.at = e.questID, GetTime()
    ns.deliver(ns.statusMessage(e))
    return true
end

local function modifierDown()
    return (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown())
        or (IsAltKeyDown and IsAltKeyDown())
end

local function questClicked(questID, index, button)
    local d = ns.db
    if not d.enabled or not d.click then return end
    if button and button ~= "LeftButton" then return end
    if modifierDown() then return end            -- shift-click inserts a link: the link hook handles that
    local e = C.findEntry(questID, index)
    if e then ns.shareStatus(e) end
end

-- Hooks ---------------------------------------------------------------------------------------------
ns.hooks = ns.hooks or {}

local function install()
    if not ns.hooks.tracker then
        local mod = (QUEST_TRACKER_MODULE and QUEST_TRACKER_MODULE.OnBlockHeaderClick and QUEST_TRACKER_MODULE)
            or (QuestObjectiveTracker and QuestObjectiveTracker.OnBlockHeaderClick and QuestObjectiveTracker)
        if mod then
            ns.hooks.tracker = pcall(hooksecurefunc, mod, "OnBlockHeaderClick", function(_, block, button)
                questClicked(block and block.id, nil, button)
            end)
        end
    end
    if not ns.hooks.watchframe and WatchFrameLinkButtonTemplate_OnClick then
        ns.hooks.watchframe = pcall(hooksecurefunc, "WatchFrameLinkButtonTemplate_OnClick", function(self, button)
            if self and self.type == "QUEST" then questClicked(nil, self.index, button) end
        end)
    end
    if not ns.hooks.insertlink and ChatEdit_InsertLink then
        ns.hooks.insertlink = pcall(hooksecurefunc, "ChatEdit_InsertLink", function(text)
            if not (ns.db.enabled and ns.db.link) then return end
            local id = string.match(tostring(text or ""), "|Hquest:(%d+)")
            local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
            if not (id and box) then return end
            local e = C.findEntry(tonumber(id))
            if not e then return end
            local names = ns.partyHas(e)
            local text, done = ns.statusText(e)
            box:Insert(" - " .. text .. (done and "" or haveSuffix(names)))
        end)
    end
end

ns.on("PLAYER_LOGIN", install)
ns.on("PLAYER_ENTERING_WORLD", install)
ns.on("ADDON_LOADED", install)         -- the tracker can load after us
install()

-- /qs probe -----------------------------------------------------------------------------------------
function ns.probe()
    local function yn(v) return v and "yes" or "NO" end
    local ok, _, _, _, iface = pcall(GetBuildInfo)
    ns.print("game interface " .. tostring(ok and iface or "?") .. ", quest API: " ..
             (C.modern and "modern (C_QuestLog)" or "classic (GetQuestLogTitle)"))
    ns.print("see who is on a quest: " .. yn(C_QuestLog and C_QuestLog.IsUnitOnQuest or IsUnitOnQuest) ..
             " | push a quest: " .. yn(QuestLogPushQuest) ..
             " | chat box helper: " .. yn(ChatFrame_OpenChat))
    ns.print("game reply messages recognised: " .. ns.patternCount() .. " (expect about 8 or more)")
    ns.print("click hooks: tracker " .. yn(ns.hooks.tracker) .. ", watch frame " .. yn(ns.hooks.watchframe) ..
             ", chat links " .. yn(ns.hooks.insertlink))
    if not (ns.hooks.tracker or ns.hooks.watchframe) then
        ns.print("-> clicking in the tracker is not supported on this client yet; shift-click a quest link still works")
    end
    ns.print("tracker control (/qs near): " .. yn(C.canWatch()) .. " | distance to quests: " .. yn(C.hasDistance()) ..
             " | mode in use: " .. ns.nearMode() .. " | tracker holds up to " .. C.maxWatch())
    ns.print("settings window: /qs settings | entry in the game's options: " .. yn(ns.hooks.optionsEntry))
    ns.print("friends (beta): add call " .. yn(C.canAddFriend()) .. " | reply messages recognised: " ..
             ns.friendPatternCount() .. " | friends " .. C.friendCount() .. "/" .. C.maxFriends() ..
             " | automatic: " .. (ns.db.friends and "on" or "off"))
    local bound = GetBindingKey and GetBindingKey("QUESTSHARING_QUICKCHAT")
    ns.print("quick chat wheel: key " .. tostring(bound or "NOT SET (/qs key V)") .. " | an addon can set keys: " ..
             yn(SetBinding) .. " | mode " .. tostring(ns.db.quickMode) .. " | sends to " .. tostring(ns.db.quickChannel))
    local peers = 0
    for _ in pairs(ns.peers or {}) do peers = peers + 1 end
    ns.print("sync with other Quest Sharing users: " .. (ns.db.sync and "on" or "off") .. ", message prefix registered: " ..
             yn(ns.prefixRegistered) .. ", synced players in your party: " .. peers)
    ns.print("quest log markers: classic " .. yn(ns.hooks.qlClassic) .. ", modern " .. yn(ns.hooks.qlModern) ..
             " (the panel, /qs panel, works either way)")
    local members, entries = C.members(), C.entries()
    ns.print(string.format("you have %d quest(s); %d in %s; party members: %d",
        #entries, (function() local n = 0 for _, e in ipairs(entries) do if C.inArea(e) then n = n + 1 end end return n end)(),
        C.zone(), #members))
    if members[1] and entries[1] then
        local r = C.unitOnQuest(members[1].unit, entries[1])
        ns.print(string.format("live test: is %s on '%s'? -> %s", members[1].name, entries[1].title, tostring(r)))
    end
end
