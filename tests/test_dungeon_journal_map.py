"""Dungeon Journal look, stream M: the Map page (client map art, 12-tile fallback, floors, zoom, no-map) and the
Route page (summary, numbered steps, pins, flight-path check box, Refresh)."""
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from test_dungeon_quests import game, plain
from test_loot import click

STYLES = ("modern", "classic")

# The Deadmines (area 1581) has client map art on two floors (291, 292); area 1581's art is 4x3 tiles of 256.
ART = r'''
NS.questie.uiMapOf=function(area) if area==1581 then return 291 end if area==16919 then return 1437 end end
C_Map.GetMapInfo=function(id)
  if id==291 then return {mapID=291,name="The Deadmines",mapType=4} end
  if id==292 then return {mapID=292,name="Ironclad Cove",mapType=4} end
  if id==1437 then return {mapID=1437,name="Wetlands",mapType=3} end
end
C_Map.GetMapGroupID=function(id) if id==291 or id==292 then return 7 end end
C_Map.GetMapGroupMembersInfo=function(g) if g==7 then return {{mapID=292,relativeHeightIndex=2,name="Ironclad Cove"},{mapID=291,relativeHeightIndex=1,name="The Deadmines"}} end end
C_Map.GetMapArtLayers=function(id) if id==291 or id==292 then return {{layerWidth=1002,layerHeight=668,tileWidth=256,tileHeight=256,minScale=1,maxScale=1}} end end
C_Map.GetMapArtLayerTextures=function(id,layer)
  if (id==291 or id==292) and layer==1 then local t={};for i=1,12 do t[i]=id*1000+i end;return t end
end
'''


def page(g, module, w=1000, h=560):
    parent=g.eval("CreateFrame('Frame',nil,UIParent)")
    mod=g.eval("NS."+module)
    mod.build(parent,w,h)
    return mod


def map_game(style, extra=ART):
    g=game(style,open_tab=False)
    g.run(extra)
    return g, page(g,"dungeonMapUI")


def test_classic_dungeon_tiles_come_from_the_client_map_art_layers(style):
    g,M=map_game(style)
    M.show(1581,"The Deadmines")
    s=M._state()
    assert s.mode=="art" and s.cols==4 and s.rows==3 and s.message is None
    tiles=list(s.tiles.values())
    assert [t.texture for t in tiles]==[291000+i for i in range(1,13)]
    # the tiles form a 4x3 grid scaled into the page, left to right then top to bottom
    w=tiles[0].width
    assert 0<w<=256 and tiles[1].point[4]==w and tiles[4].point[5]==-w and tiles[11].point[4]==3*w and tiles[11].point[5]==-2*w
    assert s.view.width<=1000 and s.view.height<=560
    # two floors, sorted by height, with buttons named after them
    assert s.floors==2
    b1,b2=s.floorButtons[1],s.floorButtons[2]
    assert b1.shown and b2.shown
    click(b2)
    s=M._state()
    assert s.floor==2 and list(s.tiles.values())[0].texture==292001
    assert not g.eval("NS.db.errors")


def test_fallback_uses_the_twelve_worldmap_tiles_and_every_floor(style):
    g,M=map_game(style,"C_Map.GetMapArtLayers=nil;C_Map.GetMapArtLayerTextures=nil")
    paths=list(M.tilePaths("TheDeadmines",2).values())
    assert paths[0]=="Interface\\WorldMap\\TheDeadmines\\TheDeadmines2_1" and paths[11]=="Interface\\WorldMap\\TheDeadmines\\TheDeadmines2_12"
    M.show(1581,"The Deadmines")
    s=M._state()
    assert s.mode=="tiles" and s.cols==4 and s.rows==3 and s.floors==2
    assert list(s.tiles.values())[0].texture=="Interface\\WorldMap\\TheDeadmines\\TheDeadmines1_1"
    click(s.floorButtons[2])
    assert list(M._state().tiles.values())[11].texture=="Interface\\WorldMap\\TheDeadmines\\TheDeadmines2_12"
    # one-floor dungeons get no floor buttons
    M.show(718,"Wailing Caverns")
    s=M._state()
    assert s.floors==1 and not s.floorButtons[1].shown
    assert list(s.tiles.values())[0].texture=="Interface\\WorldMap\\WailingCaverns\\WailingCaverns1_1"


