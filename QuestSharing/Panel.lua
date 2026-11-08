-- Panel.lua: shows which party members share your quests.
--   * a small movable panel "Quests in common" (works on every client: it is our own frame)
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

-- Tell the party how YOU are doing with a quest (what a click on a row does)
function ns.sharePanelQuest(e)
    if not e then return false end
    if not C.inGroup() then ns.print("you are not in a party") return false end
    if ns.panelLastShare and GetTime() - ns.panelLastShare < 1 then return false end      -- no accidental double clicks
    ns.panelLastShare = GetTime()
    SendChatMessage(ns.statusMessage(e), C.channel())
    ns.print("told the party how you are doing with " .. e.title)
    return true
end

-- The panel frame -------------------------------------------------------------------------------------
-- title + settings link | one icon per party member | one row per shared quest: [who has it] quest name   my progress
local panel, legend, qrows, notes
local MAX_QUESTS, MAX_MEMBERS = 12, 4
local ROW_H, ICON, WIDTH = 22, 18, 400
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

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
    for _, w in ipairs(row.who or {}) do GameTooltip:AddLine(w.m.name .. ": " .. w.text) end
    GameTooltip:AddLine("Click: tell the party how I am doing")
    GameTooltip:Show()
end

local function buildRow(f, i)
    local row = CreateFrame("Button", nil, f)
    row:SetWidth(WIDTH - 16)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.icons, row.checks = {}, {}
    for j = 1, MAX_MEMBERS do
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetWidth(ICON)
        t:SetHeight(ICON)
        row.icons[j] = t
        local c = row:CreateTexture(nil, "OVERLAY")
        c:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        c:SetWidth(10)
        c:SetHeight(10)
        row.checks[j] = c
    end
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.title:SetJustifyH("LEFT")
    row.mine = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.mine:SetJustifyH("RIGHT")
    row.mine:SetWidth(56)
    row.mine:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row:SetScript("OnClick", function(self)
        if self.questID then ns.sharePanelQuest(C.findEntry(self.questID)) end
    end)
    row:SetScript("OnEnter", rowTooltip)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -50 - (i - 1) * ROW_H)
    return row
end

local function ensurePanel()
    if panel then return panel end
    if not (CreateFrame and UIParent) then return nil end
    local ok, f = pcall(CreateFrame, "Frame", "QuestSharingPanel", UIParent, "BackdropTemplate")
    if not (ok and f) then ok, f = pcall(CreateFrame, "Frame", "QuestSharingPanel", UIParent) end
    if not (ok and f) then return nil end
    f:SetWidth(WIDTH)
    f:SetHeight(60)
    local pos = ns.db.panelPos
    -- first time: on the left, out of the way (not in the middle of the screen); afterwards where you dragged it
    if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("LEFT", UIParent, "LEFT", 20, 120) end
    pcall(function()
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0, 0, 0, 0.85)
    end)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ns.db.panelPos = { point, x, y }
    end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    f.title:SetText("Party quests")
    -- a small "Settings" link in the corner
    local link = CreateFrame("Frame", nil, f)
    link:SetWidth(60)
    link:SetHeight(14)
    link:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    link:EnableMouse(true)
    link:SetScript("OnMouseUp", function() if ns.toggleSettings then ns.toggleSettings() end end)
    local linkText = link:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    linkText:SetPoint("RIGHT", link, "RIGHT", 0, 0)
    linkText:SetText("|cff55ccffSettings|r")
    f.settingsLink = link
    legend = {}                                                   -- the party: an icon and a name each
    for i = 1, MAX_MEMBERS do
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(16)
        icon:SetHeight(16)
        local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetJustifyH("LEFT")
        legend[i] = { icon = icon, name = name }
    end
    qrows = {}
    for i = 1, MAX_QUESTS do qrows[i] = buildRow(f, i) end
    notes = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")      -- "No quests in common yet." / "+3 more"
    notes:SetJustifyH("LEFT")
    panel = f
    return f
end

function ns._panel() return panel, qrows, legend, notes end        -- for the tests

