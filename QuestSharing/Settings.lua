-- Settings.lua: a window where every setting can be switched with one click.
--   /qs settings    open / close it         (also: the "Settings" link on the quests-in-common panel,
--                                             and an entry under Game Menu > Options > AddOns)
-- It needs none of the game's UI templates: every row is a plain clickable frame with one line of text, so
-- it looks the same on every client.
local ADDON, ns = ...
local C = ns.compat

local ON, OFF = "|cff55ff55[ON] |r", "|cffff5555[OFF]|r"

-- The rows. kind = bool (click toggles) | choice (click = next, right click = previous) |
-- number (left click = +1, right click = -1, shift = 5 at a time) | action
ns.settingRows = {
    { kind = "bool", key = "enabled", label = "Quest Sharing enabled", tip = "Master switch for the whole addon." },
    { kind = "bool", key = "auto", label = "Share my quests when I join a party or someone joins",
      tip = "Once per member, never repeated, never to someone who declined." },
    { kind = "bool", key = "shareNew", label = "Share a quest when I accept it (in a party)",
      tip = "Offers just the new quest to the party, once." },
    { kind = "choice", key = "area", label = "Which quests to share", values = { "zone", "all" },
      names = { zone = "this zone only", all = "all my quests" } },
    { kind = "number", key = "gap", label = "Seconds between shared quests", min = 2, max = 30 },
    { kind = "bool", key = "chat", label = "Announce quests in common in party chat",
      tip = "\"Hey! Looks like we have these quests in common...\"" },
    { kind = "bool", key = "announce", label = "Announce when a quest we share is done" },
    { kind = "bool", key = "verbose", label = "Show me who accepted / declined my shared quests" },
    { kind = "bool", key = "click", label = "Click a tracked quest to write its status in chat" },
    { kind = "bool", key = "link", label = "Shift-click quest links add the status" },
    { kind = "choice", key = "mode", label = "Clicking a quest...", values = { "box", "send", "print" },
      names = { box = "fills the chat box (press Enter)", send = "sends it at once", print = "shows it only to me" } },
    { kind = "bool", key = "sync", label = "Sync quest lists with other Quest Sharing users",
      tip = "Exact \"who has what\" for party members who also run the addon." },
    { kind = "bool", key = "markers", label = "Mark shared quests in the quest log" },
    { kind = "bool", key = "panel", label = "Show the \"quests in common\" panel while in a party" },
    { kind = "bool", key = "near", label = "Tracker follows me (shows the nearest quests)",
      tip = "Fills the quest tracker with the quests closest to you. Switching it off puts your old list back." },
    { kind = "bool", key = "quick", label = "Quick chat wheel (hold a key, point, release)",
      tip = "Hello / want to quest together? / what I need here... Pick the key with /qs key V or in Key Bindings." },
    { kind = "choice", key = "quickMode", label = "The quick chat key", values = { "hold", "toggle" },
      names = { hold = "hold, point, release", toggle = "press to open, click a slot" } },
    { kind = "choice", key = "quickChannel", label = "Quick chat says it to", values = { "auto", "say", "party", "whisper" },
      names = { auto = "party if grouped, else nearby", say = "everybody nearby", party = "the party only", whisper = "the player I target" } },
    { kind = "action", label = "Edit the quick chat messages...", action = function() ns.openQuickEditor() end },
    { kind = "action", label = "Which key opens the wheel? (set it with /qs key V)", action = function() ns.setQuickKey("") end },
    { kind = "bool", key = "friends", label = "(beta) Add people I group with to my friends list",
      tip = "Automatic. Off by default. Skips friends, ignored players and random-dungeon groups; /qs friends adds your party now." },
    { kind = "number", key = "nearCount", label = "Quests the tracker keeps", min = 1, max = function() return C.maxWatch() end },
    { kind = "choice", key = "nearMode", label = "Tracker mode", values = { "auto", "distance", "zone" },
      names = { auto = "automatic", distance = "by distance", zone = "by zone" } },
    { kind = "action", label = "Reset everything to the defaults (all on)", action = function() ns.resetSettings() end },
}

local function limit(v) if type(v) == "function" then return v() end return v end

function ns.rowText(row)
    local d = ns.db
    if row.kind == "bool" then
        return (d[row.key] and ON or OFF) .. " " .. row.label
    elseif row.kind == "choice" then
        local v = d[row.key]
        return row.label .. ": |cff55ccff" .. ((row.names and row.names[v]) or tostring(v)) .. "|r"
    elseif row.kind == "number" then
        return string.format("%s: |cff55ccff%d|r  |cff888888(left click +, right click -)|r", row.label, d[row.key] or 0)
    end
    return "|cffffd100" .. row.label .. "|r"
end

