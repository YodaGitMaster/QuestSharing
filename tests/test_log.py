"""The debug log: every action and its outcome, errors or not, kept in QuestSharingLog (the game saves it to the
addon's SavedVariables file on /reload or logout); off by default.        python tests/test_log.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402
from test_quick import game as quick_game, pick, target, hold_and_release_on  # noqa: E402
from test_box import CLICK_ONLY, click  # noqa: E402

STYLES = ("modern", "classic")


def log(g):
    L = g.eval("QuestSharingLog")
    if L is None:
        return []
    return [L[i] for i in range(1, int(g.eval("#QuestSharingLog")) + 1)]


def text(g):
    return "\n".join(log(g))


def on(style):
    g = quick_game(style)
    g.slash("debug on")
    return g


# ---- off by default ---------------------------------------------------------------------------------------------------
def test_off_by_default_nothing_is_kept(style):
    g = quick_game(style)
    assert g.eval("NS.db.debug") is False
    target(g, "Lia")
    pick(g, 5)
    g.slash("status")
    g.fire("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()")
    assert log(g) == [], "nothing is written down while the switch is off"


def test_the_saved_variable_is_declared_and_the_settings_have_the_switch(style):
    toc = (pathlib.Path(__file__).resolve().parent.parent / "QuestSharing" / "QuestSharing.toc").read_text()
    assert re.search(r"^## SavedVariables: QuestSharingDB, QuestSharingLog$", toc, re.M)
    g = quick_game(style)
    keys = [g.eval(f"NS.settingRows[{i}].key") for i in range(1, int(g.eval("#NS.settingRows")) + 1)]
    labels = [g.eval(f"NS.settingRows[{i}].label") for i in range(1, int(g.eval("#NS.settingRows")) + 1)]
    assert "debug" in keys and "Show the debug log" in labels


# ---- what goes in -------------------------------------------------------------------------------------------------------
def test_switching_it_on_starts_with_a_line_saying_what_this_session_is(style):
    g = on(style)
    first = log(g)[0]
    assert re.match(r"\d\d:\d\d:\d\d session: debug log on - Quest Sharing \S+ \| game \S+ ", first), first
    assert "| language " in first and "| Questie: " in first


def test_a_ring_message_says_what_was_picked_who_it_was_for_and_what_happened(style):
    g = on(style)
    target(g, "Lia")
    pick(g, 5)                                                   # "Thanks": auto, Lia picked
    t = text(g)
    assert 'ring: slot 5 "Thanks" (channel auto); for: Lia; sends at once: yes' in t, t
    assert "chat: sent to WHISPER Lia: Thanks!" in t and "ring: done" in t


def test_a_release_into_the_chat_box_and_a_reason_shown_to_you_are_written_down(style):
    g = on(style)
    g.advance(2)
    hold_and_release_on(g, 1)                                    # Hello, nobody picked: /s on a release -> chat box
    t = text(g)
    assert "released on a click-only message" in t and "chat box: /s Hey there! o/" in t, t
    assert "shown: quick chat: /s and /y need a click" in t, "what you were told is in the log too"
    g.slash("quick route 5 whisper")
    g.run("TARGET = nil")
    g.advance(2)
    pick(g, 5)
    assert "shown: quick chat: target a player (or point at one when you open the ring) to whisper them" in text(g)
    assert "ring: nothing sent" in text(g)


def test_commands_and_settings_are_written_down(style):
    g = on(style)
    g.slash("quick send off")
    t = text(g)
    assert "command: /qs quick send off" in t and "setting: quickSend = false" in t


def test_errors_and_refused_calls_go_in_with_their_details(style):
    g = on(style)
    g.fire("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()")
    t = text(g)
    assert "ERROR BLOCKED by the game: tried to call the protected function UNKNOWN()" in t
    assert "     the game's event: ADDON_ACTION_BLOCKED" in t and "     running: " in t


def test_shares_are_written_down_with_their_outcome(style):
    g = Game(style, CLICK_ONLY)
    g.start()
    g.slash("debug on")
    g.join_party(["Anna"])
    g.advance(40)
    t = text(g)
    assert re.search(r"share: round \(joined a party\): \d+ to offer", t), t
    assert "(automatic): refused by the game" in t and "share: waiting for your click" in t
    click(g, "share")
    assert "(your click): offered" in text(g)


def test_what_the_game_did_around_the_addon_is_written_down(style):
    g = on(style)
    g.run("IN_COMBAT = true")
    g.fire("PLAYER_REGEN_DISABLED")
    g.run("IN_COMBAT = false")
    g.fire("PLAYER_REGEN_ENABLED")
    target(g, "Lia")
    g.fire("PLAYER_TARGET_CHANGED")
    g.join_party(["Anna"])
    g.fire("CHAT_MSG_SYSTEM", "No player named 'Bob' is currently playing.")
    t = text(g)
    for want in ("event: combat starts", "event: combat ends", "event: target: Lia (player, friendly)",
                 "event: party: Anna", "game says: No player named 'Bob' is currently playing."):
        assert want in t, (want, t)


def test_a_ping_press_says_what_was_loaded_and_whether_it_went_through():
    g = Game("modern")
    g.start()
    g.slash("auto off")
    g.slash("debug on")
    g.join_party(["Anna"])
    g.advance(3)
    g.run('ADD_CREATURE("nameplate1", "Kobold Vermin", true, 0, 0, true)')
    g.advance(1.5)
    g.eval("PRESS")(g.eval("NS.pingButton()"))
    assert "ping: press 1: loaded unit Kobold Vermin, went through" in text(g), text(g)


# ---- keeping it readable and small --------------------------------------------------------------------------------------
def test_the_same_line_again_becomes_one_line_with_a_count(style):
    g = on(style)
    n = len(log(g))
    for _ in range(4):
        g.eval("NS.log")("call", "placing a quest icon over a nameplate")
    assert len(log(g)) == n + 1 and log(g)[-1].endswith("call: placing a quest icon over a nameplate (x4)")


def test_the_oldest_lines_go_when_it_is_full(style):
    g = on(style)
    g.run("for i = 1, NS.LOG_MAX + 400 do NS.log('t', 'line ' .. i) end")
    n = len(log(g))
    assert n <= g.eval("NS.LOG_MAX") + 300 and log(g)[-1].endswith("t: line %d" % (g.eval("NS.LOG_MAX") + 400))


def test_a_new_session_does_not_count_on_into_the_last_one(style):
    g = on(style)
    g.eval("NS.log")("t", "same")
    g.eval("NS.logSession")("login")
    g.eval("NS.log")("t", "same")
    assert sum(1 for line in log(g) if line.endswith("t: same")) == 2


# ---- /qs log -----------------------------------------------------------------------------------------------------------
def test_slash_log_shows_it_in_a_window_and_clear_empties_it(style):
    g = on(style)
    target(g, "Lia")
    pick(g, 5)
    g.run("PRINTED = {}")
    g.slash("log")
    win, box = g.eval("NS._reportWindow()")
    assert win.shown is True and "debug log (on)" in box.text and "chat: sent to WHISPER Lia: Thanks!" in box.text
    assert "SavedVariables/QuestSharing.lua" in box.text
    g.slash("log clear")
    assert len(log(g)) <= 3 and "debug log cleared" in "\n".join(g.printed())


def test_the_window_scrolls_and_has_select_all_switch_clear_and_close(style):
    g = on(style)
    g.run("for i = 1, 900 do NS.log('t', 'a long log, line ' .. i) end")
    g.slash("log")
    win, box = g.eval("NS._reportWindow()")
    assert g.eval("(function() local w, b = NS._reportWindow(); return w.scroll.scrollChild == b end)()") is True, \
        "the text lies inside a scroll frame: it stays in the window"
    g.run("NS._reportWindow().scroll.scrollRange = 5000")
    g.eval("function(s) s.scripts.OnMouseWheel(s, -1) end")(win.scroll)
    assert win.scroll.vscroll == 60, "the mouse wheel scrolls"
    for b in ("selectAll", "showLog", "showErrors", "clear", "close"):
        assert win[b] is not None, b
    g.run("PRINTED = {}")
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(win.selectAll)
    assert "press Cmd+C (Mac) or Ctrl+C (Windows)" in "\n".join(g.printed())
    g.eval("NS.logError")("x", "something broke")
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(win.showErrors)
    assert "something broke" in box.text and "errors" in win.title.text and win.clear.shown is True
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(win.clear)
    assert len(g.eval("NS.db.errors")) == 0 and "no errors recorded" in box.text
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(win.showLog)
    assert "a long log, line 900" in box.text and "debug log" in win.title.text
    g.slash("doctor")
    assert win.clear.shown is False, "nothing to clear in the doctor's report"
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(win.close)
    assert win.shown is False


def test_the_settings_have_buttons_for_the_log_and_the_errors(style):
    g = quick_game(style)
    labels = [g.eval(f"NS.settingRows[{i}].label") for i in range(1, int(g.eval("#NS.settingRows")) + 1)]
    assert "Show the debug log" in labels and "Show the errors" in labels
    row = next(i for i in range(1, len(labels) + 1) if labels[i - 1] == "Show the errors")
    g.eval(f"NS.settingRows[{row}].action")()
    win, box = g.eval("NS._reportWindow()")
    assert win.shown is True and "no errors recorded" in box.text


def test_slash_log_when_it_is_off_says_how_to_switch_it_on(style):
    g = quick_game(style)
    g.run("PRINTED = {}")
    g.slash("log")
    assert "the debug log is off" in "\n".join(g.printed())


def test_switching_it_off_writes_a_last_line_and_stops(style):
    g = on(style)
    g.slash("debug off")
    n = len(log(g))
    assert "debug = false (the log stops here)" in text(g)
    target(g, "Lia")
    pick(g, 5)
    assert len(log(g)) == n


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
