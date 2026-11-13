"""Open on the current recognized dungeon without fighting manual navigation."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_loot import game,results,click
from test_usability import type_text,pick
STYLES=("modern","classic")
CURRENT='''IN_INSTANCE=true
CURRENT_ID,CURRENT_NAME,CURRENT_TYPE=43,"Wailing Caverns","party"
function GetInstanceInfo() return CURRENT_NAME,CURRENT_TYPE,1,"Normal",5,0,false,CURRENT_ID end
'''


def test_first_open_uses_eighth_return_id_even_when_localized_names_differ(style):
    g=game(style,CURRENT+'CURRENT_NAME="Localized dungeon"');g.slash("loot")
    assert {r[1] for r in results(g)}=={"Wailing Caverns"}
    w=g.eval("NS.loot._window()")
    assert "Wailing Caverns" in w.selection.text
    assert any(b.shown and "> " in b.text and b.place.name=="Wailing Caverns" for b in w.instances.values())


def test_reopen_refocuses_and_clears_stale_text_source_and_dungeon_search(style):
    g=game(style,CURRENT);g.slash("loot");w=g.eval("NS.loot._window()")
    click(w.all);pick(g,w.boss,"Cookie","Cookie")
    type_text(w.search,"Captain");type_text(w.instanceSearch,"deadmines");g.advance(.19)
    g.eval("NS.loot.close")();g.slash("loot");g.advance(.3)
    assert {r[1] for r in results(g)}=={"Wailing Caverns"}
    assert w.search.GetText(w.search)==w.instanceSearch.GetText(w.instanceSearch)==""
    assert "All encounters" in w.boss.text


def test_open_with_explicit_item_search_keeps_text_inside_current_dungeon(style):
    g=game(style,CURRENT);g.slash("loot Serpent")
    assert {r[0] for r in results(g)}=={10002}
    assert g.eval("NS.loot._window().search:GetText()") == "Serpent"
    g.slash("loot Captain");assert results(g)==[]


def test_manual_browse_and_all_dungeons_stay_until_next_open(style):
    g=game(style,CURRENT);g.slash("loot");w=g.eval("NS.loot._window()")
    click(next(b for b in w.instances.values() if b.place and b.place.name=="The Deadmines"))
    g.fire("GET_ITEM_INFO_RECEIVED",10001,True);g.advance(.3)
    assert {r[1] for r in results(g)}=={"The Deadmines"}
    click(w.all);assert {r[1] for r in results(g)}=={"The Deadmines","Wailing Caverns"}


def test_new_instance_on_reopen_keeps_equipment_filters_and_blue_quality_floor(style):
    g=game(style,CURRENT+'LOOT_ITEMS[10003].quality=2');g.slash("loot")
    g.eval("NS.equipmentUI.applyStat")(1,"Intellect","") # absent native stats hide everything
    g.eval("NS.loot.close")();g.run('CURRENT_ID=36;CURRENT_NAME="The Deadmines"')
    g.slash("loot")
    assert "The Deadmines" in g.eval("NS.loot._window().selection.text")
    assert g.eval("NS.equipmentUI.filters.stats[1].stat")=="Intellect" and results(g)==[]
    g.eval("NS.equipmentUI.applyStat")(1,"","")
    assert {r[0] for r in results(g)}=={10001,10005}


def test_outdoors_raid_unknown_and_missing_api_preserve_browsing(style):
    for extra in ('IN_INSTANCE=false','CURRENT_TYPE="raid"','CURRENT_ID=9999;CURRENT_NAME="Unknown"',
                  'GetInstanceInfo=nil;IsInInstance=nil', 'GetInstanceInfo=function()error("bad api")end;ZONE="Unknown"'):
        g=game(style,CURRENT+extra);g.slash("loot")
        assert len(results(g))==5,extra


def test_no_id_uses_exact_name_for_questie_fallback_and_legacy_client(style):
    g=game(style,CURRENT+'''AtlasLoot=nil;GetInstanceInfo=nil;ZONE="Wailing Caverns"
        C_Map.GetAreaInfo=function(id)if id==718 then return "Wailing Caverns" end end
        ItemDB.GetAllIds=function()return {10002}end
        QUESTIE_ITEMS[10002]={name="Staff",npcDrops={3669}}
        QUESTIE_NPCS[3669]={name="Cobrahn",spawns={[718]={{-1,-1}}}}
    ''');g.slash("loot")
    assert {r[1] for r in results(g)}=={"Wailing Caverns"}
    assert "Wailing Caverns" in g.eval("NS.loot._window().selection.text")


def test_focus_waits_for_batched_scan_but_manual_choice_cancels_it(style):
    extra=CURRENT+'''local t=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Deadmines.items[2][1]
        for i=1,250 do t[#t+1]={i,10003} end'''
    for manual in (False,True,"typing"):
        g=game(style,extra);g.slash("loot")
        assert g.eval("NS.loot._state()")[1]
        if manual=="typing":type_text(g.eval("NS.loot._window().search"),"Captain")
        elif manual:click(g.eval("NS.loot._window().all"))
        g.advance(1)
        expected={"The Deadmines"} if manual=="typing" else ({"The Deadmines","Wailing Caverns"} if manual else {"Wailing Caverns"})
        assert {r[1] for r in results(g)}==expected


def test_selected_dungeon_is_on_visible_navigation_page(style):
    g=game(style,CURRENT+'''local m=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids
        for i=1,18 do m["First"..i]={name="A dungeon "..i,InstanceID=36,items={{name="Boss",[1]={{1,10001}}}}}end''')
    g.slash("loot");g.advance(1)
    w=g.eval("NS.loot._window()")
    assert any(b.shown and b.place and b.place.name=="Wailing Caverns" for b in w.instances.values())
    assert {r[1] for r in results(g)}=={"Wailing Caverns"}


def test_shared_instance_id_uses_provider_subarea_names_to_choose_wing(style):
    g=game(style,CURRENT+'''CURRENT_ID=429;CURRENT_NAME="Dire Maul";SUBZONE="Warpwood Quarter"
        C_Map.GetAreaInfo=function(id)if id==34776 then return "Warpwood Quarter" end end
        local m=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids
        m.East={name="Dire Maul East",MapID=2557,SubAreaIDs={34776},items={{name="Boss",[1]={{1,10002}}}}}
        m.West={name="Dire Maul West",MapID=2557,items={{name="Boss",[1]={{1,10001}}}}}
    ''');g.slash("loot")
    assert {r[1] for r in results(g)}=={"Dire Maul East"}


def test_shared_id_without_wing_identity_does_not_choose_arbitrarily(style):
    g=game(style,CURRENT+'''local m=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids
        CURRENT_NAME="Shared dungeon"
        m.Other={name="Other wing",InstanceID=43,items={{name="Boss",[1]={{1,10001}}}}}
    ''');g.slash("loot")
    assert "All dungeons" in g.eval("NS.loot._window().selection.text")


def test_extra_tools_label_fits_and_existing_tab_actions_still_work(style):
    g=game(style);g.slash("settings");g.eval("NS.settingsTab")("optional")
    w=g.eval("NS._settingsWindow()")
    assert "Extra tools" in w.tabs.optional.text.text
    for tab in w.tabs.values():assert tab.frame.point[4]+tab.frame.width<=w.win.width-20
    g.run('for i,r in ipairs(NS.settingRows)do if r.label=="Search instance loot and who drops it" then NS.settingsClick(i,"LeftButton") end end')
    assert g.eval("NS.equipmentUI.visible")("dungeons")


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
