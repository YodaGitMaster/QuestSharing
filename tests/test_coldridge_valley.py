"""Golden use case: a level-1 gnome mage in Coldridge Valley (Dun Morogh), on the real Classic QuestieDB rows.

The data in tests/data/coldridge_valley.lua comes from tools/build_coldridge_fixture.py. The rules here are how the
Quest guide should behave in every zone (context/decisions.md, "Optimizer reference case"):
  python tests/test_coldridge_valley.py
"""
import math
import pathlib
import random
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

FIX = (pathlib.Path(__file__).resolve().parent / "data" / "coldridge_valley.lua").read_text()
SETUP = FIX + r'''
COMPLETED = COMPLETED or {}
local function getter(t) return function(id, key) local r=t[id]; return r and r[key] end end
QuestDB = { Get=getter(QUESTIE_QUESTS), GetAllIds=function() local ids={} for id in pairs(QUESTIE_QUESTS) do ids[#ids+1]=id end table.sort(ids) return ids end }
NpcDB, ItemDB, ObjectDB = {Get=getter(QUESTIE_NPCS)}, {Get=getter(QUESTIE_ITEMS)}, {Get=getter(QUESTIE_OBJECTS)}
LibQuestieDB = { Support={ Get=function(name)
    if name == "ZoneDB" then return { private={ areaIdToUiMapId="return { [1]=1426, [132]=1426 }", areaIdToUiMapIdOverride="return {}" } } end
    if name == "QuestXP" then return { db=QUESTIE_XP } end
end }, Enum={ classKeys={MAGE=128}, raceMaskById={[7]=64} } }
local function doable(id)
  if COMPLETED[id] then return false end
  local q = QUESTIE_QUESTS[id]; if not q then return false end
  if q.requiredClasses and q.requiredClasses ~= 128 then return false end
  if q.requiredRaces and bit and bit.band and (q.requiredRaces % 128) < 64 then return false end
  local pre = q.preQuestSingle
  if pre then local ok=false for _,p in ipairs(pre) do if COMPLETED[p] then ok=true end end if not ok then return false end end
  return true
end
STATES = { AVAILABLE=1, NO_PREQUESTSINGLE=2, NO_PREQUESTGROUP=3, LEVEL_TOO_LOW=4, WRONG_CLASS=5, WRONG_RACE=6 }
local function verbose(id)
  local q = QUESTIE_QUESTS[id]
  if q.requiredClasses and q.requiredClasses ~= 128 then return "class", true, STATES.WRONG_CLASS end
  if q.requiredRaces and (q.requiredRaces % 128) < 64 then return "race", true, STATES.WRONG_RACE end
  local pre = q.preQuestSingle
  if pre then local ok=false for _,p in ipairs(pre) do if COMPLETED[p] then ok=true end end
    if not ok then return "pre", true, STATES.NO_PREQUESTSINGLE end end
  if (q.requiredLevel or 1) > (PLAYER_LEVEL or 1) then return "level", true, STATES.LEVEL_TOO_LOW end
  return nil, false, STATES.AVAILABLE
end
QuestieLoader = { ImportModule=function(_, name)
    if name == "QuestieDB" then return { IsDoable=function(id) return select(2, verbose(id)) == false and not COMPLETED[id] end,
      IsDoableVerbose=verbose, DoableStates=STATES } end
end }
C_QuestLog = C_QuestLog or {}
C_QuestLog.IsQuestFlaggedCompleted = function(id) return COMPLETED[id] == true end
Enum = Enum or {}; Enum.UIMapType = { Zone=3 }
UnitClass = function() return "Mage", "MAGE", 8 end
UnitRace = function() return "Gnome", "Gnome", 7 end
UnitFactionGroup = function() return "Alliance" end
UnitLevel = function() return PLAYER_LEVEL or 1 end
UnitXP = function() return PLAYER_XP or 0 end
UnitXPMax = function() return PLAYER_XPMAX or 400 end
MAP_ID, ZONE, POS = 1426, "Dun Morogh", {x=0.2993, y=0.712}
C_Map.GetMapInfo=function(map) if map == 1426 then return {name="Dun Morogh", mapType=3, parentMapID=1415} end
  if map == 1415 then return {name="Eastern Kingdoms", mapType=2, parentMapID=947} end end
C_Map.GetMapWorldSize=function(map) if map == 1426 then return 4924.66, 3283.33 end end
C_Map.IsCityMap=function() return false end
QuestDifficultyColors = { trivial={r=0.5,g=0.5,b=0.5}, standard={r=0.1,g=0.8,b=0.1}, difficult={r=1,g=1,b=0}, verydifficult={r=1,g=0.5,b=0.1}, impossible={r=1,g=0.1,b=0.1} }
GetQuestDifficultyColor=function(level) return QuestDifficultyColors.standard end
QUESTS = {}
'''
CAPTURE = r'''
local O = NS.questOptimizer
local real = O.optimize
O.optimize = function(catalog, stops, opts)
  local ordered, report = real(catalog, stops, opts)
  LAST = { catalog = catalog, stops = stops, opts = opts, ordered = ordered, report = report }
  return ordered, report
end
'''
VALLEY = 14          # every quest a gnome mage can start in Coldridge Valley
WORLD = (4924.66, 3283.33)  # Dun Morogh in yards
NPC = {"Sten Stoutarm": (0.2993, 0.7120), "Balir Frosthammer": (0.2971, 0.7125), "Talin Keeneye": (0.2260, 0.7143),
       "Grelin Whitebeard": (0.2508, 0.7571), "Mountaineer Thalos": (0.3348, 0.7184), "Felix Whindlebolt": (0.2855, 0.6764),
       "Nori Pridedrift": (0.2498, 0.7596), "Durnan Furcutter": (0.2877, 0.6637), "Marryk Nurribit": (0.2871, 0.6637),
       "Hands Springsprocket": (0.3385, 0.7224)}


