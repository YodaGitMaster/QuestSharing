"""The quick chat wheel: key, wheel, placeholders, channels, editing, key binding.
       python tests/test_quick.py"""
import math
import pathlib
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import ADDON_DIR, Game  # noqa: E402

STYLES = ("modern", "classic")
LINK100 = "|cffffff00|Hquest:100:3|h[Wolves Among Us]|h|r"
CENTER = (500, 400)


def game(style, **kw):
    g = Game(style, fresh=kw.pop("fresh", False))
    g.start()
    g.slash("auto off")
    return g


def key_down(g):
    g.eval("QuestSharing_QuickDown")()


def key_up(g):
    g.eval("QuestSharing_QuickUp")()


def open_wheel(g, at=CENTER):
    g.cursor(*at)
    key_down(g)


def point(g, dx, dy):
    g.cursor(CENTER[0] + dx, CENTER[1] + dy)


def say_slot(g, dx, dy, hold=0.6):
    """Hold the key, point at (dx, dy) from the centre, release."""
    open_wheel(g)
    g.advance(hold)
    point(g, dx, dy)
    key_up(g)


def sent(g):
    return g.sent()


# ---- geometry ----------------------------------------------------------------------------------------------------
def test_slot_under_the_pointer():
    g = Game("modern")
    at = g.eval("NS.quickSlotAt")
    assert [at(0, 50, 8), at(35, 35, 8), at(50, 0, 8), at(35, -35, 8), at(0, -50, 8), at(-35, -35, 8), at(-50, 0, 8), at(-35, 35, 8)] == [1, 2, 3, 4, 5, 6, 7, 8]
    assert at(-1, 50, 8) == 1 and at(1, 50, 8) == 1, "the top slot is centred on straight up"
    assert at(10, 10, 8) is None and at(0, 0, 8) is None, "the middle is a dead zone"
    assert at(30, 5, 1) == 1 and at(-80, -80, 1) == 1
    assert at(0, 50, 0) is None
    assert [at(0, 50, 3), at(50, -30, 3), at(-50, -30, 3)] == [1, 2, 3]


# ---- placeholders ----------------------------------------------------------------------------------------------------
def test_name_and_here(style):
    g = game(style)
    r = g.eval("NS.quickResolve")
    assert r("Hey {name}! o/") == "Hey there! o/"
    g.run('TARGET = { name = "Lia", player = true }')
    assert r("Hey {name}! o/") == "Hey Lia! o/" and r("Hi {NAME}") == "Hi Lia"
    g.run('TARGET = { name = "Guard", player = false }')
    assert r("Hey {name}!") == "Hey there!", "only players are greeted by name"
    assert r("({here})") == "(Elwynn Forest)"
    g.run('SUBZONE = "Goldshire"')
    assert r("({here} in {zone})") == "(Goldshire in Elwynn Forest)"
    assert r("{unknown} stays") == "{unknown} stays"


def test_need_lists_what_is_left_to_do_in_this_area(style):
    g = game(style)
    r = g.eval("NS.quickResolve")
    # quest 101 is done, quest 102 has no objective lines, quest 200 is in another zone
    assert r("I need to: {need}") == "I need to: Wolf slain 3/8, Wolf Pelt 0/4 [Wolves Among Us] and [A Personal Quest]"
    g.run("for _, q in ipairs(QUESTS) do if q.id then q.complete = true end end")
    assert r("{need}") == "nothing special, just looking around"
    g.run('ZONE = "Westfall"; BYID(200).complete = false')
    assert r("{need}") == "Defias Thief slain 1/5 [The Defias Brotherhood]"


def test_need_puts_the_nearest_quest_first_when_the_client_can_measure_it():
    g = game("modern")
    g.set_dist(q100=900, q102=10)
    assert g.eval("NS.quickResolve")("{need}").startswith("[A Personal Quest] and Wolf slain 3/8")


def test_common_and_quest(style):
    g = game(style)
    r = g.eval("NS.quickResolve")
    assert r("{common}") == "nothing yet" and r("{quest}") == LINK100
    g.run('ON_QUEST["party1"] = {[100] = true}')
    g.join_party(["Anna"])
    assert r("We share: {common}") == f"We share: {LINK100}"
    g.run("for _, q in ipairs(QUESTS) do q.complete = true end")
    assert r("{quest}") == "my quests"


