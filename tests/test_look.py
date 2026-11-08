"""The beautification round: the settings window's layout, setting the key by pressing it, the welcome, the good-news
sound, and the quick chat ring's colours, destination line and size.        python tests/test_look.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")


def plain(t):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def game(style, fresh=False):
    g = Game(style, fresh=fresh)
    if fresh:
        g.fire("ADDON_LOADED", "QuestSharing")
        g.fire("PLAYER_ENTERING_WORLD")
    else:
        g.start()
        g.slash("auto off")
    return g


def window(g, tab="general"):
    g.slash("settings")
    g.eval("NS.settingsTab")(tab)
    return g.eval("NS._settingsWindow()")


def rows(W):
    return [W.rows[n] for n in range(1, 19) if W.rows[n].frame.shown]


def row(W, label):
    return next(r for r in rows(W) if label in plain(r.text.text))


def printed(g):
    return "\n".join(g.printed())


# ---- the settings window ---------------------------------------------------------------------------------------------
def test_every_tab_has_a_short_intro_and_sections(style):
    g = game(style)
    W = window(g)
    for t in ("general", "sharing", "party", "tracker", "quick", "social"):
        g.eval("NS.settingsTab")(t)
        assert len(plain(W.intro.text)) > 20, t
    g.eval("NS.settingsTab")("sharing")
    headers = [plain(r.text.text) for r in rows(W) if r.line.shown]
    assert headers == ["When I join a party", "Party chat", "Behind the scenes"]
    g.eval("NS.settingsTab")("party")
    assert [plain(r.text.text) for r in rows(W) if r.line.shown] == ["The Party quests window", "Clicking a quest"]


def test_rows_are_laid_out_top_to_bottom_without_overlapping_and_fit_in_the_window(style):
    g = game(style)
    W = window(g)
    for t in ("general", "sharing", "party", "tracker", "quick", "social"):
        g.eval("NS.settingsTab")(t)
        tops = [-r.frame.point[5] for r in rows(W)]
        heights = [r.frame.height for r in rows(W)]
        for (a, h), b in zip(zip(tops, heights), tops[1:]):
            assert b >= a + h, (t, a, h, b)
        bottom = W.bottom + (300 + 10 if t == "quick" else 0)
        assert bottom <= W.win.height - 30, (t, bottom)


def test_a_check_box_shows_the_setting_and_a_description_says_what_it_does(style):
    g = game(style)
    W = window(g)
    r = row(W, "Minimap button")
    assert r.box.shown and r.tick.shown and "Drag it around the map" in r.desc.text
    g.slash("minimap off")
    assert r.box.shown and r.tick.shown is False


def test_with_the_master_switch_off_the_other_lines_are_greyed(style):
    g = game(style)
    W = window(g)
    g.slash("off")
    assert row(W, "Minimap button").text.text.startswith("|cff9d9d9d")
    assert not row(W, "Quest Sharing enabled").text.text.startswith("|cff9d9d9d")


def test_choices_and_numbers_show_their_value_on_the_right(style):
    g = game(style)
    W = window(g, "sharing")
    assert plain(row(W, "Which quests to share").value.text) == "< this zone only >"
    assert plain(row(W, "Seconds between shared quests").value.text) == "-  4  +"


def test_the_size_setting_moves_in_steps_of_ten(style):
    g = game(style)
    idx = g.eval("(function() for i, r in ipairs(NS.settingRows) do if r.key == 'panelScale' then return i end end end)()")
    g.eval("NS.settingsClick")(idx, "LeftButton")
    assert g.eval("NS.db.panelScale") == 110
    g.run("SHIFT = true")
    g.eval("NS.settingsClick")(idx, "LeftButton")
    assert g.eval("NS.db.panelScale") == 150, "shift: 50 at a time, never above 150"


def test_action_lines_have_a_button(style):
    g = game(style)
    W = window(g)
    check = row(W, "Check my setup")
    assert check.button.shown and check.button.text == "Check"
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(check.button)
    assert g.eval("NS._reportWindow()")[0].shown is True, "the setup report opened"
    ring = row(W, "Show the ring")
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(ring.button)
    assert g.wheel()[0].shown is True


def test_the_close_button_closes_the_window(style):
    g = game(style)
    W = window(g)
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(W.close)
    assert W.win.shown is False


# ---- setting the quick chat key by pressing it -------------------------------------------------------------------------
def capture_and_press(g, W, key):
    r = row(W, "Quick chat key")
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(r.button)
    assert "press a key" in r.button.text
    g.eval("NS.captureKeyPressed")(key)
    return r


def test_click_then_press_a_key_binds_it(style):
    g = game(style)
    W = window(g)
    r = row(W, "Quick chat key")
    assert "not set" in r.button.text
    capture_and_press(g, W, "E")
    assert g.eval("BINDINGS.E") == "QUESTSHARING_QUICKCHAT" and r.button.text == "E"
    assert g.eval("NS._settingsWindow().capturing") is False


def test_modifiers_wait_for_the_real_key_and_are_part_of_it(style):
    g = game(style)
    W = window(g)
    r = row(W, "Quick chat key")
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(r.button)
    g.eval("NS.captureKeyPressed")("LALT")                     # only the modifier so far: still waiting
    assert g.eval("NS._settingsWindow().capturing") is True
    g.run("ALT = true")
    g.eval("NS.captureKeyPressed")("Q")
    g.run("ALT = false")
    assert g.eval("BINDINGS['ALT-Q']") == "QUESTSHARING_QUICKCHAT"


def test_escape_cancels_and_changes_nothing(style):
    g = game(style)
    W = window(g)
    capture_and_press(g, W, "ESCAPE")
    assert g.eval("BINDINGS.ESCAPE") is None and g.eval("NS._settingsWindow().capturing") is False


def test_no_key_changes_in_combat_and_closing_the_window_stops_listening(style):
    g = game(style)
    W = window(g)
    g.run("IN_COMBAT = true")
    r = row(W, "Quick chat key")
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(r.button)
    assert "cannot be changed in combat" in printed(g) and g.eval("NS._settingsWindow().capturing") is False
    g.run("IN_COMBAT = false")
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(r.button)
    g.slash("settings")                                         # the window closes
    g.eval("function(f) f.scripts.OnHide(f) end")(W.win)
    assert g.eval("NS._settingsWindow().capturing") is False, "the keyboard is never left captured"


def test_the_quick_chat_tab_has_the_key_too(style):
    g = game(style)
    W = window(g, "quick")
    r = row(W, "Key that opens the ring")
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(r.button)
    g.eval("NS.captureKeyPressed")("V")
    assert g.eval("BINDINGS.V") == "QUESTSHARING_QUICKCHAT" and r.button.text == "V"


# ---- welcome ------------------------------------------------------------------------------------------------------------
def test_a_new_install_is_welcomed_once(style):
    g = game(style, fresh=True)
    g.advance(6)
    text = printed(g)
    assert "Welcome to Quest Sharing 0.2.0!" in text and "Quick chat key" in text
    g.run("PRINTED = {}")
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(10)
    assert "Welcome" not in printed(g)
    g2 = Game(style)                                           # the next login: the saved settings remember it
    g2.run("QuestSharingDB = { welcomed = '0.2.0', dbVersion = 2 }")
    g2.fire("ADDON_LOADED", "QuestSharing")
    g2.fire("PLAYER_ENTERING_WORLD")
    g2.advance(10)
    later = "\n".join(g2.printed())
    assert "Welcome" not in later and "updated to" not in later, "said once, never again"


def test_the_welcome_names_the_key_once_it_is_set(style):
    g = Game(style, fresh=True)
    g.run('BINDINGS.E = "QUESTSHARING_QUICKCHAT"')
    g.fire("ADDON_LOADED", "QuestSharing")
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(6)
    assert "Hold |cffffd100E|r for the quick chat ring" in printed(g)


def test_an_update_says_what_is_new(style):
    g = Game(style)
    g.run("QuestSharingDB = { welcomed = '0.1.0', dbVersion = 2 }")
    g.fire("ADDON_LOADED", "QuestSharing")
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(6)
    text = printed(g)
    assert "Quest Sharing updated to 0.2.0" in text and "Welcome" not in text


# ---- good news ----------------------------------------------------------------------------------------------------------
def test_a_soft_sound_when_someone_accepts_my_quest(style):
    g = game(style)
    g.join_party(["Anna"])
    g.slash("share")
    g.advance(6)
    g.reply("Anna has accepted your quest.")
    assert list(g.eval("SOUNDS").values()) == [3175]
    g.reply("Anna has declined your quest.")
    assert len(g.eval("SOUNDS")) == 1, "only for good news"


def test_no_sound_in_combat_or_when_switched_off(style):
    g = game(style)
    g.run("IN_COMBAT = true")
    assert g.eval("NS.goodNews()") is False
    g.run("IN_COMBAT = false")
    g.run("NS.setSetting('sound', false)")
    assert g.eval("NS.goodNews()") is False and len(g.eval("SOUNDS")) == 0
    g.run("NS.setSetting('sound', true); SOUNDKIT = nil")
    assert g.eval("NS.goodNews()") is False, "a client without the sound list: silently nothing"


# ---- the quick chat ring ----------------------------------------------------------------------------------------------------
def open_ring(g):
    g.eval("NS.quickOpen")(True)
    return g.wheel()


def node_colour(slot):
    v = slot.node.vertex
    return tuple(round(v[i], 2) for i in (1, 2, 3))


def test_each_dot_has_the_colour_of_the_chat_it_goes_to(style):
    g = game(style)
    g.join_party(["Anna"])
    frame, slots, center, hint = open_ring(g)
    assert node_colour(slots[3]) == (0.54, 0.54, 0.8), "What I need: party blue"
    assert node_colour(slots[1]) == (0.8, 0.8, 0.8), "Hello: /s white (nearby, nobody targeted)"
    assert node_colour(slots[8]) == (0.8, 0.66, 0.0), "Invite: gold"
    g.eval("NS.quickClose")()
    g.run('TARGET = { name = "Lia", player = true }')
    frame, slots, center, hint = open_ring(g)
    assert node_colour(slots[1]) == (0.8, 0.4, 0.8), "Hello with a player targeted: whisper pink"


def test_the_middle_says_where_the_message_goes(style):
    g = game(style)
    g.join_party(["Anna"])
    frame, slots, center, hint = open_ring(g)
    g.run("CURSOR.x, CURSOR.y = 960 + 118 * math.sin(2 * 2 * math.pi / 8), 540 + 118 * math.cos(2 * 2 * math.pi / 8)")
    g.eval("NS.quickUpdateHover")()
    assert "to the party" in plain(center.text)
    g.run("CURSOR.x, CURSOR.y = 960, 540 + 118")
    g.eval("NS.quickUpdateHover")()
    assert "to everybody nearby (/s)" in plain(center.text)


def test_ring_size(style):
    g = game(style)
    for size, radius in (("small", 96), ("normal", 118), ("large", 142)):
        g.run(f"NS.setSetting('quickSize', '{size}')")
        frame, slots, center, hint = open_ring(g)
        p = slots[1].button.point
        assert round(p[5] - 540) == radius, size
        g.eval("NS.quickClose")()


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