def plain(t):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def yards(a, b):
    return math.hypot((a[0] - b[0]) * WORLD[0], (a[1] - b[1]) * WORLD[1])


_cached = {}


def planned():
    """The refined route (after the guide's background polish), as (kind, quest name, task, (x, y)) per action."""
    if "g" not in _cached:
        g = Game("modern", SETUP, fresh=True)
        g.start()
        g.run(CAPTURE)
        g.run("NS.db.questPlannerScope = 'all'")
        g.eval("NS.setSetting")("questPlanner", True)
        g.advance(10)
        _cached["g"] = g
    g = _cached["g"]
    names = g.eval("LAST.catalog")
    out = []
    for stop in g.eval("LAST.ordered").values():
        qid = next(iter(stop.quests.keys())) if stop.quests else stop.questID
        tasks = list(stop.tasks.values()) if stop.tasks else []
        out.append((stop.kind, names[qid].name, plain(tasks[0]) if tasks else "", (stop.point.x, stop.point.y)))
    return g, out


def test_every_valley_quest_is_planned_including_level_ahead_and_class_quests():
    g, route = planned()
    report = g.eval("LAST.report")
    assert len(list(report.completedIDs.keys())) == VALLEY, "all 14 quests are handed in"
    names = {name for _, name, _, _ in route}
    # Level 3 and 4 quests join because quest and kill XP reach those levels on the way.
    assert {"A Refugee's Quandary", "Scalding Mornbrew Delivery", "Bring Back the Mug"} <= names
    # A class quest you can take, given and handed in here, belongs to this zone.
    assert "Glyphic Memorandum" in names


def test_every_pickup_and_hand_in_is_where_its_npc_stands():
    _, route = planned()
    for kind, name, task, point in route:
        if kind in ("pickup", "turnin"):
            npc = next((n for n in NPC if task.endswith(" " + n)), None)
            if npc:
                assert yards(point, NPC[npc]) < 5, (task, point)


def test_visible_steps_never_merge_npcs_a_player_sees_as_two_stops():
    g, _ = planned()
    text = plain(g.eval("NS.questPlanner.debugText")())
    steps = re.findall(r"Step \d+[^:]*: (\w+) at map 1426 \(([\d.]+), ([\d.]+)\)\n((?:  action[^\n]*\n)+)", text)
    assert steps
    for kind, x, y, actions in steps:
        if kind == "objective":
            continue
        for npc, spot in NPC.items():
            if npc in actions:
                assert yards((float(x), float(y)), spot) <= 45, (npc, x, y)   # Thalos was merged into Balir's stop



