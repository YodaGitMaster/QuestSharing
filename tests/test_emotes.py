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


# ---- editing the emote rings -----------------------------------------------------------------------------------------------
def editor(g, ring=1):
    g.slash("settings")
    g.eval("NS.settingsTab")("quick")
    g.eval("NS.editorPage")(ring)
    return g.eval("NS._settingsWindow().ed")


def test_the_editor_has_a_ring_picker(style):
    g = game(style)
    ed = editor(g, 2)
    names = [plain(ed.pageButtons[i].text.text).strip("[] ") for i in range(1, 5)]
    assert names == ["Messages", "Emotes", "Group calls", "Fun"]
    assert ed.pageButtons[2].text.text.startswith("|cffffd100["), "the ring being edited is gold"
    assert "[Thank]" in ed.lines[1].text.text and "[Wait]" in ed.lines[8].text.text


def test_change_an_emote_slot_by_typing_slash_and_its_name(style):
    g = game(style)
    ed = editor(g, 2)
    g.eval("NS.editorSelect")(1)
    assert ed.channelCaption.shown is False, "emotes have no chat channel"
    assert "an emote" in plain(ed.preview.text)
    g.eval("NS.editorSave")("Salute", "/salute")
    item = g.eval("NS.quickListFor(2)[1]")
    assert (item.label, item.text) == ("Salute", "@emote SALUTE")
    g.eval("NS.editorShowRing")()
    assert labels(g)[0] == "Salute", "Show the ring opens the ring you are editing"
    g.eval("NS.quickClose")()
    open_ring(g)
    point_and_release(g, 1)
    assert list(g.eval("EMOTED").values())[-1] == "SALUTE"


def test_add_remove_and_reset_one_ring_only(style):
    g = game(style)
    g.slash("quick label 1 Hi")                                 # your messages: changed too
    ed = editor(g, 4)
    g.run("PRINTED = {}")
    g.eval("NS.editorAdd")()
    assert "holds 8" in "\n".join(g.printed()), "a ring holds 8"
    g.eval("NS.editorSelect")(8)
    g.eval("NS.editorDelete")()
    g.eval("NS.editorAdd")()
    g.eval("NS.editorSave")("", "/train")
    last = g.eval("NS.quickListFor(4)[8]")
    assert last.text == "@emote TRAIN"
    g.eval("NS.editorReset")()
    assert g.eval("NS.quickListFor(4)[8].label") == "Roar", "the Fun ring is back to its default"
    assert g.eval("NS.quickItems()[1].label") == "Hi", "your messages were not touched"


def test_only_a_real_emote_becomes_an_emote(style):
    g = game(style)
    editor(g, 2)
    g.eval("NS.editorSelect")(1)
    g.eval("NS.editorSave")("", "/dance now")
    assert g.eval("NS.quickListFor(2)[1].text") == "/dance now", "a sentence stays a sentence"
    g.eval("NS.editorSave")("", "/foobar")
    assert g.eval("NS.quickListFor(2)[1].text") == "/foobar", "an unknown word is not an emote"


def test_edited_rings_are_kept_and_reset_everything_puts_them_back(style):
    g = game(style)
    editor(g, 3)
    g.eval("NS.editorSelect")(2)
    g.eval("NS.editorSave")("Run!", "/flee")
    assert g.eval("QuestSharingDB.quickPages[2].items[2].label") == "Run!", "saved with your settings"
    g.slash("reset")
    assert g.eval("NS.quickListFor(3)[2].label") == "Charge"



