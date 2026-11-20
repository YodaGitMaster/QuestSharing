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


def game(style, extra="", open_tab=True, everything=True):
    g=optional_game(style,DATA+extra)
    if open_tab:
        g.slash("dungeons");g.advance(90)
        assert g.eval("NS.dungeonQuests._state()")[0], g.printed()
        if everything:  # the tab opens scoped to your character; most checks here want the whole catalogue
            click(g.eval("NS.dungeonQuests._window()").reset);g.advance(90)
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
        if key=="dungeon":  # the dungeon is chosen by opening its page (0 = back to the dungeon cards)
            if value: g.eval("NS.dungeonQuests.openDungeon")(value,"quests")
            else: g.eval("NS.dungeonQuests.home")()
        elif key in ("class","faction"):
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
    click(w.reset);g.advance(90)
    assert {5,7,17,18,19}<=ids(g) and 8 not in ids(g)
    assert g.eval("NS.dungeonQuests.current")()==1581


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
    assert any("Where to pick" in x for x in labels) and any("Mark quest giver (then press M)" in x for x in labels)
    assert any("Trace back" in x for x in labels) and any("How to do" in x for x in labels)
    for item in menu["items"].values():
        if item.text in ("Offer it to the party","Tell the party how I am doing","Ask in chat to do this quest","Focus it on my map"):
            assert item.why=="this quest is not in your quest log"
    assert not g.eval("NS.db.errors")


def test_quest_log_update_keeps_open_menu_until_its_quest_leaves_results(style):
    # Regression: QUEST_LOG_UPDATE -> D.refresh() -> closeQuestMenu() shut the right-click menu 0.2 s after any log change.
    g=game(style);w=g.eval("NS.dungeonQuests._window()")
    click(w.completed);assert 19 not in ids(g)  # "Hiding completed": finishing a quest removes it from the results
    row=w.rows[1];qid=row.result.id;other=4  # 4 is a standalone quest: finishing a chain-mate would also hide this one
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
    assert "Install or update QuestieDB (see /qs questie)" in g.eval("NS.dungeonQuests._window().status.text")
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
    assert not ids(g) and "cannot filter by class or faction" in w.status.text
    click(w.reset);g.advance(90);assert ids(g)


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
    # the 48 px row keeps name and level; pickup and turn-in are on the quest page (Starts at / Turn in) and the hover
    g=game(style,HOVER_DATA);row=hover(g)
    assert "Pick up:" in tooltip(g) and "Marshal McBride" in tooltip(g) and "Turn in:" in tooltip(g) and "Kobold Miner" in tooltip(g)
    row.frame.scripts.OnClick(row.frame,"LeftButton")
    p=g.eval("NS.dungeonQuests._window().panel")
    assert "Marshal McBride" in p.pickup.title.text and "48.9" in p.pickup.sub.text
    assert "Kobold Miner" in p.turnIn.title.text and "60.0" in p.turnIn.sub.text
    assert p.pickup.title.wordWrap is False and p.turnIn.sub.wordWrap is False
    assert "Kobold Miner" in g.eval("NS.dungeonQuests._window().detailsText.text")


def test_hover_shows_base_xp_and_all_item_rewards_even_non_equipment(style):
    g=game(style,HOVER_DATA)
    assert g.eval("ENUMERATIONS")==0
    hover(g)
    assert "XP: 2000 (base)" in tooltip(g) and "loading" in tooltip(g)
    g.advance(30)
    text=tooltip(g)
    assert "you may have to choose one" in text and "Reward staff" in text and "Plain material reward" in text
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
    assert "Marshal McBride" in tooltip(g) and "Kobold Miner" in tooltip(g)
    assert not g.eval("NS.db.errors")


def test_hover_reward_scan_pauses_in_combat_and_on_close_then_continues(style):
    g=game(style,HOVER_DATA)
    g.run("InCombatLockdown=function()return true end")
    hover(g);g.advance(1)
    assert g.eval("ENUMERATIONS")==0 and g.eval("NS.dataWork.busy")("dungeonQuestRewards")
    g.eval("NS.equipmentUI.close")();g.advance(2)
    assert g.eval("NS.dataWork.busy")("dungeonQuestRewards"), "paused, kept for the reopen"
    assert not g.eval("TOOLTIP.shown")
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
    assert len(w.rows)==8
    for row in w.rows.values():assert row.frame.height==48 and row.edge.height==48 and row.frame.width<=296
    assert w.list.height>=8*48
    filters(g,dungeon=1581)
    assert g.eval("NS.dungeonQuests.go")(1)
    assert w.rows[1].result and plain(w.rows[1]["from"].text).startswith(("Available from level","Needs level","Completed","Not needed"))


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
    row.frame.scripts.OnClick(row.frame,"LeftButton");p=g.eval("NS.dungeonQuests._window().panel")
    assert "+1 more" in p.pickup.sub.text and "+1 more" in p.turnIn.sub.text
    assert "Marshal McBride" in tooltip(g) and "Kobold Miner" in tooltip(g)


def test_talk_only_and_chain_labels_are_separate_on_same_quest(style):
    g=game(style,HOVER_DATA);filters(g,dungeon=1581)
    row=hover(g,3)
    assert "Chain quest: follow-up" in tooltip(g)
    assert "Task: Talk only" in tooltip(g) and "speak to Marshal McBride" in tooltip(g)
    assert "Previous chain quests:" in tooltip(g) and "A dungeon job (quest ID 2)" in tooltip(g)
    assert "Talk only" in tooltip(g)


