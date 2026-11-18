"""SPF's optional Follow adapter. The quest guide never asks SPF for walking estimates to plan."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402
from test_questmap import DATA as QUEST_DATA  # noqa: E402


def game(pre=""):
    return Game("modern", pre, fresh=True)


def install_spf(g, extra=""):
    g.run(r'''
SPF_CALLS, SPF_JOBS = {}, {}
ShortestPathForever = { API = {
    version = 2, minor = 3,
    Navigate = function(...) SPF_CALLS[#SPF_CALLS + 1] = {...}; return true end,
    EstimateWalks = function(owner, from, targets, callback)
        local job = { owner=owner, from=from, targets=targets, callback=callback, cancelled=false }
        SPF_JOBS[#SPF_JOBS + 1] = job
        return function() job.cancelled=true end
    end,
}}
function SPF_FINISH(index, costs, reason) SPF_JOBS[index].callback(costs, reason) end
''' + extra)


def point(g, x, y=0.2, map_id=12):
    return g.lua.table_from({"map": map_id, "x": x, "y": y})


def test_follow_uses_spf_api_and_validates_coordinates():
    g = game()
    path = g.eval("NS.questPlannerPath")
    assert not path.available()
    install_spf(g)
    assert path.available()
    assert path.follow(point(g, 0.4), "Kill wolves", "objective") is True
    call = g.eval("SPF_CALLS[1]")
    assert call[1] == "QuestSharing" and call[2] == 12
    assert call[3] == 0.4 and call[4] == 0.2
    assert call[5] == "Kill wolves" and call[6] == "objective"
    assert path.follow(point(g, 1.2), "bad", "objective")[0] is False


def test_unknown_api_version_and_old_minor_fall_back_cleanly():
    g = game()
    path = g.eval("NS.questPlannerPath")
    g.run("ShortestPathForever={API={version=3, Navigate=function() return true end}}")
    assert not path.available()
    assert path.follow(point(g, 0.4), "stop", "objective")[0] is False
    # Any build that can navigate can follow, with or without walking estimates.
    g.run("ShortestPathForever={API={version=2, minor=2, Navigate=function() return true end, EstimateWalks=function() end}}")
    assert path.available()
    g.run("ShortestPathForever={API={version=1, Navigate=function() return true end}}")
    assert path.available()
    assert path.follow(point(g, 0.4), "stop", "objective") is True


def test_bridge_offers_only_follow_and_no_walking_estimates():
    g = game()
    install_spf(g)
    path = g.eval("NS.questPlannerPath")
    # Planning uses straight-line travel only; the bridge has no estimator or outing reordering left.
    assert path.estimateWalks is None
    assert path.cancelWalkEstimates is None
    assert path.prioritizeFirstOuting is None
    assert callable(path.available) and callable(path.follow)


FOLLOW_SETUP = QUEST_DATA + r'''
QUESTIE_QUESTS[100].startedBy = { {197} }
QUESTIE_QUESTS[102] = { name="Near Giver Quest", questLevel=2, requiredLevel=1,
    startedBy={ {400} }, finishedBy={ {400} }, objectives={ { {400} } } }
QuestDB.GetAllIds = function() return {100, 102} end
QuestieLoader = { ImportModule = function(_, name)
    if name == "QuestieDB" then return { IsDoable = function() return true end } end
end }
Enum = { UIMapType = { Zone = 3 } }
C_Map.GetMapInfo = function(map) if map == 1429 then return {name="Elwynn Forest", mapType=3} end end
C_Map.IsCityMap = function() return false end
QuestDifficultyColors = { standard={r=0.1,g=0.8,b=0.1}, difficult={r=1,g=1,b=0} }
GetQuestDifficultyColor = function() return QuestDifficultyColors.standard end
'''


def test_planner_never_asks_spf_for_walks_and_follow_button_routes_the_selected_step():
    waypoints = []
    for spf in (False, True):
        g = Game("modern", FOLLOW_SETUP, fresh=True)
        if spf:
            install_spf(g)
        g.start()
        g.eval("NS.setSetting")("questPlanner", True)
        g.advance(8)
        g.eval("NS.questPlanner.pin")()
        waypoints.append((g.eval("WAYPOINT.map"), round(g.eval("WAYPOINT.x"), 4), round(g.eval("WAYPOINT.y"), 4)))
    # SPF is never asked for walking estimates, and the first step is the one planned without SPF.
    assert g.eval("#SPF_JOBS") == 0
    assert waypoints[1] == waypoints[0], waypoints
    assert waypoints[1][0] == 1429
    # The Follow button is shown with SPF installed and hands that selected step to SPF.
    panel = g.eval("QuestSharingPlannerPanel")
    follow = next(c for c in panel.children.values() if c.text == "Follow with SPF" and c.scripts.OnClick)
    assert follow.shown
    follow.scripts.OnClick(follow)
    call = g.eval("SPF_CALLS[1]")
    assert call[1] == "QuestSharing" and call[2] == 1429
    assert abs(call[3] - waypoints[1][1]) < 0.001 and abs(call[4] - waypoints[1][2]) < 0.001


if __name__ == "__main__":
    tests = [value for name, value in globals().items() if name.startswith("test_")]
    failures = 0
    for test in tests:
        try:
            test()
            print("ok", test.__name__)
        except Exception as error:  # keep the suite style used by this repository
            failures += 1
            print("FAIL", test.__name__, error)
    print(f"{len(tests) - failures}/{len(tests)} passed")
    raise SystemExit(bool(failures))
