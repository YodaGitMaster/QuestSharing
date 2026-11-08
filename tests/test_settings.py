"""Everything on by default, and the settings window.     python tests/test_settings.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")
BOOLS = ["enabled", "auto", "shareNew", "chat", "announce", "verbose", "click", "link", "sync", "markers", "panel", "near"]


def fresh(style, pre="", loaded=True):
    """A brand-new install: no saved settings at all."""
    g = Game(style, pre, fresh=True)
    if loaded:
        g.fire("ADDON_LOADED", "QuestSharing")
        g.fire("PLAYER_ENTERING_WORLD")
    return g


def panel_shown(g):
    res = g.eval("NS._panel()")
    panel = res[0] if isinstance(res, tuple) else res
    return bool(panel and panel.shown)


def window(g):
    """The settings window's state (win, tab, rows, tabs, ed), or None before it was ever opened."""
    W = g.eval("NS._settingsWindow()")
    return W if W is not None and W.win is not None else None

def idx(g, key=None, label=None):
    if key:
        return g.eval("(function() for i, r in ipairs(NS.settingRows) do if r.key == '%s' then return i end end end)()" % key)
    return g.eval("(function() for i, r in ipairs(NS.settingRows) do if r.label and string.find(r.label, '%s', 1, true) then return i end end end)()" % label)


def click(g, key, button="LeftButton"):
    g.eval("NS.settingsClick")(idx(g, key), button)


def row_text(g, key):
    return g.eval("NS.rowText(NS.settingRows[%d])" % idx(g, key))


# ---- defaults ---------------------------------------------------------------------------------------------
def test_every_switch_is_on_in_a_new_install(style):
    g = fresh(style)
    for key in BOOLS:
        assert g.eval(f"NS.db.{key}") is True, key
    assert (g.eval("NS.db.area"), g.eval("NS.db.gap"), g.eval("NS.db.mode"), g.eval("NS.db.nearCount"),
            g.eval("NS.db.nearMode")) == ("zone", 4, "box", 5, "auto")
    assert g.eval("QuestSharingDB.dbVersion") == 2


def test_the_window_has_a_row_for_every_switch(style):
    g = fresh(style)
    keys = [g.eval(f"NS.settingRows[{i}].key") for i in range(1, int(g.eval("#NS.settingRows")) + 1)]
    for key in BOOLS + ["area", "gap", "mode", "nearCount", "nearMode"]:
        assert key in keys, key


def test_settings_saved_by_earlier_versions_are_switched_on_but_choices_are_kept(style):
    g = fresh(style, loaded=False)
    g.run("QuestSharingDB = { near = false, panel = false, gap = 7, auto = false }")          # no dbVersion: an old save
    g.fire("ADDON_LOADED", "QuestSharing")
    assert g.eval("NS.db.near") is True and g.eval("NS.db.panel") is True, "the two new defaults arrive"
    assert g.eval("NS.db.gap") == 7 and g.eval("NS.db.auto") is False, "the player's other choices stay"
    assert g.eval("QuestSharingDB.dbVersion") == 2


def test_a_choice_made_in_the_current_version_is_never_overridden(style):
    g = fresh(style, loaded=False)
    g.run("QuestSharingDB = { near = false, panel = false, dbVersion = 2 }")
    g.fire("ADDON_LOADED", "QuestSharing")
    assert g.eval("NS.db.near") is False and g.eval("NS.db.panel") is False


def test_the_tracker_follows_you_from_the_start_and_off_restores_your_list():
    g = Game("modern", fresh=True)
    g.run("WATCHED = { [200] = true }")
    g.set_dist(q100=400, q101=900)
    g.fire("ADDON_LOADED", "QuestSharing")
    g.slash("near 2")
    g.fire("PLAYER_ENTERING_WORLD")
    assert g.watched() == [200], "it waits a few seconds for the quest log to load"
    g.advance(6)
    assert g.watched() == [100, 101]
    g.slash("near off")
    assert g.watched() == [200], "the list you had before is back"


def test_the_tracker_starts_in_zone_mode_on_a_client_without_distances():
    g = fresh("classic")
    g.advance(8)
    assert g.eval("NS.nearMode()") == "zone" and g.watched() == [100, 101, 102]


