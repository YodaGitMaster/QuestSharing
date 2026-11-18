"""Dungeon membership, outside chains, independent filters and real quest-menu actions on both clients."""
import pathlib
import re
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


def plain(text):  # the text without |cAARRGGBB ... |r colour codes
    return re.sub(r"\|c%s|\|r" % ("[0-9a-fA-F]"*8), "", text)


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


def test_quest_log_update_keeps_open_menu_until_its_quest_leaves_results(style):
    # Regression: QUEST_LOG_UPDATE -> D.refresh() -> closeQuestMenu() shut the right-click menu 0.2 s after any log change.
    g=game(style);w=g.eval("NS.dungeonQuests._window()")
    click(w.completed);assert 19 not in ids(g)  # "Hiding completed": finishing a quest removes it from the results
    row=w.rows[1];qid=row.result.id;other=w.rows[2].result.id
    row.frame.scripts.OnClick(row.frame,"RightButton")
    menu,_=g.eval("NS._questMenu()")
    assert menu.shown and menu.entry.questID==qid
    g.fire("QUEST_LOG_UPDATE");g.advance(.3)
    assert menu.shown, "an unrelated quest-log update must not close the menu"
    g.run(f"FINISHED[{other}]=true");g.fire("QUEST_LOG_UPDATE");g.advance(.3)
    assert other not in ids(g) and qid in ids(g) and menu.shown, "another quest leaving keeps this quest's menu"
    g.run(f"FINISHED[{qid}]=true");g.fire("QUEST_LOG_UPDATE");g.advance(.3)
    assert qid not in ids(g) and not menu.shown, "the menu closes once its quest leaves the results"
    # User-driven refreshes (filters, paging) still close the menu as before.
    g.eval("NS.dungeonQuests.menu")(w.rows[1].result.id);assert menu.shown
    click(w.completed);assert not menu.shown
    assert not g.eval("NS.db.errors")


def test_quest_log_update_leaves_menus_from_other_windows_alone(style):
    g=game(style)
    g.run('NS.openQuestMenu(NS.compat.findEntry(100))')
    menu,_=g.eval("NS._questMenu()");assert menu.shown
    g.fire("QUEST_LOG_UPDATE");g.advance(.3)
    assert menu.shown


def test_kept_menu_acts_on_its_own_quest_after_the_log_shifts(style):
    # Regression (classic): a menu kept open through QUEST_LOG_UPDATE kept the old quest-log index, so
    # "Offer it to the party" pushed whichever quest had moved into that slot (here 200 instead of 2).
    g=game(style,'table.insert(QUESTS,{id=2,title="A dungeon job",level=20,objectives={}})')
    g.slash("auto off");g.join_party(["Anna"]);g.advance(1)  # auto off: no automatic share round of the new quest
    g.eval("NS.dungeonQuests.menu")(2)
    menu,lines=g.eval("NS._questMenu()")
    assert menu.shown and menu.entry.questID==2 and menu.entry.index==7
    def offer():
        g.run("PUSHED={}")
        b=next(b for b in lines.values() if b.shown and "Offer it to the party" in b.text)
        b.scripts.OnClick(b,"LeftButton")
        return g.pushed()
    g.run('table.insert(QUESTS,2,{id=300,title="Inserted above",level=5,objectives={}})')
    g.fire("QUEST_LOG_UPDATE");g.advance(.3)
    assert menu.shown and menu.entry.index==8
    assert offer()==[2]
    g.advance(15)  # let the share round from the first offer end
    g.eval("NS.dungeonQuests.menu")(2);assert menu.shown and menu.entry.index==8
    g.run("table.remove(QUESTS,2);table.remove(QUESTS,2)")  # two quests above it leave: index 8 would be past the end
    g.fire("QUEST_LOG_UPDATE");g.advance(.3)
    assert menu.shown and menu.entry.index==6
    assert offer()==[2]
    # Abandoning it keeps the quest in the results as a catalogue quest, but the menu's log actions no longer apply.
    g.eval("NS.dungeonQuests.menu")(2);assert menu.shown
    g.run("table.remove(QUESTS,6)");g.fire("QUEST_LOG_UPDATE");g.advance(.3)
    assert 2 in ids(g) and not menu.shown
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
    # Closing keeps the partial scan paused (no work while hidden); reopening resumes it without re-enumerating.
    assert g.eval("NS.dungeonQuests._state()")[1] and g.eval("QUEST_ENUMS")==1
    g.slash("dungeons");g.advance(90);assert ids(g) and g.eval("QUEST_ENUMS")==1
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
    assert len(w.rows)==5
    for row in w.rows.values():assert row.frame.height==102 and row.edge.height==102
    assert g.eval("NS.dungeonQuests.go")(1)
    assert w.rows[1].result and plain(w.rows[1].pickup.text).startswith("Pickup:")


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


