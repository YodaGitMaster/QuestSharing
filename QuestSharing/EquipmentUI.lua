-- One equipment explorer shared by quest rewards and dungeon drops.
local ADDON, ns = ...
local E, U, S = {}, ns.optionalUI, ns.style
ns.equipmentUI = E
local host, active, pages, tabs = nil, nil, {}, {}
local f = { category = "All equipment", subtype = "Any type", slot = "All slots", mode = "Required level" }
E.filters = f
local categories = { "All equipment", "Weapons", "Armor", "Accessories" }
local types = {
    ["All equipment"] = { "Any type" },
    Weapons = { "Any type", "Axes", "Swords", "Maces", "Staves", "Daggers", "Polearms", "Fist weapons", "Bows", "Guns", "Crossbows", "Wands", "Thrown", "Fishing poles" },
    Armor = { "Any type", "Cloth", "Leather", "Mail", "Plate", "Shields", "Relics" },
    Accessories = { "Any type", "Neck", "Finger", "Trinket", "Back", "Offhand" },
}
local weaponTypes = { Axes={0,1}, Swords={7,8}, Maces={4,5}, Staves={10}, Daggers={15}, Polearms={6},
    ["Fist weapons"]={13}, Bows={2}, Guns={3}, Crossbows={18}, Wands={19}, Thrown={16}, ["Fishing poles"]={20} }
local armorTypes = { Cloth=1, Leather=2, Mail=3, Plate=4, Shields=6 }
local slots = { "All slots", "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "Finger", "Trinket", "Weapon", "Offhand", "Ranged" }
local quality = { [0]="|cff9d9d9d", [1]="|cffffffff", [2]="|cff1eff00", [3]="|cff0070dd", [4]="|cffa335ee", [5]="|cffff8000" }

function E.matches(info, fallback)
    -- Require confirmed quality so uncached items cannot bypass the blue-or-better rule.
    if not info or type(info.quality) ~= "number" or not (info.quality >= 3) then return false end
    local kind = info and info.kind or fallback and fallback.kind
    local sub = info and info.sub or fallback and fallback.sub
    local slot = info and info.slot
    local accessory = slot == "Neck" or slot == "Finger" or slot == "Trinket" or slot == "Back" or (kind == 4 and sub == 0)
    if f.category == "Weapons" and kind ~= 2 then return false end
    if f.category == "Armor" and (kind ~= 4 or accessory) then return false end
    if f.category == "Accessories" and not accessory then return false end
    if f.subtype ~= "Any type" then
        local list = weaponTypes[f.subtype]
        if f.category == "Weapons" then
            local found = false
            for _, n in ipairs(list or {}) do if sub == n then found = true end end
            if not found then return false end
        elseif f.category == "Armor" then
            if f.subtype == "Relics" then if not sub or sub < 7 or sub > 10 then return false end
            elseif sub ~= armorTypes[f.subtype] then return false end
        elseif f.category == "Accessories" and slot ~= f.subtype then return false end
    end
    if f.slot ~= "All slots" and slot ~= f.slot then return false end
    local key = f.mode == "Item level" and "level" or "required"
    local value = info and info[key]
    if value == nil and fallback then value = fallback[key] end
    if (f.min or f.max) and (type(value) ~= "number" or (f.min and value < f.min) or (f.max and value > f.max)) then return false end
    return true
end

local function changed()
    local p = active and pages[active]
    if p and p.refresh then p.refresh() end
end
local function nextValue(values, current, button)
    local at = 1
    for i,v in ipairs(values) do if v == current then at = i end end
    return values[(at - 1 + (button == "RightButton" and -1 or 1)) % #values + 1]
end
local controls
local function labels()
    if not controls then return end
    controls.category:SetLabel(f.category)
    controls.subtype:SetLabel(f.subtype)
    controls.slot:SetLabel(f.slot)
    controls.mode:SetLabel(f.mode)
end
function E.applyRange(minimum, maximum)
    local function parse(s)
        if s == nil or s == "" then return nil, true end
        local n = tonumber(s)
        return n, n ~= nil and n >= 0 and n <= 1000 and n % 1 == 0
    end
    local lo, ok1 = parse(minimum)
    local hi, ok2 = parse(maximum)
    if not ok1 or not ok2 or (lo and hi and lo > hi) then
        if controls then controls.error:SetText(S.RED .. "Use whole levels 0–1000; minimum must not exceed maximum.|r") end
        return false
    end
    f.min, f.max = lo, hi
    if controls then controls.error:SetText("") end
    changed()
    return true
end
function E.reset()
    f.category, f.subtype, f.slot, f.mode, f.min, f.max = "All equipment", "Any type", "All slots", "Required level", nil, nil
    if controls then controls.min:SetText(""); controls.max:SetText(""); controls.error:SetText("") end
    labels(); changed()
end
function E.visible(key) return host and host:IsShown() and active == key and pages[key] and pages[key]:IsShown() end
local function hidePage(key)
    local p = pages[key]
    if p then p:Hide(); if p.suspend then p.suspend() end end
end
function E.close(key)
    if key and key ~= active then hidePage(key); return end
    if active then hidePage(active) end
    active = nil
    if host then host:Hide() end
    U.hideTip()
end
local function build()
    if host then return true end
    host = U.window("QuestSharingEquipment", 1080, 760, "Equipment explorer")
    if not host then return false end
    local scale = math.min(1, (UIParent:GetWidth() - 40) / 1080, (UIParent:GetHeight() - 40) / 760)
    host:SetScale(math.max(0.5, scale))
    S.fill(host, "BACKGROUND", 0.035, 0.055, 0.09, 1):SetAllPoints(host)
    for i, key in ipairs({ "quests", "dungeons" }) do
        tabs[key] = S.button(host, key == "quests" and "Quest rewards" or "Instance drops", 184, function()
            if key == "quests" then ns.rewards.open() else ns.loot.open() end
        end)
        tabs[key]:SetPoint("TOPLEFT", host, "TOPLEFT", 24 + (i-1)*194, -40)
    end
    U.text(host, "Blue quality and above • select an item for its source and route", 440, 43, 610)
    local bar = CreateFrame("Frame", nil, host)
    bar:SetPoint("TOPLEFT", host, "TOPLEFT", 16, -73); bar:SetWidth(1048); bar:SetHeight(69)
    S.fill(bar, "BACKGROUND", 0.09, 0.12, 0.18, 1):SetAllPoints(bar)
    controls = {}
    local function choice(key, label, x, width, values)
        U.text(bar, label, x, 5, width)
        local b = S.button(bar, "", width, function(_, button)
            f[key] = nextValue(type(values) == "function" and values() or values, f[key], button)
            if key == "category" then f.subtype = "Any type" end
            labels(); changed()
        end, "Left click: next; right click: previous")
        b:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -25); controls[key] = b
    end
    choice("category", "Equipment", 8, 150, categories)
    choice("subtype", "Item type", 168, 150, function() return types[f.category] end)
    choice("slot", "Slot", 328, 130, slots)
    choice("mode", "Level range measures", 468, 136, { "Required level", "Item level" })
    controls.min = U.box(bar, "Min", 614, 7, 60, "", 4)
    controls.max = U.box(bar, "Max", 684, 7, 60, "", 4)
    local function apply() E.applyRange(controls.min:GetText(), controls.max:GetText()) end
    for _,b in ipairs({controls.min,controls.max}) do b:SetScript("OnEnterPressed", function(self) apply(); self:ClearFocus() end) end
    controls.apply = S.button(bar, "Apply", 70, apply); controls.apply:SetPoint("TOPLEFT", bar, "TOPLEFT", 754, -25)
    controls.reset = S.button(bar, "Reset filters", 110, E.reset); controls.reset:SetPoint("TOPLEFT", bar, "TOPLEFT", 834, -25)
    controls.error = U.text(bar, "", 8, 49, 1020)
    labels()
    host:SetScript("OnHide", function() if active then local key=active; active=nil; hidePage(key) end; U.hideTip() end)
    return true
end
function E.page(key)
    if not build() then return end
    if not pages[key] then
        local p = CreateFrame("Frame", nil, host)
        p:SetPoint("TOPLEFT", host, "TOPLEFT", 24, -152); p:SetWidth(1032); p:SetHeight(580); p:Hide()
        pages[key] = p
    end
    return pages[key]
end
function E.show(key)
    if not build() then return false end
    if active and active ~= key then hidePage(active) end
    active = key
    host:Show(); pages[key]:Show()
    for k,b in pairs(tabs) do b:SetLabel((k == key and S.GOLD or S.GREY) .. (k == "quests" and "Quest rewards" or "Instance drops") .. "|r") end
    return true
end
function E.details(parent, x, width, title)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0); panel:SetWidth(width); panel:SetHeight(550)
    S.fill(panel, "BACKGROUND", 0.07, 0.09, 0.13, 1):SetAllPoints(panel)
    U.text(panel, S.GOLD .. title .. "|r", 14, 14, width-28)
    local text, set = U.scrollText(panel, 14, 44, width-28, 452)
    set("Select an item to see its source and details here.")
    return panel, text, set