def test_the_panel_shows_only_while_in_a_party(style):
    g = fresh(style)
    g.advance(3)
    assert panel_shown(g) is False, "no party, no panel"
    g.join_party(["Anna"])
    g.advance(2)
    panel, rows, legend, notes = g.eval("NS._panel()")
    assert panel.shown is True and "Anna" in legend[1].name.text and notes.text.startswith("No quests in common yet.")
    g.leave_party()
    g.advance(2)
    assert panel_shown(g) is False


def test_the_panel_setting_off_keeps_it_hidden(style):
    g = fresh(style)
    g.slash("panel off")
    g.join_party(["Anna"])
    g.advance(3)
    assert panel_shown(g) is False


# ---- the window -----------------------------------------------------------------------------------------------
def test_rows_show_on_and_off_and_a_click_switches_them(style):
    g = fresh(style)
    assert "[ON]" in row_text(g, "chat") and "Announce quests in common" in row_text(g, "chat")
    click(g, "chat")
    assert g.eval("NS.db.chat") is False and "[OFF]" in row_text(g, "chat")
    click(g, "chat")
    assert g.eval("NS.db.chat") is True


def test_choice_rows_cycle_with_left_and_right_clicks(style):
    g = fresh(style)
    click(g, "area")
    assert g.eval("NS.db.area") == "all"
    click(g, "area")
    assert g.eval("NS.db.area") == "zone"
    click(g, "mode")
    click(g, "mode")
    assert g.eval("NS.db.mode") == "print"
    click(g, "mode")
    assert g.eval("NS.db.mode") == "box"
    click(g, "mode", "RightButton")
    assert g.eval("NS.db.mode") == "print", "right click goes backwards"
    assert "shows it only to me" in row_text(g, "mode")


def test_number_rows_step_stay_in_range_and_shift_steps_by_five(style):
    g = fresh(style)
    click(g, "gap")
    assert g.eval("NS.db.gap") == 5
    click(g, "gap", "RightButton")
    click(g, "gap", "RightButton")
    click(g, "gap", "RightButton")
    click(g, "gap", "RightButton")
    assert g.eval("NS.db.gap") == 2, "never below 2"
    g.run("SHIFT = true")
    for _ in range(10):
        click(g, "gap")
    assert g.eval("NS.db.gap") == 30, "never above 30"
    g.run("SHIFT = false")
    top = 25 if style == "modern" else 5
    for _ in range(40):
        click(g, "nearCount")
    assert g.eval("NS.db.nearCount") == top, "limited by what the tracker can hold"
    for _ in range(40):
        click(g, "nearCount", "RightButton")
    assert g.eval("NS.db.nearCount") == 1


def test_switching_things_in_the_window_does_what_the_commands_do(style):
    g = fresh(style)
    g.join_party(["Anna"])
    g.advance(5.3)
    assert g.eval("NS.isSharing()") is True
    click(g, "enabled")                                   # master switch off: a running share stops
    assert g.eval("NS.isSharing()") is False and g.eval("NS.db.enabled") is False
    click(g, "enabled")
    g.advance(2)
    assert panel_shown(g) is True
    click(g, "panel")                                     # panel off: hidden at once
    assert panel_shown(g) is False
    click(g, "panel")
    g.advance(2)
    assert panel_shown(g) is True
    click(g, "near")                                      # tracker follows me: off
    assert g.eval("NS.db.near") is False


def test_the_reset_row_puts_everything_back(style):
    g = fresh(style)
    for key in ("chat", "sync", "markers"):
        click(g, key)
    click(g, "area")
    click(g, "gap")
    g.slash("near off")
    g.run("PRINTED = {}")
    g.eval("NS.settingsClick")(idx(g, label="Reset everything"), "LeftButton")
    for key in BOOLS:
        assert g.eval(f"NS.db.{key}") is True, key
    assert (g.eval("NS.db.area"), g.eval("NS.db.gap")) == ("zone", 4)
    assert "back to their defaults" in "\n".join(g.printed())


def test_slash_reset_does_the_same(style):
    g = fresh(style)
    click(g, "link")
    g.slash("reset")
    assert g.eval("NS.db.link") is True


def visible_rows(W):
    return [W.rows[n] for n in range(1, 19) if W.rows[n].frame.shown]


def visible_texts(W):
    return [r.text.text for r in visible_rows(W)]


def row_on(W, label):
    """Is the check box of the visible row with this label ticked?"""
    r = next(r for r in visible_rows(W) if label in r.text.text)
    return r.box.shown and r.tick.shown