def test_talk_only_and_chain_labels_are_separate_on_same_quest(style):
    g=game(style,HOVER_DATA);filters(g,dungeon=1581)
    row=hover(g,3)
    assert "Chain quest: follow-up" in row['from'].text
    assert "Talk only" in row.task.text and "Marshal McBride" in row.task.text
    assert "Previous chain quests:" in tooltip(g) and "A dungeon job (2)" in tooltip(g)
    assert "Talk only" in tooltip(g)


def test_chain_start_is_recognised_by_incoming_prerequisite_link(style):
    g=game(style,HOVER_DATA);filters(g,dungeon=1581)
    row=hover(g,1)
    assert "Chain quest: prerequisite" in row['from'].text
    assert "Next chain quests:" in tooltip(g) and "A dungeon job (2)" in tooltip(g)
    assert "Task unknown" in row.task.text


def test_standalone_dungeon_kill_quest_has_work_label_not_talk_only(style):
    g=game(style,HOVER_DATA);row=hover(g,4)
    assert "Standalone quest" in row['from'].text and "Defeat enemies" in row.task.text
    assert "Talk only" not in row.task.text


def test_events_items_and_exploration_are_not_mislabelled_talk_only(style):
    g=game(style,HOVER_DATA+r'''
    QUESTIE_QUESTS[22]={name="Escort event",zoneOrSort=1581,specialFlags=3,finishedBy={{197}}}
    QUESTIE_QUESTS[23]={name="Hidden collection",zoneOrSort=1581,requiredSourceItems={950},finishedBy={{197}}}
    QUESTIE_QUESTS[24]={name="Given letter",zoneOrSort=1581,sourceItemId=951,finishedBy={{197}}}
    ''')
    for qid,label in ((22,"event / escort"),(23,"Deliver required items"),(24,"Deliver / use quest item"),(14,"Explore"),(5,"Collect items")):
        row=hover(g,qid)
        assert label in row.task.text and "Talk only" not in row.task.text


def test_chain_status_visible_in_all_dungeons_and_no_linear_step_numbers_in_branches(style):
    g=game(style,HOVER_DATA+'QUESTIE_QUESTS[4].preQuestSingle={1}')
    row=hover(g,1)
    assert "Chain quest" in row['from'].text and "step 1/" not in tooltip(g)
    assert "A dungeon job (2)" in tooltip(g) and "Class mission (4)" in tooltip(g)


def test_partial_scan_survives_close_and_tab_switch_without_working_while_hidden(style):
    g=game(style,"QUEST_READS=0 local get=QuestDB.Get QuestDB.Get=function(id,key) QUEST_READS=QUEST_READS+1 return get(id,key) end",False)
    g.slash("dungeons");g.advance(.1)
    reads=g.eval("QUEST_READS");assert reads>0 and not g.eval("NS.dungeonQuests._state()")[0]
    g.eval("NS.equipmentUI.close")();g.advance(5)
    assert g.eval("QUEST_READS")==reads, "no database work while the journal is closed"
    g.eval("NS.loot.open")();g.advance(1)  # switching tab also pauses
    paused=g.eval("QUEST_READS")
    g.slash("dungeons");g.advance(30)
    assert g.eval("NS.dungeonQuests._state()")[0] and ids(g)
    assert g.eval("QUEST_ENUMS")==1 and g.eval("QUEST_READS")>=paused


def test_open_scan_uses_foreground_slice_but_background_jobs_keep_shared_budget(style):
    g=game(style,"",False)
    g.run('''STARTS={} local start=NS.dataWork.start
NS.dataWork.start=function(owner,run,valid,finished,budget) STARTS[owner]=budget or 0 return start(owner,run,valid,finished,budget) end''')
    g.slash("dungeons");g.advance(30)
    assert g.eval("STARTS.dungeonQuests")>=8



