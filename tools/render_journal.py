"""Preview renderer for the Dungeon quests (Dungeon Journal look) pages.

Loads the real addon in the lupa test harness, records every frame's anchors, size, colour, texture and text,
computes absolute rectangles and paints them with PIL (system python3 has PIL; the test venv has lupa).
Scenes (whole window, 1032 x 715): home, home_search (search text, clear button), quests (normal quest), quests_class (class-only quest), quests_chain (a done
chain quest), bosses (Encounter Journal portraits, journal description, abilities, Needed for), map (the client's Deadmines tiles), route.
Client art and fonts come from the client listfile (/tmp/listfile/lf.csv) and wago.tools CASC downloads cached in
/tmp/journal_render (preview only, never shipped); GetFileIDFromPath in the render answers from the same listfile.
Font strings without a width are sized with the real Friz Quadrata / Morpheus advance widths. Scroll frames and
frames with SetClipsChildren clip their children (the scroll child is moved by the scroll position).

Usage:  /tmp/qs-test-env/bin/python tools/render_journal.py   -> writes JSON dumps to /tmp/journal_render/*.json
        python3 tools/render_journal.py paint                 -> paints context/renders/*.png from those dumps
Gallery: context/renders/index.html (our renders next to the Dungeon Journal reference screenshots).
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DUMPS = pathlib.Path("/tmp/journal_render")
OUT = ROOT / "context" / "renders"

PATCH = r'''
local function patch(o)
  if type(o)~="table" or o.__patched then return o end
  o.__patched=true
  local sp=o.SetPoint
  o.SetPoint=function(self,p,rel,rp,x,y)
    if type(rel)=="number" then x,y,rel,rp=rel,rp,nil,nil end
    if type(rel)=="string" then rel=_G[rel] end
    self.pts=self.pts or {}
    for i=#self.pts,1,-1 do if self.pts[i][1]==p then table.remove(self.pts,i) end end
    table.insert(self.pts,{p,rel,rp or p,x or 0,y or 0})
    if sp then return sp(self,p,rel,rp,x,y) end
  end
  o.ClearAllPoints=function(self) self.pts={}; self.all=nil end
  o.SetAllPoints=function(self,rel) self.all=rel or true end
  o.SetColorTexture=function(self,r,g,b,a) self.color={r,g,b,a or 1} end
  o.SetTextColor=function(self,r,g,b,a) self.tcolor={r,g,b,a or 1} end
  local sf=o.SetFont
  o.SetFont=function(self,file,size,flags) self.fsize=size; if sf then return sf(self,file,size,flags) end end
  o.SetFontObject=function(self,obj) self.fobj=obj end
  o.SetBackdrop=function(self,b) self.backdrop=b end
  o.SetBackdropColor=function(self,r,g,b,a) self.bdcolor={r,g,b,a or 1} end
  o.SetBackdropBorderColor=function(self,r,g,b,a) self.bdborder={r,g,b,a or 1} end
  o.SetAlpha=function(self,a) self.alpha=a end
  o.SetClipsChildren=function(self,v) self.clips=v end
  o.SetTextInsets=function(self,l,r,t,b) self.insets={l or 0,r or 0} end
  local sbm=o.SetBlendMode
  o.SetBlendMode=function(self,m) self.blend=m; if sbm then return sbm(self,m) end end
  local ssc=o.SetScrollChild
  o.SetScrollChild=function(self,child) if type(child)=="table" then child.pts={{"TOPLEFT",self,"TOPLEFT",0,0}} end; if ssc then return ssc(self,child) end end
  -- the draw layer and its sublevel (-8..7) order textures within one frame, as the client does
  local sdl=o.SetDrawLayer
  o.SetDrawLayer=function(self,layer,sub) self.layer=layer or self.layer; self.sublevel=tonumber(sub) or 0; if sdl then return sdl(self,layer,sub) end end
  local ct=o.CreateTexture
  if ct then o.CreateTexture=function(self,name,layer,...) local t=patch(ct(self,name,layer,...)); t.layer=layer; return t end end
  local cfs=o.CreateFontString
  if cfs then o.CreateFontString=function(self,name,layer,tmpl,...) local t=patch(cfs(self,name,layer,tmpl,...)); t.layer=layer; t.tmpl=tmpl; t.GetStringHeight=STRING_HEIGHT; return t end end
  return o
end
local cf=CreateFrame
CreateFrame=function(kind,name,parent,tmpl,...) local f=patch(cf(kind,name,parent,tmpl,...)); f.tmpl=tmpl; return f end
if UIParent then patch(UIParent) end
CHARW,CHARW_SERIF=CHARW or {},CHARW_SERIF or {}
local FONT_SIZES={GameFontNormalLarge=16,GameFontNormalHuge=20,GameFontHighlightLarge=16,GameFontNormalSmall=10,GameFontHighlightSmall=10,GameFontDisableSmall=10}
-- width of a font string as the client would size it (Friz Quadrata advance widths measured by the paint step)
function MEASURE(o)
  local size=o.fsize or FONT_SIZES[o.tmpl or ""] or 12
  local text=string.gsub(string.gsub(o.text,"|c%x%x%x%x%x%x%x%x",""),"|r","")
  local best=0
  for line in string.gmatch(text.."\n","([^\n]*)\n") do
    line=string.gsub(line,"|T[^|]*|t","  ")
    local w=0
    local widths=(size>=17 and CHARW_SERIF) or CHARW
    for i=1,#line do w=w+(widths[string.byte(line,i)] or 55) end
    if w>best then best=w end
  end
  return math.floor(best*size/100+0.5)
end
-- the client's height of a (wrapped) font string: lines x (size + 2), wrapping at the string's width
function STRING_HEIGHT(self)
  local size=self.fsize or FONT_SIZES[self.tmpl or ""] or 12
  local text=string.gsub(string.gsub(tostring(self.text or ""),"|c%x%x%x%x%x%x%x%x",""),"|r","")
  local lines=0
  for line in string.gmatch(text.."\n","([^\n]*)\n") do
    local w=MEASURE({text=line,fsize=size})
    local width=self.width or 0
    lines=lines+((self.wordWrap~=false and width>0) and math.max(1,math.ceil(w/width)) or 1)
  end
  return lines*(size+2)
end
LAYER_ORDER={BACKGROUND=1,BORDER=2,ARTWORK=3,OVERLAY=4,HIGHLIGHT=5}
function DUMP(root,W,H)
  local cache,out={},{}
  local function anchor(r,p)
    local x=(p:find("LEFT") and r[1]) or (p:find("RIGHT") and r[1]+r[3]) or r[1]+r[3]/2
    local y=(p:find("TOP") and r[2]) or (p:find("BOTTOM") and r[2]+r[4]) or r[2]+r[4]/2
    return x,y
  end
  local rect
  rect=function(o)
    if o==root then return {0,0,W,H} end
    if cache[o] then return cache[o] end
    cache[o]={0,0,0,0}
    local par=o.parent or root
    local r
    if o.all then
      local pr=rect(o.all==true and par or o.all); r={pr[1],pr[2],pr[3],pr[4]}
    else
      local pts=o.pts or {}
      -- a scroll child sits at its scroll frame's top left, moved up by the scroll position
      if par.scrollChild==o then pts={{"TOPLEFT",par,"TOPLEFT",0,par.vscroll or 0}} end
      local w,h=o.width or 0,o.height or 0
      if o.isFontString and w<1 and type(o.text)=="string" and o.text~="" then w,h=MEASURE(o),math.max(h,(o.fsize or 12)+2); o.measured=true end
      if #pts==0 then local pr=rect(par); r={pr[1]+(pr[3]-w)/2,pr[2]+(pr[4]-h)/2,w,h}
      else
        local L,T,R,B,cx,cy
        for _,pt in ipairs(pts) do
          local ax,ay=anchor(rect(pt[2] or par),pt[3]); ax=ax+(pt[4] or 0); ay=ay-(pt[5] or 0)
          local p=pt[1]
          if p:find("LEFT") then L=ax elseif p:find("RIGHT") then R=ax else cx=ax end
          if p:find("TOP") then T=ay elseif p:find("BOTTOM") then B=ay else cy=ay end
        end
        if L and R then w=R-L elseif L then R=L+w elseif R then L=R-w else L=(cx or 0)-w/2 end
        if T and B then h=B-T elseif T then B=T+h elseif B then T=B-h else T=(cy or 0)-h/2 end
        r={L,T,w,h}
      end
    end
    cache[o]=r; return r
  end
  -- scroll frames (and frames that clip their children) cut what lies outside them, as the client does
  local function visit(o,clip)
    if o~=root and o.shown==false then return end
    local r=rect(o)
    if o.kind=="ScrollFrame" or o.clips then
      local c={r[1],r[2],r[1]+r[3],r[2]+r[4]}
      if clip then c={math.max(c[1],clip[1]),math.max(c[2],clip[2]),math.min(c[3],clip[3]),math.min(c[4],clip[4])} end
      clip=c
    end
    local kind=(o.isTexture and "tex") or (o.isFontString and "text") or "frame"
    local tex=o.texture
    out[#out+1]={x=r[1],y=r[2],w=r[3],h=r[4],kind=kind,texture=tex and tostring(tex) or nil,color=o.color,vertex=o.vertex,
      text=(kind=="text" and o.text) or nil,tcolor=o.tcolor,fsize=o.fsize,tmpl=type(o.tmpl)=="string" and o.tmpl or nil,layer=o.layer,bdcolor=o.bdcolor,
      bdborder=o.bdborder,backdrop=o.backdrop and true or nil,blend=o.blend,measured=o.measured,alpha=o.alpha,round=o.jRing and true or nil,anchor=o.pts and o.pts[1] and o.pts[1][1] or nil,name=type(o.name)=="string" and o.name or nil,coords=o.coords,clip=clip,
      wrap=nil}
    if kind=="text" then out[#out].wrap=o.wordWrap end -- false must survive (an and/or would turn it into nil)
    local kids={}
    local index={}
    for i,c in ipairs(o.children or {}) do kids[#kids+1]=c; index[c]=i end
    local function rank(c) if c.isTexture then return LAYER_ORDER[c.layer or "ARTWORK"] or 3 elseif c.isFontString then return 6 else return 7 end end
    -- (layer, sublevel, creation order): Lua's sort is not stable, so the creation index breaks every tie
    table.sort(kids,function(a,b)
      local ra,rb=rank(a),rank(b); if ra~=rb then return ra<rb end
      local sa,sb=a.isTexture and a.sublevel or 0,b.isTexture and b.sublevel or 0; if sa~=sb then return sa<sb end
      return index[a]<index[b]
    end)
    for _,c in ipairs(kids) do visit(c,clip) end
    if o.kind=="EditBox" and type(o.text)=="string" and o.text~="" then -- what you typed, over the box art, after the left inset
      local l=o.insets and o.insets[1] or 6
      out[#out+1]={x=r[1]+l,y=r[2]+(r[4]-14)/2,w=r[3]-l-(o.insets and o.insets[2] or 6),h=14,kind="text",text=o.text,fsize=12,
        tcolor={1,1,1,1},wrap=false,clip=clip}
    end
  end
  visit(root,nil)
  return out
end
'''


def to_py(v, depth=0):
    if hasattr(v, "items"):
        if depth > 3: return None
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(v[k], depth + 1) for k in sorted(keys)]
        return {str(k): to_py(v[k], depth + 1) for k in keys}
    if isinstance(v, (int, float, str, bool)) or v is None: return v
    return str(v)


def dump(g, root_expr, w, h, name):
    data = to_py(g.eval(f"DUMP({root_expr},{w},{h})"))
    DUMPS.mkdir(parents=True, exist_ok=True)
    (DUMPS / f"{name}.json").write_text(json.dumps({"w": w, "h": h, "items": data}))
    print(name, len(data), "items")


LISTFILE = pathlib.Path("/tmp/listfile/lf.csv")
# GetFileIDFromPath in the render answers from the client listfile (every interface/ file)
KNOWN = ("interface/",)


def file_ids():
    out = {}
    if LISTFILE.exists():
        for line in LISTFILE.open(encoding="utf8", errors="ignore"):
            fid, _, path = line.strip().partition(";")
            low = path.lower()
            if low.endswith(".blp") and low.startswith(KNOWN):
                out[low[:-4]] = int(fid)
    return out


def map_tiles(floor):
    """File IDs of the Deadmines world map tiles thedeadmines<floor>_1..12 (4 x 3 tiles of 256 px)."""
    ids = {}
    if LISTFILE.exists():
        for line in LISTFILE.open(encoding="utf8", errors="ignore"):
            if "interface/worldmap/thedeadmines/thedeadmines%d_" % floor in line:
                fid, _, path = line.strip().partition(";")
                ids[int(path.rsplit("_", 1)[1].split(".")[0])] = int(fid)
    return [ids.get(i, 0) for i in range(1, 13)]


# Render-only data: real quest / boss names, AtlasLoot-shaped boss tables and item icons.
SCENE = r"""
QUESTIE_QUESTS[1].name="The Defias Brotherhood"
QUESTIE_QUESTS[2].name="Red Silk Bandanas"
QUESTIE_QUESTS[3].name="The Unsent Letter"
QUESTIE_QUESTS[4].name="The Tome of Valor"
QUESTIE_QUESTS[4].requiredClasses=1025
QUESTIE_QUESTS[1].objectives={{{639}}}
QUESTIE_QUESTS[2].objectivesText={'Bring 10 Red Silk Bandanas to Scout Riell at the Sentinel Hill tower.'}
QUESTIE_QUESTS[2].reputationReward={{72,250}}
GetFactionInfoByID=function(id) return id==72 and 'Stormwind' or nil end
UnitLevel=function() return 20 end
RAID_CLASS_COLORS={WARRIOR={r=.78,g=.61,b=.43},PALADIN={r=.96,g=.55,b=.73},HUNTER={r=.67,g=.83,b=.45},ROGUE={r=1,g=.96,b=.41},
  PRIEST={r=1,g=1,b=1},SHAMAN={r=0,g=.44,b=.87},MAGE={r=.25,g=.78,b=.92},WARLOCK={r=.53,g=.53,b=.93},DRUID={r=1,g=.49,b=.04}}