def test_chain_start_is_recognised_by_incoming_prerequisite_link(style):
    g=game(style,HOVER_DATA);filters(g,dungeon=1581)
    row=hover(g,1)
    assert "Chain quest: prerequisite" in tooltip(g)
    assert "Next chain quests:" in tooltip(g) and "A dungeon job (quest ID 2)" in tooltip(g)
    assert "Task: Task unknown" in tooltip(g)


def test_standalone_dungeon_kill_quest_has_work_label_not_talk_only(style):
    g=game(style,HOVER_DATA);row=hover(g,4)
    assert "Standalone quest" in tooltip(g) and "Task: Defeat enemies" in tooltip(g)
    assert "Talk only" not in tooltip(g)


def test_events_items_and_exploration_are_not_mislabelled_talk_only(style):
    g=game(style,HOVER_DATA+r'''
    QUESTIE_QUESTS[22]={name="Escort event",zoneOrSort=1581,specialFlags=3,finishedBy={{197}}}
    QUESTIE_QUESTS[23]={name="Hidden collection",zoneOrSort=1581,requiredSourceItems={950},finishedBy={{197}}}
    QUESTIE_QUESTS[24]={name="Given letter",zoneOrSort=1581,sourceItemId=951,finishedBy={{197}}}
    ''')
    for qid,label in ((22,"event / escort"),(23,"Deliver required items"),(24,"Deliver / use quest item"),(14,"Explore"),(5,"Collect items")):
        row=hover(g,qid)
        task=next(l for l in tooltip(g).split("\n") if l.startswith("Task: "))
        assert label in task and "Talk only" not in task


def test_chain_status_visible_in_all_dungeons_and_no_linear_step_numbers_in_branches(style):
    g=game(style,HOVER_DATA+'QUESTIE_QUESTS[4].preQuestSingle={1}')
    row=hover(g,1)
    assert "Chain quest" in tooltip(g) and "step 1/" not in tooltip(g)
    assert "A dungeon job (quest ID 2)" in tooltip(g) and "Class mission (quest ID 4)" in tooltip(g)


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
    for key in ("level","search","levelMode","mine","reset","status","detailFrame","pickup","prev","next","reload",
                "back","title","pin","content","questsPage","homeView","dungeonView"):
        assert w[key] is not None, key
    assert w.level.font and w.level.font[3]=="" and w.search.font[3]==""
    assert len(list(w.rows.values()))==8 and w.rows[1].frame.shown
    host,c,p,t=g.eval("NS.equipmentUI._window()")
    assert c.min.font[3]=="" and c.stats[3].stat is not None



CHECK="ReadyCheck-Ready"


def chain_text(g, qid):
    row=hover(g,qid);row.frame.scripts.OnClick(row.frame,"LeftButton")
    return g.eval("NS.dungeonQuests._panelText()")


def line_of(text, name):  # the chain bullet for a quest, not other lines that mention its name
    return next(l for l in text.split("\n") if name in l and ("•" in l or CHECK in l))


def test_names_and_locations_have_their_own_colours_in_rows_and_panel(style):
    g=game(style,HOVER_DATA);text=chain_text(g,2);w=g.eval("NS.dungeonQuests._window()")
    # panel: the quest name is the header; pickup and hand-in are their own big click-to-pin lines
    p=g.eval("NS.dungeonQuests._window().panel")
    assert p.title.text=="A dungeon job"
    assert plain(p.pickup.title.text)=="Pick up from Marshal McBride" and plain(p.turnIn.title.text)=="Hand in to Kobold Miner"
    # every keyword kind has its own colour: NPC teal, place brown-orange, number magenta, quest crimson, dungeon navy
    assert "|cff006666Marshal McBride|r" in p.pickup.title.text and "|cff006666Kobold Miner|r" in p.turnIn.title.text
    assert "|cff8a4000Elwynn Forest 48.9, 41.6|r" in p.pickup.sub.text
    assert "|cff1a2a6aThe Deadmines|r" in p.meta.text and "|cff8a1a6a20|r" in p.meta.text and "|cff8a1a6a15+|r" in p.meta.text
    assert "|cff8a0c0cOutdoor preparation|r" in p.chain.text and "|cff8a0c0cReturn outside|r" in p.chain.text
    assert len({"|cff006666","|cff8a4000","|cff8a1a6a","|cff8a0c0c","|cff1a2a6a"})==5
    row=next(r for r in w.rows.values() if r.result and r.result.id==2)
    assert row.item.text.startswith("|cffffd100A dungeon job|r") and "|cffff9ad815|r" in row["from"].text  # needs level 15
    assert "Available from level" in plain(row["from"].text)
    assert not g.eval("NS.db.errors")


def test_detail_panel_is_a_parchment_page_next_to_the_list(style):
    g=game(style);w=g.eval("NS.dungeonQuests._window()")
    assert w.detailFrame.parchment and w.detailFrame.width==1000-342 and w.detailFrame.height==560
    assert w.left.width==330 and w.content.width==1000 and w.content.height==560
    assert w.content.point[3]=="TOPLEFT" and w.content.point[4]==16 and w.content.point[5]==-140


def rows_by_id(g, pages=1):
    w=g.eval("NS.dungeonQuests._window()")
    return {r.result.id:r for r in w.rows.values() if r.result and r.frame.shown}


