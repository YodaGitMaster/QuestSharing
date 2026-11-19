"""Westfall-only quest plans and readable grouped travel/work instructions."""
import pathlib
import re
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
    assert "Pick up from Sentinel Hill Giver:" in visible[0].detail.text
    assert "Complete these quests here" in visible[1].detail.text
    assert "Hand in to Sentinel Hill Giver:" in visible[2].detail.text
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
    assert "Hand in to" not in output
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
    pickup = next(i for i,t in enumerate(output) if "Pick up from" in t and "Followup Harvest" in t)
    handin = next(i for i,t in enumerate(output) if "Hand in to" in t and "Local Harvest" in t)
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
    assert re.search(r"Hand in to Sentinel Hill Giver:(\n\[\d\] [^\n]*)*\n\[\d\] Foreign Active Quest", text(g)), text(g)
    assert "Faraway Creature" not in text(g)


def test_completion_rescan_adds_a_previously_blocked_local_turnin(style):
    g = game(style, '''
QUESTIE_QUESTS[9002].finishedBy={{600}}
''')
    assert "Foreign Active Quest" not in text(g)
    g.run("QUESTS[1].complete=true")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(3)
    assert re.search(r"Hand in to Sentinel Hill Giver:(\n\[\d\] [^\n]*)*\n\[\d\] Foreign Active Quest", text(g)), text(g)


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
    assert "Pick up from Sentinel Hill Giver:" in text(g)
    g.run('''QUESTS={{id=9000,title="Local Harvest",level=8,
 objectives={{text="Harvest Watcher slain: 0/8",type="monster",have=0,need=8}}}}''')
    g.fire("QUEST_ACCEPTED", 1, 9000)
    g.advance(3)
    assert "Pick up from" not in text(g)
    assert "Complete these quests here" in text(g)
    g.run("QUESTS[1].complete=true; QUESTS[1].objectives[1].finished=true")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(3)
    assert len(rows(g)) == 1
    assert "Hand in to Sentinel Hill Giver:\n[1] Local Harvest" in text(g)
    assert "Kill Harvest Watcher" not in text(g)


CAMP = r'''
QUESTIE_QUESTS[9000],QUESTIE_QUESTS[9001],QUESTIE_QUESTS[9002]=nil,nil,nil
QUESTIE_NPCS[610]={name="Harvest Watcher",spawns={[40]={
 {50.4,50.3},{70.3,70.2},
 {30,30},{31,32},{29,31},{32,29},{30.5,28.5},{28.5,30.5},
}}}
QUESTIE_QUESTS[9100]={name="Harvest Patrol",questLevel=8,zoneOrSort=40,startedBy={{600}},objectives={{{610}}},finishedBy={{600}}}
QUESTS={{id=9100,title="Harvest Patrol",level=8,objectives={{text="Harvest Watcher slain: 0/8",type="monster",have=0,need=8}}}}
'''


def objective_waypoint(g):
    row = next(r for r in rows(g) if "Complete these quests here" in r.detail.text)
    row.scripts.OnClick(row, "LeftButton")
    return g.eval("WAYPOINT.x"), g.eval("WAYPOINT.y")


def near(point, x, y):
    return abs(point[0] - x) < 0.02 and abs(point[1] - y) < 0.02


def test_objective_goes_to_a_real_camp_not_a_lone_spawn_by_the_player(style):
    g = game(style, CAMP)
    point = objective_waypoint(g)
    assert near(point, 0.30, 0.30), point
    g.run("POS.x, POS.y = 0.70, 0.70")
    g.advance(8)
    point = objective_waypoint(g)
    assert near(point, 0.30, 0.30), point


def test_objective_switches_camp_only_when_another_real_camp_is_nearer(style):
    g = game(style, CAMP + '''
for _, p in ipairs({{80,80},{81,79},{79,81}}) do table.insert(QUESTIE_NPCS[610].spawns[40], p) end
''')
    assert near(objective_waypoint(g), 0.30, 0.30)
    g.run("POS.x, POS.y = 0.52, 0.52")
    g.advance(8)
    assert near(objective_waypoint(g), 0.30, 0.30)
    g.run("POS.x, POS.y = 0.75, 0.75")
    g.advance(8)
    assert near(objective_waypoint(g), 0.80, 0.80)


