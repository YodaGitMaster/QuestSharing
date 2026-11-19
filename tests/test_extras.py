"""Error log + doctor, the invite action on the wheel, the minimap button, the release zip.
      python tests/test_extras.py"""
import math
import pathlib
import sys
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from harness import Game, VERSION  # noqa: E402

STYLES = ("modern", "classic")
CENTER = (500, 400)


def game(style, **kw):
    g = Game(style, **kw)
    g.start()
    g.slash("auto off")
    return g


def printed(g):
    return "\n".join(g.printed())


# ---- error log ---------------------------------------------------------------------------------------------------
def test_an_error_in_an_event_handler_is_logged_and_announced_once_a_minute(style):
    g = game(style)
    g.run('NS.on("MY_FAKE_EVENT", function() error("boom") end)')
    g.run("PRINTED = {}")
    g.fire("MY_FAKE_EVENT")
    g.fire("MY_FAKE_EVENT")
    errs = g.eval("NS.db.errors")
    assert len(errs) == 1 and errs[1].count == 2 and "boom" in errs[1].msg and errs[1].source == "MY_FAKE_EVENT"
    assert printed(g).count("an error was recorded") == 1
    g.advance(61)
    g.fire("MY_FAKE_EVENT")
    assert printed(g).count("an error was recorded") == 2


def test_an_error_in_a_timer_is_logged(style):
    g = game(style)
    g.run('NS.after(1, function() error("late boom") end)')
    g.advance(2)
    assert "late boom" in g.eval("NS.db.errors")[1].msg and g.eval("NS.db.errors")[1].source == "timer"


def test_lua_errors_from_our_files_are_captured_and_the_old_handler_still_runs(style):
    g = game(style)
    g.run("ERROR_SEEN = nil")
    g.eval("RAISE")("Interface\\AddOns\\QuestSharing\\Quick.lua:12: attempt to index a nil value")
    assert len(g.eval("NS.db.errors")) == 1 and "Quick.lua:12" in g.eval("NS.db.errors")[1].msg
    assert g.eval("ERROR_SEEN") is not None, "the game's own handler still gets it"
    g.eval("RAISE")("Interface\\AddOns\\SomeOtherAddon\\X.lua:1: not ours")
    assert len(g.eval("NS.db.errors")) == 1, "other addons' errors are none of our business"


def test_the_log_keeps_the_last_thirty(style):
    g = game(style)
    for i in range(45):
        g.run('NS.logError("t", "error number %d")' % i)
    errs = g.eval("NS.db.errors")
    assert len(errs) == 30 and "error number 44" in errs[30].msg and "error number 15" in errs[1].msg


def test_errors_command_shows_them_in_a_window_and_clears(style):
    g = game(style)
    g.run("PRINTED = {}")
    g.slash("errors")
    assert "No addon errors have been recorded" in g.eval("NS._reportWindow()")[1].text
    assert printed(g) == ""
    g.run('NS.logError("x", "something broke")')
    g.run("PRINTED = {}")
    g.slash("errors")
    win, box = g.eval("NS._reportWindow()")
    assert win.shown is True and "something broke" in box.text and printed(g) == ""
    g.slash("errors clear")
    assert len(g.eval("NS.db.errors")) == 0


# ---- doctor --------------------------------------------------------------------------------------------------------
def test_doctor_reports_what_works_on_a_classic_style_client():
    g = game("classic")
    g.slash("doctor")
    win, box = g.eval("NS._reportWindow()")
    assert win.shown is True and "ISSUE OVERVIEW" in box.text
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(win.selectAll)
    text = box.text
    assert f"Quest Sharing {VERSION} | game interface 16001 | classic quest API | 4 quests (3 in Elwynn Forest)" in text
    assert "[OK] share quests: push call yes, 9 reply messages recognised" in text
    assert "[--] click a tracked quest" in text and "shift-click links still work" in text
    assert "[OK] tracker follows you: zone mode (this client cannot measure distance)" in text
    assert "[--] quick chat wheel: key not set - type /qs key V" in text
    assert "[OK] no errors recorded" in text and "[enabled=true]" in text


