-- Dungeon Journal look: the home page. A search box, Alliance/Horde crest filters and a full-width 2-column grid of dungeon
-- cards (client loading-screen art, title band, LV range, open/total quests, a tick when nothing is left).
-- Contract: context/dungeon-journal-contract.md
local ADDON, ns = ...
ns.inModule("dungeons")          -- Modules.lua: Settings > General > Tools can switch this off
local H = {}
ns.dungeonHomeUI = H
local T = ns.journalTheme

local CARD_H, GAP, ROW, MARGIN = 126, 12, 138, 6
local BAND, BAR = 42, 44
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"
local CLEAR = "Interface\\Buttons\\UI-StopButton"
-- two columns that fill the page: (width - margins - gap) / 2, 488 px in a 1000 px page
local function cardWidth(width) return math.floor(((width or 1000) - 2 * MARGIN - GAP) / 2) end
local CARD_W = cardWidth(1000)
H.CARD_W, H.CARD_H, H.GAP, H.ROW, H.MARGIN, H.cardWidth = CARD_W, CARD_H, GAP, ROW, MARGIN, cardWidth

local home -- the page frame
local rows = {} -- the last D.summaries() rows
local onOpenFn

local function lower(s) return string.lower(tostring(s or "")) end
local function yes(v) return v ~= nil and v ~= false and v ~= 0 end

-- the four edges of a card, so the hover can turn them gold
local function setBorder(card, c)
    for _, e in ipairs(card.edges) do T.color(e, c) end
    card.borderColor = c
