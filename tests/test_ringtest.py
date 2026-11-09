"""The ring test (/qs quick test): every slot of every ring is run and checked against what the game really did -
emotes by the game's line ("You dance."), messages whispered to yourself by the game's "To you".
python tests/test_ringtest.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")

# like the game: a whisper you send is confirmed with CHAT_MSG_WHISPER_INFORM; REFUSE_WHISPER = the game refuses it
PRE = """
SENT_LOG = {}
local function send(msg, channel, lang, target)
    SENT_LOG[#SENT_LOG + 1] = tostring(channel) .. ":" .. tostring(target)
    if REFUSE_WHISPER then return FIRE("ADDON_ACTION_BLOCKED", "QuestSharing", "SendChatMessage()") end
    if channel == "WHISPER" then FIRE("CHAT_MSG_WHISPER_INFORM", msg, target) end
end
SendChatMessage = send
if C_ChatInfo then C_ChatInfo.SendChatMessage = send end
"""


def game(style, pre=""):
    g = Game(style, PRE + pre)
    g.start()
    g.slash("auto off")
    g.run("PRINTED = {}")
    return g


def report(g):
    return g.eval("NS._reportWindow()")[1].text


def run(g, arg="", seconds=200):
    g.slash("quick test " + arg)
    g.advance(seconds)
    return report(g)


def test_every_slot_is_run_and_checked_against_what_the_game_did(style):
    g = game(style)
    text = run(g)
    lines = text.split("\n")
    assert re.match(r"Quest Sharing \S+ - ring test: 31 of 31 worked$", lines[0]), lines[0]
    assert '[OK] Messages 1 "Hello" (on the ring: SAY): the game showed it (Hey there! o/)' in text, text
    assert '[  ] Messages 8 "Invite": skipped (an invite needs a player)' in text
    assert '[OK] Emotes 3 "Dance": the game did it (You dance.)' in text
    assert '[OK] Fun 5 "Hug": the game did it (You hug.)' in text
    assert set(g.eval("SENT_LOG").values()) == {"WHISPER:Me"}, "messages go to yourself only, nobody else"
    assert g.eval("NS.quickTestRunning()") is False


def test_an_emote_the_game_does_not_answer_and_a_refused_whisper_are_reported_not_switched_off(style):
    g = game(style, "EMOTE_SILENT = { DANCE = true }; REFUSE_WHISPER = true")
    text = run(g)
    assert '[--] Emotes 3 "Dance": no answer from the game' in text
    assert "[--] Messages 5 \"Thanks\" (on the ring: SAY): the game refused the addon's whisper" in text, text
    assert g.eval("NS.isBlocked('chat')") is False and g.eval("NS.db.chatRefused == nil or next(NS.db.chatRefused) == nil") is True, \
        "a test refusal changes nothing"
    assert re.search(r"ring test: 23 of 31 worked", text), text.split("\n")[0]


def test_a_channel_the_game_refused_before_is_named(style):
    g = game(style, "")
    g.run("NS.db.chatRefused = { SAY = true }")
    text = run(g, "messages")
    assert '"Hello" (on the ring: SAY, which this game refused: the chat box): the game showed it' in text, text


def test_fast_runs_the_emotes_back_to_back(style):
    g = game(style)
    g.slash("quick test fast")
    g.advance(2)
    assert g.eval("NS.quickTestRunning()") is True
    g.advance(30)
    text = report(g)
    assert text.startswith("Quest Sharing") and "ring test (fast): 24 of 24 worked" in text.split("\n")[0], text.split("\n")[0]
    assert "skipped (a message (only emotes tested))" in text


def test_stop_and_a_fight_end_it(style):
    g = game(style)
    g.slash("quick test")
    g.advance(4)
    g.slash("quick test stop")
    assert g.eval("NS.quickTestRunning()") is False and "stopped by you" in report(g)
    g.slash("quick test")
    g.advance(4)
    g.run("IN_COMBAT = true")
    g.advance(4)
    assert g.eval("NS.quickTestRunning()") is False and "stopped: a fight started" in report(g)


def test_the_log_window_has_a_button_for_it(style):
    g = game(style)
    g.slash("debug on")
    g.slash("log")
    win = g.eval("NS._reportWindow()")[0]
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(win.test)
    assert g.eval("NS.quickTestRunning()") is True


def test_your_own_chat_as_the_game_showed_it_goes_into_the_debug_log(style):
    g = game(style)
    g.slash("debug on")
    g.run('TARGET = { name = "Lia", player = true }')
    g.eval("NS.quickOpen")()
    g.eval("NS.quickClick")(5)                                     # Thanks -> a whisper to Lia
    g.fire("CHAT_MSG_PARTY", "on my way", "Me")
    L = g.eval("QuestSharingLog")
    log = "\n".join(L[i] for i in range(1, int(g.eval("#QuestSharingLog")) + 1))
    assert "game shows: you whispered Lia: Thanks!" in log and "game shows: you told the party: on my way" in log, log


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
