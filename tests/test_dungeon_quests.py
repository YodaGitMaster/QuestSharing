"""Dungeon membership, outside chains, independent filters and real quest-menu actions on both clients."""
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from test_optional import game as optional_game
from test_loot import click

STYLES = ("modern", "classic")
DATA = r'''
local names={[1581]="The Deadmines",[718]="Wailing Caverns",[12]="Elwynn Forest",[2717]="Molten Core"}
C_Map.GetAreaInfo=function(id) return names[id] end
QUESTIE_NPCS[900]={name="Dungeon captain",spawns={[1581]={{-1,-1}}}}
QUESTIE_NPCS[901]={name="Cavern beast",spawns={[718]={{12,20}}}}
QUESTIE_NPCS[902]={name="Raid boss",spawns={[2717]={{-1,-1}}}}
QUESTIE_OBJECTS[910]={name="Dungeon chest",spawns={[1581]={{-1,-1}}}}
QUESTIE_ITEMS[950]={name="Dungeon relic",objectDrops={910}}
QUESTIE_ITEMS[951]={name="Dropped orders",npcDrops={900}}
QUESTIE_QUESTS={
 [1]={name="Outdoor preparation",questLevel=10,startedBy={{197}}},
 [2]={name="A dungeon job",questLevel=20,requiredLevel=15,zoneOrSort=1581,startedBy={{197}},preQuestSingle={1},nextQuestInChain=3},
 [3]={name="Return outside",questLevel=20,startedBy={{197}},finishedBy={{197}},preQuestSingle={2}},
 [4]={name="Class mission",questLevel=20,requiredClasses=1024,startedBy={{197}},objectives={{{900}}}},
 [5]={name="Horde mission",questLevel=22,requiredRaces=178,startedBy={{197}},objectives={nil,nil,{{950}}}},
 [6]={name="Alliance mission",questLevel=22,requiredRaces=77,startedBy={{197}},objectives={nil,{{910}}}},
 [7]={name="Mage mission",questLevel=23,requiredClasses=128,zoneOrSort=1581,startedBy={{197}}},
 [8]={name="Cavern quest",questLevel=18,zoneOrSort=718,startedBy={{197}}},
 [9]={name="Both dungeons",questLevel=25,startedBy={{197}},objectives={{{900},{901}}}},
 [10]={name="Overworld only",questLevel=20,startedBy={{197}},objectives={{{400}}}},
 [11]={name="Raid quest",questLevel=60,startedBy={{197}},objectives={{{902}}}},
 [12]={name="Dungeon pickup",questLevel=20,startedBy={{900}}},
 [13]={name="Dungeon turn-in",questLevel=20,finishedBy={{900}}},
 [14]={name="Dungeon exploration",questLevel=20,triggerEnd={"Find room",{[1581]={{22,33}}}}},
 [15]={name="Credit objective",questLevel=20,objectives={nil,nil,nil,nil,{{{900},900}}}},
 [16]={name="Item starter",questLevel=20,startedBy={nil,nil,{951}}},
 [17]={name="High quest",questLevel=50,requiredLevel=40,zoneOrSort=1581,startedBy={{197}}},
 [18]={name="Limited level",questLevel=20,requiredLevel=10,requiredMaxLevel=19,zoneOrSort=1581},
 [19]={name="Completed quest",questLevel=20,zoneOrSort=1581},
 [20]={name="High bit faction",questLevel=20,requiredRaces=4294967296,zoneOrSort=1581},
 [21]={name="Unknown area",questLevel=20,zoneOrSort=9999},
}
FINISHED[19]=true
QUEST_ENUMS=0
QuestDB.Get=function(id,key) local r=QUESTIE_QUESTS[id];return r and r[key] end
QuestDB.GetAllIds=function()
 QUEST_ENUMS=QUEST_ENUMS+1
 local ids={};for id in pairs(QUESTIE_QUESTS) do ids[#ids+1]=id end;table.sort(ids);return ids
end
'''


def game(style, extra="", open_tab=True):
    g=optional_game(style,DATA+extra)
    if open_tab:
        g.slash("dungeons");g.advance(90)
        assert g.eval("NS.dungeonQuests._state()")[0], g.printed()
    return g


