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

function ns.panelLines()
    local members = C.members()
    if #members == 0 then return { "You are not in a party." } end
    local who = {}
    for _, m in ipairs(members) do who[#who + 1] = m.name .. (ns.peers[key(m.name)] and " (addon)" or "") end
    local lines = { "Party: " .. table.concat(who, ", ") }
    local any = false
    for _, e in ipairs(C.entries()) do
        local per = {}
        for _, m in ipairs(members) do
            local k = key(m.name)
            local peer = ns.peers[k]
            local rec = peer and peer.quests and peer.quests[e.questID]
            if rec then
                per[#per + 1] = m.name .. " " .. progressOf(rec)
            elseif not (peer and peer.listed) then            -- not a synced player: only "has it" is known
                local st = ns.known[e.questID] and ns.known[e.questID][k]
                if st == "has" or st == "accepted" or C.unitOnQuest(m.unit, e) == true then
                    per[#per + 1] = m.name .. " has it"
                end
            end
        end
        if #per > 0 then
            any = true
            lines[#lines + 1] = STAR .. " " .. e.title .. (e.complete and " (done)" or "") .. ": " .. table.concat(per, " | ")
        end
    end
    if not any then lines[#lines + 1] = "No quests in common yet." end
    return lines
end

-- The panel frame -------------------------------------------------------------------------------------
local panel, rows
local MAX_ROWS = 24

local function ensurePanel()
    if panel then return panel end
    if not (CreateFrame and UIParent) then return nil end
    local ok, f = pcall(CreateFrame, "Frame", "QuestSharingPanel", UIParent, "BackdropTemplate")
    if not (ok and f) then ok, f = pcall(CreateFrame, "Frame", "QuestSharingPanel", UIParent) end
    if not (ok and f) then return nil end
    f:SetWidth(420)
    f:SetHeight(40)
    local pos = ns.db.panelPos
    f:SetPoint(pos and pos[1] or "CENTER", UIParent, pos and pos[1] or "CENTER", pos and pos[2] or 0, pos and pos[3] or 0)
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
    -- a small "Settings" link in the corner
    local link = CreateFrame("Frame", nil, f)
    link:SetWidth(60)
    link:SetHeight(14)
    link:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
    link:EnableMouse(true)
    link:SetScript("OnMouseUp", function() if ns.toggleSettings then ns.toggleSettings() end end)
    local linkText = link:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    linkText:SetPoint("RIGHT", link, "RIGHT", 0, 0)
    linkText:SetText("|cff55ccffSettings|r")
    f.settingsLink = link
    rows = {}
    for i = 1, MAX_ROWS do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8 - (i - 1) * 14)
        fs:SetJustifyH("LEFT")
        fs:SetWidth(400)
        rows[i] = fs
    end
    panel = f
    return f
end

function ns._panel() return panel, rows end        -- for the tests

function ns.refreshPanel()
    if not (panel and panel:IsShown()) then return end
    local lines = ns.panelLines()
    for i = 1, MAX_ROWS do
        if lines[i] then rows[i]:SetText(lines[i]); rows[i]:Show() else rows[i]:Hide() end
    end
    panel:SetHeight(16 + math.min(#lines, MAX_ROWS) * 14)
end

local function tick()
    if panel and panel:IsShown() then
        ns.refreshPanel()
        ns.after(2, tick)
    end
end

function ns.showPanel(show)
    local f = ensurePanel()
    if not f then
        if show then ns.print("this client does not allow the panel (frame creation failed)") end
        return
    end
    if show then f:Show(); ns.refreshPanel(); ns.after(2, tick) else f:Hide() end
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
    for i = 1, (QUESTS_DISPLAYED or 6) do
        local btn = _G["QuestLogTitle" .. i]
        if btn and btn:IsShown() and not btn.isHeader then
            local e = C.findEntry(nil, btn:GetID())
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
    for btn in pool:EnumerateActive() do
        local e = btn.questID and C.findEntry(btn.questID)
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
