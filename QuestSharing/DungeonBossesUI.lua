-- Dungeon Journal look: the "Bosses & drops" page of one dungeon (data from ns.loot.bossesOf).
-- Left: boss rows (round portrait + level badge). Right: the selected boss and its loot rows (ns.journalItems).
-- Contract: context/dungeon-journal-contract.md
local ADDON, ns = ...
ns.inModule("dungeons")          -- Modules.lua: Settings > General > Tools can switch this off
local B = {}
ns.dungeonBossesUI = B
local S = ns.style

local EJ = "Interface\\EncounterJournal\\UI-EJ-BOSS-"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local LEFT_W, ROW_W, ROW_H, ROW_GAP = 340, 314, 52, 8 -- calm list: pitch 60, 8 rows at 560
local LOOT_W, LOOT_H, LOOT_GAP = 384, 50, 9          -- pitch 59
local FOREVER_AREA = 16000                           -- our Forever-only area IDs start here: no journal art by name
local PORTRAIT_WAIT, MAX_LIVE = 3, 24                -- staged display portraits: render wait (s), live textures at most
-- the calm palette (one accent gold)
local SLOT, SLOT_TOP, SLOT_BOTTOM = { .145, .094, .043, 1 }, { .35, .24, .11, .6 }, { 0, 0, 0, .5 }
local SEL_FILL, SEL_EDGE = { .34, .23, .11, 1 }, { .80, .57, .21, .8 }
local NAME_C, NAME_SEL, CREAM = { .82, .75, .60 }, { .95, .75, .32 }, { .93, .84, .66 }
local DARK, SKULL_TINT, SKULL_ALPHA = { .055, .047, .04, 1 }, { .55, .50, .45 }, .6
local LOOT_TOP = 102                         -- first loot row when the boss has no journal description
local DESC_Y, DESC_LINES, LINE_H = 96, 5, 14 -- the description under the boss name: at most 5 lines
local SIDE_X, ABIL_H, QUEST_H, MAX_QUESTS = 420, 44, 16, 5 -- side column x kept where it was
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local W -- the built page
local view = { token = 0, bosses = {}, selected = 1, offset = 0, lootOffset = 0, asked = {} }

local function T() return ns.journalTheme end
local function color(fs, role)
    local c = T() and T().C and T().C[role]
    if c and fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3]) end
