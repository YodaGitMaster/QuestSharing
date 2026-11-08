"""A party where several people run Quest Sharing: nobody gets the same popup twice, the party chat hears each thing once,
and your own chat stays quiet.        python tests/test_together.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game as _Game, OPEN_101  # noqa: E402


def Game(style="modern", pre="", **kw):
    """These tests are about how sharing works: two quests in progress (100 and 101)."""
    return _Game(style, OPEN_101 + pre, **kw)

STYLES = ("modern", "classic")


def party(style, names=("Anna",), on_quest=None, peers=()):
    """A party; `peers` also run Quest Sharing (their quest lists are known and lack my quests unless on_quest says so)."""
    g = Game(style)
    g.start()
    for unit, ids in (on_quest or {}).items():
        g.run(f'ON_QUEST["{unit}"] = {{{", ".join("[%d] = true" % i for i in ids)}}}')
    g.join_party(list(names))
    for p in peers:
        g.peer(p, "H|1")
        g.peer(p, "L|1|1|999:0:1/2")
    return g


def text(g):
    return "\n".join(g.printed())


def chat(g):
    return [m for m, _ in g.sent()]


# ---- quest popups: one offer per quest, whoever makes it ---------------------------------------------------------------
def test_a_quest_another_user_already_offered_is_not_offered_again(style):
    g = party(style, ("Anna", "Bob"), peers=("Anna",))
    g.peer("Anna", "O|100")                                  # Anna's addon offered 100 to the party a moment ago
    g.advance(40)
    assert g.pushed() == [101], "100 would pop up a second time on Bob"


def test_an_offer_that_arrives_during_my_round_still_counts(style):
    g = party(style, ("Bob",))
    g.advance(5.3)                                           # my round started: 100 is out, 101 is next
    assert g.pushed() == [100]
    g.peer("Bob", "H|1")
    g.peer("Bob", "L|1|1|999:0:1/2")
    g.peer("Bob", "O|101")                                   # meanwhile someone else's addon offered 101
    g.advance(30)
    assert g.pushed() == [100], "looked again right before offering it"


def test_my_offers_tell_the_other_addons(style):
    g = party(style, ("Anna",), peers=("Anna",))
    g.advance(40)
    sent = g.addon_sent()
    assert "O|100" in sent and "O|101" in sent


def test_the_first_in_line_shares_first_and_the_others_wait_their_turn(style):
    first = party(style, ("Zed",), peers=("Zed",))          # "me" comes before "zed": I am first
    first.advance(5.3)
    assert first.pushed() == [100]
    second = party(style, ("Anna",), peers=("Anna",))       # "anna" comes before "me": I wait my turn
    second.advance(5.3)
    assert second.pushed() == [], "waiting for Anna's addon to go first"
    second.advance(4)
    assert second.pushed() == [100]


def test_accepting_a_quest_someone_offered_does_not_offer_it_around_again(style):
    g = party(style, ("Anna", "Bob"), peers=("Bob",))
    g.advance(40)
    g.run("PUSHED = {}; SENT = {}")
    g.peer("Bob", "P|300:0:1/3")                             # Bob has the quest...
    g.peer("Bob", "O|300")                                   # ...and offered it to the party
    g.run('QUESTS[#QUESTS + 1] = { id = 300, title = "Bob\'s Quest", level = 5, objectives = { { text = "Thing: 0/3", finished = false, numFulfilled = 0, numRequired = 3 } } }')
    g.fire("QUEST_ACCEPTED", 300)                            # and I accepted it
    g.advance(30)
    assert g.pushed() == [], "Anna got Bob's popup already: no second one from me"
    assert chat(g) == [], "and no 'we have it in common' about a quest I just got from them"


# ---- party chat: each thing said once --------------------------------------------------------------------------------------
LINK100 = "|cffffff00|Hquest:100:3|h[Wolves Among Us]|h|r"


def test_quests_someone_just_named_are_not_announced_again(style):
    g = party(style, ("Anna", "Bob"), on_quest={"party1": [100, 101]})
    g.advance(4)
    g.fire("CHAT_MSG_PARTY", "Hey! Looks like we have these quests in common: " + LINK100, "Bob")   # Bob's addon said it
    g.advance(40)
    said = chat(g)
    assert len(said) == 1 and "Report to Goldshire" in said[0] and "Wolves Among Us" not in said[0], said


def test_when_everything_was_already_said_it_stays_quiet(style):
    g = party(style, ("Anna", "Bob"), on_quest={"party1": [100, 101]})
    g.advance(4)
    link101 = g.eval("LINK(BYID(101))")
    g.fire("CHAT_MSG_PARTY", "We have " + LINK100 + " and " + link101 + " in common", "Bob")
    g.advance(40)
    assert chat(g) == []


def test_my_own_messages_do_not_count_as_someone_else_saying_it(style):
    g = party(style, ("Anna",), on_quest={"party1": [100]})
    g.fire("CHAT_MSG_PARTY", "my progress: " + LINK100, "Me")
    g.advance(40)
    assert any("Wolves Among Us" in m for m in chat(g))


def test_finishing_together_is_said_once(style):
    g = party(style, ("Anna",), on_quest={"party1": [100]}, peers=("Anna",))
    g.run('NS.peers.anna.quests[100] = { objs = "3/8" }')
    g.advance(40)
    g.run("SENT = {}")
    g.peer("Anna", "C|100")                                  # Anna's last kill counted for her too: she says it
    g.run("""local q = BYID(100); q.complete = true
             for _, o in ipairs(q.objectives) do o.finished = true; o.numFulfilled = o.numRequired end""")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(5)
    assert not any("done with this one" in m or "ready to hand it in" in m for m in chat(g)), chat(g)


def test_finishing_alone_is_still_said(style):
    g = party(style, ("Anna",), on_quest={"party1": [100]})
    g.advance(40)
    g.run("SENT = {}")
    g.run("""local q = BYID(100); q.complete = true
             for _, o in ipairs(q.objectives) do o.finished = true; o.numFulfilled = o.numRequired end""")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(5)
    assert len(chat(g)) == 1 and "Wolves Among Us" in chat(g)[0]


# ---- your own chat window ---------------------------------------------------------------------------------------------------
def test_an_automatic_round_leaves_one_short_line(style):
    g = party(style, ("Anna", "Bob"))
    g.advance(5.3)
    g.reply("Anna has accepted your quest.")
    g.advance(4.1)
    g.reply("Bob has declined your quest.")
    g.advance(30)
    lines = g.printed()
    assert lines == ["|cff55ccffQuest Sharing:|r shared 2 quests with the party: Anna took 1, 1 declined"], lines


def test_a_round_that_shared_nothing_says_nothing(style):
    g = party(style, ("Anna",), on_quest={"party1": [100, 101]})
    g.advance(40)
    assert g.printed() == []


def test_sharing_by_hand_still_says_what_it_does(style):
    g = party(style, ("Anna",))
    g.advance(40)
    g.run("PRINTED = {}")
    g.slash("share")
    assert "sharing 2 quest(s) with 1 player(s)" in text(g)
    g.advance(40)
    assert "shared 2 quests with the party" in text(g)


def test_the_tracker_pause_is_explained_once_per_session(style):
    g = Game("classic")
    g.start()
    g.slash("near on")
    g.advance(10)
    for _ in range(3):
        g.run("WATCHED[200] = true")
        g.advance(4)
        g.advance(12)
    assert int(g.eval("NS.pauseCounts.tracker")) >= 2, "it paused every time"
    assert text(g).count("paused for 10 seconds") == 1, "but said so once"


def test_the_verbose_setting_is_gone(style):
    g = party(style)
    keys = [g.eval(f"NS.settingRows[{i}].key") for i in range(1, int(g.eval("#NS.settingRows")) + 1)]
    assert "verbose" not in keys and g.eval("NS.defaults.verbose") is None


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