PICKUP = r'''
QUESTIE_QUESTS[9000]=nil
QUESTIE_OBJECTS[900]={name="Heavenly Bloom",spawns={[40]={{52,52},{90,90},{91,91}}}}
QUESTIE_ITEMS[900]={name="Heavenly Bloom",objectDrops={900}}
QUESTIE_QUESTS[9300]={name="Bloom of the Heavens",questLevel=8,startedBy={{600}},finishedBy={{600}},
 objectives={nil,nil,{{900}}},objectivesText={"Bring %d Heavenly Bloom to the Sentinel Hill giver."}}
QUESTS={{id=9300,title="Bloom of the Heavens",level=8,objectives={{text="Heavenly Bloom: 0/%d",type="item",have=0,need=%d}}}}
'''


def pickup_game(style, count=1):
    return game(style, PICKUP % (count, count, count))


def test_item_picked_up_from_a_world_object_goes_to_the_nearest_object_not_a_far_camp(style):
    g = pickup_game(style)
    # One flower stands next to the player; two more stand together far away. One pickup needs only the nearest.
    point = objective_waypoint(g)
    assert near(point, 0.52, 0.52), point


def test_item_picked_up_from_a_world_object_costs_seconds_not_a_guessed_minute(style):
    for count in (1, 3):
        g = pickup_game(style, count)
        report = g.eval("NS.questPlanner.report")()
        # Pickups of the item plus the hand-in: a few seconds each, never the 60 s "unknown work" estimate.
        assert report.workSeconds <= 3 * count + 3 + 1e-9, (count, report.workSeconds)
        assert not report.uncertain
        assert "Work time estimated" not in text(g)


def test_object_pickup_step_reads_pick_up_without_repeating_the_name(style):
    g = pickup_game(style)
    assert "Pick up Heavenly Bloom" in text(g), text(g)
    assert "from Heavenly Bloom" not in text(g)


FOREIGN_STRAY = r'''
QUESTIE_QUESTS[9000],QUESTIE_QUESTS[9001],QUESTIE_QUESTS[9002]=nil,nil,nil
QUESTIE_NPCS[702]={name="Prowler",spawns={[12]={{40,40},{41,42},{43,41}},[40]={{52,49}}}}
QUESTIE_QUESTS[9200]={name="Elwynn Prowlers",questLevel=8,zoneOrSort=12,startedBy={{700}},objectives={{{702}}},finishedBy={{700}}}
QUESTS={{id=9200,title="Elwynn Prowlers",level=8,objectives={{text="Prowler slain: 0/6",type="monster",have=0,need=6}}}}
'''


def test_lone_local_spawn_cannot_pull_a_foreign_active_quest_into_the_plan(style):
    g = game(style, FOREIGN_STRAY)
    assert "Elwynn Prowlers" not in text(g)
    assert "Other Zone" in str(g.eval("NS.questPlanner.coverage().external[9200]"))
    # Even without a zone filing, one stray is not a real camp while the mob's camp is elsewhere.
    g = game(style, FOREIGN_STRAY + "QUESTIE_QUESTS[9200].zoneOrSort=nil")
    assert "Elwynn Prowlers" not in text(g)