def test_missing_tile_file_and_forever_dungeon_show_the_no_map_message_and_entrance_pin(style):
    g,M=map_game(style,ART+'''
GetFileIDFromPath=function(p) return nil end
NS.dungeonQuests.entranceOf=function(area) if area==16919 then return {label="The Hall of Thanes entrance",point={map=1437,x=40,y=50}} end end
PINNED={}
NS.dungeonQuests.pinPlace=function(p) PINNED[#PINNED+1]=p;return true end
''')
    M.show(16919,"The Hall of Thanes")  # QuestieDB gives the outdoor Wetlands map: refused, no client art
    s=M._state()
    assert s.mode=="none" and "No map for this dungeon in the game files" in s.message
    assert not s.view.shown and s.page.pin.shown
    click(s.page.pin)
    pinned=g.eval("PINNED[1]")
    assert pinned.point.map==1437 and pinned.source.name=="The Hall of Thanes entrance"
    # a classic dungeon whose tile files are not in this client: same message
    g.run("C_Map.GetMapArtLayers=nil")
    M.show(1581,"The Deadmines")
    assert M._state().mode=="none"
    # back to a dungeon with art: the message goes away
    g.run(ART)
    M.show(1581,"The Deadmines")
    s=M._state()
    assert s.mode=="art" and s.message is None and not s.page.pin.shown and s.view.shown


def test_zoom_is_bounded_from_one_to_four_and_drag_pans_inside_the_map(style):
    g,M=map_game(style)
    M.show(1581,"The Deadmines")
    s=M._state()
    w1=list(s.tiles.values())[0].width
    s.view.scripts.OnMouseWheel(s.view,1)
    s=M._state()
    assert s.zoom==1.5 and abs(list(s.tiles.values())[0].width-1.5*w1)<1e-6
    assert s.page.zoomText.text=="150%"
    for _ in range(20): s.view.scripts.OnMouseWheel(s.view,1)
    assert M._state().zoom==4
    for _ in range(20): s.view.scripts.OnMouseWheel(s.view,-1)
    s=M._state()
    assert s.zoom==1 and s.panX==0 and s.panY==0
    # at 1x the whole map is in view: nothing to pan
    M.pan(-200,100)
    assert M._state().panX==0
    M.setZoom(2)
    # drag: the cursor moves 50 left and 30 up, so the map follows and shows more of the right and bottom
    v=M._state().view
    before=M._state().panX
    g.cursor(500,500); v.scripts.OnMouseDown(v,"LeftButton")
    g.cursor(450,530); v.scripts.OnUpdate(v,0.1); v.scripts.OnMouseUp(v,"LeftButton")
    s=M._state()
    assert s.panX==before+50
    # pan stays inside the map
    M.pan(-100000,-100000)
    s=M._state()
    assert abs(s.panX-s.view.width)<1e-6 and s.panY==0
    # a new dungeon starts at 1x
    M.show(1581,"The Deadmines")
    assert M._state().zoom==1


ROUTE = r'''
PINNED, PLANS = {}, {}
NS.dungeonQuests.pinPlace=function(p) PINNED[#PINNED+1]=p;return true end
NS.dungeonQuests.minutes=function(s) return math.floor(s/60+0.5).." min" end
NS.dungeonQuests.routeStepText=function(st) return st.kind.." "..(st.quest or st.to or "") end
NS.dungeonQuests.routePlan=function(area,assumeAll,cb)
  PLANS[#PLANS+1]={area=area,assume=assumeAll}
  cb({quests=2,totalSeconds=600,hearthUsed=true,unknown={},notes={"Note A"},steps={
    {kind="Fly",to="Sentinel Hill",seconds=120,point={map=1436,x=56,y=47}},
    {kind="Pick up",quest="Red Silk Bandanas",npc="Scout Riell",seconds=10,point={map=1436,x=56,y=47}},
    {kind="Enter",seconds=0},
  }},{{name="The Defias Brotherhood",needs="Wanted"}},1)
  return true
end
'''