def test_two_hand_ins_185_yards_apart_stay_two_steps():
    """Balir and Thalos stand 185 yd apart. In map fractions (0.045 of Dun Morogh = ~220 yd) they became one step at
    Balir's spot; in yards they are two."""
    g = Game("modern", SETUP + '''
COMPLETED = {[179]=true,[182]=true,[218]=true,[183]=true,[233]=true,[234]=true,[3361]=true,[3364]=true,[3365]=true,
  [3114]=true,[2160]=true}
QUESTS = {{id=170,title="A New Threat",level=2,complete=true,objectives={}},
  {id=282,title="Senir's Observations",level=5,complete=true,objectives={}}}
''', fresh=True)
    g.start()
    g.run("NS.db.questPlannerScope = 'all'")
    g.eval("NS.setSetting")("questPlanner", True)
    g.advance(10)
    text = plain(g.eval("NS.questPlanner.debugText")())
    first = text.split("Step 2")[0]
    assert "Balir Frosthammer" in first and "Mountaineer Thalos" not in first, first[-400:]
    assert "Step 2: turnin at map 1426 (0.3348, 0.7184)" in text

def test_the_valley_is_finished_before_the_route_leaves_for_kharanos():
    _, route = planned()
    left = [i for i, (_, _, _, p) in enumerate(route) if p[1] < 0.6]    # Kharanos is north, y ~ 0.53
    assert left, "the two Kharanos hand-ins end the route"
    assert min(left) > max(i for i, (_, _, _, p) in enumerate(route) if p[1] >= 0.6), "no walk back into the valley"


def test_a_follow_up_at_the_same_npc_is_taken_in_the_same_visit():
    _, route = planned()
    for i, (kind, name, task, point) in enumerate(route):
        if kind == "turnin" and name in ("Dwarven Outfitters", "The Troll Cave", "The Stolen Journal"):
            nxt = route[i + 1]
            assert nxt[0] == "pickup" and yards(nxt[3], point) < 45, (name, nxt)


def test_route_time_is_close_to_an_independent_search():
    """Random or-opt / 2-opt / swap moves over the whole route, scored by the same cost model, find nothing more
    than 2 % faster. (A 4 x 300,000-move annealing run found 1201.9 s against the guide's 1211.1 s, 2026-11-19.)"""
    g, _ = planned()
    g.run('''
    OPTS = {}
    for k, v in pairs(LAST.opts) do OPTS[k] = v end
    OPTS.preferredSites = nil
    BEST = {}
    for i, s in ipairs(LAST.ordered) do BEST[i] = s.id end
    function EVAL(ids) return NS.questOptimizer._evaluate(LAST.catalog, LAST.stops, OPTS, ids) end
    ''')
    best = list(g.eval("BEST").values())
    base = g.eval("EVAL(BEST)")
    assert base and abs(base - g.eval("LAST.report.expectedSeconds")) < 0.01
    ev, table = g.eval("EVAL"), g.lua.table_from
    rng = random.Random(7)
    found = base
    for _ in range(4000):
        q, n, r = best[:], len(best), rng.random()
        if r < 0.5:
            k = rng.randint(1, 4); i = rng.randrange(0, n - k + 1); seg = q[i:i + k]; del q[i:i + k]
            j = rng.randrange(0, len(q) + 1); q[j:j] = seg
        elif r < 0.8:
            i, j = sorted(rng.sample(range(n), 2)); q[i:j + 1] = q[i:j + 1][::-1]
        else:
            i, j = rng.sample(range(n), 2); q[i], q[j] = q[j], q[i]
        t = ev(table(q))
        if t is not None and t < found:
            found = t
    assert found > base * 0.98, (base, found)
    assert 1100 < base < 1300, base   # about 20 minutes of simulated play for the whole valley


def test_quest_xp_alone_would_strand_mornbrew_after_kharanos():
    """Kill XP is part of the level forecast: without it the level-4 Mornbrew pair only unlocks after Kharanos."""
    _, route = planned()
    order = [name for _, name, _, _ in route]
    kharanos = min(i for i, (_, _, _, p) in enumerate(route) if p[1] < 0.6)
    assert max(i for i, n in enumerate(order) if n in ("Scalding Mornbrew Delivery", "Bring Back the Mug")) < kharanos


if __name__ == "__main__":
    failed = total = 0
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            total += 1
            try:
                fn()
                print("ok", name)
            except Exception as exc:  # noqa: BLE001
                failed += 1
                print("FAIL", name, type(exc).__name__, str(exc)[:200])
    print(f"{total - failed}/{total} passed")
    raise SystemExit(bool(failed))
