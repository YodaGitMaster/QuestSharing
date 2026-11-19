"""Quest planner panel movement, readable pickup rows, level bands, and map actions."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402


DATA = r'''
QUESTIE_QUESTS = {
    [8100] = { name="Green Quest", questLevel=8, requiredLevel=1, startedBy={{197}} },
    [8101] = { name="Yellow Quest With A Long Name That Must Wrap Onto Its Own Readable Lines", questLevel=10, requiredLevel=1, startedBy={{197}} },
    [8102] = { name="Too Low Quest", questLevel=5, requiredLevel=1, startedBy={{197}} },
    [8103] = { name="Too High Quest", questLevel=15, requiredLevel=1, startedBy={{197}} },
    [8104] = { name="Another Long Pickup Quest That Needs Its Own Space", questLevel=8, requiredLevel=1, startedBy={{198}} },
}
QUESTIE_NPCS = {
    [197] = { name="Town Quest Giver", spawns={ [12]={{48, 41}} } },
    [198] = { name="Second Quest Giver", spawns={ [12]={{80, 60}} } },
}
QUESTIE_ITEMS, QUESTIE_OBJECTS = {}, {}
local function getter(t) return function(id, key) local r=t[id]; return r and r[key] end end
QuestDB = { Get=getter(QUESTIE_QUESTS), GetAllIds=function() return {8100,8101,8102,8103,8104} end }
NpcDB, ItemDB, ObjectDB = {Get=getter(QUESTIE_NPCS)}, {Get=getter(QUESTIE_ITEMS)}, {Get=getter(QUESTIE_OBJECTS)}
LibQuestieDB = { Support={ Get=function(name)
    if name == "ZoneDB" then return { private={ areaIdToUiMapId="return { [12]=1429 }", areaIdToUiMapIdOverride="return {}" } } end
end } }
QuestieLoader = { ImportModule=function(_, name)
    if name == "QuestieDB" then return { IsDoable=function() return true end } end
end }
Enum = { UIMapType={ Zone=3 } }
C_Map.GetMapInfo=function(map) if map == 1429 then return {name="Elwynn Forest", mapType=3} end end
C_Map.IsCityMap=function() return false end
C_Map.OpenWorldMap=function(map) OPENED_MAP=map end
QuestDifficultyColors = {
    trivial={r=0.5,g=0.5,b=0.5}, standard={r=0.1,g=0.8,b=0.1}, difficult={r=1,g=1,b=0},
    verydifficult={r=1,g=0.5,b=0.1}, impossible={r=1,g=0.1,b=0.1},
}
GetQuestDifficultyColor=function(level)
    if level <= 5 then return QuestDifficultyColors.trivial end
    if level <= 8 then return QuestDifficultyColors.standard end
    if level <= 10 then return QuestDifficultyColors.difficult end
    return QuestDifficultyColors.verydifficult
end
'''


def planner_game(pre=DATA, scope="green-yellow"):
    g = Game("modern", pre, fresh=True)
    g.start()
    g.run("NS.db.questPlannerScope = %r" % scope)
    g.eval("NS.setSetting")("questPlanner", True)
    g.advance(5)
    return g


def planner_rows(g):
    panel = g.eval("QuestSharingPlannerPanel")
    scroll = next(panel.children[i] for i in range(1, len(panel.children) + 1)
                  if getattr(panel.children[i], "scrollChild", None) is not None)
    content = scroll.scrollChild
    rows = []
    for i in range(1, len(content.children) + 1):
        child = content.children[i]
        scripts = getattr(child, "scripts", None)
        if scripts is not None and scripts["OnClick"] is not None:
            rows.append(child)
    return panel, scroll, content, rows


def test_panel_is_movable_and_keeps_user_position_for_session():
    g = planner_game()
    panel, _, _, _ = planner_rows(g)
    assert panel.movable is True
    assert panel.scripts["OnDragStart"] is not None
    assert panel.scripts["OnDragStop"] is not None
    panel.SetPoint(panel, "CENTER", g.eval("UIParent"), "CENTER", 0, 0)
    panel.scripts["OnDragStop"](panel)
    before = [panel.point[i] for i in range(1, 6)]
    g.eval("NS.questPlanner.open")()
    after = [panel.point[i] for i in range(1, 6)]
    assert after[0] == before[0] and after[2:] == before[2:]


def test_only_green_and_yellow_quests_appear_as_line_by_line_pickups():
    g = planner_game()
    _, _, _, rows = planner_rows(g)
    assert len(rows) == 2
    details = []
    for row in rows:
        details.append(next(row.children[i] for i in range(1, len(row.children) + 1)
                            if getattr(row.children[i], "isFontString", False)
                            and "Pick up" in row.children[i].text).text)
    all_details = "\n".join(details)
    assert "Green Quest" in all_details
    assert "Yellow Quest With A Long Name" in all_details
    assert "Another Long Pickup Quest" in all_details
    assert "Too Low Quest" not in all_details
    assert "Too High Quest" not in all_details
    assert rows[0].height > 53
    assert rows[1].height >= 53


def test_wrapped_rows_get_separate_vertical_space_and_scroll_content_height():
    g = planner_game()
    _, _, content, rows = planner_rows(g)
    assert len(rows) == 2
    assert rows[0].height > 53
    assert rows[1].height >= 53
    assert rows[1].point[5] == -(rows[0].height + 3)
    assert content.height >= max(280, rows[0].height + rows[1].height + 6)


def test_right_click_marks_the_quest_giver_on_the_game_map():
    g = planner_game()
    _, _, _, rows = planner_rows(g)
    rows[0].scripts["OnClick"](rows[0], "RightButton")
    assert g.eval("OPENED_MAP") is None
    waypoint = g.eval("WAYPOINT")
    assert waypoint["map"] == 1429
    assert abs(waypoint["x"] - 0.48) < 0.001
    assert abs(waypoint["y"] - 0.41) < 0.001


def test_step_click_sets_the_waypoint_in_combat_too():
    # UX-47: one click action and one combat rule; a map waypoint is not a protected action.
    g = planner_game()
    _, _, _, rows = planner_rows(g)
    g.run("IN_COMBAT = true")
    rows[0].scripts["OnClick"](rows[0], "RightButton")
    assert g.eval("OPENED_MAP") is None
    assert g.eval("WAYPOINT") is not None


def test_all_trivial_local_quests_explain_zone_is_too_low_level():
    g = planner_game(DATA + "\nQuestDB.GetAllIds=function() return {8102} end")
    # Use one known, mapped quest; its API color is gray/trivial for this character.
    g.run('''QUESTIE_QUESTS = { [8102]={name="Too Low Quest", questLevel=5, requiredLevel=1, startedBy={{197}}} }
QuestDB.Get = function(id, key) local q=QUESTIE_QUESTS[id]; return q and q[key] end''')
    # Reload so the scan observes the reduced catalogue and Questie record.
    g.eval("NS.questPlanner.refresh")()
    g.advance(2)
    _, _, content, rows = planner_rows(g)
    assert rows == []
    assert any(content.children[i].isFontString and "This zone is too low level for you." in content.children[i].text
               for i in range(1, len(content.children) + 1))

# ---- The guide stays on: no blank list, no replan from noise, kept inside mines (2026-11-19) ----------------------
COUNT_SCANS = """PLAN_SCANS=0;local start=NS.dataWork.start
NS.dataWork.start=function(owner,...) if owner=='quest-plan' then PLAN_SCANS=PLAN_SCANS+1 end return start(owner,...) end"""
MINE = "\nlocal info=C_Map.GetMapInfo;C_Map.GetMapInfo=function(m) if m==9001 then return {name='Fargodeep Mine',mapType=5,parentMapID=1429} end return info(m) end\n"


def visible_rows(g):
    return sum(1 for r in planner_rows(g)[3] if r.shown)


def test_loot_reputation_skills_and_spells_do_not_replan_the_guide():
    g = planner_game(); g.run(COUNT_SCANS)
    for event in ("BAG_UPDATE_DELAYED", "UPDATE_FACTION", "SKILL_LINES_CHANGED", "SPELLS_CHANGED"):
        g.fire(event); g.advance(0.651)
        assert visible_rows(g) == 2, event + ": the steps stay on screen"
        g.advance(3)
    assert g.eval("PLAN_SCANS") == 0, "no replan without a quest log change"


def test_a_finished_quest_replans_without_blanking_the_list():
    g = planner_game(); g.run(COUNT_SCANS)
    g.run("QUESTS[#QUESTS+1]={id=8101,title='Green Quest',level=10,objectives={}}")
    g.fire("QUEST_ACCEPTED"); g.advance(0.651)
    assert visible_rows(g) == 2, "the old steps stay while the new route is built"
    g.advance(5)
    assert g.eval("PLAN_SCANS") == 1 and visible_rows(g) >= 1


def test_walking_does_not_replan_the_route():
    g = planner_game(); g.run(COUNT_SCANS)
    for _ in range(5):
        g.run("POS={x=POS.x+0.03,y=POS.y}"); g.advance(3.1)
    assert g.eval("PLAN_SCANS") == 0 and visible_rows(g) == 2


def test_a_mine_inside_the_zone_keeps_the_plan_and_coming_out_does_not_rebuild_it():
    g = planner_game(DATA + MINE); g.run(COUNT_SCANS)
    g.run("MAP_ID=9001"); g.fire("ZONE_CHANGED"); g.advance(2)
    assert visible_rows(g) == 2, "the plan stays inside the mine"
    panel = g.eval("QuestSharingPlannerPanel")
    texts = [panel.children[i].text for i in range(1, len(panel.children) + 1) if getattr(panel.children[i], "text", None)]
    g.run("MAP_ID=1429"); g.fire("ZONE_CHANGED"); g.advance(2)
    assert visible_rows(g) == 2 and g.eval("PLAN_SCANS") == 0, "back outside: same plan, no rebuild"


def test_the_game_hiding_the_interface_does_not_end_the_guide():
    g = planner_game()
    g.run("QuestSharingPlannerPanel:Hide(); QuestSharingPlannerPanel:Show()")   # Alt+Z or a cinematic
    assert g.eval("NS.questPlanner.active()"), "still running"
    g.run("QUESTS[#QUESTS+1]={id=8101,title='Green Quest',level=10,objectives={}}")
    g.fire("QUEST_ACCEPTED"); g.advance(5)
    assert visible_rows(g) >= 1
    g.eval("NS.questPlanner.command")("hide")
    assert not g.eval("NS.questPlanner.active()"), "the close command still ends it"


if __name__ == "__main__":
    tests = [value for name, value in globals().items() if name.startswith("test_")]
    failures = 0
    for test in tests:
        try:
            test()
            print("ok", test.__name__)
        except Exception as error:
            failures += 1
            print("FAIL", test.__name__, error)
    print(f"{len(tests) - failures}/{len(tests)} passed")
    raise SystemExit(bool(failures))