def lead_rows(g):
    """Rows of the lead-in quests (30-35), whichever page they are on; paints each page once and keeps its text."""
    out={}
    go=g.eval("NS.dungeonQuests.go")
    while go(-1): pass
    while True:
        for q,row in rows_by_id(g).items():
            tip="\n".join(g.eval("NS.dungeonQuests.hoverLines")(row.result).values())
            out[q]=type("Row",(),{"from_":row["from"].text+"\n"+tip,"item":row.item.text,"icon":row.icon.texture,"row":row["from"].text})
        if not go(1): break
    while go(-1): pass
    return out


def test_chain_is_nested_in_the_list_and_the_panel_describes_only_the_clicked_step(style):
    g=game(style,HOVER_DATA);filters(g,dungeon=1581)
    order=[r.id for r in g.eval("NS.dungeonQuests._results()").values()]
    assert order.index(1)+1==order.index(2) and order.index(2)+1==order.index(3), order
    rows=rows_by_id(g)
    assert rows[1].item.text.count("»")==0 and "»" in rows[2].item.text and "»" in rows[3].item.text
    assert rows[1].frame.width>rows[2].frame.width>rows[3].frame.width, "each next step is indented"
    text=chain_text(g,2)
    assert "A dungeon job" in plain(text) and "Quest ID: 2" in plain(text) and "Next: Return outside" in plain(text)
    assert "Before: Outdoor preparation" in plain(text), "only the neighbours, not a whole-chain tree"
    assert not g.eval("NS.db.errors")


def test_done_steps_are_ticked_and_greyed_and_a_finished_later_step_ticks_the_ones_before_it(style):
    g=game(style,HOVER_DATA);filters(g,dungeon=1581)
    ready=lambda q:"ReadyCheck-Ready" in (rows_by_id(g)[q].icon.texture or "")
    assert not any(ready(q) for q in (1,2,3))
    g.run("FINISHED[1]=true");g.eval("NS.dungeonQuests.refresh")();g.advance(.3)
    assert ready(1) and not ready(2) and not ready(3)
    # Finishing the last step: the first two will never be offered again, so they are ticked and greyed too.
    g.run("FINISHED[1]=nil;FINISHED[3]=true");g.eval("NS.dungeonQuests.refresh")();g.advance(.3)
    rows=rows_by_id(g)
    for q in (1,2,3):
        assert ready(q) and "|cff7d7d7d" in rows[q].item.text and "|cff7d7d7d" in rows[q]["from"].text, q
    assert "Not needed" in rows[1]["from"].text
    assert "Not needed" not in rows[3]["from"].text and "Completed" in rows[3]["from"].text
    assert "Skip it: the next step is done or taken" in plain(chain_text(g,2))
    assert "Next: Return outside (done)" in plain(chain_text(g,2))
    assert not g.eval("NS.db.errors")


def test_finished_later_step_does_not_tick_when_any_one_of_several_prerequisites_would_do(style):
    g=game(style,HOVER_DATA+"QUESTIE_QUESTS[4].preQuestSingle={1,2};QUESTIE_QUESTS[2].nextQuestInChain=nil;FINISHED[4]=true")
    filters(g,dungeon=1581)
    assert "ReadyCheck-Ready" not in (rows_by_id(g)[2].icon.texture or "")


def test_opens_for_your_character_and_reads_big_tables_only_for_quests_that_pass(style):
    g=game(style,r'''
    BIG={}
    local get=QuestDB.Get
    QuestDB.Get=function(id,key) if key=="startedBy" or key=="objectives" then BIG[id]=true end;return get(id,key) end
    ''',everything=False)
    seen=g.eval("BIG")
    # level 20 Alliance Druid: Horde-only (5), Mage-only (7) and level-40 (17) quests are never opened
    for qid in (5,7,17): assert seen[qid] is None, qid
    assert seen[2] and seen[1] and seen[4]
    assert {5,7,17}.isdisjoint(ids(g))
    assert g.eval("QUEST_ENUMS")==1


def test_narrowing_keeps_the_scan_and_widening_scans_again(style):
    g=game(style,everything=False);w=g.eval("NS.dungeonQuests._window()")
    edit(w.level,"10");g.advance(.3)
    assert g.eval("QUEST_ENUMS")==1                       # a lower level only filters what was read
    edit(w.level,"45");g.advance(90)
    assert g.eval("QUEST_ENUMS")==2 and 17 in ids(g)      # a higher level needs the quests the first scan skipped
    click(w.reset);g.advance(90)
    assert g.eval("QUEST_ENUMS")==3 and {5,7,17}<=ids(g)  # all factions and classes
    click(w.mine);g.advance(.3)
    assert g.eval("QUEST_ENUMS")==3 and 5 not in ids(g)   # back to one character: no new scan


LEADIN='''
QUESTIE_QUESTS[30]={name="Seeking Helper",questLevel=15,startedBy={{197}},finishedBy={{400}},nextQuestInChain=31}
QUESTIE_QUESTS[31]={name="Deadmine errand",questLevel=18,zoneOrSort=1581,startedBy={{400}}}
QUESTIE_QUESTS[32]={name="Crypt errand",questLevel=18,zoneOrSort=1581,startedBy={{400}}}
QUESTIE_QUESTS[33]={name="Seeking Crypt",questLevel=15,startedBy={{197}},finishedBy={{400}},breadcrumbForQuestId=32}
QUESTIE_QUESTS[34]={name="Vault errand",questLevel=18,zoneOrSort=1581,startedBy={{400}}}
QUESTIE_QUESTS[35]={name="Seeking Vault",questLevel=15,startedBy={{197}},finishedBy={{400}},availableUntilCompleted=34}
'''


