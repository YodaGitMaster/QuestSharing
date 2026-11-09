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


# ---- the ring sends at once by default; everything else goes into the chat box --------------------------------------
def test_a_new_install_sends_from_the_ring_at_once(style):
    g = fresh_party(style)
    assert g.eval("NS.db.mode") == "box" and g.eval("NS.db.quickSend") is True
    ring(g, 3)                                                       # "What I need": Auto -> the party
    assert g.opened() == [] and len(g.sent()) == 1, g.sent()
    msg, channel = g.sent()[0]
    assert channel == "PARTY" and msg.startswith("I need to: "), g.sent()


def test_with_sending_at_once_off_the_ring_writes_into_the_chat_box(style):
    g = fresh_party(style)
    g.run("PRINTED = {}")
    g.slash("quick send off")
    assert g.eval("NS.db.quickSend") is False and "goes into the chat box" in "\n".join(g.printed())
    ring(g, 3)
    assert g.sent() == [] and len(g.opened()) == 1 and g.opened()[0].startswith("/p I need to: ")
    g.advance(2)
    g.slash("quick send on")
    ring(g, 3)
    assert len(g.sent()) == 1, "back on: sent at once"


def test_say_and_whisper_also_go_into_the_chat_box_without_an_extra_click(style):
    g = fresh_party(style)
    g.slash("quick send off")
    ring(g, 1)                                                       # Hello: nearby, nobody targeted -> /s
    assert g.opened()[-1] == "/s Hey there! o/" and g.sent() == []
    g.advance(2)
    g.run('TARGET = { name = "Lia", player = true }')
    ring(g, 1)
    assert g.opened()[-1] == "/w Lia Hey Lia! o/"
    hint = g.eval("NS._quickWheel()")[3]
    assert "chat box" in hint.text or hint.text == ""


def test_a_refused_send_from_the_ring_goes_into_the_chat_box_and_switches_sending_at_once_off(style):
    g = fresh_party(style, pre=REFUSE_CHAT)
    g.run("PRINTED = {}")
    ring(g, 3)
    assert g.opened() and g.opened()[-1].startswith("/p I need to: "), "the refused message is in your chat box"
    assert g.eval("NS.db.quickSend") is False
    assert "does not let the addon send from the ring" in "\n".join(g.printed())
    g.advance(2)
    ring(g, 3)
    assert g.eval("SEND_TRIES") == 1 and len(g.opened()) == 2, "straight into the chat box now: no second try"


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


# A client that only lets an addon share from your own click: the push is refused unless HW (a click or key) is set
CLICK_ONLY = """PUSH_CALLS, PUSHED = 0, {}
function QuestLogPushQuest()
    PUSH_CALLS = PUSH_CALLS + 1
    if not HW then return FIRE("ADDON_ACTION_BLOCKED", "QuestSharing", "QuestLogPushQuest()") end
    PUSHED[#PUSHED + 1] = SELECTED or true
end"""


def click(g, what):
    g.run("HW = true")
    try:
        g.slash(what) if isinstance(what, str) else what()
    finally:
        g.run("HW = false")


def test_a_refused_automatic_share_switches_to_sharing_on_your_clicks(style):
    g = Game(style, CLICK_ONLY)
    g.start()
    g.run("PRINTED = {}")
    g.join_party(["Anna"])
    g.advance(40)
    assert g.eval("PUSH_CALLS") == 1 and len(g.eval("PUSHED")) == 0, "one try on a timer, refused"
    assert g.eval("NS.db.shareByClick") is True and g.eval("NS.isBlocked('share')") is False
    text = "\n".join(g.printed())
    assert "only lets the addon share a quest when you click" in text and "quest(s) to offer: click" in text
    assert "switched off until you reload" not in text
    assert not g.eval("NS.offered[100]"), "not marked as offered: it was refused"
    g.advance(60)
    assert g.eval("PUSH_CALLS") == 1, "it waits for your click, it does not try again by itself"
    click(g, "share")
    assert len(g.eval("PUSHED")) == 1, "your click shares the next quest at once"
    g.advance(30)
    assert len(g.eval("PUSHED")) == 1, "one quest per click"
    click(g, "share")
    assert len(g.eval("PUSHED")) == 2


def test_sharing_on_your_clicks_is_remembered_and_can_be_switched_off(style):
    g = Game(style, CLICK_ONLY)
    g.start()
    g.slash("shareclick on")
    g.join_party(["Anna"])
    g.advance(40)
    assert g.eval("PUSH_CALLS") == 0, "known already: no refused try at all"
    click(g, "share")
    assert len(g.eval("PUSHED")) == 1
    g.advance(200)
    assert g.eval("NS.isSharing()") is False, "nobody clicked for 2 minutes: the round ends"
    g.slash("shareclick off")
    assert g.eval("NS.db.shareByClick") is False


