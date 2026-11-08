-- MinimapButton.lua: a small button on the minimap.
--   left click: open the settings window     right click: show / hide the "quests in common" panel
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
                GameTooltip:SetText("Quest Sharing\\nLeft click: settings\\nRight click: quests-in-common panel\\nDrag: move this button", 1, 1, 1, 1, true)
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