end
local function edges(card)
    card.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local e = T.fill(card, "OVERLAY", T.C.border)
        if side == "TOP" or side == "BOTTOM" then
            e:SetHeight(2); e:SetPoint(side .. "LEFT", card, side .. "LEFT", 0, 0); e:SetPoint(side .. "RIGHT", card, side .. "RIGHT", 0, 0)
        else
            e:SetWidth(2); e:SetPoint("TOP" .. side, card, "TOP" .. side, 0, 0); e:SetPoint("BOTTOM" .. side, card, "BOTTOM" .. side, 0, 0)
        end
        card.edges[#card.edges + 1] = e
    end
end

local function lvText(row)
    local lo, hi = tonumber(row.minLevel), tonumber(row.maxLevel)
    if lo and hi and lo ~= hi then return "LV " .. lo .. "-" .. hi end
    if lo or hi then return "LV " .. (lo or hi) end
    return ""
end
H.lvText = lvText

local function countText(row)
    local open, total = tonumber(row.open) or 0, tonumber(row.total) or 0
    return open .. "/" .. total .. (total == 1 and " quest" or " quests")
end
H.countText = countText

-- the journal description of a dungeon (ns.dungeonLore, nil-guarded), or nil
local function loreOf(row)
    local L = ns.dungeonLore
    if not (row and L and type(L.dungeon) == "function") then return nil end
    local ok, entry = pcall(L.dungeon, row.area, row.name)
    local text = ok and type(entry) == "table" and entry.description
    return type(text) == "string" and text ~= "" and text or nil
end
H.loreOf = loreOf

-- the card hover: name, level range, quest counts and the journal description
function H.tooltipLines(row)
    local lines = {}
    if not row then return lines end
    local lv = lvText(row)
    if lv ~= "" then lines[#lines + 1] = { text = "Level " .. string.sub(lv, 4), color = T.C.text } end
    local open, total, done = tonumber(row.open) or 0, tonumber(row.total) or 0, tonumber(row.done) or 0
    local counts = total .. (total == 1 and " quest" or " quests") .. ": " .. open .. " to pick up"
    if done > 0 then counts = counts .. ", " .. done .. " done" end
    lines[#lines + 1] = { text = counts, color = T.C.text }
    local lore = loreOf(row)
    if lore then lines[#lines + 1] = { text = lore, color = T.C.muted, wrap = true } end
    lines[#lines + 1] = { text = "Click to open the dungeon.", color = T.GOLD }
    return lines
end

local function showTip(card)
    if not (GameTooltip and card.row) then return end
    local row = card.row
    pcall(function()
        GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.name or ("Dungeon " .. tostring(row.area)))
        for _, line in ipairs(H.tooltipLines(row)) do
            local c = line.color or {}
            GameTooltip:AddLine(line.text, c[1] or 1, c[2] or 1, c[3] or 1, line.wrap and true or false)
        end
        GameTooltip:Show()
    end)
end
local function hideTip() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end

local function newCard(parent)
    local card = CreateFrame("Button", nil, parent)
    card:SetWidth(CARD_W); card:SetHeight(CARD_H)
    card.base = T.fill(card, "BACKGROUND", T.C.frame, 1, -8)
    card.base:SetAllPoints(card)
    card.art = card:CreateTexture(nil, "BACKGROUND")
    T.try(card.art, "SetDrawLayer", "BACKGROUND", -6)
    card.art:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
    card.art:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
    card.band = T.fill(card, "BORDER", { 0, 0, 0, .62 })
    card.band:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
    card.band:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)
    card.band:SetHeight(BAND)
    card.shade = T.fill(card, "BORDER", { 0, 0, 0, .45 })
    card.shade:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 2, 2)
    card.shade:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
    card.shade:SetHeight(20)
    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -13)
    card.title:SetWidth(CARD_W - 150); T.try(card.title, "SetJustifyH", "LEFT"); T.try(card.title, "SetWordWrap", false)
    T.textColor(card.title, T.C.title); T.shadow(card.title)
    card.count = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.count:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -16)
    T.try(card.count, "SetJustifyH", "RIGHT")
    T.textColor(card.count, T.C.text); T.shadow(card.count)
    card.crests = { Alliance = T.crest(card, "Alliance", 20), Horde = T.crest(card, "Horde", 20) }
    card.lv = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.lv:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 6)
    T.textColor(card.lv, T.C.text); T.shadow(card.lv)
    card.tick = T.tick(card, 22)
    card.tick:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 4)
    card.tick:Hide()
    card.glow = T.glow(card, 46)
    card.glow:SetPoint("CENTER", card.tick, "CENTER", 0, 0)
    card.glow:Hide()
    edges(card)
    setBorder(card, T.C.border)
    card:RegisterForClicks("LeftButtonUp")
    card:SetScript("OnEnter", function(self) self.hover = true; setBorder(self, T.GOLD); showTip(self) end)
    card:SetScript("OnLeave", function(self) self.hover = false; setBorder(self, T.C.border); hideTip() end)
    card:SetScript("OnClick", function(self) if self.row and onOpenFn then onOpenFn(self.row.area) end end)
    return card
end

-- art from the theme's loading-screen table, else the tinted rock
local function paintArt(card, area)
    local file, l, r, t, b = T.cardArt(area)
    local ok, res = false, nil
    if file then ok, res = pcall(card.art.SetTexture, card.art, file) end
    if file and ok and res ~= false then
        T.try(card.art, "SetTexCoord", l, r, t, b)
        T.try(card.art, "SetVertexColor", 1, 1, 1, 1)
        card.artFile, card.fallback = file, false
    else
        T.try(card.art, "SetTexture", ROCK, "REPEAT", "REPEAT")
        T.try(card.art, "SetTexCoord", 0, 1, 0, 1)
        T.try(card.art, "SetVertexColor", .62, .48, .32, 1)
        card.artFile, card.fallback = ROCK, true
    end
end

local function paint(card, row)
    card.row = row
    paintArt(card, row.area)
    card.title:SetText(row.name or ("Dungeon " .. tostring(row.area)))
    card.lv:SetText(lvText(row))
    card.count:SetText(countText(row))
    -- crests left of the count, Horde nearest
    local anchor = card.count
    for _, faction in ipairs({ "Horde", "Alliance" }) do
        local crest = card.crests[faction]
        if yes(row[string.lower(faction)]) then
            crest:ClearAllPoints()
            crest:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
            crest:Show(); anchor = crest
        else
            crest:Hide()
        end
    end
    local open, total = tonumber(row.open) or 0, tonumber(row.total) or 0
    card.done = open == 0 and total > 0
    if card.done then card.tick:Show(); card.glow:Show() else card.tick:Hide(); card.glow:Hide() end
    card:Show()
