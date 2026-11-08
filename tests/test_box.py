"""Messages go into the chat box (you press Enter), because some game clients do not let addons send chat messages;
and calls the game refuses are written down and switched off.        python tests/test_box.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")
REFUSE_CHAT = """
SEND_TRIES = 0
local function refuse() SEND_TRIES = SEND_TRIES + 1; FIRE("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()") end
SendChatMessage = refuse
if C_ChatInfo then C_ChatInfo.SendChatMessage = refuse end
"""


def plain(t):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def fresh_party(style, names=("Anna",), on_quest=None, pre=""):
    """A new install (default settings) in a party."""
    g = Game(style, pre, fresh=True)
    g.fire("ADDON_LOADED", "QuestSharing")
    g.fire("PLAYER_ENTERING_WORLD")
    g.slash("auto off")
    for unit, ids in (on_quest or {}).items():
        g.run(f'ON_QUEST["{unit}"] = {{{", ".join("[%d] = true" % i for i in ids)}}}')
    g.join_party(list(names))
    g.advance(8)
    g.run("SENT = {}; OPENED = {}; PRINTED = {}")
    return g


def ring(g, slot):
    """Hold the key, point at a slot, release; click it if the ring stays open."""
    g.eval("NS.quickOpen")()
    g.advance(0.6)
    import math
    n = len(g.eval("NS.quickItems()"))
    a = (slot - 1) * 2 * math.pi / n
    g.run(f"CURSOR.x, CURSOR.y = CURSOR.x + 118 * math.sin({a}), CURSOR.y + 118 * math.cos({a})")
    g.eval("NS.quickUpdateHover")()
    g.eval("QuestSharing_QuickUp")()
    frame, slots = g.eval("NS._quickWheel()")[0], g.eval("NS._quickWheel()")[1]
    if frame.shown:
        g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(slots[slot].button)
    g.run("CURSOR.x, CURSOR.y = 960, 540")


# ---- the chat box by default ---------------------------------------------------------------------------------------
def test_a_new_install_writes_into_the_chat_box(style):
    g = fresh_party(style)
    assert g.eval("NS.db.mode") == "box"
    ring(g, 3)                                                       # "What I need": Auto -> the party
    assert g.sent() == [] and len(g.opened()) == 1 and g.opened()[0].startswith("/p I need to: ")


def test_say_and_whisper_also_go_into_the_chat_box_without_an_extra_click(style):
    g = fresh_party(style)
    ring(g, 1)                                                       # Hello: nearby, nobody targeted -> /s
    assert g.opened()[-1] == "/s Hey there! o/" and g.sent() == []
    g.advance(2)
    g.run('TARGET = { name = "Lia", player = true }')
    ring(g, 1)
    assert g.opened()[-1] == "/w Lia Hey Lia! o/"
    hint = g.eval("NS._quickWheel()")[3]
    assert "chat box" in hint.text or hint.text == ""


def test_the_menus_messages_go_into_the_chat_box_too(style):
    g = fresh_party(style)
    g.slash("panel on")
    g.advance(1)
    rows = g.eval("NS._panel()")[1]
    row = next(rows[i] for i in range(1, 6) if rows[i].shown and "Wolves Among Us" in rows[i].title.text)
    g.eval("function(r) r.scripts.OnClick(r, 'RightButton') end")(row)
    menu, lines = g.eval("NS._questMenu()")
    b = next(lines[i] for i in range(1, 7) if lines[i].shown and "Tell the party how I am doing" in plain(lines[i].text))
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(b)
    assert g.sent() == [] and g.opened()[-1].startswith("/p ") and "I still need" in g.opened()[-1]


def test_automatic_messages_never_type_into_your_chat_box(style):
    g = fresh_party(style, on_quest={"party1": [100]})
    g.slash("chat on")
    g.slash("auto on")
    g.join_party(["Anna", "Bob"])
    g.advance(40)
    assert g.sent() == [] and g.opened() == [], "that would take your keys while you play"


# ---- the game refuses direct sends: from then on, the chat box ------------------------------------------------------
def test_a_refused_send_switches_to_the_chat_box_and_says_so_once(style):
    g = fresh_party(style, pre=REFUSE_CHAT)
    g.slash("mode send")
    ring(g, 3)
    assert g.eval("SEND_TRIES") == 1
    assert g.eval("NS.db.mode") == "box" and "press Enter" in "\n".join(g.printed())
    assert g.opened(), "the refused message itself lands in the chat box"
    g.advance(2)
    g.run("OPENED = {}")
    ring(g, 3)
    assert g.eval("SEND_TRIES") == 1 and g.opened() and g.opened()[-1].startswith("/p "), "no second try"
    assert "while sending from the quick chat ring" in g.eval("NS.db.errors[#NS.db.errors].msg")


def test_a_refused_send_from_the_menu_also_switches_to_the_chat_box(style):
    g = fresh_party(style, pre=REFUSE_CHAT)
    g.slash("mode send")
    entry = g.eval("NS.compat.findEntry")(100)
    g.eval("NS.askParty")(entry)
    assert g.eval("SEND_TRIES") == 1 and g.eval("NS.db.mode") == "box"
    assert "while sending your status to the party" in g.eval("NS.db.errors[#NS.db.errors].msg")
    g.advance(2)
    g.eval("NS.askParty")(entry)
    assert g.eval("SEND_TRIES") == 1 and g.opened() and g.opened()[-1].startswith("/p "), "now into the chat box"


# ---- the star -----------------------------------------------------------------------------------------------------------------
def test_the_star_waits_for_the_end_of_combat(style):
    g = Game(style)
    g.start()
    g.run("IN_COMBAT = true")
    g.join_party(["Anna"])
    g.advance(3)
    assert g.eval("RAID_ICONS.player") is None, "never during a fight"
    g.run("IN_COMBAT = false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(2)
    assert g.eval("RAID_ICONS.player") == 1


def test_a_refused_star_is_written_down_and_not_tried_again(style):
    pre = """RAID_CALLS = 0
    function SetRaidTarget(u, i) RAID_CALLS = RAID_CALLS + 1; FIRE("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()") end"""
    g = Game(style, pre)
    g.start()
    g.join_party(["Anna"])
    g.advance(3)
    assert g.eval("RAID_CALLS") == 1
    err = g.eval("NS.db.errors[#NS.db.errors].msg")
    assert "UNKNOWN()" in err and "while putting the star over your head" in err, err
    assert "switched off until you reload" in "\n".join(g.printed())
    g.leave_party()
    g.advance(3)
    g.join_party(["Anna", "Bob"])
    g.advance(5)
    assert g.eval("RAID_CALLS") == 1, "no second try, no second error"


def test_a_refused_quest_share_stops_sharing_until_reload(style):
    pre = """PUSH_CALLS = 0
    function QuestLogPushQuest() PUSH_CALLS = PUSH_CALLS + 1; FIRE("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()") end"""
    g = Game(style, pre)
    g.start()
    g.join_party(["Anna"])
    g.advance(40)
    assert g.eval("PUSH_CALLS") == 1 and "while sharing a quest with the party" in g.eval("NS.db.errors[#NS.db.errors].msg")
    g.run("PRINTED = {}")
    g.slash("share")
    assert g.eval("PUSH_CALLS") == 1 and "refused by the game earlier" in "\n".join(g.printed())


def test_when_two_things_happened_at_once_both_are_written_and_nothing_is_switched_off(style):
    g = Game(style)
    g.start()
    g.eval("NS.trying")("one thing", "star")
    g.eval("NS.trying")("another thing", "pin")
    g.fire("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()")
    err = g.eval("NS.db.errors[#NS.db.errors].msg")
    assert "while one thing, then another thing" in err
    assert g.eval("NS.isBlocked('star')") is False and g.eval("NS.isBlocked('pin')") is False


def test_a_block_long_after_our_calls_is_not_blamed_on_them(style):
    g = Game(style)
    g.start()
    g.eval("NS.trying")("putting the star over your head", "star")
    g.advance(5)
    g.fire("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()")
    assert "while" not in g.eval("NS.db.errors[#NS.db.errors].msg") and g.eval("NS.isBlocked('star')") is False


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
