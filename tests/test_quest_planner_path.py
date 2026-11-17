"""SPF's optional walk estimator and guidance adapter."""
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


def lua_callback(g, fn):
    return g.eval("function(cb) return function(...) return cb(...) end end")(fn)


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
    g.run("ShortestPathForever={API={version=2, minor=2, Navigate=function() return true end, EstimateWalks=function() end}}")
    assert path.available()
    costs, reason = path.estimateWalks(point(g, 0.1), g.lua.table_from([point(g, 0.2)]), lua_callback(g, lambda *_: None))
    assert costs is None and reason == "unavailable"


def test_estimate_rejects_mixed_maps_and_handles_zero_and_unreachable():
    g = game()
    install_spf(g)
    path = g.eval("NS.questPlannerPath")
    assert path.estimateWalks(point(g, 0.1), g.lua.table_from([point(g, 0.2, map_id=13)]), lua_callback(g, lambda *_: None))[1] == "invalid"
    received = []
    cancel = path.estimateWalks(point(g, 0.1), g.lua.table_from([point(g, 0.2), point(g, 0.3)]), lua_callback(g, lambda costs, why: received.append((costs, why))))
    assert callable(cancel)
    assert g.eval("#SPF_JOBS") == 1
    g.run("SPF_FINISH(1, {0, false})")
    assert received[0][0][1] == 0 and received[0][0][2] is False


def test_estimate_chunks_over_256_targets_and_combines_results():
    g = game()
    install_spf(g)
    path = g.eval("NS.questPlannerPath")
    targets = g.lua.table_from([point(g, i / 300) for i in range(257)])
    received = []
    path.estimateWalks(point(g, 0.1), targets, lua_callback(g, lambda costs, reason: received.append((costs, reason))))
    assert g.eval("#SPF_JOBS[1].targets") == 256
    g.run("SPF_FINISH(1, {})")
    assert g.eval("#SPF_JOBS[2].targets") == 1
    g.run("SPF_FINISH(2, {42})")
    assert received[0][0][1] is False
    assert received[0][0][257] == 42 and received[0][1] is None


def test_new_estimate_cancels_old_and_ignores_its_late_callback():
    g = game()
    install_spf(g)
    path = g.eval("NS.questPlannerPath")
    stale, fresh = [], []
    path.estimateWalks(point(g, 0.1), g.lua.table_from([point(g, 0.2)]), lua_callback(g, lambda costs, reason: stale.append(costs)))
    path.estimateWalks(point(g, 0.1), g.lua.table_from([point(g, 0.3)]), lua_callback(g, lambda costs, reason: fresh.append(costs)))
    assert g.eval("SPF_JOBS[1].cancelled")
    g.run("SPF_FINISH(1, {5})")
    g.run("SPF_FINISH(2, {9})")
    assert stale == [] and fresh[0][1] == 9


def test_estimate_errors_and_cancel_do_not_leave_stale_results():
    g = game()
    install_spf(g)
    path = g.eval("NS.questPlannerPath")
    received = []
    cancel = path.estimateWalks(point(g, 0.1), g.lua.table_from([point(g, 0.2)]), lua_callback(g, lambda costs, reason: received.append((costs, reason))))
    cancel()
    assert g.eval("SPF_JOBS[1].cancelled")
    g.run("SPF_FINISH(1, {5})")
    assert received == []
    path.estimateWalks(point(g, 0.1), g.lua.table_from([point(g, 0.2)]), lua_callback(g, lambda costs, reason: received.append((costs, reason))))
    g.run("SPF_FINISH(2, nil, 'nodata')")
    assert received[0] == (None, "nodata")