-- What a click on row i does. Used by the window and by the tests.
function ns.settingsClick(i, button)
    local row = ns.settingRows[i]
    if not row then return end
    local d = ns.db
    local back = (button == "RightButton")
    if row.kind == "bool" then
        ns.setSetting(row.key, not d[row.key])
    elseif row.kind == "choice" then
        local idx = 1
        for j, v in ipairs(row.values) do if v == d[row.key] then idx = j end end
        idx = back and (idx - 2) % #row.values + 1 or idx % #row.values + 1
        ns.setSetting(row.key, row.values[idx])
    elseif row.kind == "number" then
        local step = (IsShiftKeyDown and IsShiftKeyDown()) and 5 or 1
        local v = (d[row.key] or 0) + (back and -step or step)
        ns.setSetting(row.key, math.max(row.min, math.min(limit(row.max), v)))
    elseif row.kind == "action" then
        row.action()
    end
end

-- The window ---------------------------------------------------------------------------------------------
local win, lines
local ROW_H = 18

local function build()
    if win then return win end
    if not (CreateFrame and UIParent) then return nil end
    local ok, f = pcall(CreateFrame, "Frame", "QuestSharingSettings", UIParent, "BackdropTemplate")
    if not (ok and f) then ok, f = pcall(CreateFrame, "Frame", "QuestSharingSettings", UIParent) end
    if not (ok and f) then return nil end
    f:SetWidth(430)
    f:SetHeight(48 + #ns.settingRows * ROW_H + 20)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    pcall(function()
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0, 0, 0, 0.92)
    end)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    title:SetText("Quest Sharing - settings")
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -30)
    hint:SetText("Click a line to change it. Everything is on by default.")

    lines = {}
    for i, row in ipairs(ns.settingRows) do
        local r = CreateFrame("Frame", nil, f)
        r:SetWidth(400)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -46 - (i - 1) * ROW_H)
        r:EnableMouse(true)
        r:SetScript("OnMouseUp", function(_, button) ns.settingsClick(i, button) end)
        r:SetScript("OnEnter", function(self)
            if row.tip and GameTooltip then
                pcall(function()
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(row.tip, 1, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
            end
        end)
        r:SetScript("OnLeave", function() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end)
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", r, "LEFT", 0, 0)
        lines[i] = { frame = r, text = fs }
    end

    local close = CreateFrame("Frame", nil, f)
    close:SetWidth(60)
    close:SetHeight(16)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -10)
    close:EnableMouse(true)
    close:SetScript("OnMouseUp", function() f:Hide() end)
    local ct = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ct:SetPoint("RIGHT", close, "RIGHT", 0, 0)
    ct:SetText("|cffff8080Close|r")

    if UISpecialFrames then table.insert(UISpecialFrames, "QuestSharingSettings") end       -- Esc closes it
    win = f
    f:Hide()
    return f
end

function ns.refreshSettings()
    if not (win and lines) then return end
    for i, row in ipairs(ns.settingRows) do lines[i].text:SetText(ns.rowText(row)) end
end

function ns.toggleSettings(show)
    local f = build()
    if not f then return ns.print("this client does not allow the settings window (frame creation failed)") end
    if show == nil then show = not f:IsShown() end
    if show then ns.refreshSettings(); f:Show() else f:Hide() end
end

function ns._settingsWindow() return win, lines end        -- for the tests

-- An entry in the game's own options (Game Menu > Options > AddOns) that opens this window ---------------------
local function registerOptionsEntry()
    if ns.hooks and ns.hooks.optionsEntry then return end
    local ok, f = pcall(CreateFrame, "Frame", "QuestSharingOptionsEntry", UIParent)
    if not (ok and f) then return end
    f.name = "Quest Sharing"
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    text:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    text:SetText("Quest Sharing")
    local open = CreateFrame("Frame", nil, f)
    open:SetWidth(300)
    open:SetHeight(20)
    open:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -44)
    open:EnableMouse(true)
    open:SetScript("OnMouseUp", function() ns.toggleSettings(true) end)
    local ot = open:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    ot:SetPoint("LEFT", open, "LEFT", 0, 0)
    ot:SetText("|cff55ccffClick here to open the settings window|r  (or type /qs settings)")
    ns.hooks = ns.hooks or {}
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local good, category = pcall(Settings.RegisterCanvasLayoutCategory, f, "Quest Sharing")
        if good and category then
            Settings.RegisterAddOnCategory(category)
            ns.hooks.optionsEntry = true
        end
    elseif InterfaceOptions_AddCategory then
        ns.hooks.optionsEntry = pcall(InterfaceOptions_AddCategory, f)
    end
end

ns.on("PLAYER_LOGIN", registerOptionsEntry)
ns.on("PLAYER_ENTERING_WORLD", registerOptionsEntry)
