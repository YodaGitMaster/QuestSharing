-- Recipe/farming data and guarded native Cooking reads; presentation lives inside ProfessionUI.lua.
local _, ns = ...
local P, U, Q, D, C = {}, ns.optionalUI, ns.questie, ns.professionReference, ns.cookingReference
ns.professions = P
local learned, liveInfo, scanToken, eventToken = {}, {}, 0, 0
local materialCache, sourceCache = {}, {}
local catalogue, byID, ingredientIDs, staticIDs = {}, {}, {}, {}
for _,r in ipairs(C.recipes) do
    catalogue[#catalogue+1]=r;byID[r.id]=r;staticIDs[r.id]=true
    for _,i in ipairs(r.ingredients) do ingredientIDs[i[1]]=true end
end
local function ui() return ns.professionUI end
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
-- Faction home zones of the example waters (uiMapID); other zones are shared and get no tag.
local WATER_SIDE={[1429]="Alliance",[1453]="Alliance",[1411]="Horde",[1456]="Horde"}
local function waterText(s)
    local side=WATER_SIDE[s.map]
    return s.water..(side and (" ("..side.." area)") or "")
end
local function fishSkillText(s)
    local parts={}
    if s.minSkill then parts[#parts+1]="Fish bite from fishing skill "..s.minSkill end
    -- safeSkill counts pole and lure bonuses (ProfessionReference.lua)
    if s.safeSkill then parts[#parts+1]="Fish stay hooked from skill "..s.safeSkill.." (pole and lure bonuses count)" end
    if #parts==0 then return "Fishing skill needed: not known." end
    return table.concat(parts,"; ").."."
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
        -- waters of your own faction first, the other faction's tagged
        local side=U.call(UnitFactionGroup,"player")
        local list={}
        local order={}
        for i,s in ipairs(fish.locations) do list[i]=s; order[s]=i end
        table.sort(list,function(a,b)
            local ao,bo=WATER_SIDE[a.map]==side,WATER_SIDE[b.map]==side
            if ao~=bo then return ao end
            return order[a]<order[b]
        end)
        for _,s in ipairs(list) do
            out[#out+1]="Fish: "..waterText(s).."; "..range(s.map)
            out[#out+1]=fishSkillText(s)
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
        known=true;out[#out+1]="Sold by vendors (seller not known)."
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

-- List labels are intentionally short; the selected pane/hover retains the full acquisition data.
function P.shortSource(r)
    local side=U.call(UnitFactionGroup,"player")
    local lines=D.cookingSources[r.id] or r.sources or {}
    local line=lines[1] or "Source unknown"
    for _,v in ipairs(lines) do if side and v:find(side..":",1,true) then line=v;break end end
    if line:find("[Bb]uy") or line:find("[Vv]endor") then
        local place=line:match("%(([^)]+)%)")
        for name,where in pairs(D.vendorPlaces) do
            local other=side=="Alliance" and where:find("(Horde)",1,true) or side=="Horde" and where:find("(Alliance)",1,true)
            if line:find(name,1,true) and not D.cookingSources[r.id] and not other then place=where;break end
        end
        return "Vendor"..(place and (" - "..place) or "")
    end
    if line:find("[Tt]rainer") then return "Trainer" end
    if line:find("[Qq]uest") then return (line:gsub("^[^:]*[Qq]uest:%s*","Quest - ")) end
    if line:find("[Dd]rop") then return (line:gsub("[Dd]rop:%s*","Drop - ")) end
    return "Source unknown"
end
function P.acquisition(r)
    local side=U.call(UnitFactionGroup,"player")
    local out,seen={},{}
    if D.cookingSources[r.id] then
        local native=ownCooking() and api("GetRecipeSourceText",r.id)
        if type(native)=="string" and native~="" then out[#out+1]=native end
        for _,line in ipairs(D.cookingSources[r.id]) do
            if not (side=="Alliance" and line:find("Horde:",1,true))
                and not (side=="Horde" and line:find("Alliance:",1,true)) then out[#out+1]=line end
        end
        return out
    end
    for _,line in ipairs(P.recipeSources(r)) do
        local hide=line:find("Reference checked",1,true) or line:find("Data: ",1,true)
            or line:find("Recipe item:",1,true) or line:find("other recorded spawn",1,true)
        if side=="Alliance" and line:find("Horde:",1,true) then hide=true end
        if side=="Horde" and line:find("Alliance:",1,true) then hide=true end
        if side=="Alliance" and line:find("(Horde)",1,true) then hide=true end
        if side=="Horde" and line:find("(Alliance)",1,true) then hide=true end
        if not hide and line~="" and not seen[line] then
            seen[line]=true;out[#out+1]=line:gsub("^Live source:%s*","")
        end
    end
    return out
end
function P.name(r) return liveInfo[r.id] and liveInfo[r.id].name or r.name end
function P.state(r) return learned[r.id] end
function P.live(r) return liveInfo[r.id] end
function P.itemName(id) return itemName(id) end
function P.active() return enabled() end
function P.ownCooking() return ownCooking() end
function P.record(id) return byID[id] end
function P.recipes(query,mode)
    local out={};query=string.lower(query or "")
    for _,r in ipairs(catalogue) do
        local state=learned[r.id]
        if (mode~="Missing" or state==false) and (mode~="Known" or state==true) then
            local text=P.name(r)
            for _,i in ipairs(r.ingredients) do text=text.." "..(C.items[i[1]] and C.items[i[1]].name or tostring(i[1])) end
            for _,s in ipairs(r.sources) do text=text.." "..s end
            if query=="" or string.find(string.lower(text),query,1,true) then out[#out+1]=r end
        end
    end
    table.sort(out,function(a,b)
        if (a.skill or 10000)~=(b.skill or 10000) then return (a.skill or 10000)<(b.skill or 10000) end
        if P.name(a)~=P.name(b) then return P.name(a)<P.name(b) end
        return a.id<b.id
    end)
    return out
end
function P.scan()
    scanToken=scanToken+1
    local token,index=scanToken,1
    local v=ui()
    if not enabled() or not v or not v.activeCooking() then return end
    if not ownCooking() then v.refresh();return end
    sourceCache={}
    local ids=api("GetAllRecipeIDs") or api("GetFilteredRecipeIDs") or {}
    local extraIndex=1
    local function step()
        if token~=scanToken or not enabled() or not ownCooking() or not v.activeCooking() then return end
        if U.call(InCombatLockdown) then ns.after(0.2,step);return end
        for _=1,12 do
            local r=C.recipes[index]
            if r then
                local info=api("GetRecipeInfo",r.id)
                liveInfo[r.id]=type(info)=="table" and info or nil
                if type(info)=="table" and type(info.learned)=="boolean" then learned[r.id]=info.learned
                else learned[r.id]=nil end
                index=index+1
            else
                local id=type(ids)=="table" and ids[extraIndex]
                if not id then v.refresh();return end
                extraIndex=extraIndex+1
                -- The native API may return several professions; never mix them into Cooking.
                if type(id)=="number" and not byID[id] and api("IsRecipeInSkillLine",id,185)==true then
                    local info=api("GetRecipeInfo",id)
                    if type(info)=="table" and type(info.name)=="string" then
                        local record={id=id,name=info.name,ingredients={},books={},sources={"Source unknown"}}
                        byID[id]=record;catalogue[#catalogue+1]=record
                        liveInfo[id]=info
                        if type(info.learned)=="boolean" then learned[id]=info.learned end
                    end
                elseif byID[id] and not staticIDs[id] then
                    -- Existing live-only records are refreshed on later scans, too.
                    local info=api("GetRecipeInfo",id)
                    if type(info)=="table" then liveInfo[id]=info;learned[id]=info.learned end
                end
            end
        end
        ns.after(0,step)
    end
    step()
end
function P.clearCaches() materialCache={};sourceCache={} end
function P.open()
    if not ns.db.enabled then ns.print("switch Quest Sharing on first (/qs on)");return end
    if not ns.db.professionGuide then ns.setSetting("professionGuide",true) end
    local v=ui()
    if not v or not v.attach() then ns.print("Open the game's profession window (K), then choose Cooking.");return end
    if not ProfessionsFrame:IsShown() then
        ns.print("Open the game's profession window (K), then choose Cooking.");return
    end
    v.open()
    if not ownCooking() then ns.print("Choose Cooking using the profession tabs on the right.") end
end
function P.close() eventToken=eventToken+1;scanToken=scanToken+1;if ui() then ui().close() end end
function P.settingChanged()
    if ui() then ui().attach();ui().refresh() end
    if not enabled() then P.close() end
end
local pending=false
local function changed()
    if pending or not enabled() then return end
    pending=true
    ns.after(0.1,function()
        pending=false
        if enabled() and ui() then ui().attach();ui().refresh();if ui().activeCooking() then P.scan() end end
    end)
end
local function shown()
    eventToken=eventToken+1
    local token,attempt=eventToken,0
    local function ready()
        if token~=eventToken or not enabled() then return end
        attempt=attempt+1
        if api("IsDataSourceChanging") and attempt<10 then ns.after(0.1,ready);return end
        if ui() and ui().attach() then ui().refresh();if ui().activeCooking() then P.scan() end end
    end
    ns.after(0.1,ready)
end
-- materialLines without its creature drops: "Drops from:" with its indented spawn lines and the two drop notes
local function withoutDrops(lines)
    local out,skipping={},false
    for _,l in ipairs(lines) do
        if l:find("^Drops from: ") then skipping=true
        elseif not (skipping and l:find("^  ")) then
            skipping=false
            if not (l:find("^More drop sources") or l:find("^Loot this ingredient")) then out[#out+1]=l end
        end
    end
    return out
end
P._withoutDrops=withoutDrops                                           -- for the tests
local function tooltip(self,data)
    if not enabled() then return end
    local _,link=U.call(self.GetItem,self)
    local id=type(data)=="table" and data.id or type(link)=="string" and tonumber(link:match("item:(%d+)"))
    if type(id)~="number" or self.questSharingFarmID==id or not ingredientIDs[id] then return end
    self.questSharingFarmID=id
    local lines=P.materialLines(id)
    if ns.gatherSources and ns.gatherSources.covers(id) then lines=withoutDrops(lines) end  -- one ranked drop list, from GatherSources
    if #lines==0 then return end
    self:AddLine("Where to gather",0.95,0.78,0.30)
    for _,line in ipairs(lines) do self:AddLine(line,1,1,1,true) end
    self:Show()
end
local tooltipHooked=false
local function setup()
    if ui() then ui().attach();ui().refresh() end
    if not tooltipHooked and GameTooltip and GameTooltip.HookScript then
        tooltipHooked=true
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,tooltip)
        else U.call(GameTooltip.HookScript,GameTooltip,"OnTooltipSetItem",tooltip) end
        U.call(GameTooltip.HookScript,GameTooltip,"OnTooltipCleared",function(self) self.questSharingFarmID=nil end)
    end
end
ns.on("PLAYER_LOGIN",setup)
ns.on("ADDON_LOADED",function() P.clearCaches();setup() end)
ns.on("TRADE_SKILL_SHOW",shown)
ns.on("TRADE_SKILL_CLOSE",function() P.close() end)
ns.on("TRADE_SKILL_LIST_UPDATE",changed)
ns.on("TRADE_SKILL_DATA_SOURCE_CHANGED",function() learned={};liveInfo={};sourceCache={};shown() end)
ns.on("SPELLS_CHANGED",function() learned={};liveInfo={};sourceCache={};changed() end)
ns.on("PLAYER_REGEN_ENABLED",setup)
function P._window() return ui() and ui()._view() end
function P._learned() return learned end