def ids(g):
    return {r.id for r in g.eval("NS.dungeonQuests._results()").values()}


def edit(box,text):
    box.SetText(box,text);box.scripts.OnTextChanged(box,True)


def filters(g, **values):
    w=g.eval("NS.dungeonQuests._window()")
    for key,value in values.items():
        if key in ("dungeon","class","faction"):
            b=w[key];b.chooseValue(value)
        else:
            raise ValueError(key)
    g.advance(.3)


def test_every_known_dungeon_quest_including_outside_preparation_and_followup(style):
    g=game(style)
    assert ids(g)==set(range(1,22))-{10,11,21}
    filters(g,dungeon=1581)
    assert ids(g)==set(range(1,22))-{8,10,11,21}
    rows={r.id:r for r in g.eval("NS.dungeonQuests._results()").values()}
    assert rows[1].dungeons[1581]=="Preparation"
    assert rows[3].dungeons[1581]=="Follow-up"
    assert rows[2].dungeons[1581] is True
    filters(g,dungeon=718)
    assert ids(g)=={8,9}
    assert g.eval("ITEM_READS")==0 and g.eval("ENUMERATIONS")==0


def test_faction_class_and_level_are_optional_independent_filters(style):
    g=game(style);filters(g,dungeon=1581,faction="Alliance",**{"class":"DRUID"})
    assert 5 not in ids(g) and 7 not in ids(g) and {4,6,17,18,20}<=ids(g)
    filters(g,faction="Horde",**{"class":"MAGE"})
    assert 4 not in ids(g) and 6 not in ids(g) and 20 not in ids(g) and {5,7}<=ids(g)
    w=g.eval("NS.dungeonQuests._window()")
    edit(w.level,"20");g.advance(.3)
    assert 17 not in ids(g) and 18 not in ids(g) and 7 in ids(g)
    edit(w.level,"19");g.advance(.3)
    assert 18 in ids(g)
    click(w.levelMode);assert 17 in ids(g)
    click(w.completed);assert 19 not in ids(g)


def test_all_quests_button_keeps_selected_dungeon_and_broadens_character_filters(style):
    g=game(style);filters(g,dungeon=1581)
    w=g.eval("NS.dungeonQuests._window()");click(w.mine)
    assert 17 not in ids(g) and 5 not in ids(g) and 7 not in ids(g)
    click(w.reset)
    assert {5,7,17,18,19}<=ids(g) and 8 not in ids(g)
    assert w.dungeon.readValue()==1581


def test_live_search_quest_id_and_dungeon_and_invalid_level(style):
    g=game(style);w=g.eval("NS.dungeonQuests._window()")
    edit(w.search,"preparation");g.advance(.3);assert ids(g)=={1}
    edit(w.search,"Wailing");g.advance(.3);assert ids(g)=={8,9}
    edit(w.search,"17");g.advance(.3);assert ids(g)=={17}
    before=ids(g)
    for text in ("abc","0","1001","2.5"):
        edit(w.level,text);g.advance(.3)
        assert ids(g)==before and "whole number" in w.status.text


def test_shared_tab_hides_equipment_filters_and_restores_them(style):
    g=game(style);host,c,p,t=g.eval("NS.equipmentUI._window()")
    assert p.dungeonQuests.shown and not c.bar.shown and not c.sort.shown and not c.hint.shown
    click(t.dungeons);g.advance(2)
    assert not p.dungeonQuests.shown and c.bar.shown and c.sort.shown and c.hint.shown
    click(t.dungeonQuests)
    assert p.dungeonQuests.shown and not c.bar.shown
    assert list(g.eval("UISpecialFrames").values()).count("QuestSharingEquipment")==1


