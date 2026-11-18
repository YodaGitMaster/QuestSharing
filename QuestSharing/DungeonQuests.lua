-- Explicit-open quest catalogue. Dungeon association follows quest locations, not reward equipment or pickup zone.
local ADDON, ns = ...
local D, Q, E, U, S, C = {}, ns.questie, ns.equipmentUI, ns.optionalUI, ns.style, ns.compat
ns.dungeonQuests = D
local window, filters, records, results, places = nil, nil, {}, {}, {}
local ready, loading, page, progress, total = false, false, 1, 0, 0
local selected, message, generation = nil, "Open to read dungeon quests.", 0
local filterError
local refreshPending=false
local menuEntry, menuQuest -- what D.menu last opened, to tell our right-click menu from other windows' menus
local PAGE, OWNER, REWARDS_OWNER = 5, "dungeonQuests", "dungeonQuestRewards"
local FOREGROUND_MS = 8 -- the player is waiting on this visible list; it reads ~18 fields per quest
local rewardIndex, rewardsReady, rewardsLoading = {}, false, false
local hovered, showHover
local paint
local function number(v) return tonumber(v) or 0 end
local function enums() return type(LibQuestieDB)=="table" and LibQuestieDB.Enum or {} end
local function areaName(area)
    return U.call(C_Map and C_Map.GetAreaInfo,area) or U.call(GetAreaInfo,area) or ("Dungeon area "..area)
end
local function defaults(mine)
    local _,class=U.call(UnitClass,"player")
    return {dungeon=0,faction=mine and U.call(UnitFactionGroup,"player") or "All factions",
        class=mine and class or "All classes",level=math.max(1,number(U.call(UnitLevel,"player"))),
        allLevels=not mine,completed=true,text=""}
