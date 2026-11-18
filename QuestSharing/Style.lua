-- Style.lua: one classic WoW menu look for every window of the addon (settings, Party quests, reports).
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

-- Classic menu look (Esc Game Menu / Interface Options): fully opaque dark stone inside the gold dialog border.
S.STONE = "Interface\\DialogFrame\\UI-DialogBox-Background"
S.BORDER = "Interface\\DialogFrame\\UI-DialogBox-Border"

-- Opaque stone filling frame (inset px from each edge). A solid base sits under the tile so nothing shows through.
function S.stone(frame, inset)
    inset = inset or 0
    local base = S.fill(frame, "BACKGROUND", 0.055, 0.05, 0.045, 1)
    local tile = frame:CreateTexture(nil, "BACKGROUND")
    if not pcall(tile.SetTexture, tile, S.STONE, "REPEAT", "REPEAT") then tile:SetTexture(S.STONE) end
    if tile.SetHorizTile then tile:SetHorizTile(true); tile:SetVertTile(true) end
    if base.SetDrawLayer then base:SetDrawLayer("BACKGROUND", -8); tile:SetDrawLayer("BACKGROUND", -7) end
    for _, t in ipairs({ base, tile }) do
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    end
    frame.stone = { base = base, tile = tile }
    return base
end

-- A recessed black box with a thin bronze rim: edit boxes, lists and side panels inside a window.
function S.inset(frame)
    local base = S.fill(frame, "BACKGROUND", 0.02, 0.018, 0.015, 1)
    base:SetAllPoints(frame)
    S.rim(frame)
    return base
end

-- Opaque stone with a thin bronze rim: small panels without the heavy dialog border (map overlays, overviews).
function S.panel(frame)
    local base = S.stone(frame)
    S.rim(frame)
    return base
end
function S.rim(frame)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = S.fill(frame, "BORDER", 0.42, 0.33, 0.18, 1)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetHeight(1); edge:SetPoint(side .. "LEFT", frame, side .. "LEFT", 0, 0); edge:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", 0, 0)
        else
            edge:SetWidth(1); edge:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, 0); edge:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 0)
        end
    end
end

-- Gold dialog border plus opaque stone. kind "dialog": heavy border; anything else: the same border, thinner.
function S.frame(f, kind)
    local dialog = kind == "dialog"
    local size, inset = dialog and 32 or 16, dialog and 11 or 5
    pcall(function()
        f:SetBackdrop({ edgeFile = S.BORDER, edgeSize = size, insets = { left = inset, right = inset, top = inset, bottom = inset } })
        f:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    return S.stone(f, dialog and 8 or 4)
end

-- A movable window. kind "dialog": a classic menu with a title plate. kind "hud": something that stays on screen while
-- you play; same opaque stone and gold border, thinner, with the title inside.
function S.window(name, w, h, title, kind)
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BackdropTemplate")
    if not (ok and f) then ok, f = pcall(CreateFrame, "Frame", name, UIParent) end
    if not (ok and f) then return nil end
    f:SetWidth(w)
    f:SetHeight(h)
    S.frame(f, kind)
    if kind == "dialog" then
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
        f:SetFrameStrata("MEDIUM")
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -9)
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

-- The game's red-and-gold panel button: gold text, white when the mouse is over it. tip: a tooltip line.
-- Plain textures (not SetNormalTexture), so a caller that hides b.bg for a text-only button stays hidden after clicks.
-- b.bg is the button art (callers tint it to mark the active one); b.edge is a thin gold rule, hidden unless shown.
local function panelArt(b, layer, path)
    local t = b:CreateTexture(nil, layer)
    t:SetTexture(path); t:SetTexCoord(0, 0.625, 0, 0.6875); t:SetAllPoints(b)
    return t
end
function S.button(parent, text, w, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(w)
    b:SetHeight(20)
    b.bg = panelArt(b, "BACKGROUND", "Interface\\Buttons\\UI-Panel-Button-Up")
    b.normalArt = b.bg
    b.pushedArt = panelArt(b, "BACKGROUND", "Interface\\Buttons\\UI-Panel-Button-Down")
    if b.pushedArt.SetDrawLayer then b.pushedArt:SetDrawLayer("BACKGROUND", 1) end
    b.pushedArt:Hide()
    b.highlightArt = panelArt(b, "HIGHLIGHT", "Interface\\Buttons\\UI-Panel-Button-Highlight")
    b.highlightArt:SetBlendMode("ADD")
    b:SetScript("OnMouseDown", function(self) if self.bg:IsShown() then self.pushedArt:Show() end end)
    b:SetScript("OnMouseUp", function(self) self.pushedArt:Hide() end)
    b.edge = S.fill(b, "BORDER", 1, 0.82, 0, 0.9)
    b.edge:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 4, 2)
    b.edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 2)
    b.edge:SetHeight(1)
    b.edge:Hide()
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
    b.label:SetText(text)
    b.text = text
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, which) if onClick then onClick(self, which) end end)
    b:SetScript("OnEnter", function(self)
        self.label:SetText(S.WHITE .. tostring(self.text or "") .. "|r")
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