def test_right_click_reuses_menu_and_handles_quests_not_in_log(style):
    g=game(style)
    w=g.eval("NS.dungeonQuests._window()")
    row=w.rows[1]
    row.frame.scripts.OnClick(row.frame,"RightButton")
    menu,lines=g.eval("NS._questMenu()")
    assert menu.shown and len(menu["items"])==10
    labels=[b.text for b in lines.values() if b.shown]
    assert any("Where to pick" in x for x in labels) and any("Show pickup on map" in x for x in labels)
    assert any("Trace back" in x for x in labels) and any("How to do" in x for x in labels)
    for item in menu["items"].values():
        if item.text in ("Offer it to the party","Tell the party how I am doing","Ask in chat to do this quest","Focus it on my map"):
            assert item.why=="this quest is not in your quest log"
    assert not g.eval("NS.db.errors")


def test_catalogue_actions_show_pickup_chain_objectives_without_selecting_log(style):
    g=game(style)
    g.eval("NS.dungeonQuests.menu")(2)
    menu,_=g.eval("NS._questMenu()")
    before=g.eval("SELECTED")
    item=next(x for x in menu["items"].values() if x.text=="Where to pick it up")
    item.run()
    assert "Marshal McBride" in "\n".join(g.printed()) and "48.9" in "\n".join(g.printed())
    item=next(x for x in menu["items"].values() if x.text=="Trace back the chain")
    item.run();assert "Outdoor preparation" in "\n".join(g.printed())
    item=next(x for x in menu["items"].values() if x.text=="How to do it")
    item.run();assert g.eval("SELECTED")==before
    assert not g.eval("NS.db.errors")


def test_pickup_map_places_native_waypoint_without_opening_or_redrawing_map(style):
    g=game(style)
    g.run('WAYPOINT=nil;UiMapPoint={CreateFromCoordinates=function(map,x,y)return {map=map,x=x,y=y} end};C_Map.SetUserWaypoint=function(p)WAYPOINT=p end')
    assert g.eval("NS.dungeonQuests.showPickup")(2)
    pt=g.eval("WAYPOINT")
    assert pt.map==1429 and abs(pt.x-.4892)<.0001 and abs(pt.y-.4161)<.0001
    assert len(g.eval("MAP_OPENS"))==0 and "open your world map" in "\n".join(g.printed())
    g.run("WAYPOINT=nil")
    assert not g.eval("NS.dungeonQuests.showPickup")(12) and g.eval("WAYPOINT") is None
    assert "dungeon" in "\n".join(g.printed()).lower()


def test_no_login_scan_close_combat_and_master_disable_cancel_work(style):
    g=game(style,open_tab=False)
    assert g.eval("QUEST_ENUMS")==0 and g.eval("NS.dungeonQuests._window()") is None
    g.run("InCombatLockdown=function()return true end")
    g.slash("dungeons");g.advance(10)
    assert g.eval("QUEST_ENUMS")==0
    g.run("InCombatLockdown=function()return false end");g.fire("PLAYER_REGEN_ENABLED");g.advance(.1)
    g.eval("NS.equipmentUI.close")();g.advance(10)
    assert not g.eval("NS.dataWork.busy")("dungeonQuests")
    g.slash("dungeons");g.advance(90);assert ids(g)
    g.slash("off")
    assert not g.eval("NS.equipmentUI._window()")[0].shown
    assert not g.eval("NS.dataWork.busy")("dungeonQuests")


def test_missing_enumeration_and_retry_after_provider_available(style):
    g=game(style,"QuestDB.GetAllIds=nil",False)
    g.slash("dungeons");g.advance(1)
    assert "enumerable quest" in g.eval("NS.dungeonQuests._window().status.text")
    assert not ids(g)
    g.run("QuestDB.GetAllIds=function()return {2} end")
    g.eval("NS.dungeonQuests.scan")();g.advance(10)
    assert ids(g)=={2}


def test_quest_chain_cycle_is_bounded_and_no_duplicate_result_rows(style):
    g=game(style,"QUESTIE_QUESTS[1].preQuestSingle={2};QUESTIE_QUESTS[3].nextQuestInChain=2")
    assert {1,2,3}<=ids(g)
    assert len(g.eval("NS.dungeonQuests._results()"))==len(ids(g))


def test_active_log_quest_retains_ordinary_menu_behaviour(style):
    g=game(style,'QUESTS={{id=2,title="A dungeon job",level=20,objectives={}}}')
    g.eval("NS.dungeonQuests.menu")(2)
    menu,_=g.eval("NS._questMenu()")
    ask=next(x for x in menu["items"].values() if x.text=="Ask in chat to do this quest")
    assert ask.why is None
    ask.run();assert "Anyone need" in "\n".join(str(x) for x in g.eval("OPENED").values())