for k,c in pairs(RAID_CLASS_COLORS) do c.colorStr=string.format("ff%02x%02x%02x",c.r*255,c.g*255,c.b*255) end
CLASS_ICON_TCOORDS=nil -- the theme's own copy of the client table
REWARD_ITEMS[810].icon="Interface\\Icons\\INV_Staff_08"
REWARD_ITEMS[811].icon="Interface\\Icons\\INV_Fabric_Silk_01"
local LOOT={
  [5187]={"Rhahk'Zor's Hammer","INV_Hammer_04",2,4,"INVTYPE_2HWEAPON"},[872]={"Rockslicer","INV_Axe_03",2,1,"INVTYPE_2HWEAPON"},
  [5195]={"Gold-flecked Gloves","INV_Gauntlets_05",4,1,"INVTYPE_HAND"},[5194]={"Taskmaster Axe","INV_Axe_03",2,1,"INVTYPE_2HWEAPON"},
  [5199]={"Smelting Pants","INV_Pants_03",4,2,"INVTYPE_LEGS"},[5196]={"Smite's Reaver","INV_Axe_03",2,0,"INVTYPE_WEAPON"},
  [7230]={"Smite's Mighty Hammer","INV_Hammer_09",2,5,"INVTYPE_2HWEAPON"},[5200]={"Impaling Harpoon","INV_Spear_04",2,6,"INVTYPE_2HWEAPON"},
  [5193]={"Cape of the Brotherhood","INV_Misc_Cape_08",4,1,"INVTYPE_CLOAK"},[5191]={"Cruel Barb","INV_Sword_04",2,7,"INVTYPE_WEAPON"},
  [5192]={"Thief's Blade","INV_Sword_04",2,7,"INVTYPE_WEAPON"},[10399]={"Blackened Defias Armor","INV_Chest_Leather_09",4,2,"INVTYPE_CHEST"},
  [5197]={"Cookie's Tenderizer","INV_Hammer_04",2,4,"INVTYPE_WEAPON"},[5198]={"Cookie's Stirring Rod","INV_Staff_08",2,10,"INVTYPE_WEAPON"},
}
for id,r in pairs(LOOT) do REWARD_ITEMS[id]={name=r[1],icon="Interface\\Icons\\"..r[2],class=r[3],subClass=r[4],loc=r[5],itemLevel=20,requiredLevel=15,quality=(id==5191 or id==5193) and 4 or 3} end
local function boss(name,npc,level,display,items) local t={name=name,npcID=npc,Level=level,DisplayIDs={{display}},[1]={}};for i,id in ipairs(items) do t[1][i]={i,id} end;return t end
local dm={name="The Deadmines",InstanceID=36,MapID=1581,items={
  boss("Rhahk'Zor",644,19,1,{5187,872}),boss("Sneed",643,20,2,{5195,5194}),boss("Gilnid",1763,20,3,{5199}),
  boss("Mr. Smite",646,20,4,{5196,7230}),boss("Captain Greenskin",647,20,5,{5200}),
  boss("Edwin VanCleef",639,21,6,{5193,5191,5192,10399}),boss("Cookie",645,20,7,{5197,5198}),
}}
local module={Deadmines=dm}
function module:GetDifficultyName(id) return ({[1]="Normal"})[id] end
AtlasLoot={ItemDB={Storage={AtlasLootClassic_DungeonsAndRaids=module}}}
function AtlasLoot.ItemDB:GetItemTable(mod,content,b,diff) local bt=self.Storage[mod][content].items[b];return bt[diff],{"Item"},{name="Normal"} end
INVTYPE_WEAPON="One-Hand";INVTYPE_2HWEAPON="Two-Hand";INVTYPE_HAND="Hands";INVTYPE_LEGS="Legs";INVTYPE_CLOAK="Back";INVTYPE_CHEST="Chest"
"""

# after start: item icons from the reward catalogue, client file IDs from the listfile
LATE = r"""
GetItemInfo=function(id)
  local r=REWARD_ITEMS[id]
  if not r then return nil end
  return r.name,"|Hitem:"..id.."|h["..r.name.."]|h",r.quality or 3,r.itemLevel,r.requiredLevel,"","",1,r.loc,r.icon or "Interface\\Icons\\INV_Misc_QuestionMark",0,r.class,r.subClass