local function shorten(name, n) return (#name > n) and (string.sub(name, 1, n - 1) .. ".") or name end

function ns.refreshPanel()
    if not (panel and panel:IsShown()) then return end
    local data = ns.panelData()
    local members = data and data.members or {}
    local x = 10
    for i = 1, MAX_MEMBERS do
        local m, l = members[i], legend[i]
        if m then
            setClassIcon(l.icon, m.class)
            l.icon:ClearAllPoints()
            l.icon:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -28)
            l.name:ClearAllPoints()
            l.name:SetPoint("LEFT", l.icon, "RIGHT", 3, 0)
            l.name:SetText(shorten(m.name, 10))
            l.icon:Show()
            l.name:Show()
            x = x + 16 + 3 + 6 * math.min(#m.name, 10) + 12
        else
            l.icon:Hide()
            l.name:Hide()
        end
    end
    local shown = 0
    local quests = data and data.quests or {}
    local left = 8 + math.max(#members, 1) * (ICON + 2) + 4                 -- where the quest names start
    for i = 1, MAX_QUESTS do
        local row, qd = qrows[i], quests[i]
        if qd then
            shown = shown + 1
            row.questID, row.entry, row.who = qd.e.questID, qd.e, qd.who
            local byUnit = {}
            for _, w in ipairs(qd.who) do byUnit[w.m.unit] = w end
            for j = 1, MAX_MEMBERS do
                local m, icon, check = members[j], row.icons[j], row.checks[j]
                local w = m and byUnit[m.unit]
                if w then
                    setClassIcon(icon, m.class)
                    icon:ClearAllPoints()
                    icon:SetPoint("LEFT", row, "LEFT", 2 + (j - 1) * (ICON + 2), 0)
                    icon:Show()
                    check:ClearAllPoints()
                    check:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 3, -3)
                    if w.done then check:Show() else check:Hide() end
                else
                    icon:Hide()
                    check:Hide()
                end
            end
            row.title:ClearAllPoints()
            row.title:SetPoint("LEFT", row, "LEFT", left - 8, 0)
            row.title:SetWidth(WIDTH - 16 - (left - 8) - 62)
            row.title:SetText((qd.e.complete and "|cff55ff55" or "") .. qd.e.title .. (qd.e.complete and "|r" or ""))
            row.mine:SetText(ns.panelMine(qd.e))
            row:Show()
        else
            row.questID, row.entry, row.who = nil, nil, nil
            row:Hide()
        end
    end
    local height = 52 + shown * ROW_H
    local note
    if not data then note = "You are not in a party."
    elseif #quests == 0 then note = "No quests in common yet."
    elseif #quests > MAX_QUESTS then note = string.format("+%d more - see the quest log", #quests - MAX_QUESTS) end
    if note then
        notes:ClearAllPoints()
        notes:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -(height - 2))
        notes:SetText(note)
        notes:Show()
        height = height + 16
    else
        notes:Hide()
    end
    panel:SetHeight(height + 4)
end

local function tick()
    if panel and panel:IsShown() then
        ns.refreshPanel()
        ns.after(5, tick)
    end
end

function ns.showPanel(show)
    local f = ensurePanel()
    if not f then
        if show then ns.print("this client does not allow the panel (frame creation failed)") end
        return
    end
    if show then f:Show(); ns.refreshPanel(); ns.after(5, tick) else f:Hide() end
end

-- the setting means "show the panel while I am in a party"
function ns.syncPanelVisibility()
    if ns.db.panel and C.inGroup() then
        ns.showPanel(true)
    elseif panel and panel:IsShown() then
        panel:Hide()
    end
end

ns.on("PLAYER_ENTERING_WORLD", function() ns.after(1, ns.syncPanelVisibility) end)
ns.on("GROUP_ROSTER_UPDATE", function() ns.after(1, function() ns.syncPanelVisibility(); ns.refreshPanel() end) end)
ns.on("GROUP_JOINED", function() ns.after(1, ns.syncPanelVisibility) end)

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