def test_doctor_on_a_modern_client_and_with_a_key_set():
    pre = "QUEST_TRACKER_MODULE = { OnBlockHeaderClick = function() end }"
    g = game("modern", pre=pre)
    g.slash("key V")
    g.run("PRINTED = {}")
    g.slash("doctor")
    assert printed(g) == ""
    text = g.eval("NS._reportWindow()")[0].fullText
    assert "[OK] click a tracked quest (tracker yes, watch frame no)" in text
    assert "[OK] tracker follows you: distance mode" in text
    assert "[OK] quick chat wheel: key V" in text
    assert "[OK] minimap button" in text and "[OK] invite a player from the wheel" in text


def test_doctor_lists_recorded_errors(style):
    g = game(style)
    g.run('NS.logError("x", "it broke")')
    g.slash("doctor")
    win, box = g.eval("NS._reportWindow()")
    assert "Recorded errors: 1" in box.text and "it broke" in box.text
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(win.selectAll)
    assert "[--] 1 error recorded" in box.text and "  Source: x" in box.text and "it broke" in box.text


def test_the_report_text_cannot_be_edited_by_accident(style):
    g = game(style)
    g.slash("doctor")
    win, box = g.eval("NS._reportWindow()")
    original = box.text
    box.text = "typed over it"
    g.eval("function(b) b.scripts.OnTextChanged(b, true) end")(box)
    assert box.text == original


# ---- invite from the wheel ------------------------------------------------------------------------------------------
def invite_slot(g, click=True):
    g.cursor(*CENTER)
    g.eval("QuestSharing_QuickDown")()
    g.advance(0.6)
    g.cursor(CENTER[0] - 64, CENTER[1] + 64)                        # upper left = slot 8
    g.eval("QuestSharing_QuickUp")()
    if click and g.wheel()[0].shown:                                # an invite needs a real click (release is not allowed)
        g.eval("function(b, w) b.scripts.OnClick(b, w) end")(g.wheel()[1][8].button, "LeftButton")
    g.advance(1.2)


def test_the_last_slot_invites_the_target_and_whispers_them(style):
    g = game(style)
    g.run('TARGET = { name = "Lia", player = true }')
    invite_slot(g, click=False)
    assert g.invited() == [] and g.wheel()[0].shown is True, "a key release cannot invite: the ring waits for a click"
    g.eval("function(b, w) b.scripts.OnClick(b, w) end")(g.wheel()[1][8].button, "LeftButton")
    assert g.invited() == ["Lia"]
    assert g.sent() == [("Sending you a party invite - let's quest together!", "WHISPER")] and g.eval("SENT[1].target") == "Lia"


def test_the_ring_shows_an_invite_slot_as_such(style):
    g = game(style)
    g.run('TARGET = { name = "Lia", player = true }')
    g.cursor(*CENTER)
    g.eval("QuestSharing_QuickDown")()
    _, slots, center, _ = g.wheel()
    assert "Invite" in slots[8].label.text
    g.cursor(CENTER[0] - 64, CENTER[1] + 64)
    g.eval("function(f) f.scripts.OnUpdate(f, 0.05) end")(g.wheel()[0])
    assert "Invite to my party" in center.text and "Sending you a party invite" in center.text


def test_invites_are_refused_politely_when_they_cannot_work(style):
    g = game(style)
    invite_slot(g)                                                  # nobody targeted
    assert g.invited() == [] and "target a player (or point at one when you open the ring) to invite" in printed(g)
    g.run('TARGET = { name = "Lia", player = true }')
    g.join_party(["Anna", "Bob", "Cy", "Dee"])                      # five in the party already
    g.advance(2)
    invite_slot(g)
    assert g.invited() == [] and "your party is full" in printed(g)
    g.join_party(["Anna"])
    g.run("LEADER = false")
    g.advance(2)
    invite_slot(g)
    assert g.invited() == [] and "only the party leader can invite" in printed(g)
    g.run("LEADER = true; InviteUnit = nil; C_PartyInfo = nil")
    g.advance(2)
    invite_slot(g)
    assert g.invited() == [] and "no call to invite players" in printed(g)