end

local function matches(row)
    local text = lower(home and home.query)
    if text ~= "" and not string.find(lower(row.name), text, 1, true) then
        -- a quest title in the dungeon also matches (D.summaries rows carry row.quests)
        local hit = false
        if type(row.quests) == "table" then
            for _, title in ipairs(row.quests) do
                if string.find(lower(title), text, 1, true) then hit = true; break end
            end
        end
        if not hit then return false end
    end
    local faction = home and home.faction
    if faction == "Alliance" and not yes(row.alliance) then return false end
    if faction == "Horde" and not yes(row.horde) then return false end
    return true
end

local function layout()
    if not home then return end
    local shown = {}
    for _, row in ipairs(rows) do if matches(row) then shown[#shown + 1] = row end end
    for i, row in ipairs(shown) do
        local card = home.cards[i]
        if not card then card = newCard(home.content); home.cards[i] = card end
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", home.content, "TOPLEFT", col * (CARD_W + GAP), -line * ROW)
        if not card.hover then setBorder(card, T.C.border) end
        paint(card, row)
    end
    for i = #shown + 1, #home.cards do home.cards[i].row = nil; home.cards[i]:Hide() end
    home.visible = shown
    home.content:SetHeight(math.max(1, math.ceil(#shown / 2) * ROW))
    if #rows == 0 then home.status:SetText("Reading dungeon quests...")
    elseif #shown == 0 then home.status:SetText("No dungeon matches your search.")
    else home.status:SetText("") end
    local range = T.try(home.scroll, "GetVerticalScrollRange") or 0
    if (T.try(home.scroll, "GetVerticalScroll") or 0) > range then home.scroll:SetVerticalScroll(range) end
end

local function setFaction(faction)
    home.faction = (home.faction ~= faction) and faction or nil
    for _, f in ipairs({ "Alliance", "Horde" }) do
        local b = home[string.lower(f)]
        b.selected = home.faction == f
        T.try(b.crest, "SetDesaturated", home.faction ~= nil and home.faction ~= f)
        T.try(b.crest, "SetAlpha", (home.faction == nil or home.faction == f) and 1 or .45)
        if b.selected then T.color(b.ring, T.GOLD, .9); b.ring:Show() else b.ring:Hide() end
    end
    layout()
end

local function crestButton(parent, faction, x)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(34); b:SetHeight(34)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -5)
    b.ring = T.fill(b, "BACKGROUND", T.GOLD, .9)
    b.ring:SetAllPoints(b); b.ring:Hide()
    b.disc = T.fill(b, "BORDER", T.C.frame)
    b.disc:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2); b.disc:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.crest = T.crest(b, faction, 28)
    b.crest:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.faction = faction
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() setFaction(faction) end)
    b:SetScript("OnEnter", function(self)
        if GameTooltip then pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(faction .. " dungeons")
            GameTooltip:AddLine("Show only dungeons with " .. faction .. " quests. Click again for all.", 1, 1, 1, true)
            GameTooltip:Show()
        end) end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end)
    return b
end

