-- Style.lua: one look for every window of the addon (settings, Party quests, reports).
-- Only plain frames and textures that every client has, so it looks the same on the classic and the modern client.
local ADDON, ns = ...

local S = {}
ns.style = S

S.GOLD, S.BLUE, S.GREY, S.GREEN, S.RED, S.WHITE = "|cffffd100", "|cff55ccff", "|cff9d9d9d", "|cff55ff55", "|cffff5555", "|cffffffff"
S.WHITE8 = "Interface\\Buttons\\WHITE8X8"

-- the colours the game uses for each chat channel, so the ring tells you at a glance where a message goes
S.CHAT = {
    PARTY = { 0.67, 0.67, 1 }, INSTANCE_CHAT = { 1, 0.5, 0.1 }, RAID = { 1, 0.5, 0.1 },
    WHISPER = { 1, 0.5, 1 }, SAY = { 1, 1, 1 }, YELL = { 1, 0.25, 0.25 }, INVITE = { 1, 0.82, 0 }, EMOTE = { 1, 0.5, 0.25 },
}

function S.hex(r, g, b) return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)) end

function S.classHex(class)
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if not c then return S.WHITE end
    return S.hex(c.r or 1, c.g or 1, c.b or 1)
end

-- a flat coloured rectangle
function S.fill(frame, layer, r, g, b, a)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    if t.SetColorTexture then t:SetColorTexture(r, g, b, a) else t:SetTexture(S.WHITE8); t:SetVertexColor(r, g, b, a) end
    return t
end

local function backdrop(f, edge, edgeSize, inset, alpha)
    pcall(function()
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = edge, tile = true, tileSize = 16,
                        edgeSize = edgeSize, insets = { left = inset, right = inset, top = inset, bottom = inset } })
        f:SetBackdropColor(0.04, 0.04, 0.06, alpha)
    end)
end

-- A movable window. kind "dialog": the game's classic dialog look (heavy border, title plate). kind "hud": a light frame
-- for something that stays on screen while you play.
function S.window(name, w, h, title, kind)
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BackdropTemplate")
    if not (ok and f) then ok, f = pcall(CreateFrame, "Frame", name, UIParent) end
    if not (ok and f) then return nil end
    f:SetWidth(w)
    f:SetHeight(h)
    if kind == "dialog" then
        backdrop(f, "Interface\\DialogFrame\\UI-DialogBox-Border", 32, 11, 0.95)
        f:SetFrameStrata("DIALOG")
        local plate = f:CreateTexture(nil, "ARTWORK")
        plate:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
        plate:SetWidth(300)
        plate:SetHeight(64)
        plate:SetPoint("TOP", f, "TOP", 0, 12)
        f.plate = plate
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", f, "TOP", 0, -2)
    else
        backdrop(f, "Interface\\Tooltips\\UI-Tooltip-Border", 12, 3, 0.85)
        f:SetFrameStrata("MEDIUM")
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    end
    f.title:SetText(title or "")
    f:SetMovable(true)
    f:EnableMouse(true)
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() if self.onMoved then self.onMoved(self) end end)
    return f
end

-- the game's little round "x" in the corner
function S.closeButton(parent, onClick, x, y)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(28)
    b:SetHeight(28)
    b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x or -4, y or -4)
    pcall(function()
        b:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    end)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", onClick)
    return b
end

-- A small flat button: dark with a thin edge, gold text when the mouse is over it. tip: a tooltip line.
function S.button(parent, text, w, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(w)
    b:SetHeight(20)
    b.bg = S.fill(b, "BACKGROUND", 0.12, 0.14, 0.2, 0.95)
    b.bg:SetAllPoints(b)
    b.edge = S.fill(b, "BORDER", 0.33, 0.8, 1, 0.35)
    b.edge:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.edge:SetHeight(1)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.label:SetText(text)
    b.text = text
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, which) if onClick then onClick(self, which) end end)
    b:SetScript("OnEnter", function(self)
        self.label:SetText(S.GOLD .. self.text .. "|r")
        self.bg:SetVertexColor(1.4, 1.4, 1.4)
        if tip and GameTooltip then
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(tip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.label:SetText(self.text)
        self.bg:SetVertexColor(1, 1, 1)
        if GameTooltip then pcall(function() GameTooltip:Hide() end) end
    end)
    function b:SetLabel(t) self.text = t; self.label:SetText(t) end
    return b
end

-- the game's check box picture (an empty box, and the tick on top of it when on)
function S.checkBox(parent)
    local box = parent:CreateTexture(nil, "ARTWORK")
    box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetWidth(24)
    box:SetHeight(24)
    local tick = parent:CreateTexture(nil, "OVERLAY")
    tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    tick:SetWidth(24)
    tick:SetHeight(24)
    tick:SetPoint("CENTER", box, "CENTER", 0, 0)
    return box, tick
end

-- a soft sound for good news (never in combat, never when switched off)
local SOUND_NAMES = { "MAP_PING", "IG_QUEST_LIST_SELECT", "TELL_MESSAGE" }
function ns.goodNews()
    if not (ns.db and ns.db.sound and PlaySound) then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    for _, n in ipairs(SOUND_NAMES) do
        local id = SOUNDKIT and SOUNDKIT[n]
        if id and pcall(PlaySound, id, "SFX") then return true end
    end
    return false
end