def test_clicking_a_quest_shares_it_while_a_round_waits_for_clicks(style):
    g = Game(style, CLICK_ONLY)
    g.start()
    g.join_party(["Anna"])
    g.advance(40)
    assert g.eval("NS.isSharing()") is True and len(g.eval("PUSHED")) == 0, "waiting for a click"
    g.run("PRINTED = {}")
    click(g, lambda: g.eval("NS.offerQuest")(g.eval("NS.compat.findEntry(100)")))
    assert len(g.eval("PUSHED")) == 1 and "offered" in "\n".join(g.printed())
    assert g.eval("NS.offered[100] ~= nil") is True


def test_something_else_refused_right_after_a_share_does_not_switch_sharing_off(style):
    """Found in the debug log: a share that went through, then another refusal within a second, was blamed on it."""
    g = Game(style, CLICK_ONLY)
    g.start()
    g.slash("shareclick on")
    g.join_party(["Anna"])
    g.advance(40)
    click(g, "share")
    assert len(g.eval("PUSHED")) == 1
    g.fire("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()")    # something else, a moment later
    assert g.eval("NS.isBlocked('share')") is False


def test_a_share_refused_even_from_your_click_switches_sharing_off(style):
    pre = """PUSH_CALLS = 0
    function QuestLogPushQuest() PUSH_CALLS = PUSH_CALLS + 1; FIRE("ADDON_ACTION_BLOCKED", "QuestSharing", "QuestLogPushQuest()") end"""
    g = Game(style, pre)
    g.start()
    g.join_party(["Anna"])
    g.advance(40)
    assert g.eval("PUSH_CALLS") == 1 and "while sharing a quest with the party" in g.eval("NS.db.errors[#NS.db.errors].msg")
    g.run("PRINTED = {}")
    g.slash("share")
    assert g.eval("PUSH_CALLS") == 2 and g.eval("NS.isBlocked('share')") is True
    assert "refuses sharing quests even when you click" in "\n".join(g.printed())
    g.run("PRINTED = {}")
    g.slash("share")
    assert g.eval("PUSH_CALLS") == 2 and "refused by the game earlier" in "\n".join(g.printed())


def test_when_two_things_happened_at_once_both_are_written_and_nothing_is_switched_off(style):
    g = Game(style)
    g.start()
    g.eval("NS.trying")("one thing", "waypoint")
    g.eval("NS.trying")("another thing", "pin")
    g.fire("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()")
    err = g.eval("NS.db.errors[#NS.db.errors].msg")
    assert "while one thing, then another thing" in err
    assert g.eval("NS.isBlocked('waypoint')") is False and g.eval("NS.isBlocked('pin')") is False


def test_a_block_long_after_our_calls_is_not_blamed_on_them(style):
    g = Game(style)
    g.start()
    g.eval("NS.trying")("putting a pin on your map", "waypoint")
    g.advance(5)
    g.fire("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()")
    assert "while" not in g.eval("NS.db.errors[#NS.db.errors].msg") and g.eval("NS.isBlocked('waypoint')") is False


# ---- what made the refused call: the line, what was running, the stack ------------------------------------------------
def last_error(g):
    e = g.eval("NS.db.errors[#NS.db.errors]")
    return e.msg, "\n".join(e.detail.values()) if e.detail else ""


def test_a_refused_call_names_the_line_that_made_it_and_what_was_running(style):
    pre = """function QuestLogPushQuest() FIRE("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()") end"""
    g = Game(style, pre)
    g.start()
    g.join_party(["Anna"])
    g.advance(40)
    msg, detail = last_error(g)
    assert re.search(r"UNKNOWN\(\) from Compat\.lua:\d+ push \(while sharing a quest with the party\)", msg), msg
    assert re.search(r"running: a timer set at Share\.lua:\d+", detail), detail
    assert "in combat: no" in detail and "stack (newest call first):" in detail
    assert re.search(r"  Compat\.lua:\d+: in function 'push'\n  Share\.lua:\d+: in function 'pushOne'", detail), detail