def test_walk_costs_promote_whole_reachable_outing_without_breaking_dependencies():
    g = game()
    install_spf(g)
    stops = [
        {"outingID": 1, "point": point(g, 0.8), "deps": {}, "name": "far pickup"},
        {"outingID": 1, "point": point(g, 0.85), "deps": {1: True}, "name": "far objective"},
        {"outingID": 2, "point": point(g, 0.2), "deps": {}, "name": "near pickup"},
        {"outingID": 2, "point": point(g, 0.25), "deps": {3: True}, "name": "near objective"},
    ]
    changed = []
    lua_stops = g.lua.table_from([g.lua.table_from({k: g.lua.table_from(v) if isinstance(v, dict) else v for k, v in row.items()}) for row in stops])
    g.eval("NS.questPlannerPath.prioritizeFirstOuting")(lua_stops, point(g, 0.1), lua_callback(g, lambda ok, *_: changed.append(ok)))
    g.run("SPF_FINISH(1, {80, 10})")
    assert changed == [True]
    assert [lua_stops[i]["name"] for i in range(1, 5)] == ["near pickup", "near objective", "far pickup", "far objective"]


def test_unreachable_outings_do_not_get_promoted():
    g = game()
    install_spf(g)
    stops = [
        {"outingID": 1, "point": point(g, 0.8), "deps": {}, "name": "first"},
        {"outingID": 2, "point": point(g, 0.2), "deps": {}, "name": "second"},
    ]
    results = []
    lua_stops = g.lua.table_from([g.lua.table_from({k: g.lua.table_from(v) if isinstance(v, dict) else v for k, v in row.items()}) for row in stops])
    g.eval("NS.questPlannerPath.prioritizeFirstOuting")(lua_stops, point(g, 0.1), lua_callback(g, lambda ok, reason: results.append((ok, reason))))
    g.run("SPF_FINISH(1, {false, false})")
    assert results == [(False, "unreachable")]
    assert lua_stops[1]["name"] == "first"


def test_promoted_outing_candidates_must_be_dependency_ready():
    g = game()
    install_spf(g)
    stops = [
        {"outingID": 1, "point": point(g, 0.8), "deps": {9: True}, "name": "blocked"},
        {"outingID": 2, "point": point(g, 0.3), "deps": {}, "name": "ready"},
    ]
    results = []
    lua_stops = g.lua.table_from([g.lua.table_from({k: g.lua.table_from(v) if isinstance(v, dict) else v for k, v in row.items()}) for row in stops])
    g.eval("NS.questPlannerPath.prioritizeFirstOuting")(lua_stops, point(g, 0.1), lua_callback(g, lambda ok, *_: results.append(ok)))
    assert g.eval("#SPF_JOBS[1].targets") == 1
    assert results == []
    g.run("SPF_FINISH(1, {12})")
    assert results == [True] and lua_stops[1]["name"] == "ready"


def test_planner_uses_spf_for_first_outing_and_follow_button_route():
    setup = QUEST_DATA + r'''
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
    g = Game("modern", setup, fresh=True)
    install_spf(g)
    g.start()
    g.eval("NS.setSetting")("questPlanner", True)
    g.advance(5)
    assert g.eval("#SPF_JOBS") == 1
    # Make the nearby giver outing win even if Quest Sharing's straight-line estimate chose the other one.
    g.run("local costs={}; for i,p in ipairs(SPF_JOBS[1].targets) do costs[i] = p.x > 0.5 and 10 or 900 end; SPF_FINISH(1, costs)")
    g.advance(3)  # Cost callbacks queue cooperative predictive search.
    g.eval("NS.questPlanner.pin")()
    waypoint = g.eval("WAYPOINT")
    assert waypoint["map"] == 1429
    assert abs(waypoint["x"] - 0.60) < 0.001
    assert abs(waypoint["y"] - 0.60) < 0.001
    g.eval("NS.questPlanner.follow")()
    call = g.eval("SPF_CALLS[1]")
    assert call[1] == "QuestSharing" and call[2] == 1429
    assert abs(call[3] - 0.60) < 0.001 and abs(call[4] - 0.60) < 0.001


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