def test_generic_material_sources_do_not_associate_outdoor_quests_with_dungeon(style):
    g=game(style,r'''
    QUESTIE_ITEMS[952]={name="Common wool",npcDrops={900,400}}
    QUESTIE_ITEMS[953]={name="Common thread",objectDrops={910,9}}
    QUESTIE_QUESTS[22]={name="Donate wool",objectives={nil,nil,{{952}}}}
    QUESTIE_QUESTS[23]={name="Donate thread",objectives={nil,nil,{{953}}}}
    QUESTIE_QUESTS[24]={name="Explicit dungeon task",zoneOrSort=1581,objectives={nil,nil,{{952}}}}
    ''')
    assert 22 not in ids(g) and 23 not in ids(g) and 24 in ids(g)
    filters(g,dungeon=1581)
    assert 24 in ids(g) and 22 not in ids(g) and 23 not in ids(g)


def test_expanded_catalogue_menu_buttons_work_and_ordinary_menu_shrinks_back(style):
    g=game(style);g.eval("NS.dungeonQuests.menu")(2)
    menu,lines=g.eval("NS._questMenu()")
    # The tenth line is disabled for unaccepted quests; clicking it explains why without touching the log.
    click(lines[10]);assert menu.shown and "not in your quest log" in "\n".join(g.printed())
    g.run('NS.openQuestMenu(NS.compat.findEntry(100))')
    assert len(menu["items"])==8 and not lines[9].shown and not lines[10].shown


def test_unavailable_filter_metadata_is_explained_and_all_quests_remains_usable(style):
    g=game(style,"LibQuestieDB.Enum=nil")
    assert ids(g)
    w=g.eval("NS.dungeonQuests._window()");click(w.mine)
    assert not ids(g) and "mappings are unavailable" in w.status.text
    click(w.reset);assert ids(g)


def test_closed_events_stay_idle_and_hidden_pending_search_is_applied_on_reopen(style):
    g=game(style);w=g.eval("NS.dungeonQuests._window()")
    edit(w.search,"Cavern quest")
    g.eval("NS.equipmentUI.close")();g.advance(1)
    before=g.eval("QUEST_ENUMS")
    for _ in range(5):g.fire("QUEST_LOG_UPDATE")
    g.slash("dungeons")
    assert ids(g)=={8} and g.eval("QUEST_ENUMS")==before


HOVER_DATA=r'''
QUESTIE_QUESTS[2].finishedBy={{400}}
local supportGet=LibQuestieDB.Support.Get
LibQuestieDB.Support.Get=function(name)
 if name=="QuestXP" then return {db={[2]={20,2000},[19]={20,0}}} end
 return supportGet(name)
end
REWARD_ITEMS[810]={name="Reward staff",class=2,subClass=10,itemLevel=25,requiredLevel=0,questRewards={2,2},quality=3}
REWARD_ITEMS[811]={name="Plain material reward",class=7,subClass=0,itemLevel=1,requiredLevel=0,questRewards={2},quality=1}
'''


def hover(g, qid=2):
    name=g.eval("NS.questie.get")("quest",qid,"name")
    w=g.eval("NS.dungeonQuests._window()")
    edit(w.search,name);g.advance(.3)
    row=next(row for row in w.rows.values() if row.result and row.result.id==qid)
    row.frame.scripts.OnEnter(row.frame)
    return row


def tooltip(g):
    return "\n".join(g.eval("TOOLTIP.lines").values())


def test_rows_show_distinct_pickup_and_turnin_locations(style):
    g=game(style,HOVER_DATA);row=hover(g)
    assert "Pickup:" in row.pickup.text and "Marshal McBride" in row.pickup.text and "48.9" in row.pickup.text
    assert "Turn-in:" in row.turnIn.text and "Kobold Miner" in row.turnIn.text and "60.0" in row.turnIn.text
    assert row.pickup.wordWrap is False and row.turnIn.wordWrap is False
    assert "Kobold Miner" in g.eval("NS.dungeonQuests._window().detailsText.text")


