-- Dungeon Journal look: palette and small builders. Client textures only (paths or FileDataIDs), no bundled media.
-- Contract: context/dungeon-journal-contract.md
local ADDON, ns = ...
local T = {}
ns.journalTheme = T
local S = ns.style

-- palette roles: boxes are {r,g,b,a}, text is {r,g,b}
T.C = {
    frame = {.030,.026,.020,.99}, content = {.24,.18,.10,.90}, border = {.52,.36,.16,1}, header = {.26,.18,.09,.94},
    left = {.18,.12,.06,.94}, right = {.20,.14,.07,.94}, row = {.14,.09,.045,.92}, rowSelected = {.36,.22,.08,.95},
    lootRow = {.17,.11,.06,.94}, title = {1,.80,.34}, text = {.93,.84,.66}, muted = {.82,.74,.60},
}
T.GOLD = {1, .82, .25, 1}       -- hover / selected border

local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local QUESTBG = "Interface\\QuestFrame\\QuestBG"
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- call obj:method(...) only when the client (or the test mock) has it
local function try(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, obj, ...)
    if ok then return a end
end
T.try = try

-- colour a texture; the colour is also kept on it (tex.rgba) so callers and tests can read it back
function T.color(tex, c, alpha)
    local r, g, b, a = c[1], c[2], c[3], alpha or c[4] or 1
    if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a) else tex:SetTexture(WHITE8); tex:SetVertexColor(r, g, b, a) end
    tex.rgba = { r, g, b, a }
    return tex
end
function T.fill(frame, layer, c, alpha, sub)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    T.color(t, c, alpha)
    if sub then try(t, "SetDrawLayer", layer or "BACKGROUND", sub) end
    return t
