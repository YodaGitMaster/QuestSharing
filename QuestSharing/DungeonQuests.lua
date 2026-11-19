-- Explicit-open quest catalogue. Dungeon association follows quest locations, not reward equipment or pickup zone.
local ADDON, ns = ...
local D, Q, E, U, S, C = {}, ns.questie, ns.equipmentUI, ns.optionalUI, ns.style, ns.compat
ns.dungeonQuests = D
local window, filters, records, results, places = nil, nil, {}, {}, {}
local ready, loading, page, progress, total = false, false, 1, 0, 0
local selected, message, generation = nil, "Open to read dungeon quests.", 0
local filterError
-- Whole-catalogue quest links from the last scan: chainPrev[id][before]=required, chainNext[id][after]=required.
-- "required" = the later quest cannot be taken without the earlier one (so finishing it proves the earlier one is done).
local chainPrev, chainNext = {}, {}
local chainLead = {} -- chainLead[after][before]=true: an optional lead-in (breadcrumb) that only points you to `after`
local depthOf = {} -- result id -> nesting level in the list
local pageStarts = {1} -- first result index of each page: a chain that fits on one page is never split
local refreshPending=false
local focusTarget -- the dungeon you stood in when the window opened; chosen once the list is read (no tie: no choice)
local redraw=false -- a filter changed: the details are drawn again even if the same quest stays selected
-- What the last scan read: its faction, class and level filters. Quests outside them were skipped by one cheap read each,
-- so a filter that widens past this needs a new scan (D.refresh), and one that narrows does not.
local scope
local menuEntry, menuQuest -- what D.menu last opened, to tell our right-click menu from other windows' menus
local PAGE, OWNER, REWARDS_OWNER = 5, "dungeonQuests", "dungeonQuestRewards"
local FOREGROUND_MS = 8 -- the player is waiting on this visible list; it reads ~18 fields per quest
local rewardIndex, rewardsReady, rewardsLoading = {}, false, false
local hovered, showHover
local paint
-- Memory: the catalogue is read once and kept for the session; only Settings "Purge" (D.purge) or switching the addon
-- off (D.close) frees it. A paused scan still holds its tables, so the jobs go too.
local function release()
    ns.dataWork.keep(OWNER)
    generation=generation+1
    ns.dataWork.cancel(OWNER);ns.dataWork.cancel(REWARDS_OWNER)
    records,results,places={}, {}, {}
    chainPrev,chainNext,depthOf,chainLead={}, {}, {}, {}
    rewardIndex,rewardsReady,rewardsLoading={},false,false
    ready,loading,progress,total,selected,hovered,scope=false,false,0,0,nil,nil,nil
    if window then for _,row in ipairs(window.rows or {}) do row.result=nil end end
end
local function number(v) return tonumber(v) or 0 end
local function enums() return type(LibQuestieDB)=="table" and LibQuestieDB.Enum or {} end
local function areaName(area)
    return U.call(C_Map and C_Map.GetAreaInfo,area) or U.call(GetAreaInfo,area) or ("Dungeon area "..area)
end
local function defaults(mine)
    local _,class=U.call(UnitClass,"player")
    return {dungeon=0,faction=mine and U.call(UnitFactionGroup,"player") or "All factions",
        class=mine and class or "All classes",level=math.max(1,number(U.call(UnitLevel,"player"))),
        allLevels=not mine,hideCompleted=false,hideLog=false,text=""}