end
local function text(parent, font, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    if width then fs:SetWidth(width) end
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    return fs
end
local function hasScript(frame, name)
    if frame.GetScript then return frame:GetScript(name) ~= nil end
    return type(frame.scripts) == "table" and frame.scripts[name] ~= nil
end

-- The Encounter Journal file names: some keep the spaces ("UI-EJ-BOSS-Mutanus the Devourer"), some drop them
-- ("UI-EJ-BOSS-EdwinVanCleef"). Paths are case-insensitive, so no case variants.
function B.journalNames(name)
    local list, seen = {}, {}
    local function add(n) if n ~= "" and not seen[n] then seen[n] = true; list[#list + 1] = EJ .. n end end
    if type(name) ~= "string" then return list end
    add(name)
    add((string.gsub(name, "%s+", "")))
    add((string.gsub(name, "[^%w]", ""))) -- also drops punctuation: "Mr. Smite" -> "MrSmite"
    return list
end

local function setAlpha(t, a)
    t.jAlpha = a -- kept for tests (the mock has no GetAlpha)
    if t.SetAlpha then pcall(t.SetAlpha, t, a) end
end
local function tint(t, r, g, b, a)
    if t.SetVertexColor then t:SetVertexColor(r, g, b, 1) end
    setAlpha(t, a or 1)
end

-- Staged display portraits. SetPortraitTextureFromCreatureDisplayID draws black until the model is loaded, so it
-- renders into a texture on an off-screen holding frame (W.stage); after PORTRAIT_WAIT the texture moves onto the
-- host (the row or header portrait), whose own texture hides meanwhile. Entries: { tex, id, host, ready, attached,
-- tok, last }; at most MAX_LIVE, cached by display ID, least-recently-used reuse of ones not on a shown row.
local live, tick = {}, 0

local function park(e) -- back on the stage, out of sight; the render stays in the texture
    local t = e.tex
    t:SetParent(W.stage); t:ClearAllPoints(); t:SetPoint("TOPLEFT", W.stage, "TOPLEFT", 0, 0)
    t:SetWidth(64); t:SetHeight(64)
    t:Hide()
    e.attached = false
end

local function detach(e)
    local host = e.host
    if e.attached then park(e) end
    if host then
        if host.jLive == e then host.jLive = nil end
        host.staged = nil
        host:Show()
    end
    e.host = nil
end

local function attach(e)
    local host, t = e.host, e.tex
    t:SetParent((host.GetParent and host:GetParent()) or host.parent)
    t:ClearAllPoints()
    local n = (host.GetNumPoints and host:GetNumPoints()) or 1
    for i = 1, n do
        local p, rel, rp, x, y = host:GetPoint(i)
        if p then t:SetPoint(p, rel, rp, x, y) end
    end
    t:SetWidth(host:GetWidth()); t:SetHeight(host:GetHeight())
    if host.GetDrawLayer and t.SetDrawLayer then
        local ok, layer, sub = pcall(host.GetDrawLayer, host)
        if ok and layer then pcall(t.SetDrawLayer, t, layer, sub or 0) end
    end
    t:SetTexCoord(0, 1, 0, 1) -- the host's display-portrait look, not its placeholder tint
    tint(t, 1, 1, 1, 1)
    t:Show(); host:Hide()
    e.attached, host.staged = true, t
end

local function release(e)
    e.tok = (e.tok or 0) + 1 -- its timer, if any, is stale now
    detach(e)
    e.tex:SetTexture(nil)
    e.id, e.ready = nil, false
end

-- every live portrait is emptied (page hidden, another dungeon, loading screen); the texture objects are reused
function B.releasePortraits()
    for _, e in ipairs(live) do release(e) end
end
function B._portraits() return live end

local function onShownRow(e)
    local host = e.host
    if not (host and host.jLive == e) then return false end
    local parent = (host.GetParent and host:GetParent()) or host.parent
    return (W.frame:IsShown() and (not parent or not parent.IsShown or parent:IsShown())) and true or false
end

local function acquire()
    for _, e in ipairs(live) do
        if not e.id and not e.host then return e end
    end
    if #live < MAX_LIVE then
        local e = { tex = W.stage:CreateTexture(nil, "ARTWORK"), tok = 0 }
        live[#live + 1] = e
        park(e)
        return e
    end
    local best
    for _, e in ipairs(live) do
        if not onShownRow(e) and (not best or (e.last or 0) < (best.last or 0)) then best = e end
    end
    if best then release(best) end
    return best
end

local function stage(host, id)
    tick = tick + 1
    local cur = host.jLive
    if cur and cur.id == id then -- already there, or still on its way
        cur.last = tick
        if cur.ready and not cur.attached then attach(cur) end
        return true
    end
    if cur then detach(cur) end
    for _, e in ipairs(live) do
        if e.id == id and not e.host then -- cached: rendered before (or still rendering) for another host
            e.host, e.last = host, tick
            host.jLive = e
            if e.ready then attach(e) end
            return true
        end
    end
    local e = acquire()
    if not e then return false end
    park(e); e.tex:Show()
    if not pcall(SetPortraitTextureFromCreatureDisplayID, e.tex, id) then
        e.tex:SetTexture(nil); e.tex:Hide()
        return false
    end
    e.id, e.host, e.last, e.ready = id, host, tick, false
    host.jLive = e
    e.tok = e.tok + 1
    local tok = e.tok
    ns.after(PORTRAIT_WAIT, function()
        if e.tok ~= tok then return end -- released or reused meanwhile
        e.ready = true
        local h = e.host
        if h and h.jLive == e and h.jWant == id and W.frame:IsShown() then attach(e) end
    end)
    return true
end

local function drop(texture)
    if texture.jLive then detach(texture.jLive) end
end

-- the muted placeholder: the skull, dimmed, on the dark disc (portrait.back)
local function placeholder(texture)
    texture:SetTexture(SKULL)
    texture:SetTexCoord(0, 1, 0, 1)
    tint(texture, SKULL_TINT[1], SKULL_TINT[2], SKULL_TINT[3], SKULL_ALPHA)
end

-- In-game display IDs (ns.bossPortraitResolver) for bosses with no journal art and no baked displayID
local function npcOf(boss)
    local id = tonumber(boss.npcID)
    if not id and type(boss.npcIDs) == "table" then id = tonumber(boss.npcIDs[1]) end
    return id
end
local function resolver() return ns.bossPortraitResolver end
local function resolved(npc)
    local R = resolver()
    if not (R and type(R.displayFor) == "function") then return nil end
    local ok, d = pcall(R.displayFor, npc)
    return ok and tonumber(d) or nil
end

local showPortrait
local painting = false
-- a lookup came back: repaint the rows and the header of that npc (the staged display path takes it from there)
local function repaintNpc(npc)
    if painting or not (W and W.frame:IsShown()) or view.loading then return end
    for _, row in ipairs(W.rows) do
        if row.boss and row:IsShown() and npcOf(row.boss) == npc then showPortrait(row.portrait, row.badge, row.boss) end
    end
    local boss = view.bosses[view.selected]
    if boss and npcOf(boss) == npc then showPortrait(W.portrait, W.badge, boss) end
end

-- ask the resolver once per page for a boss of the dungeon being shown (it keeps at most 12 queued)
local function ask(npc, area)
    local R = resolver()
    if not (R and type(R.request) == "function" and W and W.stage and W.frame:IsShown()) then return end
    if type(SetPortraitTextureFromCreatureDisplayID) ~= "function" then return end -- nothing could draw it
    if view.loading or area ~= tonumber(view.area) or view.asked[npc] then return end
    local token = view.token
    local ok, queued = pcall(R.request, npc, function()
        if token ~= view.token then return end -- another dungeon, or the page was hidden / shown again
        repaintNpc(npc)
    end)
    if ok and queued then view.asked[npc] = true end -- not queued (full): asked again on a later paint
end

-- Portrait source chain (returns the source):
-- 1. "journal": the boss's Encounter Journal art: boss.ejFile (FileDataID), else by name (classic areas only;
--    Forever-only areas have same-named art of other creatures);
-- 2. "display": the creature's display portrait, staged off-screen (see stage): boss.displayID, else the one the
--    client told the resolver (ns.bossPortraitResolver; asked for when unknown, the row repaints when it arrives);
-- 3. "skull": the muted placeholder.
function B.portrait(texture, boss, area)
    boss = boss or {}
    area = tonumber(area or view.area)
    texture.journalPath, texture.ejFile = nil, nil
    local ej = tonumber(boss.ejFile)
    if ej then
        drop(texture)
        texture:SetTexture(ej)
        texture:SetTexCoord(.25, .75, 0, 1) -- the 128x64 art, centre square for the round mask
        tint(texture, 1, 1, 1, 1)
        texture.ejFile, texture.jWant, texture.displayID = ej, nil, nil
        return "journal"
    end
    if area and area < FOREVER_AREA and type(GetFileIDFromPath) == "function" then
        local names = {}
        if type(boss.name) == "string" then names[#names + 1] = boss.name end
        if type(boss.npcName) == "string" and boss.npcName ~= boss.name then names[#names + 1] = boss.npcName end
        for _, n in ipairs(names) do
            for _, path in ipairs(B.journalNames(n)) do
                local ok, id = pcall(GetFileIDFromPath, path)
                if ok and id then
                    drop(texture)
                    texture:SetTexture(path)
                    texture:SetTexCoord(.25, .75, 0, 1)
                    tint(texture, 1, 1, 1, 1)
                    texture.journalPath, texture.jWant, texture.displayID = path, nil, nil
                    return "journal"
                end
            end
        end
    end
    local display = tonumber(boss.displayID)
    texture.resolved = nil
    local npc = not display and npcOf(boss) or nil
    if npc then
        display = resolved(npc)
        if not display then ask(npc, area); display = resolved(npc) end -- a cached creature may answer at once
        texture.resolved = display and true or nil
    end
    if display and W and W.stage and type(SetPortraitTextureFromCreatureDisplayID) == "function" then
        placeholder(texture) -- shown until the staged portrait arrives
        texture.jWant, texture.displayID = display, display
        if stage(texture, display) then return "display" end
    end
    drop(texture)
    texture.jWant, texture.displayID = nil, nil
    placeholder(texture)
    return "skull"
end

-- a round portrait (mask only, no ring) on a dark disc (texture.back)
local function roundPortrait(parent, size)
    local back = parent:CreateTexture(nil, "ARTWORK", nil, -2)
    back:SetTexture(MASK); back:SetWidth(size); back:SetHeight(size)
    if back.SetVertexColor then back:SetVertexColor(DARK[1], DARK[2], DARK[3], DARK[4]) end
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetWidth(size); t:SetHeight(size)
    if T() and T().round then T().round(t, parent, size, { ring = false }) end
    back:SetPoint("CENTER", t, "CENTER", 0, 0)
    t.back = back
    return t
end

-- the flat slot of boss and loot rows: fill, a faint 1px top line, a dark 1px bottom line (no edge, no parchment)
local function slotLines(b)
    local th = T()
    b.top = th.fill(b, "BORDER", SLOT_TOP)
    b.top:SetHeight(1); b.top:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); b.top:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    b.bottom = th.fill(b, "BORDER", SLOT_BOTTOM)
    b.bottom:SetHeight(1); b.bottom:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); b.bottom:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
end

-- selected: a lighter fill (b.sel) and a 1px gold outline (b.selEdges), shown together
local function selectable(b)
    local th = T()
    b.sel = th.fill(b, "BACKGROUND", SEL_FILL, nil, 1); b.sel:SetAllPoints(b)
    b.selEdges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = th.fill(b, "OVERLAY", SEL_EDGE)
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(1); t:SetPoint(side .. "LEFT", b, side .. "LEFT", 0, 0); t:SetPoint(side .. "RIGHT", b, side .. "RIGHT", 0, 0)
        else
            t:SetWidth(1); t:SetPoint("TOP" .. side, b, "TOP" .. side, 0, 0); t:SetPoint("BOTTOM" .. side, b, "BOTTOM" .. side, 0, 0)
        end
        b.selEdges[#b.selEdges + 1] = t
    end
end
local function setSelected(b, on)
    if on then b.sel:Show() else b.sel:Hide() end
    for _, t in ipairs(b.selEdges) do if on then t:Show() else t:Hide() end end
end

local function subtitle(id)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not fn then return nil end
    local ok, name, _, _, _, _, _, subType, _, loc = pcall(fn, id)
    if not ok or not name then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        return nil
    end
    local slot = type(loc) == "string" and loc ~= "" and _G[loc]
    slot = type(slot) == "string" and slot ~= "" and slot or nil
    local sub = type(subType) == "string" and subType ~= "" and subType ~= "Miscellaneous" and subType ~= slot and subType or nil
    if slot and sub then return slot .. ", " .. sub end
    return slot or sub
end

-- Native item tooltip + Shift compare; only used while ns.journalItems.button has no hover of its own.
local function fallbackHover(b)
    b:SetScript("OnEnter", function(self)
        if not self.bossItemID or not GameTooltip then return end
        pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.bossItemID)
            GameTooltip:Show()
            if IsShiftKeyDown and IsShiftKeyDown() and GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
        end)
    end)
    b:SetScript("OnLeave", function()
        if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
        for _, tip in ipairs({ _G.ShoppingTooltip1, _G.ShoppingTooltip2 }) do pcall(tip.Hide, tip) end
    end)
end

-- a text cut at a word, with "…", when longer than n characters
local function shorten(str, n)
    str = tostring(str or "")
    if #str <= n then return str, false end
    local head = string.sub(str, 1, n)
    head = string.match(head, "^(.*)%s%S*$") or head
    return (string.gsub(head, "[%s,;:%.]+$", "")) .. "…", true
end
B.shorten = shorten

local function tip(owner, title, body)
    if not GameTooltip then return end
    pcall(function()
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if body and body ~= "" then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
end
local function untip() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end

-- the boss's Encounter Journal entry (ns.dungeonLore), or nil
function B.lore(boss)
    local L = ns.dungeonLore
    if not (boss and L and type(L.boss) == "function") then return nil end
    local ok, entry = pcall(L.boss, boss.name)
    return ok and type(entry) == "table" and entry or nil
end

-- the spell icon: the client's spell texture, then the journal's icon FileDataID, then the question mark
function B.abilityIcon(ability)
    local id = ability and tonumber(ability.spellID)
    if id then
        local fns = { C_Spell and C_Spell.GetSpellTexture or false, GetSpellTexture or false } -- no nil holes for ipairs
        for _, fn in ipairs(fns) do
            if type(fn) == "function" then
                local ok, tex = pcall(fn, id)
                if ok and tex then return tex end
            end
        end
    end
    return ability and tonumber(ability.icon) or QUESTION
end

-- quests of this dungeon that ask to kill this boss: ns.dungeonQuests.questsForNpc (nil-guarded), as titles
function B.neededFor(boss)
    local D = ns.dungeonQuests
    if not (boss and D and type(D.questsForNpc) == "function") then return {} end
    local ids, seenID = {}, {}
    local function addID(v) v = tonumber(v); if v and not seenID[v] then seenID[v] = true; ids[#ids + 1] = v end end
    addID(boss.npcID)
    if type(boss.npcIDs) == "table" then for _, v in ipairs(boss.npcIDs) do addID(v) end end
    local list = {}
    for _, npc in ipairs(ids) do
        local ok, got = pcall(D.questsForNpc, npc, view.area) -- the page's dungeon, also when the filter is 0
        if ok and type(got) == "table" then for _, q in ipairs(got) do list[#list + 1] = q end end
    end
    local out, byID, seen = {}, {}, {}
    for _, q in ipairs(list) do
        local id, title
        if type(q) == "table" then
            id, title = tonumber(q.id or q.questID), q.name or q.title
        else
            id = tonumber(q)
        end
        if id and not title and ns.questie and ns.questie.get then
            local okName, name = pcall(ns.questie.get, "quest", id, "name")
            if okName and type(name) == "string" then title = name end
        end
        if id and not title and C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local okTitle, name = pcall(C_QuestLog.GetTitleForQuestID, id)
            if okTitle and type(name) == "string" and name ~= "" then title = name end
        end
        local known = title ~= nil
        title = title or (id and ("Quest " .. id))
        local row = id and byID[id]
        if row then
            if known and not row.known then row.title, row.known = title, true end -- a bare id, then its record
        elseif title and not seen[title] then
            row = { id = id, title = title, known = known }
            seen[title] = true; out[#out + 1] = row
            if id then byID[id] = row end
        end
    end
    return out
end

local RANKS = { [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }
-- the facts line: level, rank (QuestieDB npc rank, when known; not for official bosses: QuestieDB ranks are
-- unreliable there, e.g. "Rare Elite" on VanCleef) and the number of drops; " (optional)" for optional encounters
function B.facts(boss)
    if not boss then return "" end
    local parts = {}
    if boss.level then parts[#parts + 1] = "Level " .. boss.level end
    if not boss.official then
        local rank = boss.rank
        if rank == nil and boss.npcID and ns.questie and ns.questie.get then
            local ok, v = pcall(ns.questie.get, "npc", boss.npcID, "rank")
            if ok then rank = v end
        end
        if boss.rare then rank = rank == 1 and 2 or (rank or 4) end
        if RANKS[tonumber(rank)] then parts[#parts + 1] = RANKS[tonumber(rank)] end
    end
    local n = #(boss.items or {})
    parts[#parts + 1] = n == 1 and "1 drop" or (n .. " drops")
    local line = table.concat(parts, " · ")
    if boss.optional then line = line .. " (optional)" end
    return line
end

local paint

local function wheel(frame, fn)
    if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
    frame:SetScript("OnMouseWheel", function(_, delta) fn(delta > 0 and -1 or 1) end)
end

local function groupTip(self)
    local boss = self.boss
    if not (boss and boss.group and type(boss.members) == "table" and #boss.members > 0 and GameTooltip) then return end
    pcall(function()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(boss.name)
        for _, m in ipairs(boss.members) do GameTooltip:AddLine(m, 1, 1, 1) end
        GameTooltip:Show()
    end)
end

local function bossRow(parent, i)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(ROW_W); b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -(44 + (i - 1) * (ROW_H + ROW_GAP)))
    b.bg = T().fill(b, "BACKGROUND", SLOT); b.bg:SetAllPoints(b)
    slotLines(b)
    selectable(b); setSelected(b, false)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetTexture(HIGHLIGHT); b.hl:SetAllPoints(b)
    if b.hl.SetBlendMode then b.hl:SetBlendMode("ADD") end
    setAlpha(b.hl, .35)
    if b.SetHighlightTexture then pcall(b.SetHighlightTexture, b, b.hl, "ADD") end
    b.portrait = roundPortrait(b, 44); b.portrait:SetPoint("LEFT", b, "LEFT", 5, 0)
    b.badge = T().badge(b, nil, 24, { flat = true, font = 11 })
    b.badge:SetPoint("CENTER", b.portrait, "BOTTOMLEFT", 9, 3) -- hangs ~6px below the row, inside the 8px gap
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.name:SetPoint("LEFT", b, "LEFT", 62, 0); b.name:SetWidth(ROW_W - 72)
    T().font(b.name, 12, NAME_C)
    if b.name.SetJustifyH then b.name:SetJustifyH("LEFT") end
    if b.name.SetWordWrap then b.name:SetWordWrap(false) end
    b:SetScript("OnClick", function(self)
        if not self.index then return end
        view.selected, view.lootOffset = self.index, 0
        paint()
    end)
    b:SetScript("OnEnter", groupTip)
    b:SetScript("OnLeave", untip)
    wheel(b, function(d) B.scroll(d) end)
    return b
end

local function lootRow(parent, i)
    local b = ns.journalItems.button(parent, LOOT_W, LOOT_H)
    -- the boss rows' flat slot: recolour the button's own fill, hide its edge lines
    if b.bg then T().color(b.bg, SLOT) else b.bg = T().fill(b, "BACKGROUND", SLOT); b.bg:SetAllPoints(b) end
    for _, t in ipairs(b.edges or {}) do t:Hide() end
    slotLines(b)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -(LOOT_TOP + (i - 1) * (LOOT_H + LOOT_GAP)))
    if not hasScript(b, "OnEnter") then fallbackHover(b) end
    wheel(b, function(d) B.scrollLoot(d) end)
    return b
end

local function abilityRow(parent, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(width); b:SetHeight(ABIL_H - 4)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetWidth(20); b.icon:SetHeight(20)
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -1)
    if b.icon.SetTexCoord then b.icon:SetTexCoord(.08, .92, .08, .92) end
    b.name = text(b, "GameFontNormalSmall", 26, 0, width - 26); color(b.name, "title")
    b.text = text(b, "GameFontHighlightSmall", 26, 13, width - 26); color(b.text, "text")
    if b.text.SetWordWrap then b.text:SetWordWrap(true) end
    b:SetScript("OnEnter", function(self) if self.ability then tip(self, self.ability.name, self.ability.text) end end)
    b:SetScript("OnLeave", untip)
    return b
end

local function questRow(parent, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(width); b:SetHeight(QUEST_H)
    b.label = text(b, "GameFontHighlightSmall", 0, 2, width); color(b.label, "text")
    if b.label.SetWordWrap then b.label:SetWordWrap(false) end
    b:SetScript("OnEnter", function(self)
        if self.quest then
            tip(self, self.quest.title, "A quest of this dungeon asks you to kill this boss." .. (self.quest.id and "\nClick: open it in Quests." or ""))
        end
    end)
    b:SetScript("OnLeave", untip)
    b:SetScript("OnClick", function(self) -- open the quest on the Quests tab (D.openQuest resets hiding filters)
        local D, q = ns.dungeonQuests, self.quest
        if q and q.id and D and type(D.openQuest) == "function" then untip(); pcall(D.openQuest, q.id) end
    end)
    return b
end

function B.build(parent, width, height)
    if W then return W.frame end
    if not parent or not T() or not ns.journalItems then return nil end
    width, height = width or 1000, height or 560
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0); f:SetWidth(width); f:SetHeight(height)
    W = { frame = f, rows = {}, loot = {}, width = width, height = height }
    W.left = CreateFrame("Frame", nil, f)
    W.left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); W.left:SetWidth(LEFT_W); W.left:SetHeight(height)
    T().panel(W.left, "left")
    if W.left.jPage then W.left.jPage:Hide() end -- calm: no parchment behind the list
    W.title = text(W.left, "GameFontNormalLarge", 14, 14, LEFT_W - 28); W.title:SetText("Bosses"); color(W.title, "title")
    W.rowCount = math.max(1, math.floor((height - 50) / (ROW_H + ROW_GAP)))
    for i = 1, W.rowCount do W.rows[i] = bossRow(W.left, i) end
    W.leftStatus = text(W.left, "GameFontHighlightSmall", 14, height - 24, LEFT_W - 28); color(W.leftStatus, "muted")
    W.leftStatus:Hide()
    wheel(W.left, function(d) B.scroll(d) end)

    W.right = CreateFrame("Frame", nil, f)
    W.right:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT_W + 16, 0); W.right:SetWidth(width - LEFT_W - 16); W.right:SetHeight(height)
    T().panel(W.right, "right")
    if W.right.jPage then W.right.jPage:Hide() end
    W.portrait = roundPortrait(W.right, 68); W.portrait:SetPoint("TOPLEFT", W.right, "TOPLEFT", 16, -14)
    W.badge = T().badge(W.right, nil, 30, { flat = true, font = 13 })
    W.badge:SetPoint("CENTER", W.portrait, "BOTTOMLEFT", 7, 3)
    local rightW = width - LEFT_W - 16
    W.name = text(W.right, "GameFontNormalHuge", 100, 30, rightW - 116); T().font(W.name, 16, CREAM)
    if W.name.SetWordWrap then W.name:SetWordWrap(false) end
    W.facts = text(W.right, "GameFontHighlightSmall", 100, 54, rightW - 116); T().font(W.facts, 10, T().C.muted)
    W.descW = rightW - 32
    W.desc = text(W.right, "GameFontHighlight", 16, DESC_Y, W.descW); color(W.desc, "text")
    if W.desc.SetWordWrap then W.desc:SetWordWrap(true) end
    W.desc:Hide()
    W.descHit = CreateFrame("Frame", nil, W.right) -- hover the cut description for all of it
    W.descHit:SetPoint("TOPLEFT", W.right, "TOPLEFT", 16, -DESC_Y); W.descHit:SetWidth(rightW - 32); W.descHit:SetHeight(LINE_H)
    if W.descHit.EnableMouse then W.descHit:EnableMouse(true) end
    W.descHit:SetScript("OnEnter", function(self) if self.full then tip(self, self.title or "", self.full) end end)
    W.descHit:SetScript("OnLeave", untip)
    W.descHit:Hide()
    W.side = CreateFrame("Frame", nil, W.right)
    W.sideW = rightW - SIDE_X - 12
    W.side:SetPoint("TOPLEFT", W.right, "TOPLEFT", SIDE_X, -LOOT_TOP); W.side:SetWidth(W.sideW); W.side:SetHeight(height - LOOT_TOP - 30)
    W.abilityHead = text(W.side, "GameFontNormal", 0, 0, W.sideW); W.abilityHead:SetText("Abilities"); color(W.abilityHead, "title")
    W.questHead = text(W.side, "GameFontNormal", 0, 0, W.sideW); W.questHead:SetText("Needed for"); color(W.questHead, "title")
    W.abilities, W.quests = {}, {}
    for i = 1, 4 do W.abilities[i] = abilityRow(W.side, W.sideW) end
    for i = 1, MAX_QUESTS do W.quests[i] = questRow(W.side, W.sideW) end
    W.questMore = text(W.side, "GameFontDisableSmall", 0, 0, W.sideW); color(W.questMore, "muted")
    W.status = text(W.right, "GameFontNormal", 16, 110, LOOT_W); color(W.status, "text") -- not into the side column
    if W.status.SetWordWrap then W.status:SetWordWrap(true) end
    W.lootMax = math.max(1, math.floor((height - LOOT_TOP - 38) / (LOOT_H + LOOT_GAP)))
    W.lootCount = W.lootMax -- rows that fit under the description; paint sets it
    for i = 1, W.lootMax do W.loot[i] = lootRow(W.right, i) end
    -- under the drops: the drop counter (only on overflow) and, on its own line, the AtlasLoot hint (W.note)
    W.count = text(W.right, "GameFontHighlightSmall", 16, height - 34, LOOT_W); color(W.count, "muted")
    W.note = text(W.right, "GameFontHighlightSmall", 16, height - 20, LOOT_W); color(W.note, "muted")
    wheel(W.right, function(d) B.scrollLoot(d) end)
    -- staged display portraits render off-screen first (see stage)
    W.stage = CreateFrame("Frame", nil, UIParent)
    W.stage:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 10000, 0); W.stage:SetWidth(64); W.stage:SetHeight(64)
    W.stage:Show()
    ns.on("PLAYER_LEAVING_WORLD", function() B.releasePortraits() end)
    ns.on("GET_ITEM_INFO_RECEIVED", function(_, id)
        local boss = W.frame:IsShown() and view.bosses[view.selected]
        if not boss or view.pending then return end
        for _, item in ipairs(boss.items or {}) do
            if item == id then
                view.pending = true
                ns.after(0.2, function() view.pending = false; if W.frame:IsShown() then paint() end end)
                return
            end
        end
    end)
    f:Hide()
    return f
end

showPortrait = function(texture, badge, boss)
    texture.source = B.portrait(texture, boss, view.area)
    texture.back:Show()
    if not texture.staged then texture:Show() end -- a staged display portrait stands in for it
    badge:SetLevel(boss.level)
    if boss.level then badge:Show() else badge:Hide() end
end

-- The description under the boss name (at most 5 lines, hover for all of it), then a side column right of the
-- drops: "Abilities" (icon, name, short text; hover = the full text) and "Needed for" (quests that kill this boss).
-- A heading only shows when it has rows. Returns the y where the drops start.
function B.paintLore(boss)
    local entry = boss and B.lore(boss)
    local top = LOOT_TOP
    local desc = entry and type(entry.description) == "string" and entry.description ~= "" and entry.description
    if desc then
        local perLine = math.max(20, math.floor(W.descW / 6.2))
        local short, cut = shorten(desc, perLine * DESC_LINES - 4)
        W.desc:SetText(short); W.desc:Show()
        local h = (W.desc.GetStringHeight and W.desc:GetStringHeight()) or 0
        if not h or h <= 0 then h = math.ceil(#short / perLine) * LINE_H end
        h = math.min(h, DESC_LINES * LINE_H)
        if W.desc.SetHeight then W.desc:SetHeight(h) end
        W.descHit:SetHeight(h); W.descHit.full, W.descHit.title = cut and desc or nil, boss.name; W.descHit:Show()
        top = math.max(LOOT_TOP, DESC_Y + h + 12)
    else
        W.desc:SetText(""); W.desc:Hide(); W.descHit.full = nil; W.descHit:Hide()
    end
    W.side:ClearAllPoints(); W.side:SetPoint("TOPLEFT", W.right, "TOPLEFT", SIDE_X, -top)
    local y = 0
    local abilities = entry and type(entry.abilities) == "table" and entry.abilities or {}
    if #abilities > 0 then
        W.abilityHead:ClearAllPoints(); W.abilityHead:SetPoint("TOPLEFT", W.side, "TOPLEFT", 0, -y); W.abilityHead:Show()
        y = y + 20
    else W.abilityHead:Hide() end
    for i, row in ipairs(W.abilities) do
        local a = abilities[i]
        row.ability = a
        if a then
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", W.side, "TOPLEFT", 0, -y)
            row.icon:SetTexture(B.abilityIcon(a))
            row.name:SetText(a.name or "")
            row.text:SetText((shorten(a.text, 64)))
            row:Show(); y = y + ABIL_H
        else row:Hide() end
    end
    local quests = boss and B.neededFor(boss) or {}
    if #quests > 0 then
        if y > 0 then y = y + 8 end
        W.questHead:ClearAllPoints(); W.questHead:SetPoint("TOPLEFT", W.side, "TOPLEFT", 0, -y); W.questHead:Show()
        y = y + 20
    else W.questHead:Hide() end
    for i, row in ipairs(W.quests) do
        local q = quests[i]
        row.quest = q
        if q then
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", W.side, "TOPLEFT", 0, -y)
            row.label:SetText(q.title); row:Show(); y = y + QUEST_H
        else row:Hide() end
    end
    if #quests > MAX_QUESTS then
        W.questMore:ClearAllPoints(); W.questMore:SetPoint("TOPLEFT", W.side, "TOPLEFT", 0, -y)
        W.questMore:SetText("+" .. (#quests - MAX_QUESTS) .. " more"); W.questMore:Show()
    else W.questMore:SetText(""); W.questMore:Hide() end
    if y > 0 then W.side:Show() else W.side:Hide() end
    return top
end

local function paintAll()
    local bosses = view.bosses
    view.offset = math.max(0, math.min(view.offset, math.max(0, #bosses - W.rowCount)))
    for i, row in ipairs(W.rows) do
        local index = view.offset + i
        local boss = bosses[index]
        row.index, row.boss = boss and index or nil, boss
        if boss then
            row.name:SetText(boss.name)
            local c = index == view.selected and NAME_SEL or NAME_C
            if row.name.SetTextColor then row.name:SetTextColor(c[1], c[2], c[3]) end
            showPortrait(row.portrait, row.badge, boss)
            setSelected(row, index == view.selected)
            row:Show()
        else row:Hide() end
    end
    if #bosses > W.rowCount then -- the footer only when the list overflows (BRD, Stratholme, Dire Maul)
        W.leftStatus:SetText((view.offset + 1) .. "-" .. math.min(#bosses, view.offset + W.rowCount) .. " of " .. #bosses)
        W.leftStatus:Show()
    else
        W.leftStatus:SetText(""); W.leftStatus:Hide()
    end

    local boss = bosses[view.selected]
    local status
    if view.loading then status = "Loading drops…"
    elseif not boss then
        status = view.reason or "No bosses known for this dungeon."
    elseif #(boss.items or {}) == 0 then status = "No drops listed for " .. boss.name .. "." end
    local current = boss and not view.loading and boss or nil
    if current then
        showPortrait(W.portrait, W.badge, boss)
        W.name:SetText(boss.name); W.name:Show()
        W.facts:SetText(B.facts(boss)); W.facts:Show()
    else
        drop(W.portrait)
        W.portrait:Hide(); W.portrait.back:Hide(); W.badge:Hide(); W.name:SetText(""); W.name:Hide()
        W.facts:SetText(""); W.facts:Hide()
    end
    local top = B.paintLore(current)
    W.status:ClearAllPoints(); W.status:SetPoint("TOPLEFT", W.right, "TOPLEFT", 16, -(top + 8))
    W.status:SetText(status or "")
    if status then W.status:Show() else W.status:Hide() end
    local items = current and boss.items or {}
    W.lootCount = math.max(1, math.min(W.lootMax, math.floor((W.height - top - 38) / (LOOT_H + LOOT_GAP))))
    view.lootOffset = math.max(0, math.min(view.lootOffset, math.max(0, #items - W.lootCount)))
    for i, b in ipairs(W.loot) do
        local id = i <= W.lootCount and items[view.lootOffset + i] or nil
        b.bossItemID = id
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", W.right, "TOPLEFT", 16, -(top + (i - 1) * (LOOT_H + LOOT_GAP)))
        if id then b:SetItem(id, subtitle(id)); b:Show() else b:Hide() end
    end
    local hint = not view.loading and view.source ~= "AtlasLoot"
    W.note:SetText(hint and "Install AtlasLoot for full drops." or "")
    if hint then W.note:Show() else W.note:Hide() end
    if #items > W.lootCount then
        W.count:ClearAllPoints(); W.count:SetPoint("TOPLEFT", W.right, "TOPLEFT", 16, -(W.height - (hint and 34 or 20)))
        W.count:SetText((view.lootOffset + 1) .. "-" .. math.min(#items, view.lootOffset + W.lootCount) .. " of " .. #items .. " drops")
        W.count:Show()
    else
        W.count:SetText(""); W.count:Hide()
    end
end

paint = function()
    if not W then return end
    painting = true -- a lookup answered during this paint is picked up by it (no nested repaint)
    local ok, err = pcall(paintAll)
    painting = false
    if not ok then error(err, 0) end
end

function B.scroll(delta)
    if not W then return false end
    local before = view.offset
    view.offset = math.max(0, math.min(view.offset + delta, math.max(0, #view.bosses - W.rowCount)))
    if view.offset ~= before then paint(); return true end
    return false
end
function B.scrollLoot(delta)
    local boss = W and view.bosses[view.selected]
    if not boss then return false end
    local before = view.lootOffset
    view.lootOffset = math.max(0, math.min(view.lootOffset + delta, math.max(0, #(boss.items or {}) - W.lootCount)))
    if view.lootOffset ~= before then paint(); return true end
    return false
end

-- area: the dungeon's area ID; name: its name (as on the dungeon header).
function B.show(area, name)
    if not W then return false end
    view.token = view.token + 1
    local token = view.token
    if view.area ~= area then -- another dungeon: free every live portrait, drop the old dungeon's lookups
        B.releasePortraits()
        local R = resolver()
        if R and type(R.clear) == "function" then pcall(R.clear) end
    end
    view.asked = {}
    if view.area ~= area or view.name ~= name then view.selected, view.offset, view.lootOffset = 1, 0, 0 end
    view.area, view.name, view.bosses, view.loading, view.source, view.reason = area, name, {}, true, nil, nil
    W.frame:Show()
    paint()
    local function done(list, source, reason)
        if token ~= view.token then return end -- an older request (another dungeon, or the page was hidden)
        view.bosses, view.source, view.reason, view.loading = type(list) == "table" and list or {}, source, reason, false
        if view.selected > #view.bosses then view.selected = 1 end
        if view.want then
            local want = view.want
            view.want = nil
            -- a name that is not in this dungeon's list is dropped, so it never lands in another dungeon later
            if not B.select(want) then view.want = nil; paint() end
        else
            paint()
        end
    end
    if not (ns.loot and ns.loot.bossesOf) then done({}, nil, "The loot reader is not available."); return true end
    local ok, err = pcall(ns.loot.bossesOf, name, done, area)
    if not ok then done({}, nil, "Could not read the drops: " .. tostring(err)) end
    return true
end

local function indexOf(bossName)
    local want = string.lower(tostring(bossName or ""))
    for i, boss in ipairs(view.bosses) do
        if string.lower(tostring(boss.name or "")) == want then return i end
    end
end

-- Select a boss by name (another page, e.g. a quest's item, opens the Bosses tab on its boss).
-- While the bosses are still loading the name is kept and applied when they arrive.
-- Returns true when the boss is selected now or will be after loading; false when it is not in the shown list
-- (the name is then kept for the next B.show, so a select made before the tab opens still lands).
function B.select(bossName)
    if type(bossName) ~= "string" or bossName == "" then return false end
    if not W or view.loading then view.want = bossName; return W ~= nil end
    local i = indexOf(bossName)
    if not i then view.want = bossName; return false end -- may be for a dungeon shown next: applied once then
    view.want = nil
    view.selected, view.lootOffset = i, 0
    if i <= view.offset or i > view.offset + W.rowCount then view.offset = i - 1 end -- paint clamps it
    paint()
    return true
end

function B.hide()
    view.token = view.token + 1
    if W then W.frame:Hide(); B.releasePortraits() end
    local R = resolver()
    if R and type(R.clear) == "function" then pcall(R.clear) end
end

function B.refresh() if W and W.frame:IsShown() then paint() end end
function B._window() return W end
function B._view() return view end
