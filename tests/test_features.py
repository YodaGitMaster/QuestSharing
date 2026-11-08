"""Tests for addon-to-addon sync, completion announcements, the "quests in common" panel and the
quest-log markers (real addon files, Lua 5.1, mocked WoW API in both quest styles).
      python tests/test_features.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game, OPEN_101  # noqa: E402
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
    assert g.printed() == [], "no chat line: the Party quests window shows her check mark"
    assert len(g.eval("SOUNDS")) == 1, "a soft sound instead"
    g.peer("Anna", "C|300")                                                # a quest I do not have: nothing at all
    assert g.printed() == [] and len(g.eval("SOUNDS")) == 1


def test_sharing_skips_what_synced_players_have_and_announces_it(style):
    g = Game(style)
    g.run(OPEN_101)                                   # two quests in progress
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
    base = len([m for m in g.addon_sent() if not m.startswith("M|")])
    g.run('BYID(100).objectives[1].text = "Wolf slain: 5/8"; BYID(100).objectives[1].numFulfilled = 5')
    g.run("table.remove(QUESTS, 4)")                                        # quest 102 abandoned
    g.run("QUESTS[#QUESTS+1] = { id = 300, title = 'New', level = 4, objectives = {} }")
    g.fire("QUEST_LOG_UPDATE")
    g.fire("QUEST_LOG_UPDATE")                                              # bursts are folded into one look
    g.advance(4)
    sent = [m for m in g.addon_sent() if not m.startswith("M|")][base:]
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
    assert g.sent() == [(f"{{rt1}} {LINK100} - I'm done with this one, ready to turn in! - Wolf Pelt: 42.3, 61.8 in Elwynn Forest", "PARTY")], \
        "Anna still needs the pelts: where I found them comes along"
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
    g.run(OPEN_101)                                   # two quests in progress
    hello(g, "Anna", "100:0:5/8,1/4;101:1:f")
    assert lines(g) == ["Party: Anna (addon), Bob",
                        "* Wolves Among Us: Anna 5/8, 1/4 | Bob has it",
                        "* Report to Goldshire: Anna done"]


def test_panel_lines_edge_cases(style):
    g = Game(style)
    g.start()
    assert lines(g) == ["You are not in a party."]
    g.join_party(["Anna", "Bob"])
    assert lines(g) == ["Party: Anna, Bob", "No quests in common yet."]
    hello(g, "Anna", "999:0:1/2")                                            # Anna lacks all of ours
    assert lines(g)[-1] == "No quests in common yet."


def plain(t):
    """The text without colour codes."""
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def panel_of(g):
    g.slash("panel on")
    g.advance(1)
    return g.eval("NS._panel()")


CHECK, CROSS, WAIT = ("Interface\\RaidFrame\\ReadyCheck-Ready", "Interface\\RaidFrame\\ReadyCheck-NotReady",
                      "Interface\\RaidFrame\\ReadyCheck-Waiting")


def grid(rows, cols, n_members):
    """[(quest title, [cell picture per member])] for the rows on screen."""
    out = []
    for i in range(1, 13):                               # every row the window has, not just the first five
        r = rows[i]
        if r is not None and r.shown:
            out.append((plain(r.title.text), [r.cells[j].texture for j in range(1, n_members + 1)]))
    return out


def test_the_window_is_a_grid_quest_then_one_column_per_member(style):
    g = quiet_party(style, ("Anna", "Bob"), on_quest={"party1": [100], "party2": [100, 101]})
    g.run(OPEN_101)                                   # two quests in progress
    panel, rows, cols, notes = panel_of(g)
    assert g.eval("NS.db.panel") is True and panel.shown
    assert plain(panel.questHead.text) == "Quest"
    assert [plain(cols[j].name.text) for j in (1, 2)] == ["Anna", "Bob"] and cols[3].icon.shown is False
    shown = dict(grid(rows, cols, 2))
    assert shown["Wolves Among Us"] == [CHECK, CHECK]
    assert shown["Report to Goldshire"] == [CROSS, CHECK], "Anna does not have it: an X"
    assert shown["A Personal Quest"] == [CROSS, CROSS]
    g.eval("function(p) p.scripts.OnDragStop(p) end")(panel)
    assert (panel.point[1], panel.point[4], panel.point[5]) == ("LEFT", 20, 120), "first time: on the left, not mid-screen"
    assert tuple(g.eval("NS.db.panelPos").values()) == ("LEFT", 20, 120)
    g.slash("panel off")
    assert panel.shown is False


def test_at_most_five_quests_the_nearest_first(style):
    g = quiet_party(style, ("Anna",))
    g.run(OPEN_101)                                   # two quests in progress
    g.run("""for i = 1, 6 do
        table.insert(QUESTS, 5, { id = 400 + i, title = "Extra " .. i, level = 5, objectives = {} })
    end""")                                                  # all six in Elwynn Forest, like 100-102
    g.fire("QUEST_LOG_UPDATE")
    if style == "modern":
        g.set_dist(q100=900, q101=100, q102=4000, q200=50, q401=10, q402=8000, q403=2500, q404=9000, q405=6000, q406=7000)
    panel, rows, cols, notes = panel_of(g)
    titles = [t for t, _ in grid(rows, cols, 1)]
    assert len(titles) == 5 and rows[5].shown, "five at most"
    if style == "modern":
        assert titles == ["Extra 1", "Report to Goldshire", "Wolves Among Us", "Extra 3", "A Personal Quest"], titles
        assert "The Defias Brotherhood" not in titles, "Westfall's quest is not shown in Elwynn, however near"
    else:                                                # no distances on this client: the quest-log order of this zone
        assert titles[:3] == ["Wolves Among Us", "Report to Goldshire", "A Personal Quest"], titles


def test_the_list_follows_me_as_i_move_without_jumping_around(style):
    if style != "modern":
        return
    g = quiet_party(style, ("Anna",))
    g.run(OPEN_101)
    g.set_dist(q100=900, q101=100, q102=4000, q200=50)
    panel, rows, cols, notes = panel_of(g)
    assert [t for t, _ in grid(rows, cols, 1)][0] == "Report to Goldshire"
    g.set_dist(q100=10, q101=100, q102=4000, q200=50)       # I walked to the wolves
    g.advance(4.5)
    assert [t for t, _ in grid(rows, cols, 1)][0] == "Wolves Among Us", "re-sorted by itself"
    g.set_dist(q100=10, q101=12, q102=4000, q200=50)        # two quests about as near: no flip-flop
    g.advance(4.5)
    order = [t for t, _ in grid(rows, cols, 1)]
    g.set_dist(q100=12, q101=10, q102=4000, q200=50)
    g.advance(4.5)
    assert [t for t, _ in grid(rows, cols, 1)] == order, "a small difference does not reorder the rows"


def test_finished_members_get_a_gold_check_and_unknown_ones_a_question_mark(style):
    g = quiet_party(style, ("Anna", "Bob"), pre=OPEN_101)  # 101 in progress for me
    hello(g, "Anna", "101:1:f")                           # Anna runs the addon and finished 101
    g.run("function UnitIsVisible(u) return u ~= 'party2' end")                 # Bob is far away: the game cannot tell
    panel, rows, cols, notes = panel_of(g)
    row = [rows[i] for i in range(1, 6) if rows[i].shown and "Report to Goldshire" in rows[i].title.text][0]
    assert row.cells[1].texture == CHECK and tuple(round(v, 2) for v in list(row.cells[1].vertex.values())[:3]) == (1, 0.82, 0)
    assert row.cells[2].texture == WAIT, "out of range: a question mark, not a wrong X"
    assert not row.title.text.startswith("|cff55ff55"), "I am still on it"
    assert "QS" in plain(cols[1].name.text) and "QS" not in plain(cols[2].name.text)


def test_names_in_class_colour_with_the_class_icon(style):
    g = quiet_party(style, ("Anna", "Bob"))
    g.run('CLASSES.Anna = "MAGE"; CLASSES.Bob = "PRIEST"')
    panel, rows, cols, notes = panel_of(g)
    assert cols[1].name.text.startswith("|cff40c7eb") and cols[1].icon.coords[1] == 0.25
    assert cols[2].icon.coords[1] == 0.5


def test_my_own_progress_is_next_to_the_quest(style):
    g = quiet_party(style, ("Anna",))
    panel, rows, cols, notes = panel_of(g)
    row = [rows[i] for i in range(1, 6) if rows[i].shown and "Wolves Among Us" in rows[i].title.text][0]
    assert plain(row.mine.text) == "3/8 +1"


def row_of(rows, title):
    return [rows[i] for i in range(1, 6) if rows[i].shown and title in rows[i].title.text][0]


def test_left_click_offers_the_quest_to_whoever_does_not_have_it(style):
    g = quiet_party(style, ("Anna", "Bob"), on_quest={"party1": [100]})
    panel, rows, cols, notes = panel_of(g)
    g.run("PUSHED = {}; PRINTED = {}")
    g.eval("function(r) r.scripts.OnClick(r, 'LeftButton') end")(row_of(rows, "Wolves Among Us"))
    assert g.pushed() == [100] and "offered" in "\n".join(g.printed()) and "to Bob" in "\n".join(g.printed())
    assert g.sent() == [], "offering is a popup, not a chat message"


def test_left_click_explains_when_it_cannot_offer(style):
    g = quiet_party(style, ("Anna",), on_quest={"party1": [100]})
    panel, rows, cols, notes = panel_of(g)
    click = g.eval("function(r) r.scripts.OnClick(r, 'LeftButton') end")
    g.run("PUSHED = {}; PRINTED = {}")
    click(row_of(rows, "Wolves Among Us"))
    assert g.pushed() == [] and "everybody in the party has" in "\n".join(g.printed())
    click(row_of(rows, "A Personal Quest"))
    assert g.pushed() == [] and "cannot be shared" in "\n".join(g.printed())


def menu_pick(g, row, label):
    """Right click a row, then click the menu line with this text."""
    g.eval("function(r) r.scripts.OnClick(r, 'RightButton') end")(row)
    menu, lines = g.eval("NS._questMenu()")
    i = next(i for i in range(1, 7) if lines[i].shown and label in plain(lines[i].text))
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(lines[i])


def test_right_click_tells_the_party_how_i_am_doing_and_asks_them(style):
    g = quiet_party(style, ("Anna",), on_quest={"party1": [100, 101]})
    panel, rows, cols, notes = panel_of(g)
    ask = lambda row: menu_pick(g, row, "Tell the party how I am doing")
    ask(row_of(rows, "Wolves Among Us"))
    msg, channel = g.sent()[-1]
    assert channel == "PARTY" and "[Wolves Among Us]" in msg
    assert "I still need Wolf slain 3/8, Wolf Pelt 0/4." in msg and msg.endswith(("What about you?", "How about you?", "And you?"))
    ask(row_of(rows, "Wolves Among Us"))
    assert len(g.sent()) == 1, "a double click is not said twice"
    assert not any("Report to Goldshire" in rows[i].title.text for i in range(1, 6) if rows[i].shown), "I finished it: not listed"
    assert g.opened() == [], "it is sent at once: a right click is a click"


def test_the_question_carries_where_i_found_the_items(style):
    g = quiet_party(style, ("Anna",), on_quest={"party1": [100]})
    hello(g, "Anna", "100:0:5/8,1/4")
    g.run("local q = BYID(100); q.objectives[2].numFulfilled = 2; q.objectives[2].text = 'Wolf Pelt: 2/4'")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(2)
    panel, rows, cols, notes = panel_of(g)
    menu_pick(g, row_of(rows, "Wolves Among Us"), "Tell the party how I am doing")
    assert "Wolf Pelt 2/4 (Wolf Pelt at 42.3, 61.8)." in g.sent()[-1][0]
    g.advance(1)
    assert any(m.startswith("S|100|1429|0.4230|0.6180|Wolf Pelt") for m in g.addon_sent()), "addon users get a map pin there"


def test_members_who_cannot_take_it_get_a_dash(style):
    g = quiet_party(style, ("Anna",))
    g.run("NS.known[100] = { anna = 'done' }")              # "Anna has already completed that quest"
    panel, rows, cols, notes = panel_of(g)
    assert row_of(rows, "Wolves Among Us").cells[1].texture == "Interface\\Buttons\\UI-MinusButton-Up"


def test_scroll_down_for_the_rest_of_the_zone(style):
    g = quiet_party(style, ("Anna",))
    g.run("""for i = 1, 4 do
        table.insert(QUESTS, 5, { id = 400 + i, title = "Zone Quest " .. i, level = 5, objectives = {} })
    end""")                                                  # all in Elwynn Forest (before the Westfall header)
    g.fire("QUEST_LOG_UPDATE")
    panel, rows, cols, notes = panel_of(g)
    first = [t for t, _ in grid(rows, cols, 1)]
    assert len(first) == 5 and "scroll down: " in notes.text and "more in Elwynn Forest" in notes.text
    g.eval("function(f) f.scripts.OnMouseWheel(f, -1) end")(panel)
    after = [t for t, _ in grid(rows, cols, 1)]
    assert after != first and after[:4] == first[1:], "one row further down"
    for _ in range(10):
        g.eval("function(f) f.scripts.OnMouseWheel(f, -1) end")(panel)
    assert "scroll up" in notes.text
    for _ in range(10):
        g.eval("function(f) f.scripts.OnMouseWheel(f, 1) end")(panel)
    assert [t for t, _ in grid(rows, cols, 1)] == first


def test_in_a_raid_it_says_why_nothing_is_shared(style):
    g = quiet_party(style, ("Anna",))
    panel, rows, cols, notes = panel_of(g)
    g.run("RAID = true")
    g.eval("NS.refreshPanel")()
    assert "not in a raid" in notes.text


def test_a_finished_quest_does_not_add_who_else_has_it(style):
    g = quiet_party(style, ("Anna",), on_quest={"party1": [100, 101]})
    done = g.eval("NS.statusMessage")(g.eval("NS.compat.findEntry")(101))
    open_ = g.eval("NS.statusMessage")(g.eval("NS.compat.findEntry")(100))
    assert "has it too" not in done and done.startswith("{rt1} "), "finished: no 'Anna has it too' tail"
    assert "Anna has it too!" in open_, "still said for a quest you are working on"


def test_the_header_counts_the_shared_quests_and_marks_addon_users(style):
    g = quiet_party(style, ("Anna", "Bob"), on_quest={"party1": [100]})
    g.run(OPEN_101)                                   # two quests in progress
    hello(g, "Bob", "100:0:1/8")
    panel, rows, cols, notes = panel_of(g)
    assert plain(panel.count.text) == "(1 shared, 3 here)"
    assert "QS" not in cols[1].name.text and plain(cols[2].name.text) == "Bob QS", "Bob runs Quest Sharing too"


def test_post_all_puts_the_shared_ones_in_the_chat_box_at_once(style):
    g = quiet_party(style, ("Anna",), on_quest={"party1": [100, 101]})
    g.slash("mode box")                          # the chat box, as by default
    g.run(OPEN_101)                                   # two quests in progress
    panel, rows, cols, notes = panel_of(g)
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(panel.post)
    text = g.eval("EDITBOX.text")
    assert "Wolves Among Us" in text and "Report to Goldshire" in text and " + " in text and "{rt1}" not in text
    assert "Personal" not in text, "only quests someone in the party has"
    assert g.sent() == [] and len(g.opened()) == 1, "one message, waiting for Enter"
    g.run("CLOSE_CHAT()")
    g.slash("mode send")
    g.eval("NS.postAllProgress")()
    assert len(g.sent()) == 1 and g.sent()[0][1] == "PARTY" and " + " in g.sent()[0][0]


def test_post_all_says_when_not_everything_fits(style):
    g = quiet_party(style, ("Anna",))
    g.run("""QUESTS = { { header = "Elwynn Forest" } }
    for i = 1, 5 do
        QUESTS[#QUESTS + 1] = { id = 400 + i, title = "A rather long quest name number " .. i, level = 5, objectives = {
            { text = "Something to collect: 0/10", finished = false, numFulfilled = 0, numRequired = 10 },
            { text = "Something else to find: 0/10", finished = false, numFulfilled = 0, numRequired = 10 } } }
        ON_QUEST["party1"] = ON_QUEST["party1"] or {}
        ON_QUEST["party1"][400 + i] = true
    end""")
    g.fire("QUEST_LOG_UPDATE")
    panel_of(g)
    added = g.eval("NS.postAllProgress")()
    assert 0 < added < 5 and len(g.eval("EDITBOX.text")) <= 255
    assert "fit in one message" in "\n".join(g.printed())


def test_the_share_button_offers_my_quests_now(style):
    g = quiet_party(style, ("Anna",))
    panel, rows, cols, notes = panel_of(g)
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(panel.share)
    g.advance(20)
    assert g.pushed() != [], "the area quests were offered"


def test_the_window_folds_to_its_title_and_remembers_it(style):
    g = quiet_party(style, ("Anna",), on_quest={"party1": [100]})
    panel, rows, cols, notes = panel_of(g)
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(panel.collapse)
    assert g.eval("NS.db.panelCollapsed") is True and panel.height == 30 and rows[1].shown is False and cols[1].icon.shown is False
    assert panel.collapse.text == "+"
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(panel.collapse)
    assert g.eval("NS.db.panelCollapsed") is False and rows[1].shown is True


def test_the_window_hides_in_combat_and_comes_back(style):
    g = quiet_party(style, ("Anna",), on_quest={"party1": [100]})
    panel, rows, cols, notes = panel_of(g)
    g.run("IN_COMBAT = true")
    g.fire("PLAYER_REGEN_DISABLED")
    assert panel.shown is False
    g.fire("GROUP_ROSTER_UPDATE")
    g.advance(2)
    assert panel.shown is False, "not even a roster change brings it back mid-fight"
    g.run("IN_COMBAT = false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(1)
    assert panel.shown is True
    g.run("NS.setSetting('panelCombat', false); IN_COMBAT = true")
    g.fire("PLAYER_REGEN_DISABLED")
    assert panel.shown is True, "switched off: it stays"


def test_size_and_moving_it_back(style):
    g = quiet_party(style, ("Anna",))
    panel, rows, cols, notes = panel_of(g)
    g.run("NS.setSetting('panelScale', 130)")
    assert panel.scale == 1.3
    g.run('NS.db.panelPos = { "TOPLEFT", 3000, 3000 }')
    g.run("NS.resetPanelPosition()")
    assert g.eval("NS.db.panelPos") is None and (panel.point[1], panel.point[4], panel.point[5]) == ("LEFT", 20, 120)


def test_a_row_has_a_tooltip_with_everybodys_status(style):
    g = quiet_party(style, ("Anna", "Bob"), on_quest={"party2": [100]})
    hello(g, "Anna", "100:0:5/8,1/4")
    panel, rows, cols, notes = panel_of(g)
    row = [rows[i] for i in range(1, 6) if rows[i].shown and "Wolves Among Us" in rows[i].title.text][0]
    g.eval("function(r) r.scripts.OnEnter(r) end")(row)
    lines = list(g.eval("TOOLTIP.lines").values())
    assert g.eval("TOOLTIP.text") == "Wolves Among Us" and "Anna: 5/8, 1/4" in lines and "Bob: has it" in lines
    assert any("Left click: offer it" in l for l in lines) and any("Right click: more" in l for l in lines)


def test_the_window_is_as_wide_as_the_party(style):
    g = quiet_party(style, ("Anna",))
    panel, rows, cols, notes = panel_of(g)
    narrow = panel.width
    g.join_party(["Anna", "Bob", "Cy", "Dee"])
    g.advance(5)
    assert panel.width > narrow and cols[4].icon.shown is True


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