def test_hover_shows_base_xp_and_all_item_rewards_even_non_equipment(style):
    g=game(style,HOVER_DATA)
    assert g.eval("ENUMERATIONS")==0
    hover(g)
    assert "XP: 2000 (base)" in tooltip(g) and "loading" in tooltip(g)
    g.advance(30)
    text=tooltip(g)
    assert "choices may apply" in text and "Reward staff" in text and "Plain material reward" in text
    assert text.count("Reward staff")==1 and "before character-level and bonus" in text
    assert "Marshal McBride" in text and "Kobold Miner" in text
    assert g.eval("ENUMERATIONS")==1
    hover(g);g.advance(1);assert g.eval("ENUMERATIONS")==1


def test_zero_xp_is_distinct_from_unknown_and_empty_rewards_do_not_claim_none_exist(style):
    g=game(style,HOVER_DATA);hover(g,19);g.advance(30)
    assert "XP: 0 (base)" in tooltip(g) and "No item rewards listed" in tooltip(g)
    hover(g,18)
    assert "XP: unknown" in tooltip(g) and "XP: 0" not in tooltip(g)


def test_missing_item_catalogue_keeps_locations_and_xp_usable(style):
    g=game(style,HOVER_DATA+'ItemDB.GetAllIds=nil')
    row=hover(g);g.advance(1)
    assert "Item rewards: unavailable" in tooltip(g) and "XP: 2000" in tooltip(g)
    assert "Marshal McBride" in row.pickup.text and "Kobold Miner" in row.turnIn.text
    assert not g.eval("NS.db.errors")


def test_hover_reward_scan_pauses_in_combat_and_cancels_on_close(style):
    g=game(style,HOVER_DATA)
    g.run("InCombatLockdown=function()return true end")
    hover(g);g.advance(1)
    assert g.eval("ENUMERATIONS")==0 and g.eval("NS.dataWork.busy")("dungeonQuestRewards")
    g.eval("NS.equipmentUI.close")();g.advance(2)
    assert not g.eval("NS.dataWork.busy")("dungeonQuestRewards") and not g.eval("TOOLTIP.shown")
    g.run("InCombatLockdown=function()return false end");g.fire("PLAYER_REGEN_ENABLED")
    g.slash("dungeons");hover(g);g.advance(30)
    assert "Reward staff" in tooltip(g) and g.eval("ENUMERATIONS")==1


def test_leaving_row_does_not_reopen_tooltip_after_async_rewards_or_item_event(style):
    g=game(style,HOVER_DATA);row=hover(g)
    row.frame.scripts.OnLeave(row.frame)
    g.advance(30);g.fire("GET_ITEM_INFO_RECEIVED",810)
    assert not g.eval("TOOLTIP.shown")


def test_expanded_location_rows_fit_page_and_page_navigation_still_works(style):
    g=game(style,HOVER_DATA);w=g.eval("NS.dungeonQuests._window()")
    assert len(w.rows)==6
    for row in w.rows.values():assert row.frame.height==84 and row.edge.height==84
    assert g.eval("NS.dungeonQuests.go")(1)
    assert w.rows[1].result and w.rows[1].pickup.text.startswith("Pickup:")


def test_legacy_xp_module_fallback_and_multiple_locations_remain_visible(style):
    g=game(style,HOVER_DATA+r'''
    local supportGet=LibQuestieDB.Support.Get
    LibQuestieDB.Support.Get=function(name)if name~="QuestXP" then return supportGet(name)end end
    QuestieLoader={ImportModule=function(_,name)if name=="QuestXP" then return {db={[2]={20,1250}}} end end}
    QUESTIE_QUESTS[2].startedBy={{197,400}}
    QUESTIE_QUESTS[2].finishedBy={{400,197}}
    ''')
    row=hover(g)
    assert "XP: 1250 (base)" in tooltip(g)
    assert "+1 more" in row.pickup.text and "+1 more" in row.turnIn.text
    assert "Marshal McBride" in tooltip(g) and "Kobold Miner" in tooltip(g)


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
