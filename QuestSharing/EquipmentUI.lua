-- One equipment explorer shared by quest rewards and dungeon drops.
local ADDON, ns = ...
local E, U, S = {}, ns.optionalUI, ns.style
ns.equipmentUI = E
local host, active, pages, tabs = nil, nil, {}, {}
local f = { category = "All equipment", subtype = "Any type", slot = "All slots", mode = "Required level", sort = "Highest item level", stats = {{},{},{}} }
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
local readableQuality = { [3]="|cff79bfff", [4]="|cffcd9bff", [5]="|cffffbf80" }
local quality = { [0]="|cff9d9d9d", [1]="|cffffffff", [2]="|cff1eff00", [3]="|cff0070dd", [4]="|cffa335ee", [5]="|cffff8000" }
local statChoices = {{value="",label="Any stat"}}
local statKeys = {}
for _,entry in ipairs({
    {"Strength","ITEM_MOD_STRENGTH_SHORT"}, {"Agility","ITEM_MOD_AGILITY_SHORT"},
    {"Stamina","ITEM_MOD_STAMINA_SHORT"}, {"Intellect","ITEM_MOD_INTELLECT_SHORT"},
    {"Spirit","ITEM_MOD_SPIRIT_SHORT"}, {"Armor","RESISTANCE0_NAME"},
    {"Health","ITEM_MOD_HEALTH_SHORT"}, {"Mana","ITEM_MOD_MANA_SHORT"},
    {"Attack power","ITEM_MOD_ATTACK_POWER_SHORT"}, {"Ranged attack power","ITEM_MOD_RANGED_ATTACK_POWER_SHORT"},
    {"Spell power","ITEM_MOD_SPELL_POWER_SHORT"}, {"Spell damage","ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"},
    {"Healing","ITEM_MOD_SPELL_HEALING_DONE_SHORT"}, {"Mana per 5 sec","ITEM_MOD_MANA_REGENERATION_SHORT"},
    {"Hit rating","ITEM_MOD_HIT_RATING_SHORT"}, {"Crit rating","ITEM_MOD_CRIT_RATING_SHORT"},
    {"Haste rating","ITEM_MOD_HASTE_RATING_SHORT"}, {"Defense rating","ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"},
    {"Dodge rating","ITEM_MOD_DODGE_RATING_SHORT"}, {"Parry rating","ITEM_MOD_PARRY_RATING_SHORT"},
    {"Block rating","ITEM_MOD_BLOCK_RATING_SHORT"}, {"Block value","ITEM_MOD_BLOCK_VALUE_SHORT"},
    {"Arcane resistance","RESISTANCE6_NAME"}, {"Fire resistance","RESISTANCE2_NAME"},
    {"Frost resistance","RESISTANCE4_NAME"}, {"Nature resistance","RESISTANCE3_NAME"},
    {"Shadow resistance","RESISTANCE5_NAME"},
}) do
    statChoices[#statChoices+1]=entry[1];statKeys[entry[1]]=entry[2]
end
local statCache={}
ns.on("GET_ITEM_INFO_RECEIVED",function() statCache={} end)
local function statHint()
    if not ((C_Item and type(C_Item.GetItemStats)=="function") or type(GetItemStats)=="function") then
        return "Stat API unavailable on this client; leave Any stat selected."
    end
    return "Blank min = 1 • Any stat clears a condition • client-reported bonuses only • ratings use points"
end
local function itemStats(info)
    local link=info.link
    if not link then return end
    if statCache[link] then return statCache[link] end
    for i=1,2 do
        local fn=i==1 and C_Item and C_Item.GetItemStats or (i==2 and GetItemStats)
        if type(fn)=="function" then
            local ok,stats=pcall(fn,link)
            if ok and type(stats)=="table" then statCache[link]=stats;return stats end
        end
    end
    -- Do not cache failures: the client may supply the item on a later refresh.
end

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
    local stats
    for _,condition in ipairs(f.stats) do
        if condition.stat then
            stats=stats or itemStats(info)
            local amount=stats and stats[statKeys[condition.stat]]
            if type(amount)~="number" or not (amount >= (condition.min or 1)) then return false end
        end
    end
    return true
end

local function changed()
    local p = active and pages[active]
    if p and p.refresh then p.refresh() end
end
local menu, drawMenu
local function option(entry)
    if type(entry) == "table" then return entry.value, entry.label or tostring(entry.value) end
    return entry, tostring(entry)
end
function E.dismissMenu()
    if menu then menu.frame:Hide(); menu.search:ClearFocus(); menu.owner=nil end
end
local function chooseOption(entry)
    if not menu or not menu.owner or not entry then return end
    local owner = menu.owner
    local value = option(entry)
    E.dismissMenu(); owner.chooseValue(value); owner.refresh()
end
local function buildMenu()
    if menu then return end
    local panel = CreateFrame("Frame", nil, host)
    panel:SetWidth(250); panel:SetHeight(330); panel:SetFrameStrata("TOOLTIP")
    if panel.SetFrameLevel then panel:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 0)+40) end
    panel:SetClampedToScreen(true); panel:EnableMouse(true)
    S.fill(panel,"BACKGROUND",0.07,0.09,0.14,1):SetAllPoints(panel)
    menu={frame=panel,rows={},offset=0,cursor=1}
    menu.search=U.box(panel,"Find an option",10,8,230,"",80)
    if menu.search.SetAltArrowKeyMode then menu.search:SetAltArrowKeyMode(false) end
    menu.status=U.text(panel,"",10,307,230)
    for i=1,10 do
        local row=S.button(panel,"",230,function(self) chooseOption(self.entry) end)
        row:SetHeight(24);row:SetPoint("TOPLEFT",panel,"TOPLEFT",10,-(48+(i-1)*25))
        row.label:ClearAllPoints();row.label:SetPoint("LEFT",row,"LEFT",8,0);row.label:SetWidth(214);row.label:SetJustifyH("LEFT");row.label:SetWordWrap(false)
        row:HookScript("OnEnter",function(self) if self.entry then local _,label=option(self.entry);U.tip(self,label,{}) end end)
        row:HookScript("OnLeave",U.hideTip)
        menu.rows[i]=row
    end
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel",function(_,delta) menu.offset=menu.offset+(delta>0 and -3 or 3);drawMenu() end)
    for _,row in ipairs(menu.rows) do row:EnableMouseWheel(true);row:SetScript("OnMouseWheel",function(_,delta) menu.offset=menu.offset+(delta>0 and -3 or 3);drawMenu() end) end
    menu.search:SetScript("OnTextChanged",function() menu.offset,menu.cursor=0,1;drawMenu() end)
    menu.search:SetScript("OnEnterPressed",function() chooseOption(menu.filtered[menu.cursor]) end)
    menu.search:SetScript("OnArrowPressed",function(_,key)
        if key~="UP" and key~="DOWN" then return end
        local n=#menu.filtered
        menu.cursor=math.max(1,math.min(n,menu.cursor+(key=="UP" and -1 or 1)))
        if menu.cursor<=menu.offset then menu.offset=menu.cursor-1 elseif menu.cursor>menu.offset+10 then menu.offset=menu.cursor-10 end
        drawMenu()
    end)
    menu.search:SetScript("OnEscapePressed",E.dismissMenu)
    panel:Hide()