end
function T.textColor(fs, c) try(fs, "SetTextColor", c[1], c[2], c[3]) end
function T.shadow(fs) try(fs, "SetShadowColor", 0, 0, 0, 1); try(fs, "SetShadowOffset", 1, -1) end
function T.font(fs, size, c)
    try(fs, "SetFont", STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    if c then T.textColor(fs, c) end
    return fs
end

local function inside(t, frame, inset)
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
end

-- the tooltip edge, drawn by a child frame so it works on frames created without BackdropTemplate
local function edgeFrame(frame, size, c)
    local ok, e = pcall(CreateFrame, "Frame", nil, frame, "BackdropTemplate")
    if not (ok and e) then ok, e = pcall(CreateFrame, "Frame", nil, frame) end
    if not (ok and e) then return nil end
    e:SetAllPoints(frame)
    pcall(function()
        e:SetBackdrop({ edgeFile = EDGE, edgeSize = size, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
        e:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
    end)
    e.edgeSize, e.rgba = size, { c[1], c[2], c[3], c[4] or 1 }
    function e:SetEdgeColor(col)
        self.rgba = { col[1], col[2], col[3], col[4] or 1 }
        try(self, "SetBackdropBorderColor", col[1], col[2], col[3], col[4] or 1)
    end
    return e
end
T.edgeFrame = edgeFrame

-- Base of every box: a flat fill in the role colour, a faint parchment under the tint, the tooltip edge.
function T.panel(frame, role, edge)
    local c = T.C[role or "content"] or T.C.content
    edge = edge or 12
    local inset = math.floor(edge / 4)
    local fill = T.fill(frame, "BACKGROUND", c, nil, -8)
    inside(fill, frame, inset)
    local page = frame:CreateTexture(nil, "BACKGROUND")
    page:SetTexture(QUESTBG)
    try(page, "SetDrawLayer", "BACKGROUND", -7)
    try(page, "SetTexCoord", 0, .586, 0, .65)
    try(page, "SetAlpha", .14)
    inside(page, frame, inset)
    frame.jFill, frame.jPage = fill, page
    frame.jEdge = edgeFrame(frame, edge, T.C.border)
    frame.jRole = role or "content"
    return frame
end

-- The quest detail page: the client's parchment over the whole frame.
function T.parchment(frame)
    local page = frame:CreateTexture(nil, "BACKGROUND")
    page:SetTexture(QUESTBG)
    try(page, "SetTexCoord", 0, .586, 0, .65)
    page:SetAllPoints(frame)
    frame.jPage = page
    frame.jEdge = edgeFrame(frame, 12, T.C.border)
    return frame
end

-- small dark button with a gold label and the quest-title glow on hover
function T.button(parent, label, width, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(width or 100); b:SetHeight(22)
    b.bg = T.fill(b, "BACKGROUND", { .07, .05, .035, .94 })
    b.bg:SetAllPoints(b)
    b.edge = edgeFrame(b, 10, T.C.border)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetTexture(HIGHLIGHT); try(b.hl, "SetBlendMode", "ADD"); inside(b.hl, b, 2)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    T.textColor(b.label, T.C.title); T.shadow(b.label)
    b.text = label or ""
    b.label:SetText(b.text)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, which) if onClick then onClick(self, which) end end)
    b:SetScript("OnEnter", function(self)
        if tip and GameTooltip then
            pcall(function() GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show() end)
        end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end)
    function b:SetLabel(t) self.text = t; self.label:SetText(t) end
    return b
end

-- a page tab: the client's red panel button when it has the template, else our panel button; icon on the left
function T.tab(parent, label, icon, width, onClick)
    width = width or 110
    local b
    local ok, made = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
    if ok and made and type(made.GetFontString) == "function" and made:GetFontString() then
        b = made
        b:SetWidth(width); b:SetHeight(26)
        b:SetText(label or "")
        b.text = label or ""
        b:SetScript("OnClick", function(self, which) if onClick then onClick(self, which) end end)
        function b:SetLabel(t) self.text = t; self:SetText(t) end
        b.template = true
    else
        b = S.button(parent, label or "", width, onClick)
        b:SetHeight(26)
    end
    if icon then
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetTexture(icon)
        b.icon:SetWidth(16); b.icon:SetHeight(16)
        b.icon:SetPoint("LEFT", b, "LEFT", 8, 0)
        if type(icon) == "string" and string.find(icon, "Icons\\", 1, true) then try(b.icon, "SetTexCoord", .08, .92, .08, .92) end
        -- the template centres its label: keep it right of the icon so narrow tabs do not overlap
        local fs = b.template and b:GetFontString()
        if fs then
            try(fs, "ClearAllPoints")
            try(fs, "SetPoint", "LEFT", b.icon, "RIGHT", 4, 0)
            try(fs, "SetPoint", "RIGHT", b, "RIGHT", -6, 0)
        end
    end
    b.mark = T.fill(b, "OVERLAY", T.GOLD, .9)
    b.mark:SetHeight(2)
    b.mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 6, 3); b.mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -6, 3)
    b.mark:Hide()
    function b:SetSelected(on)
        self.selected = on and true or false
        if self.selected then
            self.mark:Show(); try(self, "LockHighlight")
            if self.bg then try(self.bg, "SetVertexColor", 1, .85, .55) end
        else
            self.mark:Hide(); try(self, "UnlockHighlight")
            if self.bg then try(self.bg, "SetVertexColor", 1, 1, 1) end
        end
    end
    b:SetSelected(false)
    return b
end

-- the XP / money / reputation chips
T.PILLS = {
    xp = { fill = { .36, .18, .56, .90 }, edge = { .66, .44, .92, 1 }, text = { .95, .88, 1 } },
    money = { fill = { .20, .15, .06, .92 }, edge = { .70, .55, .22, 1 }, text = { 1, .86, .40 }, icon = "Interface\\MoneyFrame\\UI-GoldIcon" },
    rep = { fill = { .12, .34, .12, .90 }, edge = { .40, .78, .36, 1 }, text = { .82, 1, .78 } },
}
function T.pill(parent, kind, text)
    local style = T.PILLS[kind] or T.PILLS.money
    local f = CreateFrame("Frame", nil, parent)
    f.kind = kind
    f:SetWidth(116); f:SetHeight(24)
    f.bg = T.fill(f, "BACKGROUND", style.fill)
    inside(f.bg, f, 2)
    f.edge = edgeFrame(f, 8, style.edge)
    local x = 8
    if style.icon then
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetTexture(style.icon); f.icon:SetWidth(12); f.icon:SetHeight(12)
        f.icon:SetPoint("LEFT", f, "LEFT", 7, 0)
        x = 22
    end
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("LEFT", f, "LEFT", x, 0)
    T.textColor(f.text, style.text)
    function f:SetText(v)
        self.text:SetText(v or "")
        local w = try(self.text, "GetStringWidth")
        if type(w) == "number" and w > 0 then self:SetWidth(math.max(48, math.ceil(w) + x + 10)) end
    end
    f:SetText(text or "")
    return f
