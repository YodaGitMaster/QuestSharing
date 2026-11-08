-- Panel.lua: shows which party members share your quests.
--   * a small movable window "Party quests": a grid with your 5 nearest quests (re-sorted as you move) down the side and
--     one column per party member, with a check (has it), a gold check (has it and finished it), an X (does not have
--     it) or a ? (the game cannot tell: out of range, offline)
--   (works on every client: it is our own frame)
--   * a star and the names next to shared quests in the game's own quest log (hooks the quest log
--     of the classic and of the modern client; if a client's quest log looks different, the markers
--     are skipped and /qs probe says so)
local ADDON, ns = ...
local C = ns.compat
local key = ns.memberKey

local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12|t"
ns.hooks = ns.hooks or {}

-- Data model (no frames involved) ---------------------------------------------------------------------
-- " <star> Anna +1" for a quest the party shares, "" otherwise
function ns.markerText(e)
    local names = ns.partyHas(e)
    if #names == 0 then return "" end
    return " " .. STAR .. " " .. names[1] .. ((#names > 1) and (" +" .. (#names - 1)) or "")
end

local function progressOf(rec)
    if rec.complete then return "done" end
    if rec.objs and rec.objs ~= "" then return (string.gsub(rec.objs, ",", ", ")) end
    return "has it"
end

-- Who has which quest: { members = { {name, unit, class} }, quests = { {e = entry, who = { {m = member, text, done} } } } }
-- (or nil when you are not in a party). Both the window and the plain-text lines are made from this.
function ns.panelData()
    local members = C.members()
    if #members == 0 then return nil end
    for _, m in ipairs(members) do
        if UnitClass then local _, file = UnitClass(m.unit); m.class = file end
        m.addon = ns.peers[key(m.name)] and true or false
    end
    local data = { members = members, quests = {} }
    for _, e in ipairs(C.entries()) do
        local who = {}
        for _, m in ipairs(members) do
            local k = key(m.name)
            local peer = ns.peers[k]
            local rec = peer and peer.quests and peer.quests[e.questID]
            if rec then
                who[#who + 1] = { m = m, text = progressOf(rec), done = rec.complete and true or false }
            elseif not (peer and peer.listed) then            -- not a synced player: only "has it" is known
                local st = ns.known[e.questID] and ns.known[e.questID][k]
                if st == "has" or st == "accepted" or C.unitOnQuest(m.unit, e) == true then
                    who[#who + 1] = { m = m, text = "has it", done = false }
                end
            end
        end
        if #who > 0 then data.quests[#data.quests + 1] = { e = e, who = who } end
    end
    return data
end

-- How party member m stands on my quest e: "done" | "has" | "no" | "unknown".
-- Players running Quest Sharing tell us exactly (sync). For the others the game can only tell while they are in range.
function ns.memberStatus(m, e)
    local k = key(m.name)
    local peer = ns.peers[k]
    if peer and peer.listed then
        local rec = peer.quests and peer.quests[e.questID]
        if not rec then return "no" end
        return rec.complete and "done" or "has"
    end
    local st = ns.known[e.questID] and ns.known[e.questID][k]
    if st == "has" or st == "accepted" then return "has" end
    if st == "done" or st == "full" or st == "other" then return "cant" end   -- did it before, log full, not eligible
    if st == "declined" then return "no" end
    if UnitIsConnected and UnitIsConnected(m.unit) == false then return "unknown" end
    if UnitIsVisible and not UnitIsVisible(m.unit) then return "unknown" end
    local on = C.unitOnQuest(m.unit, e)
    if on == true then return "has" elseif on == false then return "no" end
    return "unknown"
end

local STATUS_TEXT = { done = "done", has = "has it", no = "does not have it", unknown = "cannot tell (out of range or offline)",
                      cant = "cannot take it (did it before, quest log full, or not eligible)" }

-- My nearest quests, at most `n`, nearest first. To keep the rows calm while you walk, a quest only moves above another
-- one (or onto the list) when it is clearly closer: about 20 % (0.64 on squared distances). Without distances (some
-- clients): the quests of the zone you are in first, in quest-log order.
local previous = {}           -- the order shown last time: questIDs
local CLEARLY = 0.64
function ns.nearestQuests(entries, n)
    local list, rest = {}, {}
    if C.hasDistance() then
        local byId, seen = {}, {}
        for _, e in ipairs(entries) do
            local d = C.distanceSq(e)
            if d then byId[e.questID] = { e = e, d = d } else rest[#rest + 1] = { e = e } end   -- another continent: last
        end
        for _, id in ipairs(previous) do                         -- what was shown stays in its place to begin with
            if byId[id] then list[#list + 1] = byId[id]; seen[id] = true end
        end
        local fresh = {}
        for id, x in pairs(byId) do if not seen[id] then fresh[#fresh + 1] = x end end
        table.sort(fresh, function(a, b) if a.d == b.d then return a.e.questID < b.e.questID end return a.d < b.d end)
        for _, x in ipairs(fresh) do list[#list + 1] = x end
        for i = 2, #list do                                      -- then a quest moves up only past ones clearly farther
            local j = i
            while j > 1 and list[j].d < list[j - 1].d * CLEARLY do
                list[j], list[j - 1] = list[j - 1], list[j]
                j = j - 1
            end
        end
    else
        for _, e in ipairs(entries) do if C.inArea(e) then list[#list + 1] = { e = e } else rest[#rest + 1] = { e = e } end end
    end
    for _, x in ipairs(rest) do list[#list + 1] = x end
    local out = {}
    previous = {}
    for i = 1, math.min(n, #list) do
        out[i] = list[i].e
        previous[i] = list[i].e.questID
    end
    return out
end

-- The grid of the window: { members, rows = { { e = entry, cells = { status per member }, who } }, near = 5 } (nil: no
-- party). The first rows are my nearest quests; after them come the rest of my quests in this zone (scroll down).
local GRID_ROWS = 5           -- rows on screen
local NEAREST = 5
function ns.panelGrid(entries)
    local members = C.members()
    if #members == 0 then return nil end
    entries = entries or C.entries()
    for _, m in ipairs(members) do
        if UnitClass then local _, file = UnitClass(m.unit); m.class = file end
        m.addon = ns.peers[key(m.name)] and true or false
    end
    local grid = { members = members, rows = {}, shared = 0 }
    local list, inList = ns.nearestQuests(entries, NEAREST), {}
    grid.near = #list
    for _, e in ipairs(list) do inList[e.questID] = true end
    for _, e in ipairs(entries) do                                      -- then the rest of this zone
        if not inList[e.questID] and C.inArea(e) then list[#list + 1] = e end
    end
    for _, e in ipairs(list) do
        local row = { e = e, cells = {}, who = {} }
        local any = false
        for j, m in ipairs(members) do
            local st = ns.memberStatus(m, e)
            row.cells[j] = st
            local rec = ns.peers[key(m.name)] and ns.peers[key(m.name)].quests and ns.peers[key(m.name)].quests[e.questID]
            local detail = (rec and (st == "has" or st == "done")) and progressOf(rec) or STATUS_TEXT[st]
            row.who[#row.who + 1] = { m = m, text = detail, done = (st == "done"), status = st }
            if st == "has" or st == "done" then any = true end
        end
        if any then grid.shared = grid.shared + 1 end
        -- everybody who has it is done (and so am I): time to hand it in together
        local done, busy = 0, 0
        for _, st in ipairs(row.cells) do if st == "done" then done = done + 1 elseif st == "has" then busy = busy + 1 end end
        row.allDone = e.complete and done > 0 and busy == 0
        grid.rows[#grid.rows + 1] = row
    end
    return grid
end

function ns.panelLines()
    local data = ns.panelData()
    if not data then return { "You are not in a party." } end
    local names = {}
    for _, m in ipairs(data.members) do names[#names + 1] = m.name .. (m.addon and " (addon)" or "") end
    local lines = { "Party: " .. table.concat(names, ", ") }
    for _, qd in ipairs(data.quests) do
        local per = {}
        for _, w in ipairs(qd.who) do per[#per + 1] = w.m.name .. " " .. w.text end
        lines[#lines + 1] = STAR .. " " .. qd.e.title .. (qd.e.complete and " (done)" or "") .. ": " .. table.concat(per, " | ")
    end
    if #data.quests == 0 then lines[#lines + 1] = "No quests in common yet." end
    return lines
end

-- how far YOU are, in a few characters: "5/8", "done", ""
function ns.panelMine(e)
    if e.complete then return "done" end
    local objs = C.objectives(e)
    local open, first = 0, nil
    for _, o in ipairs(objs) do
        if not o.finished then
            open = open + 1
            first = first or o
        end
    end
    if #objs > 0 and open == 0 then return "done" end
    if not first then return "" end
    local txt = (first.have and first.need) and string.format("%d/%d", first.have, first.need) or "..."
    return txt .. (open > 1 and (" +" .. (open - 1)) or "")
end

-- A click on a row does what a click on the game's tracker does: your status for that quest goes into the chat box,
-- added to what is already there (click several quests, then press Enter once)
function ns.sharePanelQuest(e)
    if not e then return false end
    return ns.shareStatus(e)
end

-- Post my progress at once (the "Post all" button): the quests on the window that someone in the party has, one message
function ns.postAllProgress()
    local grid = ns.panelGrid()
    if not grid then ns.print("you are not in a party"); return 0 end
    local list = {}
    for _, row in ipairs(grid.rows) do
        for _, st in ipairs(row.cells) do if st == "has" or st == "done" then list[#list + 1] = row.e; break end end
    end
    if #list == 0 then ns.print("nobody in the party has these quests yet - Share offers them"); return 0 end
    local mode, added = ns.db.mode, 0
    if mode == "box" and ChatFrame_OpenChat then
        for _, e in ipairs(list) do
            if ns.addToChatBox(ns.statusMessage(e, true), C.link(e)) then added = added + 1 else break end
        end
    else
        local parts, len = {}, 0
        for _, e in ipairs(list) do
            local m = ns.statusMessage(e, mode ~= "send")
            if len + #m + 3 > 255 then break end
            parts[#parts + 1] = m
            len = len + #m + 3
        end
        added = #parts
        ns.deliver(table.concat(parts, " + "))
    end
    if added < #list then
        ns.print(string.format("%d of %d quests fit in one message; send it, then click Post all again for the rest", added, #list))
    end
    return added
end

-- The panel frame -------------------------------------------------------------------------------------
--   Party quests (2 of 5 shared)                  [Share] [Post all] [-]  Settings
--   Quest                          [mage] Anna   [priest] Bob
--   Wolves Among Us          3/8       (check)        (X)
--   Report to Goldshire     done       (gold)         (?)
local S = ns.style
local panel, cols, qrows, notes
local MAX_MEMBERS = 4
local ROW_H, QUEST_W, COL_W, CELL = 20, 230, 70, 16
local MIN_W = 410
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local CELL_ICON = { has = "Interface\\RaidFrame\\ReadyCheck-Ready", done = "Interface\\RaidFrame\\ReadyCheck-Ready",
                    no = "Interface\\RaidFrame\\ReadyCheck-NotReady", unknown = "Interface\\RaidFrame\\ReadyCheck-Waiting",
                    cant = "Interface\\Buttons\\UI-MinusButton-Up" }
local START = { "LEFT", 20, 120 }                  -- where it first appears: on the left, out of the way

local function setClassIcon(tex, class)
    local c = CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class]
    if c then
        tex:SetTexture(CLASS_ICONS)
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        tex:SetTexture(UNKNOWN_ICON)
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function rowTooltip(row)
    if not (GameTooltip and GameTooltip.AddLine and row.entry) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.entry.title)
    GameTooltip:AddLine("Me: " .. (ns.panelMine(row.entry) ~= "" and ns.panelMine(row.entry) or "in progress"))
    for _, w in ipairs(row.who or {}) do GameTooltip:AddLine(w.m.name .. ": " .. w.text) end
    if row.allDone then GameTooltip:AddLine(S.GREEN .. "Everyone who has it is done - time to turn it in!|r") end
    GameTooltip:AddLine(S.GREY .. "Left click: offer it to whoever does not have it|r")
    GameTooltip:AddLine(S.GREY .. "Right click: tell the party how I am doing and ask them|r")
    GameTooltip:Show()
end

local function buildRow(f, i)
    local row = CreateFrame("Button", nil, f)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    if i % 2 == 0 then                                            -- soft stripes: easier to follow a row with the eye
        local stripe = S.fill(row, "BACKGROUND", 1, 1, 1, 0.04)
        stripe:SetAllPoints(row)
    end
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.title:SetJustifyH("LEFT")
    row.title:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.title:SetWidth(QUEST_W - 56)
    row.mine = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.mine:SetJustifyH("RIGHT")
    row.mine:SetWidth(48)
    row.mine:SetPoint("LEFT", row, "LEFT", QUEST_W - 52, 0)
    row.cells = {}
    for j = 1, MAX_MEMBERS do
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetWidth(CELL)
        t:SetHeight(CELL)
        t:SetPoint("CENTER", row, "LEFT", QUEST_W + (j - 0.5) * COL_W, 0)
        row.cells[j] = t
    end
    row:SetScript("OnClick", function(self, button)
        if not self.questID then return end
        local e = C.findEntry(self.questID)
        if button == "RightButton" then ns.askParty(e) else ns.offerQuest(e) end
    end)
    row:SetScript("OnEnter", rowTooltip)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -50 - (i - 1) * ROW_H)
    return row
end

function ns.applyPanelScale()
    if panel and panel.SetScale then panel:SetScale((ns.db.panelScale or 100) / 100) end
end

function ns.resetPanelPosition(quiet)
    ns.db.panelPos = nil
    if panel then
        panel:ClearAllPoints()
        panel:SetPoint(START[1], UIParent, START[1], START[2], START[3])
    end
    if not quiet then ns.print("the Party quests window is back on the left of the screen") end
end

local function headerButton(f, text, w, onClick, tip)
    local b = S.button(f, text, w, onClick, tip)
    b:SetHeight(18)
    return b
end

local function ensurePanel()
    if panel then return panel end
    if not (CreateFrame and UIParent) then return nil end
    local f = S.window("QuestSharingPanel", MIN_W, 60, "Party quests", "hud")
    if not f then return nil end
    -- first time: on the left, out of the way (not in the middle of the screen); afterwards where you dragged it
    local pos = ns.db.panelPos
    if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint(START[1], UIParent, START[1], START[2], START[3]) end
    f.onMoved = function(self)
        local point, _, _, x, y = self:GetPoint()
        ns.db.panelPos = { point, x, y }
    end
    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.count:SetPoint("LEFT", f.title, "RIGHT", 6, 0)
    -- a small "Settings" link in the corner
    local link = CreateFrame("Frame", nil, f)
    link:SetWidth(50)
    link:SetHeight(14)
    link:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -9)
    link:EnableMouse(true)
    link:SetScript("OnMouseUp", function() if ns.toggleSettings then ns.toggleSettings(true, "party") end end)
    local linkText = link:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    linkText:SetPoint("RIGHT", link, "RIGHT", 0, 0)
    linkText:SetText("|cff55ccffSettings|r")
    f.settingsLink = link
    f.collapse = headerButton(f, "-", 18, function() ns.togglePanelCollapsed() end, "Fold the window to its title (click again to open it)")
    f.collapse:SetPoint("TOPRIGHT", f, "TOPRIGHT", -62, -7)
    f.post = headerButton(f, "Post all", 62, function() ns.postAllProgress() end,
        "Put my progress on these quests (the ones someone in the party has) in the chat box, in one message")
    f.post:SetPoint("RIGHT", f.collapse, "LEFT", -4, 0)
    f.share = headerButton(f, "Share", 48, function() ns.startShare("manual") end,
        "Offer my quests of this area to the party now (once per person)")
    f.share:SetPoint("RIGHT", f.post, "LEFT", -4, 0)
    -- the column titles: "Quest", then a class icon and the name of each party member
    f.questHead = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.questHead:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    f.questHead:SetText("Quest")
    f.headLine = S.fill(f, "ARTWORK", 1, 0.82, 0, 0.3)
    f.headLine:SetHeight(1)
    f.headLine:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -47)
    f.headLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -47)
    cols = {}
    for j = 1, MAX_MEMBERS do
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(14)
        icon:SetHeight(14)
        local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetJustifyH("LEFT")
        name:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        local x = 8 + QUEST_W + (j - 1) * COL_W + 4
        icon:SetPoint("TOPLEFT", f, "TOPLEFT", x, -30)
        cols[j] = { icon = icon, name = name }
    end
    qrows = {}
    for i = 1, GRID_ROWS do qrows[i] = buildRow(f, i) end
    notes = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")      -- "You are not in a party." / "No quests"
    notes:SetJustifyH("LEFT")
    -- the mouse wheel scrolls from the nearest quests down to the rest of the zone
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) ns.scrollPanel(delta > 0 and -1 or 1) end)
    panel = f
    ns.applyPanelScale()
    return f
end

function ns._panel() return panel, qrows, cols, notes end        -- for the tests

local function shorten(name, n) return (#name > n) and (string.sub(name, 1, n - 1) .. ".") or name end

local offset = 0                 -- how far the list is scrolled down
function ns.scrollPanel(step)
    offset = offset + step
    ns.refreshPanel()
end

function ns.togglePanelCollapsed()
    ns.db.panelCollapsed = not ns.db.panelCollapsed
    ns.refreshPanel()
end

local function paintCell(t, st)
    t:SetTexture(CELL_ICON[st] or CELL_ICON.unknown)
    if st == "done" then t:SetVertexColor(1, 0.82, 0, 1)                       -- gold: has it and finished it
    elseif st == "unknown" or st == "cant" then t:SetVertexColor(0.6, 0.6, 0.6, 0.8)
    else t:SetVertexColor(1, 1, 1, 1) end
    t:Show()
end

function ns.refreshPanel()
    if not (panel and panel:IsShown()) then return end
    local grid = ns.panelGrid()
    local members = grid and grid.members or {}
    local rows = grid and grid.rows or {}
    local folded = ns.db.panelCollapsed and true or false
    local width = math.max(MIN_W, 16 + QUEST_W + math.min(#members, MAX_MEMBERS) * COL_W)
    panel:SetWidth(width)
    offset = math.max(0, math.min(offset, #rows - GRID_ROWS))
    panel.count:SetText(grid and (S.GREY .. "(" .. grid.shared .. " shared, " .. #rows .. " here)|r") or "")
    panel.collapse:SetLabel(folded and "+" or "-")
    if folded then panel.questHead:Hide(); panel.headLine:Hide() else panel.questHead:Show(); panel.headLine:Show() end
    for j = 1, MAX_MEMBERS do
        local m, c = members[j], cols[j]
        if m and not folded then
            setClassIcon(c.icon, m.class)
            c.name:SetText(S.classHex(m.class) .. shorten(m.name, 8) .. "|r" .. (m.addon and (" " .. S.GREEN .. "QS|r") or ""))
            c.icon:Show()
            c.name:Show()
        else
            c.icon:Hide()
            c.name:Hide()
        end
    end
    local shownRows = 0
    for i = 1, GRID_ROWS do
        local row, data = qrows[i], (not folded) and rows[i + offset] or nil
        if data then
            shownRows = shownRows + 1
            row.questID, row.entry, row.who = data.e.questID, data.e, data.who
            row:SetWidth(width - 16)
            local done = data.e.complete
            row.title:SetText((done and "|cff55ff55" or "|cffffffff") .. data.e.title .. "|r")
            local mine = ns.panelMine(data.e)
            if data.allDone then row.mine:SetText(S.GOLD .. "turn in!|r")
            else row.mine:SetText(mine == "done" and (S.GREEN .. "done|r") or (S.GREY .. mine .. "|r")) end
            for j = 1, MAX_MEMBERS do
                local st = members[j] and data.cells[j]
                if st then paintCell(row.cells[j], st) else row.cells[j]:Hide() end
            end
            row:Show()
        else
            row.questID, row.entry, row.who = nil, nil, nil
            row:Hide()
        end
    end
    if folded then
        notes:Hide()
        panel:SetHeight(30)
        return
    end
    local height = 52 + shownRows * ROW_H
    local note
    if C.inRaid() then note = "Quests can only be shared in a 5-player party, not in a raid."
    elseif not grid then note = "You are not in a party."
    elseif #rows == 0 then note = "You have no quests right now."
    elseif #rows > GRID_ROWS then
        local below = #rows - GRID_ROWS - offset
        note = below > 0 and (S.GREY .. "scroll down: " .. below .. " more in " .. C.zone() .. "|r")
                          or (S.GREY .. "scroll up for the nearest quests|r")
    elseif grid.shared == 0 then note = "Nobody in the party has these quests yet.  " .. S.GREY .. "Share offers them.|r" end
    if note then
        notes:ClearAllPoints()
        notes:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -(height + 2))
        notes:SetText(note)
        notes:Show()
        height = height + 18
    else
        notes:Hide()
    end
    panel:SetHeight(height + 6)
end

local function tick()
    if panel and panel:IsShown() then
        ns.refreshPanel()
        ns.after(4, tick)                         -- often enough to follow you as you move, cheap enough to never be felt
    end
end

function ns.showPanel(show)
    local f = ensurePanel()
    if not f then
        if show then ns.print("this client does not allow the panel (frame creation failed)") end
        return
    end
    if show then f:Show(); ns.refreshPanel(); ns.after(4, tick) else f:Hide() end
end

local function inCombat() return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) end

-- the setting means "show the panel while I am in a party" (and, with panelCombat, "but not during a fight")
function ns.syncPanelVisibility()
    if ns.db.panel and C.inGroup() and not (ns.db.panelCombat and inCombat()) then
        ns.showPanel(true)
    elseif panel and panel:IsShown() then
        panel:Hide()
    end
end

ns.on("PLAYER_ENTERING_WORLD", function() ns.after(1, ns.syncPanelVisibility) end)
ns.on("GROUP_ROSTER_UPDATE", function() ns.after(1, function() ns.syncPanelVisibility(); ns.refreshPanel() end) end)
ns.on("GROUP_JOINED", function() ns.after(1, ns.syncPanelVisibility) end)
ns.on("PLAYER_REGEN_DISABLED", function() if ns.db.panelCombat and panel and panel:IsShown() then panel:Hide() end end)
ns.on("PLAYER_REGEN_ENABLED", function() ns.after(0.5, ns.syncPanelVisibility) end)

-- Quest log markers -------------------------------------------------------------------------------------
local function marked(text) return text and string.find(text, "UI-RaidTargetingIcon_1", 1, true) end

-- classic quest log: buttons QuestLogTitle1..N, button:GetID() is the quest log index
local function decorateClassic()
    if not ns.db.markers then return end
    local byIndex
    for i = 1, (QUESTS_DISPLAYED or 6) do
        local btn = _G["QuestLogTitle" .. i]
        if btn and btn:IsShown() and not btn.isHeader then
            if not byIndex then
                byIndex = {}
                for _, entry in ipairs(C.entries()) do byIndex[entry.index] = entry end       -- one scan for all buttons
            end
            local e = byIndex[btn:GetID()]
            local text = btn:GetText()
            if e and text and not marked(text) then
                local mark = ns.markerText(e)
                if mark ~= "" then btn:SetText(text .. mark) end
            end
        end
    end
end

-- modern quest log: the entries are pooled buttons with .questID and a .Text font string
local function decorateModern()
    if not ns.db.markers then return end
    local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
    if not (pool and pool.EnumerateActive) then return end
    local byId
    for btn in pool:EnumerateActive() do
        if btn.questID and not byId then byId = C.entryMap() end                               -- one scan for all buttons
        local e = btn.questID and byId[btn.questID]
        local fs = btn.Text
        if e and fs then
            local text = fs:GetText()
            if text and not marked(text) then
                local mark = ns.markerText(e)
                if mark ~= "" then fs:SetText(text .. mark) end
            end
        end
    end
end

function ns.refreshQuestLog()
    if QuestLogFrame and QuestLogFrame.IsShown and QuestLogFrame:IsShown() and QuestLog_Update then pcall(QuestLog_Update) end
end

local function installMarkers()
    if not ns.hooks.qlClassic and QuestLog_Update and _G["QuestLogTitle1"] then
        ns.hooks.qlClassic = pcall(hooksecurefunc, "QuestLog_Update", decorateClassic)
    end
    if not ns.hooks.qlModern and QuestLogQuests_Update and QuestScrollFrame then
        ns.hooks.qlModern = pcall(hooksecurefunc, "QuestLogQuests_Update", decorateModern)
    end
end
ns.on("PLAYER_LOGIN", installMarkers)
ns.on("PLAYER_ENTERING_WORLD", installMarkers)
ns.on("ADDON_LOADED", installMarkers)           -- the quest log can load after us
installMarkers()