end

drawMenu=function()
    if not menu.owner then return end
    local values=type(menu.owner.choices)=="function" and menu.owner.choices() or menu.owner.choices
    local needle=string.lower(menu.search:GetText() or "")
    menu.filtered={}
    for _,entry in ipairs(values or {}) do
        local _,label=option(entry)
        if needle=="" or string.find(string.lower(label),needle,1,true) then menu.filtered[#menu.filtered+1]=entry end
    end
    menu.offset=math.max(0,math.min(menu.offset,math.max(0,#menu.filtered-10)))
    menu.cursor=math.max(menu.offset+1,math.min(menu.cursor,menu.offset+10,#menu.filtered))
    local current=menu.owner.readValue()
    for i,row in ipairs(menu.rows) do
        local entry=menu.filtered[menu.offset+i];row.entry=entry
        if entry then
            local value,label=option(entry)
            row:SetLabel((value==current and S.GOLD or S.WHITE)..(menu.offset+i==menu.cursor and "> " or "  ")..label.."|r");row:Show()
        else row:Hide() end
    end
    menu.status:SetText(#menu.filtered==0 and "No matching options" or ("Scroll or type to find • "..#menu.filtered.." options"))
end

function E.dropdown(parent,label,x,y,width,choices,read,choose)
    local b=S.button(parent,"",width,function(self)
        if menu and menu.owner==self and menu.frame:IsShown() then E.dismissMenu();return end
        U.hideTip();buildMenu();menu.owner=self;menu.offset,menu.cursor=0,1
        menu.frame:ClearAllPoints();menu.frame:SetPoint("TOPLEFT",self,"BOTTOMLEFT",0,-4)
        menu.search:SetText("");drawMenu()
        for i,entry in ipairs(menu.filtered) do local value=option(entry);if value==self.readValue() then menu.cursor=i;menu.offset=math.max(0,i-5);break end end
        drawMenu();menu.frame:Show();menu.search:SetFocus()
    end,"Choose directly from a searchable list")
    b:SetHeight(24);b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    b.choices,b.readValue,b.chooseValue=choices,read,choose
    b.label:ClearAllPoints();b.label:SetPoint("LEFT",b,"LEFT",8,0);b.label:SetWidth(width-30);b.label:SetJustifyH("LEFT");b.label:SetWordWrap(false)
    U.text(b,"v",width-16,5,12)
    b.refresh=function()
        local current=read();local values=type(choices)=="function" and choices() or choices
        local text=tostring(current or "All")
        for _,entry in ipairs(values or {}) do local v,l=option(entry);if v==current then text=l;break end end
        b:SetLabel((label and (label..": ") or "")..text)
        if menu and menu.owner==b and menu.frame:IsShown() then drawMenu() end
    end
    b:HookScript("OnEnter",function(self) U.tip(self,self.text,{"Click to choose; type to find an option."}) end)
    b.refresh();return b
end
function E.liveBox(box,key,apply)
    local serial=0
    box.cancel=function() serial=serial+1;box.dirty=false end
    box.flush=function() box.cancel();apply(box:GetText()) end
    box:SetScript("OnTextChanged",function()
        serial=serial+1;local token=serial;box.dirty=true
        ns.after(0.18,function()
            if token~=serial then return end
            if (key and E.visible(key)) or (not key and host and host:IsShown()) then box.flush() end
        end)
    end)
    box:SetScript("OnEnterPressed",function(self) self.flush();self:ClearFocus() end)
    box:SetScript("OnEscapePressed",function(self) self:SetText("");self.flush();self:ClearFocus() end)
    box:SetScript("OnEditFocusGained",E.dismissMenu)
end
function E.searchBox(parent,label,x,y,width,key,apply)
    local box=U.box(parent,label,x,y,width-54,"",100)
    E.liveBox(box,key,apply)
    local clear=S.button(parent,"Clear",48,function() box:SetText("");box.flush();box:ClearFocus() end)
    clear:SetPoint("TOPLEFT",parent,"TOPLEFT",x+width-48,-(y+18))
    return box,clear
end
function E.wheel(frame,step)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel",function(_,delta) if delta~=0 then E.dismissMenu();step(delta>0 and -1 or 1) end end)
end
function E.navigation(box,rows,step)
    if box.SetAltArrowKeyMode then box:SetAltArrowKeyMode(false) end
    box:SetScript("OnArrowPressed",function(_,key)
        if key~="UP" and key~="DOWN" then return end
        local visible,at={},0
        for _,row in ipairs(rows) do if row.result and row.frame:IsShown() then visible[#visible+1]=row;if row.selected then at=#visible end end end
        local dir=key=="UP" and -1 or 1
        local target=at+dir
        if target<1 or target>#visible then
            if #visible==0 then return end
            if step(dir)==false then return end
            visible={}
            for _,row in ipairs(rows) do if row.result and row.frame:IsShown() then visible[#visible+1]=row end end
            target=dir>0 and 1 or #visible
        end
        if visible[target] then visible[target].choose() end
    end)
end
function E.focusRows(rows,wanted,keyOf)
    local selected,first
    for _,row in ipairs(rows) do
        if row.result and row.frame:IsShown() then
            first=first or row
            if keyOf(row.result)==wanted then selected=row end
        end
    end
    selected=selected or first
    if selected then selected.choose(true) else E.select(rows,nil) end
    return selected
end
function E.sortResults(list,infoOf,nameOf,tie)
    table.sort(list,function(a,b)
        local ai,bi=infoOf(a) or {},infoOf(b) or {}
        if f.sort=="Highest item level" then
            local av,bv=tonumber(ai.level) or -1,tonumber(bi.level) or -1
            if av~=bv then return av>bv end
        elseif f.sort=="Lowest required level" then
            local av,bv=tonumber(ai.required) or math.huge,tonumber(bi.required) or math.huge
            if av~=bv then return av<bv end
        end
        local an,bn=string.lower(nameOf(a)),string.lower(nameOf(b))
        if an~=bn then return an<bn end
        return tie(a,b)
    end)
end
-- Keep source records intact; only the filtered presentation is grouped by equipment name.
function E.groupItems(list,nameOf,infoOf,sourceLess)
    local groups,ordered={},{}
    for _,r in ipairs(list) do
        local name=string.gsub(string.gsub(nameOf(r),"|c%x%x%x%x%x%x%x%x",""),"|r","")
        local key=string.lower(string.match(name,"^%s*(.-)%s*$"))
        if not groups[key] then
            groups[key]={key=key,sources={}}
            ordered[#ordered+1]=groups[key]
        end
        local sources=groups[key].sources
        sources[#sources+1]=r
    end
    for i,group in ipairs(ordered) do
        table.sort(group.sources,sourceLess)
        local best,versions=group.sources[1],{}
        for _,r in ipairs(group.sources) do
            versions[r.itemID]=r
            local level,bestLevel=tonumber(infoOf(r).level) or 0,tonumber(infoOf(best).level) or 0
            if level>bestLevel or (level==bestLevel and r.itemID<best.itemID) then best=r end
        end
        local result={}
        for k,v in pairs(best) do result[k]=v end
        result.key,result.sources,result.itemIDs,result.versions=group.key,group.sources,{},{}
        for id in pairs(versions) do result.itemIDs[#result.itemIDs+1]=id end
        table.sort(result.itemIDs)
        for _,id in ipairs(result.itemIDs) do result.versions[#result.versions+1]=versions[id] end
        ordered[i]=result
    end
    return ordered
end
function E.versionLines(r,infoOf)
    local lines={}
    if #r.itemIDs>1 then
        lines[1]="Versions with this name (tooltip compares item "..r.itemID.."):"
        for _,v in ipairs(r.versions) do
            local info=infoOf(v)
            lines[#lines+1]="Item "..v.itemID..": iLvl "..tostring(info.level or "?")..", requires level "..tostring(info.required or "?")
        end
    end
    return lines
end
function E.pageStatus(first,count,total)
    if total==0 then return "No matching equipment" end
    return first.."–"..math.min(total,first+count-1).." of "..total.." items • scroll to browse"
end
function E.pageButtons(prev,next,total,page,count)
    for _,pair in ipairs({{prev,page>1},{next,page*count<total}}) do
        local b,enabled=pair[1],pair[2]
        if b then
            b.disabled=not enabled;b:SetAlpha(enabled and 1 or 0.35)
            if enabled and b.Enable then b:Enable() elseif not enabled and b.Disable then b:Disable() end
            b.label:SetText((enabled and S.WHITE or S.GREY)..b.text.."|r")
        end
    end
end
function E._menu() return menu end
local controls
local function labels()
    if not controls then return end
    for _,key in ipairs({"category","subtype","slot","mode","sort"}) do controls[key].refresh() end
    for _,row in ipairs(controls.stats or {}) do row.stat.refresh() end
end
function E.applyStat(index,stat,minimum)
    if not f.stats[index] or (stat~="" and not statKeys[stat]) then return false end
    local n=minimum=="" and 1 or tonumber(minimum)
    if stat~="" and (not n or n<1 or n>100000 or n%1~=0) then
        if controls then controls.statError:SetText(S.RED.."Stat minimum must be a whole number from 1 to 100000.|r") end
        return false
    end
    local row=controls and controls.stats[index]
    if row then row.min.cancel() end
    f.stats[index]={stat=stat~="" and stat or nil,min=stat~="" and n or nil}
    if controls then controls.statError:SetText(statHint()) end
    labels();changed();return true
end
function E.applyRange(minimum, maximum)
    E.dismissMenu()
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
    labels();changed()
    return true
end
function E.reset()
    f.category, f.subtype, f.slot, f.mode, f.min, f.max = "All equipment", "Any type", "All slots", "Required level", nil, nil
    if controls then controls.min:SetText(""); controls.max:SetText(""); controls.min.cancel();controls.max.cancel();controls.error:SetText("") end
    f.sort="Highest item level"
    for i=1,3 do
        f.stats[i]={}
        if controls then controls.stats[i].min:SetText("");controls.stats[i].min.cancel() end
    end
    if controls then controls.statError:SetText(statHint()) end
    E.dismissMenu();labels()
    local p=active and pages[active]
    if p and p.clear then p.clear() else changed() end
end
function E.myLevel()
    local level=U.call(UnitLevel,"player")
    if type(level)~="number" or level<1 then return end
    f.mode="Required level"
    controls.min:SetText("");controls.max:SetText(tostring(level));controls.min.cancel();controls.max.cancel();E.applyRange("",tostring(level))
end
function E.visible(key) return host and host:IsShown() and active == key and pages[key] and pages[key]:IsShown() end
local function hidePage(key)
    local p = pages[key]
    if p then p:Hide(); if p.suspend then p.suspend() end end
end
function E.close(key)
    E.dismissMenu()
    if key and key ~= active then hidePage(key); return end
    if active then hidePage(active) end
    active = nil
    if host then host:Hide() end
    U.hideTip()
end
local function build()
    if host then return true end
    host = U.window("QuestSharingEquipment", 1080, 828, "Equipment explorer")
    if not host then return false end
    local scale = math.min(1, (UIParent:GetWidth() - 40) / 1080, (UIParent:GetHeight() - 40) / 828)
    host:SetScale(math.max(0.5, scale))
    S.fill(host, "BACKGROUND", 0.035, 0.055, 0.09, 1):SetAllPoints(host)
    for i, key in ipairs({ "quests", "dungeons" }) do
        tabs[key] = S.button(host, key == "quests" and "Quest rewards" or "Instance drops", 184, function()
            if key == "quests" then ns.rewards.open() else ns.loot.open() end
        end)
        tabs[key]:SetPoint("TOPLEFT", host, "TOPLEFT", 24 + (i-1)*194, -40)
    end
    U.text(host, "Blue+ only • hover to compare", 440, 43, 370)
    local bar = CreateFrame("Frame", nil, host)
    bar:SetPoint("TOPLEFT", host, "TOPLEFT", 16, -73); bar:SetWidth(1048); bar:SetHeight(137)
    S.fill(bar, "BACKGROUND", 0.09, 0.12, 0.18, 1):SetAllPoints(bar)
    controls = {}
    local function choice(key,label,x,width,values)
        U.text(bar,label,x,5,width)
        controls[key]=E.dropdown(bar,nil,x,24,width,values,function() return f[key] end,function(value)
            f[key]=value
            if key=="category" then f.subtype="Any type";f.slot="All slots" end
            labels();changed()
        end)
    end
    choice("category", "Equipment", 8, 150, categories)
    choice("subtype", "Item type", 168, 150, function() return types[f.category] end)
    choice("slot", "Slot", 328, 130, slots)
    choice("mode", "Level range measures", 468, 136, { "Required level", "Item level" })
    controls.sort=E.dropdown(host,"Sort",830,38,226,{"Highest item level","Lowest required level","Name A–Z"},function() return f.sort end,function(value) f.sort=value;labels();changed() end)
    controls.min = U.box(bar, "Min", 614, 7, 60, "", 4)
    controls.max = U.box(bar, "Max", 684, 7, 60, "", 4)
    local function apply()
        controls.min.cancel();controls.max.cancel()
        E.applyRange(controls.min:GetText(), controls.max:GetText())
    end
    for _,b in ipairs({controls.min,controls.max}) do E.liveBox(b,nil,apply) end
    controls.apply = S.button(bar, "Apply", 70, apply); controls.apply:SetPoint("TOPLEFT", bar, "TOPLEFT", 754, -25)
    controls.reset = S.button(bar, "Clear filters", 110, E.reset); controls.reset:SetPoint("TOPLEFT", bar, "TOPLEFT", 834, -25)
    controls.mine=S.button(bar,"My level",86,E.myLevel,"Only equipment requiring your level or lower");controls.mine:SetPoint("TOPLEFT",bar,"TOPLEFT",954,-25)
    controls.error = U.text(bar, "", 8, 49, 1020)
    U.text(bar,"Stats • all selected must match",8,70,228)
    controls.stats={}
    for i=1,3 do
        local index,x=i,8+(i-1)*344
        local row={};controls.stats[index]=row
        row.min=U.box(bar,"Min bonus",x+238,74,88,"",6)
        row.stat=E.dropdown(bar,nil,x,92,228,statChoices,function() return f.stats[index].stat or "" end,function(value)
            if E.applyStat(index,value,row.min:GetText()) and value=="" then row.min:SetText("");row.min.cancel() end
        end)
        E.liveBox(row.min,nil,function(text) E.applyStat(index,f.stats[index].stat or "",text) end)
        row.stat:HookScript("OnEnter",function(self) U.tip(self,"Item stat filter",{"All selected bonuses must meet their minimum.","Uses bonuses reported by the client; procs and unreported bonuses are not matched.","Ratings use rating points, not percentages."}) end)
    end
    controls.statError=U.text(bar,statHint(),8,118,1020)
    labels()
    host:HookScript("OnMouseDown",E.dismissMenu)
    host:SetScript("OnHide", function() E.dismissMenu();if active then local key=active; active=nil; hidePage(key) end; U.hideTip() end)
    return true
end
function E.page(key)
    if not build() then return end
    if not pages[key] then
        local p = CreateFrame("Frame", nil, host)
        p:SetPoint("TOPLEFT", host, "TOPLEFT", 24, -220); p:SetWidth(1032); p:SetHeight(580); p:Hide()
        pages[key] = p
    end
    return pages[key]
end
function E.show(key)
    if not build() then return false end
    E.dismissMenu()
    if active and active ~= key then hidePage(active) end
    active = key
    host:Show(); pages[key]:Show()
    for _,b in ipairs({controls.min,controls.max}) do if b.dirty then b.flush() end end
    for _,row in ipairs(controls.stats) do if row.min.dirty then row.min.flush() end end
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
    row.rarity=S.fill(b,"ARTWORK",1,1,1,1);row.rarity:SetWidth(34);row.rarity:SetHeight(3);row.rarity:SetPoint("TOPLEFT",b,"TOPLEFT",9,-42)
    row.item = U.text(b, "", 52, 6, width-60); row.item:SetFontObject(GameFontNormal or ChatFontNormal)
    row.from = U.text(b, "", 52, 27, width-60)
    if row.item.SetWordWrap then row.item:SetWordWrap(false); row.from:SetWordWrap(false) end
    b:RegisterForClicks("LeftButtonUp")
    return row
end
function E.paintRow(row, info, name, subtitle)
    row.icon:SetTexture(info and info.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    local title,stats=string.match(name,"^(.-)( · iLvl .*)$")
    row.item:SetText((readableQuality[info and info.quality] or S.WHITE)..(title or name).."|r"..S.GREY..(stats or "").."|r")
    local hex=quality[info and info.quality] or S.WHITE
    row.rarity:SetVertexColor(tonumber(string.sub(hex,5,6),16)/255,tonumber(string.sub(hex,7,8),16)/255,tonumber(string.sub(hex,9,10),16)/255)
    row.from:SetText(S.GREY .. subtitle .. "|r")
end
function E.select(rows, selected)
    for _,r in ipairs(rows) do
        r.selected=r==selected
        local tint=r.selected and 1.15 or 1;r.bg:SetVertexColor(tint,tint,tint)
        if r.selected then r.edge:Show() else r.edge:Hide() end
    end
end
function E._window() return host, controls, pages, tabs end