end
local function shown() return window and ns.db.enabled and E.visible(OWNER) end
local function completed(id)
    return U.call((C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted,id)==true
end
local function inLog(id) return C.findEntry(id)~=nil end -- taken: in the quest log right now
local function finished(id,seen)
    if completed(id) then return true,false end
    seen=seen or {}
    if seen[id] then return false end
    seen[id]=true
    -- A later step that needs this one is done -> this one was done too (or can no longer be taken).
    -- Every quest this one leads to is done (even if each only needs "any one of" several earlier quests, and this is
    -- just one of those): nothing is left for it to unlock, so it is pointless to go and take it.
    -- "Done" for the quest it leads to also counts when you already took it: the game stops offering a lead-in then.
    local count,everyDone=0,true
    for after,required in pairs(chainNext[id] or {}) do
        count=count+1
        if inLog(after) or finished(after,seen) then
            if required then return true,true end
        else everyDone=false end
    end
    if count>0 and everyDone then return true,true end
    return false
end
local function playerLevel() return tonumber(U.call(UnitLevel,"player")) end
-- Can my character take it now: level reached (and not above a level cap), and not a quest for the other faction.
local function canTake(r)
    local level=playerLevel()
    if level and (r.required>level or (r.max>0 and level>r.max)) then return false end
    local mask=enums().factionRaceMasks and enums().factionRaceMasks[U.call(UnitFactionGroup,"player") or ""]
    if mask and r.races~=0 and not ns.rewards.overlaps(r.races,mask) then return false,"faction" end
    local _,class=U.call(UnitClass,"player")
    local classMask=class and enums().classKeys and enums().classKeys[class]
    if classMask and r.classes~=0 and not ns.rewards.overlaps(r.classes,classMask) then return false,"class" end
    return true
end
-- ===== Keyword colours: every kind of keyword has its own colour, on parchment (KW) and on the dark list (KW_ROW) =====
local KW={npc="|cff006666",place="|cff8a4000",num="|cff8a1a6a",quest="|cff8a0c0c",item="|cff6a4a00",dungeon="|cff1a2a6a",
    done="|cff0d6e0d",log="|cff8a5a00",bad="|cff9a1a1a"}
local KW_ROW={npc="|cffffffff",place="|cffffc080",num="|cffff9ad8",dungeon="|cffa0c0ff"}
local KW_ROUTE={npc="|cffffffff",place="|cffffc080",num="|cffff9ad8",quest="|cffffd100",item="|cff9fe6ff"} -- the route window (dark stone)
local ROUTE_RIDE=false
local function kw(kind,text,palette) return (palette or KW)[kind]..tostring(text).."|r" end
local function escape(text) return (string.gsub(text,"[%^%$%(%)%%%.%[%]%*%+%-%?]","%%%0")) end
-- Colour numbers, then known names, inside plain text (never inside existing colour codes: numbers go first).
local function highlight(text,names,palette)
    palette=palette or KW
    text=string.gsub(text,"%d[%d,%.]*",function(n)
        local tail=string.match(n,"[,%.]+$") or "" -- "10." at the end of a sentence: the dot is not part of the number
        return palette.num..string.sub(n,1,#n-#tail).."|r"..tail
    end)
    local seen={}
    for _,pair in ipairs(names or {}) do
        local name,kind=pair[1],pair[2]
        local inside=false
        for done in pairs(seen) do if type(name)=="string" and string.find(done,name,1,true) then inside=true;break end end
        if type(name)=="string" and #name>2 and not inside and palette[kind] then
            seen[name]=true
            text=string.gsub(text,escape(name),palette[kind]..name.."|r")
        end
    end
    return text
end
-- "NPC — Zone 12.3, 45.6" with the NPC and the place in their colours.
local function placeText(p,palette)
    palette=palette or KW
    if not p then return "unknown" end
    local source=p.source
    local who=source.startsFrom and ("item "..kw("item",source.startsFrom.name or source.startsFrom.id,palette.item and palette or KW).." from "..kw("npc",source.name or "?",palette))
        or kw("npc",source.name or "unknown",palette)
    return who,(p.point and kw("place",Q.where(p.point),palette) or "location unknown")
end
local function bold(t,color)
    if t.SetShadowColor then t:SetShadowColor(color[1],color[2],color[3],1) end
    if t.SetShadowOffset then t:SetShadowOffset(1,0) end
end

local function classChoices()
    local list={{value="All classes",label="All classes"}}
    local keys={}
    for key,mask in pairs(enums().classKeys or {}) do
        if type(mask)=="number" and mask>0 and not string.find(key,"ALL",1,true) and key~="NONE" then keys[#keys+1]=key end
    end
    table.sort(keys)
    for _,key in ipairs(keys) do
        list[#list+1]={value=key,label=(LOCALIZED_CLASS_NAMES_MALE or {})[key] or key}
    end
    return list
end
local function dungeonChoices()
    local list,sorted={{value=0,label="All dungeons"}},{}
    for _,place in pairs(places) do sorted[#sorted+1]=place end
    table.sort(sorted,function(a,b) if a.name~=b.name then return a.name<b.name end;return a.area<b.area end)
    for _,place in ipairs(sorted) do list[#list+1]={value=place.area,label=place.name.." ("..place.count..")"} end
    return list
end

local function currentDungeon()
    local name,kind
    if type(GetInstanceInfo)=="function" then
        local ok,n,k=pcall(GetInstanceInfo)
        if ok then name,kind=n,k end
    end
    local inside,instanceType=U.call(IsInInstance)
    if inside==false or (kind or instanceType)~="party" then return end
    local subzone=U.call(GetSubZoneText)
    name=type(name)=="string" and name~="" and name or U.call(GetRealZoneText)
    return {name=name,subzone=type(subzone)=="string" and subzone~="" and subzone or nil}
end
-- Same rule as Instance drops: the best name match wins, and a tie chooses nothing.
local function focusCurrentDungeon()
    local target=focusTarget
    focusTarget=nil
    if not target then return end
    local best,score,tied=nil,0,false
    for area,place in pairs(places) do
        local rank=(place.name==target.subzone and 20 or 0)+(place.name==target.name and 10 or 0)
        if rank>score then best,score,tied=area,rank,false elseif rank>0 and rank==score then tied=true end
    end
    if best and not tied then filters.dungeon,page=best,1 end
end

local function covers(done,f)
    if done.faction~="All factions" and f.faction~=done.faction then return false end
    if done.class~="All classes" and f.class~=done.class then return false end
    return done.allLevels or (not f.allLevels and f.level<=done.level)
end

function D.search(f)
    filters=f or filters or defaults()
    results={};pageStarts={1}
    local mask=enums().factionRaceMasks and enums().factionRaceMasks[filters.faction]
    local class=enums().classKeys and enums().classKeys[filters.class]
    filterError=nil
    if (filters.faction~="All factions" and not mask) or (filters.class~="All classes" and not class) then
        filterError="This QuestieDB cannot filter by class or faction. Install or update QuestieDB (see /qs questie), or use All quests."
        return results
    end
    local needle=string.lower(filters.text or "")
    for _,r in pairs(records) do
        if (filters.dungeon==0 or r.dungeons[filters.dungeon])
            and (filters.allLevels or (r.required<=filters.level and (r.max==0 or filters.level<=r.max)))
            and (filters.class=="All classes" or r.classes==0 or (class and ns.rewards.overlaps(r.classes,class)))
            and (filters.faction=="All factions" or r.races==0 or (mask and ns.rewards.overlaps(r.races,mask)))
            and (not filters.hideCompleted or not finished(r.id))
            and (not filters.hideLog or not inLog(r.id))
            and (needle=="" or string.find(string.lower(r.name.." "..r.id.." "..r.dungeonText),needle,1,true)) then
            results[#results+1]=r
        end
    end
    table.sort(results,function(a,b)
        if filters.dungeon==0 and a.dungeonText~=b.dungeonText then return a.dungeonText<b.dungeonText end
        if a.level~=b.level then return a.level<b.level end
        if a.name~=b.name then return a.name<b.name end
        return a.id<b.id
    end)
    -- Nest chains: a step directly follows the earlier step it needs, one level deeper (only steps that are listed).
    local inList={};for _,r in ipairs(results) do inList[r.id]=r end
    local ordered,placed={},{}
    depthOf={}
    local function place(r,depth)
        if placed[r.id] then return end
        placed[r.id]=true;depthOf[r.id]=depth;ordered[#ordered+1]=r
        local kids={}
        for after in pairs(chainNext[r.id] or {}) do if inList[after] then kids[#kids+1]=inList[after] end end
        table.sort(kids,function(a,b) if a.level~=b.level then return a.level<b.level end;return a.id<b.id end)
        for _,kid in ipairs(kids) do place(kid,depth+1) end
    end
    for _,r in ipairs(results) do
        local top=true
        for before in pairs(chainPrev[r.id] or {}) do if inList[before] then top=false;break end end
        if top then place(r,0) end
    end
    for _,r in ipairs(results) do place(r,0) end -- anything a loop left out
    results=ordered
    -- Pages: start a new page rather than split a chain (top step + its nested steps) that fits on one page.
    pageStarts={1}
    local count,index=0,1
    while index<=#results do
        local size=1
        while results[index+size] and (depthOf[results[index+size].id] or 0)>0 do size=size+1 end
        if count>0 and size<=PAGE and count+size>PAGE then pageStarts[#pageStarts+1]=index;count=0 end
        for k=index,index+size-1 do
            if count==PAGE then pageStarts[#pageStarts+1]=k;count=0 end
            count=count+1
        end
        index=index+size
    end
    return results
end

-- Cache only repeated source associations (bounded to 256); no item catalogue enumeration or native item reads.
local function memberships(id,read,sourceCache)
    local found={}
    local function add(area) if ns.loot.isDungeonArea(area) then found[tonumber(area)]=true end end
    add(read("quest",id,"zoneOrSort"))
    local function source(kind,sourceID,collect)
        local key=kind..":"..tostring(sourceID)
        local areas=sourceCache[key]
        if not areas then
            areas={outside=false,known=false}
            local spawns=read(kind,sourceID,"spawns")
            for area,points in pairs(type(spawns)=="table" and spawns or {}) do
                if type(points)=="table" and next(points) then
                    areas.known=true
                    if ns.loot.isDungeonArea(area) then areas[#areas+1]=tonumber(area) else areas.outside=true end
                end
            end
            sourceCache.slot=(sourceCache.slot or 0)%256+1
            sourceCache.keys=sourceCache.keys or {}
            local old=sourceCache.keys[sourceCache.slot]
            if old then sourceCache[old]=nil end
            sourceCache.keys[sourceCache.slot],sourceCache[key]=key,areas
        end
        if collect~=false then for _,area in ipairs(areas) do add(area) end end
        return areas
    end
    local function sources(kind,ids,rows)
        for _,value in ipairs(type(ids)=="table" and ids or {}) do
            local sourceID=rows and type(value)=="table" and value[1] or value
            if type(sourceID)=="number" then source(kind,sourceID) end
        end
    end
    local function item(itemID,starter)
        local areas,outside={},false
        for _,kind in ipairs({"npc","object"}) do
            local ids=read("item",itemID,kind=="npc" and "npcDrops" or "objectDrops")
            for _,from in ipairs(type(ids)=="table" and ids or {}) do
                local locations=source(kind,from,false)
                if locations.outside or not locations.known then outside=true end
                for _,area in ipairs(locations) do areas[area]=true end
            end
        end
        -- Shared cloth, leather, food and crafted goods do not make every collection quest a dungeon quest.
        if starter or not outside then for area in pairs(areas) do add(area) end end
    end
    for _,field in ipairs({"startedBy","finishedBy"}) do
        local by=read("quest",id,field)
        if type(by)=="table" then
            sources("npc",by[1]);sources("object",by[2])
            for _,itemID in ipairs(type(by[3])=="table" and by[3] or {}) do item(itemID,true) end
        end
    end
    local objectives=read("quest",id,"objectives")
    if type(objectives)=="table" then
        sources("npc",objectives[1],true);sources("object",objectives[2],true)
        for _,row in ipairs(type(objectives[3])=="table" and objectives[3] or {}) do
            if type(row)=="table" and type(row[1])=="number" then item(row[1]) end
        end
        for _,row in ipairs(type(objectives[5])=="table" and objectives[5] or {}) do
            if type(row)=="table" then sources("npc",row[1]) end
        end
    end
    local trigger=read("quest",id,"triggerEnd")
    for area in pairs(type(trigger)=="table" and type(trigger[2])=="table" and trigger[2] or {}) do add(area) end
    return found
end

-- The saved list (ns.dataWork.saved) per filter scope: the dungeon quests plus every quest linked to one of them, so a
-- scan of only those IDs builds the same records, chains and chain names as a scan of the whole catalogue.
local SAVED="dungeonQuests"
local function savedScope(f) return table.concat({tostring(f.faction),tostring(f.class),f.allLevels and "all" or tostring(f.level)},"|") end
local function linkedIDs(all)
    local keep={}
    local function each(r,fn)
        for _,list in ipairs({r.beforeAny,r.beforeAll}) do if type(list)=="table" then for _,v in ipairs(list) do fn(v) end end end
        if type(r.crumbs)=="table" then for _,v in ipairs(r.crumbs) do fn(v) end else fn(r.crumbs) end
        fn(r.next);fn(r.crumbFor);fn(r.availUntil);for _,v in ipairs(r.inferred or {}) do fn(v) end
    end
    for id,r in pairs(all) do
        if records[id] then
            keep[id]=true
            each(r,function(v) v=math.abs(number(v)); if all[v] then keep[v]=true end end)
        else
            each(r,function(v) if records[math.abs(number(v))] then keep[id]=true end end)
        end
    end
    return ns.dataWork.sortedKeys(keep)
end
function D.scan(full)
    if not shown() then return false end
    ns.closeQuestMenu();E.dismissMenu();ns.dataWork.cancel(OWNER)
    ns.dataWork.cancel(REWARDS_OWNER)
    filters=filters or defaults(true)
    scope={faction=filters.faction,class=filters.class,level=filters.level,allLevels=filters.allLevels}
    local gate={level=not filters.allLevels and filters.level or nil,noMax=true}
    if filters.faction~="All factions" then gate.raceMask=enums().factionRaceMasks and enums().factionRaceMasks[filters.faction] end
    if filters.class~="All classes" then gate.classMask=enums().classKeys and enums().classKeys[filters.class] end
    rewardIndex,rewardsReady,rewardsLoading={},false,false
    generation=generation+1
    local token=generation
    records,results,places={}, {}, {}
    chainPrev,chainNext,depthOf,chainLead={}, {}, {}, {}
    ready,loading,progress,total,filterError=false,true,0,0,nil
    message="No dungeon quest list yet. Install or update QuestieDB (see /qs questie)."
    local key=savedScope(filters)
    ns.dataWork.start(OWNER,function()
        local saved=full~=true and ns.dataWork.saved(SAVED,key)
        local ids=saved or Q.ids("quest")
        if type(ids)~="table" then loading=false;paint();return end
        total=#ids
        local cache,all,seeds={},{},{}
        local function read(kind,id,key) local value=Q.get(kind,id,key);ns.dataWork.checkpoint();return value end
        for _,id in ipairs(ids) do
            -- Only single numbers are read until a quest passes the filters; its spawns and objectives wait for that.
            local name=not Q.questGate(id,gate) and read("quest",id,"name")
            if type(name)=="string" and name~="" then
                local r={id=id,name=name,level=number(read("quest",id,"questLevel")),
                    required=number(read("quest",id,"requiredLevel")),max=number(read("quest",id,"requiredMaxLevel")),
                    classes=number(read("quest",id,"requiredClasses")),races=number(read("quest",id,"requiredRaces")),
                    beforeAny=read("quest",id,"preQuestSingle"),beforeAll=read("quest",id,"preQuestGroup"),
                    next=read("quest",id,"nextQuestInChain"),dungeons=memberships(id,read,cache),
                    -- Other ways Questie says "this quest only leads to that one, and goes away once that one is done".
                    crumbFor=read("quest",id,"breadcrumbForQuestId"),crumbs=read("quest",id,"breadcrumbs"),
                    availUntil=read("quest",id,"availableUntilCompleted")}
                all[id]=r
                if next(r.dungeons) then seeds[#seeds+1]=r end
            end
            progress=progress+1
            if progress%100==0 then paint() end
            ns.dataWork.yield()
        end
        -- Chain membership is separate from what a step asks the player to do (a chain can include talk-only steps).
        local isPre={}
        local function link(before,after,required,lead)
            before,after=math.abs(number(before)),math.abs(number(after))
            if before==0 or after==0 or before==after then return end
            if lead then
                if not (isPre[after] and isPre[after][before]) then chainLead[after]=chainLead[after] or {};chainLead[after][before]=true end
            else
                isPre[after]=isPre[after] or {};isPre[after][before]=true
                if chainLead[after] then chainLead[after][before]=nil end
            end
            chainNext[before]=chainNext[before] or {};chainPrev[after]=chainPrev[after] or {}
            if required or chainNext[before][after]==nil then chainNext[before][after]=required==true;chainPrev[after][before]=required==true end
            if all[before] then
                all[before].chainAfter=all[before].chainAfter or {}
                all[before].chainAfter[after]=all[after] and all[after].name or ("Quest "..after)
            end
            if all[after] then
                all[after].chainBefore=all[after].chainBefore or {}
                all[after].chainBefore[before]=all[before] and all[before].name or ("Quest "..before)
            end
        end
        for _,r in pairs(all) do
            -- "any one of" several prerequisites does not prove which one was done; a single or an "all" list does.
            -- (Unrolled, no throwaway tables: this runs once per quest of the whole catalogue.)
            local anyOf,allOf=r.beforeAny,r.beforeAll
            if type(anyOf)=="table" then for _,before in ipairs(anyOf) do link(before,r.id,#anyOf==1) end end
            if type(allOf)=="table" then for _,before in ipairs(allOf) do link(before,r.id,true) end end
            -- Questie's nextQuestInChain: once the next quest is active or done this one is no longer offered. When that
            -- next quest does not list this one as a prerequisite, this one is an optional lead-in (a "go and speak to" quest).
            if number(r.next)>0 then link(r.id,r.next,true,true) end
            if number(r.crumbFor)>0 then link(r.id,r.crumbFor,true,true) end
            if type(r.crumbs)=="table" then for _,crumb in ipairs(r.crumbs) do link(crumb,r.id,true,true) end
            else link(number(r.crumbs),r.id,true,true) end
            if number(r.availUntil)>0 then link(r.id,r.availUntil,true,true) end
            ns.dataWork.yield()
        end
        -- Questie often records no link at all for a "go and speak to X" quest (e.g. "Seeking Caitlin" -> "Lost in the
        -- Thicket Things"). Infer it: a talk-only quest of a dungeon that ends at an NPC who starts a quest of the same
        -- dungeon, with no prerequisite of its own, leads to that quest.
        local function npcs(list) return type(list)=="table" and type(list[1])=="table" and list[1] or {} end
        local function filled(v) return type(v)=="table" and next(v)~=nil end
        local startsAt={}
        for _,seed in ipairs(seeds) do
            seed.starters=npcs(read("quest",seed.id,"startedBy"))
            for _,npc in ipairs(seed.starters) do startsAt[npc]=startsAt[npc] or {};table.insert(startsAt[npc],seed) end
        end
        local function sharesDungeon(a,b) for area in pairs(a.dungeons) do if b.dungeons[area] then return true end end end
        for _,seed in ipairs(seeds) do
            -- A lead-in starts a chain and is handed out by an NPC (a "return to X" step started by an item is a chain's end).
            local talkOnly=#seed.starters>0 and not chainNext[seed.id] and not chainPrev[seed.id]
            for _,key in ipairs({"triggerEnd","extraObjectives","requiredSourceItems"}) do
                if talkOnly and filled(read("quest",seed.id,key)) then talkOnly=false end
            end
            local objectives=talkOnly and read("quest",seed.id,"objectives")
            if type(objectives)=="table" then for _,part in pairs(objectives) do if filled(part) then talkOnly=false end end end
            if talkOnly and (number(read("quest",seed.id,"sourceItemId"))>0 or number(read("quest",seed.id,"specialFlags"))%4>=2) then talkOnly=false end
            if talkOnly then
                local targets,mine={}, {}
                for _,npc in ipairs(seed.starters) do mine[npc]=true end
                for _,npc in ipairs(npcs(read("quest",seed.id,"finishedBy"))) do
                    for _,t in ipairs(not mine[npc] and startsAt[npc] or {}) do
                        if t.id~=seed.id and not filled(t.beforeAny) and not filled(t.beforeAll) and not chainPrev[t.id]
                            and sharesDungeon(seed,t) and (seed.races==t.races or seed.races==0 or t.races==0) then targets[#targets+1]=t end
                    end
                end
                -- One target: finishing it proves this one is pointless. Several: only when all of them are done.
                for _,t in ipairs(targets) do link(seed.id,t.id,#targets==1,true);seed.inferred=seed.inferred or {};seed.inferred[#seed.inferred+1]=t.id end
            end
            ns.dataWork.yield()
        end
        -- Include outdoor preparation quests and explicit follow-ups, with cycle guards per dungeon.
        for _,seed in ipairs(seeds) do
            local direct={};for area in pairs(seed.dungeons) do direct[#direct+1]=area end
            for _,area in ipairs(direct) do
                local seen={}
                local function include(id,role)
                    id=math.abs(number(id))
                    local r=all[id]
                    if not r or seen[id] then return end
                    seen[id]=true
                    r.dungeons[area]=r.dungeons[area] or role
                    local anyOf,allOf=r.beforeAny,r.beforeAll
                    if type(anyOf)=="table" then for _,before in ipairs(anyOf) do include(before,"Preparation") end end
                    if type(allOf)=="table" then for _,before in ipairs(allOf) do include(before,"Preparation") end end
                    -- An optional lead-in ("go and speak to X") belongs to the quest it points to, so it is listed with it.
                    for before in pairs(chainLead[id] or {}) do include(before,"Lead-in") end
                    ns.dataWork.checkpoint()
                end
                include(seed.id,true)
                local nextID=number(seed.next)
                local followed={}
                while nextID>0 and all[nextID] and not followed[nextID] do
                    followed[nextID]=true;include(nextID,"Follow-up");nextID=number(all[nextID].next)
                end
            end
        end
        for id,r in pairs(all) do
            if next(r.dungeons) then
                local names={}
                for area in pairs(r.dungeons) do
                    places[area]=places[area] or {area=area,name=areaName(area),count=0}
                    places[area].count=places[area].count+1;names[#names+1]=places[area].name
                end
                table.sort(names);r.dungeonText=table.concat(names,", ");records[id]=r
            end
            ns.dataWork.yield()
        end
        if not saved and next(records) then ns.dataWork.save(SAVED,key,linkedIDs(all)) end
        ready,loading=true,false
        if filters.dungeon~=0 and not places[filters.dungeon] then filters.dungeon=0 end
        focusCurrentDungeon()
        D.updateControls();D.refresh()
    end,shown,function(ok,err)
        if token~=generation then return end
        if not ok then loading=false;message="Could not read dungeon quests: "..tostring(err);paint() end
    end,FOREGROUND_MS)
    paint();return true
end

local function entry(r)
    return C.findEntry(r.id) or {questID=r.id,title=r.name,level=r.level,catalogue=true}
end
local function pickups(r)
    local out={}
    for _,source in ipairs(Q.plannerStarters(r.id)) do
        local points=Q.nearest(source.spawns or {},1)
        local point=points[1]
        out[#out+1]={source=source,point=point}
    end
    return out
end
local function locations(r)
    if r.locations then return r.locations end
    local list={pickups=pickups(r),turnIns={}}
    local by=Q.get("quest",r.id,"finishedBy")
    for index,kind in ipairs({"npc","object"}) do
        for _,id in ipairs(type(by)=="table" and type(by[index])=="table" and by[index] or {}) do
            list.turnIns[#list.turnIns+1]={source={kind=kind,name=Q.get(kind,id,"name") or "Unknown giver"},point=Q.nearest(Q.spawnList(kind,id),1)[1]}
        end
    end
    r.locations=list
    return list
end
local function pickupText(p)
    local source=p.source
    return (source.startsFrom and ("Item "..(source.startsFrom.name or source.startsFrom.id).." from ") or "")
        ..(source.name or "Unknown giver")..(p.point and (" — "..Q.where(p.point)) or " — location unknown")
end
local function locationSummary(list)
    if #list==0 then return "Unknown location" end
    return pickupText(list[1])..(#list>1 and (" +"..(#list-1).." more") or "")
end

local function chainLabel(r)
    if not r.chainBefore and not r.chainAfter then return "Standalone quest" end
    local role=filters.dungeon~=0 and r.dungeons[filters.dungeon]
    for _,leads in pairs(chainLead) do if leads[r.id] then return "Chain quest: optional lead-in" end end
    if role=="Preparation" then return "Chain quest: prerequisite" end
    if role=="Follow-up" then return "Chain quest: follow-up" end
    if role=="Lead-in" then return "Chain quest: optional lead-in" end
    if role==true then return "Chain quest: dungeon step" end
    return "Chain quest"
end
local function taskLabel(r)
    if r.taskLabel then return r.taskLabel,r.talkOnly end
    local actions={}
    local objectives=Q.get("quest",r.id,"objectives")
    local function has(value) return type(value)=="table" and next(value)~=nil end
    local function add(label) for _,s in ipairs(actions) do if s==label then return end end;actions[#actions+1]=label end
    for index,label in ipairs({"Defeat enemies","Use objects","Collect items","Gain reputation","Complete creature objective","Use quest spell/item"}) do
        if type(objectives)=="table" and has(objectives[index]) then add(label) end
    end
    if has(Q.get("quest",r.id,"triggerEnd")) then add("Explore / reach a location") end
    if has(Q.get("quest",r.id,"extraObjectives")) then add("Complete special objectives") end
    if has(Q.get("quest",r.id,"requiredSourceItems")) then add("Deliver required items") end
    local flags=number(Q.get("quest",r.id,"specialFlags"))
    if math.floor(flags/2)%2==1 then add("Complete event / escort") end
    local by=Q.get("quest",r.id,"startedBy")
    if number(Q.get("quest",r.id,"sourceItemId"))>0 or (type(by)=="table" and has(by[3])) then add("Deliver / use quest item") end
    if #actions==0 then
        local e=C.findEntry(r.id)
        if e and #C.objectives(e)>0 then add("Complete quest objectives") end
    end
    local turnIns=locations(r).turnIns
    if #actions>0 then r.taskLabel=table.concat(actions," + ")
    elseif turnIns[1] and turnIns[1].source.kind=="npc" then
        r.talkOnly=true;r.taskLabel="Talk only — speak to "..turnIns[1].source.name
    elseif turnIns[1] then r.taskLabel="Interact with quest object — "..turnIns[1].source.name
    else r.taskLabel="Task unknown — check quest details" end
    return r.taskLabel,r.talkOnly
end
local function chainLines(r)
    local lines={chainLabel(r)}
    for _,field in ipairs({"chainBefore","chainAfter"}) do
        local list={}
        for id,name in pairs(r[field] or {}) do list[#list+1]={id=id,name=name} end
        table.sort(list,function(a,b)return a.id<b.id end)
        if #list>0 then
            lines[#lines+1]=field=="chainBefore" and "Previous chain quests:" or "Next chain quests:"
            for _,q in ipairs(list) do lines[#lines+1]=q.name.." (quest ID "..q.id..")"..(finished(q.id) and " - done" or inLog(q.id) and " - in your quest log" or "") end
        end
    end
    return lines
end

-- A step counts as done when it is, and also when a later step that needs it is done: the giver then has nothing
-- left to offer, so there is no point travelling there. The list shows such steps ticked green and greyed out.
local GREEN,DIM="|cff0d6e0d","|cff6b4a26"
local NAME,PICK,TURN,REWARD="|cff7a0c0c","|cff0a2a8a","|cff5a1a7a","|cff6b4a00" -- panel: quest name crimson, pickup deep blue, turn-in purple
local GREYED="|cff7d7d7d"
local ROW_PICK,ROW_TURN,ROW_TASK="|cff9fe6ff","|cffe6b3ff","|cffe0e0e0" -- the same roles, bright for the dark list
local function baseXP(id)
    local support=type(LibQuestieDB)=="table" and LibQuestieDB.Support
    local xp=support and U.call(support.Get,"QuestXP")
    if type(xp)~="table" or type(xp.db)~="table" then
        xp=QuestieLoader and U.call(QuestieLoader.ImportModule,QuestieLoader,"QuestXP")
    end
    local row=type(xp)=="table" and type(xp.db)=="table" and xp.db[id]
    local value=type(row)=="table" and row[2]
    if type(value)=="number" and value>=0 and value<math.huge then return value end
end
-- Classic XP falloff for a quest below your level (6+ levels under: 80/60/40/20 %, then 10 %). nil when it is full.
local function xpAtMyLevel(xp,questLevel)
    local level=playerLevel()
    if not xp or not level or questLevel<=0 then return nil end
    local diff=level-questLevel
    if diff<=5 then return nil end
    local share=({[6]=0.8,[7]=0.6,[8]=0.4,[9]=0.2})[diff] or 0.1
    return math.floor(xp*share/5+0.5)*5
end
local function xpText(r)
    local xp=baseXP(r.id)
    if not xp then return nil end
    local mine=xpAtMyLevel(xp,r.level)
    return xp.." (base)"..(mine and (", about "..mine.." at your level") or "")
end
local function reputationLines(r)
    local out={}
    local rep=Q.get("quest",r.id,"reputationReward")
    for _,pair in ipairs(type(rep)=="table" and rep or {}) do
        if type(pair)=="table" and tonumber(pair[1]) and tonumber(pair[2]) then
            local name=U.call(GetFactionInfoByID,pair[1]) or ("Faction "..pair[1])
            out[#out+1]=kw("num",(pair[2]>=0 and "+" or "")..pair[2]).." reputation with "..kw("item",name)
        end
    end
    return out
end
-- Reward lines for the tooltip and the details panel (items need the reward scan; it starts on first hover/click).
local function rewardLines(r)
    local lines={}
    local xp=xpText(r)
    lines[#lines+1]=xp and ("XP: "..xp) or "XP: unknown in installed quest data"
    for _,line in ipairs(reputationLines(r)) do lines[#lines+1]=line end
    if not rewardsReady then lines[#lines+1]="Item rewards: loading…"
    elseif not rewardIndex then lines[#lines+1]="Item rewards: unavailable in installed quest data"
    elseif not rewardIndex[r.id] or #rewardIndex[r.id]==0 then lines[#lines+1]="No item rewards listed in quest data."
    else
        lines[#lines+1]="Item rewards (you may have to choose one):"
        for _,id in ipairs(rewardIndex[r.id]) do
            local name=U.call((C_Item and C_Item.GetItemInfo) or GetItemInfo,id) or Q.get("item",id,"name") or ("Item "..id)
            lines[#lines+1]="• "..name.." ("..id..")"
        end
    end
    return lines
end

local function scanRewards()
    if rewardsReady or rewardsLoading or not ready or not shown() then return end
    rewardsLoading=true;rewardIndex={}
    local token=generation
    ns.dataWork.start(REWARDS_OWNER,function()
        local ids=Q.ids("item")
        if type(ids)~="table" then
            rewardsLoading=false;rewardsReady=true;rewardIndex=nil
            if hovered then showHover(hovered) end
            return
        end
        for _,id in ipairs(ids) do
            local quests=Q.get("item",id,"questRewards")
            local seen={}
            for _,qid in ipairs(type(quests)=="table" and quests or {}) do
                if records[qid] and not seen[qid] then
                    rewardIndex[qid]=rewardIndex[qid] or {}
                    rewardIndex[qid][#rewardIndex[qid]+1]=id;seen[qid]=true
                end
            end
            ns.dataWork.yield()
        end
        for _,items in pairs(rewardIndex) do table.sort(items);ns.dataWork.yield() end
        rewardsLoading=false;rewardsReady=true
        if hovered then showHover(hovered) end
        if selected and records[selected] then window.showQuest(records[selected]) end
    end,shown,function(ok)
        if token~=generation then return end
        if not ok then
            rewardsLoading=false;rewardsReady=true;rewardIndex=nil
            if hovered then showHover(hovered) end
        end
    end)
end

function D.hoverLines(r)
    local xp=baseXP(r.id)
    local lines=chainLines(r)
    local done,implied=finished(r.id)
    if implied then lines[#lines+1]="Not needed: the next step is done or in your quest log"
    elseif done then lines[#lines+1]="Completed"
    elseif inLog(r.id) then lines[#lines+1]="In your quest log" end
    lines[#lines+1]="Task: "..taskLabel(r)
    for _,line in ipairs(rewardLines(r)) do lines[#lines+1]=line end
    local list=locations(r)
    lines[#lines+1]="Pick up:"
    if #list.pickups==0 then lines[#lines+1]="Unknown location" end
    for _,p in ipairs(list.pickups) do lines[#lines+1]=pickupText(p) end
    lines[#lines+1]="Turn in:"
    if #list.turnIns==0 then lines[#lines+1]="Unknown location" end
    for _,p in ipairs(list.turnIns) do lines[#lines+1]=pickupText(p) end
    if xp~=nil then lines[#lines+1]="Base XP is before character-level and bonus adjustments." end
    lines[#lines+1]="Left-click: full quest details. Right-click: quest actions."
    return lines
end
showHover=function(row)
    if not shown() or not row.result or not row.frame:IsShown() then return end
    U.tip(row.frame,row.result.name,D.hoverLines(row.result))
end
function D.menu(id)
    local r=records[id]
    if not r then return end
    local e=entry(r)
    local items=ns.questMenuItems(e)
    table.insert(items,1,{text="Mark quest giver (then press M)",run=function() D.showPickup(id) end})
    table.insert(items,1,{text="Where to pick it up",run=function()
        local list=pickups(r)
        if #list==0 then ns.print(Q.whereText(id) or "Quest pickup location unknown in QuestieDB.") end
        for _,p in ipairs(list) do ns.print(pickupText(p)) end
    end})
    menuEntry,menuQuest=e,id
    ns.openQuestMenu(e,items)
end

-- ===== Details panel: built to be read in a few seconds =====
-- Status badge first, then what to do, where (click = map pin), rewards (hover items for stats), chain, and only then
-- the small print. Plain words, big type for the key facts, small type for everything else.
local INK={0.18,0.105,0.045}
local SOFT={0.38,0.27,0.13}
local QUALITY_INK={[0]="|cff5a5a5a",[1]="|cff2a1a08",[2]="|cff0a6a0a",[3]="|cff0a3f9a",[4]="|cff6a1a9a",[5]="|cff9a4a00"}
local BADGES={ -- text colour on parchment, strip tint, icon
    todo={"|cff6a4600",{0.90,0.66,0.12,0.40},"Interface\\GossipFrame\\AvailableQuestIcon"},
    taken={"|cff6a4600",{0.98,0.86,0.25,0.40},"Interface\\GossipFrame\\ActiveQuestIcon"},
    done={"|cff0d5e0d",{0.30,0.70,0.30,0.35},"Interface\\RaidFrame\\ReadyCheck-Ready"},
    skip={"|cff4a4a4a",{0.50,0.50,0.50,0.35},"Interface\\RaidFrame\\ReadyCheck-Ready"},
    blocked={"|cff8a1010",{0.85,0.25,0.20,0.30},"Interface\\RaidFrame\\ReadyCheck-NotReady"},
}
local function badgeOf(r)
    local _,implied=finished(r.id)
    if completed(r.id) then return "done","Done" end
    if implied then return "skip","Skip it: the next step is done or taken" end
    if inLog(r.id) then return "taken","In your quest log" end
    local level=playerLevel()
    if level and r.required>level then return "blocked","Needs level "..r.required end
    if level and r.max>0 and level>r.max then return "blocked","Only up to level "..r.max end
    local able,why=canTake(r)
    if not able then return "blocked",why=="class" and "Not for your class" or "Not for your faction" end
    return "todo","To pick up"
end
local function roleWord(r)
    local label=chainLabel(r)
    if label=="Standalone quest" then return "single quest" end
    if label=="Chain quest" then return "chain quest" end
    return (string.gsub(label,"^Chain quest: ",""))
end
local function objectiveNames(r)
    local names={}
    local list=locations(r)
    for _,group in ipairs({list.pickups,list.turnIns}) do
        for _,p in ipairs(group) do names[#names+1]={p.source.name,"npc"} end
    end
    local objectives=Q.get("quest",r.id,"objectives")
    for index,kind in ipairs({"npc","object","item"}) do
        local group=type(objectives)=="table" and objectives[index]
        for _,entry in ipairs(type(group)=="table" and group or {}) do
            local id=type(entry)=="table" and entry[1] or entry
            names[#names+1]={Q.get(kind,id,"name"),kind=="item" and "item" or "npc"}
        end
    end
    names[#names+1]={r.dungeonText,"dungeon"}
    table.sort(names,function(a,b) return #(a[1] or "")>#(b[1] or "") end) -- longest first: "Defias Overseer" before "Defias"
    return names
end
local function doText(r)
    local text=Q.get("quest",r.id,"objectivesText")
    if type(text)=="table" then
        local parts={}
        for _,line in ipairs(text) do if type(line)=="string" and line~="" then parts[#parts+1]=line end end
        text=table.concat(parts," ")
    end
    local task,talk=taskLabel(r)
    if type(text)=="string" and text~="" then return text,talk and "Talk only" or task end
    local who=talk and string.match(task,"speak to (.+)$")
    if who then return "Talk to "..who,nil end
    if string.find(task,"^Task unknown") then return "Not clear from the quest data: open the quest log or Questie for steps.",nil end
    return task,nil
end
local function pinnable(pt) return pt and pt.map and not pt.dungeon and pt.x>=0 and pt.x<=100 and pt.y>=0 and pt.y<=100 end
local function pinPlace(p)
    local pt=p and p.point
    if pinnable(pt) then
        C.setWaypoint(pt.map,pt.x/100,pt.y/100)
        ns.print("map pin: "..pickupText(p));U.mapHint(pt.map);return true
    end
    ns.print(p and pickupText(p) or "Location unknown in quest data.")
    if pt and pt.map then U.mapHint(pt.map) end
    return false
end
local function itemInfo(id)
    local get=(C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok,name,link,quality,_,_,_,_,_,_,icon=pcall(get or function() end,id)
    if not ok then name,link,quality,icon=nil,nil,nil,nil end
    icon=icon or U.call((C_Item and C_Item.GetItemIconByID) or GetItemIcon,id)
    return name or Q.get("item",id,"name") or ("Item "..id),link,quality,icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function fs(parent,size,color,width)
    local t=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    E.font(t,size,color[1],color[2],color[3])
    if t.SetShadowColor then t:SetShadowColor(0,0,0,0) end
    t:SetJustifyH("LEFT");if width then t:SetWidth(width) end
    return t
end
local function textHeight(t,size)
    local h=t.GetStringHeight and t:GetStringHeight() or 0
    if not h or h<=0 then h=size+4 end
    return h
end
local function hoverable(b)
    b.hl=S.fill(b,"BACKGROUND",0.55,0.38,0.12,0.20);b.hl:SetAllPoints(b);b.hl:Hide()
    b:SetScript("OnLeave",function(self) self.hl:Hide();U.hideTip();if GameTooltip_HideShoppingTooltips and GameTooltip then pcall(GameTooltip_HideShoppingTooltips,GameTooltip) end end)
    b:RegisterForClicks("LeftButtonUp")
end
local function placeButton(parent,width)
    local b=CreateFrame("Button",nil,parent);b:SetWidth(width);b:SetHeight(40)
    hoverable(b)
    b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetWidth(22);b.icon:SetHeight(22);b.icon:SetPoint("TOPLEFT",b,"TOPLEFT",2,-4)
    b.title=fs(b,14,INK,width-34);b.title:SetPoint("TOPLEFT",b,"TOPLEFT",30,-3);b.title:SetWordWrap(false);bold(b.title,INK)
    b.sub=fs(b,11,SOFT,width-34);b.sub:SetPoint("TOPLEFT",b,"TOPLEFT",30,-22);b.sub:SetWordWrap(false)
    b:SetScript("OnEnter",function(self)
        self.hl:Show()
        U.tip(self,self.title:GetText() or "",{pinnable(self.place and self.place.point) and "Click: put a pin on your world map (open it with M)."
            or "No map pin: inside the dungeon or location unknown."})
    end)
    b:SetScript("OnClick",function(self) if self.place then pinPlace(self.place) end end)
    return b
end
local function itemButton(parent,width)
    local b=CreateFrame("Button",nil,parent);b:SetWidth(width);b:SetHeight(36)
    hoverable(b)
    b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetWidth(30);b.icon:SetHeight(30);b.icon:SetPoint("TOPLEFT",b,"TOPLEFT",2,-3)
    b.name=fs(b,12,INK,width-40);b.name:SetPoint("TOPLEFT",b,"TOPLEFT",37,-3)
    b:SetScript("OnEnter",function(self)
        self.hl:Show()
        if not self.itemID then return end
        if GameTooltip and GameTooltip.SetHyperlink then
            pcall(function()
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetHyperlink("item:"..self.itemID);GameTooltip:Show()
                if GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
            end)
        else U.tip(self,(itemInfo(self.itemID)),{"Shift-click: link it in chat."}) end
    end)
    b:SetScript("OnClick",function(self)
        local _,link=itemInfo(self.itemID)
        if link and HandleModifiedItemClick then pcall(HandleModifiedItemClick,link) end
    end)
    return b
end
local MAX_ITEMS=6
local function buildPanel(frame)
    local P={frame=frame,width=330,texts={}}
    P.title=fs(frame,15,{1,0.82,0},326);P.title:SetPoint("TOPLEFT",frame,"TOPLEFT",14,-10);P.title:SetWordWrap(false);bold(P.title,{1,0.82,0})
    P.strip=S.fill(frame,"ARTWORK",1,1,1,1);P.strip:SetHeight(28)
    P.badgeIcon=frame:CreateTexture(nil,"OVERLAY");P.badgeIcon:SetWidth(20);P.badgeIcon:SetHeight(20)
    P.badge=fs(frame,15,INK,290);P.badge:SetWordWrap(false);bold(P.badge,INK)
    P.meta=fs(frame,12,SOFT,330)
    P.heads={}
    for _,key in ipairs({"do","where","rewards","chain","more"}) do
        P.heads[key]=fs(frame,11,{0.48,0.30,0.05});bold(P.heads[key],{0.48,0.30,0.05})
        P.heads[key]:SetText(({["do"]="WHAT TO DO",where="WHERE (click for a map pin)",rewards="REWARDS (hover an item for stats)",chain="QUEST CHAIN",more="MORE DETAILS"})[key])
    end
    P.doText=fs(frame,14,INK,330)
    P.doKind=fs(frame,11,SOFT,330)
    P.pickup=placeButton(frame,330);P.pickup.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    P.turnIn=placeButton(frame,330);P.turnIn.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
    P.xp=fs(frame,15,INK,330);bold(P.xp,INK)
    P.rep=fs(frame,12,INK,330)
    P.itemNote=fs(frame,12,SOFT,330)
    P.itemMore=fs(frame,11,SOFT,330)
    P.items={}
    for i=1,MAX_ITEMS do P.items[i]=itemButton(frame,163) end
    P.chain=fs(frame,12,INK,330)
    return P
end
-- Lay the panel out top to bottom for quest r (or hide it and show a message when r is nil).
local function renderPanel(P,r,message,setMore,moreScroll)
    local f=P.frame
    local all={P.title,P.strip,P.badgeIcon,P.badge,P.meta,P.doText,P.doKind,P.pickup,P.turnIn,P.xp,P.rep,P.itemNote,P.itemMore,P.chain}
    for _,h in pairs(P.heads) do all[#all+1]=h end
    for _,b in ipairs(P.items) do all[#all+1]=b end
    for _,w in ipairs(all) do w:Hide() end
    local y=44
    local function at(w,x,dy) w:ClearAllPoints();w:SetPoint("TOPLEFT",f,"TOPLEFT",x or 14,-y);w:Show();y=y+(dy or 0) end
    local function head(key) y=y+6;at(P.heads[key],14,16) end
    local function text(t,value,size,gap) t:SetText(value);at(t,14,0);y=y+textHeight(t,size)+(gap or 2) end
    if not r then
        P.title:SetText("Quest details");P.title:Show()
        moreScroll:ClearAllPoints();moreScroll:SetPoint("TOPLEFT",f,"TOPLEFT",16,-y);moreScroll:SetHeight(f:GetHeight()-y-14)
        setMore(message or "");return
    end
    P.title:SetText(r.name);P.title:Show()
    local state,label=badgeOf(r)
    local b=BADGES[state]
    P.strip:SetVertexColor(b[2][1],b[2][2],b[2][3],b[2][4])
    P.strip:ClearAllPoints();P.strip:SetPoint("TOPLEFT",f,"TOPLEFT",8,-y+2);P.strip:SetPoint("TOPRIGHT",f,"TOPRIGHT",-8,-y+2);P.strip:Show()
    local x=16
    if b[3] then P.badgeIcon:SetTexture(b[3]);P.badgeIcon:ClearAllPoints();P.badgeIcon:SetPoint("TOPLEFT",f,"TOPLEFT",x,-y-2);P.badgeIcon:Show();x=x+24 end
    P.badge:SetText(b[1]..label.."|r");P.badge:ClearAllPoints();P.badge:SetPoint("TOPLEFT",f,"TOPLEFT",x,-y-5);P.badge:Show()
    y=y+32
    local req=r.required>1 and (" · needs "..kw("num",r.required.."+")) or ""
    text(P.meta,kw("dungeon",r.dungeonText).." · level "..kw("num",r.level)..req.." · "..roleWord(r),12,2)
    -- what to do
    head("do")
    local what,kind=doText(r)
    text(P.doText,highlight(what,objectiveNames(r)),14,0)
    if kind then text(P.doKind,kind,11,0) end
    -- where (pick up / hand in), each a click-to-pin button
    head("where")
    local list=locations(r)
    for _,pair in ipairs({{P.pickup,list.pickups,"Pick up from "},{P.turnIn,list.turnIns,"Hand in to "}}) do
        local button,places,verb=pair[1],pair[2],pair[3]
        local place=places[1]
        button.place=place
        if place then
            local who,where=placeText(place)
            button.title:SetText(verb..who)
            local pt=place.point
            button.sub:SetText(where..(pinnable(pt) and "" or (pt and pt.dungeon and " · inside the dungeon" or ""))
                ..(#places>1 and (" · +"..(#places-1).." more place"..(#places>2 and "s" or "")) or ""))
        else
            button.title:SetText(verb.."unknown")
            button.sub:SetText(verb=="Pick up from " and (Q.whereText(r.id) or "not in quest data") or "not in quest data")
        end
        at(button,10,42)
    end
    -- rewards
    head("rewards")
    local xp=baseXP(r.id)
    local mine=xp and xpAtMyLevel(xp,r.level)
    text(P.xp,xp and (kw("num",mine or xp).." XP"..(mine and ("  |cff7a6a5a(base "..xp..", less at your level)|r") or "")) or "XP unknown",15,2)
    local reps=reputationLines(r)
    if #reps>0 then text(P.rep,table.concat(reps,"\n"),12,2) end
    if not rewardsReady then text(P.itemNote,"Items: loading…",12,2)
    elseif not rewardIndex then text(P.itemNote,"Items: not in the installed quest data",12,2)
    elseif not rewardIndex[r.id] or #rewardIndex[r.id]==0 then text(P.itemNote,"No item rewards",12,2)
    else
        local ids=rewardIndex[r.id]
        if #ids>1 then text(P.itemNote,"Items (you may pick one):",12,0) end
        for i=1,math.min(#ids,MAX_ITEMS) do
            local button=P.items[i]
            local name,_,quality,icon=itemInfo(ids[i])
            button.itemID=ids[i];button.icon:SetTexture(icon)
            button.name:SetText((QUALITY_INK[quality] or QUALITY_INK[1])..name.."|r")
            button:ClearAllPoints();button:SetPoint("TOPLEFT",f,"TOPLEFT",i%2==1 and 10 or 177,-y);button:Show()
            if i%2==0 or i==math.min(#ids,MAX_ITEMS) then y=y+38 end
        end
        if #ids>MAX_ITEMS then text(P.itemMore,"+"..(#ids-MAX_ITEMS).." more items (see details)",11,2) end
    end
    -- chain: plain before/next lines with their state
    local lines={}
    for _,field in ipairs({"chainBefore","chainAfter"}) do
        local ids={}
        for id in pairs(r[field] or {}) do ids[#ids+1]=id end
        table.sort(ids)
        for i,id in ipairs(ids) do
            if i>2 then lines[#lines+1]="   +"..(#ids-2).." more";break end
            local name=r[field][id]
            local state=finished(id) and (" "..kw("done","(done)")) or inLog(id) and (" "..kw("log","(in your log)")) or ""
            lines[#lines+1]=(field=="chainBefore" and "Before: " or "Next: ")..kw("quest",name)..state
        end
    end
    if #lines>0 then head("chain");text(P.chain,table.concat(lines,"\n"),12,2) end
    head("more")
    moreScroll:ClearAllPoints();moreScroll:SetPoint("TOPLEFT",f,"TOPLEFT",16,-y)
    moreScroll:SetHeight(math.max(60,f:GetHeight()-y-12))
    setMore(D.detail(r))
end

function D.showPickup(id)
    local r=records[id]
    if not r then return false end
    local list=pickups(r)
    for _,p in ipairs(list) do if pinnable(p.point) then return pinPlace(p) end end
    if list[1] then pinPlace(list[1]) else ns.print(Q.whereText(id) or "Quest pickup location unknown in QuestieDB.") end
    return false
end
-- The small print under MORE DETAILS: everything a tired reader does not need first.
function D.detail(r)
    local lines={}
    local factionNames={}
    for _,faction in ipairs({"Alliance","Horde"}) do
        local mask=enums().factionRaceMasks and enums().factionRaceMasks[faction]
        if r.races==0 or (mask and ns.rewards.overlaps(r.races,mask)) then factionNames[#factionNames+1]=faction end
    end
    lines[#lines+1]="Faction: "..(#factionNames>0 and table.concat(factionNames," / ") or "Unknown")
    local classNames={}
    if r.classes==0 then classNames[1]="All classes"
    else
        for _,choice in ipairs(classChoices()) do
            local mask=enums().classKeys and enums().classKeys[choice.value]
            if mask and ns.rewards.overlaps(r.classes,mask) then classNames[#classNames+1]=choice.label end
        end
    end
    lines[#lines+1]="Class: "..(#classNames>0 and table.concat(classNames,", ") or "Unknown")
    lines[#lines+1]="Level: "..(r.required>1 and ("needs "..r.required..(r.max>0 and ("–"..r.max) or "+")) or (r.max>0 and ("up to "..r.max) or "no level requirement"))
    lines[#lines+1]="Quest ID: "..r.id
    local before,any=Q.before(r.id)
    if #before>0 then lines[#lines+1]="Needs first ("..(any and "any one" or "all").."): "..table.concat(before,", ") end
    local list=locations(r)
    for index,p in ipairs(list.pickups) do if index>1 then lines[#lines+1]="Also picked up from: "..pickupText(p) end end
    for index,p in ipairs(list.turnIns) do if index>1 then lines[#lines+1]="Also handed in to: "..pickupText(p) end end
    if rewardsReady and rewardIndex and rewardIndex[r.id] and #rewardIndex[r.id]>MAX_ITEMS then
        for index,id in ipairs(rewardIndex[r.id]) do if index>MAX_ITEMS then lines[#lines+1]="Item: "..(itemInfo(id)) end end
    end
    local how=Q.howText(r.id,r.name)
    if how then lines[#lines+1]=how end
    -- Raw Questie link fields, so a wrong chain can be diagnosed from a screenshot: only with debug logging on.
    local raw={}
    for _,key in ipairs({"preQuestSingle","preQuestGroup","nextQuestInChain","breadcrumbForQuestId","breadcrumbs","availableUntilCompleted","exclusiveTo","parentQuest"}) do
        local v=Q.get("quest",r.id,key)
        if type(v)=="table" then local ids={};for _,x in ipairs(v) do ids[#ids+1]=tostring(x) end;v=#ids>0 and table.concat(ids,",") or nil end
        if v~=nil and v~=0 and v~="" then raw[#raw+1]=key.."="..tostring(v) end
    end
    if r.inferred then lines[#lines+1]="Chain step guessed (not linked in the quest data): you speak to the NPC who offers quest ID "..table.concat(r.inferred,", ") end
    if ns.logging() then lines[#lines+1]="Debug, quest data chain fields: "..(#raw>0 and table.concat(raw,"  ") or "none") end
    lines[#lines+1]="XP is the base value; it drops for quests 6+ levels below you. Filters do not check reputation, professions or events."
    for index,line in ipairs(lines) do
        local label,value=string.match(line,"^([^:]+:)%s(.*)$")
        if label and #label<24 then lines[index]=DIM..label.."|r "..highlight(value,{{r.dungeonText,"dungeon"}}) else lines[index]=DIM..line.."|r" end
    end
    return table.concat(lines,"\n")
end
function D.go(delta)
    local wanted=math.max(1,math.min(#pageStarts,page+delta))
    if wanted==page then return false end
    page=wanted;ns.closeQuestMenu();paint();return true
end
-- keepMenu (quest-log events): leave an open right-click menu alone unless its quest left the results.
function D.refresh(keepMenu)
    if not shown() then return end
    local open=keepMenu and menuEntry and ns.questMenuEntry()==menuEntry and menuQuest
    if not keepMenu then ns.closeQuestMenu();redraw=true end
    if ready and scope and not covers(scope,filters) then D.scan();return end
    D.search()
    if open then
        local kept=false
        for _,r in ipairs(results) do if r.id==open then kept=true;break end end
        -- The menu's actions hold menuEntry. On classic they act on its quest-log index, which moves when quests
        -- above it are added or removed: refresh it in place, and close if the quest joined or left the log.
        local live=C.findEntry(open)
        if kept and (live==nil)~=(menuEntry.catalogue==true) then kept=false end
        if not kept then ns.closeQuestMenu()
        elseif live then menuEntry.index,menuEntry.complete,menuEntry.title=live.index,live.complete,live.title end
    end
    paint()
end
function D.updateControls()
    if not window then return end
    for _,control in ipairs(window.controls) do control.refresh() end
    if window.route then
        local on=ready and filters.dungeon~=0
        window.route.disabled=not on;window.route:SetAlpha(on and 1 or 0.4)
        if on and window.route.Enable then window.route:Enable() elseif not on and window.route.Disable then window.route:Disable() end
    end
    window.levelMode:SetLabel("Quest levels: "..(filters.allLevels and "all" or ("for level "..filters.level)))
end
paint=function()
    if not window then return end
    hovered=nil;U.hideTip()
    page=math.max(1,math.min(page,#pageStarts))
    local first=pageStarts[page] or 1
    local last=math.min(#results,(pageStarts[page+1] or #results+1)-1)
    window.status:SetText(window.levelError or filterError or (loading and ("Reading dungeon quests: "..progress.."/"..total.." (pauses in combat)"))
        or (not ready and message) or (#results==0 and "No matching quests; broaden your filters or refresh Questie data.")
        or first.."–"..last.." of "..#results.." quests • !: to pick up • ?: in your log • green tick: done / not needed • right-click: actions")
    E.pageButtons(window.prev,window.next,#pageStarts,page,1)
    for i,row in ipairs(window.rows) do
        local r=first+i-1<=last and results[first+i-1] or nil;row.result=r
        if r then
            local done,implied=finished(r.id)
            local taken=not done and inLog(r.id)
            local depth=math.min(depthOf[r.id] or 0,4);local indent=depth*22
            row.frame:ClearAllPoints();row.frame:SetPoint("TOPLEFT",window.list,"TOPLEFT",indent,-(i-1)*106)
            row.frame:SetWidth(650-indent)
            for _,fs in ipairs({row.item,row.from}) do fs:SetWidth(650-indent-60) end
            for _,fs in ipairs({row.task,row.pickup,row.turnIn}) do fs:SetWidth(590-indent) end
            local req=r.required>1 and (" · req "..r.required.."+") or ""
            local subtitle=chainLabel(r).." · "..r.dungeonText..(completed(r.id) and " · Completed" or implied and " · Not needed (next step done or taken)"
                or taken and " · In your quest log" or "")
            E.paintRow(row,nil,r.name.." · level "..r.level..req,subtitle)
            if done then row.from:SetText(GREYED..subtitle.."|r") end -- grey means done; open quests keep the tan line
            -- a quest you cannot take yet (level too low, other faction) is not "still to take": no "!", red requirement
            local able=canTake(r)
            if not able and r.required>(playerLevel() or 0) then req=" · |cffff6060req "..r.required.."+|r" end
            row.item:SetText((depth>0 and (S.GREY.."» |r") or "")..(done and (GREYED..r.name.."|r") or (S.GOLD..r.name.."|r"))
                ..S.GREY.." · level |r"..(done and GREYED or KW_ROW.num)..r.level.."|r"..S.GREY..req.."|r"
                ..(baseXP(r.id) and ((done and GREYED or "|cffb8a0ff").." · "..(xpAtMyLevel(baseXP(r.id),r.level) or baseXP(r.id)).." XP|r") or ""))
            local task,talk=taskLabel(r)
            local list=locations(r)
            if done then
                row.task:SetText(GREYED.."Task: "..task.."|r")
                row.pickup:SetText(GREYED.."Pickup: "..locationSummary(list.pickups).."|r")
                row.turnIn:SetText(GREYED.."Turn-in: "..locationSummary(list.turnIns).."|r")
            else
                -- labels keep their role colour; the NPC (white) and the place (light orange) stand out inside the line
                local names={}
                for _,group in ipairs({list.pickups,list.turnIns}) do for _,pl in ipairs(group) do names[#names+1]={pl.source.name,"npc"} end end
                row.task:SetText((talk and "|cff80e0ff" or ROW_TASK).."Task:|r "..highlight(task,names,KW_ROW))
                for _,pair in ipairs({{row.pickup,list.pickups,ROW_PICK,"Pickup:"},{row.turnIn,list.turnIns,ROW_TURN,"Turn-in:"}}) do
                    local places=pair[2]
                    local who,where=placeText(places[1],KW_ROW)
                    pair[1]:SetText(pair[3]..pair[4].."|r "..(places[1] and (who.." "..S.GREY.."—|r "..where) or "Unknown location")
                        ..(#places>1 and (S.GREY.." +"..(#places-1).." more|r") or ""))
                end
            end
            -- done (or made pointless by a later done step): green tick and grey text, so you do not travel for it
            -- the game's own NPC marks: a yellow "?" when it is in your quest log, a yellow "!" when you can still pick it
            -- up (gold stays the selection colour); a quest you cannot take yet keeps the plain note icon
            local toTake=not done and not taken and able
            local flat=done or taken or toTake
            row.icon:SetTexture(done and "Interface\\RaidFrame\\ReadyCheck-Ready" or taken and "Interface\\GossipFrame\\ActiveQuestIcon"
                or toTake and "Interface\\GossipFrame\\AvailableQuestIcon" or "Interface\\Icons\\INV_Misc_Note_01")
            row.icon:SetTexCoord(flat and 0 or 0.06,flat and 1 or 0.94,flat and 0 or 0.06,flat and 1 or 0.94)
            row.rarity:Hide();row.frame:Show()
        else row.frame:Hide() end
    end
    local focused=E.focusRows(window.rows,selected,function(r) return r.id end)
    redraw=false
    if not focused then
        selected=nil;window.setDetails(loading and "Loading quests…" or "Select a dungeon and quest to see pickups, objectives and prerequisites.")
    end
end
local function build()
    if window then return true end
    local f=E.page(OWNER)
    if not f then return false end
    window={frame=f,rows={},controls={}}
    local function choice(label,x,width,choices,key)
        local b=E.dropdown(f,label,x,8,width,choices,function() return filters[key] end,function(value)
            if key=="dungeon" then focusTarget=nil end
            filters[key]=value;page=1;D.updateControls();D.refresh()
        end)
        window.controls[#window.controls+1]=b;return b
    end
    window.dungeon=choice("Dungeon",0,300,dungeonChoices,"dungeon")
    window.faction=choice("Faction",310,165,{"All factions","Alliance","Horde"},"faction")
    window.class=choice("Class",485,165,classChoices,"class")
    window.level=E.box(f,"Character level",0,43,100,filters.level,4)
    E.liveBox(window.level,OWNER,function(text)
        local n=tonumber(text)
        if n and n>=1 and n<=1000 and n%1==0 then
            filters.level=n;filters.allLevels=false;window.levelError=nil;page=1;D.updateControls();D.refresh()
        else window.levelError="Character level must be a whole number from 1 to 1000.";paint() end
    end)
    window.level:SetScript("OnEscapePressed",function(self)
        self:SetText(tostring(filters.level));self.cancel();window.levelError=nil;self:ClearFocus();D.refresh()
    end)
    window.levelMode=E.button(f,"Quest levels: all",180,function() filters.allLevels=not filters.allLevels;page=1;D.updateControls();D.refresh() end)
    window.levelMode:SetPoint("TOPLEFT",f,"TOPLEFT",110,-60)
    local function checkbox(label,x,y,width,key)
        local b=CreateFrame("Button",nil,f)
        b:SetPoint("TOPLEFT",f,"TOPLEFT",x,-y);b:SetWidth(width);b:SetHeight(24)
        b.box,b.tick=S.checkBox(b);b.box:SetPoint("LEFT",b,"LEFT",0,0)
        b.text=E.text(b,label,28,6,width-30)
        b.refresh=function() if filters[key] then b.tick:Show() else b.tick:Hide() end end
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick",function() filters[key]=not filters[key];page=1;D.updateControls();D.refresh() end)
        window.controls[#window.controls+1]=b
        return b
    end
    window.completed=checkbox("Hide completed quests",300,60,185,"hideCompleted")
    window.inLog=checkbox("Hide quests in my log",310,108,160,"hideLog")
    window.mine=E.button(f,"My character",160,function()
        local dungeon=filters.dungeon;filters=defaults(true);filters.dungeon=dungeon
        window.level:SetText(tostring(filters.level));window.level.cancel();window.search:SetText("");window.search.cancel()
        window.levelError=nil;page=1;D.updateControls();D.refresh()
    end)
    window.mine:SetPoint("TOPLEFT",f,"TOPLEFT",490,-60)
    window.search,window.clearSearch=E.searchBox(f,"Search dungeon, quest or ID",0,90,300,OWNER,function(text) filters.text=text;page=1;D.refresh() end)
    window.reset=E.button(f,"All quests",170,function()
        local dungeon=filters.dungeon;filters=defaults();filters.dungeon=dungeon
        window.level:SetText(tostring(filters.level));window.level.cancel();window.search:SetText("");window.search.cancel()
        window.levelError=nil;page=1;D.updateControls();D.refresh()
    end)
    window.reset:SetPoint("TOPLEFT",f,"TOPLEFT",480,-108)
    window.status=E.text(f,"",0,143,650)
    window.list=CreateFrame("Frame",nil,f);window.list:SetPoint("TOPLEFT",f,"TOPLEFT",0,-170);window.list:SetWidth(650);window.list:SetHeight(530)
    E.wheel(window.list,D.go)
    window.detailFrame,window.detailsText,window.setMore,window.moreScroll=E.details(f,674,358,"",690)
    window.detailFrame:SetHeight(690)
    window.detailFrame.journalSurface.grain:Hide() -- plain parchment yellow, no picture behind the text
    if window.detailsText.SetFont then E.font(window.detailsText,11,0.30,0.21,0.10) end
    window.panel=buildPanel(window.detailFrame)
    window.pickup=window.panel.pickup -- click: map pin at the pickup
    window.showQuest=function(r) renderPanel(window.panel,r,nil,window.setMore,window.moreScroll) end
    window.setDetails=function(message) renderPanel(window.panel,nil,message,window.setMore,window.moreScroll) end
    for i=1,PAGE do
        local row=E.row(window.list,0,(i-1)*106,650,i);window.rows[i]=row
        row.frame:SetHeight(102);row.edge:SetHeight(102)
        row.task=E.text(row.frame,"",52,44,590);row.task:SetWordWrap(false)
        row.pickup=E.text(row.frame,"",52,62,590);row.pickup:SetWordWrap(false)
        row.turnIn=E.text(row.frame,"",52,80,590);row.turnIn:SetWordWrap(false)
        row.choose=function(auto)
            local r=row.result;if not r then return end
            if auto~=true then E.dismissMenu();ns.closeQuestMenu() end
            E.select(window.rows,row)
            if selected~=r.id or auto~=true or redraw then selected=r.id;window.showQuest(r) end
            -- item rewards need one pass over the item catalogue: only when the player asks (click), never on open
            if auto~=true then scanRewards() end
        end
        row.frame:RegisterForClicks("LeftButtonUp","RightButtonUp")
        row.frame:SetScript("OnClick",function(_,button) row.choose();if button=="RightButton" and row.result then D.menu(row.result.id) end end)
        row.frame:SetScript("OnEnter",function()
            if row.result then hovered=row;showHover(row);scanRewards() end
        end)
        row.frame:SetScript("OnLeave",function() if hovered==row then hovered=nil end;U.hideTip() end);E.wheel(row.frame,D.go)
    end
    window.prev=E.button(f,"Previous",100,function() D.go(-1) end);window.prev:SetPoint("TOPLEFT",f,"TOPLEFT",0,-705)
    window.next=E.button(f,"Next",100,function() D.go(1) end);window.next:SetPoint("TOPLEFT",f,"TOPLEFT",110,-705)
    window.reload=E.button(f,"Refresh data",120,function() D.scan(true) end);window.reload:SetPoint("TOPLEFT",f,"TOPLEFT",530,-705) -- Refresh reads the whole catalogue again
    window.route=E.button(f,"Plan route to get them all",240,function() D.planRoute() end,
        "The shortest way to pick up every quest of this dungeon you can take now, with flights, boats and your hearthstone.")
    window.route:SetPoint("TOPLEFT",f,"TOPLEFT",230,-705)
    E.navigation(window.search,window.rows,D.go)
    -- Hiding (close, Esc, other tab) pauses both scans so reopening continues them; the read data is kept.
    f.suspend=function()
        ns.dataWork.pause(OWNER);ns.dataWork.pause(REWARDS_OWNER);ns.closeQuestMenu()
        hovered=nil;U.hideTip();focusTarget=nil
    end
    f:SetScript("OnHide",f.suspend)
    return true
end

-- ===== "Get them all": route to pick up every open quest of the chosen dungeon (logic in DungeonRoute.lua) =====
local ROUTE_OWNER="dungeonRoute"
local routeWindow
local ROUTE_ICONS={Walk="Interface\\Icons\\Ability_Rogue_Sprint",Fly="Interface\\Icons\\Ability_Mount_Gryphon_01",
    Boat="Interface\\Icons\\INV_Misc_Anchor",Zeppelin="Interface\\Icons\\INV_Misc_Anchor",Tram="Interface\\Icons\\INV_Misc_Gear_01",
    Hearth="Interface\\Icons\\INV_Misc_Rune_01",["Pick up"]="Interface\\GossipFrame\\AvailableQuestIcon",
    ["Hand in"]="Interface\\GossipFrame\\ActiveQuestIcon",Enter="Interface\\Icons\\Spell_Arcane_PortalStormwind"}
local function minutes(seconds)
    seconds=math.max(0,math.floor((seconds or 0)+0.5))
    if seconds<60 then return seconds.." s" end
    return math.floor(seconds/60+0.5).." min"
end
-- Which quests to route for the dungeon: open ones you can take now, plus talk-only lead-ins that unlock them.
function D.routeTargets(area)
    local targets,doFirst,later={}, {}, 0
    local isLead={}
    for after,leads in pairs(chainLead) do for before in pairs(leads) do isLead[before]=isLead[before] or {};isLead[before][#isLead[before]+1]=after end end
    local leadTarget={}
    for id,r in pairs(records) do
        if r.dungeons[area] and not finished(id) and not inLog(id) and isLead[id] and canTake(r) then
            local _,talk=taskLabel(r)
            if talk then
                local list=locations(r)
                leadTarget[id]={id=id,name=r.name,kind="leadin",pickup=list.pickups[1],turnIn=list.turnIns[1],unlocks=isLead[id]}
            end
        end
    end
    for id,r in pairs(records) do
        if r.dungeons[area] and not finished(id) and not inLog(id) and not leadTarget[id] then
            if not canTake(r) then later=later+1
            else
                local missing
                for before,required in pairs(chainPrev[id] or {}) do
                    local lead=chainLead[id] and chainLead[id][before]
                    if not lead and not finished(before) and not inLog(before) and not leadTarget[before] then
                        -- "any one of": fine when another of the alternatives is done
                        local other=false
                        if not required then for alt in pairs(chainPrev[id]) do if alt~=before and finished(alt) then other=true end end end
                        if not other then missing=records[before] and records[before].name or ("quest "..before) end
                    end
                end
                if missing then doFirst[#doFirst+1]={name=r.name,needs=missing}
                else targets[#targets+1]={id=id,name=r.name,kind="pickup",pickup=locations(r).pickups[1]} end
            end
        end
    end
    for _,t in pairs(leadTarget) do targets[#targets+1]=t end
    table.sort(targets,function(a,b) return a.id<b.id end)
    table.sort(doFirst,function(a,b) return a.name<b.name end)
    return targets,doFirst,later
end
-- The dungeon's entrance: QuestieDB's own list first (it knows Forever dungeons such as the Excavation Site),
-- then the static TravelData pins.
local function entranceOf(area)
    local lib=type(LibQuestieDB)=="table" and LibQuestieDB.Support
    local zone=lib and U.call(lib.Get,"ZoneDB")
    local list=type(zone)=="table" and type(zone.private)=="table" and zone.private.dungeons
    if type(list)=="table" then
        local entry=list[area]
        if not entry then
            for _,e in pairs(list) do
                for _,alt in ipairs(type(e)=="table" and type(e[2])=="table" and e[2] or {}) do if alt==area then entry=e end end
                if entry then break end
            end
        end
        local spot=type(entry)=="table" and type(entry[4])=="table" and entry[4][1]
        local map=type(spot)=="table" and Q.uiMapOf(spot[1])
        if map and tonumber(spot[2]) and tonumber(spot[3]) then
            return {label=(entry[1] or (places[area] and places[area].name) or "Dungeon").." entrance",point={map=map,x=spot[2],y=spot[3]}}
        end
    end
    local name=places[area] and places[area].name
    for _,d in ipairs((ns.travelData or {}).dungeons or {}) do
        local hit=d.name==name
        for _,inside in ipairs(d.inside or {}) do if inside[1]==name then hit=true end end
        if hit then return {label=d.name.." entrance",point={map=d.map,x=d.x,y=d.y}} end
    end
end
local function stepText(step)
    if (step.kind=="Pick up" or step.kind=="Hand in") and step.quests then
        return (step.kind=="Pick up" and "Pick up " or "Hand in ")..kw("num",#step.quests,KW_ROUTE).." quests "
            ..(step.kind=="Pick up" and "from " or "to ")..kw("npc",step.npc,KW_ROUTE)
    elseif step.kind=="Pick up" or step.kind=="Hand in" then
        local verb=step.kind=="Pick up" and (step.leadin and "Take the lead-in " or "Pick up ") or "Hand in "
        return verb..kw("quest",step.quest,KW_ROUTE)..(step.npc and (" — "..kw("npc",step.npc,KW_ROUTE)) or "")
    elseif step.kind=="Hearth" then return "Use your "..kw("item","Hearthstone",KW_ROUTE).." to "..kw("place",step.to,KW_ROUTE)
    elseif step.kind=="Fly" then return "Fly to "..kw("place",step.to,KW_ROUTE)
    elseif step.kind=="Enter" then return "You are there: enter the dungeon"
    elseif step.kind=="Walk" then return (ROUTE_RIDE and "Ride" or "Walk").." to "..kw(step.npc and "npc" or "place",step.to,KW_ROUTE)..(step.zone and (S.GREY.." ("..step.zone..")|r") or "")
    end
    return "Take the "..string.lower(step.kind).." to "..kw("place",step.to,KW_ROUTE)
end
local ROUTE_ROWS=40
local function buildRoute()
    if routeWindow then return routeWindow end
    local f=S.window("QuestSharingDungeonRoute",460,560,"Get them all — route","dialog")
    if not f then return nil end
    f:SetPoint("CENTER",UIParent,"CENTER",120,0);f:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames,"QuestSharingDungeonRoute") end
    S.closeButton(f,function() f:Hide() end)
    f.summary=U.text(f,"",20,30,420);E.font(f.summary,13,1,0.82,0);bold(f.summary,{1,0.82,0})
    f.notes=U.text(f,"",20,50,420);E.font(f.notes,11,0.85,0.78,0.62)
    local list=CreateFrame("ScrollFrame",nil,f);list:SetPoint("TOPLEFT",f,"TOPLEFT",16,-92);list:SetWidth(428);list:SetHeight(400)
    local content=CreateFrame("Frame",nil,list);content:SetWidth(428);content:SetHeight(400);list:SetScrollChild(content)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel",function(self,delta)
        self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*40)))
    end)
    f.list,f.content,f.rows=list,content,{}
    for i=1,ROUTE_ROWS do
        local b=CreateFrame("Button",nil,content);b:SetWidth(424);b:SetHeight(26)
        b:SetPoint("TOPLEFT",content,"TOPLEFT",0,-(i-1)*27)
        b.hl=S.fill(b,"BACKGROUND",1,0.82,0,0.10);b.hl:SetAllPoints(b);b.hl:Hide()
        b.num=U.text(b,"",0,6,26);E.font(b.num,12,0.62,0.55,0.42);b.num:SetJustifyH("RIGHT")
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetWidth(20);b.icon:SetHeight(20);b.icon:SetPoint("TOPLEFT",b,"TOPLEFT",32,-3)
        b.text=U.text(b,"",58,3,310);E.font(b.text,12,0.93,0.88,0.75);b.text:SetWordWrap(false)
        b.time=U.text(b,"",370,6,52);E.font(b.time,11,0.62,0.55,0.42);b.time:SetJustifyH("RIGHT")
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnEnter",function(self)
            self.hl:Show()
            local st=self.step
            if not st then return end
            local lines={}
            for _,q in ipairs(st.quests or {}) do lines[#lines+1]="• "..q end
            if st.seconds and st.seconds>=1 then lines[#lines+1]="About "..minutes(st.seconds) end
            lines[#lines+1]="Click: put a pin on your world map (open it with M)."
            U.tip(self,"Step "..self.index,lines)
        end)
        b:SetScript("OnLeave",function(self) self.hl:Hide();U.hideTip() end)
        b:SetScript("OnClick",function(self)
            local st=self.step
            if st and st.point then pinPlace({source={name=st.npc or st.to or st.quest},point=st.point}) end
        end)
        b:Hide();f.rows[i]=b
    end
    f.assume=CreateFrame("Button",nil,f);f.assume:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",18,22);f.assume:SetWidth(230);f.assume:SetHeight(24)
    f.assume.box,f.assume.tick=S.checkBox(f.assume);f.assume.box:SetPoint("LEFT",f.assume,"LEFT",0,0)
    f.assume.text=U.text(f.assume,"Assume I know all flight paths",28,6,200);E.font(f.assume.text,12,0.93,0.88,0.75)
    f.assume:RegisterForClicks("LeftButtonUp")
    f.assume:SetScript("OnClick",function() ns.setSetting("routeAllFlights",not ns.db.routeAllFlights);D.planRoute() end)
    f.refresh=E.button(f,"Refresh",90,function() D.planRoute() end);f.refresh:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-20,20)
    routeWindow=f
    return f
end
local function showRoute(f,result,area,doFirst,later)
    local name=places[area] and places[area].name or "this dungeon"
    if ns.db.routeAllFlights then f.assume.tick:Show() else f.assume.tick:Hide() end
    if not result then
        f.summary:SetText("Planning the route…");f.notes:SetText("");for _,b in ipairs(f.rows) do b:Hide() end;return
    end
    if result.noStart or result.nothing then
        f.summary:SetText(result.noStart and "Can't plan from here" or (name..": nothing left to pick up"))
        local lines={result.noStart and "Your position is unknown, for example inside a dungeon. Step outside and press Refresh."
            or "Every quest you can take here is done or already in your quest log."}
        if #doFirst>0 then lines[#lines+1]="Do these first: "..doFirst[1].name.." (needs "..doFirst[1].needs..")"..(#doFirst>1 and (" +"..(#doFirst-1).." more") or "") end
        f.notes:SetText(table.concat(lines,"\n"))
        for _,b in ipairs(f.rows) do b:Hide() end
        return
    end
    local lead=0
    for _,st in ipairs(result.steps) do if st.kind=="Pick up" and st.leadin then lead=lead+1 end end
    f.summary:SetText(name..": "..kw("num",result.quests,KW_ROUTE).." quest"..(result.quests==1 and "" or "s").." · about "
        ..kw("num",minutes(result.totalSeconds),KW_ROUTE)..(result.hearthUsed and " · uses your hearthstone" or ""))
    local notes={}
    if #doFirst>0 then
        local list={}
        for i,q in ipairs(doFirst) do if i<=4 then list[#list+1]=q.name.." (needs "..q.needs..")" end end
        notes[#notes+1]="Do these first: "..table.concat(list,", ")..(#doFirst>4 and (" +"..(#doFirst-4).." more") or "")
    end
    if #result.unknown>0 then notes[#notes+1]="Not on the map (inside the dungeon or unknown): "..table.concat(result.unknown,", ") end
    if later>0 then notes[#notes+1]=later.." more quest"..(later==1 and "" or "s").." need a higher level, another class or the other faction." end
    for _,n in ipairs(result.notes) do notes[#notes+1]=n end
    notes[#notes+1]="Times are estimates. Click a step for a map pin."
    f.notes:SetText(table.concat(notes,"\n"))
    local y=56+math.max(0,(f.notes.GetStringHeight and f.notes:GetStringHeight() or 14))
    f.list:ClearAllPoints();f.list:SetPoint("TOPLEFT",f,"TOPLEFT",16,-y);f.list:SetHeight(math.max(120,560-y-60))
    for i,b in ipairs(f.rows) do
        local st=result.steps[i]
        b.step,b.index=st,i
        if st then
            b.num:SetText(i..".");b.icon:SetTexture(ROUTE_ICONS[st.kind] or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.text:SetText(stepText(st));b.time:SetText(st.seconds and st.seconds>=1 and minutes(st.seconds) or "")
            b:Show()
        else b:Hide() end
    end
    f.content:SetHeight(math.max(400,#result.steps*27))
    if #result.steps>ROUTE_ROWS then f.notes:SetText(f.notes:GetText().."\nShowing the first "..ROUTE_ROWS.." steps.") end
end
function D.planRoute()
    local area=filters and filters.dungeon or 0
    if not ready or area==0 then ns.print("choose a dungeon first, then plan the route.");return false end
    local f=buildRoute()
    if not f then return false end
    f:Show();showRoute(f,nil,area)
    local targets,doFirst,later=D.routeTargets(area)
    local map,x,y=C.playerPos()
    local options={start=map and {map=map,x=x*100,y=y*100} or nil,assumeAllFlights=ns.db.routeAllFlights and true or false,finish=entranceOf(area),
        checkpoint=ns.dataWork.checkpoint}
    ROUTE_RIDE=(tonumber(U.call(UnitLevel,"player")) or 0)>=40
    ns.dataWork.start(ROUTE_OWNER,function()
        local result=ns.dungeonRoute.plan(targets,options)
        if f:IsShown() then showRoute(f,result,area,doFirst,later) end
        D._lastRoute=result
    end,function() return f:IsShown() end,function(ok,err)
        if not ok then f.summary:SetText("Could not plan the route: "..tostring(err)) end
    end,FOREGROUND_MS)
    return true
end
function D._routeWindow() return routeWindow end
local function stop()
    generation=generation+1;ns.dataWork.cancel(OWNER)
    if loading then loading,ready=false,false end
end
function D.open(text)
    if not ns.db.enabled then ns.print("switch Quest Sharing on first (/qs on)");return end
    filters=filters or defaults(true)
    if not build() then return end
    E.show(OWNER)
    if text and text~="" then filters.text=text;window.search:SetText(text);window.search.cancel() end
    focusTarget=currentDungeon()
    if ready then focusCurrentDungeon() end
    D.updateControls()
    for _,box in ipairs({window.level,window.search}) do if box.dirty then box.flush() end end
    if ready then ns.dataWork.resume(REWARDS_OWNER);D.refresh()
    elseif loading and ns.dataWork.busy(OWNER) then ns.dataWork.resume(OWNER);paint()
    else D.scan() end
end
-- Settings "Purge": free the kept catalogue; an open window reads it again at once, a closed one on its next open.
function D.purge()
    ns.dataWork.forget(SAVED);release()
    if window and shown() then D.scan();paint() end
end
ns.dataWork.onPurge("Dungeon quests",D.purge)
-- Master disable: discard the scan entirely.
function D.close() if window then E.close(OWNER);stop();release() end end
function D._window() return window end
function D._results() return results end
function D._panelText()
    local P=window and window.panel
    if not P then return "" end
    local out={}
    local function add(t) if t and t:IsShown() and t:GetText() then out[#out+1]=t:GetText() end end
    add(P.title);add(P.badge);add(P.meta);add(P.heads["do"]);add(P.doText);add(P.doKind);add(P.heads.where)
    for _,b in ipairs({P.pickup,P.turnIn}) do if b:IsShown() then add(b.title);add(b.sub) end end
    add(P.heads.rewards);add(P.xp);add(P.rep);add(P.itemNote)
    for _,b in ipairs(P.items) do if b:IsShown() then add(b.name) end end
    add(P.itemMore)
    add(P.heads.chain);add(P.chain);add(P.heads.more)
    out[#out+1]=window.detailsText.text or ""
    return table.concat(out,"\n")
end
function D._state() return ready,loading,progress end
function D._release() release() end -- tests: free memory only (as a new session would), the saved list stays
ns.on("QUEST_LOG_UPDATE",function()
    if not shown() or not ready or refreshPending then return end
    refreshPending=true
    ns.after(0.2,function()
        refreshPending=false
        if shown() and ready then
            for _,r in pairs(records) do r.taskLabel,r.talkOnly=nil,nil end
            selected=nil;D.refresh(true)
        end
    end)
end)
ns.on("GET_ITEM_INFO_RECEIVED",function()
    if hovered and shown() then showHover(hovered) end
    if selected and records[selected] and shown() and window and window.showQuest then window.showQuest(records[selected]) end
end)