def route_game(style, extra=ROUTE):
    g=game(style,open_tab=False)
    g.run(extra)
    return g, page(g,"dungeonRouteUI")


def shown_rows(p):
    return [b for b in p.rows.values() if b.shown]


def test_route_page_shows_summary_notes_and_numbered_step_rows(style):
    g,R=route_game(style)
    R.show(1581,"The Deadmines")
    p=R._page()
    assert p.shown
    assert plain(p.summary.text)=="The Deadmines: 2 quests · about 10 min · uses your hearthstone"
    notes=plain(p.notes.text)
    assert "Do these first: The Defias Brotherhood (needs Wanted)" in notes and "Note A" in notes and "1 more quest need" in notes
    rows=shown_rows(p)
    assert len(rows)==3
    assert [r.num.text for r in rows]==["1.","2.","3."]
    assert rows[0].text.text=="Fly Sentinel Hill" and rows[0].time.text=="2 min" and rows[2].time.text==""
    assert rows[0].icon.texture=="Interface\\Icons\\Ability_Mount_Gryphon_01"
    assert rows[1].icon.texture=="Interface\\GossipFrame\\AvailableQuestIcon"
    click(rows[1])
    pin=g.eval("PINNED[1]")
    assert pin.point.map==1436 and pin.source.name=="Scout Riell"
    click(rows[2])  # no point: no pin
    assert g.eval("#PINNED")==1
    assert g.eval("PLANS[1].area")==1581


def test_route_flight_path_check_box_and_refresh_plan_again(style):
    g,R=route_game(style)
    R.show(1581,"The Deadmines")
    p=R._page()
    assume=bool(g.eval("NS.db.routeAllFlights"))
    click(p.assume)
    assert bool(g.eval("NS.db.routeAllFlights"))!=assume
    assert g.eval("#PLANS")==2 and bool(g.eval("PLANS[2].assume"))==(not assume)
    assert p.assume.tick.shown==(not assume)
    click(p.refresh)
    assert g.eval("#PLANS")==3


def test_route_page_drops_late_answers_and_works_without_the_stream_b_exports(style):
    g,R=route_game(style,r'''
    NS.dungeonQuests.routePlan=function(area,assumeAll,cb) PENDING=cb;return true end
    ''')
    R.show(1581,"The Deadmines")
    p=R._page()
    assert plain(p.summary.text)=="Planning the route…"
    late=g.eval("PENDING")
    R.hide()
    late(g.eval("{quests=1,totalSeconds=60,unknown={},notes={},steps={{kind='Walk',to='X',seconds=60}}}"),g.eval("{}"),0)
    assert shown_rows(p)==[]
    # without D.routePlan the page says so instead of failing
    g.run("NS.dungeonQuests.routePlan=nil;NS.dungeonQuests.routeStepText=nil;NS.dungeonQuests.minutes=nil")
    R.show(718,"Wailing Caverns")
    assert plain(p.summary.text)=="Route planner not available"
    # nothing to do
    g.run("NS.dungeonQuests.routePlan=function(a,s,cb) cb({nothing=true},{},0);return true end")
    R.show(1581,"The Deadmines")
    assert plain(p.summary.text)=="The Deadmines: nothing left to pick up" and shown_rows(p)==[]
    assert not g.eval("NS.db.errors")