def test_only_quests_filed_under_this_zone_are_planned_even_with_a_local_giver(style):
    g = game(style, '''
QUESTIE_QUESTS[9000].zoneOrSort=40
QUESTIE_QUESTS[9010]={name="Class Trial",questLevel=8,zoneOrSort=-81,startedBy={{600}},objectives={{{601}}},finishedBy={{600}}}
QUESTIE_QUESTS[9011]={name="Elwynn Errand",questLevel=8,zoneOrSort=12,startedBy={{600}},objectives={{{601}}},finishedBy={{600}}}
QUESTIE_QUESTS[9012]={name="Sentinel Hill Duty",questLevel=8,zoneOrSort=999,startedBy={{600}},objectives={{{601}}},finishedBy={{600}}}
QUESTIE_QUESTS[9013]={name="Unmapped Area Task",questLevel=8,zoneOrSort=5555,startedBy={{600}},objectives={{{601}}},finishedBy={{600}}}
''')
    output = text(g)
    assert "Local Harvest" in output
    assert "Sentinel Hill Duty" in output      # filed under a sub-zone map of Westfall
    assert "Unmapped Area Task" in output      # an unresolved filing keeps the location rule
    assert "Class Trial" not in output
    assert "Elwynn Errand" not in output
    external = g.eval("NS.questPlanner.coverage().external")
    assert "Class" in str(external[9010])
    assert "Other Zone" in str(external[9011])


def test_quest_from_another_zone_appears_only_for_its_ready_local_handin(style):
    base = '''
QUESTIE_QUESTS[9002].zoneOrSort=12
QUESTIE_QUESTS[9002].finishedBy={{600}}
'''
    assert "Foreign Active Quest" not in text(game(style, base))
    g = game(style, base + "QUESTS[1].complete=true")
    assert re.search(r"Hand in to Sentinel Hill Giver:(\n\[\d\] [^\n]*)*\n\[\d\] Foreign Active Quest", text(g)), text(g)
    assert "Faraway Creature" not in text(g)
    # A breadcrumb has nothing to do but hand in, so it is ready as soon as it is in the log.
    g = game(style, '''
QUESTIE_QUESTS[9014]={name="Report to Sentinel Hill",questLevel=8,zoneOrSort=12,startedBy={{700}},finishedBy={{600}}}
QUESTS={{id=9014,title="Report to Sentinel Hill",level=8,objectives={}}}
''')
    assert re.search(r"Hand in to Sentinel Hill Giver:\n\[\d\] Report to Sentinel Hill", text(g)), text(g)


TWO_CAMPS = CAMP + '''
for _, p in ipairs({{80,80},{81,79},{79,81}}) do table.insert(QUESTIE_NPCS[610].spawns[40], p) end
'''

# Shortest Path Forever builds. The guide uses SPF only for the optional Follow arrow and never to plan, so every
# build must leave the plan exactly as it is without SPF, and none is ever asked for walking estimates
# (SPF_ESTIMATES stays 0). v2.3 can estimate walks: walking to the 30,30 camp costs WALK_FACTOR times the straight
# line (a river detour). If the guide did ask, spf_tick would deliver the answer 0.4 s later (or a failed estimate
# when SPF_FAIL is set), so a guide that used the estimates would plan differently.
SPF_WALKS = r'''
SPF_ESTIMATES, SPF_PENDING, SPF_FAIL = 0, nil, nil
ShortestPathForever = { API = { version = 2, minor = 3,
 Navigate = function() return true end,
 EstimateWalks = function(owner, from, targets, callback)
  SPF_ESTIMATES = SPF_ESTIMATES + 1
  local costs = {}
  for i, t in ipairs(targets) do
   local dx, dy = (t.x - from.x) * 3000, (t.y - from.y) * 2000
   costs[i] = math.sqrt(dx * dx + dy * dy)
   if math.abs(t.x - 0.30) < 0.03 and math.abs(t.y - 0.30) < 0.03 then costs[i] = costs[i] * WALK_FACTOR end
  end
  local job = { callback = callback, costs = costs }
  SPF_PENDING = job
  return function() job.cancelled = true end
 end } }
function SPF_DELIVER()
 local job = SPF_PENDING; SPF_PENDING = nil
 if job and not job.cancelled then
  if SPF_FAIL then job.callback(nil, SPF_FAIL) else job.callback(job.costs) end
 end
end
'''

