"""Learned pace of the quest guide and the saved guide settings.     python tests/test_planner_calibration.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402
from test_quest_planner_zone_steps import WESTFALL, game  # noqa: E402

STYLES = ("modern", "classic")
LOG = r'''
QUESTS={{id=9000,title="Local Harvest",level=8,objectives={{text="Harvest Watcher slain: 0/40",type="monster",have=0,need=40}}}}
function KILL(n)
 local o=QUESTS[1].objectives[1]; o.have=o.have+(n or 1); o.text="Harvest Watcher slain: "..o.have.."/40"
 NS.fire = nil
end
'''


def pace(g):
    return g.eval("NS.questCalibration.get")()


def near(a, b):
    return abs(a - b) < 0.01


def kills(g, gaps):
    """Look at the quest log, kill once, then once more after each gap (seconds)."""
    g.fire("QUEST_LOG_UPDATE")
    g.run("KILL(1)"); g.fire("QUEST_LOG_UPDATE")
    for gap in gaps:
        g.advance(gap); g.run("KILL(1)"); g.fire("QUEST_LOG_UPDATE")


def test_defaults_until_five_samples_then_the_median_of_the_players_own_kills(style):
    g = game(style, LOG)
    assert pace(g).killSeconds == 10 and not pace(g).killCalibrated
    kills(g, [7, 7, 7, 7])          # 4 samples
    assert pace(g).killSamples == 4 and pace(g).killSeconds == 10 and not pace(g).killCalibrated
    kills(g, [7])
    assert pace(g).killSamples == 5 and near(pace(g).killSeconds, 7) and pace(g).killCalibrated
    assert "7 s per kill, from 5 kills" in g.eval("NS.questCalibration.describe")()


def test_outliers_are_ignored_and_a_double_kill_counts_as_two_samples(style):
    g = game(style, LOG)
    kills(g, [7, 120, 0.5, 8])      # 120 s and 0.5 s are not kills in a row
    assert pace(g).killSamples == 2
    g.advance(10); g.run("KILL(2)"); g.fire("QUEST_LOG_UPDATE")
    assert pace(g).killSamples == 4, "two kills in 10 s: two samples of 5 s"


def test_pace_is_clamped(style):
    g = game(style, LOG)
    kills(g, [1.5] * 6)
    assert pace(g).killSeconds == 4
    g.run("NS.questCalibration.reset()")
    kills(g, [60] * 6)
    assert pace(g).killSeconds == 40


def test_quest_giver_time_runs_from_the_window_opening_to_accept_or_turn_in(style):
    g = game(style, LOG)
    for _ in range(5):
        g.fire("QUEST_DETAIL"); g.advance(6); g.fire("QUEST_ACCEPTED", 1, 9000)
    assert pace(g).interactionSamples == 5 and near(pace(g).interactionSeconds, 6) and pace(g).interactionCalibrated
    g.fire("QUEST_COMPLETE"); g.advance(90); g.fire("QUEST_TURNED_IN", 9000)
    assert pace(g).interactionSamples == 5, "a visit that took 90 s is not a quest giver time"


def test_reset_and_reload_keep_the_right_state(style):
    g = game(style, LOG)
    kills(g, [7] * 6)
    saved = g.eval("NS.db.plannerCalibration.kill[1]")
    assert near(saved, 7), "the samples live in the saved settings"
    g.eval("NS.questCalibration.reset")()
    assert pace(g).killSamples == 0 and pace(g).killSeconds == 10


def test_nothing_is_recorded_while_the_guide_is_closed(style):
    g = game(style, LOG)
    g.slash("plan hide")
    kills(g, [7] * 6)
    assert pace(g).killSamples == 0


def test_the_route_uses_the_learned_times(style):
    g = game(style, LOG)
    before = g.eval("NS.questPlanner.report")().expectedSeconds
    kills(g, [30] * 6)              # a slow player: 30 s per kill
    g.eval("NS.questPlanner.applySettings")()
    g.advance(8)
    after = g.eval("NS.questPlanner.report")().expectedSeconds
    assert after > before, (before, after)


# ---- the saved guide settings -------------------------------------------------------------------------------
def test_a_saved_goal_is_read_and_replans_at_once(style):
    g = game(style)
    assert g.eval("NS.questPlanner.report")().mode == "all"
    g.eval("NS.setSetting")("questPlannerGoal", "xp"); g.advance(5)
    assert g.eval("NS.questPlanner.report")().mode == "xp"
    g.eval("NS.setSetting")("questPlannerGoal", "budget"); g.eval("NS.setSetting")("questPlannerBudget", 20); g.advance(5)
    assert g.eval("NS.questPlanner.report")().mode == "budget"
    g.eval("NS.setSetting")("questPlannerGoal", "selected"); g.eval("NS.setSetting")("questPlannerSelected", "9000, abc"); g.advance(5)
    assert g.eval("NS.questPlanner.report")().mode == "selected"
    g.eval("NS.setSetting")("questPlannerScope", "green-yellow")
    assert g.eval("NS.questPlanner.levelScope") == "green-yellow"


def test_chosen_quests_goal_without_ids_keeps_the_previous_goal(style):
    g = game(style)
    g.eval("NS.setSetting")("questPlannerGoal", "selected"); g.advance(5)
    assert g.eval("NS.questPlanner.report")().mode == "all"


def test_goal_commands_are_saved_like_the_settings(style):
    g = game(style)
    g.slash("plan xp"); g.advance(5)
    assert g.eval("NS.db.questPlannerGoal") == "xp"
    g.slash("plan budget 45"); g.advance(5)
    assert (g.eval("NS.db.questPlannerGoal"), g.eval("NS.db.questPlannerBudget")) == ("budget", 45)
    g.slash("plan range")
    assert g.eval("NS.db.questPlannerScope") == "green-yellow"
    g.slash("plan unrestricted")
    assert g.eval("NS.db.questPlannerScope") == "all"


def test_a_saved_goal_is_used_when_the_guide_opens_after_a_reload(style):
    g = Game(style, WESTFALL + "\nNS_PRESET=1", fresh=True)
    g.start()
    g.run('NS.db.questPlannerGoal = "xp"')
    g.eval("NS.setSetting")("questPlanner", True); g.advance(5)
    assert g.eval("NS.questPlanner.report")().mode == "xp"


def test_show_report_opens_the_report_window(style):
    g = game(style)
    g.eval("NS.questPlanner.showReport")()
    assert g.eval("QuestSharingReport.shown")


if __name__ == "__main__":
    failed = total = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        for style in STYLES:
            total += 1
            try:
                fn(style); print("ok", name, style)
            except Exception as exc:
                failed += 1; print("FAIL", name, style, type(exc).__name__, str(exc)[:500])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
