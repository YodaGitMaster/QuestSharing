"""UX review 2026-11-19, batch B1: Settings window, slash commands and diagnostics.
python tests/test_ux_b1.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game, VERSION  # noqa: E402

STYLES = ("modern", "classic")


def plain(t):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def fresh(style):
    g = Game(style, fresh=True)
    g.fire("ADDON_LOADED", "QuestSharing")
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(6)                                    # past the welcome
    g.run("PRINTED = {}")
    return g


def printed(g):
    return "\n".join(plain(p) for p in g.printed())


def window(g, tab):
    g.slash("settings")
    g.eval("NS.settingsTab")(tab)
    return g.eval("NS._settingsWindow()")


def rows(W):
    return [W.rows[n] for n in range(1, len(W.rows) + 1) if W.rows[n].frame.shown]


def row(W, label):
    return next(r for r in rows(W) if label in plain(r.text.text))


def press(g, button):
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(button)


def idx(g, key=None, label=None):
    if key:
        return g.eval("(function() for i, r in ipairs(NS.settingRows) do if r.key == '%s' then return i end end end)()" % key)
    return g.eval("(function() for i, r in ipairs(NS.settingRows) do if r.label == '%s' then return i end end end)()" % label)


KEY_WORDS = re.compile(r"\b(autoSellGray|chatLock|bagMarks|questItems|aggroPlates|shareNew|auto-share|new-quest|mode box|friends\(beta\))")


# ---- UX-01: automatic party messages need Send immediately ----------------------------------------------------------
def test_ux01_party_chat_rows_are_greyed_and_say_why_until_send_immediately(style):
    g = fresh(style)
    W = window(g, "sharing")
    for label in ("Announce quests in common in party chat", "Tell the party when I finish a shared quest",
                  "Tell the party when I accept a quest a teammate has"):
        r = row(W, label)
        assert r.text.text.startswith("|cff9d9d9d") or "9d9d9d" in r.text.text[:12], (label, r.text.text)
        assert "Has no effect until" in plain(r.desc.text) and "Send immediately" in plain(r.desc.text), label
    g.slash("mode send")
    W = window(g, "sharing")
    r = row(W, "Announce quests in common in party chat")
    assert "Has no effect until" not in plain(r.desc.text)


def test_ux01_switching_party_chat_on_in_draft_mode_says_nothing_will_be_sent(style):
    g = fresh(style)
    g.slash("chat on")
    text = printed(g)
    assert "Send immediately" in text and "/qs mode send" in text, text
    g.run("PRINTED = {}")
    g.eval("NS.settingsClick")(idx(g, "announce"), "LeftButton")
    assert "Send immediately" in printed(g), "the window says it too"
    g.slash("mode send")
    g.run("PRINTED = {}")
    g.slash("pickup on")
    assert "nothing is sent" not in printed(g)


# ---- UX-04: reset asks for a second click and says what it does ------------------------------------------------------
def test_ux04_reset_button_needs_a_second_click(style):
    g = fresh(style)
    g.run("NS.db.sound = false")
    W = window(g, "support")
    r = row(W, "Reset everything to the defaults")
    press(g, r.button)
    assert g.eval("NS.db.sound") is False, "one click does not reset"
    r = row(W, "Reset everything to the defaults")
    assert plain(r.button.text) == "Click again to reset"
    press(g, r.button)
    assert g.eval("NS.db.sound") is True
    text = printed(g)
    assert "back to their defaults" in text and "everything on" not in text and "quick chat messages" in text


def test_ux04_a_late_second_click_starts_over(style):
    g = fresh(style)
    g.run("NS.db.sound = false")
    W = window(g, "support")
    press(g, row(W, "Reset everything to the defaults").button)
    g.advance(8)
    W = window(g, "support")
    r = row(W, "Reset everything to the defaults")
    assert plain(r.button.text) == "Reset settings"
    press(g, r.button)
    assert g.eval("NS.db.sound") is False


def test_ux04_help_and_slash_reset_no_longer_claim_everything_on(style):
    g = fresh(style)
    g.slash("help")
    g.slash("reset")
    text = printed(g)
    assert "everything on" not in text
    assert "/qs reset" in text and "quick chat messages" in text


# ---- UX-08: every toggle says what changed ---------------------------------------------------------------------------
TOGGLES = [
    ("sellgray on", "Sell gray items when I open a vendor: on (Settings > Bags)"),
    ("pickup on", "Tell the party when I accept a quest a teammate has: on (Settings > Quest sharing)"),
    ("chatlock on", "Block the chat box during combat: on (Settings > General)"),
    ("bagmarks off", "Mark quest items in my bags: off (Settings > Quest items)"),
    ("items off", "Show usable item buttons beside tracked quests: off (Settings > Quest items)"),
    ("aggro on", "Show my aggro on enemies (for tanks): on (Settings > General)"),
    ("debug off", "Record addon actions for troubleshooting: off (Settings > Errors & logs)"),
    ("sort on", "Arrange my bags automatically: on (Settings > Bags)"),
    ("bookmarks off", "Bookmark bag items with the Space bar: off (Settings > Bags)"),
    ("professions off", "Show the recipe guide in the profession window: off (Settings > Professions & character)"),
    ("fishing on", "Show saved spots on the world map: on (Settings > Professions & character)"),
    ("fishing off", "Show saved spots on the world map: off (Settings > Professions & character)"),
    ("mode send", "How to send quest progress messages: Send immediately (Settings > General)"),
    ("area all", "Which quests to share: All my quests (Settings > Quest sharing)"),
    ("gap 6", "Seconds between shared quests: 6 (Settings > Quest sharing)"),
    ("off", "Turn on Quest Sharing: off (Settings > General)"),
]


def test_ux08_each_toggle_prints_one_line_with_its_settings_name(style):
    for command, line in TOGGLES:
        g = fresh(style)
        g.slash(command)
        text = printed(g)
        assert line in text, (command, text)
        assert "| auto-share" not in text and not KEY_WORDS.search(text), (command, text)


def test_ux08_every_simple_switch_command_names_a_real_setting(style):
    g = fresh(style)
    for cmd in ("minimap", "auto", "new", "chat", "click", "link", "solo", "pickup", "coords", "shareclick", "debug",
                "bagmarks", "hidetracker", "sellgray", "chatlock", "aggro", "mappins", "waypoint", "sound", "ping",
                "pingobjects", "items", "sync", "announce", "markers", "panel", "friends", "near"):
        g.run("PRINTED = {}")
        g.slash(cmd + " off")
        text = printed(g)
        assert re.search(r": off \(Settings > [^)]+\)", text), (cmd, text)


# ---- UX-11: clearing errors and logs needs a second click --------------------------------------------------------------
def test_ux11_settings_clear_buttons_need_a_second_click(style):
    g = fresh(style)
    g.run("NS.db.errors = { { at = '10:00', msg = 'boom', count = 1 } }")
    g.run("NS.log('t', 'kept line')")
    W = window(g, "support")
    press(g, row(W, "Clear the errors").button)
    assert g.eval("#NS.db.errors") == 1
    assert plain(row(W, "Clear the errors").button.text) == "Click again to clear"
    press(g, row(W, "Clear the errors").button)
    assert g.eval("#NS.db.errors") == 0
    press(g, row(W, "Clear the logs").button)
    assert "kept line" in "\n".join(v for v in g.eval("QuestSharingLog").values() if isinstance(v, str))
    press(g, row(W, "Clear the logs").button)
    assert "kept line" not in "\n".join(v for v in g.eval("QuestSharingLog").values() if isinstance(v, str))


def test_ux11_report_window_clear_needs_a_second_click(style):
    g = fresh(style)
    g.eval("NS.logError")("x", "something broke")
    g.slash("errors")
    win = g.eval("NS._reportWindow()")[0]
    press(g, win.clear)
    assert len(g.eval("NS.db.errors")) == 1, "one click keeps the records"
    assert plain(win.clear.text) == "Click again to clear"
    assert "Click again within 5 seconds" in plain(win.hint.text)
    g.advance(6)                                    # the arming runs out: label and hint both go back
    assert plain(win.clear.text) == "Clear records"
    assert "Click again" not in plain(win.hint.text) and "Copy all includes" in plain(win.hint.text)
    press(g, win.clear)
    assert len(g.eval("NS.db.errors")) == 1, "after the time-out the next click only arms again"
    press(g, win.clear)
    assert len(g.eval("NS.db.errors")) == 0
    assert plain(win.clear.text) == "Clear records"
    assert "Copy all includes" in plain(win.hint.text)


# ---- UX-15: the ring test lives in Quick chat, not in the report window ---------------------------------------------
def test_ux15_report_window_has_no_ring_test_and_quick_chat_has_it(style):
    g = fresh(style)
    g.slash("errors")
    win = g.eval("NS._reportWindow()")[0]
    assert win.test is None, "no button that emotes to nearby players in a bug report window"
    W = window(g, "quick")
    r = row(W, "Test every message on the ring")
    assert plain(r.button.text) == "Test the ring"
    assert "players near you" in plain(r.desc.text)
    press(g, r.button)
    assert g.eval("NS.quickTestRunning()") is True


# ---- UX-25: /qs alone, unknown commands and the help list --------------------------------------------------------------
def test_ux25_bare_qs_prints_a_few_plain_lines(style):
    g = fresh(style)
    g.slash("")
    lines = g.printed()
    text = printed(g)
    assert 1 <= len(lines) <= 4 and "/qs settings" in text and "/qs help" in text
    assert "Quest Sharing: Quest Sharing" not in text, "ns.print already names the addon"
    assert "mode box" not in text and "sync on" not in text


def test_ux25_unknown_command_is_one_line(style):
    g = fresh(style)
    for command in ("autoaccept on", "travel", "where"):
        g.run("PRINTED = {}")
        g.slash(command)
        assert len(g.printed()) == 1 and "unknown command" in printed(g) and "/qs help" in printed(g), command
    g.run("PRINTED = {}")
    g.slash("mode nonsense")
    assert len(g.printed()) == 1 and "/qs mode box|send|print" in printed(g)


def test_ux25_help_lists_guide_subcommands_and_missing_commands(style):
    g = fresh(style)
    g.slash("help")
    text = printed(g)
    for part in ("/qs plan all|xp", "budget", "selected", "busy", "range|unrestricted", "why", "options", "follow", "hide",
                 "/qs lfg", "/qs ilvl", "/qs sound on|off", "/qs solo on|off",
                 "/qs pingobjects on|off", "/qs map", "/qs status", "/qs help"):
        assert part in text, part
    assert "planner" not in text.lower()


def test_ux25_map_lists_the_map_switches_with_their_place(style):
    g = fresh(style)
    g.slash("map")
    text = printed(g)
    assert "Show zone questing level ranges: off (Settings > Map)" in text
    assert "Show dungeons, boats and zeppelins on the world map: on (Settings > Map)" in text
    assert "Show the search box on the world map: off (Settings > Items & dungeons)" in text
    assert "Show saved spots on the world map: off (Settings > Professions & character)" in text


# ---- UX-33: the Map page names everything on it and points to the rest -----------------------------------------------
def test_ux33_map_intro_names_its_pins_and_points_to_the_other_pages(style):
    g = fresh(style)
    W = window(g, "maps")
    intro = plain(W.intro.text)
    for word in ("dungeon", "boats", "zeppelins", "trainers"):
        assert word in intro, word
    # The pointers live in the intro so the Map page still fits its window without scrolling.
    assert "Items & dungeons" in intro and "Professions & character" in intro and "fishing" in intro
    assert W.bottom < W.win.height - 30


def test_chosen_quests_box_keeps_typed_names_and_ids(style):
    g = fresh(style)
    i = next(n for n in range(1, 400) if g.eval(f"NS.settingRows[{n}] and NS.settingRows[{n}].key") == "questPlannerSelected")
    label = g.eval(f"NS.settingRows[{i}].label")
    assert "IDs" not in label and "Quests for the Chosen quests goal" == label
    assert "names or IDs" in g.eval(f"NS.settingRows[{i}].desc")
    g.eval("NS.settingsText")(i, "Local Harvest, 9001")
    saved = g.eval("NS.db.questPlannerSelected")
    assert "Local Harvest" in saved and "9001" in saved, saved


def test_quest_invitation_has_one_name_in_settings_help_and_minimap(style):
    g = fresh(style)
    labels = [g.eval(f"NS.settingRows[{n}].label") for n in range(1, 400) if g.eval(f"NS.settingRows[{n}]")]
    assert "Quest invitation" in labels and "Seek fellow adventurers" not in labels
    src = pathlib.Path(__file__).resolve().parent.parent / "QuestSharing"
    assert "open the Quest invitation window" in (src / "Core.lua").read_text()
    assert "quest optimizer" not in (src / "MinimapButton.lua").read_text()


# ---- UX-34: search knows the words players use -------------------------------------------------------------------------
def found(g, query):
    out = g.eval("NS.settingsResults")(query)
    res = out[0] if isinstance(out, tuple) else out
    keys = []
    for v in res.values():
        if isinstance(v, int):
            keys.append(g.eval(f"NS.settingRows[{v}].key"))
    return keys


def test_ux34_search_finds_gather_junk_and_keybind(style):
    g = fresh(style)
    assert "itemSources" in found(g, "gather")
    assert "itemSources" in found(g, "where to gather")
    assert "autoSellGray" in found(g, "junk") and "autoSellGray" in found(g, "trash")
    labels = [g.eval(f"NS.settingRows[{v}].label") for v in g.eval("NS.settingsResults")("keybind")[0].values()
              if isinstance(v, int)]
    assert "Quick chat key" in labels, labels


# ---- UX-42: one report button on Errors & logs --------------------------------------------------------------------------
def test_ux42_errors_and_logs_has_one_report_button(style):
    g = fresh(style)
    W = window(g, "support")
    buttons = [plain(r.button.text) for r in rows(W) if r.button.shown]
    assert buttons.count("Open report") == 1
    for gone in ("Run check", "Show errors", "Show logs"):
        assert gone not in buttons, gone
    press(g, row(W, "Check my setup, errors and logs").button)
    assert g.eval("NS._reportWindow()")[0].shown is True


# ---- UX-43: setup notes say what is wrong ------------------------------------------------------------------------------
def test_ux43_setup_notes_are_plain_sentences(style):
    g = fresh(style)
    checks = g.eval("""(function() return {
        "[--] quest icons above creatures that are part of your quests",
        "[--] pin the nearest quest in the world (the game's waypoint marker)",
        "[--] some brand new check",
    } end)()""")
    text = "\n".join(g.eval("NS.diagnosticOverview")(checks).values())
    assert "Quest ! marks above enemies are not available on this client." in text
    assert "The waypoint that follows your nearest quest is not available on this client." in text
    assert "Not available here: some brand new check" in text
    assert "- quest icons above creatures" not in text


# ---- UX-44: the Arrange bags card says what it really does -------------------------------------------------------------
def test_ux44_arrange_card_describes_the_chosen_bags_and_order(style):
    g = fresh(style)
    W = window(g, "bags")
    r = row(W, "Arrange bags")
    assert "Arrange the chosen bags once, right now, with the order set above." in plain(r.desc.text)
    assert "all your bags by topic" not in plain(r.desc.text)


# ---- UX-46: what's new after an update -------------------------------------------------------------------------------
def test_ux46_update_message_names_the_newest_features(style):
    g = Game(style)
    g.run("QuestSharingDB = { welcomed = '0.1.0', dbVersion = 3 }")
    g.fire("ADDON_LOADED", "QuestSharing")
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(6)
    text = printed(g)
    assert f"Quest Sharing updated to {VERSION}" in text
    assert "your messages now go into the chat box" not in text
    assert "Bags" in text and "Party finder" in text and "/qs settings" in text

# ---- UX-50: /qs gap keeps to the Settings range and says when it changes the value ---------------------------------
def test_ux50_gap_is_kept_between_2_and_30_and_says_so(style):
    g = fresh(style)
    g.slash("gap 500")
    assert g.eval("NS.db.gap") == 30
    text = printed(g)
    assert "between 2 and 30" in text and "Seconds between shared quests: 30 (Settings > Quest sharing)" in text, text
    g.run("PRINTED = {}")
    g.slash("gap 1")
    assert g.eval("NS.db.gap") == 2 and "between 2 and 30" in printed(g)
    g.run("PRINTED = {}")
    g.slash("gap 6")
    assert g.eval("NS.db.gap") == 6 and "between 2 and 30" not in printed(g)


# ---- UX-57: the Party finder picker's two toggles share one on-colour; Find says what it does ------------------------
def test_ux57_finder_toggles_use_the_same_on_colour_and_find_tip(style):
    g = fresh(style)
    g.run("NS.db.lfgSupercharge = true; NS.db.lfgWhisper = true")
    g.eval("NS.lfgFinder.toggle")(True)
    W = g.eval("NS.lfgFinder._window()")
    assert W.super.label.text[:10] == W.whisper.label.text[:10], (W.super.label.text, W.whisper.label.text)
    src = (pathlib.Path(__file__).resolve().parent.parent / "QuestSharing" / "LFGFinderUI.lua").read_text()
    assert "Search your listing's dungeon and invite players for the open roles" in src
    assert "invite the best match" not in src


# ---- UX-62: one name for the Party quests window ---------------------------------------------------------------------
def test_ux62_minimap_and_settings_say_party_quests_window(style):
    g = fresh(style)
    lines = [plain(l) for l in g.eval("NS.minimapLines()").values()]
    assert "Left click: settings   Right click: Party quests window   Drag: move" in lines, lines
    W = window(g, "general")
    assert "Right-click: Party quests window." in plain(row(W, "minimap").desc.text)
    g.slash("help")
    assert "quests in common\" panel" not in printed(g)


# ---- UX-65: no hand-written 'Needs ...' next to the automatic dependency note ----------------------------------------
def test_ux65_dependent_rows_say_their_dependency_once(style):
    g = fresh(style)
    g.run("NS.db.autoSortBags = false; NS.db.panel = false")
    for tab, label in (("bags", "Wait before arranging automatically"), ("party", "Also show the Party quests window")):
        W = window(g, tab)
        d = plain(row(W, label).desc.text)
        assert d.count("Has no effect until") == 1 and "Needs " not in d and "Requires " not in d, d
    W = window(g, "finder")
    for r in rows(W):
        d = plain(r.desc.text)
        assert "Needs Invite" not in d and "as dps" not in d, d


# ---- UX-74: proper singular and plural forms -------------------------------------------------------------------------
def test_ux74_bookmark_and_problem_counts_use_real_plurals(style):
    g = fresh(style)
    for n, word in ((1, "1 bookmark removed"), (3, "3 bookmarks removed"), (0, "no bookmarks to remove")):
        g.run("PRINTED = {}")
        g.run("NS.bagTools.clearBookmarks = function() return %d end" % n)
        g.slash("bookmarks clear")
        assert word in printed(g) and "(s)" not in printed(g), printed(g)
    g.run("NS.bagTools.clearBookmarks = function() return 2 end")
    W = window(g, "bags")
    g.run("PRINTED = {}")
    press(g, row(W, "Bookmarks").button)
    assert "2 bookmarks removed" in printed(g) and "(s)" not in printed(g), printed(g)
    g.run("NS.db.errors = { { at = '10:00', msg = 'boom', count = 1 } }")
    text = "\n".join(plain(l) for l in g.eval("NS.minimapLines()").values())
    assert "1 problem recorded" in text and "(s)" not in text, text
    g.run("NS.db.errors = { { msg = 'a' }, { msg = 'b' } }")
    text = "\n".join(plain(l) for l in g.eval("NS.minimapLines()").values())
    assert "2 problems recorded" in text, text


# ---- UX-75: the chat prefix is gold, not the blue that means 'elsewhere' ---------------------------------------------
def test_ux75_chat_prefix_is_gold(style):
    g = fresh(style)
    g.eval("NS.print")("hello")
    assert g.printed()[-1] == "|cffffd100Quest Sharing:|r hello", g.printed()



# ---- Follow-ups 2026-11-19 (UX-48 rest, UX-55 rest, UX-63 rest, plural errors) ----------------------------------
def test_qs_panel_without_argument_shows_the_window(style):
    g = fresh(style)
    g.run("NS.db.panel = false")
    g.slash("panel"); g.slash("panel")
    assert g.eval("NS.db.panel") is True, "/qs panel never hides; the x or /qs panel off does"
    g.slash("panel off")
    assert g.eval("NS.db.panel") is False


def test_minimap_right_click_hiding_the_window_says_how_to_bring_it_back(style):
    g = fresh(style)
    g.run("NS.db.panel = true; NS.syncMinimapButton()")
    b = g.eval("QuestSharingMinimapButton")
    b.scripts.OnClick(b, "RightButton")
    assert g.eval("NS.db.panel") is False and "/qs panel on" in printed(g)
    b.scripts.OnClick(b, "RightButton")
    assert g.eval("NS.db.panel") is True


def test_follow_up_wording_in_code():
    root = pathlib.Path(__file__).resolve().parent.parent / "QuestSharing"
    share = (root / "Share.lua").read_text()
    assert "click Stop or type /qs stop to cancel" in share
    settings = (root / "Settings.lua").read_text()
    assert '"Zone level guides"' not in settings and '"Saved fishing spots"' not in settings
    core = (root / "Core.lua").read_text()
    assert "2-30 (default 4)" in core and "water editor" not in core and "rewardBrowser" not in core
    assert "error(s)" not in (root / "Diagnostics.lua").read_text()

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