function H.build(parent, width, height, onOpen)
    onOpenFn = onOpen or onOpenFn
    if home then return home end
    width, height = width or 1000, height or 560
    CARD_W = cardWidth(width); H.CARD_W = CARD_W
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width); f:SetHeight(height)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    home = f
    f.cards, f.visible, f.query, f.faction = {}, {}, "", nil

    -- top bar: search, crest filters; the shell anchors its check boxes to f.bar's right side
    f.bar = CreateFrame("Frame", nil, f)
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.bar:SetWidth(width); f.bar:SetHeight(BAR)
    local box = CreateFrame("EditBox", nil, f.bar)
    box:SetWidth(260); box:SetHeight(24)
    box:SetPoint("TOPLEFT", f.bar, "TOPLEFT", MARGIN, -10)
    T.panel(box, "frame", 10)
    if ChatFontNormal then box:SetFontObject(ChatFontNormal) end
    box:SetAutoFocus(false); box:SetMaxLetters(60)
    T.try(box, "SetTextInsets", 24, 24, 0, 0)
    box.icon = box:CreateTexture(nil, "OVERLAY")
    box.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    box.icon:SetWidth(14); box.icon:SetHeight(14)
    box.icon:SetPoint("LEFT", box, "LEFT", 7, -1)
    box.hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    box.hint:SetPoint("LEFT", box, "LEFT", 25, 0)
    box.hint:SetText("Search for dungeons...")
    -- clear button (the client's stop cross), shown while there is text
    box.clear = CreateFrame("Button", nil, box)
    box.clear:SetWidth(16); box.clear:SetHeight(16)
    box.clear:SetPoint("RIGHT", box, "RIGHT", -5, 0)
    if not T.hasFile or T.hasFile(CLEAR) then
        box.clear.icon = box.clear:CreateTexture(nil, "ARTWORK")
        box.clear.icon:SetTexture(CLEAR); box.clear.icon:SetAllPoints(box.clear)
        box.clear.hl = box.clear:CreateTexture(nil, "HIGHLIGHT")
        box.clear.hl:SetTexture(CLEAR); box.clear.hl:SetAllPoints(box.clear); T.try(box.clear.hl, "SetBlendMode", "ADD")
    else -- texture missing: a plain "x" so the button is never invisible
        box.clear.label = box.clear:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        box.clear.label:SetPoint("CENTER", box.clear, "CENTER", 0, 0)
        box.clear.label:SetText("x")
    end
    box.clear:Hide()
    local function clearSearch()
        box:SetText(""); f.query = ""; box.hint:Show(); box.clear:Hide(); layout()
    end
    box.clear:RegisterForClicks("LeftButtonUp")
    box.clear:SetScript("OnClick", function() clearSearch(); box:ClearFocus() end)
    box.clear:SetScript("OnEnter", function(self)
        if GameTooltip then pcall(function() GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Clear search"); GameTooltip:Show() end) end
    end)
    box.clear:SetScript("OnLeave", function() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end)
    box:SetScript("OnTextChanged", function(self)
        f.query = self:GetText() or ""
        if f.query == "" then self.hint:Show(); self.clear:Hide() else self.hint:Hide(); self.clear:Show() end
        layout()
    end)
    box:SetScript("OnEscapePressed", function(self) clearSearch(); self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.search = box
    f.alliance = crestButton(f.bar, "Alliance", MARGIN + 276)
    f.horde = crestButton(f.bar, "Horde", MARGIN + 316)
    f.rule = T.fill(f, "ARTWORK", T.C.border, .7)
    f.rule:SetHeight(1)
    f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -BAR - 2); f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -BAR - 2)

    -- the card grid, full page width, one row per wheel step
    local gridW = CARD_W * 2 + GAP
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", MARGIN, -BAR - 10)
    scroll:SetWidth(gridW); scroll:SetHeight(height - BAR - 10)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(gridW); content:SetHeight(1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local pos = self:GetVerticalScroll() - delta * ROW
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), pos)))
    end)
    f.scroll, f.content = scroll, content
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.status:SetPoint("TOP", f, "TOP", 0, -BAR - 40)
    T.textColor(f.status, T.C.muted)
    layout()
    return f
end

-- repaint from D.summaries() rows (read from ns.dungeonQuests when none are passed)
function H.refresh(summaries)
    if summaries == nil then
        local D = ns.dungeonQuests
        local ok, list = false, nil
        if D and type(D.summaries) == "function" then ok, list = pcall(D.summaries) end
        summaries = ok and type(list) == "table" and list or rows
    end
    rows = type(summaries) == "table" and summaries or {}
    layout()
end

function H.show() if home then home:Show(); layout() end end
function H.hide() if home then home:Hide() end end
function H._frame() return home end
