-- Dungeon Journal look: the "Bosses & drops" page of one dungeon (data from ns.loot.bossesOf).
-- Left: boss rows (round portrait + level badge). Right: the selected boss and its loot rows (ns.journalItems).
-- Contract: context/dungeon-journal-contract.md
local ADDON, ns = ...
local B = {}
ns.dungeonBossesUI = B
local S = ns.style

local EJ = "Interface\\EncounterJournal\\UI-EJ-BOSS-"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local LEFT_W, ROW_W, ROW_H, ROW_GAP = 340, 315, 55, 6
local LOOT_W, LOOT_H, LOOT_GAP = 388, 52, 6
local LOOT_TOP = 102                         -- first loot row when the boss has no journal description
local DESC_Y, DESC_LINES, LINE_H = 96, 5, 14 -- the description under the boss name: at most 5 lines
local SIDE_X, ABIL_H, QUEST_H, MAX_QUESTS = LOOT_W + 32, 44, 16, 5
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local W -- the built page
local view = { token = 0, bosses = {}, selected = 1, offset = 0, lootOffset = 0 }

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

-- Portrait source chain: Blizzard's Encounter Journal art by boss name, then the creature's display ID, then the skull.
function B.portrait(texture, boss)
    boss = boss or {}
    if type(boss.name) == "string" and type(GetFileIDFromPath) == "function" then
        for _, path in ipairs(B.journalNames(boss.name)) do
            local ok, id = pcall(GetFileIDFromPath, path)
            if ok and id then
                texture:SetTexture(path)
                texture:SetTexCoord(.25, .75, 0, 1) -- the 128x64 art, centre square for the round mask
                texture.journalPath = path
                return "journal"
            end
        end
    end
    if boss.displayID and type(SetPortraitTextureFromCreatureDisplayID) == "function"
        and pcall(SetPortraitTextureFromCreatureDisplayID, texture, boss.displayID) then
        texture:SetTexCoord(0, 1, 0, 1)
        return "display"
    end
    texture:SetTexture(SKULL)
    texture:SetTexCoord(0, 1, 0, 1)
    return "skull"
end