end

-- faction crest from the target frame's PvP icon, cropped to the badge
function T.crest(parent, faction, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetWidth(size or 20); t:SetHeight(size or 20)
    t:SetTexture(faction == "Horde" and "Interface\\TargetingFrame\\UI-PVP-Horde" or "Interface\\TargetingFrame\\UI-PVP-Alliance")
    try(t, "SetTexCoord", 0, .625, 0, .625)
    t.faction = faction == "Horde" and "Horde" or "Alliance"
    return t
end

-- dark round disc, the minimap tracking ring around it, the level number on top
function T.badge(parent, level, size)
    size = size or 28
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(size); f:SetHeight(size)
    f.disc = f:CreateTexture(nil, "BACKGROUND")
    f.disc:SetTexture(MASK); f.disc:SetAllPoints(f)
    try(f.disc, "SetVertexColor", .07, .05, .03, 1)
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    -- the ring's hole sits at the top left of the art: 53 px art around a 20 px icon at 7,-5
    local k = size / 20
    f.ring:SetWidth(53 * k); f.ring:SetHeight(53 * k)
    f.ring:SetPoint("TOPLEFT", f, "TOPLEFT", -7 * k, 5 * k)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    T.textColor(f.text, T.C.title)
    function f:SetLevel(n) self.level = n; self.text:SetText(n and tostring(n) or "") end
    f:SetLevel(level)
    return f
end

function T.tick(parent, size)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetWidth(size or 22); t:SetHeight(size or 22)
    t:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    return t
end

-- masks a texture round and puts a gold ring over it
function T.round(texture, parent, size)
    parent = parent or try(texture, "GetParent") or texture.parent
    if size then texture:SetWidth(size); texture:SetHeight(size) end
    local masked = false
    if parent and parent.CreateMaskTexture and texture.AddMaskTexture then
        local ok = pcall(function()
            local m = parent:CreateMaskTexture()
            m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(texture)
            texture:AddMaskTexture(m)
            texture.jMask = m
        end)
        masked = ok
    end
    if not masked and texture.SetMask then masked = pcall(texture.SetMask, texture, MASK) end
    texture.rounded = masked
    if parent then
        local ring = parent:CreateTexture(nil, "OVERLAY")
        ring:SetTexture("Interface\\Common\\GoldRing")
        ring:SetPoint("TOPLEFT", texture, "TOPLEFT", -2, 2)
        ring:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT", 2, -2)
        texture.jRing = ring
    end
    return texture
end

-- Card art: the client's own loading screen of each dungeon. Classic files by path, Forever files by FileDataID.
local LS = "Interface\\Glues\\LoadingScreens\\"
T.ART = {
    [2437] = { LS .. "LoadScreenRagefireChasm" },                               -- Ragefire Chasm
    [718] = { LS .. "LoadScreenWailingCaverns" },                               -- Wailing Caverns
    [1581] = { LS .. "LoadScreenDeadmines" },                                   -- The Deadmines
    [209] = { LS .. "LoadScreenShadowFangKeep" },                               -- Shadowfang Keep
    [717] = { LS .. "LoadScreenStormwindStockade" },                            -- The Stockade
    [719] = { LS .. "LoadScreenBlackFathomDeeps" },                             -- Blackfathom Deeps
    [721] = { LS .. "LoadScreenGnomeregan" },                                   -- Gnomeregan
    [796] = { LS .. "LoadScreenMonastery", LS .. "LoadScreenScarletMonastery2" }, -- Scarlet Monastery
    [491] = { LS .. "LoadScreenRazorfenKraul" },                                -- Razorfen Kraul
    [722] = { LS .. "LoadScreenRazorfenDowns" },                                -- Razorfen Downs
    [1337] = { LS .. "LoadScreenUldaman" },                                     -- Uldaman
    [1176] = { LS .. "LoadScreenZulFarrak" },                                   -- Zul'Farrak
    [2100] = { LS .. "LoadScreenMaraudon" },                                    -- Maraudon
    [1477] = { LS .. "LoadScreenSunkenTemple" },                                -- The Temple of Atal'Hakkar
    [1584] = { LS .. "LoadScreenBlackrockDepths" },                             -- Blackrock Depths
    [1583] = { LS .. "LoadScreenBlackrockSpire" },                              -- Blackrock Spire
    [2557] = { LS .. "LoadScreenDireMaul" },                                    -- Dire Maul
    [2057] = { LS .. "LoadScreenScholomance" },                                 -- Scholomance
    [2017] = { LS .. "LoadScreenStratHome" },                                   -- Stratholme
    [16919] = { 7963781 },  -- The Hall of Thanes: camelot160\main\loadscreen_camelot_oldironforge (to confirm in game)
    [16611] = { 7963782 },  -- Ruins of Lordaeron: loadscreen_camelot_ruinsoflordaeron
    [16732] = { 7963777 },  -- Excavation Site: Wetlands: loadscreen_camelot_excavation
    [16544] = { 7963775 },  -- City of Dalaran: loadscreen_camelot_dalaran
    [16550] = { 7963741 },  -- The Drowned City
    [16842] = { 7963780 },  -- Krol'dok Stronghold
    [16620] = { 7963734 },  -- Alcaz Prison
    [16554] = { 7963784 },  -- Blackmaw Hold
    [16667] = { 7963783 },  -- The Shaper's Terrace
}
T.ART_CROP = { .02, .98, .24, .82 } -- cuts the logo band of a loading screen

-- area id, or a dungeon name (matched through DungeonQuestData's names)
local function areaOf(area)
    if type(area) == "number" then return area end
    if type(area) == "string" then
        local n = tonumber(area)
        if n then return n end
        local names = ns.dungeonQuestData and ns.dungeonQuestData.names or {}
        for id, name in pairs(names) do if name == area then return id end end
    end
end
T.areaOf = areaOf

function T.cardArt(area)
    local list = T.ART[areaOf(area) or -1]
    if not list then return nil end
    local c = T.ART_CROP
    for _, file in ipairs(list) do
        if type(file) == "number" then return file, c[1], c[2], c[3], c[4] end
        -- where the client can tell, only a file it really has
        if type(GetFileIDFromPath) ~= "function" then return file, c[1], c[2], c[3], c[4] end
        local ok, id = pcall(GetFileIDFromPath, file)
        if ok and id then return file, c[1], c[2], c[3], c[4] end
    end
    return nil
end

-- round dungeon icon of the client's group finder
T.LFG = {
    [2437] = "RagefireChasm", [718] = "WailingCaverns", [1581] = "Deadmines", [209] = "ShadowfangKeep",
    [717] = "StormwindStockades", [719] = "BlackfathomDeeps", [721] = "Gnomeregan", [796] = "ScarletMonastery",
    [491] = "RazorfenKraul", [722] = "RazorfenDowns", [1337] = "Uldaman", [1176] = "ZulFarak", [2100] = "Maraudon",
    [1477] = "SunkenTemple", [1584] = "BlackrockDepths", [1583] = "BlackrockSpire", [2557] = "DireMaul",
    [2057] = "Scholomance", [2017] = "Stratholme", [16611] = "RuinsOfLordaeron",
}
function T.lfgIcon(area)
    local name = T.LFG[areaOf(area) or -1]
    return name and ("Interface\\LFGFrame\\LFGIcon-" .. name) or nil
end

-- Is this client file there? Unknown (no GetFileIDFromPath) counts as yes.
local function hasFile(path)
    if type(GetFileIDFromPath) ~= "function" then return true end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and id ~= nil
end
T.hasFile = hasFile

-- soft star glow (ADD blend) behind a done tick
T.GLOW = "Interface\\Cooldown\\star4"
function T.glow(parent, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    size = size or 40
    t:SetWidth(size); t:SetHeight(size)
    t:SetTexture(T.GLOW)
    try(t, "SetBlendMode", "ADD")
    try(t, "SetDrawLayer", "ARTWORK", 7)
    try(t, "SetVertexColor", .45, 1, .35, .85)
    t.blend = "ADD"
    return t
end

-- class icon from the character-create sheet, cropped with the client's CLASS_ICON_TCOORDS
T.CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
T.CLASS_COORDS = { -- used only when the client has no CLASS_ICON_TCOORDS
    WARRIOR = { 0, .25, 0, .25 }, MAGE = { .25, .49609375, 0, .25 }, ROGUE = { .49609375, .7421875, 0, .25 },
    DRUID = { .7421875, .98828125, 0, .25 }, HUNTER = { 0, .25, .25, .5 }, SHAMAN = { .25, .49609375, .25, .5 },
    PRIEST = { .49609375, .7421875, .25, .5 }, WARLOCK = { .7421875, .98828125, .25, .5 }, PALADIN = { 0, .25, .5, .75 },
}
function T.classIcon(parent, size, classToken)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetWidth(size or 16); t:SetHeight(size or 16)
    t:SetTexture(T.CLASS_SHEET)
    local token = string.upper(tostring(classToken or ""))
    local coords = (type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[token]) or T.CLASS_COORDS[token]
    if coords then try(t, "SetTexCoord", coords[1], coords[2], coords[3], coords[4]) end
    try(t, "SetDrawLayer", "ARTWORK", 2)
    t.classToken = token
    -- a class-coloured ring (a square 1 px larger on each side, behind the icon): dark icons such as the druid's stay
    -- readable at 16 px on the dark list and on parchment. It follows the icon's Show / Hide.
    local c = (type(CUSTOM_CLASS_COLORS) == "table" and CUSTOM_CLASS_COLORS[token])
        or (type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[token])
    local rgb = (type(c) == "table" and c.r) and { c.r, c.g, c.b } or T.C.muted
    local ring = parent:CreateTexture(nil, "ARTWORK")
    T.color(ring, rgb, .95)
    try(ring, "SetDrawLayer", "ARTWORK", 1)
    ring:SetPoint("TOPLEFT", t, "TOPLEFT", -1, 1)
    ring:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 1, -1)
    t.ring = ring
    local show, hide = t.Show, t.Hide
    if type(show) == "function" and type(hide) == "function" then
        t.Show = function(self, ...) ring:Show(); return show(self, ...) end
        t.Hide = function(self, ...) ring:Hide(); return hide(self, ...) end
        local setShown = t.SetShown
        if type(setShown) == "function" then
            t.SetShown = function(self, on, ...) if on then ring:Show() else ring:Hide() end; return setShown(self, on, ...) end
        end
    end
    return t
end

-- the client's "Dungeon" atlas (picked up inside the dungeon), else a rune icon
T.DUNGEON_FALLBACK = "Interface\\Icons\\INV_Misc_Rune_01"
function T.dungeonIcon(parent, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetWidth(size or 16); t:SetHeight(size or 16)
    local done = false
    if type(t.SetAtlas) == "function" then
        local known = true
        if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
            local ok, info = pcall(C_Texture.GetAtlasInfo, "Dungeon")
            known = ok and info ~= nil
        end
        if known then
            local ok, res = pcall(t.SetAtlas, t, "Dungeon")
            done = ok and res ~= false
        end
    end
    if done then
        t.atlas = "Dungeon"
    else
        t:SetTexture(T.DUNGEON_FALLBACK)
        try(t, "SetTexCoord", .08, .92, .08, .92)
    end
    return t
end

-- a chain icon for quest chains (both in the client listfile), first one the client has
T.CHAIN_ICONS = { "Interface\\Icons\\Spell_Frost_ChainsOfIce", "Interface\\Icons\\INV_Misc_WartornScrap_Chain" }
T.CHAIN_FALLBACK = "Interface\\Icons\\INV_Misc_Note_01"
function T.chainIcon(parent, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetWidth(size or 16); t:SetHeight(size or 16)
    local file = T.CHAIN_FALLBACK
    for _, path in ipairs(T.CHAIN_ICONS) do
        if hasFile(path) then file = path; break end
    end
    t:SetTexture(file)
    try(t, "SetTexCoord", .08, .92, .08, .92)
    return t
end
