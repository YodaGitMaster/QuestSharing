"""Westfall-only quest plans and readable grouped travel/work instructions."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game
from test_quest_planner_ui import DATA, planner_rows

WESTFALL = DATA + r'''
QUESTS={}
MAP_ID, ZONE, POS=1436,"Westfall",{x=0.5,y=0.5}
QUESTIE_QUESTS={
 [9000]={name="Local Harvest",questLevel=8,startedBy={{600}},objectives={{{601}}},finishedBy={{600}}},
 [9001]={name="Other Continent Quest",questLevel=8,startedBy={{700}},objectives={{{701}}},finishedBy={{700}}},
 [9002]={name="Foreign Active Quest",questLevel=8,startedBy={{700}},objectives={{{701}}},finishedBy={{700}}},
}
QUESTIE_NPCS={
 [600]={name="Sentinel Hill Giver",spawns={[40]={{55,45}}}},
 [601]={name="Harvest Watcher",spawns={[40]={{44,50}}}},
 [700]={name="Faraway Giver",spawns={[12]={{50,50}}}},
 [701]={name="Faraway Creature",spawns={[12]={{60,60}}}},
}
QuestDB.GetAllIds=function() local ids={};for id in pairs(QUESTIE_QUESTS) do ids[#ids+1]=id end;table.sort(ids);return ids end
QuestDB.Get=function(id,key) local q=QUESTIE_QUESTS[id];return q and q[key] end
NpcDB.Get=function(id,key) local n=QUESTIE_NPCS[id];return n and n[key] end
LibQuestieDB.Support.Get=function(name)
 if name=="ZoneDB" then return {private={areaIdToUiMapId="return {[12]=1429,[40]=1436,[999]=2001}",areaIdToUiMapIdOverride="return {}"}} end
end
C_Map.GetMapInfo=function(id)
 return ({[1436]={name="Westfall",mapType=3,parentMapID=100},
          [1429]={name="Other Zone",mapType=3,parentMapID=100},
          [2001]={name="Sentinel Hill",mapType=4,parentMapID=1436},
          [100]={name="Eastern Kingdoms",mapType=2,parentMapID=0}})[id]
end
-- Some map APIs return an unusable rectangle rather than nil for unrelated maps.
C_Map.GetMapRectOnMap=function() return 0,0,0,0 end
C_Map.GetMapInfoAtPosition=function(map,x,y)
 if map==1436 and x>0.5 then return {name="Sentinel Hill",mapID=2001,mapType=4,parentMapID=1436} end
end
QUESTS={{id=9002,title="Foreign Active Quest",level=8,objectives={{text="Faraway Creature slain: 0/8",type="monster",have=0,need=8}}}}
'''


def game(style, extra=""):
    g = Game(style, WESTFALL + extra, fresh=True)
    g.start()
    g.eval("NS.setSetting")("questPlanner", True)
    g.advance(5)
    return g


def rows(g):
    return [row for row in planner_rows(g)[3] if row.shown]


def text(g):
    return "\n".join(row.title.text + "\n" + row.detail.text for row in rows(g))


def test_zero_rectangle_cannot_pull_worldwide_quests_into_westfall(style):
    g = game(style)
    output = text(g)
    assert "Local Harvest" in output
    assert "Other Continent Quest" not in output
    assert "Foreign Active Quest" not in output
    for row in rows(g):
        row.scripts.OnClick(row, "LeftButton")
        assert g.eval("WAYPOINT.map") == 1436
        assert g.eval("WAYPOINT.x") > 0 and g.eval("WAYPOINT.y") > 0


def test_plausible_rectangle_does_not_make_a_sibling_zone_local(style):
    g = game(style, "C_Map.GetMapRectOnMap=function() return 0,1,0,1 end")
    output = text(g)
    assert "Local Harvest" in output and "Faraway" not in output and "Foreign" not in output


def test_named_travel_pickup_work_and_turnin_steps_follow_dependencies(style):
    g = game(style)
    visible = rows(g)
    assert len(visible) == 3
    assert "Step 1" in visible[0].title.text and "Go to Sentinel Hill" in visible[0].title.text
    assert "Take these quests" in visible[0].detail.text
    assert "Complete these quests here" in visible[1].detail.text
    assert "Hand in these quests" in visible[2].detail.text
    assert all("[1]" in row.detail.text for row in visible)
    assert "TRIP" not in text(g)


def test_valid_child_map_belongs_to_westfall_but_remote_map_does_not(style):
    g = game(style, '''
QUESTIE_NPCS[600].spawns={[999]={{50,50}}}
C_Map.GetMapRectOnMap=function(child,parent)
 if child==2001 and parent==1436 then return 0.5,0.6,0.4,0.5 end
 return 0,1,0,1
end
''')
    output = text(g)
    assert "Local Harvest" in output and "Other Continent Quest" not in output


def test_new_quests_with_only_remote_work_are_not_recommended(style):
    g = game(style, '''
QUESTIE_QUESTS[9003]={name="Travel Around The World",questLevel=8,startedBy={{600}},objectives={{{701}}},finishedBy={{700}}}
''')
    assert "Travel Around The World" not in text(g)


def test_incomplete_offzone_objective_cannot_unlock_turnin_or_followup(style):
    g = game(style, '''
QUESTIE_QUESTS[9000].objectives={{{601},{701}}}
QUESTIE_QUESTS[9004]={name="Premature Followup",questLevel=8,startedBy={{600}},preQuestSingle={9000}}
QUESTS={{id=9000,title="Local Harvest",level=8,objectives={
 {text="Harvest Watcher slain: 0/8",type="monster",have=0,need=8},
 {text="Faraway Creature slain: 0/8",type="monster",have=0,need=8}}}}
QuestieLoader.ImportModule=function(_,name)
 if name=="QuestieDB" then return {
  IsDoable=function(id) return id~=9004 end,
  IsDoableVerbose=function() return nil,true,1 end,
  DoableStates={NO_PREQUESTSINGLE=1},
 } end
end
''')
    output = text(g)
    assert "Harvest Watcher" in output
    assert "Turn in Local Harvest" not in output
    assert "Premature Followup" not in output


def test_grouped_objectives_list_every_quest_and_action_without_hidden_more(style):
    extra = '''
for id=9005,9009 do
 QUESTIE_QUESTS[id]={name="Local Task "..id,questLevel=8,startedBy={{600}},objectives={{{601}}},finishedBy={{600}}}
end
'''
    g = game(style, extra)
    objectives = [row.detail.text for row in rows(g) if "Complete these quests here" in row.detail.text]
    assert len(objectives) == 1
    for quest_id in range(9005, 9010):
        assert "Local Task " + str(quest_id) in objectives[0]
    assert "+" not in objectives[0]


def test_prerequisite_followup_at_same_giver_waits_until_parent_handin(style):
    g = game(style, '''
QUESTIE_QUESTS[9004]={name="Followup Harvest",questLevel=8,startedBy={{600}},
 objectives={{{601}}},finishedBy={{600}},preQuestSingle={9000}}
QuestieLoader.ImportModule=function(_,name)
 if name=="QuestieDB" then return {
  IsDoable=function(id) return id~=9004 end,
  IsDoableVerbose=function() return nil,true,1 end,
  DoableStates={NO_PREQUESTSINGLE=1},
 } end
end
''')
    output = [row.detail.text for row in rows(g)]
    pickup = next(i for i,t in enumerate(output) if "Pick up Followup Harvest" in t)
    handin = next(i for i,t in enumerate(output) if "Turn in Local Harvest" in t)
    assert pickup > handin


def test_changing_zones_clears_stale_steps_before_debounced_rescan(style):
    g = game(style)
    assert "Local Harvest" in text(g)
    g.run('MAP_ID=1429; ZONE="Other Zone"')
    g.fire("ZONE_CHANGED_NEW_AREA")
    assert "Local Harvest" not in text(g)
    g.advance(3)
    assert "Local Harvest" not in text(g)
    assert "Other Continent Quest" in text(g)


def test_completed_active_quest_can_have_a_local_turnin_even_if_started_elsewhere(style):
    g = game(style, '''
QUESTIE_QUESTS[9002].finishedBy={{600}}
QUESTS[1].complete=true
''')
    assert "Turn in Foreign Active Quest" in text(g)
    assert "Faraway Creature" not in text(g)


def test_completion_rescan_adds_a_previously_blocked_local_turnin(style):
    g = game(style, '''
QUESTIE_QUESTS[9002].finishedBy={{600}}
''')
    assert "Foreign Active Quest" not in text(g)
    g.run("QUESTS[1].complete=true")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(3)
    assert "Turn in Foreign Active Quest" in text(g)


def test_invalid_local_spawn_coordinates_do_not_become_zero_point_steps(style):
    g = game(style, '''
QUESTIE_NPCS[600].spawns={[40]={{-1,45},{101,45},{0/0,45}}}
''')
    assert "Local Harvest" not in text(g)


def test_degenerate_child_rectangle_is_rejected_even_with_correct_ancestry(style):
    g = game(style, "QUESTIE_NPCS[600].spawns={[999]={{50,50}}}")
    assert "Local Harvest" not in text(g)


def test_accepting_and_completing_quest_advances_from_pickup_to_work_to_handin(style):
    g = game(style)
    assert "Take these quests" in text(g)
    g.run('''QUESTS={{id=9000,title="Local Harvest",level=8,
 objectives={{text="Harvest Watcher slain: 0/8",type="monster",have=0,need=8}}}}''')
    g.fire("QUEST_ACCEPTED", 1, 9000)
    g.advance(3)
    assert "Pick up Local Harvest" not in text(g)
    assert "Complete these quests here" in text(g)
    g.run("QUESTS[1].complete=true; QUESTS[1].objectives[1].finished=true")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(3)
    assert len(rows(g)) == 1
    assert "Turn in Local Harvest" in text(g)
    assert "Kill Harvest Watcher" not in text(g)


if __name__ == "__main__":
    failed = total = 0
    for name, test in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        for style in ("modern", "classic"):
            total += 1
            try:
                test(style)
                print("ok", name, style)
            except Exception as error:
                failed += 1
                print("FAIL", name, style, type(error).__name__, str(error)[:300])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