def test_optional_lead_in_quests_are_listed_with_their_dungeon_quest_and_not_standalone(style):
    # Questie says "30 leads to 31" only on quest 30 (31 does not list it as a prerequisite): a lead-in, not a standalone quest.
    g=game(style,LEADIN);filters(g,dungeon=1581)
    assert {30,31,32,33,34,35}<=ids(g), "lead-ins are listed with the dungeon quest they point to"
    rows=lead_rows(g)
    for lead,quest in ((30,31),(33,32),(35,34)):
        assert "optional lead-in" in rows[lead].from_ and "Standalone" not in rows[lead].from_, lead
        assert "Chain quest" in rows[quest].from_ and "Standalone" not in rows[quest].from_, quest
    order=[r.id for r in g.eval("NS.dungeonQuests._results()").values()]
    for lead,quest in ((30,31),(33,32),(35,34)):
        assert order.index(lead)+1==order.index(quest), "the dungeon quest sits right under its lead-in"
    assert not g.eval("NS.db.errors")


def test_lead_in_is_greyed_and_ticked_once_the_quest_it_leads_to_is_done(style):
    g=game(style,LEADIN);filters(g,dungeon=1581)
    rows=lead_rows(g)
    assert not any("ReadyCheck-Ready" in rows[q].icon for q in (30,31,32,33,34,35))
    g.run("FINISHED[31]=true;FINISHED[32]=true;FINISHED[34]=true");g.eval("NS.dungeonQuests.refresh")();g.advance(.3)
    rows=lead_rows(g)
    for lead in (30,33,35):
        assert "ReadyCheck-Ready" in rows[lead].icon and "Not needed" in rows[lead].from_ and "|cff7d7d7d" in rows[lead].item, lead
    assert "Not needed" not in rows[31].from_
    assert not g.eval("NS.db.errors")


def test_real_prerequisite_is_not_mislabelled_as_lead_in(style):
    g=game(style,HOVER_DATA);filters(g,dungeon=1581)
    tip="\n".join(g.eval("NS.dungeonQuests.hoverLines")(rows_by_id(g)[1].result).values())
    assert "optional lead-in" not in tip and "Chain quest: prerequisite" in tip  # quest 2 lists quest 1 as its prerequisite


def border_on(row):
    # UX-18: the gold "still to take" border is gone (gold means selected); rows never carry it
    todo=row.todo
    return todo is not None and len(list(todo.values()))>0 and all(e.shown for e in todo.values())


def test_hide_options_are_check_boxes_with_a_tick(style):
    g=game(style);w=g.eval("NS.dungeonQuests._window()")
    assert "Hide completed" in w.completed.text.text and "Hide quests in my log" in w.inLog.text.text
    assert not w.completed.tick.shown and not w.inLog.tick.shown
    click(w.completed);assert w.completed.tick.shown and 19 not in ids(g)
    click(w.completed);assert not w.completed.tick.shown and 19 in ids(g)
    click(w.reset);assert not w.completed.tick.shown and not w.inLog.tick.shown
    assert not g.eval("NS.db.errors")


def test_hide_quests_in_my_log_and_hide_completed_also_hide_not_needed_steps(style):
    g=game(style,HOVER_DATA);filters(g,dungeon=1581);w=g.eval("NS.dungeonQuests._window()")
    g.run("QUESTS[#QUESTS+1]={id=2,title='A dungeon job',level=20,objectives={}}")
    g.fire("QUEST_LOG_UPDATE");g.advance(.3)
    assert 2 in ids(g)
    click(w.inLog);assert 2 not in ids(g) and {1,3,4}<=ids(g)
    click(w.inLog);assert 2 in ids(g)
    g.run("FINISHED[3]=true");g.eval("NS.dungeonQuests.refresh")();g.advance(.3)
    click(w.completed);assert not ({1,3}&ids(g)), "a finished quest and the lead-ins it made pointless are hidden"
    assert not g.eval("NS.db.errors")


def test_quest_in_log_shows_question_mark_and_missing_quests_show_exclamation(style):
    g=game(style,HOVER_DATA);filters(g,dungeon=1581)
    g.run("QUESTS[#QUESTS+1]={id=2,title='A dungeon job',level=20,objectives={}}")
    g.fire("QUEST_LOG_UPDATE");g.advance(.3)
    rows=rows_by_id(g)
    assert "ActiveQuestIcon" in rows[2].icon.texture and rows[2].have.shown and rows[2].have.text=="YOU HAVE IT"
    assert not rows[3].have.shown
    assert not border_on(rows[2]), "already taken: no border"
    assert "AvailableQuestIcon" in rows[3].icon.texture and not border_on(rows[3]), "not taken yet: yellow '!', no gold border"
    assert "ReadyCheck-Ready" in rows[1].icon.texture and not border_on(rows[1]), "its lead-in is pointless once it is taken"
    g.run("FINISHED[3]=true");g.eval("NS.dungeonQuests.refresh")();g.advance(.3)
    rows=rows_by_id(g)
    assert "ReadyCheck-Ready" in rows[3].icon.texture and not border_on(rows[3]), "done: tick, no border"
    assert not g.eval("NS.db.errors")


