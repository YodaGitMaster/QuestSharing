"""Error log + doctor, the invite action on the wheel, the minimap button, the release zip.
      python tests/test_extras.py"""
import math
import pathlib
import sys
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from harness import Game  # noqa: E402

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
    assert "no errors recorded" in printed(g)
    g.run('NS.logError("x", "something broke")')
    g.run("PRINTED = {}")
    g.slash("errors")
    win, box = g.eval("NS._reportWindow()")
    assert win.shown is True and "something broke" in box.text and "something broke" in printed(g)
    g.slash("errors clear")
    assert len(g.eval("NS.db.errors")) == 0


# ---- doctor --------------------------------------------------------------------------------------------------------
def test_doctor_reports_what_works_on_a_classic_style_client():
    g = game("classic")
    g.slash("doctor")
    win, box = g.eval("NS._reportWindow()")
    text = box.text
    assert win.shown is True and text == "\n".join(g.eval("NS.doctorLines()").values())
    assert "Quest Sharing 0.2.0 | game interface 16001 | classic quest API | 4 quests (3 in Elwynn Forest)" in text
    assert "[OK] share quests: push call yes, 9 reply messages recognised" in text
    assert "[--] click a tracked quest" in text and "shift-click links still work" in text
    assert "[OK] tracker follows you: zone mode (this client cannot measure distance)" in text
    assert "[--] quick chat wheel: key not set - type /qs key V" in text
    assert "[OK] no errors recorded" in text and "settings: enabled=on" in text


def test_doctor_on_a_modern_client_and_with_a_key_set():
    pre = "QUEST_TRACKER_MODULE = { OnBlockHeaderClick = function() end }"
    g = game("modern", pre=pre)
    g.slash("key V")
    g.run("PRINTED = {}")
    g.slash("doctor")
    text = printed(g)
    assert "[OK] click a tracked quest (tracker yes, watch frame no)" in text
    assert "[OK] tracker follows you: distance mode" in text
    assert "[OK] quick chat wheel: key V" in text
    assert "[OK] minimap button" in text and "[OK] invite a player from the wheel" in text


def test_doctor_lists_recorded_errors(style):
    g = game(style)
    g.run('NS.logError("x", "it broke")')
    g.slash("doctor")
    text = g.eval("NS._reportWindow()")[1].text
    assert "[--] 1 error(s) recorded" in text and "error: [12:34:56] x: it broke" in text


def test_the_report_text_cannot_be_edited_by_accident(style):
    g = game(style)
    g.slash("doctor")
    win, box = g.eval("NS._reportWindow()")
    original = box.text
    box.text = "typed over it"
    g.eval("function(b) b.scripts.OnTextChanged(b, true) end")(box)
    assert box.text == original


# ---- invite from the wheel ------------------------------------------------------------------------------------------
def invite_slot(g):
    g.cursor(*CENTER)
    g.eval("QuestSharing_QuickDown")()
    g.advance(0.6)
    g.cursor(CENTER[0] - 64, CENTER[1] + 64)                        # upper left = slot 8
    g.eval("QuestSharing_QuickUp")()


def test_the_last_slot_invites_the_target_and_whispers_them(style):
    g = game(style)
    g.run('TARGET = { name = "Lia", player = true }')
    invite_slot(g)
    assert g.invited() == ["Lia"]
    assert g.sent() == [("Sending you a party invite - let's quest together!", "WHISPER")] and g.eval("SENT[1].target") == "Lia"


def test_the_wheel_shows_an_invite_slot_as_such(style):
    g = game(style)
    g.cursor(*CENTER)
    g.eval("QuestSharing_QuickDown")()
    _, labels, _ = g.wheel()
    assert "Invite: Sending you a party" in labels[8].text          # the wheel shortens labels to 30 characters


def test_invites_are_refused_politely_when_they_cannot_work(style):
    g = game(style)
    invite_slot(g)                                                  # nobody targeted
    assert g.invited() == [] and "target a player first to invite" in printed(g)
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
    g.slash("quick add @invite")
    invite_slot(g)
    assert g.invited() == ["Lia"] and g.sent() == []
    g.advance(2)
    g.slash("quick edit 8 @inviteme please")
    invite_slot(g)
    assert g.invited() == ["Lia"], "'@inviteme' is just a message, not the action"
    assert g.sent()[-1][0] == "@inviteme please"


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
    assert g.eval("NS._settingsWindow()")[0].shown is True
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


def test_the_minimap_tooltip(style):
    g = game(style)
    b = g.eval("NS._minimapButton()")
    g.eval("function(b) b.scripts.OnEnter(b) end")(b)
    assert "Left click: settings" in g.eval("TOOLTIP.text")


# ---- release zip -------------------------------------------------------------------------------------------------------
def test_the_release_zip_is_ready_to_install():
    import build_release
    zpath, ver, names = build_release.build()
    assert ver == "0.2.0" and zpath.name == "QuestSharing-0.2.0.zip"
    with zipfile.ZipFile(zpath) as z:
        inside = set(z.namelist())
    assert all(n.startswith("QuestSharing/") for n in inside), "one folder to drop into AddOns"
    toc = (pathlib.Path(__file__).resolve().parent.parent / "QuestSharing" / "QuestSharing.toc").read_text().splitlines()
    for f in [l.strip() for l in toc if l.strip() and not l.startswith("#")]:
        assert f"QuestSharing/{f}" in inside, f
    assert "QuestSharing/Bindings.xml" in inside and "QuestSharing/QuestSharing.toc" in inside
    assert not any("test" in n or n.endswith(".py") for n in inside), "no tests in the install package"
    notes = (zpath.parent / "RELEASE_NOTES.md").read_text()
    assert "Quick chat wheel" in notes and "0.1.0" not in notes


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
