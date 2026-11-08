-- MinimapButton.lua: a small button on the minimap.
--   left click: open the settings window     right click: show / hide the Party quests window
--   the tooltip shows how things are right now (party, tracker, quick chat key, problems)
--   drag it around the minimap edge to move it       /qs minimap off  hides it
local ADDON, ns = ...
local C = ns.compat

local button

local function place()
    if not (button and Minimap) then return end
    local angle = math.rad(ns.db.minimapAngle or 215)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function dragging()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    ns.db.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    place()
end

local function build()
    if button then return button end
    if not (Minimap and CreateFrame) then return nil end
    local ok, b = pcall(CreateFrame, "Button", "QuestSharingMinimapButton", Minimap)
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
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetWidth(53)
    border:SetHeight(53)
    border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
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
    b:SetScript("OnLeave", function() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragging) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button = b
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
        lines[#lines + 1] = "Quick chat key: " .. (key and (S.GOLD .. key .. "|r") or (S.RED .. "not set|r - Settings > General"))
        local errors = d.errors and #d.errors or 0
        if errors > 0 then lines[#lines + 1] = S.RED .. errors .. " problem(s) recorded|r - /qs errors" end
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = S.GREY .. "Left click: settings   Right click: Party quests   Drag: move|r"
    return lines
end

function ns.syncMinimapButton()
    if ns.db.minimap then
        if build() then place(); button:Show() end
    elseif button then
        button:Hide()
    end
end

function ns._minimapButton() return button end              -- for the tests

ns.on("PLAYER_LOGIN", ns.syncMinimapButton)
ns.on("PLAYER_ENTERING_WORLD", ns.syncMinimapButton)
ns.on("ADDON_LOADED", function(_, name) if name == ADDON then ns.syncMinimapButton() end end)