def test_a_resolved_message_always_fits_one_chat_message(style):
    g = game(style)
    g.run("BYID(100).objectives[1].text = '" + "x" * 300 + ": 1/9'")
    assert len(g.eval("NS.quickResolve")("I need to: {need}")) <= 255


# ---- the key and the wheel ---------------------------------------------------------------------------------------------
def test_hold_point_release_says_the_message(style):
    g = game(style)
    say_slot(g, 0, 90)                                          # straight up = slot 1
    assert sent(g) == [("Hey there! o/", "SAY")], "no party: everybody nearby"
    wheel = g.wheel()
    assert wheel[0].shown is False, "the wheel closes after sending"


def test_in_a_party_it_goes_to_the_party(style):
    g = game(style)
    g.join_party(["Anna"])
    say_slot(g, 90, 0)                                          # right = slot 3
    assert sent(g) == [("I need to: Wolf slain 3/8, Wolf Pelt 0/4 [Wolves Among Us] and [A Personal Quest]", "PARTY")]


def test_releasing_in_the_middle_closes_without_saying_anything(style):
    g = game(style)
    open_wheel(g)
    g.advance(0.6)
    point(g, 5, 5)
    key_up(g)
    assert sent(g) == [] and g.wheel()[0].shown is False


def test_a_quick_tap_keeps_the_wheel_open_for_a_click(style):
    g = game(style)
    open_wheel(g)
    g.advance(0.1)
    key_up(g)
    frame = g.wheel()[0]
    assert frame.shown is True and sent(g) == []
    point(g, -90, 0)                                            # left = slot 7 ("Follow me!")
    g.eval("function(f) f.scripts.OnMouseUp(f, 'LeftButton') end")(frame)
    assert sent(g) == [("Follow me!", "SAY")] and frame.shown is False


def test_right_click_and_pressing_the_key_again_close_it(style):
    g = game(style)
    open_wheel(g)
    frame = g.wheel()[0]
    g.eval("function(f) f.scripts.OnMouseUp(f, 'RightButton') end")(frame)
    assert frame.shown is False
    open_wheel(g)
    key_down(g)
    assert frame.shown is False and sent(g) == []
    assert "QuestSharingQuickChat" in list(g.eval("UISpecialFrames").values()), "Esc closes it"


def test_toggle_mode_waits_for_a_click(style):
    g = game(style)
    g.slash("quick mode toggle")
    open_wheel(g)
    g.advance(1)
    point(g, 0, 90)
    key_up(g)                                                   # releasing does nothing in this mode
    frame = g.wheel()[0]
    assert frame.shown is True and sent(g) == []
    g.eval("function(f) f.scripts.OnMouseUp(f, 'LeftButton') end")(frame)
    assert sent(g) == [("Hey there! o/", "SAY")]


def test_the_wheel_is_laid_out_around_the_pointer_and_highlights_the_slot(style):
    g = game(style)
    open_wheel(g)
    frame, labels, preview = g.wheel()
    assert frame.shown is True
    p1, p3 = labels[1].point, labels[3].point                  # (point, relativeTo, relativePoint, x, y)
    assert (round(p1[4]), round(p1[5])) == (500, 495), (p1[4], p1[5])           # slot 1: straight above the pointer
    assert (round(p3[4]), round(p3[5])) == (round(500 + 95 * 1.35), 400), (p3[4], p3[5])   # slot 3: to the right
    assert preview.text == "|cff888888point and release|r"
    g.advance(0.2)
    point(g, 90, 0)
    g.eval("function(f) f.scripts.OnUpdate(f, 0.05) end")(frame)
    assert labels[3].text.startswith("|cffffd100> ") and not labels[1].text.startswith("|cffffd100>")
    assert "Wolf slain 3/8" in preview.text, preview.text


def test_unused_slots_are_hidden(style):
    g = game(style)
    g.run("NS.db.quickItems = { 'One', 'Two', 'Three' }")
    open_wheel(g)
    _, labels, _ = g.wheel()
    assert [labels[i].shown for i in range(1, 9)] == [True, True, True, False, False, False, False, False]
    key_up(g)
    point(g, 90, -52)


def test_a_double_send_is_ignored_for_a_second(style):
    g = game(style)
    say_slot(g, 0, 90)
    say_slot(g, 0, 90, hold=0.3)
    assert len(sent(g)) == 1
    g.advance(1.2)
    say_slot(g, 0, 90)
    assert len(sent(g)) == 2