local function roundPortrait(parent, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetWidth(size); t:SetHeight(size)
    if T() and T().round then T().round(t, parent, size) end
    return t
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
    if not (boss and boss.npcID and D and type(D.questsForNpc) == "function") then return {} end
    local ok, list = pcall(D.questsForNpc, boss.npcID, view.area) -- the page's dungeon, also when the filter is 0
    if not ok or type(list) ~= "table" then return {} end
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
-- the facts line: level, rank (QuestieDB npc rank, when known) and the number of drops
function B.facts(boss)
    if not boss then return "" end
    local parts = {}
    if boss.level then parts[#parts + 1] = "Level " .. boss.level end
    local rank = boss.rank
    if rank == nil and boss.npcID and ns.questie and ns.questie.get then
        local ok, v = pcall(ns.questie.get, "npc", boss.npcID, "rank")
        if ok then rank = v end
    end
    if boss.rare then rank = rank == 1 and 2 or (rank or 4) end
    if RANKS[tonumber(rank)] then parts[#parts + 1] = RANKS[tonumber(rank)] end
    local n = #(boss.items or {})
    parts[#parts + 1] = n == 1 and "1 drop" or (n .. " drops")
    return table.concat(parts, " · ")
end

local paint

local function wheel(frame, fn)
    if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
    frame:SetScript("OnMouseWheel", function(_, delta) fn(delta > 0 and -1 or 1) end)
end

local function bossRow(parent, i)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(ROW_W); b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -(44 + (i - 1) * (ROW_H + ROW_GAP)))
    T().panel(b, "row")
    local c = T().C.rowSelected
    b.sel = S.fill(b, "BORDER", c[1], c[2], c[3], c[4] or 1); b.sel:SetAllPoints(b); b.sel:Hide()
    if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD") end
    b.portrait = roundPortrait(b, 44); b.portrait:SetPoint("LEFT", b, "LEFT", 6, 0)
    b.badge = T().badge(b, nil, 22); b.badge:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 1)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.name:SetPoint("LEFT", b, "LEFT", 62, 0); b.name:SetWidth(ROW_W - 72)
    if b.name.SetJustifyH then b.name:SetJustifyH("LEFT") end
    b:SetScript("OnClick", function(self)
        if not self.index then return end
        view.selected, view.lootOffset = self.index, 0
        paint()
    end)
    wheel(b, function(d) B.scroll(d) end)
    return b
end

local function lootRow(parent, i)
    local b = ns.journalItems.button(parent, LOOT_W, LOOT_H)
    T().panel(b, "lootRow")
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
    W.title = text(W.left, "GameFontNormalLarge", 14, 14, LEFT_W - 28); W.title:SetText("Bosses"); color(W.title, "title")
    W.rowCount = math.max(1, math.floor((height - 50) / (ROW_H + ROW_GAP)))
    for i = 1, W.rowCount do W.rows[i] = bossRow(W.left, i) end
    W.leftStatus = text(W.left, "GameFontHighlightSmall", 14, height - 24, LEFT_W - 28); color(W.leftStatus, "muted")
    wheel(W.left, function(d) B.scroll(d) end)

    W.right = CreateFrame("Frame", nil, f)
    W.right:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT_W + 16, 0); W.right:SetWidth(width - LEFT_W - 16); W.right:SetHeight(height)
    T().panel(W.right, "right")
    W.portrait = roundPortrait(W.right, 68); W.portrait:SetPoint("TOPLEFT", W.right, "TOPLEFT", 16, -14)
    W.badge = T().badge(W.right, nil, 28); W.badge:SetPoint("TOPLEFT", W.right, "TOPLEFT", 10, -58)
    W.name = text(W.right, "GameFontNormalHuge", 96, 34, width - LEFT_W - 130); color(W.name, "title")
    local rightW = width - LEFT_W - 16
    W.facts = text(W.right, "GameFontHighlightSmall", 96, 64, rightW - 110); color(W.facts, "muted")
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
    W.note = text(W.right, "GameFontHighlightSmall", 16, height - 26, width - LEFT_W - 50); color(W.note, "muted")
    wheel(W.right, function(d) B.scrollLoot(d) end)
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

local function showPortrait(texture, badge, boss)
    texture.source = B.portrait(texture, boss)
    texture:Show()
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

paint = function()
    if not W then return end
    local bosses = view.bosses
    view.offset = math.max(0, math.min(view.offset, math.max(0, #bosses - W.rowCount)))
    for i, row in ipairs(W.rows) do
        local index = view.offset + i
        local boss = bosses[index]
        row.index, row.boss = boss and index or nil, boss
        if boss then
            row.name:SetText(boss.name)
            color(row.name, index == view.selected and "title" or "text")
            showPortrait(row.portrait, row.badge, boss)
            if index == view.selected then row.sel:Show() else row.sel:Hide() end
            row:Show()
        else row:Hide() end
    end
    W.leftStatus:SetText(#bosses > W.rowCount
        and ((view.offset + 1) .. "-" .. math.min(#bosses, view.offset + W.rowCount) .. " of " .. #bosses .. " (mouse wheel)") or "")

    local boss = bosses[view.selected]
    local status
    if view.loading then status = "Loading drops…"
    elseif not boss then
        status = view.reason or "No bosses known for this dungeon."
        if view.source ~= "AtlasLoot" then status = status .. "\n\nInstall AtlasLoot for full drops." end
    elseif #(boss.items or {}) == 0 then status = "No drops listed for " .. boss.name .. "." end
    local current = boss and not view.loading and boss or nil
    if current then
        showPortrait(W.portrait, W.badge, boss)
        W.name:SetText(boss.name); W.name:Show()
        W.facts:SetText(B.facts(boss)); W.facts:Show()
    else
        W.portrait:Hide(); W.badge:Hide(); W.name:SetText(""); W.name:Hide()
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
    local note = {}
    if #items > W.lootCount then
        note[#note + 1] = (view.lootOffset + 1) .. "-" .. math.min(#items, view.lootOffset + W.lootCount) .. " of " .. #items .. " drops (mouse wheel)"
    end
    if boss and not view.loading and view.source ~= "AtlasLoot" then note[#note + 1] = "Partial QuestieDB drops. Install AtlasLoot for full drops." end
    W.note:SetText(table.concat(note, " · "))
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
    if W then W.frame:Hide() end
end

function B.refresh() if W and W.frame:IsShown() then paint() end end
function B._window() return W end
function B._view() return view end