def test_closed_catalogue_is_kept_for_the_session_until_purged_in_settings(style):
    g=game(style);enums=g.eval("QUEST_ENUMS")
    g.eval("NS.equipmentUI.close")();g.advance(3600)
    assert g.eval("NS.dungeonQuests._state()")[0], "kept long after closing"
    assert not g.eval("NS.dataWork.releasePending")("dungeonQuests"), "no free timer is armed"
    g.slash("dungeons");g.advance(1)
    assert g.eval("NS.dungeonQuests._state()")[0] and g.eval("QUEST_ENUMS")==enums, "reopening is instant, no re-read"
    g.eval("NS.equipmentUI.close")()
    g.eval("NS.dungeonQuests.purge")()
    assert not g.eval("NS.dungeonQuests._state()")[0] and not g.eval("NS.dataWork.busy")("dungeonQuests")
    assert g.eval("next(NS.dungeonQuests._results()) == nil"), "purge frees the catalogue"
    g.slash("dungeons");g.advance(90)
    assert g.eval("NS.dungeonQuests._state()")[0] and ids(g) and g.eval("QUEST_ENUMS")==enums+1, "next open reads again"


def test_purge_with_the_window_open_reads_the_data_again_at_once(style):
    g=game(style);enums=g.eval("QUEST_ENUMS")
    g.eval("NS.dungeonQuests.purge")();g.advance(90)
    assert g.eval("NS.dungeonQuests._state()")[0] and ids(g) and g.eval("QUEST_ENUMS")==enums+1
    assert not g.eval("NS.db.errors")


def test_a_paused_half_read_scan_is_kept_and_continues_on_reopen(style):
    g=game(style,open_tab=False)
    g.slash("dungeons");g.advance(.1)
    g.eval("NS.equipmentUI.close")();g.advance(600)
    assert g.eval("NS.dataWork.busy")("dungeonQuests"), "paused, not dropped"
    assert not g.eval("NS.dungeonQuests._state()")[0]
    g.slash("dungeons");g.advance(90)
    assert g.eval("NS.dungeonQuests._state()")[0] and ids(g)


ANYOF=r'''
QUESTIE_QUESTS[40]={name="Seeking Caitlin",questLevel=15,startedBy={{197}},finishedBy={{400}}}
QUESTIE_QUESTS[42]={name="Seeking Another",questLevel=15,startedBy={{197}},finishedBy={{400}}}
QUESTIE_QUESTS[41]={name="Dungeon from harbor",questLevel=18,zoneOrSort=1581,startedBy={{400}},preQuestSingle={40,42}}
'''


def test_lead_in_that_is_one_of_several_any_prerequisites_is_greyed_when_the_quest_is_done(style):
    g=game(style,ANYOF);filters(g,dungeon=1581)
    rows=lead_rows(g)
    assert not any("ReadyCheck-Ready" in rows[q].icon for q in (40,41,42))
    g.run("FINISHED[41]=true");g.eval("NS.dungeonQuests.refresh")();g.advance(.3)
    rows=lead_rows(g)
    for q in (40,42):
        assert "ReadyCheck-Ready" in rows[q].icon and "Not needed" in rows[q].from_ and "|cff7d7d7d" in rows[q].item, q
    assert not g.eval("NS.db.errors")


def test_a_quest_with_a_not_done_follow_up_is_not_greyed_by_another_done_follow_up(style):
    g=game(style,ANYOF+"QUESTIE_QUESTS[43]={name='Other branch',questLevel=18,zoneOrSort=1581,startedBy={{400}},preQuestSingle={40,44}};QUESTIE_QUESTS[44]={name='Other lead',questLevel=15,startedBy={{197}}}")
    filters(g,dungeon=1581);g.run("FINISHED[41]=true");g.eval("NS.dungeonQuests.refresh")();g.advance(.3)
    rows=lead_rows(g)
    assert "ReadyCheck-Ready" not in rows[40].icon, "40 still unlocks 43, which is not done"
    assert "ReadyCheck-Ready" in rows[42].icon


def test_panel_shows_raw_questie_link_fields_only_with_debug_logging(style):
    g=game(style,HOVER_DATA);g.run("NS.db.debug=false");text=plain(chain_text(g,2))
    assert "preQuestSingle" not in text and "Questie data" not in text, "UX-31: no field names for players"
    g.run("NS.db.debug=true");text=plain(chain_text(g,2))
    assert "Debug, quest data chain fields: preQuestSingle=1  nextQuestInChain=3" in text
    assert "Debug, quest data chain fields: none" in plain(chain_text(g,4))


SEEKING=r'''
QUESTIE_NPCS[500]={name="Llana",spawns={[12]={{20,20}}}}
QUESTIE_NPCS[501]={name="Caitlin Grassman",spawns={[12]={{11,58}}}}
QUESTIE_QUESTS[50]={name="Seeking Caitlin",questLevel=31,zoneOrSort=1581,startedBy={{500}},finishedBy={{501}}}
QUESTIE_QUESTS[51]={name="Lost in the Thicket",questLevel=31,zoneOrSort=1581,startedBy={{501}},finishedBy={{501}},objectives={{{900}}}}
QUESTIE_QUESTS[52]={name="Caitlin unrelated errand",questLevel=22,zoneOrSort=718,startedBy={{501}}}
QUESTIE_QUESTS[53]={name="Fetch for Llana",questLevel=31,zoneOrSort=1581,startedBy={{500}},finishedBy={{501}},objectives={nil,nil,{{950}}}}
'''


