-- Read-only companion: never changes profession filters, crafts items, or navigates protected maps.
local _, ns = ...
local P, U, S, Q, D, C = {}, ns.optionalUI, ns.style, ns.questie, ns.professionReference, ns.cookingReference
ns.professions = P
local ui, page, view, selected, filter, faction = nil, 1, "cooking", nil, "All", "Both"
local PAGE, results, learned, scanToken, nativeOwner, nativeEpoch = 6, {}, {}, 0, false, 0
local nativeButtons, hooks = {}, {}
local materialCache, sourceCache = {}, {}
local ingredientIDs={}
for _,r in ipairs(C.recipes) do for _,i in ipairs(r.ingredients) do ingredientIDs[i[1]]=true end end
local refresh
local function show(frame,on) if on then frame:Show() else frame:Hide() end end
local function enabled() return ns.db and ns.db.enabled and ns.db.professionGuide and not ns.isBlocked("professions") end
local function api(name, ...) return U.call(C_TradeSkillUI and C_TradeSkillUI[name], ...) end
local function ownCooking()
    if api("IsDataSourceChanging") or api("IsTradeSkillLinked") or api("IsTradeSkillGuild")
        or api("IsTradeSkillGuildMember") or api("IsNPCCrafting") then return false end
    local p = api("GetBaseProfessionInfo")
    return type(p)=="table" and p.professionID==185
end
local function itemName(id)
    return U.call(GetItemInfo,id) or (C.items[id] and C.items[id].name) or Q.get("item",id,"name") or ("Item "..tostring(id))
end
local function range(map)
    local lo,hi,kind=ns.zoneLevels.range(map)
    if lo then return "zone levels "..lo.."-"..hi..(kind and " ("..kind..")" or "") end
    return kind or "zone levels unknown"
end
local function location(s)
    if not s then return "location unknown" end
    local name=U.call(C_Map and C_Map.GetAreaInfo,s.area) or U.call(GetAreaInfo,s.area)
    return (name or ("Area "..tostring(s.area)))..(s.dungeon and " (dungeon)" or string.format(" %.1f, %.1f",s.x,s.y))
        .."; "..range(s.map)
