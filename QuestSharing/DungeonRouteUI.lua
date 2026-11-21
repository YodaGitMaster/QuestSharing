-- Dungeon Journal look: the Route page ("get them all"): summary, notes, numbered steps with icons and times
-- (click = map pin), the flight-path check box and Refresh. The planning itself stays in DungeonQuests.lua
-- (D.routePlan) and DungeonRoute.lua. Contract: context/dungeon-journal-contract.md
local ADDON, ns = ...
ns.inModule("dungeons")          -- Modules.lua: Settings > General > Tools can switch this off
local R = {}
ns.dungeonRouteUI = R
local U, E = ns.optionalUI, ns.equipmentUI

local ROWS, ROW_H = 40, 30
local ICONS = {Walk = "Interface\\Icons\\Ability_Rogue_Sprint", Fly = "Interface\\Icons\\Ability_Mount_Gryphon_01",
    Boat = "Interface\\Icons\\INV_Misc_Anchor", Zeppelin = "Interface\\Icons\\INV_Misc_Anchor", Tram = "Interface\\Icons\\INV_Misc_Gear_01",
    Hearth = "Interface\\Icons\\INV_Misc_Rune_01", ["Pick up"] = "Interface\\GossipFrame\\AvailableQuestIcon",
    ["Hand in"] = "Interface\\GossipFrame\\ActiveQuestIcon", Enter = "Interface\\Icons\\Spell_Arcane_PortalStormwind"}
R.ICONS = ICONS

local page
local current = {area = nil, name = nil, generation = 0, result = nil}

local function theme() return ns.journalTheme or {} end
local function color(role, fallback) local c = theme().C and theme().C[role]; return c or fallback end
local function D() return ns.dungeonQuests or {} end
local function font(t, size, c) if E and E.font then E.font(t, size, c[1], c[2], c[3]) end end

-- stream B exports these; until then a plain local version
local function minutes(seconds)
    if D().minutes then return D().minutes(seconds) end
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    if seconds < 60 then return seconds .. " s" end
    return math.floor(seconds / 60 + 0.5) .. " min"
end
local function stepText(step)
    if D().routeStepText then return D().routeStepText(step) end
    return tostring(step.kind or "Go") .. " " .. tostring(step.quest or step.to or step.npc or "")
end
local function pin(step)
    if not (step and step.point) then return false end
    local place = {source = {name = step.npc or step.to or step.quest}, point = step.point}
    if D().pinPlace then return D().pinPlace(place) end
    local pt = step.point
    if pt.map and ns.compat and ns.compat.setWaypoint then ns.compat.setWaypoint(pt.map, pt.x / 100, pt.y / 100); return true end
    return false
end

local function hideRows() for _, b in ipairs(page.rows) do b.step = nil; b:Hide() end end

