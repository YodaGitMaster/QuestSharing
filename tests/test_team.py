"""Playing together without spam: "picked up a quest Anna has", where the quest items were, and the budget of automatic
messages.        python tests/test_team.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")
NEW = '''QUESTS[#QUESTS + 1] = { id = %d, title = "%s", level = 5, objectives = {
    { text = "Boar Tusk: 0/5", finished = false, numFulfilled = 0, numRequired = 5, type = "item" } } }'''


def party(style, names=("Anna",), on_quest=None):
    g = Game(style)
    g.start()
    g.slash("auto off")                                   # no quest popups in these tests: only the messages
    for unit, ids in (on_quest or {}).items():
        g.run(f'ON_QUEST["{unit}"] = {{{", ".join("[%d] = true" % i for i in ids)}}}')
    g.join_party(list(names))
    g.advance(40)
    g.run("SENT = {}; PRINTED = {}")
    return g


def pick_up(g, qid, title="Boar Tusks"):
    g.run(NEW % (qid, title))
    g.fire("QUEST_ACCEPTED", qid)


def chat(g):
    return [m for m, _ in g.sent()]


# ---- "picked up a quest someone has" --------------------------------------------------------------------------------------
def test_picking_up_a_quest_a_party_member_has_invites_them(style):
    g = party(style, on_quest={"party1": [300]})
    pick_up(g, 300)
    g.advance(2)
    assert chat(g) == [], "waits a moment: more quests may come from the same quest giver"
    g.advance(2)
    said = chat(g)
    assert len(said) == 1 and "[Boar Tusks]" in said[0] and "Anna has it too" in said[0] and "together?" in said[0], said


def test_several_quests_from_one_quest_giver_are_one_message(style):
    g = party(style, ("Anna", "Bob"), on_quest={"party1": [300], "party2": [301]})
    pick_up(g, 300)
    pick_up(g, 301, "More Boars")
    g.advance(4)
    said = chat(g)
    assert len(said) == 1 and "[Boar Tusks]" in said[0] and "[More Boars]" in said[0]
    assert "Anna and Bob have them too" in said[0] and "do them together?" in said[0]


def test_nothing_is_said_when_nobody_has_it(style):
    g = party(style)
    pick_up(g, 300)
    g.advance(5)
    assert chat(g) == []


def test_a_shared_quest_is_not_announced_back(style):
    g = party(style, on_quest={"party1": [300]})
    g.run('QUESTNPC = { name = "Anna", player = true }')
    g.fire("QUEST_DETAIL")                                # the quest window came from Anna sharing it
    pick_up(g, 300)
    g.advance(5)
    assert chat(g) == [], "Anna knows: she shared it"
    g.run("QUESTNPC = { name = 'Marshal Dughan', player = false }")
    g.fire("QUEST_DETAIL")                                # a real quest giver this time
    pick_up(g, 301, "From The Marshal")
    g.run('ON_QUEST["party1"][301] = true')
    g.advance(5)
    assert len(chat(g)) == 1 and "[From The Marshal]" in chat(g)[0]


def test_a_share_window_that_was_closed_without_accepting_does_not_count(style):
    g = party(style, on_quest={"party1": [300]})
    g.run('QUESTNPC = { name = "Anna", player = true }')
    g.fire("QUEST_DETAIL")
    g.fire("QUEST_FINISHED")                              # declined Anna's share
    g.advance(4)
    g.run("QUESTNPC = nil")
    pick_up(g, 300)                                       # later took it from the quest giver
    g.advance(5)
    assert len(chat(g)) == 1


def test_a_quest_another_quest_sharing_user_offered_is_not_announced_back(style):
    g = party(style, on_quest={"party1": [300]})
    g.peer("Anna", "H|1")
    g.peer("Anna", "L|1|1|300:0:0/5")
    g.peer("Anna", "O|300")
    pick_up(g, 300)
    g.advance(5)
    assert chat(g) == []


def test_said_once_per_quest_and_not_when_someone_just_named_it(style):
    g = party(style, on_quest={"party1": [300, 302]})
    pick_up(g, 300)
    g.advance(5)
    g.run("SENT = {}")
    g.fire("QUEST_ACCEPTED", 300)                         # abandoned and taken again
    g.advance(5)
    assert chat(g) == []
    link = "|cffffff00|Hquest:302:5|h[Named]|h|r"
    g.fire("CHAT_MSG_PARTY", "who has " + link + "?", "Anna")
    pick_up(g, 302, "Named")
    g.advance(5)
    assert chat(g) == [], "Anna just talked about it"


def test_the_setting_and_the_party_rules(style):
    g = party(style, on_quest={"party1": [300]})
    g.slash("pickup off")
    pick_up(g, 300)
    g.advance(5)
    assert chat(g) == [] and g.eval("NS.db.pickup") is False
    g2 = Game(style)
    g2.start()
    pick_up(g2, 300)                                      # no party
    g2.advance(5)
    assert chat(g2) == []


# ---- where the quest items were ---------------------------------------------------------------------------------------------
def collect(g, qid, have):
    g.run(f"""local q = BYID({qid})
        for _, o in ipairs(q.objectives) do if o.type == "item" then o.numFulfilled = {have}; o.text = "Wolf Pelt: {have}/4" end end""")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(2)                                          # the quest log is looked at 1.5 seconds after a change


def test_my_progress_message_tells_where_i_found_the_items(style):
    g = party(style, on_quest={"party1": [100]})
    collect(g, 100, 2)
    msg = g.eval("NS.statusMessage")(g.eval("NS.compat.findEntry")(100), True)
    assert msg.endswith(" - Wolf Pelt: 42.3, 61.8 in Elwynn Forest"), msg
    assert "Wolf Pelt 2/4" in msg


def test_the_spot_is_the_last_one_where_progress_happened(style):
    g = party(style, on_quest={"party1": [100]})
    collect(g, 100, 1)
    g.run("POS = { x = 0.5, y = 0.25 }")
    collect(g, 100, 2)
    assert "Wolf Pelt: 50.0, 25.0" in g.eval("NS.statusMessage")(g.eval("NS.compat.findEntry")(100), True)


def test_kills_dungeons_and_nobody_needing_it_add_nothing(style):
    g = party(style, on_quest={"party1": [100]})
    g.run("local q = BYID(100); q.objectives[1].numFulfilled = 5; q.objectives[1].text = 'Wolf slain: 5/8'")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(2)
    entry = g.eval("NS.compat.findEntry")(100)
    assert " in Elwynn Forest" not in g.eval("NS.statusMessage")(entry, True), "where wolves were killed is no news"
    g.run("POS = nil")
    collect(g, 100, 1)
    assert " in Elwynn Forest" not in g.eval("NS.statusMessage")(entry, True), "inside a dungeon there is no map spot"
    g.run("POS = { x = 0.423, y = 0.618 }")
    collect(g, 100, 2)
    g.peer("Anna", "H|1")
    g.peer("Anna", "L|1|1|100:1:8/8,4/4")                 # Anna runs the addon and is done already
    assert " in Elwynn Forest" not in g.eval("NS.statusMessage")(entry, True), "nobody still needs it"


def test_the_setting_switches_it_off(style):
    g = party(style, on_quest={"party1": [100]})
    collect(g, 100, 2)
    g.slash("coords off")
    assert " in Elwynn Forest" not in g.eval("NS.statusMessage")(g.eval("NS.compat.findEntry")(100), True)


def test_the_done_message_carries_the_spot(style):
    g = party(style, on_quest={"party1": [100]})
    collect(g, 100, 3)
    g.run("""local q = BYID(100); q.complete = true
             for _, o in ipairs(q.objectives) do o.finished = true; o.numFulfilled = o.numRequired end""")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(4)
    said = chat(g)
    assert len(said) == 1 and said[0].endswith("Wolf Pelt: 42.3, 61.8 in Elwynn Forest"), said


# ---- the budget of automatic messages -------------------------------------------------------------------------------------
def test_never_more_than_four_automatic_messages_a_minute(style):
    g = party(style)
    for i in range(7):
        g.eval("NS.say")(f"automatic {i}", True)
    g.advance(30)
    assert len(chat(g)) == 4 and g.eval("NS.dropped") == 3
    g.advance(40)
    g.eval("NS.say")("a minute later", True)
    g.advance(3)
    assert chat(g)[-1] == "a minute later"


def test_what_you_send_yourself_is_never_limited(style):
    g = party(style, on_quest={"party1": [100]})
    for _ in range(7):
        g.eval("NS.say")("automatic", True)
    g.slash("mode send")
    g.eval("NS.shareStatus")(g.eval("NS.compat.findEntry")(100))
    assert any("Wolves Among Us" in m for m in chat(g)), "a quest click always goes out"


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