def test_switched_off_it_does_nothing_and_says_so(style):
    g = game(style)
    g.slash("quick off")
    g.run("PRINTED = {}")
    key_down(g)
    assert g.wheel()[0] is None or g.wheel()[0].shown is False
    assert "quick chat is switched off" in "\n".join(g.printed())
    g.slash("off")
    g.slash("quick on")
    key_down(g)
    assert g.wheel()[0] is None or g.wheel()[0].shown is False, "the master switch wins"



# ---- before somebody is in your party you cannot know their quests: ask, linking yours -----------------------------------
LINK102 = "|cffffff00|Hquest:102:2|h[A Personal Quest]|h|r"


def test_mine_links_your_unfinished_quests_of_this_area(style):
    g = game(style)
    r = g.eval("NS.quickResolve")
    assert r("{mine}") == f"{LINK100}, {LINK102}", "the finished quest and the other zone's quest are left out"
    g.run("for _, q in ipairs(QUESTS) do if q.id then q.complete = true end end")
    assert r("{mine}") == "my quests"


def test_mine_is_nearest_first_and_at_most_three_when_the_client_measures_distance():
    g = game("modern")
    for i in range(3):
        g.run("table.insert(QUESTS, 5, { id = %d, title = 'Extra %d', level = 4, objectives = {} })" % (310 + i, i))
    g.set_dist(q100=900, q102=500, q310=10, q311=700, q312=800)
    links = g.eval("NS.quickResolve")("{mine}").split(", ")
    assert len(links) == 3 and "Extra 0" in links[0] and "A Personal Quest" in links[1] and "Extra 1" in links[2]


def test_with_a_stranger_the_message_is_a_question_that_links_your_quests(style):
    g = game(style)
    assert g.eval("NS.quickResolve")("{shared}") == f"Are you doing any of these quests here? {LINK100}, {LINK102} Want to do them together?"
    g.run("for _, q in ipairs(QUESTS) do if q.id then q.complete = true end end")
    assert g.eval("NS.quickResolve")("{shared}") == "Are you questing around here? Want to team up?"


def test_in_a_party_the_same_message_reports_what_you_have_in_common(style):
    g = game(style)
    g.join_party(["Anna"])
    r = g.eval("NS.quickResolve")
    assert r("{shared}") == f"No quest in common yet - I'm on {LINK100}, {LINK102}. Any of these yours?"
    g.run('ON_QUEST["party1"] = {[100] = true}')
    assert r("{shared}") == f"We have these quests in common: {LINK100}"
    g.run('ON_QUEST["party1"] = {}; for _, q in ipairs(QUESTS) do if q.id then q.complete = true end end')
    assert r("{shared}") == "No quest in common yet - what are you working on here?"


def test_the_fourth_slot_of_the_wheel_asks_a_stranger(style):
    g = game(style)
    say_slot(g, 64, -64)                                         # lower right = slot 4
    assert sent(g) == [(f"Are you doing any of these quests here? {LINK100}, {LINK102} Want to do them together?", "SAY")]


def test_the_old_fourth_default_is_updated_but_your_own_list_is_not(style):
    g = Game(style, fresh=True)
    old = "We have these quests in common: {common}"
    g.run("QuestSharingDB = { dbVersion = 2, quickItems = { 'Hello', '%s', 'Mine' } }" % old)
    g.fire("ADDON_LOADED", "QuestSharing")
    assert items(g) == ["Hello", "{shared}", "Mine"]
    g.run("QuestSharingDB = { dbVersion = 2, quickItems = { 'We have these quests in common: {common} :)' } }")
    g.fire("ADDON_LOADED", "QuestSharing")
    assert items(g) == ["We have these quests in common: {common} :)"], "a message you changed is left alone"
    assert g.eval("NS.defaultQuickItems()[4]") == "{shared}"


def test_three_long_quest_titles_still_fit_one_message(style):
    g = game(style)
    g.run("QUESTS = {{ header = 'Elwynn Forest' }}")
    for i in range(3):
        g.run("QUESTS[#QUESTS+1] = { id = %d, title = '%s', level = 9, objectives = {} }" % (900 + i, "A very long quest title indeed " * 3 + str(i)))
    assert len(g.eval("NS.quickResolve")("{shared}")) <= 255