def test_talk_only_quest_to_an_npc_who_starts_a_dungeon_quest_is_linked_even_without_questie_data(style):
    # Real case: "Seeking Caitlin" (95737) has no link fields in QuestieDB; Caitlin Grassman starts the dungeon quest.
    g=game(style,SEEKING);filters(g,dungeon=1581)
    order=[r.id for r in g.eval("NS.dungeonQuests._results()").values()]
    assert order.index(50)+1==order.index(51), "the quest she offers sits right under the talk-only one"
    rows=lead_rows(g)
    assert "ReadyCheck-Ready" not in rows[50].icon
    g.run("FINISHED[51]=true");g.eval("NS.dungeonQuests.refresh")();g.advance(.3)
    rows=lead_rows(g)
    assert "ReadyCheck-Ready" in rows[50].icon and "Not needed" in rows[50].from_ and "|cff7d7d7d" in rows[50].item
    assert "Not needed" not in rows[53].from_, "a quest with real objectives is not treated as a lead-in"
    assert "guessed" in plain(chain_text(g,50)) and "51" in plain(chain_text(g,50))
    assert not g.eval("NS.db.errors")


def test_inferred_lead_in_ignores_quests_of_other_dungeons_and_ones_with_their_own_prerequisite(style):
    g=game(style,SEEKING+"QUESTIE_QUESTS[51].preQuestSingle={53}");filters(g,dungeon=1581)
    assert "guessed" not in plain(chain_text(g,50)), "51 has its own prerequisite chain"
    g=game(style,SEEKING);filters(g,dungeon=718)
    assert "guessed" not in plain(chain_text(g,52))
    g=game(style,SEEKING+"QUESTIE_QUESTS[50].preQuestSingle={53}");filters(g,dungeon=1581)
    assert "guessed" not in plain(chain_text(g,50)), "a quest with its own prerequisite is a later step, not a lead-in"
    # Real case 95795 "Fallen in the Fen": a "return to X" step with no NPC starter, X starts the chain's first quest.
    g=game(style,SEEKING+"QUESTIE_QUESTS[54]={name='Return to Caitlin',questLevel=31,zoneOrSort=1581,finishedBy={{501}}}")
    filters(g,dungeon=1581)
    assert "guessed" not in plain(chain_text(g,54)), "a step without an NPC starter is not a lead-in"


def test_lead_in_is_not_needed_once_the_quest_it_leads_to_is_already_in_my_log(style):
    # Llana stops offering "Seeking Caitlin" as soon as the quest Caitlin gives is taken, not only when it is finished.
    g=game(style,SEEKING);filters(g,dungeon=1581)
    g.run("QUESTS[#QUESTS+1]={id=51,title='Lost in the Thicket',level=31,objectives={}}");g.fire("QUEST_LOG_UPDATE");g.advance(.3)
    rows=lead_rows(g)
    assert "ReadyCheck-Ready" in rows[50].icon and "Not needed" in rows[50].from_ and "|cff7d7d7d" in rows[50].item
    assert "ActiveQuestIcon" in rows[51].icon and "In your quest log" in rows[51].from_, "the quest itself is just marked as taken"
    w=g.eval("NS.dungeonQuests._window()");click(w.completed)
    assert 50 not in ids(g) and 51 in ids(g), "Hide completed also hides the lead-in that can no longer be taken"
    assert not g.eval("NS.db.errors")


def test_round_three_labels_border_only_for_what_i_can_take_and_no_req_zero(style):
    g=game(style,HOVER_DATA+SEEKING+"UnitLevel=function() return 20 end UnitFactionGroup=function() return 'Alliance' end")
    filters(g,dungeon=1581);w=g.eval("NS.dungeonQuests._window()")
    rows=lead_rows(g)
    assert "optional lead-in" in rows[50].from_, "a lead-in is called one even when it is listed for the dungeon itself"
    assert "level 0" not in plain(rows[4].row) and "Available from level 15" in plain(rows[2].row)
    edit(w.search,"High quest");g.advance(.3)
    hi=rows_by_id(g)[17]
    assert "AvailableQuestIcon" not in hi.icon.texture and "|cffff6060Needs level 40" in hi["from"].text, "too high: red requirement, no '!'"
    edit(w.search,"Horde mission");g.advance(.3)
    assert "AvailableQuestIcon" not in rows_by_id(g)[5].icon.texture, "other faction: no '!'"
    edit(w.search,"Class mission");g.advance(.3)
    assert "AvailableQuestIcon" in rows_by_id(g)[4].icon.texture and not border_on(rows_by_id(g)[4])
    assert "no level requirement" in plain(chain_text(g,4))
    assert len(plain(w.status.text))<=110
    assert not g.eval("NS.db.errors")


def page_ids(g):
    out=[];go=g.eval("NS.dungeonQuests.go")
    while go(-1): pass
    while True:
        out.append([r.result.id for r in g.eval("NS.dungeonQuests._window()").rows.values() if r.result and r.frame.shown])
        if not go(1): break
    return out


def test_a_chain_that_fits_on_one_page_is_never_split_across_pages(style):
    # 4 standalone quests then a 3-step chain: the chain moves whole to page 2 instead of 1 step on page 1.
    extra="".join(f"QUESTIE_QUESTS[{60+k}]={{name='Aaa filler {k}',questLevel=1,zoneOrSort=1581}}\n" for k in range(4))
    g=game(style,HOVER_DATA+extra);filters(g,dungeon=1581)
    pages=page_ids(g)
    chain=[1,2,3]
    holder=[p for p in pages if 1 in p][0]
    assert all(q in holder for q in chain), pages
    assert sum(len(p) for p in pages)==len(ids(g)) and all(len(p)<=8 for p in pages)
    w=g.eval("NS.dungeonQuests._window()")
    assert "of %d quests" % len(ids(g)) in plain(w.status.text)
    assert not g.eval("NS.db.errors")