def test_journal_text_boxes_pass_font_flags_so_the_whole_window_builds(style):
    # Regression: EditBox:SetFont without flags errored in the client and left a black page with only the top dropdowns.
    g=game(style);w=g.eval("NS.dungeonQuests._window()")
    for key in ("level","search","levelMode","mine","reset","status","detailFrame","pickup","prev","next","reload"):
        assert w[key] is not None, key
    assert w.level.font and w.level.font[3]=="" and w.search.font[3]==""
    assert len(list(w.rows.values()))==5 and w.rows[1].frame.shown
    host,c,p,t=g.eval("NS.equipmentUI._window()")
    assert c.min.font[3]=="" and c.stats[3].stat is not None



CHECK="ReadyCheck-Ready"


def chain_text(g, qid):
    row=hover(g,qid);row.frame.scripts.OnClick(row.frame,"LeftButton")
    return g.eval("NS.dungeonQuests._window().detailsText.text")


def line_of(text, name):  # the chain bullet for a quest, not other lines that mention its name
    return next(l for l in text.split("\n") if name in l and ("•" in l or CHECK in l))


def test_names_and_locations_have_their_own_colours_in_rows_and_panel(style):
    g=game(style,HOVER_DATA);text=chain_text(g,2);w=g.eval("NS.dungeonQuests._window()")
    # panel: crimson name, deep-blue pickup, purple turn-in, each on its own coloured line
    assert "|cff7a0c0cA dungeon job|r" in text
    assert "|cff0a2a8aMarshal McBride" in text and "|cff5a1a7aKobold Miner" in text
    row=next(r for r in w.rows.values() if r.result and r.result.id==2)
    assert row.item.text.startswith("|cffffd100A dungeon job|r")
    assert row.pickup.text.startswith("|cff9fe6ffPickup:") and row.turnIn.text.startswith("|cffe6b3ffTurn-in:")
    assert not g.eval("NS.db.errors")


def test_detail_panel_keeps_the_yellow_but_drops_the_picture(style):
    g=game(style)
    surface=g.eval("NS.dungeonQuests._window().detailFrame.journalSurface")
    assert not surface.grain.shown and surface.base.shown


def test_chain_is_an_indented_bullet_list_with_pending_steps_and_where_to_go(style):
    g=game(style,HOVER_DATA)
    text=chain_text(g,2)
    a,b,c=(line_of(text,n) for n in ("Outdoor preparation","A dungeon job","Return outside"))
    indent=lambda l:len(l)-len(l.lstrip(" "))
    assert indent(a)<indent(b)<indent(c), "each next step is one tab deeper"
    assert all("•" in l and CHECK not in l for l in (a,b,c))
    assert "< this quest" in b and "< this quest" not in a
    assert "Go speak to Marshal McBride" in text, "a talk-only step says who to go and speak to"
    assert not g.eval("NS.db.errors")


def test_done_steps_get_a_green_tick_and_a_finished_later_step_ticks_the_ones_before_it(style):
    g=game(style,HOVER_DATA)
    g.run("FINISHED[1]=true");text=chain_text(g,2)
    assert CHECK in line_of(text,"Outdoor preparation") and "(done)" in line_of(text,"Outdoor preparation")
    assert CHECK not in line_of(text,"Return outside")
    # Finishing the last step means the first two have nothing to offer any more, even if never flagged themselves.
    g.run("FINISHED[1]=nil;FINISHED[3]=true");text=chain_text(g,2)
    for name in ("Outdoor preparation","A dungeon job","Return outside"):
        assert CHECK in line_of(text,name), name
    assert "not needed" in line_of(text,"Outdoor preparation")
    assert "(done)" in line_of(text,"Return outside")
    assert not g.eval("NS.db.errors")


def test_finished_later_step_does_not_tick_when_any_one_of_several_prerequisites_would_do(style):
    # Quest 4 can be reached through 1 or 2: finishing it does not prove which one was done.
    g=game(style,HOVER_DATA+"QUESTIE_QUESTS[4].preQuestSingle={1,2};QUESTIE_QUESTS[2].nextQuestInChain=nil;FINISHED[4]=true")
    text=chain_text(g,2)
    assert CHECK not in line_of(text,"A dungeon job")


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
