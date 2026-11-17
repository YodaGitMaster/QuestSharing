"""Reference-led compact guide controls, current step and mini mode."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from test_quest_planner_zone_steps import game, rows


def button(g, label):
    panel = g.eval("QuestSharingPlannerPanel")
    return next(c for c in panel.children.values() if c.text == label and c.scripts.OnClick)


def test_only_one_step_is_emphasized_and_upcoming_steps_are_muted(style):
    g = game(style)
    visible = rows(g)
    assert [r.current for r in visible] == [True, False, False]
    assert visible[0].title.text.startswith("|cffffd100")
    assert visible[0].detail.text.startswith("|cffffffff")
    assert visible[1].detail.text.startswith("|cffa9a69f")


def test_arrows_change_current_step_and_waypoint_without_completing_quests(style):
    g = game(style)
    next_button = button(g, ">")
    previous = button(g, "<")
    assert not previous.enabled and next_button.enabled
    next_button.scripts.OnClick(next_button)
    assert rows(g)[0].stepIndex == 2 and rows(g)[0].current
    assert g.eval("WAYPOINT.map") == 1436
    assert abs(g.eval("WAYPOINT.x") - 0.44) < 0.001
    previous.scripts.OnClick(previous)
    assert rows(g)[0].stepIndex == 1
    assert g.eval("QUESTS[1].complete") is None


def test_mini_mode_shows_current_step_and_expansion_restores_upcoming(style):
    g = game(style)
    panel = g.eval("QuestSharingPlannerPanel")
    expanded_height = panel.height
    toggle = button(g, "-")
    toggle.scripts.OnClick(toggle)
    assert len(rows(g)) == 1 and toggle.text == "+"
    assert panel.height < expanded_height
    toggle.scripts.OnClick(toggle)
    assert len(rows(g)) == 3 and toggle.text == "-"


def test_lock_keeps_position_and_unlock_restores_dragging(style):
    g = game(style)
    panel = g.eval("QuestSharingPlannerPanel")
    toggle = button(g, "Lock")
    toggle.scripts.OnClick(toggle)
    assert panel.movable is False and toggle.text == "Unlock"
    g.run('''QuestSharingPlannerPanel.StartMoving=function(self) self.dragCalls=(self.dragCalls or 0)+1 end
QuestSharingPlannerPanel.StopMovingOrSizing=function(self) self.stopCalls=(self.stopCalls or 0)+1 end''')
    panel.scripts.OnDragStart(panel)
    panel.scripts.OnDragStop(panel)
    assert panel.dragCalls is None and panel.stopCalls is None
    toggle.scripts.OnClick(toggle)
    assert panel.movable is True and toggle.text == "Lock"
    panel.scripts.OnDragStart(panel)
    panel.scripts.OnDragStop(panel)
    assert panel.dragCalls == 1 and panel.stopCalls == 1


def test_guide_navigation_stops_at_boundaries(style):
    g = game(style)
    assert g.eval("NS.questPlanner.navigate")(-1) is False
    assert g.eval("WAYPOINT") is None
    g.eval("NS.questPlanner.navigate")(1)
    g.eval("NS.questPlanner.navigate")(1)
    assert not button(g, ">").enabled
    assert g.eval("NS.questPlanner.navigate")(1) is False
    assert rows(g)[0].stepIndex == 3


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
