-- MinimapButton.lua: a small button on the minimap.
--   left click: open the settings window     right click: show / hide the Party quests window
--   the tooltip shows how things are right now (party, tracker, quick chat key, problems)
--   drag it around the minimap edge to move it       /qs minimap off  hides it
-- Two shortcut buttons sit beside it (Quest guide, Dungeon quests) so nobody has to search the menus; they move
-- with it and are hidden with it.
local ADDON, ns = ...

local button
local shortcuts = {}
local STEP = 26                                     -- degrees between neighbouring buttons on the minimap edge

local function put(b, slot)
    local angle = math.rad((ns.db.minimapAngle or 215) + slot * STEP)
    local radius = (Minimap:GetWidth() / 2) + 5
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function place()
    if not (button and Minimap) then return end
    put(button, 0)
    for _, b in ipairs(shortcuts) do put(b, b.slot) end
end

-- dragging any of the buttons moves the whole row: the main button keeps the angle, the others keep their slot
local function dragging(self)
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    ns.db.minimapAngle = (math.deg(math.atan2(cy - my, cx - mx)) - (self and self.slot or 0) * STEP) % 360
    place()
end

local function newButton(name, texture)
    local ok, b = pcall(CreateFrame, "Button", name, Minimap)
    if not (ok and b) then return nil end
    b:SetWidth(31)
    b:SetHeight(31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    icon:SetTexture(texture)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetWidth(53)
    border:SetHeight(53)
    border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnLeave", function() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragging) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    return b
end

-- one shortcut: a title, a line of help, and what a click does (looked up at click time, the modules load later)
local function shortcut(slot, name, texture, title, help, run)
    local b = newButton(name, texture)
    if not b then return nil end
    b.slot = slot
    b:SetScript("OnClick", function() if not run() then ns.print(title .. " is not available") end end)
    b:SetScript("OnEnter", function(self)
        if GameTooltip then
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText(title, 1, 0.82, 0)
                GameTooltip:AddLine(help, 1, 1, 1)
                GameTooltip:Show()
            end)
        end
    end)
    shortcuts[#shortcuts + 1] = b
    return b
end

local function buildShortcuts()
    if #shortcuts > 0 then return end
    shortcut(1, "QuestSharingGuideButton", "Interface\\Icons\\INV_Misc_Map_01", "Quest guide",
        "Click: open the quest optimizer (route for this zone).",
        function() local P = ns.questPlanner; if P and P.open then P.open(); return true end end)
    shortcut(2, "QuestSharingDungeonButton", "Interface\\Icons\\INV_Misc_Key_03", "Dungeon quests",
        "Click: browse dungeon quests, pickups and chains.",
        function() local D = ns.dungeonQuests; if D and D.open then D.open(); return true end end)
end

local function build()
    if button then return button end
    if not (Minimap and CreateFrame) then return nil end
    local b = newButton("QuestSharingMinimapButton", "Interface\\Icons\\INV_Misc_Note_01")
    if not b then return nil end
    b.slot = 0
    b:SetScript("OnClick", function(_, which)
        if which == "RightButton" then ns.setSetting("panel", not ns.db.panel) else ns.toggleSettings() end
    end)
    b:SetScript("OnEnter", function(self)
        if GameTooltip then
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText("Quest Sharing", 1, 0.82, 0)
                for _, line in ipairs(ns.minimapLines()) do GameTooltip:AddLine(line, 1, 1, 1) end
                GameTooltip:Show()
            end)
        end
    end)
    button = b
    buildShortcuts()
    ns.hooks = ns.hooks or {}
    ns.hooks.minimap = true
    return b
end

-- what the tooltip of the button says: how things are right now, then what the clicks do
function ns.minimapLines()
    local S, d = ns.style, ns.db
    local lines = {}
    if not d.enabled then
        lines[#lines + 1] = S.RED .. "Switched off|r (left click to switch it on in the settings)"
    else
        local data = ns.panelData and ns.panelData()
        if data then
            lines[#lines + 1] = string.format("Party: %d %s, %s%d quest%s in common|r", #data.members,
                #data.members == 1 and "member" or "members", S.GREEN, #data.quests, #data.quests == 1 and "" or "s")
        else
            lines[#lines + 1] = S.GREY .. "Not in a party|r"
        end
        lines[#lines + 1] = "Tracker: " .. (d.near and (S.GREEN .. "follows you|r") or (S.GREY .. "off|r"))
        local key = ns.quickKeyName and ns.quickKeyName()
        lines[#lines + 1] = "Quick chat key: " .. (key and (S.GOLD .. key .. "|r") or (S.RED .. "not set|r - Settings > Quick chat"))
        local errors = d.errors and #d.errors or 0
        if errors > 0 then lines[#lines + 1] = S.RED .. errors .. " problem(s) recorded|r - /qs errors" end
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = S.GREY .. "Left click: settings   Right click: Party quests   Drag: move|r"
    return lines
end

function ns.syncMinimapButton()
    if ns.db.minimap then
        if build() then
            place()
            button:Show()
            for _, b in ipairs(shortcuts) do b:Show() end
        end
    elseif button then
        button:Hide()
        for _, b in ipairs(shortcuts) do b:Hide() end
    end
end

function ns._minimapButton() return button end              -- for the tests
function ns._minimapShortcuts() return shortcuts end

ns.on("PLAYER_LOGIN", ns.syncMinimapButton)
ns.on("PLAYER_ENTERING_WORLD", ns.syncMinimapButton)
ns.on("ADDON_LOADED", function(_, name) if name == ADDON then ns.syncMinimapButton() end end)