end
GetItemIcon=function(id) local r=REWARD_ITEMS[id];return r and r.icon end
GetFileIDFromPath=function(p) return FILE_IDS[string.lower(string.gsub(p,"\\","/"))] end
"""


def map_art():
    a, b = map_tiles(1), map_tiles(2)
    return r"""
NS.questie.uiMapOf=function(area) if area==1581 then return 291 end end
C_Map.GetMapInfo=function(id)
  if id==291 then return {mapID=291,name="The Deadmines",mapType=4} end
  if id==292 then return {mapID=292,name="Ironclad Cove",mapType=4} end
end
C_Map.GetMapGroupID=function(id) if id==291 or id==292 then return 7 end end
C_Map.GetMapGroupMembersInfo=function(g) if g==7 then return {{mapID=292,relativeHeightIndex=2,name="Ironclad Cove"},{mapID=291,relativeHeightIndex=1,name="The Deadmines"}} end end
C_Map.GetMapArtLayers=function(id) if id==291 or id==292 then return {{layerWidth=1002,layerHeight=668,tileWidth=256,tileHeight=256,minScale=1,maxScale=1}} end end
TILES={[291]={%s},[292]={%s}}
C_Map.GetMapArtLayerTextures=function(id,layer) if TILES[id] and layer==1 then return TILES[id] end end
""" % (",".join(map(str, a)), ",".join(map(str, b)))


# A route as the planner hands it over (render only; the Route page draws whatever routePlan returns).
ROUTE = r"""
NS.dungeonQuests.routePlan=function(area,assumeAll,cb)
  cb({quests=4,totalSeconds=1680,hearthUsed=true,unknown={},notes={"Westfall quests first, then the dungeon in one run."},steps={
    {kind="Fly",to="Sentinel Hill",seconds=240,point={map=1436,x=56.6,y=52.6}},
    {kind="Pick up",quest="Red Silk Bandanas",npc="Scout Riell",seconds=10,point={map=1436,x=56.6,y=47.6}},
    {kind="Pick up",quest="The Defias Brotherhood",npc="Gryan Stoutmantle",seconds=10,point={map=1436,x=56.3,y=47.5}},
    {kind="Walk",to="Moonbrook",seconds=300,point={map=1436,x=43.5,y=70.1}},
    {kind="Enter",to="The Deadmines",seconds=0},
    {kind="Hand in",quest="Red Silk Bandanas",npc="Scout Riell",seconds=10,point={map=1436,x=56.6,y=47.6}},
    {kind="Hearth",to="Stormwind City",seconds=10},
  }},{{name="The Defias Brotherhood",needs="the Westfall chain"}},0)
  return true
