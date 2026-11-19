"""UX review 2026-11-19, batch B3 (party, chat and keys): the quest item, ping, party finder and quick chat keys say
what the key used to do in plain words (UX-03), and a refused key changes nothing (UX-47). The other B3 fixes are
tested in test_together.py (UX-06), test_menu.py (UX-22) and test_adventure.py (UX-45). Low findings: the Party
quests window close button (UX-48), Share/Stop (UX-55), the Invite slot hint (UX-56), plain words (UX-58, UX-62).
        python tests/test_ux_b3.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")


def plain(t):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def game(style):
    g = Game(style, "ITEMS[6000] = { name = 'Unlit Torch', spell = 'Light Torch', count = 1 }")
    g.start()
    g.slash("auto off")
    g.run("BAGS[0] = { { id = 6000 } }")
    g.fire("BAG_UPDATE_DELAYED")
    g.advance(1)
    g.run("PRINTED = {}")
    return g


def text(g):
    return plain("\n".join(g.printed()))


# (command or function, what the binding becomes, style it needs)
KEYS = {
    "item": (lambda g, k: g.slash("itemkey " + k), "CLICK QuestSharingItemButton:LeftButton"),
    "ping": (lambda g, k: g.slash("pingkey " + k), "CLICK QuestSharingPingButton:LeftButton"),
    "party finder": (lambda g, k: g.eval("NS.setLfgKey")(k), "QUESTSHARING_LFGSCAN"),
    "quick chat": (lambda g, k: g.slash("key " + k), "QUESTSHARING_QUICKCHAT"),
}


def kinds(style):
    # the classic client in these tests has no ping system
    return [k for k in KEYS if not (k == "ping" and style == "classic")]


# ---- UX-03: a key that did something says so, in plain words -----------------------------------------------------------
def test_taking_a_movement_key_says_what_it_used_to_do(style):
    for kind in kinds(style):
        g = game(style)
        setkey, action = KEYS[kind]
        g.run('BINDINGS.W = "MOVEFORWARD"')
        setkey(g, "W")
        assert g.eval("BINDINGS.W") == action, kind
        t = text(g)
        assert "W used to do: move forward" in t, (kind, t)
        assert "MOVEFORWARD" not in t, (kind, t)


def test_a_key_that_did_nothing_or_already_did_this_says_nothing_extra(style):
    for kind in kinds(style):
        g = game(style)
        setkey, action = KEYS[kind]
        setkey(g, "F7")
        assert "used to do" not in text(g), kind
        g.run("PRINTED = {}")
        setkey(g, "F7")                                   # the same key again
        assert "used to do" not in text(g), kind


def test_another_quest_sharing_key_is_named_plainly(style):
    g = game(style)
    g.slash("itemkey F8")
    g.run("PRINTED = {}")
    g.slash("key F8")
    assert "F8 used to do: the quest item key" in text(g), text(g)


# ---- UX-47: a refused key changes nothing ------------------------------------------------------------------------------
def test_a_protected_key_leaves_the_old_key_in_place(style):
    for kind in kinds(style):
        g = game(style)
        setkey, action = KEYS[kind]
        setkey(g, "F")
        assert g.eval("BINDINGS.F") == action, kind
        g.run('BINDINGS.ESCAPE = "TOGGLEGAMEMENU"; PRINTED = {}')
        setkey(g, "ESCAPE")
        assert "nothing was changed" in text(g), kind
        assert g.eval("BINDINGS.ESCAPE") == "TOGGLEGAMEMENU", kind
        assert g.eval("BINDINGS.F") == action, (kind, "the old key must still work")


# ---- UX-48: the Party quests window has a close button that says how to bring it back --------------------------------
def party_window(style):
    g = Game(style)
    g.start()
    g.slash("auto off")
    g.join_party(["Anna"])
    g.advance(3.5)
    g.slash("panel on")
    g.advance(1)
    g.run("PRINTED = {}")
    return g, g.eval("NS._panel()")[0]


def click(g, b):
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(b)


def test_the_party_quests_window_closes_and_says_how_to_reopen_it(style):
    g, panel = party_window(style)
    assert panel.close is not None and panel.shown is True
    click(g, panel.close)
    assert panel.shown is False and g.eval("NS.db.panel") is False
    t = text(g)
    assert "Party quests window hidden" in t and "/qs panel on" in t and "Settings > Party window" in t, t
    g.fire("GROUP_ROSTER_UPDATE")
    g.advance(2)
    assert panel.shown is False, "it stays closed"


# ---- UX-55: one sentence for "sharing in progress", and the Share button becomes Stop -----------------------------------
BUSY = "quests are being shared right now - try again in a few seconds"


def test_share_button_reads_stop_while_a_round_runs_and_stops_it(style):
    g, panel = party_window(style)
    g.run("QUESTS = { { header = 'Elwynn Forest' } }; for i = 1, 3 do QUESTS[#QUESTS + 1] = { id = 500 + i, title = 'Q' .. i, level = 5 } end")
    g.fire("QUEST_LOG_UPDATE")
    g.eval("NS.startShare")("manual")
    assert g.eval("NS.isSharing()") is True
    assert g.eval("NS.shareBusy()") is True
    assert panel.share.text == "Stop", panel.share.text
    g.run("PRINTED = {}")
    g.eval("NS.startShare")("manual")
    assert BUSY in text(g) and "already sharing" not in text(g), text(g)
    click(g, panel.share)
    assert g.eval("NS.isSharing()") is False and "sharing stopped (you clicked Stop)" in text(g), text(g)
    assert panel.share.text == "Share", panel.share.text


def test_both_busy_messages_are_the_same_sentence():
    src = (pathlib.Path(__file__).resolve().parent.parent / "QuestSharing" / "Share.lua").read_text()
    assert "already sharing (/qs stop to cancel)" not in src


# ---- UX-56: the Invite slot says "invite", and asks for a target first -------------------------------------------------
def ring(style):
    g = Game(style)
    g.start()
    g.slash("auto off")
    return g


def release_on_invite(g):
    g.cursor(500, 400)
    g.eval("QuestSharing_QuickDown")()
    g.advance(0.6)
    g.cursor(500 - 90, 400 + 90)                                # slot 8: Invite
    g.eval("QuestSharing_QuickUp")()
    return plain(g.wheel()[3].text)


def test_invite_slot_hint_says_invite(style):
    g = ring(style)
    g.run('TARGET = { name = "Lia", player = true }')
    hint = release_on_invite(g)
    assert hint == "click it (or press the key again) to invite", hint


def test_invite_slot_without_a_target_asks_for_one(style):
    g = ring(style)
    hint = release_on_invite(g)
    assert hint == "no target: target a player first", hint


# ---- UX-58: plain words in the party finder and invitation messages -----------------------------------------------------
def test_invitation_length_messages_say_letters(style):
    g = Game(style, fresh=True)
    g.start()
    prepare, e = g.eval("NS.adventure.prepare"), g.eval("NS.compat.findEntry")(100)
    ok, why = prepare(e, "x" * 300, "say")
    assert ok is False and why == "Your invitation must be 1–255 letters; shorten it before preparing chat.", why
    g.run('ACTIVE_BOX=EDITBOX; EDITBOX.text=string.rep("x",250)')
    ok, why = prepare(e, "Join me?", "current")
    assert ok is False and "exceeds 255 letters" in why and "bytes" not in why, why


def test_party_finder_log_says_item_level():
    src = (pathlib.Path(__file__).resolve().parent.parent / "QuestSharing" / "LFGInvite.lua").read_text()
    assert '", ilvl "' not in src and '", item level " .. tostring(level or "unknown")' in src


# ---- UX-62: one name for the Party quests window ----------------------------------------------------------------------
def test_panel_failure_message_names_the_party_quests_window():
    src = (pathlib.Path(__file__).resolve().parent.parent / "QuestSharing" / "Panel.lua").read_text()
    assert "this client cannot show the Party quests window" in src and "does not allow the panel" not in src


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