# ---- channels ------------------------------------------------------------------------------------------------------------
def test_channels(style):
    g = game(style)
    g.join_party(["Anna"])
    g.run("INSTANCE_GROUP = true")
    say_slot(g, 0, 90)
    assert sent(g)[-1][1] == "INSTANCE_CHAT"
    g.run("INSTANCE_GROUP = false")
    g.slash("quick channel say")
    g.advance(2)
    say_slot(g, 0, 90)
    assert sent(g)[-1][1] == "SAY"
    g.slash("quick channel whisper")
    g.advance(2)
    g.run("PRINTED = {}")
    say_slot(g, 0, 90)
    assert len(sent(g)) == 2 and "target a player first" in "\n".join(g.printed())
    g.run('TARGET = { name = "Lia", player = true }')
    g.advance(2)
    say_slot(g, 0, 90)
    assert sent(g)[-1] == ("Hey Lia! o/", "WHISPER") and g.eval("SENT[#SENT].target") == "Lia"
    g.slash("quick channel party")
    g.leave_party()
    g.advance(2)
    g.run("PRINTED = {}")
    say_slot(g, 0, 90)
    assert len(sent(g)) == 3 and "not in a party" in "\n".join(g.printed())


# ---- editing the messages ---------------------------------------------------------------------------------------------------
def items(g):
    return list(g.eval("NS.db.quickItems").values())


def test_the_default_messages_and_their_limit(style):
    g = game(style)
    assert items(g)[:3] == ["Hey {name}! o/", "Want to quest together here? ({here})", "I need to: {need}"] and len(items(g)) == 8
    g.slash("quick add one too many")
    assert len(items(g)) == 8 and "holds 8 messages" in "\n".join(g.printed())


def test_add_edit_remove_move_reset(style):
    g = game(style)
    g.slash("quick remove 8")
    g.slash("quick remove 7")
    g.slash("quick add Anyone need a hand with {quest}?")
    assert items(g)[-1] == "Anyone need a hand with {quest}?" and len(items(g)) == 7
    g.slash("quick edit 1 Hi {name}, nice to meet you")
    assert items(g)[0] == "Hi {name}, nice to meet you"
    g.slash("quick move 7 1")
    assert items(g)[0] == "Anyone need a hand with {quest}?" and items(g)[1] == "Hi {name}, nice to meet you"
    g.slash("quick remove 1")
    assert len(items(g)) == 6 and items(g)[0] == "Hi {name}, nice to meet you"
    g.slash("quick reset")
    assert items(g)[0] == "Hey {name}! o/" and len(items(g)) == 8
    assert g.eval("QuestSharingDB.quickItems[1]") == "Hey {name}! o/", "kept in the saved settings"


def test_bad_edits_are_refused_politely(style):
    g = game(style)
    before = items(g)
    for cmd in ("quick edit 99 hello", "quick remove 99", "quick move 1 99", "quick move 9 1", "quick edit 1", "quick add   ",
                "quick add " + "x" * 201, "quick edit 1 " + "y" * 201):
        g.slash(cmd)
    assert items(g) == before
    g.run("PRINTED = {}")
    g.slash("quick nonsense")
    assert "/qs quick [list]" in "\n".join(g.printed())


def test_defaults_are_a_fresh_copy_each_time(style):
    g = Game(style, fresh=True)
    g.run("QuestSharingDB = { dbVersion = 2 }")                  # a save from before quick chat existed
    g.fire("ADDON_LOADED", "QuestSharing")
    assert len(items(g)) == 8
    g.slash("quick edit 1 changed")
    assert g.eval("NS.defaultQuickItems()[1]") == "Hey {name}! o/", "editing never changes the defaults"
    g.run("QuestSharingDB = { dbVersion = 2, quickItems = { 'mine' } }")
    g.fire("ADDON_LOADED", "QuestSharing")
    assert items(g) == ["mine"], "your own list is never replaced"


# ---- the key binding ---------------------------------------------------------------------------------------------------------
def test_bindings_file_is_valid_and_calls_the_wheel(style):
    root = ET.parse(ADDON_DIR / "Bindings.xml").getroot()
    b = root.find("Binding")
    assert b.get("name") == "QUESTSHARING_QUICKCHAT" and b.get("runOnUp") == "true" and b.get("header") == "QUESTSHARING"
    g = game(style)
    assert g.eval("BINDING_HEADER_QUESTSHARING") == "Quest Sharing" and "Quick chat" in g.eval("BINDING_NAME_QUESTSHARING_QUICKCHAT")
    run = g.eval("function(code, state) local f = assert(loadstring(code)); setfenv(f, setmetatable({ keystate = state }, { __index = _G })); f() end")
    g.cursor(*CENTER)
    run(b.text, "down")
    assert g.wheel()[0].shown is True
    g.advance(0.6)
    point(g, 0, 90)
    run(b.text, "up")
    assert sent(g) == [("Hey there! o/", "SAY")]


