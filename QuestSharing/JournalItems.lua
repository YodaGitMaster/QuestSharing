-- Item buttons and item tooltips for the Dungeon Journal look: full game tooltip on hover, Shift compares,
-- Shift-click links in chat, Ctrl-click opens the dressing room. Client textures only.
-- Contract: context/dungeon-journal-contract.md
local ADDON, ns = ...
ns.inModule(nil)          -- core: always on (Modules.lua)
local I = {}
ns.journalItems = I
local S = ns.style
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
-- The game's own quality colours (readable on the dark item box), used when ITEM_QUALITY_COLORS is missing.
local QUALITY = { [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00", [3] = "|cff0070dd", [4] = "|cffa335ee",
    [5] = "|cffff8000", [6] = "|cffe6cc80", [7] = "|cff00ccff" }
I.QUALITY = QUALITY

local function call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d, e, f, g, h, i, j = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j end
end
function I.qualityColor(quality)
    local c = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[quality]
    if type(c) == "table" and type(c.hex) == "string" then return c.hex end
    return QUALITY[quality] or QUALITY[1]
end
-- name, link, quality, icon, type, subType, equipLoc (nil fields while the client has not cached the item)
function I.info(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, link, quality, _, _, kind, subKind, _, equipLoc, icon = call(get, id)
    icon = icon or call((C_Item and C_Item.GetItemIconByID) or GetItemIcon, id)
    if not name and ns.questie and ns.questie.get then name = ns.questie.get("item", id, "name") end
    return name, link, quality, icon, kind, subKind, equipLoc
end
local function idOf(button)
    local v = button.journalItem
    if type(v) == "function" then v = v(button) end
    return tonumber(v) or tonumber(button.itemID)
end
local function hideCompare()
    if not GameTooltip then return end
    if GameTooltip_HideShoppingTooltips then pcall(GameTooltip_HideShoppingTooltips, GameTooltip) return end
    for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2" }) do
        local t = _G[name]
        if t and t.Hide then pcall(t.Hide, t) end
    end
end
local function shift() return call(IsShiftKeyDown) == true end
local function compare(on)
    if on and GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) else hideCompare() end
end
-- Where an item drops (set by the page shell, DungeonQuests.lua): source(id, button, update) returns a boss name or
-- nil; update() is called once a late answer arrives. open(id, button, boss) handles a plain click (true = handled).
-- A button can override both with button.journalSource / button.journalOpen.
local hovered
function I.setSource(fn) I.source = fn end
function I.setOpener(fn) I.open = fn end
function I.setLeave(fn) I.leave = fn end -- called when the mouse leaves an item (the shell drops a pending click)
local function sourceOf(button, id)
    local fn = button.journalSource or I.source
    if type(fn) ~= "function" then return nil end
    local ok, boss = pcall(fn, id, button, function() if hovered == button then I.show(button) end end)
    if ok and type(boss) == "string" and boss ~= "" then return boss end
end
I.sourceOf = sourceOf
function I.show(button)
    local id = idOf(button)
    if not id or not GameTooltip then return false end
    hovered = button
    local boss = sourceOf(button, id)
    local ok = pcall(function()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. id)
        if boss then GameTooltip:AddLine("Drops from " .. boss, 1, 0.82, 0) end
        GameTooltip:Show()
    end)
    if not ok then return false end
    button.journalShift = shift()
    compare(button.journalShift)
    return true
end
function I.hide()
    hovered = nil
    hideCompare()
    if GameTooltip then pcall(function() GameTooltip:Hide() end) end
