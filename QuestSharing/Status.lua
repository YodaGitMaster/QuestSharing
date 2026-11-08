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

-- icon + quest link + status + who else has it; always fits in one chat message
function ns.statusMessage(e)
    local names = ns.partyHas(e)
    local icon = (#names > 0) and (ICON .. " ") or ""
    local link = C.link(e)
    local text = ns.statusText(e)
    local suffix = haveSuffix(names)
    local msg = icon .. link .. " - " .. text .. suffix
    if #msg > 250 then                      -- too many objectives: cut the list, keep the link and the suffix
        local room = 250 - #(icon .. link .. " - ") - #suffix - 3
        msg = icon .. link .. " - " .. string.sub(text, 1, math.max(room, 0)) .. "..." .. suffix
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
    if e then ns.deliver(ns.statusMessage(e)) end
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
            box:Insert(" - " .. ns.statusText(e) .. haveSuffix(names) .. ((#names > 0) and (" " .. ICON) or ""))
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
