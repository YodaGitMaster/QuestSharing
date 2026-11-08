"""The emote rings: while the quick chat ring is open the mouse wheel flips to rings with the game's emotes (thank, bow,
dance, point, no, train...).        python tests/test_emotes.py"""
import math
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")


def plain(t):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def game(style, pre=""):
    g = Game(style, pre)
    g.start()
    g.slash("auto off")
    return g


def ring(g):
    return g.eval("NS._quickWheel()")


def wheel(g, delta):
    frame = ring(g)[0]
    g.eval("function(f, d) f.scripts.OnMouseWheel(f, d) end")(frame, delta)


def labels(g):
    slots = ring(g)[1]
    return [plain(slots[i].label.text) for i in range(1, 9) if slots[i].button.shown]


def point_and_release(g, slot):
    n = len(g.eval("NS.quickRingItems()"))
    a = (slot - 1) * 2 * math.pi / n
    g.run(f"CURSOR.x, CURSOR.y = 960 + 118 * math.sin({a}), 540 + 118 * math.cos({a})")
    g.eval("NS.quickUpdateHover")()
    g.eval("QuestSharing_QuickUp")()
    g.run("CURSOR.x, CURSOR.y = 960, 540")


def open_ring(g):
    g.run("CURSOR.x, CURSOR.y = 960, 540")
    g.eval("QuestSharing_QuickDown")()
    g.advance(0.6)


def test_the_mouse_wheel_flips_to_the_emote_rings_and_around(style):
    g = game(style)
    open_ring(g)
    assert labels(g)[0] == "Hello" and "Messages" in ring(g)[0].pageText.text
    wheel(g, -1)
    assert labels(g) == ["Thank", "Bow", "Dance", "Wave", "Cheer", "Point", "No", "Wait"]
    assert plain(ring(g)[0].pageText.text).startswith("Emotes  (2/4")
    wheel(g, -1)
    assert "Attack!" in labels(g) and "Heal me" in labels(g), "group calls"
    wheel(g, -1)
    assert "Train" in labels(g) and "Laugh" in labels(g), "fun"
    wheel(g, -1)
    assert labels(g)[0] == "Hello", "and around to your messages"
    wheel(g, 1)
    assert "Train" in labels(g), "the other way too"


def test_an_emote_is_done_on_release_without_any_chat(style):
    g = game(style)
    open_ring(g)
    wheel(g, -1)
    point_and_release(g, 2)                                       # Bow
    assert list(g.eval("EMOTED").values()) == ["BOW"]
    assert g.sent() == [] and g.opened() == [] and ring(g)[0].shown is False


def test_the_middle_says_which_emote(style):
    g = game(style)
    open_ring(g)
    wheel(g, -1)
    n = 8
    a = (3 - 1) * 2 * math.pi / n
    g.run(f"CURSOR.x, CURSOR.y = 960 + 118 * math.sin({a}), 540 + 118 * math.cos({a})")
    g.eval("NS.quickUpdateHover")()
    text = plain(ring(g)[2].text)
    assert "Dance  (/dance)" in text and "an emote everybody around sees" in text, text


def test_the_ring_you_used_last_opens_first(style):
    g = game(style)
    open_ring(g)
    wheel(g, -1)
    wheel(g, -1)
    g.eval("NS.quickClose")()
    open_ring(g)
    assert "Attack!" in labels(g) and g.eval("NS.db.quickPage") == 3


def test_if_the_game_refuses_emotes_they_go_into_the_chat_box(style):
    pre = """EMOTE_TRIES = 0
    function DoEmote(t) EMOTE_TRIES = EMOTE_TRIES + 1; FIRE("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()") end"""
    g = game(style, pre)
    open_ring(g)
    wheel(g, -1)
    point_and_release(g, 2)
    assert g.eval("EMOTE_TRIES") == 1 and g.opened()[-1] == "/bow", "the refused one is ready to send with Enter"
    assert "press Enter" in "\n".join(g.printed())
    g.advance(2)
    open_ring(g)
    point_and_release(g, 3)
    assert g.eval("EMOTE_TRIES") == 1 and g.opened()[-1] == "/dance", "no second try: straight into the chat box"


def test_emote_dots_are_orange(style):
    g = game(style)
    open_ring(g)
    wheel(g, -1)
    node = ring(g)[1][1].node
    v = node.vertex
    assert (round(v[1], 2), round(v[2], 2), round(v[3], 2)) == (0.8, 0.4, 0.2)


def test_your_messages_ring_and_its_editor_are_unchanged(style):
    g = game(style)
    open_ring(g)
    wheel(g, -1)
    g.eval("NS.quickClose")()
    assert len(g.eval("NS.quickItems()")) == 8 and g.eval("NS.quickItems()[1].label") == "Hello"


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