end
function E.row(parent, x, y, width, i)
    local row = { frame = CreateFrame("Button", nil, parent) }
    local b = row.frame
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y); b:SetWidth(width); b:SetHeight(48)
    row.bg = S.fill(b, "BACKGROUND", 0.10, 0.13, (i%2==0 and 0.20 or 0.17), 1); row.bg:SetAllPoints(b)
    row.edge = S.fill(b, "OVERLAY", 0.3, 0.75, 1, 0.9); row.edge:SetWidth(3); row.edge:SetHeight(48); row.edge:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); row.edge:Hide()
    row.icon = b:CreateTexture(nil, "ARTWORK"); row.icon:SetWidth(34); row.icon:SetHeight(34); row.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 9, -7)
    row.item = U.text(b, "", 52, 6, width-60); row.item:SetFontObject(GameFontNormal or ChatFontNormal)
    row.from = U.text(b, "", 52, 27, width-60)
    if row.item.SetWordWrap then row.item:SetWordWrap(false); row.from:SetWordWrap(false) end
    b:RegisterForClicks("LeftButtonUp")
    return row
end
function E.paintRow(row, info, name, subtitle)
    row.icon:SetTexture(info and info.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.item:SetText((quality[info and info.quality] or S.WHITE) .. name .. "|r")
    row.from:SetText(S.GREY .. subtitle .. "|r")
end
function E.select(rows, selected)
    for _,r in ipairs(rows) do if r == selected then r.edge:Show() else r.edge:Hide() end end
end
function E._window() return host, controls, pages, tabs end