end
local function npcLines(id, prefix)
    local name=Q.get("npc",id,"name") or ("NPC "..id)
    local lo,hi=Q.get("npc",id,"minLevel"),Q.get("npc",id,"maxLevel")
    local level=type(lo)=="number" and ("; mob level "..lo..(type(hi)=="number" and hi~=lo and ("-"..hi) or "")) or ""
    local out={prefix..name..level}
    local places=Q.spawnList("npc",id)
    for i=1,math.min(2,#places) do out[#out+1]="  "..location(places[i]) end
    if #places==0 then out[#out+1]="  Location unknown in installed Questie." end
    if #places>2 then out[#out+1]="  +"..(#places-2).." other recorded spawn points." end
    return out
end
local function append(a,b) for _,v in ipairs(b) do a[#a+1]=v end end

function P.materialLines(id)
    if materialCache[id] then return materialCache[id] end
    local out,known={},false
    local fish=D.fish[id]
    if fish then
        known=true
        for _,s in ipairs(fish.locations) do
            out[#out+1]="Fish: "..s.water.."; "..range(s.map)
            out[#out+1]="Fishing minimum: "..tostring(s.minSkill or "unknown").."; no-getaway: "..tostring(s.safeSkill or "unknown").." (effective skill, including bonuses)."
            if s.note then out[#out+1]=s.note end
        end
        out[#out+1]="Example waters from the Forever guide; catches vary by water/time."
    end
    local drops=Q.get("item",id,"npcDrops")
    local vendors=Q.get("item",id,"vendors")
    for i,npc in ipairs(type(drops)=="table" and drops or {}) do
        known=true
        if i>6 then out[#out+1]="More drop sources exist in Questie."; break end
        append(out,npcLines(npc,"Drops from: "))
    end
    for i,npc in ipairs(type(vendors)=="table" and vendors or {}) do
        known=true
        if i>3 then out[#out+1]="More sellers exist in Questie.";break end
        append(out,npcLines(npc,"Buy from: "))
    end
    local item=C.items[id]
    if item and item.vendor and not (type(vendors)=="table" and #vendors>0) then
        known=true;out[#out+1]="Vendor supply in the client reference; specific seller unknown."
    end
    -- AnglerAtlas is a zone estimate, never a verified individual-water catch list.
    local a=AnglerAtlas
    local atlas=a and a.MM and U.call(a.MM.GetModule,a.MM,"DATA")
    if type(atlas)=="table" and type(atlas.fish)=="table" and (atlas.fish[id] or atlas.fish[tostring(id)]) then
        local count=0
        local maps={}
        for map in pairs(type(atlas.mapToZoneID)=="table" and atlas.mapToZoneID or {}) do
            if type(map)=="number" then maps[#maps+1]=map end
        end
        table.sort(maps)
        for _,map in ipairs(maps) do
            local zone=atlas.zones and atlas.zones[atlas.mapToZoneID[map]]
            local stats=type(zone)=="table" and zone.fishStats
            if type(stats)=="table" and (stats[id] or stats[tostring(id)]) then
                known=true;count=count+1
                out[#out+1]="AnglerAtlas estimate: "..(zone.name or ("map "..map)).."; "..range(map).."; fishing minimum "..tostring(zone.fishingLevel or "unknown")..(zone.isForeverZone and " (provisional Forever data)" or "")
                if count>=4 then break end
            end
        end
    end
    if not known then out[#out+1]="Farming location, mob and fishing skill unknown in available data; install Questie/AnglerAtlas for additional sources." end
    if type(drops)=="table" and #drops>0 then out[#out+1]="Loot this ingredient from slain mobs; a loot drop does not require Skinning." end
    -- Empty answers may become available when an optional provider finishes loading.
    if known then materialCache[id]=out end
    return out
end

function P.recipeSources(r)
    if sourceCache[r.id] then return sourceCache[r.id] end
    local out={}
    local native=ownCooking() and api("GetRecipeSourceText",r.id)
    if type(native)=="string" and native~="" then out[#out+1]="Live source: "..native end
    for _,line in ipairs(D.cookingSources[r.id] or r.sources or {}) do
        out[#out+1]=line
        for name,place in pairs(D.vendorPlaces) do
            if string.find(line,name,1,true) then out[#out+1]="  "..name.." - "..place end
        end
    end
    for _,id in ipairs(r.books or {}) do
        out[#out+1]="Recipe item: "..itemName(id)
        local sellers=Q.get("item",id,"vendors")
        for i,npc in ipairs(type(sellers)=="table" and sellers or {}) do
            if i>4 then out[#out+1]="Additional sellers recorded in Questie.";break end
            append(out,npcLines(npc,"Vendor: "))
        end
        local drops=Q.get("item",id,"npcDrops")
        for i,npc in ipairs(type(drops)=="table" and drops or {}) do
            if i>3 then out[#out+1]="Additional drops recorded in Questie.";break end
            append(out,npcLines(npc,"Recipe drop: "))
        end
        local quests=Q.get("item",id,"questRewards")
        for i,qid in ipairs(type(quests)=="table" and quests or {}) do
            if i>3 then break end
            out[#out+1]="Quest reward: "..(Q.get("quest",qid,"name") or ("Quest "..qid))
            local start=Q.starter(qid)
            if start then out[#out+1]="  "..(start.who or "Quest giver").." - "..(start.zone or "location unknown") end
        end
    end
    if r.uncertain then out[#out+1]="Unconfirmed client record: availability or ingredients may be incomplete." end
    out[#out+1]="Reference checked "..D.date.."; patch changes may affect sources."
    out[#out+1]="Data: Profit Forever build "..C.build.." + wow-professions.com/forever guides."
    sourceCache[r.id]=out
    return out
end

function P.recipes(query, mode)
    local out={};query=string.lower(query or "")
    for _,r in ipairs(C.recipes) do
        local state=learned[r.id]
        if (mode~="Missing" or state==false) and (mode~="Known" or state==true) then
            local text=r.name
            for _,i in ipairs(r.ingredients) do text=text.." "..(C.items[i[1]] and C.items[i[1]].name or tostring(i[1])) end
            for _,s in ipairs(r.sources) do text=text.." "..s end
            if query=="" or string.find(string.lower(text),query,1,true) then out[#out+1]=r end
        end
    end
    return out
end
local function status(r)
    return learned[r.id]==true and "Known" or learned[r.id]==false and "Missing" or "Unconfirmed"
end
function P.scan()
    scanToken=scanToken+1
    local token,index=scanToken,1
    if not enabled() then return end
    if not ownCooking() then if refresh then refresh() end;return end
    sourceCache={}
    local function step()
        if token~=scanToken or not enabled() or not ownCooking() or not ui or not ui.frame:IsShown() then return end
        if U.call(InCombatLockdown) then ns.after(0.2,step);return end
        for _=1,12 do
            local r=C.recipes[index]
            if not r then if refresh then refresh() end;return end
            local info=api("GetRecipeInfo",r.id)
            -- A missing record is unknown, never evidence of an unlearned recipe.
            if type(info)=="table" and type(info.learned)=="boolean" then learned[r.id]=info.learned
            else learned[r.id]=nil end
            index=index+1
        end
        ns.after(0,step)
    end
    step()
end
local function detail(r)
    selected=r
    ui.setDetail(r.name.." | "..status(r).." | Cooking "..tostring(r.skill or "unknown").."\n\n"..table.concat(P.recipeSources(r),"\n").."\n\nHover the ingredient buttons for farming locations and skills.")
    for i,b in ipairs(ui.ingredients) do
        local reagent=r.ingredients[i]
        if reagent then b.itemID=reagent[1];b:SetLabel(reagent[2].."x "..itemName(reagent[1]));b:Show()
        else b.itemID=nil;b:Hide() end
    end
end
local function upgradeText(p)
    local out={p.name.." - rank upgrades (both factions available)","Guide checked "..D.date.."; higher-rank guide data is partly beta-derived. Confirm with the live trainer."}
    for _,r in ipairs(p.ranks) do
        out[#out+1]="\n"..r.name.." - cap "..r.cap.." | requires skill "..r.skill..(r.level>0 and (", character level "..r.level) or ", no character-level requirement listed")
        out[#out+1]=r.method
        for _,side in ipairs({"Alliance","Horde"}) do if faction=="Both" or faction==side then out[#out+1]=side..": "..r[side] end end
    end
    out[#out+1]="\nSource: "..p.source
    return table.concat(out,"\n")
end
refresh=function()
    if not ui then return end
    local cooking=view=="cooking"
    show(ui.search,cooking);show(ui.searchLabel,cooking);show(ui.mode,cooking);show(ui.faction,not cooking)
    ui.cookingTab:SetLabel((cooking and "> " or "").."Cooking recipes")
    ui.upgradesTab:SetLabel((not cooking and "> " or "").."Upgrades")
    for _,b in ipairs(ui.ingredients) do b:Hide() end
    for _,b in ipairs(ui.professions) do show(b,not cooking) end
    show(ui.previous,cooking);show(ui.nextPage,cooking)
    if not cooking then
        for _,r in ipairs(ui.rows) do r:Hide() end
        ui.counter:SetText("All 12 professions | faction: "..faction)
        ui.setDetail(upgradeText(ui.profession or D.professions[1]));return
    end
    results=P.recipes(ui.search:GetText(),filter)
    local pages=math.max(1,math.ceil(#results/PAGE));page=math.max(1,math.min(page,pages))
    for i,b in ipairs(ui.rows) do
        local r=results[(page-1)*PAGE+i];b.recipe=r
        if r then b:SetLabel(r.name.." | "..status(r).." | "..tostring(r.skill or "?"));b:Show() else b:Hide() end
    end
    ui.mode:SetLabel("Recipes: "..filter)
    local confirmed=0;for _,v in pairs(learned) do if type(v)=="boolean" then confirmed=confirmed+1 end end
    ui.counter:SetText(#results.." recipes | "..page.."/"..pages.." | "..confirmed.." learned states checked")
    local found=false;for _,r in ipairs(results) do if r==selected then found=true;break end end
    if not found then selected=results[1] end
    if selected then detail(selected)
    else ui.setDetail("No recipes match. Missing/Known require live learned-state data: open your own Cooking profession. Unconfirmed recipes remain visible under All.") end
end
local function build()
    if ui then return true end
    local f=U.window("QuestSharingProfessions",740,610,"Cooking and profession guide")
    if not f then return end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    ui={frame=f,rows={},ingredients={},professions={}}
    f:SetScript("OnHide",function() scanToken=scanToken+1;nativeEpoch=nativeEpoch+1 end)
    ui.cookingTab=S.button(f,"Cooking recipes",155,function() view="cooking";refresh() end)
    ui.cookingTab:SetPoint("TOPLEFT",f,"TOPLEFT",20,-34)
    ui.upgradesTab=S.button(f,"Upgrades",135,function() view="upgrades";refresh() end)
    ui.upgradesTab:SetPoint("LEFT",ui.cookingTab,"RIGHT",8,0)
    local reload=S.button(f,"Refresh",90,function() materialCache={};sourceCache={};P.scan();refresh() end)
    reload:SetPoint("TOPRIGHT",f,"TOPRIGHT",-20,-34)
    ui.searchLabel=U.text(f,"Search recipe, ingredient or source",20,70,400)
    ui.search=U.box(f,"",20,70,400,"",100)
    ui.search:SetScript("OnTextChanged",function() page=1;refresh() end)
    ui.mode=S.button(f,"Recipes: All",180,function()
        filter=filter=="All" and "Missing" or filter=="Missing" and "Known" or "All";page=1;refresh()
    end);ui.mode:SetPoint("TOPLEFT",f,"TOPLEFT",440,-87)
    ui.faction=S.button(f,"Faction: Both",180,function()
        faction=faction=="Both" and "Alliance" or faction=="Alliance" and "Horde" or "Both"
        ui.faction:SetLabel("Faction: "..faction);refresh()
    end);ui.faction:SetPoint("TOPLEFT",f,"TOPLEFT",20,-80)
    ui.counter=U.text(f,"",20,122,700)
    for i=1,PAGE do
        local b=S.button(f,"",700,function(self) detail(self.recipe) end)
        b:SetPoint("TOPLEFT",f,"TOPLEFT",20,-(144+(i-1)*26))
        b:SetScript("OnEnter",function(self) if self.recipe then U.tip(self,self.recipe.name,P.recipeSources(self.recipe)) end end)
        b:SetScript("OnLeave",U.hideTip);ui.rows[i]=b
    end
    ui.detail,ui.setDetail,ui.detailScroll=U.scrollText(f,250,314,470,220)
    for i=1,6 do
        local b=S.button(f,"",220,function() end)
        b:SetPoint("TOPLEFT",f,"TOPLEFT",20,-(314+(i-1)*34))
        b:SetScript("OnEnter",function(self) if self.itemID then U.tip(self,itemName(self.itemID),P.materialLines(self.itemID)) end end)
        b:SetScript("OnLeave",U.hideTip);ui.ingredients[i]=b
    end
    -- Upgrade text uses the same scroll area with a wider, taller viewport.
    ui.cookingDetail=ui.detail
    local upgradeDetail,setUpgrade,upgradeScroll=U.scrollText(f,225,146,495,385)
    ui.upgradeDetail=upgradeDetail
    ui.detail:SetWordWrap(true);upgradeDetail:SetWordWrap(true)
    upgradeScroll:Hide()
    local setCooking=ui.setDetail
    ui.setDetail=function(text)
        local upgrades=view=="upgrades"
        show(ui.detailScroll,not upgrades);show(upgradeScroll,upgrades)
        if upgrades then setUpgrade(text);upgradeScroll:SetVerticalScroll(0)
        else setCooking(text);ui.detailScroll:SetVerticalScroll(0) end
    end
    for i,p in ipairs(D.professions) do
        local b=S.button(f,p.name,190,function() ui.profession=p;refresh() end)
        b:SetPoint("TOPLEFT",f,"TOPLEFT",20,-(146+(i-1)*30));ui.professions[i]=b
    end
    ui.previous=S.button(f,"Previous",100,function() page=page-1;refresh() end)
    ui.previous:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",20,28)
    ui.nextPage=S.button(f,"Next",100,function() page=page+1;refresh() end)
    ui.nextPage:SetPoint("LEFT",ui.previous,"RIGHT",8,0)
    U.text(f,"Reference information only. Unknown sources and learned states are labelled; /qs professions off disables integration.",20,588,700)
    return true
end

function P.open(tab,fromNative)
    if not ns.db.enabled then ns.print("switch Quest Sharing on first (/qs on)");return end
    if not ns.db.professionGuide then ns.setSetting("professionGuide",true) end
    if not build() then return end
    nativeOwner=fromNative==true;view=tab=="upgrades" and "upgrades" or "cooking"
    ui.frame:Show();refresh()
    if view=="cooking" then P.scan() end
end
function P.close() nativeEpoch=nativeEpoch+1;scanToken=scanToken+1;if ui then ui.frame:Hide() end end
local function install()
    for _,name in ipairs({"ProfessionsFrame","TradeSkillFrame","CraftFrame"}) do
        local frame=_G[name]
        if frame and frame.HookScript and not hooks[frame] and not U.call(InCombatLockdown) then
            hooks[frame]=true
            local strip=CreateFrame("Frame",nil,frame);strip:SetWidth(310);strip:SetHeight(26)
            strip:SetPoint("TOPLEFT",frame,"BOTTOMLEFT",0,-5)
            local b=S.button(strip,"QS Cooking",145,function() P.open("cooking",true) end)
            b:SetPoint("TOPLEFT",strip,"TOPLEFT",0,0)
            local u=S.button(strip,"QS Upgrades",145,function() P.open("upgrades",true) end)
            u:SetPoint("LEFT",b,"RIGHT",8,0)
            nativeButtons[#nativeButtons+1]=strip
            show(strip,enabled())
            frame:HookScript("OnHide",function() if nativeOwner then P.close() end end)
        end
    end
end
function P.settingChanged()
    install()
    for _,b in ipairs(nativeButtons) do show(b,enabled()) end
    if not enabled() then P.close() end
end
local pending=false
local function changed()
    if pending or not enabled() then return end
    pending=true
    ns.after(0.1,function()
        pending=false
        if enabled() and ui and ui.frame:IsShown() and view=="cooking" then P.scan() end
    end)
end
local function shown()
    if not enabled() then return end
    install()
    nativeEpoch=nativeEpoch+1
    local epoch,attempt=nativeEpoch,0
    local function ready()
        if epoch~=nativeEpoch or not enabled() then return end
        attempt=attempt+1
        if api("IsDataSourceChanging") and attempt<10 then ns.after(0.1,ready);return end
        if ownCooking() then P.open("cooking",true)
        elseif nativeOwner and ui and view=="cooking" then P.close() end
    end
    ns.after(0.1,ready)
end
local function tooltip(self,data)
    if not enabled() then return end
    local _,link=U.call(self.GetItem,self)
    local id=type(data)=="table" and data.id or type(link)=="string" and tonumber(link:match("item:(%d+)"))
    if type(id)~="number" or self.questSharingFarmID==id or not ingredientIDs[id] then return end
    self.questSharingFarmID=id
    self:AddLine("Quest Sharing - ingredient sources",0.95,0.78,0.30)
    for _,line in ipairs(P.materialLines(id)) do self:AddLine(line,1,1,1,true) end
    self:Show()
end
local tooltipHooked=false
local function setup()
    install()
    for _,b in ipairs(nativeButtons) do show(b,enabled()) end
    if not tooltipHooked and GameTooltip and GameTooltip.HookScript then
        tooltipHooked=true
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,tooltip)
        else U.call(GameTooltip.HookScript,GameTooltip,"OnTooltipSetItem",tooltip) end
        U.call(GameTooltip.HookScript,GameTooltip,"OnTooltipCleared",function(self) self.questSharingFarmID=nil end)
    end
end
ns.on("PLAYER_LOGIN",setup)
ns.on("ADDON_LOADED",function() materialCache={};sourceCache={};setup() end)
ns.on("TRADE_SKILL_SHOW",shown)
ns.on("TRADE_SKILL_CLOSE",function() nativeEpoch=nativeEpoch+1;scanToken=scanToken+1;if nativeOwner then P.close() end end)
ns.on("TRADE_SKILL_LIST_UPDATE",changed)
ns.on("TRADE_SKILL_DATA_SOURCE_CHANGED",function() learned={};sourceCache={};shown() end)
ns.on("SPELLS_CHANGED",function() learned={};sourceCache={};changed() end)
ns.on("PLAYER_REGEN_ENABLED",setup)
function P._window() return ui end
function P._learned() return learned end