end
local function shown() return window and ns.db.enabled and E.visible(OWNER) end
local function completed(id)
    return U.call((C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted,id)==true
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

function D.search(f)
    filters=f or filters or defaults()
    results={}
    local mask=enums().factionRaceMasks and enums().factionRaceMasks[filters.faction]
    local class=enums().classKeys and enums().classKeys[filters.class]
    filterError=nil
    if (filters.faction~="All factions" and not mask) or (filters.class~="All classes" and not class) then
        filterError="Update QuestieDB: class/faction mappings are unavailable; use All quests to browse without these filters."
        return results
    end
    local needle=string.lower(filters.text or "")
    for _,r in pairs(records) do
        if (filters.dungeon==0 or r.dungeons[filters.dungeon])
            and (filters.allLevels or (r.required<=filters.level and (r.max==0 or filters.level<=r.max)))
            and (filters.class=="All classes" or r.classes==0 or (class and ns.rewards.overlaps(r.classes,class)))
            and (filters.faction=="All factions" or r.races==0 or (mask and ns.rewards.overlaps(r.races,mask)))
            and (filters.completed or not completed(r.id))
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

function D.scan()
    if not shown() then return false end
    ns.closeQuestMenu();E.dismissMenu();ns.dataWork.cancel(OWNER)
    ns.dataWork.cancel(REWARDS_OWNER)
    rewardIndex,rewardsReady,rewardsLoading={},false,false
    generation=generation+1
    local token=generation
    records,results,places={}, {}, {}
    ready,loading,progress,total,filterError=false,true,0,0,nil
    message="Needs a recent QuestieDB with an enumerable quest catalogue."
    ns.dataWork.start(OWNER,function()
        local ids=Q.ids("quest")
        if type(ids)~="table" then loading=false;paint();return end
        total=#ids
        local cache,all,seeds={},{},{}
        local function read(kind,id,key) local value=Q.get(kind,id,key);ns.dataWork.checkpoint();return value end
        for _,id in ipairs(ids) do
            local name=read("quest",id,"name")
            if type(name)=="string" and name~="" then
                local r={id=id,name=name,level=number(read("quest",id,"questLevel")),
                    required=number(read("quest",id,"requiredLevel")),max=number(read("quest",id,"requiredMaxLevel")),
                    classes=number(read("quest",id,"requiredClasses")),races=number(read("quest",id,"requiredRaces")),
                    beforeAny=read("quest",id,"preQuestSingle"),beforeAll=read("quest",id,"preQuestGroup"),
                    next=read("quest",id,"nextQuestInChain"),dungeons=memberships(id,read,cache)}
                all[id]=r
                if next(r.dungeons) then seeds[#seeds+1]=r end
            end
            progress=progress+1
            if progress%100==0 then paint() end
            ns.dataWork.yield()
        end
        -- Chain membership is separate from what a step asks the player to do (a chain can include talk-only steps).
        local function link(before,after)
            before,after=math.abs(number(before)),math.abs(number(after))
            if before==0 or after==0 or before==after then return end
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
            for _,list in ipairs({r.beforeAny or {},r.beforeAll or {}}) do
                for _,before in ipairs(type(list)=="table" and list or {}) do link(before,r.id) end
            end
            if number(r.next)>0 then link(r.id,r.next) end
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
                    for _,list in ipairs({r.beforeAny or {},r.beforeAll or {}}) do
                        for _,before in ipairs(type(list)=="table" and list or {}) do include(before,"Preparation") end
                    end
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
        ready,loading=true,false
        if filters.dungeon~=0 and not places[filters.dungeon] then filters.dungeon=0 end
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
    if role=="Preparation" then return "Chain quest: prerequisite" end
    if role=="Follow-up" then return "Chain quest: follow-up" end
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
            for _,q in ipairs(list) do lines[#lines+1]=q.name.." ("..q.id..")" end
        end
    end
    return lines
end

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
    lines[#lines+1]="Task: "..taskLabel(r)
    lines[#lines+1]=xp~=nil and ("XP: "..xp.." (base)") or "XP: unknown in installed quest data"
    if not rewardsReady then lines[#lines+1]="Item rewards: loading…"
    elseif not rewardIndex then lines[#lines+1]="Item rewards: unavailable in installed quest data"
    elseif not rewardIndex[r.id] or #rewardIndex[r.id]==0 then lines[#lines+1]="No item rewards listed in quest data."
    else
        lines[#lines+1]="Item rewards (choices may apply):"
        for _,id in ipairs(rewardIndex[r.id]) do
            local name=U.call((C_Item and C_Item.GetItemInfo) or GetItemInfo,id) or Q.get("item",id,"name") or ("Item "..id)
            lines[#lines+1]="• "..name.." ("..id..")"
        end
    end
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
function D.showPickup(id)
    local r=records[id]
    if not r then return false end
    local list=pickups(r)
    for _,p in ipairs(list) do
        local pt=p.point
        if pt and pt.map and not pt.dungeon and pt.x>=0 and pt.x<=100 and pt.y>=0 and pt.y<=100 then
            C.setWaypoint(pt.map,pt.x/100,pt.y/100)
            ns.print(pickupText(p));U.mapHint(pt.map);return true
        end
    end
    if list[1] then
        ns.print(pickupText(list[1]))
        local pt=list[1].point
        if pt and pt.map then U.mapHint(pt.map) end
    else ns.print(Q.whereText(id) or "Quest pickup location unknown in QuestieDB.") end
    return false
end
function D.menu(id)
    local r=records[id]
    if not r then return end
    local e=entry(r)
    local items=ns.questMenuItems(e)
    table.insert(items,1,{text="Show pickup on map (open M)",run=function() D.showPickup(id) end})
    table.insert(items,1,{text="Where to pick it up",run=function()
        local list=pickups(r)
        if #list==0 then ns.print(Q.whereText(id) or "Quest pickup location unknown in QuestieDB.") end
        for _,p in ipairs(list) do ns.print(pickupText(p)) end
    end})
    menuEntry,menuQuest=e,id
    ns.openQuestMenu(e,items)
end
function D.detail(r)
    local lines={r.name.." (quest "..r.id..")",r.dungeonText,
        "Quest level "..r.level.." • requires level "..r.required..(r.max>0 and ("–"..r.max) or "+"),"", "Pick up:"}
    local factionNames={}
    for _,faction in ipairs({"Alliance","Horde"}) do
        local mask=enums().factionRaceMasks and enums().factionRaceMasks[faction]
        if r.races==0 or (mask and ns.rewards.overlaps(r.races,mask)) then factionNames[#factionNames+1]=faction end
    end
    table.insert(lines,4,"Faction: "..(#factionNames>0 and table.concat(factionNames," / ") or "Unknown"))
    local classNames={}
    if r.classes==0 then classNames[1]="All classes"
    else
        for _,choice in ipairs(classChoices()) do
            local mask=enums().classKeys and enums().classKeys[choice.value]
            if mask and ns.rewards.overlaps(r.classes,mask) then classNames[#classNames+1]=choice.label end
        end
    end
    table.insert(lines,5,"Class: "..(#classNames>0 and table.concat(classNames,", ") or "Unknown"))
    table.insert(lines,6,chainLabel(r));table.insert(lines,7,"Task: "..taskLabel(r))
    local list=pickups(r)
    for _,p in ipairs(list) do lines[#lines+1]=pickupText(p) end
    if #list==0 then lines[#lines+1]=Q.whereText(r.id) or "Unknown pickup location in QuestieDB." end
    local turnIns=locations(r).turnIns
    lines[#lines+1]="\nTurn in:"
    if #turnIns==0 then lines[#lines+1]="Unknown turn-in location in quest data." end
    for _,p in ipairs(turnIns) do lines[#lines+1]=pickupText(p) end
    local before,any=Q.before(r.id)
    if #before>0 then lines[#lines+1]="\nPrerequisites ("..(any and "any" or "all").."): "..table.concat(before,", ") end
    for i,line in ipairs(chainLines(r)) do if i>1 then lines[#lines+1]=line end end
    local chain=Q.chainText(r.id,C.link(entry(r)))
    if chain then lines[#lines+1]="\n"..chain end
    local how=Q.howText(r.id,r.name)
    if how then lines[#lines+1]="\n"..how end
    lines[#lines+1]="\nFaction/class/level filters do not check reputation, professions, events or every acceptance condition."
    lines[#lines+1]="Includes known outdoor preparation and follow-ups. Coverage depends on installed QuestieDB."
    return table.concat(lines,"\n")
end
function D.go(delta)
    local wanted=math.max(1,math.min(math.max(1,math.ceil(#results/PAGE)),page+delta))
    if wanted==page then return false end
    page=wanted;ns.closeQuestMenu();paint();return true
end
-- keepMenu (quest-log events): leave an open right-click menu alone unless its quest left the results.
function D.refresh(keepMenu)
    if not shown() then return end
    local open=keepMenu and menuEntry and ns.questMenuEntry()==menuEntry and menuQuest
    if not keepMenu then ns.closeQuestMenu() end
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
    window.levelMode:SetLabel(filters.allLevels and "All levels" or ("Available at level "..filters.level))
    window.completed:SetLabel(filters.completed and "Including completed" or "Hiding completed")
end
paint=function()
    if not window then return end
    hovered=nil;U.hideTip()
    page=math.max(1,math.min(page,math.max(1,math.ceil(#results/PAGE))))
    window.status:SetText(window.levelError or filterError or (loading and ("Reading dungeon quests: "..progress.."/"..total.." (pauses in combat)"))
        or (not ready and message) or (#results==0 and "No matching quests; broaden your filters or refresh Questie data.")
        or ((page-1)*PAGE+1).."–"..math.min(#results,page*PAGE).." of "..#results.." quests • right-click for quest actions")
    E.pageButtons(window.prev,window.next,#results,page,PAGE)
    for i,row in ipairs(window.rows) do
        local r=results[(page-1)*PAGE+i];row.result=r
        if r then
            E.paintRow(row,nil,r.name.." · level "..r.level.." · req "..r.required.."+",
                chainLabel(r).." · "..r.dungeonText..(completed(r.id) and " · Completed" or ""))
            local task,talk=taskLabel(r)
            row.task:SetText((talk and "|cff80e0ff" or S.GOLD).."Task: "..task.."|r")
            local list=locations(r)
            row.pickup:SetText("Pickup: "..locationSummary(list.pickups))
            row.turnIn:SetText("Turn-in: "..locationSummary(list.turnIns))
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01");row.rarity:Hide();row.frame:Show()
        else row.frame:Hide() end
    end
    if not E.focusRows(window.rows,selected,function(r) return r.id end) then
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
            filters[key]=value;page=1;D.updateControls();D.refresh()
        end)
        window.controls[#window.controls+1]=b;return b
    end
    window.dungeon=choice("Dungeon",0,300,dungeonChoices,"dungeon")
    window.faction=choice(nil,310,165,{"All factions","Alliance","Horde"},"faction")
    window.class=choice(nil,485,165,classChoices,"class")
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
    window.levelMode=E.button(f,"All levels",180,function() filters.allLevels=not filters.allLevels;page=1;D.updateControls();D.refresh() end)
    window.levelMode:SetPoint("TOPLEFT",f,"TOPLEFT",110,-60)
    window.completed=E.button(f,"",180,function() filters.completed=not filters.completed;page=1;D.updateControls();D.refresh() end)
    window.completed:SetPoint("TOPLEFT",f,"TOPLEFT",300,-60)
    window.mine=E.button(f,"My character",160,function()
        local dungeon=filters.dungeon;filters=defaults(true);filters.dungeon=dungeon
        window.level:SetText(tostring(filters.level));window.level.cancel();window.search:SetText("");window.search.cancel()
        window.levelError=nil;page=1;D.updateControls();D.refresh()
    end)
    window.mine:SetPoint("TOPLEFT",f,"TOPLEFT",490,-60)
    window.search,window.clearSearch=E.searchBox(f,"Search dungeon, quest or ID",0,90,470,OWNER,function(text) filters.text=text;page=1;D.refresh() end)
    window.reset=E.button(f,"All quests",170,function()
        local dungeon=filters.dungeon;filters=defaults();filters.dungeon=dungeon
        window.level:SetText(tostring(filters.level));window.level.cancel();window.search:SetText("");window.search.cancel()
        window.levelError=nil;page=1;D.updateControls();D.refresh()
    end)
    window.reset:SetPoint("TOPLEFT",f,"TOPLEFT",480,-108)
    window.status=E.text(f,"",0,143,650)
    window.list=CreateFrame("Frame",nil,f);window.list:SetPoint("TOPLEFT",f,"TOPLEFT",0,-170);window.list:SetWidth(650);window.list:SetHeight(530)
    E.wheel(window.list,D.go)
    window.detailFrame,window.detailsText,window.setDetails=E.details(f,674,358,"Quest pickup and chain",690)
    window.detailFrame:SetHeight(690)
    window.pickup=E.button(window.detailFrame,"Show pickup on map (open M)",320,function() if selected then D.showPickup(selected) end end)
    window.pickup:SetPoint("BOTTOMLEFT",window.detailFrame,"BOTTOMLEFT",14,18)
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
            if selected~=r.id or auto~=true then selected=r.id;window.setDetails(D.detail(r)) end
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
    window.reload=E.button(f,"Refresh data",120,D.scan);window.reload:SetPoint("TOPLEFT",f,"TOPLEFT",530,-705)
    E.navigation(window.search,window.rows,D.go)
    -- Hiding (close, Esc, other tab) pauses the catalogue scan so reopening continues it instead of restarting.
    f.suspend=function()
        ns.dataWork.pause(OWNER);ns.closeQuestMenu()
        hovered=nil;U.hideTip();ns.dataWork.cancel(REWARDS_OWNER)
        if rewardsLoading then rewardsLoading,rewardsReady=false,false;rewardIndex={} end
    end
    f:SetScript("OnHide",f.suspend)
    return true
end
local function stop()
    generation=generation+1;ns.dataWork.cancel(OWNER)
    if loading then loading,ready=false,false end
end
function D.open(text)
    if not ns.db.enabled then ns.print("switch Quest Sharing on first (/qs on)");return end
    filters=filters or defaults()
    if not build() then return end
    E.show(OWNER)
    if text and text~="" then filters.text=text;window.search:SetText(text);window.search.cancel() end
    D.updateControls()
    for _,box in ipairs({window.level,window.search}) do if box.dirty then box.flush() end end
    if ready then D.refresh()
    elseif loading and ns.dataWork.busy(OWNER) then ns.dataWork.resume(OWNER);paint()
    else D.scan() end
end
-- Master disable: discard the scan entirely.
function D.close() if window then E.close(OWNER);stop() end end
function D._window() return window end
function D._results() return results end
function D._state() return ready,loading,progress end
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
end)