# Builds that can navigate but cannot estimate walks (v1, or v2 before minor 3).
SPF_NAVIGATE_ONLY = (
    "SPF_ESTIMATES = 0\nShortestPathForever = { API = { version = 1, Navigate = function() return true end } }\n",
    "SPF_ESTIMATES = 0\nShortestPathForever = { API = { version = 2, minor = 2, Navigate = function() return true end,"
    " EstimateWalks = function() SPF_ESTIMATES = SPF_ESTIMATES + 1 end } }\n",
)

# Every build: navigate-only, estimates that would make the west camp three or one and a half times as far,
# and estimates that always fail.
SPF_BUILDS = SPF_NAVIGATE_ONLY + (
    SPF_WALKS + "WALK_FACTOR=3\n",
    SPF_WALKS + "WALK_FACTOR=1.5\n",
    SPF_WALKS + 'WALK_FACTOR=3\nSPF_FAIL="no-path"\n',
)

# Every route the guide renders, as the camp of its objective step.
RENDER_LOG = r'''
CAMP_RENDERS = {}
local G = NS.questGuidance
local set = G.set
G.set = function(route, index, ...)
 for _, stop in ipairs(route) do
  if stop.kind == "objective" then CAMP_RENDERS[#CAMP_RENDERS + 1] = string.format("%.2f,%.2f", stop.point.x, stop.point.y) end
 end
 return set(route, index, ...)
end
'''


def spf_tick(g, seconds):
    """Advances the clock; an SPF asked for walking estimates answers 0.4 s after the request."""
    for _ in range(int(seconds * 10)):
        g.advance(0.1)
        if g.eval("SPF_PENDING") is not None:
            g.advance(0.4)
            g.run("SPF_DELIVER()")


def spf_game(style, extra=""):
    g = Game(style, WESTFALL + extra, fresh=True)
    g.run(RENDER_LOG)
    g.start()
    g.eval("NS.setSetting")("questPlanner", True)
    spf_tick(g, 5)
    return g


# The player walks from the middle (0.50) towards the east camp B (0.80) and back towards the west camp A (0.30).
CAMP_WALK = (0.53, 0.56, 0.65, 0.56, 0.53, 0.44, 0.53)


def camp_timeline(style, extra, positions=CAMP_WALK):
    """The objective's camp and every step's text after the first plan and after each move."""
    g = spf_game(style, extra)

    def plan():
        renders = list(g.eval("CAMP_RENDERS").values())
        return {"0.30,0.30": "A", "0.80,0.80": "B"}[renders[-1]], text(g)

    plans = [plan()]
    for x in positions:
        g.run(f"POS.x, POS.y = {x}, {x}")
        spf_tick(g, 4)
        plans.append(plan())
    return plans, g


def test_objective_camp_switches_only_when_clearly_cheaper_and_never_flips_back(style):
    # The guide keeps the camp it chose until another one is cheaper by a quarter of the visit's cost and at least
    # 20 s. At 0.56 the east camp is only about 10 s nearer; at 0.65 it is clearly cheaper. Walking back keeps it
    # until the west camp is clearly cheaper again (0.44), so standing near the middle never flips the step.
    plans, _ = camp_timeline(style, TWO_CAMPS)
    assert [camp for camp, _ in plans] == ["A", "A", "A", "B", "B", "B", "A", "A"], [camp for camp, _ in plans]


def test_spf_is_never_asked_for_walks_and_the_guide_plans_as_without_it(style):
    expected, _ = camp_timeline(style, TWO_CAMPS)
    for spf in SPF_BUILDS:
        plans, g = camp_timeline(style, TWO_CAMPS + spf)
        assert g.eval("SPF_ESTIMATES") == 0, (spf, g.eval("SPF_ESTIMATES"))
        assert [camp for camp, _ in plans] == [camp for camp, _ in expected], (spf, plans)
        assert plans == expected, spf


