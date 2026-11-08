"""Tests for addon-to-addon sync, completion announcements, the "quests in common" panel and the
quest-log markers (real addon files, Lua 5.1, mocked WoW API in both quest styles).
      python tests/test_features.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402
from test_questsharing import LINK100, party_game  # noqa: E402

STYLES = ("modern", "classic")
STAR = r"|TInterface\TargetingFrame\UI-RaidTargetingIcon_1:12|t"
FULL_LIST = "L|1|1|100:0:3/8,0/4;101:1:f;102:0:;200:0:1/5"


def quiet_party(style, names=("Anna",), on_quest=None, pre="", baseline=True):
    """A party with auto-share off (so no quests are pushed) and the quest-log baseline taken."""
    g = Game(style, pre)
    g.start()
    g.slash("auto off")
    for unit, ids in (on_quest or {}).items():
        g.run(f'ON_QUEST["{unit}"] = {{{", ".join("[%d] = true" % i for i in ids)}}}')
    g.join_party(list(names))
    if baseline:
        g.advance(3.5)
    return g


def hello(g, who="Anna", listed=None):
    g.peer(who, "H|1")
    if listed is not None:
        g.peer(who, "L|1|1|" + listed)


def objectives_done(g, qid, text1, text2=None):
    """Make every objective of a quest finished (data used by both the modern and the classic mock)."""
    g.run(f"""
        local q = BYID({qid}); q.complete = true
        for i, o in ipairs(q.objectives) do o.finished = true; o.numFulfilled = o.numRequired end
        q.objectives[1].text = "{text1}"
        {'q.objectives[2].text = "%s"' % text2 if text2 else ''}
    """)


# ---- sync ------------------------------------------------------------------------------------------------------
def test_sync_registers_its_prefix_and_says_hello(style):
    g = party_game(style)
    assert g.eval("PREFIXES.QSHARE") is True
    g.advance(2.1)
    assert g.addon_sent() == ["H|1"]
    assert g.eval("ADDON_SENT[1].channel") == "PARTY" and g.eval("ADDON_SENT[1].prefix") == "QSHARE"


def test_sync_answers_a_hello_with_hello_and_the_full_quest_list(style):
    g = quiet_party(style, baseline=False)
    g.advance(2.5)
    g.peer("Anna", "H|1")
    g.advance(2)
    assert g.addon_sent() == ["H|1", "H|1", FULL_LIST]


def test_sync_answers_once_per_30_seconds_so_there_is_no_ping_pong(style):
    g = quiet_party(style, baseline=False)
    g.advance(2.5)
    before = len(g.addon_sent())
    g.peer("Anna", "H|1")
    g.advance(3)
    mid = len(g.addon_sent())
    g.peer("Anna", "H|1")
    g.advance(3)
    assert mid > before and len(g.addon_sent()) == mid
    g.advance(30)
    g.peer("Anna", "H|1")
    g.advance(3)
    assert len(g.addon_sent()) > mid


def test_sync_makes_who_has_what_exact(style):
    g = quiet_party(style, ("Anna", "Bob"), on_quest={"party1": [101]})        # the game claims Anna has 101
    hello(g, "Anna", "100:0:5/8,1/4")
    assert g.eval("NS.peerHas('anna', 100)") is True
    assert g.eval("NS.peerHas('anna', 101)") is False, "a synced player's list is exact"
    assert g.eval("NS.peerHas('bob', 100)") is None, "Bob does not run the addon: unknown"
    names = lambda qid: tuple(g.eval("NS.partyHas")(g.eval(f"NS.compat.findEntry({qid})")).values())      # noqa: E731
    assert names(100) == ("Anna",) and names(101) == ()


def test_sync_list_arrives_in_parts_and_replaces_the_old_one_only_when_complete(style):
    g = quiet_party(style)
    hello(g, "Anna", "100:0:5/8,1/4")
    g.peer("Anna", "L|1|2|101:1:f")                                       # a new list starts: part 1 of 2
    assert g.eval("NS.peerHas('anna', 100)") is True, "old list kept until the new one is complete"
    g.peer("Anna", "L|2|2|200:0:1/5")
    assert g.eval("NS.peerHas('anna', 100)") is False
    assert g.eval("NS.peerHas('anna', 101)") is True and g.eval("NS.peerHas('anna', 200)") is True


def test_sync_ignores_strangers_yourself_other_prefixes_and_junk(style):
    g = quiet_party(style)
    g.peer("Zed", "H|1")                                                   # not in the party
    g.peer("Me", "H|1")                                                    # ourselves
    g.peer("Anna", "H|1", prefix="OTHERADDON")
    g.peer("Anna", "garbage")
    g.peer("Anna", "L|x|y|z")
    g.peer("Anna", "P|100:0:5/8")                                          # before any hello
    assert g.eval("next(NS.peers) == nil") is True
    hello(g, "Anna")
    g.peer("Anna", "L|1|1|not an entry;;100:9:x;100:0:1/2")                # junk entries are skipped
    assert g.eval("NS.peerHas('anna', 100)") is True


def test_sync_can_be_switched_off(style):
    g = Game(style)
    g.start()
    g.slash("sync off")
    g.slash("auto off")
    g.join_party(["Anna"])
    hello(g, "Anna", "100:0:5/8")
    g.advance(5)
    assert g.eval("next(NS.peers) == nil") is True and g.addon_sent() == []


def test_sync_updates_removals_and_completions_from_a_peer(style):
    g = quiet_party(style)
    hello(g, "Anna", "100:0:5/8,1/4;101:0:f")
    g.peer("Anna", "P|100:0:6/8,1/4")
    assert g.eval("NS.peers.anna.quests[100].objs") == "6/8,1/4"
    g.peer("Anna", "P|300:0:0/2")                                          # she accepted a quest
    assert g.eval("NS.peerHas('anna', 300)") is True
    g.peer("Anna", "R|101")
    assert g.eval("NS.peerHas('anna', 101)") is False
    g.run("PRINTED = {}")
    g.peer("Anna", "C|100")
    assert g.eval("NS.peers.anna.quests[100].complete") is True
    assert any("Anna finished the objectives of" in m and "Wolves Among Us" in m for m in g.printed())
    g.run("PRINTED = {}")
    g.peer("Anna", "C|300")                                                # a quest I do not have: no message
    assert g.printed() == []


def test_sharing_skips_what_synced_players_have_and_announces_it(style):
    g = Game(style)
    g.start()
    g.join_party(["Anna"])
    g.advance(2.5)
    hello(g, "Anna", "100:0:5/8,1/4")
    g.advance(30)
    assert g.pushed() == [101], g.pushed()
    sent = g.sent()
    assert len(sent) == 1 and LINK100 in sent[0][0] and "Anna" in sent[0][0], sent


def test_a_synced_player_who_lacks_the_quest_gets_it_even_if_the_game_says_otherwise(style):
    g = Game(style)
    g.start()
    g.run('ON_QUEST["party1"] = {[100] = true}')                            # the (unreliable) game API says "yes"
    g.join_party(["Anna"])
    g.advance(2.5)
    hello(g, "Anna", "")                                                    # but her exact list is empty
    g.advance(8)
    assert 100 in g.pushed()


def test_a_big_quest_log_is_sent_in_messages_under_the_limit(style):
    g = quiet_party(style, baseline=False)
    for i in range(40):
        g.run("QUESTS[#QUESTS+1] = { id = %d, title = 'Quest %d', level = 5, objectives = "
              "{ { text = 'Thing: 1/%d', finished = false, numFulfilled = 1, numRequired = %d } } }" % (1000 + i, i, i + 2, i + 2))
    g.advance(2.5)
    g.peer("Anna", "H|1")
    g.advance(8)
    parts = [m for m in g.addon_sent() if m.startswith("L|")]
    assert len(parts) >= 3 and all(len(m) <= 255 for m in parts), [len(m) for m in parts]
    n = int(parts[0].split("|")[2])
    assert n == len(parts) and [int(m.split("|")[1]) for m in parts] == list(range(1, n + 1))
    entries = [e for m in parts for e in m.split("|", 3)[3].split(";") if e]
    assert len(entries) == 4 + 40 and "1039:0:1/41" in entries


def test_leaving_the_party_forgets_the_synced_players(style):
    g = quiet_party(style)
    hello(g, "Anna", "100:0:5/8")
    g.leave_party()
    assert g.eval("next(NS.peers) == nil") is True
    g.join_party(["Anna"])
    assert g.eval("NS.peerHas('anna', 100)") is None


def test_quest_log_changes_are_sent_to_synced_players(style):
    g = quiet_party(style)
    hello(g, "Anna", "100:0:3/8,0/4")
    g.advance(3)
    base = len(g.addon_sent())
    g.run('BYID(100).objectives[1].text = "Wolf slain: 5/8"; BYID(100).objectives[1].numFulfilled = 5')
    g.run("table.remove(QUESTS, 4)")                                        # quest 102 abandoned
    g.run("QUESTS[#QUESTS+1] = { id = 300, title = 'New', level = 4, objectives = {} }")
    g.fire("QUEST_LOG_UPDATE")
    g.fire("QUEST_LOG_UPDATE")                                              # bursts are folded into one look
    g.advance(4)
    sent = g.addon_sent()[base:]
    assert "P|100:0:5/8,0/4" in sent and "R|102" in sent and "P|300:0:" in sent, sent
    assert len(sent) == 3, sent


def test_nothing_is_sent_when_nobody_listens(style):
    g = quiet_party(style)
    base = len(g.addon_sent())
    g.run('BYID(100).objectives[1].text = "Wolf slain: 5/8"; BYID(100).objectives[1].numFulfilled = 5')
    g.fire("QUEST_LOG_UPDATE")
    g.advance(4)
    assert [m for m in g.addon_sent()[base:] if m.startswith(("P|", "R|", "C|"))] == []


# ---- completion announcements -------------------------------------------------------------------------------------
def test_finishing_a_shared_quest_is_announced_to_the_party(style):
    g = quiet_party(style, on_quest={"party1": [100]})
    objectives_done(g, 100, "Wolf slain: 8/8", "Wolf Pelt: 4/4")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(2)
    assert g.sent() == [(f"{{rt1}} {LINK100} - I'm done with this one, ready to turn in! (Anna has it too!)", "PARTY")]
    g.fire("QUEST_LOG_UPDATE")                                              # the log keeps firing: said only once
    g.advance(2)
    assert len(g.sent()) == 1


def test_finishing_is_also_sent_to_synced_players(style):
    g = quiet_party(style)
    hello(g, "Anna", "100:0:3/8,0/4")
    g.advance(3)
    objectives_done(g, 100, "Wolf slain: 8/8", "Wolf Pelt: 4/4")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(4)
    sent = g.addon_sent()
    assert "C|100" in sent and "P|100:1:8/8,4/4" in sent, sent
    assert len(g.sent()) == 1, "Anna has it (synced list), so the party is told too"


def test_no_announcement_when_nobody_shares_it_or_it_is_switched_off(style):
    g = quiet_party(style)                                                  # nobody has quest 100
    objectives_done(g, 100, "Wolf slain: 8/8", "Wolf Pelt: 4/4")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(2)
    assert g.sent() == []
    g2 = quiet_party(style, on_quest={"party1": [100]})
    g2.slash("announce off")
    objectives_done(g2, 100, "Wolf slain: 8/8", "Wolf Pelt: 4/4")
    g2.fire("QUEST_LOG_UPDATE")
    g2.advance(2)
    assert g2.sent() == []


def test_quests_that_were_already_done_or_are_just_accepted_are_not_announced(style):
    g = quiet_party(style, on_quest={"party1": [101, 300]})                 # 101 was complete from the start
    g.run("QUESTS[#QUESTS+1] = { id = 300, title = 'Fresh', level = 4, complete = true, objectives = {} }")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(2)
    assert g.sent() == []


# ---- the "quests in common" panel ------------------------------------------------------------------------------------
def lines(g):
    return [s.replace(STAR, "*") for s in g.eval("NS.panelLines")().values()]


def test_panel_lines_for_synced_and_plain_members(style):
    g = quiet_party(style, ("Anna", "Bob"), on_quest={"party2": [100]})
    hello(g, "Anna", "100:0:5/8,1/4;101:1:f")
    assert lines(g) == ["Party: Anna (addon), Bob",
                        "* Wolves Among Us: Anna 5/8, 1/4 | Bob has it",
                        "* Report to Goldshire (done): Anna done"]


def test_panel_lines_edge_cases(style):
    g = Game(style)
    g.start()
    assert lines(g) == ["You are not in a party."]
    g.join_party(["Anna", "Bob"])
    assert lines(g) == ["Party: Anna, Bob", "No quests in common yet."]
    hello(g, "Anna", "999:0:1/2")                                            # Anna lacks all of ours
    assert lines(g)[-1] == "No quests in common yet."


def test_panel_window_shows_the_lines_and_remembers_where_it_was_put(style):
    g = quiet_party(style, on_quest={"party1": [100]})
    g.slash("panel on")
    panel, rows = g.eval("NS._panel()")
    assert g.eval("NS.db.panel") is True and panel.shown
    texts = [rows[i].text for i in range(1, 4)]
    assert texts[0] == "Party: Anna" and "Wolves Among Us" in texts[1] and "Anna has it" in texts[1], texts
    assert rows[3].shown is False, "unused rows are hidden"
    assert panel.height == 16 + 2 * 14
    hello(g, "Anna", "100:0:5/8,1/4")                                         # new data refreshes it by itself
    g.advance(1)
    assert "Anna 5/8, 1/4" in rows[2].text
    g.eval("function(p) p.scripts.OnDragStop(p) end")(panel)
    assert tuple(g.eval("NS.db.panelPos").values()) == ("CENTER", 0, 0)
    g.slash("panel off")
    assert panel.shown is False


# ---- markers in the quest log ----------------------------------------------------------------------------------------
def test_marker_text(style):
    g = quiet_party(style, ("Anna", "Bob"), on_quest={"party1": [100], "party2": [100]})
    e = lambda q: g.eval(f"NS.compat.findEntry({q})")                          # noqa: E731
    assert g.eval("NS.markerText")(e(100)).replace(STAR, "*") == " * Anna +1"
    assert g.eval("NS.markerText")(e(101)) == ""


def test_classic_quest_log_gets_markers():
    g = quiet_party("classic", on_quest={"party1": [100]}, pre="CLASSIC_QUESTLOG(6)")
    assert g.eval("NS.hooks.qlClassic") is True
    g.eval("QuestLog_Update")()
    t = lambda i: g.eval(f"QuestLogTitle{i}.text").replace(STAR, "*")          # noqa: E731
    assert t(1) == " Elwynn Forest" and t(2) == " Wolves Among Us * Anna" and t(3) == " Report to Goldshire"
    g.eval("QuestLog_Update")()                                                # redrawn: still one marker
    assert t(2) == " Wolves Among Us * Anna"
    g.slash("markers off")
    g.eval("QuestLog_Update")()
    assert t(2) == " Wolves Among Us"


def test_modern_quest_log_gets_markers():
    g = quiet_party("modern", on_quest={"party1": [100]}, pre="MODERN_QUESTLOG()")
    assert g.eval("NS.hooks.qlModern") is True
    g.eval("QuestLogQuests_Update")()
    texts = sorted(b.Text.text.replace(STAR, "*") for b in g.eval("QuestScrollFrame.titleFramePool.active").keys())
    assert texts == ["A Personal Quest", "Report to Goldshire", "The Defias Brotherhood", "Wolves Among Us * Anna"], texts
    g.eval("QuestLogQuests_Update")()                                          # redrawn: still one marker
    again = sorted(b.Text.text.replace(STAR, "*") for b in g.eval("QuestScrollFrame.titleFramePool.active").keys())
    assert again == texts
    g.slash("markers off")
    g.eval("QuestLogQuests_Update")()
    assert all("*" not in b.Text.text.replace(STAR, "*") for b in g.eval("QuestScrollFrame.titleFramePool.active").keys())


def test_markers_install_when_the_quest_log_loads_late():
    g = Game("classic")
    g.start()
    assert g.eval("NS.hooks.qlClassic") is None
    g.run("CLASSIC_QUESTLOG(6)")
    g.fire("ADDON_LOADED", "Blizzard_QuestLog")
    assert g.eval("NS.hooks.qlClassic") is True


# ---- commands and probe -----------------------------------------------------------------------------------------------
def test_new_commands(style):
    g = Game(style)
    g.start()
    g.slash("sync off")
    g.slash("announce off")
    g.slash("markers off")
    assert (g.eval("NS.db.sync"), g.eval("NS.db.announce"), g.eval("NS.db.markers")) == (False, False, False)
    g.slash("panel")
    assert g.eval("NS.db.panel") is True


def test_probe_reports_sync_and_markers():
    g = quiet_party("classic", pre="CLASSIC_QUESTLOG(6)")
    hello(g, "Anna", "100:0:1/2")
    g.run("PRINTED = {}")
    g.slash("probe")
    text = "\n".join(g.printed())
    assert "message prefix registered: yes, synced players in your party: 1" in text
    assert "quest log markers: classic yes, modern NO" in text


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
