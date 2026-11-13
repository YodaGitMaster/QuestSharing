-- Read-only map information: own click-through labels, never Blizzard map pins or map navigation.
local ADDON, ns = ...
local Z,U,S = {},ns.optionalUI,ns.style
ns.zoneLevels=Z
local views,current,cache={},nil,{}
local lastMap,nextBuild=nil,0
local function finite(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge end
local function zoneType() return Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3 end
local function mapInfo(id)
    local info=U.call(C_Map and C_Map.GetMapInfo,id)
    return type(info)=="table" and info or nil
end
local function clean(s) return type(s)=="string" and string.gsub(string.gsub(s,"|c%x%x%x%x%x%x%x%x",""),"|r","") or "Unknown zone" end
local function span(lo,hi) return lo==hi and tostring(lo) or (lo.."–"..hi) end
function Z.range(id)
    if not finite(id) or id<=0 or id%1~=0 then return end
    if cache[id] then return cache[id][1],cache[id][2] end
    local lo,hi=U.call(C_Map and C_Map.GetMapLevels,id)
    if finite(lo) and finite(hi) and lo>=1 and hi<=1000 and lo<=hi and lo%1==0 and hi%1==0 then
        cache[id]={lo,hi};return lo,hi
    end
    -- Missing/loading data is not a zero-level zone and must be retried.
end
local function hide(view)
    if not view then return end
    view.panel:Hide()
    for _,label in ipairs(view.labels) do label:Hide() end
end
local function viewFor(canvas,scroll)
    if views[canvas] then return views[canvas] end
    ns.trying("showing zone questing level ranges", "zonelevels")
    local v={labels={},zones={},canvas=canvas}
    v.panel=CreateFrame("Frame",nil,scroll)
    v.panel:SetWidth(290);v.panel:SetHeight(48);v.panel:SetPoint("TOPLEFT",scroll,"TOPLEFT",12,-12)
    v.panel:EnableMouse(false)
    S.fill(v.panel,"BACKGROUND",0.025,0.04,0.065,0.88):SetAllPoints(v.panel)
    v.heading=U.text(v.panel,S.GOLD.."Questing levels|r",8,6,274)
    v.text=U.text(v.panel,"",8,25,274);v.text:SetWordWrap(false)
    views[canvas]=v;return v
end
local function rectangle(child,parent)
    local fn=C_Map and C_Map.GetMapRectOnMap
    if type(fn)~="function" then return end
    local ok,x1,x2,y1,y2=pcall(fn,child,parent)
    if ok and finite(x1) and finite(x2) and finite(y1) and finite(y2)
        and x1>=0 and x2<=1 and y1>=0 and y2<=1 and x1<x2 and y1<y2 then
        return (x1+x2)/2,(y1+y2)/2
    end
end
local function rebuild(v,id,info)
    v.zones={}
    local world=Enum and Enum.UIMapType and Enum.UIMapType.World or 1
    if info and type(info.mapType)=="number" and info.mapType>world then
        local children=U.call(C_Map and C_Map.GetMapChildrenInfo,id,zoneType(),true)
        local seen={}
        for _,child in ipairs(type(children)=="table" and children or {}) do
            local map=type(child)=="table" and child.mapID
            if map~=id and finite(map) and not seen[map] and child.mapType==zoneType() then
                seen[map]=true
                local x,y=rectangle(map,id)
                if x then
                    local lo,hi=Z.range(map)
                    v.zones[#v.zones+1]={id=map,name=clean(child.name),x=x,y=y,min=lo,max=hi}
                end
            end
        end
        table.sort(v.zones,function(a,b) return a.id<b.id end)
    end
end
local function labelFor(v,i)
    if v.labels[i] then return v.labels[i] end
    local p=CreateFrame("Frame",nil,v.canvas)
    p:SetWidth(72);p:SetHeight(19);p:EnableMouse(false)
    S.fill(p,"BACKGROUND",0.025,0.04,0.065,0.8):SetAllPoints(p)
    p.text=U.text(p,"",2,3,68);p.text:SetJustifyH("CENTER");p.text:SetWordWrap(false)
    v.labels[i]=p;return p
end
local function describe(info)
    if not info then return "Zone level data is unavailable on this client." end
    if info.mapType==zoneType() then
        local lo,hi=Z.range(info.mapID)
        return (lo and span(lo,hi) or "range unavailable").." · "..clean(info.name)
    end
    local world=Enum and Enum.UIMapType and Enum.UIMapType.World or 1
    if type(info.mapType)=="number" and info.mapType<=world then return "Choose a continent or zone to see its ranges." end
    local continent=Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
    if info.mapType==continent then return "Hover a zone · ? means range unavailable" end
    return "Questing ranges are shown for outdoor zones."
end
function Z.draw()
    local wm=WorldMapFrame
    local scroll=wm and wm.ScrollContainer
    local canvas=scroll and scroll.Child
    if not (ns.db.enabled and ns.db.zoneLevels and not ns.isBlocked("zonelevels") and wm and U.call(wm.IsShown,wm) and canvas) then
        hide(current);lastMap=nil;return
    end
    local id=U.call(wm.GetMapID,wm)
    if not finite(id) or id<=0 then hide(current);lastMap=nil;return end
    local v=viewFor(canvas,scroll)
    if current~=v then hide(current);current=v;lastMap=nil end
    local info=mapInfo(id)
    local now=GetTime()
    if id~=lastMap or now>=nextBuild then rebuild(v,id,info);lastMap,nextBuild=id,now+2 end
    local scale=U.call(canvas.GetScale,canvas) or 1
    if not finite(scale) or scale<=0 then scale=1 end
    local width,height=U.call(canvas.GetWidth,canvas),U.call(canvas.GetHeight,canvas)
    local count=0
    if finite(width) and finite(height) and width>0 and height>0 then
        for i,zone in ipairs(v.zones) do
            count=i
            local p=labelFor(v,i);p.zone=zone
            p.text:SetText(zone.min and (S.GOLD..span(zone.min,zone.max).."|r") or (S.GREY.."?|r"))
            p:ClearAllPoints();p:SetScale(1/scale)
            p:SetPoint("CENTER",canvas,"TOPLEFT",zone.x*width*scale,-zone.y*height*scale)
            p:Show()
        end
    end
    for i=count+1,#v.labels do v.labels[i]:Hide() end
    local hovered
    if type(wm.GetNormalizedCursorPosition)=="function" then
        local x,y=U.call(wm.GetNormalizedCursorPosition,wm)
        if finite(x) and finite(y) and x>=0 and x<=1 and y>=0 and y<=1 then
            local hit=U.call(C_Map and C_Map.GetMapInfoAtPosition,id,x,y)
            if type(hit)=="table" and hit.mapType==zoneType() then hovered=hit end
        end
    end
    v.text:SetText(describe(hovered or info));v.panel:Show()
end
function Z.refresh()
    cache={};lastMap=nil;Z.draw()
end
function Z._view() return current end
local function tick()
    Z.draw()
    local wm=WorldMapFrame
    ns.after(ns.db.enabled and ns.db.zoneLevels and wm and U.call(wm.IsShown,wm) and 0.25 or 1,tick)
end
ns.after(1,tick)
for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LEVEL_UP","WORLD_MAP_UPDATE"}) do ns.on(event,Z.refresh) end