end
-- Shift-click: link in chat (or whatever the game's modified click does); Ctrl-click: dressing room.
function I.click(button)
    local id = idOf(button)
    if not id then return false end
    local _, link = I.info(id)
    link = link or ("item:" .. id)
    local ctrl = call(IsControlKeyDown) == true or call(IsModifiedClick, "DRESSUP") == true
    local chat = shift() or call(IsModifiedClick, "CHATLINK") == true
    if ctrl then
        if DressUpItemLink then pcall(DressUpItemLink, link) return true end
        if HandleModifiedItemClick then pcall(HandleModifiedItemClick, link) return true end
    elseif chat then
        if HandleModifiedItemClick and call(HandleModifiedItemClick, link) then return true end
        if ChatEdit_InsertLink then return call(ChatEdit_InsertLink, link) and true or false end
    else
        -- plain click: an item a boss of this dungeon drops opens that boss on the Bosses tab
        local fn = button.journalOpen or I.open
        if type(fn) == "function" then
            local ok, done = pcall(fn, id, button, sourceOf(button, id))
            return ok and done == true
        end
    end
    return false
end
-- Turns any button into an item button. item = an itemID or a function(button) returning one.
function I.attach(button, item)
    button.journalItem = item
    if type(item) == "number" then button.itemID = item end
    if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp") end
    button:SetScript("OnEnter", function(self)
        if self.hl then self.hl:Show() end
        if I.show(self) then
            -- Shift pressed or released while the mouse stays on the item: show or hide the compare tooltips.
            self:SetScript("OnUpdate", function(me)
                local now = shift()
                if now ~= me.journalShift then me.journalShift = now; compare(now) end
            end)
        end
    end)
    button:SetScript("OnLeave", function(self)
        if self.hl then self.hl:Hide() end
        self:SetScript("OnUpdate", nil)
        I.hide()
        if type(I.leave) == "function" then pcall(I.leave, self) end
    end)
    button:SetScript("OnClick", function(self) I.click(self) end)
    return button
end

-- 38 px icon, quality-coloured name, small grey subtitle (slot / type), on a dark box with a thin edge.
function I.button(parent, width, height)
    width, height = width or 176, height or 46
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(width); b:SetHeight(height)
    local T = ns.journalTheme
    local c = T and T.C and T.C.lootRow or { .17, .11, .06, .94 }
    b.bg = S.fill(b, "BACKGROUND", c[1], c[2], c[3], 1); b.bg:SetAllPoints(b) -- opaque: no see-through boxes on the page
    local e = T and T.C and T.C.border or { .52, .36, .16, 1 }
    b.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = S.fill(b, "BORDER", e[1], e[2], e[3], .9)
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(1); t:SetPoint(side .. "LEFT", b, side .. "LEFT", 0, 0); t:SetPoint(side .. "RIGHT", b, side .. "RIGHT", 0, 0)
        else
            t:SetWidth(1); t:SetPoint("TOP" .. side, b, "TOP" .. side, 0, 0); t:SetPoint("BOTTOM" .. side, b, "BOTTOM" .. side, 0, 0)
        end
        b.edges[#b.edges + 1] = t
    end
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); b.hl:SetBlendMode("ADD"); b.hl:SetAllPoints(b); b.hl:Hide()
    local size = math.min(38, height - 6)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetWidth(size); b.icon:SetHeight(size)
    b.icon:SetPoint("LEFT", b, "LEFT", 4, 0); b.icon:SetTexCoord(.08, .92, .08, .92)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.name:SetPoint("TOPLEFT", b, "TOPLEFT", size + 10, -6); b.name:SetWidth(width - size - 14); b.name:SetJustifyH("LEFT")
    if b.name.SetWordWrap then b.name:SetWordWrap(false) end
    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.sub:SetPoint("TOPLEFT", b, "TOPLEFT", size + 10, -24); b.sub:SetWidth(width - size - 14); b.sub:SetJustifyH("LEFT")
    if b.sub.SetWordWrap then b.sub:SetWordWrap(false) end
    local m = T and T.C and T.C.muted or { .82, .74, .60 }
    if b.sub.SetTextColor then b.sub:SetTextColor(m[1], m[2], m[3]) end
    function b:SetItem(id, subtitle)
        self.itemID, self.journalItem = id, id
        if not id then self.name:SetText(""); self.sub:SetText(""); self.icon:SetTexture(QUESTION); return end
        local name, _, quality, icon, kind, subKind = I.info(id)
        self.quality = quality
        self.icon:SetTexture(icon or QUESTION)
        self.name:SetText(I.qualityColor(quality or 1) .. (name or ("Item " .. id)) .. "|r")
        local auto = subKind and subKind ~= "" and subKind or kind
        self.sub:SetText(subtitle or auto or "")
    end
    I.attach(b, function(self) return self.itemID end)
    return b
end
