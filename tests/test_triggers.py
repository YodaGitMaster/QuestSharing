"""When does the addon share? Once when you join a party, once for a new member, once when you accept
a quest; never repeatedly and never nagging someone who declined.      python tests/test_triggers.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")


def add_quest(g, qid, title="Fresh Quest"):
    """A new quest in the Elwynn Forest part of the log (before the Westfall header)."""
    g.run("table.insert(QUESTS, 5, { id = %d, title = '%s', level = 4, objectives = {} })" % (qid, title))


def accept(g, style, qid):
    """The game's QUEST_ACCEPTED event: (questID) on the modern client, (logIndex, questID) on the classic one."""
    if style == "modern":
        g.fire("QUEST_ACCEPTED", qid)
    else:
        g.fire("QUEST_ACCEPTED", 5, qid)


def in_party(style, names=("Anna",), settle_run=True):
    g = Game(style)
    g.start()
    g.join_party(list(names))
    if settle_run:
        g.advance(30)                       # the join round: pushes 100 and 101, then finishes
    return g


# ---- once, not forever -----------------------------------------------------------------------------------
def test_joining_shares_once_and_then_stays_quiet(style):
    g = in_party(style)
    assert g.pushed() == [100, 101]
    sent, printed = len(g.sent()), len(g.printed())
    g.advance(900)                          # a quarter of an hour in the same party
    assert g.pushed() == [100, 101] and len(g.sent()) == sent and len(g.printed()) == printed
    assert g.eval("NS.isSharing()") is False


def test_an_unchanged_roster_does_not_start_another_round(style):
    g = in_party(style)
    for _ in range(5):
        g.fire("GROUP_ROSTER_UPDATE")       # the game fires this constantly (health, position, ...)
    g.advance(60)
    assert g.pushed() == [100, 101]


def test_a_new_member_gets_one_more_round(style):
    g = in_party(style)
    g.join_party(["Anna", "Bob"])
    g.advance(30)
    assert g.pushed() == [100, 101, 100, 101], "Bob had not been offered anything yet"
    g.advance(300)
    g.fire("GROUP_ROSTER_UPDATE")
    g.advance(60)
    assert len(g.pushed()) == 4, "and then nothing more"


def test_someone_who_left_and_comes_back_is_a_new_member(style):
    g = in_party(style, ("Anna", "Bob"))
    g.join_party(["Anna"])                  # Bob leaves
    g.advance(60)
    assert g.pushed() == [100, 101], "a member leaving starts nothing"
    g.join_party(["Anna", "Bob"])
    g.advance(30)
    assert g.pushed() == [100, 101, 100, 101]


def test_leaving_and_forming_a_new_party_starts_fresh(style):
    g = in_party(style)
    g.leave_party()
    g.advance(60)
    g.join_party(["Cy"])
    g.advance(30)
    assert g.pushed() == [100, 101, 100, 101]


# ---- never nag -----------------------------------------------------------------------------------------------
def test_a_quest_someone_declined_is_not_offered_again_automatically(style):
    g = Game(style)
    g.start()
    g.join_party(["Anna"])
    g.advance(5.3)
    g.reply("Anna has declined your quest.")                # about quest 100
    g.advance(30)
    assert g.pushed() == [100, 101]
    g.join_party(["Anna", "Bob"])
    g.advance(30)
    assert g.pushed() == [100, 101, 101], "100 would pop up on Anna again, so it is skipped"
    assert "someone declined" in "\n".join(g.printed())


def test_slash_share_repeats_offers_on_purpose(style):
    g = in_party(style)
    g.slash("share")
    g.advance(30)
    assert g.pushed() == [100, 101, 100, 101]


def test_a_quest_everyone_ignored_is_not_repeated(style):
    g = in_party(style)                                      # Anna never answered: the popup expired
    g.reply("Anna did not respond.")
    g.join_party(["Anna", "Bob"])
    g.advance(30)
    assert g.pushed().count(100) == 2 and g.pushed().count(101) == 2    # Bob was offered; Anna's non-answer is not "declined"