MIXED = r'''
QUESTIE_QUESTS[9000],QUESTIE_QUESTS[9001],QUESTIE_QUESTS[9002]=nil,nil,nil
QUESTIE_QUESTS[9300]={name="Bog Hides",questLevel=8,zoneOrSort=40,startedBy={{600}},objectives={nil,nil,{{77}}},finishedBy={{600}}}
QUESTIE_ITEMS[77]={name="Bog Hide",npcDrops={630,631}}
ItemDB.Get=function(id,key) local t=QUESTIE_ITEMS[id];return t and t[key] end
local old=QuestieLoader.ImportModule
QuestieLoader.ImportModule=function(self,name)
 if name=="DropDB" then return {GetItemDroprate=function() return {40,"fixture"} end} end
 return old(self,name)
end
QUESTS={{id=9300,title="Bog Hides",level=8,objectives={{text="Bog Hide: 0/6",type="item",have=0,need=6}}}}
'''


def test_mixed_creature_camp_stays_real_when_one_creature_gathers_elsewhere(style):
    # Two creatures share one local camp (2 + 2 spawns); one of them also has a 3-spawn camp in another zone.
    g = game(style, MIXED + '''
QUESTIE_NPCS[630]={name="Bog Crawler",spawns={[40]={{25,65},{26,66}},[12]={{40,40},{41,41},{40.5,42}}}}
QUESTIE_NPCS[631]={name="Bog Stalker",spawns={[40]={{25.5,66},{26,65}}}}
''')
    assert "Collect Bog Hide" in text(g)
    assert near(objective_waypoint(g), 0.255, 0.655), objective_waypoint(g)


def test_nearby_mixed_camp_beats_a_far_single_creature_camp(style):
    # The mixed camp is next to the player; one creature also gathers in a 3-spawn camp across the zone.
    g = game(style, MIXED + '''
QUESTIE_NPCS[630]={name="Bog Crawler",spawns={[40]={{48,52},{49,53},{85,15},{86,16},{85.5,14.5}}}}
QUESTIE_NPCS[631]={name="Bog Stalker",spawns={[40]={{48.5,53},{49,52}}}}
''')
    assert near(objective_waypoint(g), 0.485, 0.525), objective_waypoint(g)


# Not yet accepted: the guide walks to the giver first, and from there the east camp is the cheaper one,
# although the west camp is nearer to the player (so it is the objective's default place).
BUSY_CAMPS = r'''
QUESTIE_QUESTS[9000],QUESTIE_QUESTS[9001],QUESTIE_QUESTS[9002]=nil,nil,nil
QUESTIE_NPCS[610]={name="Harvest Watcher",spawns={[40]={
 {30,30},{31,32},{29,31},{32,29},{30.5,28.5},{28.5,30.5},
 {62,40},{63,41},{61,39},
}}}
QUESTIE_QUESTS[9100]={name="Harvest Patrol",questLevel=8,zoneOrSort=40,startedBy={{600}},objectives={{{610}}},finishedBy={{600}}}
QUESTS={}
POS={x=0.40,y=0.40}
'''


def mark_objective_camp_busy(g):
    objective_waypoint(g)  # selects the objective step
    g.eval("NS.questPlanner.markCampBusy")()
    spf_tick(g, 5)


def clear_camp_wait(g):
    g.eval("NS.questPlanner.clearCampWaits")()
    spf_tick(g, 5)


def test_camp_busy_also_applies_to_an_alternative_camp(style):
    g = game(style, BUSY_CAMPS)
    assert near(objective_waypoint(g), 0.62, 0.40), objective_waypoint(g)
    assert g.eval("NS.questPlanner.report")().waitSeconds == 0
    # The chosen camp is an alternative of the objective; marking it busy sends the guide to the free camp.
    mark_objective_camp_busy(g)
    assert near(objective_waypoint(g), 0.30, 0.30), objective_waypoint(g)
    assert g.eval("NS.questPlanner.report")().waitSeconds == 0
    # Every camp busy: the guide still plans the work and waits for the camp that frees up first.
    mark_objective_camp_busy(g)
    assert near(objective_waypoint(g), 0.62, 0.40), objective_waypoint(g)
    assert g.eval("NS.questPlanner.report")().waitSeconds > 0
    clear_camp_wait(g)
    assert near(objective_waypoint(g), 0.62, 0.40), objective_waypoint(g)
    assert g.eval("NS.questPlanner.report")().waitSeconds == 0


