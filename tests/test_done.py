"""A quest I have finished is never shared, announced, listed or marked as something to do together.
Quest 101 (Report to Goldshire) is finished in these tests; 100 (Wolves Among Us) is in progress.
        python tests/test_done.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")


def plain(t):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def party(style, names=("Anna",), on_quest=None, auto=True):
    g = Game(style)
    g.start()
    if not auto:
        g.slash("auto off")
    for unit, ids in (on_quest or {}).items():
        g.run(f'ON_QUEST["{unit}"] = {{{", ".join("[%d] = true" % i for i in ids)}}}')
    g.join_party(list(names))
    return g


def entry(g, qid):
    return g.eval("NS.compat.findEntry")(qid)


def test_a_finished_quest_is_not_offered_when_a_party_forms_nor_by_hand(style):
    g = party(style)
    g.advance(40)
    assert g.pushed() == [100], "101 is finished: no popup for it"
    g.run("PRINTED = {}")
    g.slash("share")
    assert "sharing 1 quest(s)" in "\n".join(g.printed()), "the round itself leaves it out"
    g.advance(40)
    assert g.pushed() == [100, 100]
    g.run("PRINTED = {}")
    assert g.eval("NS.offerQuest")(entry(g, 101)) is False
    assert "you have finished" in "\n".join(g.printed()) and g.pushed() == [100, 100]


def test_a_quest_finished_during_a_round_is_not_offered_any_more(style):
    g = party(style, ("Anna",))
    g.run("local q = BYID(101); q.complete = false; q.objectives[1].finished = false")
    g.advance(5.3)
    assert g.pushed() == [100]
    g.run("local q = BYID(101); q.complete = true; q.objectives[1].finished = true")    # finished it meanwhile
    g.advance(30)
    assert g.pushed() == [100]


def test_a_finished_quest_is_never_in_the_in_common_message(style):
    g = party(style, ("Anna",), on_quest={"party1": [100, 101]})
    g.advance(40)
    said = [m for m, _ in g.sent()]
    assert said and all("Report to Goldshire" not in m for m in said), said
    assert any("Wolves Among Us" in m for m in said)


def test_a_quest_finished_the_moment_it_is_accepted_is_not_announced_either(style):
    """'Report to ...' quests are complete as soon as you take them. Accepted while a round runs, they join it."""
    g = party(style, ("Anna",), on_quest={"party1": [100, 300]})
    g.advance(5.3)                                           # the round is running
    g.run('QUESTS[#QUESTS + 1] = { id = 300, title = "Report to the Mayor", level = 2, complete = true, objectives = {} }')
    g.fire("QUEST_ACCEPTED", 300)
    g.advance(40)
    said = [m for m, _ in g.sent()]
    assert all("Report to the Mayor" not in m for m in said), said
    assert 300 not in g.pushed()


def test_when_only_finished_quests_are_shared_nothing_is_announced(style):
    g = party(style, ("Anna",), on_quest={"party1": [101]})
    g.advance(40)
    assert g.sent() == []


def test_the_ring_does_not_offer_a_finished_quest_to_do_together(style):
    g = party(style, ("Anna",), on_quest={"party1": [100, 101]}, auto=False)
    shared = g.eval("NS.quickResolve")("{shared}")
    common = g.eval("NS.quickResolve")("{common}")
    assert "Report to Goldshire" not in shared and "Report to Goldshire" not in common
    assert "Wolves Among Us" in common


def test_the_party_quests_window_leaves_it_out(style):
    g = party(style, ("Anna",), on_quest={"party1": [100, 101]}, auto=False)
    g.slash("panel on")
    g.advance(1)
    rows = g.eval("NS._panel()")[1]
    titles = [plain(rows[i].title.text) for i in range(1, 6) if rows[i].shown]
    assert "Report to Goldshire" not in titles and "Wolves Among Us" in titles
    data = g.eval("NS.panelData")()
    assert [data.quests[i].e.questID for i in range(1, len(data.quests) + 1)] == [100], "and from the count of quests in common"
    g.eval("NS.postAllProgress")()
    assert "Report to Goldshire" not in (g.eval("EDITBOX.text") or "")


def test_no_star_in_the_quest_log_for_it(style):
    g = party(style, ("Anna",), on_quest={"party1": [100, 101]}, auto=False)
    assert g.eval("NS.markerText")(entry(g, 101)) == ""
    assert g.eval("NS.markerText")(entry(g, 100)) != ""


def test_the_world_pin_does_not_prefer_it_as_a_quest_we_share(style):
    if style != "modern":
        return
    g = Game(style)
    g.start()
    g.slash("auto off")
    g.run('ON_QUEST["party1"] = {[101] = true}')
    g.set_dist(q100=400, q101=900, q102=2500, q200=10000)
    g.join_party(["Anna"])
    g.slash("near 2")
    g.slash("near on")
    g.advance(6)
    assert g.eval("SUPER") == 100, "Anna has 101, but I finished it: the nearest quest wins"


def test_clicking_it_in_the_games_tracker_still_tells_that_i_am_done(style):
    """Your own click is your choice: it posts that you are done, without any 'do it together'."""
    g = party(style, ("Anna",), on_quest={"party1": [101]}, auto=False)
    msg = g.eval("NS.statusMessage")(entry(g, 101), True)
    assert ("done" in msg.lower() or "finished" in msg.lower()) and "has it too" not in msg and "together" not in msg


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
