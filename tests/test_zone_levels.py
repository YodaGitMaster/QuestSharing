"""Read-only map ranges from native data and verified standalone zone guides."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from harness import Game
from test_questmap import DATA as MAP_DATA
STYLES=("modern","classic")
DATA=MAP_DATA+r'''
Enum=Enum or {};Enum.UIMapType={Cosmic=0,World=1,Continent=2,Zone=3,Dungeon=4,Micro=5}
MAP_INFO={
 [947]={mapID=947,name="Azeroth",mapType=1},[1415]={mapID=1415,name="Eastern Kingdoms",mapType=2},
 [1429]={mapID=1429,name="Elwynn Forest",mapType=3},[1436]={mapID=1436,name="Westfall",mapType=3},
 [2001]={mapID=2001,name="Forever Coast",mapType=3},[2002]={mapID=2002,name="Unknown Reach",mapType=3},
 [2003]={mapID=2003,name="Dungeon",mapType=4},
}
MAP_LEVELS={[1429]={1,10,5,9},[1436]={10,20,1,2},[2001]={45,60},[2002]={0,0},[2003]={15,25}}
RECTS={[1429]={.1,.3,.2,.4},[1436]={.35,.55,.5,.7},[2001]={.6,.8,.3,.5},[2002]={.7,.9,.6,.8}}
NATIVE_READS,CHILD_READS,HOVER_READS=0,0,0
C_Map.GetMapInfo=function(id)return MAP_INFO[id]end
C_Map.GetMapLevels=function(id)
 NATIVE_READS=NATIVE_READS+1;local t=MAP_LEVELS[id];if t then return unpack(t)end
end
C_Map.GetMapChildrenInfo=function(id,kind,descendants)
 CHILD_READS=CHILD_READS+1;assert(kind==3 and descendants==true)
 if id==1415 then return {MAP_INFO[1429],MAP_INFO[1436],MAP_INFO[2001],MAP_INFO[2002]}end
 return {}
end
C_Map.GetMapRectOnMap=function(child,parent)local r=RECTS[child];if r and parent==1415 then return unpack(r)end end
C_Map.GetMapInfoAtPosition=function(map,x,y)HOVER_READS=HOVER_READS+1;return MAP_INFO[HOVER_MAP]end
function WorldMapFrame:GetNormalizedCursorPosition()return CURSOR_X,CURSOR_Y end
NATIVE_WRITES=0
function WorldMapFrame:SetMapID()NATIVE_WRITES=NATIVE_WRITES+1;error("must not navigate the native map")end
function WorldMapFrame:RefreshAllDataProviders()NATIVE_WRITES=NATIVE_WRITES+1;error("must not refresh native map pins")end
function WorldMapFrame:AddDataProvider()NATIVE_WRITES=NATIVE_WRITES+1;error("must not change native map providers")end
local old=CreateFrame
function CreateFrame(...)
 local f=old(...)
 function f:EnableMouse(value)self.mouseEnabled=value end
 return f
end
'''


def game(style,extra="",enabled=True):
    g=Game(style,DATA+extra,fresh=True);g.start();g.advance(2)
    if enabled:g.eval("NS.setSetting")("zoneLevels",True)
    return g


def show(g,map=1415):
    g.run(f'WORLDMAP_ID={map};WorldMapFrame.shown=true')
    g.eval("NS.zoneLevels.draw")()
    g.advance(1.1) # let the closed-map idle tick switch to visible-map polling
    return g.eval("NS.zoneLevels._view()")


def labels(v):
    return {p.zone.id:p for p in v.labels.values() if p.shown}


def test_default_off_requires_explicit_opt_in_even_when_map_is_open(style):
    g=game(style,enabled=False)
    assert not g.eval("NS.db.zoneLevels") and g.eval("NS.zoneLevels._view()")==None
    g.run('WORLDMAP_ID=1415;WorldMapFrame.shown=true')
    g.advance(10);assert g.eval("NATIVE_READS")==g.eval("CHILD_READS")==0
    assert g.eval("NS.zoneLevels._view()")==None
    g.eval("NS.setSetting")("zoneLevels",True)
    assert g.eval("NS.zoneLevels._view().panel.shown")


def test_continent_badges_include_classic_forever_and_unknown_ranges(style):
    g=game(style);v=show(g);p=labels(v)
    assert set(p)=={1429,1436,2001,2002}
    for id,text in ((1429,"1–10"),(1436,"10–20"),(2001,"45–60"),(2002,"?")):
        assert text in p[id].text.text
    assert "Hover a zone" in v.text.text and g.eval("NATIVE_WRITES")==0


def test_read_player_levels_not_pet_levels_and_display_selected_zone(style):
    g=game(style);v=show(g,1436)
    assert "Westfall" in v.text.text and "10–20" in v.text.text
    assert labels(v)=={} and v.panel.shown
    assert g.eval("NS.zoneLevels.range")(1436)==(10,20)


def test_hover_panel_changes_and_resets_without_changing_map_or_tooltip(style):
    g=game(style);v=show(g)
    g.run('CURSOR_X=.2;CURSOR_Y=.3;HOVER_MAP=1429');g.advance(.4)
    assert "Elwynn Forest" in v.text.text and "1–10" in v.text.text
    g.run('HOVER_MAP=2001');g.advance(.4)
    assert "Forever Coast" in v.text.text and "45–60" in v.text.text
    g.run('CURSOR_X=2');g.advance(.4)
    assert "Hover a zone" in v.text.text
    assert g.eval("WORLDMAP_ID")==1415 and g.eval("NATIVE_WRITES")==0


def test_labels_use_native_centres_and_compensate_zoom_and_resize(style):
    g=game(style);v=show(g);p=labels(v)[1429]
    assert abs(p.point[4]-200)<.001 and abs(p.point[5]+210)<.001
    g.run('WorldMapFrame.ScrollContainer.Child.scale=2;WorldMapFrame.ScrollContainer.Child.width=1200')
    g.eval("NS.zoneLevels.draw")()
    assert p.scale==.5 and abs(p.point[4]-480)<.001 and abs(p.point[5]+420)<.001


def test_overlays_are_click_through_and_do_not_restore_quest_or_minimap_symbols(style):
    g=game(style);v=show(g)
    assert v.panel.mouseEnabled is False
    for p in labels(v).values():assert p.mouseEnabled is False and not p.qpoint
    assert g.eval("NS.questMap")==None and g.eval("NS.db.questMap")==None
    assert g.eval("NATIVE_WRITES")==0


def test_disabling_option_or_master_hides_existing_badges_immediately(style):
    for key in ("zoneLevels","enabled"):
        g=game(style);v=show(g);g.eval("NS.setSetting")(key,False)
        assert not v.panel.shown and labels(v)=={}
        reads=g.eval("NATIVE_READS");g.advance(3);assert g.eval("NATIVE_READS")==reads
        g.eval("NS.setSetting")(key,True);assert v.panel.shown and len(labels(v))==4


def test_map_close_reopen_map_change_and_world_view_clear_stale_badges(style):
    g=game(style);v=show(g)
    g.run('WorldMapFrame.shown=false');g.advance(.4)
    assert not v.panel.shown and labels(v)=={}
    show(g,1429);assert "Elwynn Forest" in v.text.text and labels(v)=={}
    show(g,947);assert "Choose a continent" in v.text.text and labels(v)=={}
    show(g,1415);assert len(labels(v))==4


def test_dungeon_ranges_are_not_presented_as_outdoor_questing(style):
    g=game(style);v=show(g,2003)
    assert "outdoor zones" in v.text.text and "15–25" not in v.text.text and labels(v)=={}


def test_missing_level_api_or_data_has_explicit_unknown_state_and_recovers(style):
    for extra in ('C_Map.GetMapLevels=nil','C_Map.GetMapLevels=function()error("not ready")end'):
        g=game(style,extra);v=show(g,2002)
        assert "range unavailable" in v.text.text
        g.run('C_Map.GetMapLevels=function()return 1,10 end');g.advance(2.2)
        assert "1–10" in v.text.text


def test_malformed_ranges_rectangles_duplicate_children_are_not_invented(style):
    g=game(style,'''MAP_LEVELS[1429]={20,10};MAP_LEVELS[1436]={-1,20};MAP_LEVELS[2001]={1.5,60}
        RECTS[2002]={-1,.2,0,.4}
        local old=C_Map.GetMapChildrenInfo
        C_Map.GetMapChildrenInfo=function(...)local t=old(...);t[#t+1]=MAP_INFO[1429];t[#t+1]=42;return t end''')
    v=show(g)
    assert set(labels(v))=={1429,1436,2001}
    assert "1–12" in labels(v)[1429].text.text and "10–20" in labels(v)[1436].text.text
    assert "?" in labels(v)[2001].text.text  # Invalid metadata never invents a range for unknown maps.
    for id in (0,-1,1.5):assert g.eval("NS.zoneLevels.range")(id)==None


def test_unknown_child_levels_retry_after_loading_and_cache_refreshes_on_level_up(style):
    g=game(style);v=show(g)
    g.run('MAP_LEVELS[2002]={30,40}');g.advance(2.3)
    assert "30–40" in labels(v)[2002].text.text
    g.run('MAP_LEVELS[2002]={35,45}');g.fire('PLAYER_LEVEL_UP',35)
    assert "35–45" in labels(v)[2002].text.text


def test_late_map_loading_and_canvas_replacement_hide_old_view(style):
    g=game(style,'SAVED_MAP=WorldMapFrame;WorldMapFrame=nil')
    assert g.eval("NS.zoneLevels._view()")==None
    g.run('WorldMapFrame=SAVED_MAP');old=show(g)
    g.run('WorldMapFrame.ScrollContainer.Child=CreateFrame("Frame");WorldMapFrame.ScrollContainer.Child.width=1000;WorldMapFrame.ScrollContainer.Child.height=700')
    g.eval("NS.zoneLevels.draw")();new=g.eval("NS.zoneLevels._view()")
    assert not old.panel.shown and labels(old)=={} and new.panel.shown and len(labels(new))==4


def test_provider_data_stays_unchanged_and_valid_ranges_are_cached(style):
    g=game(style);show(g,1429)
    before=g.eval("NATIVE_READS")
    for _ in range(3):g.eval("NS.zoneLevels.draw")()
    assert g.eval("NATIVE_READS")==before
    assert g.eval("MAP_LEVELS[1429][1]")==1 and g.eval("MAP_INFO[1429].name")=="Elwynn Forest"


def test_extra_tools_toggle_fits_settings_and_saved_false_stays_false(style):
    g=game(style);g.slash('settings');g.eval('NS.settingsTab')('optional')
    w=g.eval('NS._settingsWindow()');assert w.bottom<w.win.height-30
    g.run('for i,r in ipairs(NS.settingRows)do if r.key=="zoneLevels"then NS.settingsClick(i,"LeftButton")end end')
    assert not g.eval('QuestSharingDB.zoneLevels')
    h=Game(style,DATA,fresh=True);h.run('QuestSharingDB={zoneLevels=false,dbVersion=3}');h.start()
    assert not h.eval('NS.db.zoneLevels')


def test_old_default_is_switched_off_once_then_explicit_opt_in_survives_reload(style):
    g=Game(style,DATA,fresh=True)
    g.run('QuestSharingDB={zoneLevels=true,dbVersion=3}')
    g.start();assert not g.eval('NS.db.zoneLevels')
    assert g.eval('QuestSharingDB.zoneLevelsOptInMigrated')
    g.eval('NS.setSetting')('zoneLevels',True)
    g.fire('ADDON_LOADED','QuestSharing')
    assert g.eval('NS.db.zoneLevels') and g.eval('QuestSharingDB.zoneLevelsOptInMigrated')


def test_reset_returns_optional_ranges_to_off_without_repeating_migration(style):
    g=game(style);assert g.eval('NS.db.zoneLevels')
    g.eval('NS.resetSettings')();assert not g.eval('NS.db.zoneLevels')
    assert g.eval('QuestSharingDB.zoneLevelsOptInMigrated')
    g.eval('NS.setSetting')('zoneLevels',True);g.fire('ADDON_LOADED','QuestSharing')
    assert g.eval('NS.db.zoneLevels')


def test_zero_client_ranges_still_show_known_zone_guides_across_the_map(style):
    g=game(style,'C_Map.GetMapLevels=function()return 0,0 end');v=show(g)
    assert "1–12" in labels(v)[1429].text.text and "10–20" in labels(v)[1436].text.text
    v=show(g,1436)
    assert "Zone guide" in v.text.text and "10–20" in v.text.text


def test_guide_fallback_handles_absent_throwing_and_invalid_native_api(style):
    for extra in ('C_Map.GetMapLevels=nil','C_Map.GetMapLevels=function()error("not ready")end',
                  'C_Map.GetMapLevels=function()return 0,0 end','C_Map.GetMapLevels=function()return 20,10 end'):
        g=game(style,extra);v=show(g,1429)
        assert "1–12" in v.text.text and "Zone guide" in v.text.text


def test_native_range_can_replace_a_fallback_without_clearing_cache(style):
    g=game(style,'MAP_LEVELS[1429]={0,0}');show(g,1429)
    assert g.eval('NS.zoneLevels.range(1429)')[:2]==(1,12)
    g.run('MAP_LEVELS[1429]={1,10}');g.advance(.4)
    assert "1–10" in g.eval('NS.zoneLevels._view().text.text')
    assert "Zone guide" not in g.eval('NS.zoneLevels._view().text.text')


def test_all_standard_questing_zone_ids_have_standalone_fallbacks(style):
    g=game(style,'C_Map.GetMapLevels=nil;LibQuestieDB=nil;QuestieLoader=nil')
    # Outdoor questing maps; continents, cities, sanctuary and instances are not leveling brackets.
    maps=[1411,1412,1413,*range(1416,1450),1451,1452]
    for map_id in maps:
        value=g.eval('NS.zoneLevels.range')(map_id)
        assert value is not None and 1<=value[0]<=value[1]<=60,map_id
    assert g.eval('NS.zoneLevels.range')(99999) is None


def test_forever_fallbacks_use_real_ui_map_ids_and_label_known_quest_spans(style):
    g=game(style,'C_Map.GetMapLevels=nil')
    for map_id,name,low,high,source in ((2521,"Zephras Isle",1,12,"Zone guide"),
            (2548,"Riverglades",35,45,"Zone guide"),(2482,"Mount Hyjal",56,60,"Known quests"),
            (2652,"Shen'dralas",38,43,"Known quests")):
        g.run(f'MAP_INFO[{map_id}]={{mapID={map_id},name="{name}",mapType=3}}')
        v=show(g,map_id)
        assert f"{low}–{high}" in v.text.text and source in v.text.text,(map_id,v.text.text)
    # AreaTable IDs are not UI map IDs and must never accidentally select a range.
    assert g.eval('NS.zoneLevels.range')(16593) is None


def test_city_and_sanctuary_maps_are_labeled_instead_of_unknown_levels(style):
    g=game(style,'C_Map.GetMapLevels=function()return 0,0 end')
    for map_id,name,kind in ((1453,"Stormwind City","City"),(1454,"Orgrimmar","City"),
            (1455,"Ironforge","City"),(1456,"Thunder Bluff","City"),(1457,"Darnassus","City"),
            (1458,"Undercity","City"),(1450,"Moonglade","Sanctuary")):
        g.run(f'MAP_INFO[{map_id}]={{mapID={map_id},name="{name}",mapType=3}}')
        v=show(g,map_id)
        assert kind in v.text.text and "unavailable" not in v.text.text


def test_fallback_uses_map_ids_with_localized_names_and_leaves_unknown_data_unknown(style):
    g=game(style,'C_Map.GetMapLevels=nil;MAP_INFO[1429].name="Forêt d’Elwynn"')
    v=show(g,1429)
    assert "1–12" in v.text.text and "Forêt d’Elwynn" in v.text.text
    v=show(g,2002);assert "range unavailable" in v.text.text
    assert g.eval('NS.zoneLevels.range')(2002) is None and g.eval('NATIVE_WRITES')==0


def test_entire_known_world_map_has_readable_badges_when_client_returns_zero(style):
    g=game(style,'''C_Map.GetMapLevels=function()return 0,0 end
        C_Map.GetMapChildrenInfo=function()
            local out={};local ids={1411,1412,1413,1450,1451,1452,1453,1454,1455,1456,1457,1458,2482,2521,2548,2652}
            for id=1416,1449 do ids[#ids+1]=id end
            for i,id in ipairs(ids) do
                MAP_INFO[id]={mapID=id,name="Zone "..id,mapType=3};out[#out+1]=MAP_INFO[id]
                local x,y=((i-1)%10)/10,math.floor((i-1)/10)/5
                RECTS[id]={x,x+.08,y,y+.15}
            end
            return out
        end''')
    v=show(g);p=labels(v)
    assert len(p)==50 and all("?" not in badge.text.text for badge in p.values())
    assert "City" in p[1453].text.text and "Sanctuary" in p[1450].text.text
    assert g.eval('NATIVE_WRITES')==0 and all(not badge.mouseEnabled for badge in p.values())


if __name__=="__main__":
    total=failed=0
    for name,fn in sorted(list(globals().items())):
        if not name.startswith("test_"):continue
        for style in STYLES:
            total+=1
            try:fn(style);print("ok",name,style)
            except Exception as e:failed+=1;print("FAIL",name,style,type(e).__name__,str(e)[:700])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