def test_the_key_command(style):
    g = game(style)
    g.run('BINDINGS.E = "STRAFERIGHT"')
    g.slash("key E")
    assert g.eval('BINDINGS.E') == "QUESTSHARING_QUICKCHAT" and g.eval("SAVED_BINDINGS") == 1
    text = "\n".join(g.printed())
    assert "E used to do: STRAFERIGHT" in text and "quick chat key: E" in text
    g.run("PRINTED = {}")
    g.slash("key")
    assert "quick chat key: E" in "\n".join(g.printed())
    g.slash("key v")
    assert g.eval("BINDINGS.V") == "QUESTSHARING_QUICKCHAT"
    g.slash("key none")
    assert g.eval("BINDINGS.E") is None and g.eval("BINDINGS.V") is None
    g.run("PRINTED = {}")
    g.slash("key !!")
    assert "could not bind" in "\n".join(g.printed())
    g.run("IN_COMBAT = true")
    g.slash("key V")
    assert g.eval("BINDINGS.V") is None and "cannot be changed in combat" in "\n".join(g.printed())


# ---- the editor window --------------------------------------------------------------------------------------------------------
def test_the_editor_window(style):
    g = game(style)
    g.slash("quick editor")
    ed = g.eval("NS._quickEditor()")
    assert ed.win.shown is True
    assert ed.rows[1].text.text == "|cffffffff1. Hey {name}! o/|r" and ed.rows[8].frame.shown is True
    g.eval("function(r) r.frame.scripts.OnMouseUp(r.frame, 'LeftButton') end")(ed.rows[3])
    assert ed.box.text == "I need to: {need}" and ed.rows[3].text.text.startswith("|cffffd100")
    ed.box.text = "I still need: {need}"
    g.eval("function(b) b.scripts.OnEnterPressed(b) end")(ed.box)
    assert items(g)[2] == "I still need: {need}"
    g.eval("NS.editorMove")(-1)
    assert items(g)[1] == "I still need: {need}" and ed.selected == 2
    g.eval("NS.editorMove")(1)
    g.eval("NS.editorDelete")()
    assert len(items(g)) == 7 and ed.selected is None and ed.rows[8].frame.shown is False
    g.eval("NS.editorAdd")()
    assert items(g)[-1] == "New message" and ed.selected == 8


# ---- settings, defaults, probe ------------------------------------------------------------------------------------------------
def test_defaults_and_the_settings_window(style):
    g = Game(style, fresh=True)
    g.fire("ADDON_LOADED", "QuestSharing")
    assert (g.eval("NS.db.quick"), g.eval("NS.db.quickMode"), g.eval("NS.db.quickChannel")) == (True, "hold", "auto")
    idx = lambda key: g.eval("(function() for i, r in ipairs(NS.settingRows) do if r.key == '%s' then return i end end end)()" % key)   # noqa: E731
    g.eval("NS.settingsClick")(idx("quickMode"), "LeftButton")
    g.eval("NS.settingsClick")(idx("quickChannel"), "LeftButton")
    assert (g.eval("NS.db.quickMode"), g.eval("NS.db.quickChannel")) == ("toggle", "say")
    edit = g.eval("(function() for i, r in ipairs(NS.settingRows) do if r.label and string.find(r.label, 'Edit the quick chat', 1, true) then return i end end end)()")
    g.eval("NS.settingsClick")(edit, "LeftButton")
    assert g.eval("NS._quickEditor()").win.shown is True
    g.slash("quick remove 1")
    g.slash("reset")
    assert (g.eval("NS.db.quickMode"), g.eval("NS.db.quickChannel")) == ("hold", "auto") and len(items(g)) == 8


def test_probe_and_status_mention_the_wheel(style):
    g = game(style)
    g.run("PRINTED = {}")
    g.slash("probe")
    g.slash("status")
    text = "\n".join(g.printed())
    assert "quick chat wheel: key NOT SET" in text and "an addon can set keys: yes" in text and "quick on" in text
    g.slash("key V")
    g.run("PRINTED = {}")
    g.slash("probe")
    assert "quick chat wheel: key V" in "\n".join(g.printed())


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