def test_hover_says_when_a_quest_is_not_needed_or_taken(style):
    g=game(style,SEEKING);filters(g,dungeon=1581)
    g.run("QUESTS[#QUESTS+1]={id=51,title='Lost in the Thicket',level=31,objectives={}}");g.fire("QUEST_LOG_UPDATE");g.advance(.3)
    hover(g,50);assert "Not needed" in tooltip(g) and "Lost in the Thicket (quest ID 51) - in your quest log" in tooltip(g)
    hover(g,51);assert "In your quest log" in tooltip(g)


def test_rewards_are_in_the_details_panel_and_xp_on_the_row(style):
    g=game(style,HOVER_DATA+"UnitLevel=function() return 30 end QUESTIE_QUESTS[2].reputationReward={{72,250}} GetFactionInfoByID=function(id) return id==72 and 'Stormwind' or nil end")
    w=g.eval("NS.dungeonQuests._window()")
    edit(w.search,"A dungeon job");g.advance(.3)
    row=rows_by_id(g)[2]
    assert "200 XP" in plain(row["from"].text), "level 30 vs quest 20: 10 % of 2000 shown on the row"
    assert g.eval("ITEM_READS")==0, "opening and auto-selecting does not read the item catalogue"
    row.frame.scripts.OnClick(row.frame,"LeftButton");g.advance(30)
    text=plain(g.eval("NS.dungeonQuests._panelText()"))
    p=g.eval("NS.dungeonQuests._window().panel")
    assert "Choose one reward" in text and p.xpPill.shown and p.xpPill.value=="200 XP" and "base 2000 XP, less at your level" in text
    assert p.repPills[1].shown and p.repPills[1].value=="+250 Stormwind" and not p.repPills[2].shown
    assert "Reward staff" in text and "You will also receive:" in text, "panel refreshes when item rewards finish loading"
    assert not g.eval("NS.db.errors")


def test_xp_at_level_is_full_within_five_levels(style):
    g=game(style,HOVER_DATA+"UnitLevel=function() return 24 end")
    hover(g,2);assert "XP: 2000 (base)" in tooltip(g) and "at your level" not in tooltip(g)


def test_panel_reads_in_seconds_status_first_and_click_to_pin_places(style):
    g=game(style,HOVER_DATA+"UnitLevel=function() return 20 end QUESTIE_QUESTS[2].objectivesText={'Bring 5 Red Bandanas to Kobold Miner.'}")
    g.run('WAYPOINT=nil;UiMapPoint={CreateFromCoordinates=function(map,x,y)return {map=map,x=x,y=y} end};C_Map.SetUserWaypoint=function(p)WAYPOINT=p end')
    text=plain(chain_text(g,2));p=g.eval("NS.dungeonQuests._window().panel")
    order=[text.index(k) for k in ("Available from level","To pick up","Objective","Bring 5 Red Bandanas","Starts at","Turn in","Rewards","You will receive:","Quest chain","More details")]
    assert order==sorted(order), "status, task, where, rewards, chain, then small print"
    p.turnIn.scripts.OnClick(p.turnIn,"LeftButton")
    pt=g.eval("WAYPOINT");assert pt and abs(pt.x-.60)<.001 and abs(pt.y-.60)<.001, "clicking the hand-in NPC pins it"
    g.run("WAYPOINT=nil");p.pickup.scripts.OnClick(p.pickup,"LeftButton")
    assert abs(g.eval("WAYPOINT").x-.4892)<.0001, "clicking the quest giver pins them"
    p.pickup.scripts.OnEnter(p.pickup);assert "world map" in tooltip(g)
    assert not g.eval("NS.db.errors")


def test_status_badge_says_the_one_thing_to_know(style):
    g=game(style,HOVER_DATA+SEEKING+"UnitLevel=function() return 20 end")
    p=lambda q:(chain_text(g,q),plain(g.eval("NS.dungeonQuests._window().panel").badge.text))[1]
    assert p(2)=="To pick up" and p(17)=="Needs level 40"
    g.run("QUESTS[#QUESTS+1]={id=51,title='Lost in the Thicket',level=31,objectives={}}");g.fire("QUEST_LOG_UPDATE");g.advance(.3)
    assert p(51)=="In your quest log" and p(50).startswith("Skip it")
    g.run("FINISHED[4]=true");assert p(4)=="Done"


def test_item_rewards_are_buttons_with_icons_that_show_stats_on_hover(style):
    g=game(style,HOVER_DATA+"GameTooltip.SetHyperlink=function(_,link) TOOLTIP.link=link end")
    chain_text(g,2);g.advance(30);chain_text(g,2)
    p=g.eval("NS.dungeonQuests._window().panel")
    shown=[b for b in p["items"].values() if b.shown]
    assert len(shown)==2 and {b.itemID for b in shown}=={810,811}
    staff=next(b for b in shown if b.itemID==810)
    assert "|cff0070ddReward staff" in staff.name.text, "rare quality blue on the dark item box"
    assert staff.icon.width==38 and list(staff.icon.coords.values())==[.08,.92,.08,.92]
    staff.scripts.OnEnter(staff);assert g.eval("TOOLTIP.link")=="item:810"
    assert not g.eval("NS.db.errors")