local function paint(result, doFirst, later)
    current.result = result
    doFirst, later = doFirst or {}, later or 0
    local name = current.name or "this dungeon"
    if ns.db and ns.db.routeAllFlights then page.assume.tick:Show() else page.assume.tick:Hide() end
    if not result then
        page.summary:SetText("Planning the route…"); page.notes:SetText(""); hideRows(); return
    end
    if result.noStart or result.nothing then
        page.summary:SetText(result.noStart and "Can't plan from here" or (name .. ": nothing left to pick up"))
        local lines = {result.noStart and "Your position is unknown, for example inside a dungeon. Step outside and press Refresh."
            or "Every quest you can take here is done or already in your quest log."}
        if #doFirst > 0 then
            lines[#lines + 1] = "Do these first: " .. doFirst[1].name .. " (needs " .. doFirst[1].needs .. ")"
                .. (#doFirst > 1 and (" +" .. (#doFirst - 1) .. " more") or "")
        end
        page.notes:SetText(table.concat(lines, "\n")); hideRows(); return
    end
    local steps = result.steps or {}
    local quests = result.quests or 0
    page.summary:SetText(name .. ": " .. quests .. " quest" .. (quests == 1 and "" or "s") .. " · about "
        .. minutes(result.totalSeconds) .. (result.hearthUsed and " · uses your hearthstone" or ""))
    local notes = {}
    if #doFirst > 0 then
        local list = {}
        for i, q in ipairs(doFirst) do if i <= 4 then list[#list + 1] = q.name .. " (needs " .. q.needs .. ")" end end
        notes[#notes + 1] = "Do these first: " .. table.concat(list, ", ") .. (#doFirst > 4 and (" +" .. (#doFirst - 4) .. " more") or "")
    end
    if result.unknown and #result.unknown > 0 then notes[#notes + 1] = "Not on the map (inside the dungeon or unknown): " .. table.concat(result.unknown, ", ") end
    if later > 0 then notes[#notes + 1] = later .. " more quest" .. (later == 1 and "" or "s") .. " need a higher level, another class or the other faction." end
    for _, n in ipairs(result.notes or {}) do notes[#notes + 1] = n end
    notes[#notes + 1] = "Times are estimates. Click a step for a map pin."
    if #steps > ROWS then notes[#notes + 1] = "Showing the first " .. ROWS .. " steps." end
    page.notes:SetText(table.concat(notes, "\n"))
    local y = 52 + math.max(14, (page.notes.GetStringHeight and page.notes:GetStringHeight() or 14))
    page.list:ClearAllPoints(); page.list:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -y)
    page.list:SetHeight(math.max(120, page.h - y - 52))
    for i, b in ipairs(page.rows) do
        local st = steps[i]
        b.step, b.index = st, i
        if st then
            b.num:SetText(i .. ".")
            b.icon:SetTexture(ICONS[st.kind] or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.text:SetText(stepText(st))
            b.time:SetText(st.seconds and st.seconds >= 1 and minutes(st.seconds) or "")
            -- "where do I go next": the route starts where you stand, so step 1 is the next thing to do
            local c = i == 1 and page.nextColor or page.rowColor
            if b.bg.SetColorTexture then b.bg:SetColorTexture(c[1], c[2], c[3], c[4] or .92) else b.bg:SetVertexColor(c[1], c[2], c[3], c[4] or .92) end
            b.bg.rgba, b.isNext = c, i == 1
            b:Show()
        else b:Hide() end
    end
    page.content:SetHeight(math.max(120, math.min(#steps, ROWS) * (ROW_H + 2)))
end

-- plan again for the shown dungeon; a late answer for an older request is dropped
function R.plan()
    if not page or not current.area then return false end
    current.generation = current.generation + 1
    local mine = current.generation
    paint(nil)
    local plan = D().routePlan
    if not plan then
        page.summary:SetText("Route planner not available"); page.notes:SetText("The quest list has not loaded the planner yet.")
        return false
    end
    local ok, started = pcall(plan, current.area, ns.db and ns.db.routeAllFlights and true or false, function(result, doFirst, later, err)
        if mine ~= current.generation or not page:IsShown() then return end
        if not result and err then
            -- the planner failed: say so instead of "Planning the route…" for ever
            current.result = nil; hideRows()
            page.summary:SetText("Could not plan the route")
            page.notes:SetText(tostring(err) .. "\nPress Refresh to try again.")
            return
        end
        paint(result, doFirst, later)
    end)
    if not ok then
        page.summary:SetText("Could not plan the route: " .. tostring(started)); return false
    end
    if started == false and mine == current.generation and not current.result then
        page.summary:SetText("The quest list is still loading"); page.notes:SetText("Press Refresh in a moment.")
    end
    return started ~= false
end

function R.build(parent, width, height)
    if page then return page end
    local T = theme()
    width, height = width or 1000, height or 560
    page = CreateFrame("Frame", nil, parent)
    page:SetWidth(width); page:SetHeight(height); page.w, page.h = width, height
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    if T.parchment then T.parchment(page) elseif T.panel then T.panel(page, "content") end
    local title, text, muted = color("title", {1, .80, .34}), color("text", {.93, .84, .66}), color("muted", {.82, .74, .60})
    -- the summary, notes and check box sit on the parchment: dark ink (the light journal text is for the dark rows)
    local INK, HEAD = {.30, .21, .10}, {.36, .20, .04}
    page.summary = U.text(page, "", 20, 16, width - 40); font(page.summary, 16, HEAD)
    page.notes = U.text(page, "", 20, 42, width - 40); font(page.notes, 12, INK)
    for _, t in ipairs({page.summary, page.notes}) do if t.SetShadowColor then t:SetShadowColor(0, 0, 0, 0) end end
    if page.notes.SetWordWrap then page.notes:SetWordWrap(true) end
    local list = CreateFrame("ScrollFrame", nil, page)
    list:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -92); list:SetWidth(width - 32); list:SetHeight(height - 144)
    local content = CreateFrame("Frame", nil, list); content:SetWidth(width - 32); content:SetHeight(120)
    list:SetScrollChild(content)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40)))
    end)
    page.list, page.content, page.rows = list, content, {}
    local rowW = width - 36
    local rowColor = color("row", {.14, .09, .045, .92})
    page.rowColor, page.nextColor = rowColor, color("rowSelected", {.30, .20, .07, .95})
    for i = 1, ROWS do
        local b = CreateFrame("Button", nil, content); b:SetWidth(rowW); b:SetHeight(ROW_H)
        b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * (ROW_H + 2))
        b.bg = ns.style.fill(b, "BACKGROUND", rowColor[1], rowColor[2], rowColor[3], rowColor[4] or .9); b.bg:SetAllPoints(b)
        b.hl = ns.style.fill(b, "BORDER", 1, .82, 0, .12); b.hl:SetAllPoints(b); b.hl:Hide()
        b.num = U.text(b, "", 4, 9, 30); font(b.num, 12, muted); b.num:SetJustifyH("RIGHT")
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetWidth(22); b.icon:SetHeight(22); b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 42, -4)
        b.text = U.text(b, "", 74, 8, rowW - 160); font(b.text, 13, text); if b.text.SetWordWrap then b.text:SetWordWrap(false) end
        b.time = U.text(b, "", rowW - 80, 9, 72); font(b.time, 12, muted); b.time:SetJustifyH("RIGHT")
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnEnter", function(self)
            self.hl:Show()
            local st = self.step
            if not st then return end
            local lines = {}
            for _, q in ipairs(st.quests or {}) do lines[#lines + 1] = "• " .. q end
            if st.seconds and st.seconds >= 1 then lines[#lines + 1] = "About " .. minutes(st.seconds) end
            lines[#lines + 1] = st.point and "Click: put a pin on your world map (open it with M)." or "No map pin for this step."
            U.tip(self, "Step " .. self.index .. (self.index == 1 and " (next)" or ""), lines)
        end)
        b:SetScript("OnLeave", function(self) self.hl:Hide(); U.hideTip() end)
        b:SetScript("OnClick", function(self) pin(self.step) end)
        b:Hide(); page.rows[i] = b
    end
    local assume = CreateFrame("Button", nil, page)
    assume:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 18, 14); assume:SetWidth(260); assume:SetHeight(24)
    assume.box, assume.tick = ns.style.checkBox(assume); assume.box:SetPoint("LEFT", assume, "LEFT", 0, 0)
    assume.text = U.text(assume, "Assume I know all flight paths", 28, 6, 230); font(assume.text, 12, INK)
    if assume.text.SetShadowColor then assume.text:SetShadowColor(0, 0, 0, 0) end
    assume:RegisterForClicks("LeftButtonUp")
    assume:SetScript("OnClick", function()
        ns.setSetting("routeAllFlights", not (ns.db and ns.db.routeAllFlights))
        R.plan()
    end)
    page.assume = assume
    page.refresh = (T.button or ns.style.button)(page, "Refresh", 100, function() R.plan() end, "Plan the route again from where you stand.")
    page.refresh:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -18, 14)
    page:Hide()
    return page
end

function R.show(area, name)
    if not page then return end
    local changed = current.area ~= area
    current.area, current.name = area, name
    page:Show()
    if changed or not current.result then R.plan() end
end
function R.hide()
    if page then page:Hide() end
    current.generation = current.generation + 1 -- drop a pending answer
    current.result = nil
end
function R.refresh() if page and page:IsShown() then R.plan() end end

-- tests
function R._page() return page end