def test_the_window_opens_closes_and_follows_commands(style):
    g = fresh(style)
    assert window(g) is None
    g.slash("settings")
    W = window(g)
    assert W.win.shown is True and W.tab == "general"
    assert row_on(W, "Quest Sharing enabled") is True
    g.slash("minimap off")                                # a command changes it: the window shows it at once
    assert row_on(W, "Minimap button") is False
    g.slash("config")
    assert W.win.shown is False
    g.slash("options")
    assert W.win.shown is True
    assert "QuestSharingSettings" in list(g.eval("UISpecialFrames").values()), "Esc closes it"


def test_every_setting_is_on_exactly_one_tab(style):
    g = fresh(style)
    n = int(g.eval("#NS.settingRows"))
    tabs = [g.eval("NS.settingRows[%d].tab" % i) for i in range(1, n + 1)]
    ids = [g.eval("NS.settingTabs[%d].id" % i) for i in range(1, int(g.eval("#NS.settingTabs")) + 1)]
    assert ids == ["general", "sharing", "party", "tracker", "quick", "social"]
    assert all(t in ids for t in tabs)
    assert all(tabs.count(t) >= 1 for t in ids), "no empty tab"
    keys = [g.eval("NS.settingRows[%d].key" % i) for i in range(1, n + 1) if g.eval("NS.settingRows[%d].key" % i)]
    assert len(keys) == len(set(keys)), "no setting appears twice"


def test_tabs_show_only_their_own_rows(style):
    g = fresh(style)
    g.slash("settings")
    W = window(g)
    general = visible_texts(W)
    g.eval("NS.settingsTab")("tracker")
    tracker = visible_texts(W)
    assert W.tab == "tracker" and not set(general) & set(tracker)
    assert any("Tracker follows me" in t for t in tracker) and any("Seconds it waits after I change the tracker" in t for t in tracker)
    assert W.tabs.tracker.text.text.startswith("|cffffd100") and W.tabs.general.text.text.startswith("|cff55ccff"), "the open tab is gold"
    assert W.ed.frame.shown is False, "the message editor belongs to the Quick chat tab only"
    g.eval("NS.settingsTab")("quick")
    assert W.ed.frame.shown is True


def test_clicking_a_tab_button_switches_tab(style):
    g = fresh(style)
    g.slash("settings")
    W = window(g)
    g.eval("function(t) t.frame.scripts.OnMouseUp(t.frame, 'LeftButton') end")(W.tabs.sharing)
    assert W.tab == "sharing" and any("Share my quests" in t for t in visible_texts(W))


def test_clicking_a_row_in_the_window_frame_works(style):
    g = fresh(style)
    g.slash("settings")
    W = window(g)
    g.eval("NS.settingsTab")("sharing")
    n = next(i for i in range(1, 19) if W.rows[i].frame.shown and "Sync quest lists" in W.rows[i].text.text)
    g.eval("function(f, b) f.scripts.OnMouseUp(f, b) end")(W.rows[n].frame, "LeftButton")
    assert g.eval("NS.db.sync") is False and W.rows[n].tick.shown is False
    g.eval("NS.settingsTab")("tracker")
    n = next(i for i in range(1, 19) if W.rows[i].frame.shown and "Tracker follows me" in W.rows[i].text.text)
    g.eval("function(f) f.scripts.OnEnter(f) end")(W.rows[n].frame)
    assert "puts your old list back" in g.eval("TOOLTIP.text")


def test_the_panels_settings_link_opens_the_window(style):
    g = fresh(style)
    g.join_party(["Anna"])
    g.advance(2)
    panel = g.eval("NS._panel()")[0]
    g.eval("function(f) f.scripts.OnMouseUp(f, 'LeftButton') end")(panel.settingsLink)
    assert window(g).win.shown is True


def test_the_game_options_get_an_entry(style):
    g = fresh(style)
    assert g.eval("NS.hooks.optionsEntry") is True
    added = list(g.eval("OPTIONS_ADDED").values())
    assert len(added) == 1
    name = added[0].name if style == "modern" else added[0].name
    assert name == "Quest Sharing"


def test_status_help_and_probe_mention_the_window(style):
    g = fresh(style)
    g.run("PRINTED = {}")
    g.slash("status")
    g.slash("help")
    g.slash("probe")
    text = "\n".join(g.printed())
    assert "near on" in text and "panel on" in text and "/qs settings" in text and "/qs reset" in text
    assert "settings window: /qs settings | entry in the game's options: yes" in text


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
