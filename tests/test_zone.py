"""Only the quests of where you are: standing in Teldrassil, quests from Stormwind are never in the Party quests window,
the tracker or the map pin - even on a client that does not tell which continent a quest is on.
        python tests/test_zone.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")
TELDRASSIL = """
ZONE = "Teldrassil"
QUESTS = {
    { header = "Teldrassil" },
    { id = 500, title = "The Balance of Nature", level = 3, objectives = {
        { text = "Nightsaber slain: 2/7", finished = false, numFulfilled = 2, numRequired = 7, type = "monster" } } },
    { id = 501, title = "Seek Redemption!", level = 4, objectives = {
        { text = "Fel Cone: 1/3", finished = false, numFulfilled = 1, numRequired = 3, type = "item" } } },
    { header = "Stormwind City" },
    { id = 600, title = "The Stockade Riots", level = 29, objectives = {
        { text = "Targorr slain: 0/1", finished = false, numFulfilled = 0, numRequired = 1, type = "monster" } } },
    { id = 601, title = "Rest and Relaxation", level = 10, objectives = {
        { text = "Speak with the innkeeper", finished = false } } },
}
"""
# a client that gives a distance but does not say whether the quest is on your continent
NO_CONTINENT = """
if C_QuestLog then
    C_QuestLog.GetDistanceSqToQuest = function(id) local d = DIST[id]; return d end
end
"""


def plain(t):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def teldrassil(style, extra=""):
    g = Game(style, TELDRASSIL + extra)
    g.start()
    g.slash("auto off")
    return g


def window_titles(g):
    g.join_party(["Anna"])
    g.slash("panel on")
    g.advance(1)
    rows = g.eval("NS._panel()")[1]
    return [plain(rows[i].title.text) for i in range(1, 13) if rows[i] is not None and rows[i].shown]


def test_the_party_quests_window_shows_only_this_zones_quests(style):
    g = teldrassil(style, NO_CONTINENT)
    if style == "modern":
        g.set_dist(q500=900, q501=400, q600=100, q601=50)          # nonsense: Stormwind quests look nearer
    titles = window_titles(g)
    assert titles == ["Seek Redemption!", "The Balance of Nature"] or sorted(titles) == ["Seek Redemption!", "The Balance of Nature"], titles
    assert "The Stockade Riots" not in titles and "Rest and Relaxation" not in titles, "never filled up with far quests"


def test_the_tracker_never_picks_quests_from_another_zone_it_cannot_place(style):
    g = teldrassil(style, NO_CONTINENT)
    if style == "modern":
        g.set_dist(q500=900, q501=400, q600=100, q601=50)
    g.slash("near 4")
    g.slash("near on")
    g.advance(10)
    assert set(g.watched()) <= {500, 501} and {500, 501} <= set(g.watched()), g.watched()
    g.slash("near mode zone")
    g.advance(10)
    assert set(g.watched()) == {500, 501}


def test_the_tracker_takes_a_quest_just_across_the_border_when_the_game_says_it_is_near(style):
    if style != "modern":
        return
    g = teldrassil(style)                                            # this client says "on your continent"
    g.set_dist(q500=900, q501=400, q600=90000, q601=250000000)     # 600: 300 yards away; 601: far away
    g.slash("near 4")
    g.slash("near on")
    g.advance(10)
    assert 600 in g.watched() and 601 not in g.watched(), g.watched()


def test_the_map_pin_never_points_to_the_other_side_of_the_world(style):
    if style != "modern":
        return
    g = teldrassil(style, NO_CONTINENT)
    g.set_dist(q500=900, q501=400, q600=100, q601=50)
    g.slash("near 2")
    g.slash("near on")
    g.advance(10)
    assert g.eval("SUPER") in (500, 501), g.eval("SUPER")


def test_sharing_also_stays_in_the_zone(style):
    g = teldrassil(style)
    g.slash("auto on")
    g.join_party(["Anna"])
    g.advance(40)
    assert set(g.pushed()) == {500, 501}


if __name__ == "__main__":
    import inspect
    failed = total = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        styles = STYLES if inspect.signature(fn).parameters else (None,)
        for style in styles:
            total += 1
            label = f"{name}[{style}]" if style else name
            try:
                fn(style) if style else fn()
                print("ok  ", label)
            except Exception as e:                       # noqa: BLE001
                failed += 1
                print("FAIL", label, type(e).__name__, str(e)[:400])
    print(f"\n{total - failed}/{total} passed")
    raise SystemExit(1 if failed else 0)