def test_a_floor_without_art_keeps_the_floor_buttons_and_labels_the_pin(style):
    # floor 2 (292) has no art layer and no tile files: the no-map message, but floor 1 stays reachable
    g,M=map_game(style,ART+"""
GetFileIDFromPath=function(p) return nil end
C_Map.GetMapArtLayers=function(id) if id==291 then return {{layerWidth=1002,layerHeight=668,tileWidth=256,tileHeight=256}} end end
NS.dungeonQuests.entranceOf=nil
""")
    M.show(1581,"The Deadmines")
    assert M._state().mode=="art"
    click(M._state().floorButtons[2])
    s=M._state()
    assert s.mode=="none" and s.floor==2 and "No map for this dungeon" in s.message
    assert s.floorButtons[1].shown and s.floorButtons[2].shown
    assert not any(t.shown for t in s.tiles.values())
    assert plain(s.page.pin.label.text)=="Entrance unknown"
    click(s.floorButtons[1])
    s=M._state()
    assert s.mode=="art" and s.floor==1 and s.message is None and s.view.shown
    assert not g.eval("NS.db.errors")


# ===== Round 3, stream U: user-story polish =====
def test_the_map_opens_on_the_floor_you_stand_on_and_floor_buttons_explain_themselves(style):
    g,M=map_game(style,ART+"C_Map.GetBestMapForUnit=function(u) if u=='player' then return 292 end end")
    M.show(1581,"The Deadmines")
    s=M._state()
    assert s.floor==2 and list(s.tiles.values())[0].texture==292001, "inside Ironclad Cove: that floor first"
    b=s.floorButtons[1]
    b.scripts.OnEnter(b)
    assert "Floor 1 of 2" in "\n".join(g.eval("TOOLTIP.lines").values())
    # outside (another map): the first floor, as before
    g.run("C_Map.GetBestMapForUnit=function() return 1436 end")
    M.show(1581,"The Deadmines")
    assert M._state().floor==1
    assert not g.eval("NS.db.errors")


def test_a_floor_you_picked_survives_a_refresh_of_the_same_dungeon(style):
    g,M=map_game(style)
    M.show(1581,"The Deadmines")
    M.setFloor(2)
    M.refresh(); assert M._state().floor==2, "refresh keeps your floor"
    M.show(1581,"The Deadmines"); assert M._state().floor==2, "the same dungeon again"
    M.show(718,"Wailing Caverns"); M.show(1581,"The Deadmines")
    assert M._state().floor==1, "another dungeon in between: start over"
    assert not g.eval("NS.db.errors")


def test_route_page_marks_the_next_step(style):
    g,R=route_game(style)
    R.show(1581,"The Deadmines")
    p=R._page()
    rows=shown_rows(p)
    assert rows[0].isNext and not rows[1].isNext and not rows[2].isNext, "step 1 is where you go next"
    assert list(rows[0].bg.rgba.values())!=list(rows[1].bg.rgba.values())
    rows[0].scripts.OnEnter(rows[0])
    assert g.eval("TOOLTIP.text")=="Step 1 (next)"
    rows[1].scripts.OnEnter(rows[1])
    assert g.eval("TOOLTIP.text")=="Step 2"
    assert not g.eval("NS.db.errors")


def test_route_page_says_when_the_planner_failed(style):
    g,R=route_game(style,'NS.dungeonQuests.routePlan=function(area,assumeAll,cb) cb(nil,{},0,"planner broke");return true end')
    R.show(1581,"The Deadmines")
    p=R._page()
    assert plain(p.summary.text)=="Could not plan the route" and "planner broke" in p.notes.text and "Refresh" in p.notes.text
    assert shown_rows(p)==[]
    assert not g.eval("NS.db.errors")


def test_lua_files_compile(style):
    from lupa.lua51 import LuaRuntime
    lua=LuaRuntime()
    root=pathlib.Path(__file__).resolve().parent.parent/"QuestSharing"
    for name in ("DungeonMapUI.lua","DungeonRouteUI.lua"):
        ok,err=lua.eval("function(c,n) local f,e=loadstring(c,n);return f~=nil,e end")((root/name).read_text(),name)
        assert ok, err


if __name__=="__main__":
    failed=total=0
    for name,fn in sorted(list(globals().items())):
        if not name.startswith("test_"):continue
        for style in STYLES:
            total+=1
            try:fn(style);print("ok",name,style)
            except Exception as exc:failed+=1;print("FAIL",name,style,type(exc).__name__,str(exc)[:500])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