def test_different_emotes_can_follow_each_other_right_away_but_the_same_one_is_not_done_twice(style):
    """Reported: Hug then Salute quickly - the Salute did nothing (one second between ANY two picks)."""
    g = game(style)
    g.eval("NS.quickOpen")()
    fun = next(i for i in range(1, 9) if g.eval("NS.quickPageList()")[i] and g.eval("NS.quickPageList()")[i].title == "Fun")
    g.run("NS.db.quickPage = %d" % fun)
    g.eval("NS.quickClose")()
    def emote(slot):
        g.eval("NS.quickOpen")()
        g.eval("NS.quickClick")(slot)
    emote(5)                                                        # Hug
    emote(4)                                                        # Salute, right after
    emote(4)                                                        # Salute again by accident: not twice
    assert list(g.eval("EMOTED").values()) == ["HUG", "SALUTE"], list(g.eval("EMOTED").values())
    g.advance(1.2)
    emote(4)
    assert list(g.eval("EMOTED").values())[-1] == "SALUTE" and len(g.eval("EMOTED")) == 3


def fun_ring(g):
    pages = g.eval("NS.quickPageList()")
    fun = next(i for i in range(1, 9) if pages[i] and pages[i].title == "Fun")
    g.run("NS.db.quickPage = %d" % fun)


def ring_labels(g):
    g.eval("NS.quickOpen")()
    labels = [it.label for it in g.eval("NS.quickRingItems()").values()]
    g.eval("NS.quickClose")()
    return labels


def test_emotes_this_game_does_not_have_are_left_off_the_ring(style):
    """Reported: some ring items do nothing - an emote the game does not have is not offered at all."""
    g = game(style)
    fun_ring(g)
    g.run("""local i = 0
    for t in string.gmatch("AGREE AMAZE ANGRY APPLAUD BOW CHEER CHICKEN DANCE FLEX LAUGH ROAR SALUTE TRAIN WAVE", "%u+") do
        i = i + 1; _G["EMOTE" .. i .. "_TOKEN"] = t
    end
    for j = 1, 120 do _G["EMOTE" .. (100 + j) .. "_TOKEN"] = "FILLER" .. j end     -- a real list is long
    NS.quickResetEmoteList()""")
    labels = ring_labels(g)
    assert "Hug" not in labels and "Salute" in labels and len(labels) == 7, labels


def test_without_the_game_s_list_nothing_is_left_out(style):
    g = game(style)
    fun_ring(g)
    assert len(ring_labels(g)) == 8


def log_text(g):
    L = g.eval("QuestSharingLog")
    return "\n".join(L[i] for i in range(1, int(g.eval("#QuestSharingLog")) + 1))


def test_an_emote_the_game_does_not_answer_is_said_and_stays_on_the_ring(style):
    """Reported: some emotes work sometimes, not always - the game may hold back quick ones, so none is taken away."""
    g = game(style)
    fun_ring(g)
    g.slash("debug on")
    g.run('EMOTE_SILENT.HUG = true')
    def hug():
        g.eval("NS.quickOpen")()
        slot = next(i for i, it in enumerate(g.eval("NS.quickRingItems()").values(), 1) if it.label == "Hug")
        g.eval("NS.quickClick")(slot)
        g.advance(2.5)
    g.run("PRINTED = {}")
    g.eval("NS.quickOpen")()
    g.eval("NS.quickClick")(4)                                     # Salute first
    g.advance(1.2)
    hug()
    assert "the game did not show /hug (1.2 s after the emote before)" in "\n".join(g.printed()), g.printed()
    assert "emote: /hug: no answer from the game (1.2 s after the emote before)" in log_text(g), log_text(g)
    hug()
    hug()
    assert "Hug" in ring_labels(g), "still on the ring: it may work a moment later"
    assert sum("the game did not show" in l for l in g.printed()) == 1, "said at most every 10 seconds"


def test_an_emote_the_game_answers_is_written_down_as_done(style):
    g = game(style)
    fun_ring(g)
    g.slash("debug on")
    g.eval("NS.quickOpen")()
    g.eval("NS.quickClick")(4)                                     # Salute
    g.advance(2.5)
    assert "emote: /salute: the game did it (You salute.)" in log_text(g), log_text(g)

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