def test_an_invite_without_text_does_not_whisper_and_lookalikes_are_plain_text(style):
    g = game(style)
    g.run('TARGET = { name = "Lia", player = true }')
    g.slash("quick remove 8")
    g.slash("quick add Invite | @invite")
    invite_slot(g)
    assert g.invited() == ["Lia"] and g.sent() == []
    g.advance(2)
    g.slash("quick edit 8 @inviteme please")
    invite_slot(g, click=False)                                     # "@inviteme" is just a message: a whisper, sent on release
    assert g.invited() == ["Lia"], "'@inviteme' is not the action"
    assert g.sent()[-1] == ("@inviteme please", "WHISPER")


# ---- minimap button ---------------------------------------------------------------------------------------------------
def test_the_minimap_button_sits_on_the_edge_and_is_on_by_default(style):
    g = Game(style, fresh=True)
    g.fire("ADDON_LOADED", "QuestSharing")
    g.fire("PLAYER_ENTERING_WORLD")
    b = g.eval("NS._minimapButton()")
    assert b.shown is True and g.eval("NS.hooks.minimap") is True
    p = b.point                                                       # (point, relativeTo, relativePoint, x, y)
    radius = 140 / 2 + 5
    assert abs(p[4] - math.cos(math.radians(215)) * radius) < 0.01 and abs(p[5] - math.sin(math.radians(215)) * radius) < 0.01


def test_left_click_opens_the_settings_right_click_toggles_the_panel(style):
    g = game(style)
    b = g.eval("NS._minimapButton()")
    click = g.eval("function(b, which) b.scripts.OnClick(b, which) end")
    click(b, "LeftButton")
    assert g.eval("NS._settingsWindow()").win.shown is True
    before = g.eval("NS.db.panel")
    click(b, "RightButton")
    assert g.eval("NS.db.panel") is (not before)
    click(b, "RightButton")
    assert g.eval("NS.db.panel") is before


def test_dragging_moves_it_around_the_edge_and_remembers_where(style):
    g = game(style)
    b = g.eval("NS._minimapButton()")
    g.eval("function(b) b.scripts.OnDragStart(b) end")(b)
    g.cursor(800 + 100, 400)                                          # to the right of the minimap centre
    g.eval("function(b) b.scripts.OnUpdate(b, 0.03) end")(b)
    assert abs(g.eval("NS.db.minimapAngle")) < 0.01 or abs(g.eval("NS.db.minimapAngle") - 360) < 0.01
    assert round(b.point[4]) == 75 and round(b.point[5]) == 0
    g.cursor(800, 400 + 100)                                          # straight above
    g.eval("function(b) b.scripts.OnUpdate(b, 0.03) end")(b)
    assert round(g.eval("NS.db.minimapAngle")) == 90
    g.eval("function(b) b.scripts.OnDragStop(b) end")(b)
    assert b.scripts.OnUpdate is None


def test_the_minimap_button_can_be_hidden_and_shown_again(style):
    g = game(style)
    b = g.eval("NS._minimapButton()")
    g.slash("minimap off")
    assert b.shown is False
    g.slash("minimap on")
    assert b.shown is True
    idx = g.eval("(function() for i, r in ipairs(NS.settingRows) do if r.key == 'minimap' then return i end end end)()")
    g.eval("NS.settingsClick")(idx, "LeftButton")
    assert b.shown is False and g.eval("NS.db.minimap") is False
    g.slash("reset")
    assert b.shown is True


def test_shortcut_buttons_open_the_quest_guide_and_dungeon_quests(style):
    g = game(style)
    guide, dungeon, finder = g.eval("NS._minimapShortcuts()").values()
    main = g.eval("NS._minimapButton()")
    assert guide.shown is True and dungeon.shown is True
    pts = [main.point, guide.point, dungeon.point, finder.point]
    assert len({(round(p[4]), round(p[5])) for p in pts}) == 4, "four separate buttons"
    g.eval("function() NS.questPlanner.open = function() CALLED_GUIDE = true end end")()
    g.eval("function() NS.dungeonQuests.open = function() CALLED_DUNGEON = true end end")()
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(guide)
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(dungeon)
    assert g.eval("CALLED_GUIDE") is True and g.eval("CALLED_DUNGEON") is True
    g.eval("function(b) b.scripts.OnEnter(b) end")(dungeon)
    assert g.eval("TOOLTIP.text") == "Dungeon quests"