# ---- a quest you just accepted ---------------------------------------------------------------------------------------
def test_accepting_a_quest_in_a_party_shares_it_once(style):
    g = in_party(style)
    add_quest(g, 300)
    accept(g, style, 300)
    g.advance(2.9)
    assert g.pushed() == [100, 101], "a short pause first, in case you accept several"
    g.advance(1)
    assert g.pushed() == [100, 101, 300]
    accept(g, style, 300)                                    # the same event again
    g.advance(30)
    assert g.pushed() == [100, 101, 300]


def test_several_accepts_close_together_become_one_round(style):
    g = in_party(style)
    add_quest(g, 300, "First")
    add_quest(g, 301, "Second")
    accept(g, style, 300)
    g.advance(1)
    accept(g, style, 301)
    g.advance(2.3)                                           # 3 seconds after the first accept: one round starts
    assert len(g.pushed()) == 3 and g.pushed()[2] in (300, 301), g.pushed()
    first = g.pushed()[2]
    g.advance(3.5)
    assert len(g.pushed()) == 3, "the second one waits for the gap"
    g.advance(1)
    assert sorted(g.pushed()[2:]) == [300, 301] and g.pushed()[2] == first, "four seconds apart, in one round"
    g.advance(60)
    assert len(g.pushed()) == 4


def test_a_quest_accepted_during_a_round_joins_that_round(style):
    g = Game(style)
    g.start()
    g.join_party(["Anna"])
    g.advance(5.3)                                           # 100 pushed, 101 still waiting
    add_quest(g, 300)
    accept(g, style, 300)
    g.advance(60)
    assert g.pushed() == [100, 101, 300]


def test_a_quest_accepted_while_the_round_is_closing_still_gets_shared(style):
    g = Game(style)
    g.start()
    g.join_party(["Anna"])
    g.advance(14.5)                                          # queue drained, waiting for the last replies
    assert g.eval("NS.isSharing()") is True and g.pushed() == [100, 101]
    add_quest(g, 300)
    accept(g, style, 300)
    g.advance(60)
    assert g.pushed() == [100, 101, 300]


def test_a_quest_the_party_already_has_is_not_pushed(style):
    g = in_party(style)
    g.run('ON_QUEST["party1"] = {[300] = true}')
    add_quest(g, 300)
    accept(g, style, 300)
    g.advance(30)
    assert g.pushed() == [100, 101]


def test_accepting_a_quest_shares_nothing_when_it_should_not(style):
    # not in a party
    g = Game(style)
    g.start()
    add_quest(g, 300)
    accept(g, style, 300)
    g.advance(30)
    assert g.pushed() == []
    # switched off, or auto off, or the new-quest option off
    for cmd in ("off", "auto off", "new off"):
        g = in_party(style)
        g.slash(cmd)
        add_quest(g, 300)
        accept(g, style, 300)
        g.advance(30)
        assert g.pushed() == [100, 101], cmd


def test_accepting_a_quest_in_a_raid_does_nothing(style):
    g = in_party(style)
    g.run("RAID = true")
    add_quest(g, 300)
    accept(g, style, 300)
    g.advance(30)
    assert g.pushed() == [100, 101]


def test_a_quest_abandoned_right_away_is_silently_ignored(style):
    g = in_party(style)
    g.run("PRINTED = {}")
    accept(g, style, 999)                                    # not in the quest log any more
    g.advance(30)
    assert g.pushed() == [100, 101] and g.printed() == []


def test_new_quest_option_and_status(style):
    g = Game(style)
    g.start()
    g.slash("new off")
    assert g.eval("NS.db.shareNew") is False
    g.run("PRINTED = {}")
    g.slash("status")
    assert "new-quest off" in "\n".join(g.printed())
    g.slash("new")
    assert g.eval("NS.db.shareNew") is True


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