end
"""


FONT = "/tmp/journal_render/art/615960.ttf"   # Friz Quadrata (fonts/frizqt__.ttf), preview only
SERIF = "/tmp/journal_render/art/615962.ttf"  # Morpheus (fonts/morpheus.ttf), preview only


def char_widths():
    """Advance widths (at size 100) of printable ASCII in both fonts, measured by the system python3 (PIL)."""
    import subprocess
    code = ("import json,sys;from PIL import ImageFont\n"
            "out=[]\n"
            "for p in sys.argv[1:]:\n"
            " f=ImageFont.truetype(p,100);out.append({c:f.getlength(chr(c)) for c in range(32,127)})\n"
            "print(json.dumps(out))")
    try:
        res = subprocess.run(["python3", "-I", "-c", code, FONT, SERIF], capture_output=True, text=True, check=True)
        return [{int(k): v for k, v in t.items()} for t in json.loads(res.stdout)]
    except Exception as err:
        print("no font metrics, text widths are estimated:", err)
        return [{}, {}]


def collect():
    sys.path.insert(0, str(ROOT / "tests"))
    import test_dungeon_quests as tq
    from test_dungeon_quests import edit

    ids = file_ids()
    print("listfile ids", len(ids))
    widths = char_widths()

    def shell(extra=""):
        g = tq.game("classic", PATCH + tq.HOVER_DATA + tq.SEEKING + SCENE + extra)
        g.run("FILE_IDS={} CHARW={} CHARW_SERIF={}")
        for name, table in (("CHARW", widths[0]), ("CHARW_SERIF", widths[1])):
            t = g.eval(name)
            for k, v in table.items():
                t[k] = v
        fids = g.eval("FILE_IDS")
        for k, v in ids.items():
            fids[k] = v
        g.run(LATE + map_art() + ROUTE)
        g.advance(40)
        return g

    root = "NS.dungeonQuests._window().frame"

    def quest(g, qid):
        w = g.eval("NS.dungeonQuests._window()")
        edit(w.search, ""); g.advance(.3)
        rows = [r for r in w.rows.values() if r.result and r.result.id == qid and r.frame.shown]
        if not rows:  # not on the first page: search for it
            edit(w.search, g.eval("NS.questie.get")("quest", qid, "name")); g.advance(.3)
            rows = [r for r in w.rows.values() if r.result and r.result.id == qid]
        row = rows[0]
        row.frame.scripts.OnClick(row.frame, "LeftButton"); g.advance(40)
        row.frame.scripts.OnClick(row.frame, "LeftButton"); g.advance(1)

    # home: a done dungeon (glow behind the tick) next to open ones
    g = shell()
    g.eval("NS.dungeonQuests.home")(); g.advance(2)
    dump(g, root, 1032, 715, "home")
    # home with search text: the clear button shows and the grid narrows
    home = g.eval("NS.dungeonHomeUI._frame()")
    edit(home.search, "dead"); g.advance(1)
    dump(g, root, 1032, 715, "home_search")
    # quests: a normal quest, a class-only quest, a done chain quest
    g = shell("FINISHED[1]=true")
    g.eval("NS.dungeonQuests.openDungeon")(1581, "quests"); g.advance(1)
    for qid, name in ((2, "quests"), (4, "quests_class"), (1, "quests_chain")):
        quest(g, qid)
        dump(g, root, 1032, 715, name)
    # bosses (EJ portraits from the client listfile), Edwin VanCleef chosen as an item click would do
    g.eval("NS.dungeonQuests.openDungeon")(1581, "bosses"); g.advance(5)
    B = g.eval("NS.dungeonBossesUI")
    if B.select: B.select("Edwin VanCleef")
    g.advance(1)
    bw = B._window()
    print("bosses: description", bool(bw.desc.shown), "abilities", sum(1 for r in bw.abilities.values() if r.shown),
          "needed for", sum(1 for r in bw.quests.values() if r.shown))
    dump(g, root, 1032, 715, "bosses")
    g.eval("NS.dungeonQuests.openDungeon")(1581, "map"); g.advance(2)
    dump(g, root, 1032, 715, "map")
    g.eval("NS.dungeonQuests.openDungeon")(1581, "route"); g.advance(2)
    dump(g, root, 1032, 715, "route")


# ---------------------------------------------------------------------------------------------------- painting
def paint():
    import re
    import subprocess
    import time
    from PIL import Image, ImageDraw, ImageFont

    icons = pathlib.Path("/tmp/journal_render/icons"); icons.mkdir(parents=True, exist_ok=True)

    def font(size, serif=False):
        try: return ImageFont.truetype(SERIF if serif else FONT, max(8, int(size)))
        except Exception: return ImageFont.load_default()

    def rgba(c, a=1.0):
        if not c: return None
        c = list(c) + [1] * (4 - len(c))
        return tuple(int(max(0, min(1, v)) * 255) for v in c[:3]) + (int(max(0, min(1, c[3] * a)) * 255),)

    def icon(name):
        p = icons / (name.lower() + ".jpg")
        if not p.exists():
            subprocess.run(["curl", "-sSL", "-m", "30", "-A", "Mozilla/5.0", "-o", str(p), f"https://wow.zamimg.com/images/wow/icons/large/{name.lower()}.jpg"], check=False)
        try: return Image.open(p).convert("RGBA")
        except Exception: return None

    LOAD = {"Deadmines": "Deadmines", "7963": "Forever loading screen"}

    LF = pathlib.Path("/tmp/listfile/lf.csv")
    ids = {}
    if LF.exists():
        for line in LF.open(encoding="utf8", errors="ignore"):
            if line.find(";interface/") > 0 or line.find(";Interface/") > 0:
                a, _, b = line.strip().partition(";")
                ids[b.lower()] = a
    CASC = pathlib.Path("/tmp/journal_render/casc"); CASC.mkdir(parents=True, exist_ok=True)
    cache = {}

    def real(tex):
        if tex in cache: return cache[tex]
        fid = tex if re.fullmatch(r"\d+", tex) else ids.get(tex.lower().replace("\\", "/") + ".blp")
        im = None
        if fid:
            f = CASC / f"{fid}.blp"
            for attempt in range(4):  # the CDN rate-limits bursts ("error code: 1015"): never keep such a reply
                if f.exists() and f.stat().st_size > 64 and f.read_bytes()[:4] == b"BLP2": break
                f.unlink(missing_ok=True)
                if attempt: time.sleep(3 * attempt)
                subprocess.run(["curl", "-sSL", "-m", "60", "-A", "Mozilla/5.0", "-o", str(f), f"https://wago.tools/api/casc/{fid}?download"], check=False)
            try: im = Image.open(f).convert("RGBA")
            except Exception: im = None
        cache[tex] = im
        return im

    def blit(img, src, box, coords, vertex, round_=False, alpha=1.0, blend=None):
        x0, y0, x1, y1 = [int(round(v)) for v in box]
        w, h = x1 - x0, y1 - y0
        if w < 1 or h < 1: return
        W, H = src.size
        if coords and len(coords) >= 4:
            if len(coords) == 8:  # ULx,ULy,LLx,LLy,URx,URy,LRx,LRy
                l, t, r, b = coords[0], coords[1], coords[6], coords[7]
            else:
                l, r, t, b = coords[0], coords[1], coords[2], coords[3]
            src = src.crop((int(l * W), int(t * H), max(int(l * W) + 1, int(r * W)), max(int(t * H) + 1, int(b * H))))
        part = src.resize((w, h))
        if vertex:
            vr, vg, vb = [max(0, min(1, c)) for c in (list(vertex) + [1, 1, 1])[:3]]
            va = (list(vertex) + [1, 1, 1, 1])[3] if len(vertex) >= 4 and vertex[3] is not None else 1
            r_, g_, b_, a_ = part.split()
            r_ = r_.point(lambda v: int(v * vr)); g_ = g_.point(lambda v: int(v * vg)); b_ = b_.point(lambda v: int(v * vb))
            a_ = a_.point(lambda v: int(v * va * alpha))
            part = Image.merge("RGBA", (r_, g_, b_, a_))
        elif alpha < 1:
            part.putalpha(part.split()[3].point(lambda v: int(v * alpha)))
        if round_:
            m = Image.new("L", (w, h), 0); ImageDraw.Draw(m).ellipse((0, 0, w - 1, h - 1), fill=255)
            part.putalpha(Image.composite(part.split()[3], Image.new("L", (w, h), 0), m))
        if blend == "ADD":  # additive, as the client blends glows: dst + src * alpha
            from PIL import ImageChops
            x0c, y0c = max(0, x0), max(0, y0)
            x1c, y1c = min(img.size[0], x1), min(img.size[1], y1)
            if x1c <= x0c or y1c <= y0c: return
            part = part.crop((x0c - x0, y0c - y0, x1c - x0, y1c - y0))
            black = Image.new("RGBA", part.size, (0, 0, 0, 255))
            lit = Image.composite(part, black, part.split()[3]).convert("RGB")
            base = img.crop((x0c, y0c, x1c, y1c))
            added = ImageChops.add(base.convert("RGB"), lit).convert("RGBA")
            img.paste(added, (x0c, y0c))
            return
        img.alpha_composite(part, (x0, y0))

    def fillbox(img, box, color):
        x0, y0, x1, y1 = [int(round(v)) for v in box]
        if x1 <= x0 or y1 <= y0 or not color: return
        img.alpha_composite(Image.new("RGBA", (x1 - x0, y1 - y0), color), (x0, y0))

    def stand_in(d, img, box, tex, item):
        t = tex.lower()
        if "tempportraitalphamask" in t or "tooltip-border" in t or "highlight" in t: return
        if "white8x8" in t:
            fillbox(img, box, rgba(item.get("vertex")) or (255, 255, 255, 255)); return
        src = real(tex)
        if src is not None:
            blit(img, src, box, item.get("coords"), item.get("vertex"), bool(item.get("round")), item.get("alpha") or 1.0, item.get("blend")); return
        return old_stand_in(d, img, box, tex, item)

    def old_stand_in(d, img, box, tex, item):
        x0, y0, x1, y1 = box
        w, h = x1 - x0, y1 - y0
        t = tex.lower()
        v = rgba(item.get("vertex")) or (255, 255, 255, 255)
        def fill(c): d.rectangle(box, fill=c)
        if "white8x8" in t: fill(v); return
        if "questbg" in t: fill((205, 182, 136, int(v[3] * 0.85 + 30) if v[3] < 255 else 255)); return
        if "ui-background-rock" in t: fill((58, 51, 43, 255)); return
        if "loadingscreens" in t or re.fullmatch(r"7963\d{3}", tex):
            for i in range(int(h)):
                k = i / max(1, h)
                d.line([(x0, y0 + i), (x1, y0 + i)], fill=(int(70 + 60 * k), int(60 + 40 * k), int(45 + 20 * k), 255))
            label = tex.split("\\")[-1] if "\\" in tex else f"Forever loading screen #{tex}"
            d.text((x0 + 8, y1 - 16), "[client art] " + label, fill=(255, 240, 200, 200), font=font(10))
            return
        if "\\icons\\" in t:
            im = icon(tex.split("\\")[-1])
            if im:
                img.alpha_composite(im.resize((max(1, int(w)), max(1, int(h)))), (int(x0), int(y0))); return
            d.rectangle(box, fill=(40, 40, 40, 255), outline=(120, 100, 60, 255)); return
        glyph = None
        if "availablequesticon" in t: glyph = ("!", (255, 210, 0, 255))
        elif "activequesticon" in t: glyph = ("?", (255, 210, 0, 255))
        elif "readycheck-ready" in t: glyph = ("✓", (60, 220, 60, 255))
        elif "readycheck-notready" in t: glyph = ("✕", (230, 60, 60, 255))
        elif "raidtargetingicon_8" in t or "skull" in t: glyph = ("☠", (235, 235, 235, 255))
        elif "searchbox-icon" in t: glyph = ("⌕", (200, 200, 190, 255))
        elif "goldicon" in t: glyph = ("●", (240, 200, 40, 255))
        if glyph:
            f = font(max(10, h * 0.9))
            d.text((x0 + w / 2, y0 + h / 2), glyph[0], fill=glyph[1], font=f, anchor="mm"); return
        if "ui-pvp-alliance" in t:
            d.ellipse(box, fill=(30, 60, 140, 255), outline=(220, 190, 90, 255)); d.text(((x0 + x1) / 2, (y0 + y1) / 2), "A", fill=(240, 220, 150, 255), font=font(h * 0.6), anchor="mm"); return
        if "ui-pvp-horde" in t:
            d.ellipse(box, fill=(140, 25, 20, 255), outline=(30, 20, 15, 255)); d.text(((x0 + x1) / 2, (y0 + y1) / 2), "H", fill=(240, 220, 150, 255), font=font(h * 0.6), anchor="mm"); return
        if "tempportraitalphamask" in t: d.ellipse(box, fill=(22, 18, 14, 240)); return
        if "trackingborder" in t or "goldring" in t: d.ellipse(box, outline=(225, 180, 70, 255), width=max(2, int(w / 14))); return
        if "encounterjournal" in t or "lfgicon" in t:
            d.ellipse(box, fill=(90, 70, 50, 255)); d.text(((x0 + x1) / 2, (y0 + y1) / 2), "EJ" if "encounter" in t else "LFG", fill=(255, 230, 180, 255), font=font(h * 0.25), anchor="mm"); return
        if "worldmap" in t or re.fullmatch(r"29[12]\d{3}", tex):
            d.rectangle(box, fill=(178, 150, 100, 255), outline=(120, 95, 60, 255))
            d.text((x0 + 4, y0 + 4), "map tile " + tex.split("\\")[-1], fill=(80, 60, 30, 255), font=font(10)); return
        if "tooltip-border" in t or "highlight" in t: return
        d.rectangle(box, outline=(150, 120, 70, 160))

    COLOR = re.compile(r"\|c([0-9a-fA-F]{8})(.*?)(\|r|$)", re.S)

    def draw_text(d, item, box):
        raw = item.get("text") or ""
        if not raw: return
        raw = re.sub(r"\|T[^|]*\|t", "■ ", raw)
        size = item.get("fsize") or {"GameFontNormalLarge": 16, "GameFontNormalHuge": 20, "GameFontHighlightLarge": 16,
                                     "GameFontNormalSmall": 10, "GameFontHighlightSmall": 10}.get(item.get("tmpl") or "", 12)
        base = rgba(item.get("tcolor")) or ((255, 209, 0, 255) if (item.get("tmpl") or "").startswith("GameFontNormal") else (235, 228, 210, 255))
        serif = size >= 17
        f = font(size, serif)
        x, y = box[0], box[1]
        if (item.get("w") or 0) < 1:  # no width: place by the anchor, as the client does
            plain_ = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", raw).split("\n")
            tw = max(d.textlength(l, font=f) for l in plain_) if plain_ else 0
            th = (size + 3) * len(plain_)
            a = item.get("anchor") or "CENTER"
            if "RIGHT" in a: x -= tw
            elif "LEFT" not in a: x -= tw / 2
            if "BOTTOM" in a: y -= th
            elif "TOP" not in a: y -= th / 2
        sized = (item.get("w") or 0) >= 1 and not item.get("measured")
        maxw = box[2] - box[0] if sized and box[2] - box[0] > 20 else 10000
        # the client wraps a font string with a width (unless SetWordWrap(false)), stops at its height and ends a cut
        # line with "..."; a one-line string is cut at its width the same way
        wrap = item.get("wrap") is not False and maxw < 10000
        h = box[3] - box[1]
        limit = max(1, int(round(h / (size + 2)))) if (sized and h >= size) else 10 ** 6
        if not wrap and maxw < 10000: limit = 1
        rows = []
        for line in raw.split("\n"):
            pos = 0
            segs = []
            for m in COLOR.finditer(line):
                if m.start() > pos: segs.append((line[pos:m.start()], base))
                segs.append((m.group(2), (int(m.group(1)[2:4], 16), int(m.group(1)[4:6], 16), int(m.group(1)[6:8], 16), 255)))
                pos = m.end()
            if pos < len(line): segs.append((line[pos:], base))
            words = [(w_, c) for s_, c in segs for w_ in re.split(r"(\s+)", s_.replace("|r", "")) if w_]
            row, width = [], 0.0
            for w_, c in words:
                lw = d.textlength(w_, font=f)
                if wrap and row and width + lw > maxw and not w_.isspace():
                    rows.append(row); row, width = [], 0.0
                if not row and w_.isspace(): continue
                row.append((w_, c)); width += lw
            rows.append(row)
        cut = len(rows) > limit or (not wrap and maxw < 10000 and any(sum(d.textlength(w_, font=f) for w_, _ in r) > maxw for r in rows[:1]))
        rows = rows[:limit]
        if cut and rows:  # end the last shown line with "..." inside the width
            last, ell = list(rows[-1]), d.textlength("...", font=f)
            while last and sum(d.textlength(w_, font=f) for w_, _ in last) + ell > maxw:
                w_, c = last.pop()
                while w_ and d.textlength(w_, font=f) + sum(d.textlength(v, font=f) for v, _ in last) + ell > maxw: w_ = w_[:-1]
                if w_: last.append((w_, c)); break
            last.append(("...", last[-1][1] if last else base)); rows[-1] = last
        for row in rows:
            cx = x
            for s_, c in row:
                d.text((cx + 1, y + 1), s_, fill=(0, 0, 0, 160), font=f)
                d.text((cx, y), s_, fill=c, font=f)
                cx += d.textlength(s_, font=f)
            y += size + 3

    OUT.mkdir(parents=True, exist_ok=True)
    for p in sorted(DUMPS.glob("*.json")):
        data = json.loads(p.read_text())
        base = Image.new("RGBA", (data["w"], data["h"]), (12, 10, 8, 255))
        # a run of items inside a scroll frame is drawn on a copy, and only the scroll frame's rectangle is kept
        img, clip = base, None

        def flush():
            if clip is None: return
            x0, y0 = max(0, int(round(clip[0]))), max(0, int(round(clip[1])))
            x1, y1 = min(base.size[0], int(round(clip[2]))), min(base.size[1], int(round(clip[3])))
            if x1 > x0 and y1 > y0: base.paste(img.crop((x0, y0, x1, y1)), (x0, y0))

        for it in data["items"]:
            c = it.get("clip")
            c = tuple(c) if c else None
            if c != clip:
                flush()
                clip, img = c, (base.copy() if c else base)
            d = ImageDraw.Draw(img)
            x, y, w, h = it["x"], it["y"], it["w"], it["h"]
            if w is None or h is None: continue
            box = (x, y, x + max(w, 0), y + max(h, 0))
            if it["kind"] == "frame":
                if it.get("bdcolor"): fillbox(img, box, rgba(it["bdcolor"]))
                if it.get("bdborder"): d.rectangle(box, outline=rgba(it["bdborder"]), width=2)
                continue
            if it["kind"] == "tex":
                if w < 1 or h < 1 or it.get("layer") == "HIGHLIGHT": continue  # highlights show only under the mouse
                if it.get("color"): fillbox(img, box, rgba(it["color"]))
                elif it.get("texture"): stand_in(d, img, box, it["texture"], it)
                continue
            if it["kind"] == "text":
                draw_text(d, it, box)
        flush()
        base.convert("RGB").save(OUT / f"{p.stem}.png")
        print("wrote", OUT / f"{p.stem}.png")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "paint": paint()
    else: collect()
