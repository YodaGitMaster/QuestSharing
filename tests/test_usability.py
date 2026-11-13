"""Equipment workflows: direct choices, live search, scrolling, selection and recovery."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_loot import game as loot_game,results,click,key
from test_optional import game as quest_game,ids
from test_equipment import controls
STYLES=("modern","classic")


def type_text(box,text):
    box.SetText(box,text);box.scripts.OnTextChanged(box,True)


def pick(g,button,value,search=""):
    click(button);menu=g.eval("NS.equipmentUI._menu()")
    if search:type_text(menu.search,search)
    for row in menu.rows.values():
        if row.shown:
            entry=row.entry
            candidate=entry if isinstance(entry,str) else entry.value
            if candidate==value:
                click(row);return
    raise AssertionError(f"option {value} not visible")


def selected(rows):
    return next((r for r in rows.values() if r.selected and r.result),None)


def many_quests(style):
    return quest_game(style,'''for id=9000,9017 do
            QUESTIE_QUESTS[id]={name="Route "..id,requiredLevel=15,questLevel=20,startedBy={{197}}}
            REWARD_ITEMS[id]={name="Staff "..id,class=2,subClass=10,itemLevel=25,requiredLevel=18,
                questRewards={id},loc="INVTYPE_2HWEAPON"}
        end''')


def test_searchable_direct_filters_choose_subtype_and_slot_without_cycling(style):
    g=loot_game(style);g.slash("loot");_,c,_,_=controls(g)
    pick(g,c.category,"Weapons");pick(g,c.subtype,"Staves","stav")
    assert {r[0] for r in results(g)}=={10002}
    pick(g,c.slot,"Ranged","rang");assert results(g)==[]
    pick(g,c.category,"Armor")
    assert g.eval("NS.equipmentUI.filters.slot")=="All slots"
    pick(g,c.subtype,"Cloth")
    assert {r[0] for r in results(g)}=={10005}


def test_quest_class_and_faction_are_direct_searchable_choices(style):
    g=quest_game(style);g.slash("rewards");w=g.eval("NS.rewards._window()")
    pick(g,w.controls[1],"WARRIOR","warrior")
    assert (802,8002) in ids(g)
    assert "Warrior" in w.controls[1].text
    pick(g,w.controls[2],"Horde")
    assert (803,8003) in ids(g) and (800,8000) not in ids(g)


def test_live_search_debounces_both_tabs_without_enter(style):
    g=loot_game(style);g.slash("loot");w=g.eval("NS.loot._window()")
    type_text(w.search,"Cookie");g.advance(0.1);assert len(results(g))==4
    type_text(w.search,"Serpent");g.advance(0.19)
    assert {r[0] for r in results(g)}=={10002}
    q=quest_game(style);q.slash("rewards");qw=q.eval("NS.rewards._window()")
    type_text(qw.search,"healing");q.advance(0.19)
    assert ids(q)==[(801,8001)]


def test_live_dungeon_search_clear_and_source_selection(style):
    g=loot_game(style);g.slash("loot");w=g.eval("NS.loot._window()")
    type_text(w.instanceSearch,"caverns");g.advance(0.19)
    assert w.instances[1].place.name=="Wailing Caverns" and not w.instances[2].shown
    click(w.instances[1]);assert {r[0] for r in results(g)}=={10002}
    click(w.clearInstanceSearch);assert w.instances[2].shown
    _,c,_,_=controls(g);click(c.reset)
    pick(g,w.boss,"Cookie","cook")
    assert {r[0] for r in results(g)}=={10003}


def test_reset_recovers_from_combined_search_dungeon_source_and_type_filters(style):
    g=loot_game(style);g.slash("loot");w=g.eval("NS.loot._window()")
    g.eval("NS.loot.search")("",key(g,"The Deadmines"),None)
    pick(g,w.boss,"Cookie")
    type_text(w.search,"impossible");g.advance(0.19)
    assert results(g)==[] and "Clear filters" in w.detailsText.text
    click(controls(g)[1].reset)
    assert len(results(g))==4 and w.search.GetText(w.search)=="" and w.boss.text=="Source: All encounters"
    assert selected(w.rows) is not None and "Source:" in w.detailsText.text


def test_search_clear_and_escape_work_immediately(style):
    g=quest_game(style);g.slash("rewards");w=g.eval("NS.rewards._window()")
    type_text(w.search,"no such reward");g.advance(0.19);assert ids(g)==[]
    click(w.clearSearch);assert len(ids(g))==2
    type_text(w.search,"healing");w.search.scripts.OnEnterPressed(w.search)
    assert ids(g)==[(801,8001)]
    w.search.scripts.OnEscapePressed(w.search);assert len(ids(g))==2


def test_sorting_and_my_level_shortcut_apply_to_both_tabs(style):
    g=loot_game(style,'function UnitLevel() return 15 end');g.slash("loot");_,c,_,_=controls(g)
    assert results(g)[0][0]==10001
    pick(g,c.sort,"Lowest required level");assert results(g)[0][0]==10003
    pick(g,c.sort,"Name A–Z");assert results(g)[0][0]==10001
    click(c.mine)
    assert g.eval("NS.equipmentUI.filters.max")==g.eval('UnitLevel("player")')
    assert g.eval("NS.equipmentUI.filters.mode")=="Required level"
    assert 10001 not in {r[0] for r in results(g)} and {10002,10003,10005}.issubset(r[0] for r in results(g))
    q=quest_game(style);q.slash("rewards")
    pick(q,controls(q)[1].sort,"Lowest required level");assert ids(q)[0]==(801,8001)


def test_details_auto_select_and_keep_user_selection_after_cache_refresh(style):
    g=loot_game(style);g.slash("loot");w=g.eval("NS.loot._window()")
    assert selected(w.rows).result.itemID==10001 and "Captain's Blade" in w.detailsText.text
    chosen=next(r for r in w.rows.values() if r.result and r.result.itemID==10003);click(chosen.frame)
    g.fire("GET_ITEM_INFO_RECEIVED",10001,True);g.advance(0.3)
    assert selected(w.rows).result.itemID==10003 and "Cookie's Ladle" in w.detailsText.text
    q=quest_game(style);q.slash("rewards");qw=q.eval("NS.rewards._window()")
    click(qw.rows[2].frame);q.fire("GET_ITEM_INFO_RECEIVED",800,True);q.advance(0.3)
    assert selected(qw.rows).result.itemID==801 and "Healing Robe" in qw.route.text


def test_results_scroll_and_arrow_navigation_stop_at_boundaries(style):
    g=many_quests(style);g.slash("rewards");w=g.eval("NS.rewards._window()")
    first=selected(w.rows).result.questID
    assert w.prev.disabled
    w.search.scripts.OnArrowPressed(w.search,"UP");assert selected(w.rows).result.questID==first
    w.rows[1].frame.scripts.OnMouseWheel(w.rows[1].frame,-1)
    assert selected(w.rows).result.questID!=first and not w.prev.disabled
    current=selected(w.rows).result.questID
    w.search.scripts.OnArrowPressed(w.search,"DOWN")
    assert selected(w.rows).result.questID!=current
    w.list.scripts.OnMouseWheel(w.list,1);assert selected(w.rows).result.questID==first


def test_dungeon_navigation_scrolls_without_changing_selected_dungeon(style):
    g=loot_game(style,'''local m=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids
        for i=1,19 do m["Extra"..i]={name="Dungeon "..i,InstanceID=36,items={{name="Boss",[1]={{1,10001}}}}} end''')
    g.slash("loot");g.advance(0.5);w=g.eval("NS.loot._window()")
    first=w.instances[1].place.key
    w.dungeonList.scripts.OnMouseWheel(w.dungeonList,-1)
    assert w.instances[1].place.key!=first
    w.instances[1].scripts.OnMouseWheel(w.instances[1],1)
    assert w.instances[1].place.key==first


def test_dropdown_keyboard_escape_and_single_popup_survive_live_refresh(style):
    g=loot_game(style);g.slash("loot");_,c,_,_=controls(g)
    click(c.slot);menu=g.eval("NS.equipmentUI._menu()")
    g.fire("GET_ITEM_INFO_RECEIVED",10001,True);g.advance(0.3)
    assert menu.frame.shown
    type_text(menu.search,"chest");menu.search.scripts.OnEnterPressed(menu.search)
    assert not menu.frame.shown and {r[0] for r in results(g)}=={10005}
    click(c.slot);again=g.eval("NS.equipmentUI._menu()")
    type_text(again.search,"not an option");assert "No matching options" in again.status.text
    again.search.scripts.OnEscapePressed(again.search);assert not again.frame.shown
    assert list(g.eval("UISpecialFrames").values()).count("QuestSharingEquipment")==1


def test_live_character_level_and_invalid_input_preserve_valid_context(style):
    g=quest_game(style);g.slash("rewards");w=g.eval("NS.rewards._window()")
    type_text(w.level,"10");g.advance(0.19);assert ids(g)==[]
    type_text(w.level,"20");g.advance(0.19);assert len(ids(g))==2
    type_text(w.level,"oops");g.advance(0.19)
    assert len(ids(g))==2 and "Character level must" in w.status.text
    w.level.scripts.OnEscapePressed(w.level)
    assert w.level.GetText(w.level)=="20" and "Character level must" not in w.status.text


def test_pending_live_search_survives_tab_return_without_hidden_requests(style):
    g=loot_game(style);g.slash("loot");w=g.eval("NS.loot._window()")
    type_text(w.search,"Cookie");g.slash("rewards");g.advance(0.3)
    before=g.eval("LOOT_READS");g.advance(1);assert g.eval("LOOT_READS")==before
    g.slash("loot");assert {r[0] for r in results(g)}=={10003}


def test_apply_cancels_pending_range_refresh_so_scrolling_does_not_jump_back(style):
    g=many_quests(style);g.slash("rewards");w=g.eval("NS.rewards._window()");_,c,_,_=controls(g)
    type_text(c.max,"20");click(c.apply)
    w.list.scripts.OnMouseWheel(w.list,-1)
    chosen=selected(w.rows).result.questID
    assert not w.prev.disabled
    g.advance(0.3)
    assert selected(w.rows).result.questID==chosen and not w.prev.disabled


def test_dropdown_wheel_keeps_enter_target_visible(style):
    g=loot_game(style);g.slash("loot");_,c,_,_=controls(g)
    click(c.slot);menu=g.eval("NS.equipmentUI._menu()")
    menu.frame.scripts.OnMouseWheel(menu.frame,-1)
    top=menu.rows[1].entry
    menu.search.scripts.OnEnterPressed(menu.search)
    assert g.eval("NS.equipmentUI.filters.slot")==top


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