def test_shortcut_buttons_follow_the_main_button_and_hide_with_it(style):
    g = game(style)
    main = g.eval("NS._minimapButton()")
    guide = list(g.eval("NS._minimapShortcuts()").values())[0]
    g.eval("function(b) b.scripts.OnDragStart(b) end")(guide)
    g.cursor(800 + 100, 400)
    g.eval("function(b) b.scripts.OnUpdate(b, 0.03) end")(guide)
    assert round(g.eval("NS.db.minimapAngle")) == 334, "the guide button sits one step past the main one"
    g.eval("function(b) b.scripts.OnDragStop(b) end")(guide)
    g.slash("minimap off")
    assert main.shown is False and all(not b.shown for b in g.eval("NS._minimapShortcuts()").values())
    g.slash("minimap on")
    assert all(b.shown for b in g.eval("NS._minimapShortcuts()").values())


def test_the_minimap_tooltip(style):
    g = game(style)
    b = g.eval("NS._minimapButton()")
    g.eval("function(b) b.scripts.OnEnter(b) end")(b)
    lines = "\n".join(g.eval("TOOLTIP.lines").values())
    assert g.eval("TOOLTIP.text") == "Quest Sharing" and "Left click: settings" in lines
    assert "Not in a party" in lines and "Quick chat key:" in lines and "not set" in lines
    assert "\\n" not in lines, "no stray backslash-n"
    g.join_party(["Anna"])
    g.run('ON_QUEST["party1"] = {[100] = true}')
    g.eval("function(b) b.scripts.OnEnter(b) end")(b)
    lines = "\n".join(g.eval("TOOLTIP.lines").values())
    assert "Party: 1 member, |cff55ff551 quest in common" in lines


# ---- release zip -------------------------------------------------------------------------------------------------------
def test_the_release_zip_is_ready_to_install():
    import build_release, tempfile
    out = pathlib.Path(tempfile.mkdtemp())                      # never write into the real dist/ (it holds published zips)
    ver, zpath, names, skipped, data = build_release.build(out=out, policy=False)
    assert ver == VERSION and zpath.name == f"QuestSharing-{VERSION}.zip"
    with zipfile.ZipFile(zpath) as z:
        inside = set(z.namelist())
    assert all(n.startswith("QuestSharing/") for n in inside), "one folder to drop into AddOns"
    toc = (pathlib.Path(__file__).resolve().parent.parent / "QuestSharing" / "QuestSharing.toc").read_text().splitlines()
    for f in [l.strip() for l in toc if l.strip() and not l.startswith("#")]:
        assert f"QuestSharing/{f}" in inside, f
    assert "QuestSharing/Bindings.xml" in inside and "QuestSharing/QuestSharing.toc" in inside
    assert not any("test" in n or n.endswith(".py") for n in inside), "no tests in the install package"
    assert inside == {f"QuestSharing/{n}" for n in names}, "exactly the allowlisted files, nothing else"
    try:
        build_release.build(out=out, policy=False)
        assert False, "an existing zip of the same version must not be replaced without --force"
    except SystemExit as e:
        assert "already exists" in str(e)
    notes = (zpath.parent / "RELEASE_NOTES.md").read_text()
    assert notes.strip().startswith("- ") and "## " not in notes, "only this version's section, as a list"


# ---- progressive versions ----------------------------------------------------------------------------------------------
def _problems(ver, released=("0.4.21", "0.4.22"), titles=("Unreleased", "0.4.22", "0.4.21"), zips=(), allow=False):
    import build_release
    return build_release.version_problems(ver, list(released) if released is not None else None, list(titles), list(zips), allow)