def test_the_game_s_own_stack_lines_are_made_readable_and_name_the_function(style):
    """The game's lines: '[string "@Interface/AddOns/..."]:35: in function `x'' or 'Interface/AddOns/...:35: in ...'."""
    older = '[string "=[C]"]:-1: in function `SendChatMessage\'\n[string "@Interface/AddOns/QuestSharing/Core.lua"]:198: in function `say\'\n'
    g0 = Game(style)
    g0.start()
    g0.run("function debugstack() return [==[" + older + "]==] end")
    g0.fire("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()")
    assert last_error(g0)[0] == "tried to call the protected function SendChatMessage() from Core.lua:198 say", last_error(g0)
    stack = ("[C]: in function `SetRaidTarget'\n"
             '[string "@Interface/AddOns/QuestSharing/Marker.lua"]:35: in function `syncSelfMark\'\n'
             "Interface/AddOns/QuestSharing/Core.lua:104: in function <Interface/AddOns/QuestSharing/Core.lua:96>\n"
             '[string "@Interface/AddOns/Blizzard_ObjectiveTracker/Tracker.lua"]:10: in function <...>\n')
    g = Game(style)
    g.start()
    g.run("function debugstack() return [==[" + stack + "]==] end")
    g.fire("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()")
    msg, detail = last_error(g)
    assert msg == "tried to call the protected function SetRaidTarget() from Marker.lua:35 syncSelfMark", msg
    for want in ("  [C]: in function `SetRaidTarget'", "  Marker.lua:35: in function `syncSelfMark'",
                 "  Core.lua:104: in function <Core.lua:96>", "  Blizzard_ObjectiveTracker/Tracker.lua:10: in function"):
        assert want in detail, (want, detail)


def test_a_refusal_with_none_of_our_code_on_the_stack_says_so(style):
    g = Game(style)
    g.start()
    g.advance(3)
    g.run("IN_COMBAT = true")
    g.fire("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()")
    msg, detail = last_error(g)
    assert msg == "tried to call the protected function UNKNOWN()", msg
    assert "running: no timer or event of the addon" in detail and re.search(r"the addon last ran a timer set at \w+\.lua:\d+", detail)
    assert "in combat: yes" in detail and "no Quest Sharing line on the stack" in detail


def test_other_addons_refusals_are_not_ours(style):
    g = Game(style)
    g.start()
    g.fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "UNKNOWN()")
    assert g.eval("NS.db.errors == nil or #NS.db.errors == 0") is True and g.eval("NS.blockedStack") is None


def test_lua_errors_in_timers_and_events_keep_their_stack(style):
    g = Game(style)
    g.start()
    g.run("NS.after(0, function() local t = nil; return t.x end)")
    g.advance(0.5)
    msg, detail = last_error(g)
    assert "attempt to index" in msg and "stack (newest call first):" in detail and re.search(r"Core\.lua:\d+", detail), detail
    g.run('NS.on("QS_TEST_EVENT", function() error("boom in an event") end)')
    g.fire("QS_TEST_EVENT")
    msg, detail = last_error(g)
    assert "boom in an event" in msg and "stack (newest call first):" in detail


def test_the_errors_window_has_the_details_and_the_chat_stays_short(style):
    pre = """function QuestLogPushQuest() FIRE("ADDON_ACTION_BLOCKED", "QuestSharing", "UNKNOWN()") end"""
    g = Game(style, pre)
    g.start()
    g.join_party(["Anna"])
    g.advance(40)
    g.run("PRINTED = {}")
    g.slash("errors")
    chat = "\n".join(g.printed())
    assert "from Compat.lua:" in chat and "stack (newest call first)" not in chat and "the window has the details" in chat
    text = g.eval("NS._reportWindow()")[1].text
    assert text.startswith("Quest Sharing ") and "running: a timer set at Share.lua:" in text and "  Compat.lua:" in text


# ---- calls the addon must never make (the game refuses them, or makes Blizzard code do it in our name) ----------------
NEVER = ["SetPassThroughButtons", "SetPropagateMouseClicks", "SetPropagateMouseMotion", "QuestMapFrame_OpenToQuestDetails",
         "ToggleWorldMap", "OpenWorldMap", "AddDataProvider", "AcquirePin",
         "SetRaidTarget"]                                       # raid marks: refused even outside combat
NEVER_TEXT = ["WorldMapFrame:Show", "ShowUIPanel(WorldMapFrame", "ShowUIPanel, WorldMapFrame"]


def test_the_addon_never_calls_what_makes_the_game_refuse_it():
    """Not even through pcall(name, ...): the bare name may not appear in the code (comments aside)."""
    root = pathlib.Path(__file__).resolve().parent.parent / "QuestSharing"
    found = []
    for f in sorted(root.glob("*.lua")):
        for n, line in enumerate(f.read_text().splitlines(), 1):
            code = line.split("--", 1)[0]                       # comments may name them
            for bad in NEVER:
                if re.search(r"\b" + bad + r"\b", code):
                    found.append(f"{f.name}:{n}: {bad}")
            for bad in NEVER_TEXT:
                if bad in code:
                    found.append(f"{f.name}:{n}: {bad}")
    assert found == [], found


def test_every_file_compiles_under_lua_5_1():
    """The game runs Lua 5.1: no goto, no broken strings - every file must load."""
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime()
    check = lua.eval("function(s, n) local f, err = loadstring(s, n); return err end")
    root = pathlib.Path(__file__).resolve().parent.parent / "QuestSharing"
    errors = [check(f.read_text(), f.name) for f in sorted(root.glob("*.lua"))]
    assert [e for e in errors if e] == []


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
