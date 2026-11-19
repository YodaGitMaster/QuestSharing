"""Everything on by default, and the settings window.     python tests/test_settings.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")
BOOLS = ["enabled", "auto", "shareNew", "click", "link", "sync", "markers", "panel", "panelSolo", "near", "mapPins", "teamWaypoint", "quickSend"]
QUIET = ["chat", "announce", "pickup"]          # the automatic party chat: off until you switch it on


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
    assert g.eval("QuestSharingDB.dbVersion") == 3


def test_the_window_has_a_row_for_every_switch(style):
    g = fresh(style)
    keys = [g.eval(f"NS.settingRows[{i}].key") for i in range(1, int(g.eval("#NS.settingRows")) + 1)]
    for key in BOOLS + ["area", "gap", "mode", "nearCount", "nearMode"]:
        assert key in keys, key


def test_an_older_save_keeps_every_choice_and_gains_the_new_defaults(style):
    g = fresh(style, loaded=False)
    g.run("QuestSharingDB = { near = false, panel = false, gap = 7, auto = false }")          # no dbVersion: an old save
    g.fire("ADDON_LOADED", "QuestSharing")
    assert g.eval("NS.db.near") is False and g.eval("NS.db.panel") is False, "the player's choices stay"
    assert g.eval("NS.db.gap") == 7 and g.eval("NS.db.auto") is False
    assert g.eval("NS.db.nearCount") == 5, "a setting the old save lacks gets its default"
    assert g.eval("QuestSharingDB.dbVersion") == 3


def test_the_automatic_party_chat_is_off_in_a_new_install(style):
    g = fresh(style)
    for key in QUIET:
        assert g.eval(f"NS.db.{key}") is False, key


def test_a_choice_made_in_the_current_version_is_never_overridden(style):
    g = fresh(style, loaded=False)
    g.run("QuestSharingDB = { near = false, panel = false, chat = true, dbVersion = 3 }")
    g.fire("ADDON_LOADED", "QuestSharing")
    assert g.eval("NS.db.near") is False and g.eval("NS.db.panel") is False
    assert g.eval("NS.db.chat") is True, "switched the chat back on yourself: it stays on"


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


def test_the_panel_shows_alone_too_and_the_option_turns_that_off(style):
    g = fresh(style)
    g.advance(3)
    assert panel_shown(g) is True, "on your own: your quests of the zone"
    panel, rows, cols, notes = g.eval("NS._panel()")
    assert panel.title.text == "Quests here" and "(2 in Elwynn Forest)" in panel.count.text
    assert cols[1].icon.shown is False, "no member columns when alone"
    g.slash("solo off")
    assert panel_shown(g) is False and g.eval("NS.db.panelSolo") is False
    g.join_party(["Anna"])
    g.advance(2)
    panel, rows, legend, notes = g.eval("NS._panel()")
    assert panel.shown is True and panel.title.text == "Party quests" and "Anna" in legend[1].name.text
    g.leave_party()
    g.advance(2)
    assert panel_shown(g) is False, "alone again, with the option off: hidden"

def test_the_panel_setting_off_keeps_it_hidden(style):
    g = fresh(style)
    g.slash("panel off")
    g.join_party(["Anna"])
    g.advance(3)
    assert panel_shown(g) is False


# ---- the window -----------------------------------------------------------------------------------------------
def test_rows_show_on_and_off_and_a_click_switches_them(style):
    g = fresh(style)
    assert "[OFF]" in row_text(g, "chat") and "Announce quests in common" in row_text(g, "chat")
    click(g, "chat")
    assert g.eval("NS.db.chat") is True and "[ON]" in row_text(g, "chat")
    click(g, "chat")
    assert g.eval("NS.db.chat") is False


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
    assert "Only show me" in row_text(g, "mode")


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
    assert g.eval("NS.db.sync") is False, "the first click only asks for a second one"
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
    assert row_on(W, "Turn on Quest Sharing") is True
    g.slash("minimap off")                                # a command changes it: the window shows it at once
    assert row_on(W, "Show the minimap button") is False
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
    assert ids == ["general", "objectives", "tracker", "dialogs", "items", "bags", "sharing", "party", "finder", "actions", "quick", "maps", "guide", "browser", "optional", "support"]
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
    assert any("Automatically track nearby quests" in t for t in tracker) and any("Pause after I edit the quest list" in t for t in tracker)
    assert W.tabs.tracker.text.text.startswith("|cffffd100") and W.tabs.general.text.text.startswith("|cffffffff"), "the open tab is gold, the others white"
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
    n = next(i for i in range(1, 19) if W.rows[i].frame.shown and "Automatically track nearby quests" in W.rows[i].text.text)
    g.eval("function(f) f.scripts.OnEnter(f) end")(W.rows[n].frame)
    assert "restore your previous tracked quests" in g.eval("TOOLTIP.text")


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



def visible_by_key(g, W, key):
    return next(r for r in W.rows.values() if r.index and g.eval("NS.settingRows")[r.index].key == key)


def press(g, button):
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(button)


def test_named_choices_select_exact_value_and_explain_the_result(style):
    g = fresh(style)
    g.slash("settings")
    W = window(g)
    r = visible_by_key(g, W, "mode")
    press(g, r.choices[3])
    assert g.eval("NS.db.mode") == "print"
    assert "Nobody else receives it" in r.desc.text
    assert "[x] Only show me" in r.choices[3].text
    press(g, r.choices[1])
    assert g.eval("NS.db.mode") == "box" and "press Enter" in r.desc.text
    # A label/background click no longer cycles a choice by accident.
    g.eval("function(f) f.scripts.OnMouseUp(f, 'LeftButton') end")(r.frame)
    assert g.eval("NS.db.mode") == "box"


def test_scrolling_keeps_position_on_changes_and_category_switch_resets_it(style):
    g = fresh(style)
    g.slash("settings")
    g.eval("NS.settingsTab")("sharing")
    W = window(g)
    press(g, W.scrollDown)
    offset = W.rowScroll.vscroll
    assert offset > 0
    press(g, visible_by_key(g, W, "area").choices[2])
    assert W.rowScroll.vscroll == offset
    g.eval("NS.settingsTab")("objectives")
    assert W.rowScroll.vscroll == 0 and not W.scrollDown.shown
    assert W.scrollHint.text == "All options shown"
    g.eval("NS.settingsTab")("quick")
    g.eval("NS.settingsScroll")(100000)
    assert W.rowScroll.vscroll == W.contentHeight - W.rowScroll.height
    assert W.scrollHint.text == "End of page" and W.ed.frame.shown


def test_all_controls_have_visible_plain_language_help_and_correct_categories(style):
    g = fresh(style)
    rows = list(g.eval("NS.settingRows").values())
    assert all(r.desc for r in rows if r.kind != "header")
    by_key = {r.key: r for r in rows if r.key}
    assert by_key["markMobs"].tab == "objectives"
    assert by_key["markMobs"].label == "Show ! above quest enemies"
    assert "nameplates" in by_key["markMobs"].desc
    assert by_key["near"].tab == "tracker"
    assert by_key["autoAcceptQuests"].tab == by_key["autoCompleteQuests"].tab == "dialogs"
    assert by_key["vendorSearch"].tab == by_key["itemSources"].tab == "browser"
    assert by_key["zoneLevels"].tab == "maps"
    assert "Requires QuestieDB" in by_key["vendorSearch"].note
    assert "Multiple rewards" in by_key["autoCompleteQuests"].desc


def test_map_overlays_have_switches_in_the_map_tab_that_work(style):
    g = fresh(style)
    for key in ("travelMap", "myTrainers"):
        assert g.eval(f"NS.settingRows[{idx(g, key)}].tab") == "maps" and g.eval(f"NS.settingRows[{idx(g, key)}].kind") == "bool"
        assert g.eval(f"NS.db.{key}") is True, "on by default"
        click(g, key)
        assert g.eval(f"NS.db.{key}") is False, f"{key} turns off from the window"
        click(g, key)
        assert g.eval(f"NS.db.{key}") is True, f"{key} turns back on"


def test_travel_faction_choice_cycles_mine_all_alliance_horde(style):
    g = fresh(style)
    assert g.eval("NS.db.travelFaction") == "mine" and g.eval(f"NS.settingRows[{idx(g, 'travelFaction')}].tab") == "maps"
    seen = []
    for _ in range(5):
        click(g, "travelFaction")
        seen.append(g.eval("NS.db.travelFaction"))
    assert seen == ["all", "Alliance", "Horde", "mine", "all"]


def test_settings_does_not_drop_rows_after_eighteen_and_last_row_is_reachable(style):
    g = fresh(style)
    g.run("""for i = 1, 25 do table.insert(NS.settingRows, {
        tab='optional',kind='bool',key='extra'..i,label='Extra option '..i,
        desc='Explanation of the extra option.'}) end""")
    g.slash("settings")
    g.eval("NS.settingsTab")("optional")
    W = window(g)
    last = visible_by_key(g, W, "extra25")
    g.eval("NS.settingsScroll")(100000)
    assert -last.frame.point[5] + last.frame.height - W.rowScroll.vscroll <= W.rowScroll.height
    g.eval("function(f) f.scripts.OnMouseUp(f, 'LeftButton') end")(last.frame)
    assert g.eval("NS.db.extra25") and last.tick.shown


def test_wrapped_game_font_measurements_increase_row_height(style):
    g = fresh(style)
    g.slash("settings")
    W = window(g)
    r = visible_by_key(g, W, "minimap")
    # Simulate a client/font requiring multiple lines for both the label and help.
    g.eval("function(r) r.text.GetStringHeight=function() return 56 end; r.desc.GetStringHeight=function() return 65 end end")(r)
    g.eval("NS.refreshSettings")()
    assert r.frame.height >= 56 + 65
    following = W.rows[4]
    assert -following.frame.point[5] >= -r.frame.point[5] + r.frame.height


def test_quest_marker_checkbox_changes_the_visible_enemy_marker():
    g = fresh("modern")
    g.run('ADD_PLATE("nameplate1", true)')
    g.slash("settings")
    g.eval("NS.settingsTab")("objectives")
    W = window(g)
    r = visible_by_key(g, W, "markMobs")
    assert g.eval("NS.markerFor(PLATES.nameplate1).shown")
    g.eval("function(f) f.scripts.OnMouseUp(f, 'LeftButton') end")(r.frame)
    assert not g.eval("NS.markerFor(PLATES.nameplate1).shown")
    assert "Off" in r.value.text and not r.tick.shown
    g.eval("function(f) f.scripts.OnMouseUp(f, 'LeftButton') end")(r.frame)
    assert g.eval("NS.markerFor(PLATES.nameplate1).shown")
    assert "On" in r.value.text and r.tick.shown


def test_tool_cards_keep_primary_action_separate_from_persistent_switch(style):
    g = fresh(style)
    g.slash("settings")
    g.eval("NS.settingsTab")("optional")
    W = window(g)
    spots = visible_by_key(g, W, "fishingMap")
    g.run("FISH_OPENS=0; NS.fishing.open=function() FISH_OPENS=FISH_OPENS+1 end")
    press(g, spots.button)
    assert g.eval("FISH_OPENS") == 1 and not g.eval("NS.db.fishingMap")
    g.eval('function(r) r.toggle.scripts.OnMouseUp(r.toggle,"LeftButton") end')(spots)
    assert g.eval("NS.db.fishingMap") and g.eval("FISH_OPENS") == 1
    assert spots.tick.shown and "On" in spots.toggleText.text
    # The card body is informational, so clicking the description cannot toggle it.
    g.eval('function(r) r.frame.scripts.OnMouseUp(r.frame,"LeftButton") end')(spots)
    assert g.eval("NS.db.fishingMap")
    g.eval("NS.settingsTab")("general")
    assert all(not r.card.shown and not r.toggle.shown and not r.note.shown for r in visible_rows(W))


def test_browser_db_contains_all_reference_launchers_and_extra_tools_stays_focused(style):
    g = fresh(style)
    g.slash("settings")
    g.eval("NS.settingsTab")("browser")
    W = window(g)
    assert "Items & dungeons" in W.heading.text
    cards = [r for r in W.rows.values() if r.index and r.frame.shown and r.card.shown]
    assert len(cards) == 7
    expected = {"Browse rewards", "Browse drops", "Dungeon quests", "Purge"}
    assert {r.button.text for r in cards if r.button.shown} == expected
    assert all(r.desc.text and r.note.shown for r in cards)
    # Exercise the actual shared button dispatcher for every reference launcher.
    g.run("""OPENED_TOOLS={}; NS.rewards.open=function() table.insert(OPENED_TOOLS,'rewards') end
       NS.loot.open=function() table.insert(OPENED_TOOLS,'loot') end
       NS.dungeonQuests.open=function() table.insert(OPENED_TOOLS,'dungeons') end
       NS.purgeData=function() table.insert(OPENED_TOOLS,'purge') end
       NS.professions.open=function() table.insert(OPENED_TOOLS,'cooking') end""")
    for r in cards:
        if r.button.shown:
            press(g, r.button)
    assert list(g.eval("OPENED_TOOLS").values()) == ["rewards", "loot", "dungeons", "purge"]
    g.eval("NS.settingsScroll")(100000)
    assert W.rowScroll.vscroll == W.contentHeight - W.rowScroll.height
    g.eval("NS.settingsTab")("optional")
    assert W.rowScroll.vscroll == 0
    cards = [r for r in W.rows.values() if r.index and r.frame.shown and r.card.shown]
    assert "Professions & character" in W.heading.text
    assert len(cards) == 3
    assert {r.button.text for r in cards} == {"Cooking recipes", "Update ranks", "Edit spots"}
    assert all(r.button.shown for r in cards)
    for r in cards:
        if r.button.text == "Cooking recipes":
            press(g, r.button)
    assert list(g.eval("OPENED_TOOLS").values()) == ["rewards", "loot", "dungeons", "purge", "cooking"]
    # the leftover-items review lives with the other quest item settings, the invitation with quest sharing
    by_label = {r.label: r.tab for r in g.eval("NS.settingRows").values() if r.kind == "action"}
    assert by_label["Review quest items left in my bags"] == "items"
    assert by_label["Quest invitation"] == "sharing"


def test_errors_and_logs_have_their_own_tab_with_check_errors_logs_and_reset(style):
    g = fresh(style)
    tabs = list(g.eval("NS.settingTabs").values())
    ids = [t.id for t in tabs]
    assert ids[-1] == "support" and tabs[-1].group == "Help" and tabs[-1].title == "Errors & logs"
    g.run("NS.db.errors = { { at = '10:00', msg = 'boom', count = 1 } }")
    g.slash("settings")
    g.eval("NS.settingsTab")("support")
    W = window(g)
    buttons = {r.button.text: r for r in visible_rows(W) if r.button.shown}
    assert set(buttons) >= {"Clear errors", "Clear logs", "Open report", "Reset settings"}
    assert not set(buttons) & {"Run check", "Show errors", "Show logs"}, "one button opens the report"
    info = next(r for r in visible_rows(W) if "Errors recorded" in r.text.text)
    assert "1 recorded" in info.desc.text or "1 recorded" in info.text.text
    press(g, buttons["Open report"].button)
    assert g.eval("NS._reportWindow()")[0].shown is True, "the report with the errors opened"
    press(g, buttons["Clear errors"].button)
    assert g.eval("#NS.db.errors") == 1, "clearing asks for a second click"
    press(g, buttons["Clear errors"].button)
    assert g.eval("#NS.db.errors") == 0
    press(g, buttons["Clear logs"].button)
    press(g, buttons["Clear logs"].button)
    assert "debug log cleared" in "\n".join(g.printed())
    assert [r.tab for r in g.eval("NS.settingRows").values() if r.key == "debug"] == ["support"], "the recording switch is with the logs"
    g.run("NS.db.sound = false")
    press(g, buttons["Reset settings"].button)
    press(g, buttons["Reset settings"].button)
    assert g.eval("NS.db.sound") is True, "reset restores the defaults"


# ---- the Quest guide tab ------------------------------------------------------------------------------------------------
# The planner API (QuestPlanner.lua / QuestCalibration.lua) is stubbed: the tab only talks to it through this contract.
GUIDE_STUB = """GUIDE_CALLS = {}
for _, name in ipairs({ "applySettings", "markCampBusy", "clearCampWaits", "showReport", "debug", "open" }) do
    NS.questPlanner[name] = function() GUIDE_CALLS[#GUIDE_CALLS + 1] = name end
end
CALIBRATION = { killSeconds = 10, interactionSeconds = 3, killSamples = 0, interactionSamples = 0,
                killCalibrated = false, interactionCalibrated = false }
NS.questCalibration = { get = function() return CALIBRATION end,
                        reset = function() GUIDE_CALLS[#GUIDE_CALLS + 1] = "reset" end }"""

GUIDE_ROWS = [
    ("header", None, "Quest guide"),
    ("bool", "questPlanner", None),
    ("choice", "questPlannerGoal", None),
    ("number", "questPlannerBudget", None),
    ("text", "questPlannerSelected", None),
    ("choice", "questPlannerScope", None),
    ("header", None, "Camps"),
    ("action", None, "Mark selected camp busy (5 min)"),
    ("action", None, "Clear camp waits"),
    ("bool", "campMap", None),
    ("header", None, "Learned pace"),
    ("info", None, None),
    ("action", None, "Reset learned pace"),
    ("header", None, "Report"),
    ("action", None, "Show plan report"),
    ("action", None, "Copy plan debug"),
]


def guide_calls(g):
    return list(g.eval("GUIDE_CALLS").values())


def guide_tab(g, stub=True):
    if stub:
        g.run(GUIDE_STUB)
    g.slash("settings")
    g.eval("NS.settingsTab")("guide")
    return window(g)


def guide_row(g, W, label):
    return next(r for r in visible_rows(W) if label in r.text.text)


def test_the_quest_guide_tab_follows_map_and_holds_every_guide_option(style):
    g = fresh(style)
    tabs = list(g.eval("NS.settingTabs").values())
    ids = [t.id for t in tabs]
    assert ids.index("guide") == ids.index("maps") + 1
    guide = tabs[ids.index("guide")]
    assert guide.title == "Quest guide" and len(guide.intro) > 20
    rows = [r for r in g.eval("NS.settingRows").values() if r.tab == "guide"]
    assert [(r.kind, r.key, r.label if r.kind in ("header", "action") else None) for r in rows] == GUIDE_ROWS
    by_key = {r.key: r for r in rows if r.key}
    assert list(by_key["questPlannerGoal"]["values"].values()) == ["all", "xp", "selected", "budget"]
    assert list(by_key["questPlannerScope"]["values"].values()) == ["all", "green-yellow"]
    assert (by_key["questPlannerBudget"].min, by_key["questPlannerBudget"].max) == (5, 240)
    assert by_key["questPlanner"].button == "Open plan"
    assert all(r.desc for r in rows if r.kind != "header"), "every control explains its visible effect"
    W = guide_tab(g)
    assert W.tab == "guide" and W.heading.text == "Quest guide"
    texts = visible_texts(W)
    for label in ("Quest guide", "Camps", "Learned pace", "Report", "Mark selected camp busy", "Reset learned pace",
                  "Show plan report", "Copy plan debug"):
        assert any(label in t for t in texts), label


def test_the_quest_guide_switch_lives_in_the_guide_tab_only(style):
    g = fresh(style)
    rows = list(g.eval("NS.settingRows").values())
    assert not [r for r in rows if r.tab == "optional" and r.key and r.key.startswith("questPlanner")]
    assert [r.tab for r in rows if r.key == "questPlanner"] == ["guide"], "the switch lives in the guide tab only"
    assert not [r for r in rows if r.label and "moved to its own tab" in r.label], "no pointer card is left behind"


def test_guide_controls_save_their_setting_and_update_the_guide(style):
    g = fresh(style)
    assert (g.eval("NS.db.questPlannerGoal"), g.eval("NS.db.questPlannerBudget"), g.eval("NS.db.questPlannerSelected"),
            g.eval("NS.db.questPlannerScope")) == ("all", 30, "", "all")
    W = guide_tab(g)
    goal = visible_by_key(g, W, "questPlannerGoal")
    press(g, goal.choices[4])
    assert g.eval("NS.db.questPlannerGoal") == "budget" and guide_calls(g) == ["applySettings"]
    assert "[x] Time limit" in goal.choices[4].text and "minutes" in goal.desc.text
    budget = visible_by_key(g, W, "questPlannerBudget")
    press(g, budget.more)
    assert g.eval("NS.db.questPlannerBudget") == 35 and guide_calls(g)[-1] == "applySettings"
    for _ in range(10):
        press(g, budget.less)
    assert g.eval("NS.db.questPlannerBudget") == 5, "never below 5 minutes"
    g.run("SHIFT = true")
    for _ in range(12):
        press(g, budget.more)
    g.run("SHIFT = false")
    assert g.eval("NS.db.questPlannerBudget") == 240, "never above 240 minutes"
    # The quest ID box saves on Enter, keeps only the numbers and shows what it kept.
    box = visible_by_key(g, W, "questPlannerSelected").edit
    assert box.shown and box.kind == "EditBox" and box.text == ""
    assert box.font[2] and box.font[3] is not None, "EditBox:SetFont needs flags"
    before = len(guide_calls(g))
    box.SetText(box, "12 345")
    g.eval("function(b) b.scripts.OnEnterPressed(b) end")(box)
    assert g.eval("NS.db.questPlannerSelected") == "12, 345" and box.text == "12, 345"
    assert guide_calls(g)[before:] == ["applySettings"]
    g.eval("function(b) b.scripts.OnEditFocusLost(b) end")(box)
    assert len(guide_calls(g)) == before + 1, "unchanged text does not replan"
    box.SetText(box, "999")
    g.eval("function(b) b.scripts.OnEscapePressed(b) end")(box)
    assert box.text == "12, 345" and g.eval("NS.db.questPlannerSelected") == "12, 345", "Escape keeps the saved IDs"
    box.SetText(box, "77")
    g.eval("function(b) b.scripts.OnEditFocusLost(b) end")(box)
    assert g.eval("NS.db.questPlannerSelected") == "77", "clicking away saves too"
    box.SetText(box, "12, Local Harvest")
    g.eval("function(b) b.scripts.OnEnterPressed(b) end")(box)
    assert g.eval("NS.db.questPlannerSelected") == "12, Local Harvest", "quest names are kept, not stripped"
    scope = visible_by_key(g, W, "questPlannerScope")
    press(g, scope.choices[2])
    assert g.eval("NS.db.questPlannerScope") == "green-yellow" and guide_calls(g)[-1] == "applySettings"
    # The on/off switch keeps its own path (settingChanged), not applySettings.
    before = len(guide_calls(g))
    switch = visible_by_key(g, W, "questPlanner")
    g.eval('function(r) r.toggle.scripts.OnMouseUp(r.toggle, "LeftButton") end')(switch)
    assert g.eval("NS.db.questPlanner") is True and "applySettings" not in guide_calls(g)[before:]
    for label, expected in (("Mark selected camp busy", ["markCampBusy"]), ("Clear camp waits", ["clearCampWaits"]),
                            ("Reset learned pace", ["reset", "applySettings"]), ("Show plan report", ["showReport"]),
                            ("Copy plan debug", ["debug"])):
        before = len(guide_calls(g))
        press(g, guide_row(g, W, label).button)
        assert guide_calls(g)[before:] == expected, label
    before = len(guide_calls(g))
    press(g, switch.button)
    assert switch.button.text == "Open plan" and guide_calls(g)[before:] == ["open"]


def test_the_learned_pace_line_shows_default_or_calibrated_times(style):
    g = fresh(style)
    W = guide_tab(g)
    pace = next(r for r in visible_rows(W) if g.eval("NS.settingRows")[r.index].kind == "info")
    assert "10 s per kill (default)" in pace.desc.text and "3 s per quest giver (default)" in pace.desc.text
    g.run("""CALIBRATION = { killSeconds = 7, interactionSeconds = 2.5, killSamples = 23, interactionSamples = 6,
                             killCalibrated = true, interactionCalibrated = true }""")
    g.eval("NS.refreshSettings")()
    assert "7 s per kill, from 23 kills" in pace.desc.text
    assert "2.5 s per quest giver, from 6 visits" in pace.desc.text
    assert "7 s per kill, from 23 kills" in g.eval("NS.rowText(NS.settingRows[%d])" % pace.index)
    assert not pace.button.shown and not pace.box.shown, "read-only: nothing to click"


def test_the_guide_tab_works_before_the_planner_api_exists(style):
    g = fresh(style)
    g.run("""NS.questCalibration = nil
        for _, name in ipairs({ "applySettings", "markCampBusy", "clearCampWaits", "showReport" }) do NS.questPlanner[name] = nil end""")
    W = guide_tab(g, stub=False)
    pace = next(r for r in visible_rows(W) if g.eval("NS.settingRows")[r.index].kind == "info")
    assert "10 s per kill (default)" in pace.desc.text
    press(g, visible_by_key(g, W, "questPlannerGoal").choices[2])
    assert g.eval("NS.db.questPlannerGoal") == "xp"
    g.run("PRINTED = {}")
    for label in ("Mark selected camp busy", "Clear camp waits", "Reset learned pace", "Show plan report"):
        press(g, guide_row(g, W, label).button)
    assert "\n".join(g.printed()).count("quest guide") >= 4


def test_set_setting_updates_the_guide_for_every_guide_key_but_not_the_switch(style):
    g = fresh(style)
    g.run(GUIDE_STUB)
    for key, value in (("questPlannerGoal", "xp"), ("questPlannerScope", "green-yellow"), ("questPlannerBudget", 60),
                       ("questPlannerSelected", "12")):
        g.eval("NS.setSetting")(key, value)
    assert guide_calls(g) == ["applySettings"] * 4
    g.eval("NS.setSetting")("gap", 6)
    g.eval("NS.setSetting")("questPlanner", False)
    assert guide_calls(g) == ["applySettings"] * 4
    g.slash("reset")
    assert (g.eval("NS.db.questPlannerGoal"), g.eval("NS.db.questPlannerScope"), g.eval("NS.db.questPlannerBudget"),
            g.eval("NS.db.questPlannerSelected")) == ("all", "all", 30, "")


def test_settings_tab_guide_opens_the_window_on_that_tab(style):
    g = fresh(style)
    assert window(g) is None
    g.eval("NS.settingsTab")("guide")                      # the guide's Options button and /qs plan options
    W = window(g)
    assert W.win.shown is True and W.tab == "guide"
    g.eval("NS.settingsTab")("general")
    assert W.win.shown is True and W.tab == "general"
    assert not [r for r in visible_rows(W) if r.edit and r.edit.shown], "the quest ID box stays on its own tab"
    g.slash("settings")
    assert W.win.shown is False
    g.eval("NS.settingsTab")("guide")
    assert W.win.shown is True and W.tab == "guide"



def test_every_saved_option_has_a_row_in_the_window(style):
    g = fresh(style)
    keys = set(g.eval("(function() local t = {} for k in pairs(NS.defaults) do if k ~= 'dbVersion' then t[#t + 1] = k end end table.sort(t) return table.concat(t, ',') end)()").split(","))
    rows = {g.eval(f"NS.settingRows[{i}].key") for i in range(1, int(g.eval("#NS.settingRows")) + 1)}
    assert not keys - rows, "options without a Settings row: %s" % sorted(keys - rows)


def test_the_item_button_move_back_row_clears_its_saved_position(style):
    g = fresh(style)
    g.eval("(function() NS.db.itemButtonPos = { 'TOPLEFT', 10, -10 } end)()")
    g.eval("NS.settingRows[%d].action" % idx(g, label="Move the item button back"))()
    assert g.eval("NS.db.itemButtonPos") is None


def test_tunable_waits_are_settings_rows_and_change_behaviour(style):
    g = fresh(style)
    for key, default in (("sortDelay", 3), ("chatLockNotice", 20), ("friendsReserve", 5), ("lfgReinvite", 5), ("ilvlKeepDays", 14)):
        assert g.eval(f"NS.db.{key}") == default, key
        assert idx(g, key), f"{key} has no Settings row"
        click(g, key)
        assert g.eval(f"NS.db.{key}") > default, f"{key} row does not step up"


def test_party_finder_classes_have_a_switch_each_and_follow_the_finder(style):
    g = fresh(style)
    i = idx(g, label="Invite Priest healers")
    assert i, "no class switch for priest healers"
    assert g.eval("NS.rowText(NS.settingRows[%d])" % i).find("Invite Priest healers") >= 0
    assert g.eval("NS.lfgInvite.classAllowed('healer', 'PRIEST')") is True
    g.eval("NS.settingsClick")(i, "LeftButton")
    assert g.eval("NS.lfgInvite.classAllowed('healer', 'PRIEST')") is False
    assert g.eval("NS.settingOn(NS.settingRows[%d])" % i) is False
    g.eval("NS.lfgInvite.setClass")("healer", "PRIEST", True)
    assert g.eval("NS.settingOn(NS.settingRows[%d])" % i) is True
    n = g.eval("(function() local n = 0 for _, r in ipairs(NS.settingRows) do if r.lfgClass then n = n + 1 end end return n end)()")
    roles = g.eval("(function() local n = 0 for _, l in pairs(NS.lfgInvite.ROLE_CLASSES) do n = n + #l end return n end)()")
    assert n == roles


def test_party_finder_key_has_a_set_key_row(style):
    g = fresh(style)
    i = idx(g, label="Key to search the party finder")
    assert i and g.eval("NS.settingRows[%d].kind" % i) == "key"
    g.eval("NS.setLfgKey")("F9")
    assert g.eval("NS.lfgKeyName()") == "F9"
    assert "F9" in g.eval("NS.rowText(NS.settingRows[%d])" % i)


def plain(t):
    import re
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def all_rows(W):
    out, n = [], 1
    while W.rows[n] is not None:
        if W.rows[n].frame.shown:
            out.append(W.rows[n])
        n += 1
    return out


def test_search_finds_settings_on_every_page_with_their_page_and_section(style):
    g = fresh(style)
    g.slash("settings")
    W = window(g)
    g.eval("NS.settingsSearch")("sort")
    texts = [plain(r.text.text) for r in all_rows(W)]
    assert any(t.startswith("Bags  >  ") for t in texts), texts
    assert any("Arrange my bags automatically" in t for t in texts)
    assert "Search:" in plain(W.heading.text) and "match" in plain(W.intro.text)
    g.eval("NS.settingsSearch")("party key")                  # every word must match
    texts = [plain(r.text.text) for r in all_rows(W)]
    assert any("Key to search the party finder" in t for t in texts) and not any("Arrange my bags" in t for t in texts)
    g.eval("NS.settingsSearch")("zzzz")
    assert "Nothing matches" in plain(W.intro.text)
    g.eval("NS.settingsSearch")("sound")
    i = next(n for n, r in enumerate(all_rows(W)) if "Play a sound" in plain(r.text.text))
    before = g.eval("NS.db.sound")
    g.eval("NS.settingsClick")(all_rows(W)[i].index, "LeftButton")
    assert g.eval("NS.db.sound") is (not before), "a found row works like on its page"
    g.eval("NS.settingsTab")("bags")                          # picking a page leaves the search
    assert W.query is None and W.tab == "bags"


def test_rows_that_need_another_switch_say_so_while_it_is_off(style):
    g = fresh(style)
    g.eval("(function() NS.db.autoSortBags = false end)()")
    assert g.eval("NS.settingNeedsOff(NS.settingRows[%d])" % idx(g, "sortDelay")) == "Arrange my bags automatically"
    g.eval("(function() NS.db.autoSortBags = true end)()")
    assert g.eval("NS.settingNeedsOff(NS.settingRows[%d])" % idx(g, "sortDelay")) is None
    for i in range(1, int(g.eval("#NS.settingRows")) + 1):
        need = g.eval("NS.settingRows[%d].needs" % i)
        if need:
            assert idx(g, need), f"row {i} needs unknown setting {need}"


def test_every_settings_path_in_the_code_names_a_real_page(style):
    import re
    g = fresh(style)
    titles = {g.eval("NS.settingTabs[%d].title" % i) for i in range(1, int(g.eval("#NS.settingTabs")) + 1)}
    root = pathlib.Path(__file__).resolve().parent.parent / "QuestSharing"
    bad = []
    for f in root.glob("*.lua"):
        for m in re.finditer(r"Settings > ([A-Z][A-Za-z&' ]+?)(?= >|[.,:)\"]| \(|$| Show| for| first| changed)", f.read_text(), re.M):
            name = m.group(1).strip()
            if name not in titles:
                bad.append(f"{f.name}: {name}")
    assert not bad, bad
    assert g.eval("(NS.settingPath('sortBy'))") == "Settings > Bags > Order items by"


def test_search_understands_everyday_words(style):
    g = fresh(style)
    for word, label in (("keybind", "Key to target and ping a quest enemy"), ("hotkey", "Quick chat key"),
                        ("junk", "Sell gray items when I open a vendor"), ("threat", "Show my aggro on enemies"),
                        ("sort", "Arrange my bags automatically")):
        out, n = g.eval("NS.settingsResults")(word)
        labels = [g.eval("NS.settingRows[%d].label" % out[i]) for i in range(1, n + 20) if isinstance(out[i], (int, float))]
        assert any(label in l for l in labels), (word, labels)


def test_item_level_rows_are_dimmed_until_a_minimum_is_set(style):
    g = fresh(style)
    g.eval("(function() NS.db.lfgMinIlvl = 0 end)()")
    assert g.eval("NS.settingRows[%d].inactive(NS.db)" % idx(g, "lfgUnknown")) is True
    g.eval("(function() NS.db.lfgMinIlvl = 50 end)()")
    assert g.eval("NS.settingRows[%d].inactive(NS.db)" % idx(g, "lfgAskIlvl")) is False

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