def test_objective_text_colours_numbers_npcs_and_items_without_breaking_codes(style):
    g=game(style,HOVER_DATA+"QUESTIE_QUESTS[2].objectivesText={'Bring 5 Dungeon relic and 10 more to Kobold Miner in The Deadmines.'} QUESTIE_QUESTS[2].objectives={nil,nil,{{950}}}")
    chain_text(g,2);t=g.eval("NS.dungeonQuests._window().panel").doText.text
    assert "|cff8a1a6a5|r" in t and "|cff8a1a6a10|r" in t
    assert "|cff6a4a00Dungeon relic|r" in t and "|cff006666Kobold Miner|r" in t and "|cff1a2a6aThe Deadmines|r" in t
    assert plain(t)=="Bring 5 Dungeon relic and 10 more to Kobold Miner in The Deadmines.", "colour codes are well formed"
    assert not g.eval("NS.db.errors")


def test_a_short_name_inside_a_longer_one_is_not_coloured_twice(style):
    g=game(style,HOVER_DATA+"QUESTIE_NPCS[903]={name='Kobold',spawns={}} QUESTIE_QUESTS[2].objectivesText={'Kill a Kobold, then talk to Kobold Miner.'} QUESTIE_QUESTS[2].objectives={{{903}}}")
    chain_text(g,2);t=g.eval("NS.dungeonQuests._window().panel").doText.text
    assert "|cff006666Kobold Miner|r" in t and t.count("|c")==t.count("|r"), t


FOREVER=r'''
local names2={[1337]="Uldaman",[16732]="Excavation Site: Wetlands",[16919]="The Hall of Thanes",[16611]="Ruins of Lordaeron"}
local area=C_Map.GetAreaInfo
C_Map.GetAreaInfo=function(id) return names2[id] or area(id) end
QUESTIE_NPCS[920]={name="Thicket stalker",spawns={[16878]={{40,40}}}}   -- Excavation Site sub-area
QUESTIE_NPCS[921]={name="Lordaeron ghoul",spawns={[16617]={{50,50}}}}   -- Ruins of Lordaeron: Market Street
QUESTIE_QUESTS[30]={name="Uldaman under its quest id",questLevel=40,zoneOrSort=1517,startedBy={{197}}}
QUESTIE_QUESTS[31]={name="Stalker hunt",questLevel=31,startedBy={{197}},objectives={{{920}}}}
QUESTIE_QUESTS[32]={name="Thanes errand",questLevel=40,zoneOrSort=16919,startedBy={{197}}}
QUESTIE_QUESTS[33]={name="Ghoul cleanup",questLevel=40,startedBy={{197}},objectives={{{921}}}}
local get=LibQuestieDB.Support.Get
LibQuestieDB.Support.Get=function(name)
 if name=="ZoneDB" then
  local z=get(name) or {private={}}
  z.private.dungeons="return {[1337]={'Uldaman',{1517},3,{{3,44.6,12.1}}},[2717]={'Molten Core',nil,51,{{51,34.9,83.9}}},[16732]={'Excavation Site: Wetlands',nil,11,{{11,47.79,56.16}}}}"
  return z
 end
 return get(name)
end
'''


def test_forever_dungeons_sub_areas_and_alternative_quest_ids_are_dungeons(style):
    g=game(style,FOREVER)
    rows={r.id:r for r in g.eval("NS.dungeonQuests._results()").values()}
    assert rows[30].dungeons[1337], "Uldaman's quests use area 1517 in Questie: it is Uldaman"
    assert rows[31].dungeons[16732], "an NPC in Stalkers' Thicket (16878) makes it an Excavation Site quest"
    assert rows[32].dungeons[16919], "The Hall of Thanes is a dungeon"
    assert rows[33].dungeons[16611], "Market Street (16617) belongs to Ruins of Lordaeron"
    assert 11 not in rows, "a Molten Core (raid) quest is still not a dungeon quest"
    loot=g.eval("NS.loot")
    assert loot.dungeonOf(1517)==1337 and loot.dungeonOf(16880)==16732 and loot.dungeonOf(2717) is None
    assert not g.eval("NS.db.errors")


def test_wowhead_dungeon_quest_lists_add_new_forever_dungeons_without_questie_locations(style):
    # Questie has no location for these (outdoor giver, no zone): Wowhead's per-dungeon lists still place them.
    g=game(style,r'''
    QUESTIE_QUESTS[95788]={name="Drowned City errand",questLevel=36,startedBy={{197}}}
    QUESTIE_QUESTS[96246]={name="Blackmaw errand",questLevel=56,startedBy={{197}}}
    QUESTIE_QUESTS[96403]={name="Thanes errand",questLevel=14,startedBy={{197}}}
    ''')
    rows={r.id:r for r in g.eval("NS.dungeonQuests._results()").values()}
    assert rows[95788].dungeons[16550] and rows[96246].dungeons[16554] and rows[96403].dungeons[16919]
    assert "The Drowned City" in rows[95788].dungeonText and "Blackmaw Hold" in rows[96246].dungeonText
    loot=g.eval("NS.loot")
    assert loot.dungeonOf(16985)==16667 and loot.dungeonOf(17780)==16842
    assert not g.eval("NS.db.errors")


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