def test_marking_or_clearing_a_busy_camp_refines_the_route_again(style):
    from test_quest_optimizer import COUNT_REFINES
    g = Game(style, WESTFALL + BUSY_CAMPS, fresh=True)
    g.run(COUNT_REFINES)
    g.start()
    g.eval("NS.setSetting")("questPlanner", True)
    g.advance(5)
    refines = g.eval("REFINES")
    assert refines >= 1
    # Busy camps are plan inputs: the local search runs again for the new set of free camps.
    mark_objective_camp_busy(g)
    assert g.eval("REFINES") == refines + 1, (refines, g.eval("REFINES"))
    clear_camp_wait(g)
    assert g.eval("REFINES") == refines + 2, (refines, g.eval("REFINES"))


def test_busy_default_camp_gives_way_to_a_free_alternative(style):
    for spf in ("",) + SPF_BUILDS:
        g = spf_game(style, TWO_CAMPS + spf)
        assert near(objective_waypoint(g), 0.30, 0.30), (spf, objective_waypoint(g))
        mark_objective_camp_busy(g)
        assert near(objective_waypoint(g), 0.80, 0.80), (spf, objective_waypoint(g))
        assert g.eval("NS.questPlanner.report")().waitSeconds == 0
        # "Clear camp wait" forgets the busy camp, and the guide goes back to the camp it chose before.
        clear_camp_wait(g)
        assert near(objective_waypoint(g), 0.30, 0.30), (spf, objective_waypoint(g))
        assert g.eval("SPF_ESTIMATES or 0") == 0, spf


def test_clear_camp_wait_chooses_the_camp_afresh_from_where_you_stand(style):
    for spf in ("",) + SPF_BUILDS:
        g = spf_game(style, TWO_CAMPS + spf)
        g.run("POS.x, POS.y = 0.65, 0.65")
        spf_tick(g, 4)
        assert near(objective_waypoint(g), 0.80, 0.80), (spf, objective_waypoint(g))
        mark_objective_camp_busy(g)
        assert near(objective_waypoint(g), 0.30, 0.30), (spf, objective_waypoint(g))
        g.run("POS.x, POS.y = 0.53, 0.53")
        spf_tick(g, 4)
        assert near(objective_waypoint(g), 0.30, 0.30), (spf, objective_waypoint(g))
        # Clearing forgets the remembered camps as well: from 0.53 the west camp is nearer, so the guide does not
        # send you back to the east camp it held before the busy mark.
        clear_camp_wait(g)
        assert near(objective_waypoint(g), 0.30, 0.30), (spf, objective_waypoint(g))
        assert g.eval("SPF_ESTIMATES or 0") == 0, spf


def test_camp_chosen_before_a_busy_mark_returns_when_the_wait_ends(style):
    for spf in ("",) + SPF_BUILDS:
        g = spf_game(style, TWO_CAMPS + spf)
        assert near(objective_waypoint(g), 0.30, 0.30), (spf, objective_waypoint(g))
        mark_objective_camp_busy(g)
        assert near(objective_waypoint(g), 0.80, 0.80), (spf, objective_waypoint(g))
        # The camp the busy mark forced is not remembered as the guide's choice: once the five minutes are over,
        # the next re-plan (a small step) returns to the west camp instead of holding on to the east one.
        g.advance(301)
        g.run("POS.x, POS.y = 0.52, 0.52")
        spf_tick(g, 4)
        assert "plan origin: map 1436 (0.5200, 0.5200)" in g.eval("NS.questPlanner.debugText")()
        assert near(objective_waypoint(g), 0.30, 0.30), (spf, objective_waypoint(g))
        assert g.eval("SPF_ESTIMATES or 0") == 0, spf


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