def test_the_next_patch_minor_or_major_version_is_accepted():
    for ver in ("0.4.23", "0.5.0", "1.0.0"):
        assert _problems(ver, titles=("Unreleased", ver, "0.4.22", "0.4.21")) == [], ver


def test_a_released_skipped_or_older_version_is_refused():
    assert any("already released" in p for p in _problems("0.4.22"))
    assert _problems("0.4.22", allow=True) == [], "--force may rebuild a tagged version"
    assert any("skips ahead" in p and "0.4.23" in p for p in _problems("0.4.24", titles=("0.4.24", "0.4.22")))
    assert any("skips ahead" in p for p in _problems("0.6.0", titles=("0.6.0", "0.4.22")))
    assert any("not newer" in p for p in _problems("0.4.20", titles=("0.4.20", "0.4.22")))
    assert any("not MAJOR.MINOR.PATCH" in p for p in _problems("0.4"))


def test_a_changelog_out_of_order_or_a_newer_zip_is_refused():
    assert any("newest-first" in p for p in _problems("0.4.23", titles=("Unreleased", "0.4.22", "0.4.23")))
    assert any("older than the newest" in p for p in _problems("0.4.23", titles=("0.4.24", "0.4.22")))
    assert any("Unreleased" in p for p in _problems("0.4.23", titles=("0.4.23", "Unreleased", "0.4.22")))
    assert any("newer than 0.4.23" in p for p in _problems("0.4.23", titles=("0.4.23", "0.4.22"), zips=("0.4.24",)))
    assert _problems("0.4.23", titles=("0.4.23", "0.4.22"), zips=("0.4.20", "0.4.22")) == [], "older zips are fine"


def test_without_git_the_previous_release_comes_from_the_changelog():
    assert _problems("0.4.23", released=None, titles=("0.4.23", "0.4.22")) == []
    assert any("skips ahead" in p for p in _problems("0.4.25", released=None, titles=("0.4.25", "0.4.22")))


def test_the_real_changelog_is_newest_first():
    import build_release
    probs = build_release.version_problems(build_release.version(), None, build_release.changelog_titles(), [])
    assert not [p for p in probs if "newest-first" in p or "not a version" in p or "Unreleased" in p], probs


def test_bump_moves_the_unreleased_notes_into_the_next_version():
    import build_release, tempfile
    tmp = pathlib.Path(tempfile.mkdtemp())
    (tmp / "QuestSharing").mkdir()
    (tmp / "QuestSharing" / "QuestSharing.toc").write_text("## Interface: 1\n## Version: 0.4.22\nCore.lua\n")
    (tmp / "CHANGELOG.md").write_text("# Changelog\n\n## Unreleased\n- new thing\n\n## 0.4.22\n- old\n\n## 0.4.21\n- older\n")
    saved = build_release.ROOT, build_release.ADDON, build_release.git_tags
    build_release.ROOT, build_release.ADDON = tmp, tmp / "QuestSharing"
    try:
        build_release.git_tags = lambda: ["0.4.21", "0.4.22"]
        assert build_release.bump() == ("0.4.22", "0.4.23")
        assert "## Version: 0.4.23" in (tmp / "QuestSharing" / "QuestSharing.toc").read_text()
        log = (tmp / "CHANGELOG.md").read_text()
        assert log.index("## Unreleased") < log.index("## 0.4.23") < log.index("- new thing") < log.index("## 0.4.22")
        assert build_release.notes("0.4.23") == "- new thing\n"
        try:
            build_release.bump()
            assert False, "0.4.23 has no tag yet: the next bump must wait for its release"
        except SystemExit as e:
            assert "not released yet" in str(e)
        build_release.git_tags = lambda: ["0.4.21", "0.4.22", "0.4.23"]
        try:
            build_release.bump()
            assert False, "nothing unreleased"
        except SystemExit as e:
            assert "nothing under" in str(e)
        assert build_release.bump.__defaults__ == ("patch",)
    finally:
        build_release.ROOT, build_release.ADDON, build_release.git_tags = saved


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
