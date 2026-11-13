-- Water-specific notes belong to the user. AnglerAtlas is read at runtime for a separate zone overview;
-- its zone catch lists must never be presented as the verified catch list of every lake in that zone.
local ADDON, ns = ...
local F, U, S = {}, ns.optionalUI, ns.style
ns.fishing = F
local pins, editor, overview, selected = {}, nil, nil, nil
local page, PAGE = 1, 5
local hookedCanvas

local function trim(s) return (string.gsub(string.gsub(tostring(s or ""), "^%s+", ""), "%s+$", "")) end
local function waters()
    if type(ns.db.fishingWaters) ~= "table" then ns.db.fishingWaters = {} end
    return ns.db.fishingWaters
end
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function valid(w)
    return type(w) == "table" and finite(w.map) and w.map > 0 and finite(w.x) and finite(w.y)
        and w.x >= 0 and w.x <= 100 and w.y >= 0 and w.y <= 100 and type(w.name) == "string"
end

function F.list(map)
    local out = {}
    for id, w in pairs(waters()) do
        if type(id) == "number" and valid(w) and (not map or w.map == map) then
            out[#out + 1] = { id = id, water = w }
        end
    end
    table.sort(out, function(a, b)
        if a.water.name == b.water.name then return a.id < b.id end
        return a.water.name < b.water.name
    end)
    return out
end

local function skillText(w)
    return "Minimum skill: " .. (w.minSkill and tostring(w.minSkill) or "unknown")
        .. " | No-getaway skill: " .. (w.safeSkill and tostring(w.safeSkill) or "unknown")
end

function F.save(input, id)
    local w = { name = trim(input.name), map = tonumber(input.map), x = tonumber(input.x), y = tonumber(input.y),
        fish = trim(input.fish), notes = trim(input.notes) }
    if not valid(w) or w.map % 1 ~= 0 or w.name == "" then
        return nil, "Enter a water name, a positive whole map ID and X/Y coordinates from 0 to 100."
    end
    for _, key in ipairs({ "minSkill", "safeSkill" }) do
        local raw = trim(input[key])
        if raw ~= "" then
            local n = tonumber(raw)
            if not finite(n) or n < 0 or n % 1 ~= 0 or n > 10000 then return nil, "Skills must be whole numbers from 0 to 10000, or blank for unknown." end
            w[key] = n
        end
    end
    if w.minSkill and w.safeSkill and w.minSkill > w.safeSkill then return nil, "No-getaway skill must be at least the minimum skill." end
    if #w.name > 80 or #w.fish > 500 or #w.notes > 300 then return nil, "Name, fish list or notes are too long." end
    local list = waters()
    if id and not list[id] then return nil, "This water no longer exists; select New water." end
    if not id then
        id = 1
        for k in pairs(list) do if type(k) == "number" and k >= id then id = k + 1 end end
    end
    list[id] = w
    F.refresh()
    return id
end

function F.remove(id)
    if not id or not waters()[id] then return false end
    waters()[id] = nil
    if selected == id then selected = nil end
    F.refresh()
    return true
end

-- This adapter intentionally leaves unknown/provisional data labelled as such.
function F.zoneSummary(map)
    local a = AnglerAtlas
    local data = a and a.MM and U.call(a.MM.GetModule, a.MM, "DATA")
    if not (type(data) == "table" and type(data.mapToZoneID) == "table" and type(data.zones) == "table") then return nil end
    local zoneID = data.mapToZoneID[map]
    local zone = data.zones[zoneID] or data.zones[tostring(zoneID)]
    if type(zone) ~= "table" then return nil end
    local names = {}
    for id in pairs(type(zone.fishStats) == "table" and zone.fishStats or {}) do
        local f = type(data.fish) == "table" and (data.fish[id] or data.fish[tostring(id)])
        if type(f) == "table" then names[#names + 1] = f.name or ("Item " .. tostring(id)) end
    end
    table.sort(names)
    return { name = zone.name or "Fishing", minSkill = zone.fishingLevel, fish = names,
        provisional = zone.isForeverZone == true }
end

local function newPin(parent)
    local p = CreateFrame("Button", nil, parent)
    p:SetWidth(20); p:SetHeight(20)
    p.icon = p:CreateTexture(nil, "OVERLAY"); p.icon:SetAllPoints(p)
    p.icon:SetTexture("Interface\\Icons\\Trade_Fishing")
    p.label = U.text(p, "", 20, 1, 160)
    if p.label.SetWordWrap then p.label:SetWordWrap(false) end
    p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    p:SetScript("OnEnter", function(self)
        local w = self.water
        U.tip(self, w.name, { skillText(w), "Fish: " .. (type(w.fish) == "string" and w.fish ~= "" and w.fish or "not recorded"),
            type(w.notes) == "string" and w.notes or "", "User-recorded water. Click to edit." })
    end)
    p:SetScript("OnLeave", U.hideTip)
    p:SetScript("OnClick", function(self) F.open(self.waterID) end)
    return p
end

function F.draw()
    local wm = WorldMapFrame
    local cv = wm and wm.ScrollContainer and wm.ScrollContainer.Child
    local on = ns.db.enabled and ns.db.fishingMap and not ns.isBlocked("fishingmap")
    local map = on and wm and cv and wm.GetMapID and wm:IsShown() and wm:GetMapID()
    local n = 0
    if map then
        ns.trying("drawing fishing waters on the world map", "fishingmap")
        local scroll = wm.ScrollContainer
        if scroll.HookScript and wm.GetNormalizedCursorPosition and hookedCanvas ~= scroll then
            scroll:HookScript("OnMouseDown", function(_, button)
                if button ~= "LeftButton" or not (ns.db.enabled and ns.db.fishingMap and U.call(IsAltKeyDown)) then return end
                local x, y = U.call(wm.GetNormalizedCursorPosition, wm)
                if finite(x) and finite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    F.openAt(wm:GetMapID(), x * 100, y * 100)
                end
            end)
            hookedCanvas = scroll
        end
        local scale = cv.GetScale and cv:GetScale() or 1
        if scale <= 0 then scale = 1 end
        for _, row in ipairs(F.list(map)) do
            n = n + 1
            local p, w = pins[n] or newPin(cv), row.water
            pins[n], p.water, p.waterID = p, w, row.id
            p.label:SetText(w.name .. " (" .. (w.minSkill and tostring(w.minSkill) or "?") .. ")")
            p:ClearAllPoints(); p:SetScale(1 / scale)
            p:SetPoint("CENTER", cv, "TOPLEFT", w.x / 100 * cv:GetWidth() * scale, -w.y / 100 * cv:GetHeight() * scale)
            p:Show()
        end
        if not overview then
            overview = CreateFrame("Frame", nil, wm, "BackdropTemplate")
            overview:SetWidth(250); overview:SetHeight(210)
            overview:SetPoint("BOTTOMLEFT", wm, "BOTTOMLEFT", 12, 24)
            S.fill(overview, "BACKGROUND", 0.03, 0.03, 0.05, 0.92):SetAllPoints(overview)
            overview.text, overview.setText = U.scrollText(overview, 8, 8, 234, 162)
            local add = S.button(overview, "Add / edit water", 150, function() F.open() end)
            add:SetPoint("BOTTOMLEFT", overview, "BOTTOMLEFT", 8, 8)
        end
        local z = F.zoneSummary(map)
        local text = S.GOLD .. "Fishing waters|r\n" .. n .. " water markers on this map.\n"
            .. (wm.GetNormalizedCursorPosition and "Alt-click water to add a marker.\n" or "")
        if z then
            text = text .. "\n" .. z.name .. " (AnglerAtlas zone overview)\nMinimum skill: " .. tostring(z.minSkill or "unknown")
                .. "\n" .. table.concat(z.fish, ", ") .. "\nZone estimates; individual waters can differ."
                .. (z.provisional and "\nProvisional Forever data." or "")
        else
            text = text .. "\nAdd a marker for each lake, river or coast, with its skill and fish.\n\n"
                .. "Install AnglerAtlas for zone summaries.\nNo built-in catalogue of individual waters."
        end
        overview.setText(text)
        overview:Show()
    elseif overview then overview:Hide() end
    for i = n + 1, #pins do pins[i]:Hide() end
end

function F.refresh()
    F.draw()
    if not ns.db.enabled and editor then editor.frame:Hide() end
end

local function fill(w)
    for _, k in ipairs({ "name", "map", "x", "y", "minSkill", "safeSkill", "fish", "notes" }) do
        editor[k]:SetText(w and w[k] ~= nil and tostring(w[k]) or "")
    end
end

local function refreshEditor()
    if not editor then return end
    local list = F.list()
    page = math.max(1, math.min(page, math.max(1, math.ceil(#list / PAGE))))
    for i, b in ipairs(editor.rows) do
        local r = list[(page - 1) * PAGE + i]
        if r then
            b.waterID = r.id
            b:SetLabel((selected == r.id and "> " or "") .. r.water.name .. " — map " .. r.water.map)
            b:Show()
        else b.waterID = nil; b:Hide() end
    end
    editor.count:SetText("Saved waters: " .. #list .. "   Page " .. page .. "/" .. math.max(1, math.ceil(#list / PAGE)))
end

local function currentPosition()
    local map, x, y = ns.compat.playerPos()
    if not (map and x and y) then editor.message:SetText(S.RED .. "Your position is unavailable; enter map ID and coordinates.|r"); return end
    editor.map:SetText(tostring(map)); editor.x:SetText(string.format("%.2f", x * 100)); editor.y:SetText(string.format("%.2f", y * 100))
    editor.message:SetText("Position set to where you are standing; move X/Y to the water if needed.")
end

local function build()
    if editor then return true end
    local f = U.window("QuestSharingFishing", 670, 550, "Fishing waters")
    if not f then return false end
    editor = { frame = f, rows = {} }
    U.text(f, "Record each body of water; blank skill means unknown. Coordinates are 0–100 on the selected map.", 24, 32, 620)
    editor.name = U.box(f, "Water name", 24, 60, 300, "", 80)
    editor.map = U.box(f, "Map ID", 340, 60, 90, "", 6)
    editor.x = U.box(f, "X (%)", 446, 60, 86, "", 8)
    editor.y = U.box(f, "Y (%)", 548, 60, 86, "", 8)
    editor.minSkill = U.box(f, "Minimum fishing skill", 24, 112, 195, "", 5)
    editor.safeSkill = U.box(f, "No-getaway skill", 235, 112, 195, "", 5)
    local pos = S.button(f, "Use my position", 185, currentPosition)
    pos:SetPoint("TOPLEFT", f, "TOPLEFT", 449, -129)
    editor.fish = U.box(f, "Fish caught here (comma-separated)", 24, 164, 610, "", 500)
    editor.notes = U.box(f, "Notes: pools, season, time of day, source...", 24, 216, 610, "", 300)
    local save = S.button(f, "Save water", 120, function()
        local input = {}
        for _, k in ipairs({ "name", "map", "x", "y", "minSkill", "safeSkill", "fish", "notes" }) do input[k] = editor[k]:GetText() end
        local id, err = F.save(input, selected)
        if id then selected = id; editor.message:SetText(S.GREEN .. "Saved." .. (ns.db.fishingMap and "" or " Enable fishing in Optional to show markers.") .. "|r"); refreshEditor()
        else editor.message:SetText(S.RED .. err .. "|r") end
    end)
    save:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -270)
    local new = S.button(f, "New water", 120, function() selected = nil; fill(); currentPosition(); refreshEditor() end)
    new:SetPoint("LEFT", save, "RIGHT", 10, 0)
    local del = S.button(f, "Delete selected", 130, function()
        if F.remove(selected) then fill(); refreshEditor(); editor.message:SetText("Water removed.") end
    end)
    del:SetPoint("LEFT", new, "RIGHT", 10, 0)
    local show = S.button(f, "Map location", 120, function()
        if not U.mapHint(tonumber(editor.map:GetText())) then editor.message:SetText("Enter a map ID first.") end
    end)
    show:SetPoint("LEFT", del, "RIGHT", 10, 0)
    editor.message = U.text(f, "", 24, 300, 610)
    editor.count = U.text(f, "", 24, 335, 610)
    for i = 1, PAGE do
        local b = S.button(f, "", 610, function(self)
            selected = self.waterID; fill(waters()[selected]); refreshEditor()
        end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -(355 + (i - 1) * 25))
        editor.rows[i] = b
    end
    local prev = S.button(f, "Previous", 100, function() page = math.max(1, page - 1); refreshEditor() end)
    prev:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 20)
    local nextPage = S.button(f, "Next", 100, function() page = page + 1; refreshEditor() end)
    nextPage:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    return true
end

function F.open(id)
    if not ns.db.enabled then ns.print("switch Quest Sharing on first (/qs on)"); return end
    if not build() then return end
    selected = id and waters()[id] and id or nil
    fill(selected and waters()[selected]); if not selected then currentPosition() end
    if not selected and WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:IsShown() then
        local viewed = WorldMapFrame:GetMapID()
        if viewed and tonumber(editor.map:GetText()) ~= viewed then
            editor.map:SetText(tostring(viewed)); editor.x:SetText(""); editor.y:SetText("")
        end
    end
    editor.message:SetText("Water notes are saved locally. Fish and skill values are entered by you.")
    refreshEditor(); editor.frame:Show()
end

function F.openAt(map, x, y)
    F.open()
    if not editor or not ns.db.enabled then return end
    editor.map:SetText(tostring(map)); editor.x:SetText(string.format("%.2f", x)); editor.y:SetText(string.format("%.2f", y))
    editor.message:SetText("Map location selected. Name this water, add its skill and fish, then Save water.")
end

function F._pins() return pins end
function F._editor() return editor end
function F._overview() return overview end
local function tick()
    if ns.db.fishingMap or #pins > 0 or overview then F.draw() end
    ns.after(0.5, tick)
end
ns.after(3, tick)
ns.on("PLAYER_ENTERING_WORLD", F.refresh)
