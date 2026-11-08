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
LINK102 = "|cffffff00|Hquest:102:2|h[A Personal Quest]|h|r"


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


def test_three_long_quest_titles_still_fit_one_message(style):
    g = game(style)
    g.run("QUESTS = {{ header = 'Elwynn Forest' }}")
    for i in range(3):
        g.run("QUESTS[#QUESTS+1] = { id = %d, title = '%s', level = 9, objectives = {} }" % (900 + i, "A very long quest title indeed " * 3 + str(i)))
    assert len(g.eval("NS.quickResolve")("{shared}")) <= 255


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



# ---- helpers for the ring ------------------------------------------------------------------------------------------------
SLOT_DIR = {1: (0, 1), 2: (1, 1), 3: (1, 0), 4: (1, -1), 5: (0, -1), 6: (-1, -1), 7: (-1, 0), 8: (-1, 1)}


def point_slot(g, i, far=90):
    dx, dy = SLOT_DIR[i]
    point(g, dx * far, dy * far)


def tick(g):
    g.eval("function(f) f.scripts.OnUpdate(f, 0.05) end")(g.wheel()[0])


def click_slot(g, i, button="LeftButton"):
    g.eval("function(b, w) b.scripts.OnClick(b, w) end")(g.wheel()[1][i].button, button)


def hold_and_release_on(g, i, hold=0.6):
    open_wheel(g)
    g.advance(hold)
    point_slot(g, i)
    key_up(g)


def pick(g, i):
    """What a player does: hold the key, point at slot i, release; if the ring stays open (/say needs a click), click it."""
    hold_and_release_on(g, i)
    if g.wheel()[0].shown:
        click_slot(g, i)


def target(g, name="Lia"):
    g.run('TARGET = { name = "%s", player = true }' % name)


# ---- the key and the ring ---------------------------------------------------------------------------------------------------
def test_with_a_player_targeted_releasing_whispers_them(style):
    g = game(style)
    target(g)
    hold_and_release_on(g, 1)
    assert sent(g) == [("Hey Lia! o/", "WHISPER")] and g.eval("SENT[1].target") == "Lia"
    assert g.wheel()[0].shown is False, "a whisper needs no click: it went on release"


def test_in_a_party_releasing_sends_to_the_party(style):
    g = game(style)
    g.join_party(["Anna"])
    hold_and_release_on(g, 3)
    assert sent(g) == [("I need to: Wolf slain 3/8, Wolf Pelt 0/4 [Wolves Among Us] and [A Personal Quest]", "PARTY")]


def test_say_is_not_sent_on_release_but_on_a_click(style):
    g = game(style)                                             # nobody targeted, no party: it would be /say
    hold_and_release_on(g, 1)
    frame, slots, center, hint = g.wheel()
    assert sent(g) == [] and frame.shown is True, "the game only allows /say from a key press or a click"
    assert "click it" in hint.text
    click_slot(g, 1)
    assert sent(g) == [("Hey there! o/", "SAY")] and frame.shown is False


LINK = "|cffffff00|Hquest:100:3|h[Wolves Among Us]|h|r"


def test_a_long_message_is_never_cut_inside_a_quest_link(style):
    g = game(style)
    text = "x" * 230 + " {quest} and more"
    out = g.eval("NS.quickResolve")(text)
    assert len(out) <= 255 and out.endswith("...")
    assert "|H" not in out or out.count("|h") == 2, "either the whole link or none of it"
    for n in range(240, 262):                                    # wherever the limit falls, links stay whole
        cut = g.eval("NS.compat.safeCut")(("y" * n) + LINK + " tail", 255)
        assert len(cut) <= 255 and (LINK in cut or "|H" not in cut), n


def test_a_long_message_never_splits_an_accented_letter(style):
    g = game(style)
    for n in range(248, 256):
        cut = g.eval("NS.compat.safeCut")("a" * n + "è" * 10, 255)
        cut.encode("utf-8") if isinstance(cut, str) else bytes(cut).decode("utf-8")   # valid UTF-8 or this raises


def test_a_pipe_you_type_reaches_the_game_escaped(style):
    g = game(style)
    assert g.eval("NS.quickResolve")("left | right") == "left || right"
    assert g.eval("NS.quickResolve")("left || right") == "left || right", "an edit box may already give ||"
    assert g.eval("NS.quickResolve")("a {quest}") == "a " + LINK, "the links we add are left alone"
    cut = g.eval("NS.compat.safeCut")
    assert cut("z" * 251 + "||||x", 255) == "z" * 251 + "...", "half an escaped pipe at the cut is dropped"
    assert cut("z" * 250 + "||||||", 255) == "z" * 250 + "||...", "a whole escaped pipe is kept"


def test_greetings_go_to_the_people_around_you_not_to_the_party(style):
    g = game(style)
    g.join_party(["Anna"])
    pick(g, 1)                                                   # "Hello" is a nearby message: /s even in a party
    assert sent(g)[-1] == ("Hey there! o/", "SAY")
    g.advance(2)
    pick(g, 2)                                                   # "Team up?"
    assert sent(g)[-1][1] == "SAY"
    g.advance(2)
    target(g, "Lia")                                             # but a player you target is whispered
    pick(g, 1)
    assert sent(g)[-1] == ("Hey Lia! o/", "WHISPER")
    g.advance(2)
    pick(g, 3)                                                   # "What I need" still follows the party
    assert sent(g)[-1][1] == "PARTY"


def test_a_message_can_be_switched_between_auto_and_nearby(style):
    g = game(style)
    g.join_party(["Anna"])
    g.slash("quick route 3 nearby")
    pick(g, 3)
    assert sent(g)[-1][1] == "SAY", "now it is nearby"
    g.advance(2)
    g.slash("quick route 1 auto")
    pick(g, 1)
    assert sent(g)[-1][1] == "PARTY"
    assert "(nearby)" in "\n".join(g.printed()) and g.eval("NS.db.quickItems[1].channel") == "auto"
    g.slash("quick route 1 sideways")
    assert g.eval("NS.db.quickItems[1].channel") == "auto", "an unknown route changes nothing"
    g.run("NS.quickItems()")
    assert g.eval("NS.db.quickItems[1].channel") == "auto", "and the old-save upgrade does not undo your choice"


def test_the_global_channel_setting_still_overrides_every_route(style):
    g = game(style)
    g.join_party(["Anna"])
    g.slash("quick channel party")
    pick(g, 1)
    assert sent(g)[-1][1] == "PARTY", "forcing the channel wins over a message's own route"


def test_saved_messages_from_before_routes_get_them_for_the_greetings(style):
    g = game(style)
    g.run('NS.db.quickItems = { { label = "Hello", text = "Hey {name}! o/" }, { label = "Mine", text = "Hi all" }, "Want to quest together here? ({here})" }')
    g.run("NS.quickItems()")
    assert g.eval("NS.db.quickItems[1].channel") == "nearby" and g.eval("NS.db.quickItems[2].channel") is None
    assert g.eval("NS.db.quickItems[3].channel") == "nearby", "an old plain-text default too"


def test_the_editor_button_flips_the_route_of_the_selected_message(style):
    g = game(style)
    g.slash("quick editor")
    g.eval("NS.editorSelect")(3)
    g.eval("NS.editorRoute")()
    assert g.eval("NS.db.quickItems[3].channel") == "nearby"
    assert "nearby" in g.eval("NS._settingsWindow().ed.routeText.text")
    g.eval("NS.editorRoute")()
    assert g.eval("NS.db.quickItems[3].channel") == "auto" and "auto" in g.eval("NS._settingsWindow().ed.routeText.text")


def test_a_send_the_game_blocks_ends_up_in_the_chat_box_and_in_the_error_log(style):
    g = game(style)
    hold_and_release_on(g, 1)
    click_slot(g, 1)
    g.run("OPENED = {}")
    g.fire("ADDON_ACTION_FORBIDDEN", "QuestSharing", "UNKNOWN()")      # what the game says when it blocks the send
    assert g.eval("OPENED") and g.eval("OPENED[1]") == "/s Hey there! o/", "ready for Enter"
    assert "press Enter" in "\n".join(g.printed())
    err = g.eval("NS.db.errors[#NS.db.errors].msg")
    assert "UNKNOWN()" in err and "quick chat ring to SAY" in err


def test_a_blocked_whisper_is_prepared_as_a_whisper(style):
    g = game(style)
    g.run('TARGET = { name = "Lia", player = true }')
    hold_and_release_on(g, 1)
    g.run("OPENED = {}")
    g.fire("ADDON_ACTION_FORBIDDEN", "QuestSharing", "UNKNOWN()")
    assert g.eval("OPENED[1]") == "/w Lia Hey Lia! o/"


def test_a_block_that_has_nothing_to_do_with_the_ring_is_only_logged(style):
    g = game(style)
    g.run("OPENED = {}")
    g.fire("ADDON_ACTION_FORBIDDEN", "QuestSharing", "SetSuperTrackedQuestID()")
    assert g.eval("#OPENED") == 0
    assert "SetSuperTrackedQuestID()" in g.eval("NS.db.errors[#NS.db.errors].msg")
    g.fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "X()")           # another addon's trouble is not ours
    assert g.eval("#NS.db.errors") == 1


def test_an_old_send_is_not_blamed_for_a_later_block(style):
    g = game(style)
    hold_and_release_on(g, 1)
    click_slot(g, 1)
    g.advance(5)
    g.run("OPENED = {}")
    g.fire("ADDON_ACTION_FORBIDDEN", "QuestSharing", "UNKNOWN()")
    assert g.eval("#OPENED") == 0


def test_pressing_the_key_again_says_what_is_pointed_at(style):
    g = game(style)
    hold_and_release_on(g, 7)
    assert sent(g) == []
    key_down(g)                                                 # a key PRESS is a real input
    assert sent(g) == [("Follow me!", "SAY")] and g.wheel()[0].shown is False


def test_pressing_the_key_again_with_nothing_pointed_at_just_closes(style):
    g = game(style)
    open_wheel(g)
    key_down(g)
    assert sent(g) == [] and g.wheel()[0].shown is False


def test_a_quick_tap_keeps_the_ring_open_for_a_click(style):
    g = game(style)
    open_wheel(g)
    g.advance(0.1)
    key_up(g)
    frame = g.wheel()[0]
    assert frame.shown is True and sent(g) == []
    point_slot(g, 7)
    click_slot(g, 7)
    assert sent(g) == [("Follow me!", "SAY")] and frame.shown is False


def test_releasing_in_the_middle_closes_without_saying_anything(style):
    g = game(style)
    open_wheel(g)
    g.advance(0.6)
    point(g, 5, 5)
    key_up(g)
    assert sent(g) == [] and g.wheel()[0].shown is False


def test_a_right_click_a_click_outside_and_escape_close_it(style):
    g = game(style)
    open_wheel(g)
    click_slot(g, 2, "RightButton")
    assert g.wheel()[0].shown is False and sent(g) == []
    open_wheel(g)
    frame = g.wheel()[0]
    g.eval("function(f) f.scripts.OnMouseUp(f, 'LeftButton') end")(frame)
    assert frame.shown is False and sent(g) == []
    assert "QuestSharingQuickChat" in list(g.eval("UISpecialFrames").values()), "Esc closes it"


def test_toggle_mode_waits_for_a_click(style):
    g = game(style)
    target(g)
    g.slash("quick mode toggle")
    open_wheel(g)
    g.advance(1)
    point_slot(g, 1)
    key_up(g)                                                   # releasing does nothing in this mode
    assert g.wheel()[0].shown is True and sent(g) == []
    click_slot(g, 1)
    assert sent(g) == [("Hey Lia! o/", "WHISPER")]


def test_the_ring_is_laid_out_cleanly_around_the_pointer(style):
    g = game(style)
    open_wheel(g)
    frame, slots, center, hint = g.wheel()
    where = lambda i: (round(slots[i].button.point[4]), round(slots[i].button.point[5]))   # noqa: E731
    assert [where(i) for i in (1, 3, 5, 7)] == [(500, 518), (618, 400), (500, 282), (382, 400)]
    assert [slots[i].label.point[1] for i in (1, 3, 5, 7)] == ["BOTTOM", "LEFT", "TOP", "RIGHT"], "labels sit outside the ring"
    assert [slots[i].label.point[3] for i in (1, 3, 5, 7)] == ["TOP", "RIGHT", "BOTTOM", "LEFT"]
    assert all(slots[i].button.shown for i in range(1, 9))
    assert [slots[i].label.text for i in (1, 2)] == ["|cffffffffHello|r", "|cffffffffTeam up?|r"], "short labels, not whole sentences"


def test_the_ring_never_runs_off_the_screen(style):
    g = game(style)
    open_wheel(g, at=(10, 10))
    slots = g.wheel()[1]
    xs = [slots[i].button.point[4] for i in range(1, 9)]
    ys = [slots[i].button.point[5] for i in range(1, 9)]
    assert min(xs) > 0 and min(ys) > 0
    key_down(g)
    g.cursor(1915, 1075)
    key_down(g)
    open_wheel(g, at=(1915, 1075))
    slots = g.wheel()[1]
    assert max(slots[i].button.point[4] for i in range(1, 9)) < 1920 and max(slots[i].button.point[5] for i in range(1, 9)) < 1080


def test_pointing_highlights_a_slot_and_shows_the_whole_message_in_the_middle(style):
    g = game(style)
    open_wheel(g)
    g.advance(0.2)
    point_slot(g, 3)
    tick(g)
    frame, slots, center, hint = g.wheel()
    assert slots[3].label.text.startswith("|cffffd100") and slots[1].label.text.startswith("|cffffffff")
    assert "Wolf slain 3/8" in center.text, center.text
    point_slot(g, 1)
    tick(g)
    assert slots[1].label.text.startswith("|cffffd100") and slots[3].label.text.startswith("|cffffffff")


def test_unused_slots_are_hidden(style):
    g = game(style)
    g.run("NS.db.quickItems = { { label = 'One', text = 'one' }, { label = 'Two', text = 'two' }, { label = 'Three', text = 'three' } }")
    open_wheel(g)
    slots = g.wheel()[1]
    assert [slots[i].button.shown for i in range(1, 9)] == [True, True, True, False, False, False, False, False]


def test_a_double_send_is_ignored_for_a_second(style):
    g = game(style)
    target(g)
    hold_and_release_on(g, 1)
    hold_and_release_on(g, 1, hold=0.3)
    assert len(sent(g)) == 1
    g.advance(1.2)
    hold_and_release_on(g, 1)
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


def test_the_fourth_slot_of_the_ring_asks_a_stranger(style):
    g = game(style)
    pick(g, 4)
    assert sent(g) == [(f"Are you doing any of these quests here? {LINK100}, {LINK102} Want to do them together?", "SAY")]


def test_the_invite_slot_invites_and_whispers(style):
    g = game(style)
    target(g)
    hold_and_release_on(g, 8)
    assert g.invited() == [], "an invite is not allowed from a release either"
    assert g.wheel()[0].shown is True
    click_slot(g, 8)
    assert g.invited() == ["Lia"] and sent(g) == [("Sending you a party invite - let's quest together!", "WHISPER")]


# ---- where it goes ------------------------------------------------------------------------------------------------------------
def test_channels(style):
    g = game(style)
    pick(g, 3)                                                   # "What I need" is an auto message; no party, no target
    assert sent(g)[-1][1] == "SAY"
    g.advance(2)
    g.join_party(["Anna"])
    pick(g, 3)
    assert sent(g)[-1][1] == "PARTY"
    g.advance(2)
    g.run("INSTANCE_GROUP = true")
    pick(g, 3)
    assert sent(g)[-1][1] == "INSTANCE_CHAT"
    g.run("INSTANCE_GROUP = false")
    g.advance(2)
    target(g, "Lia")                                             # in a party the party comes first, target or not
    pick(g, 3)
    assert sent(g)[-1][1] == "PARTY"
    g.leave_party()
    g.advance(2)
    pick(g, 3)                                                   # alone with a target: /w
    assert sent(g)[-1][1] == "WHISPER" and g.eval("SENT[#SENT].target") == "Lia"
    g.run("TARGET = nil")
    g.advance(2)
    pick(g, 3)                                                   # alone, nobody targeted: /s
    assert sent(g)[-1][1] == "SAY"
    target(g, "Lia")
    g.join_party(["Anna"])
    g.slash("quick channel say")
    g.advance(2)
    pick(g, 1)
    assert sent(g)[-1][1] == "SAY"
    g.slash("quick channel party")
    g.leave_party()
    g.advance(2)
    g.run("PRINTED = {}")
    pick(g, 1)
    assert "not in a party" in "\n".join(g.printed())
    g.slash("quick channel whisper")
    g.run("TARGET = nil")
    g.advance(2)
    g.run("PRINTED = {}")
    pick(g, 1)
    assert "target a player first to whisper" in "\n".join(g.printed())


def test_a_cross_realm_target_is_whispered_with_the_realm(style):
    g = game(style)
    target(g, "Lia")
    g.run('function UnitName(u) if u == "target" then return "Lia", "Draenor" end if u == "player" then return "Me" end end')
    hold_and_release_on(g, 5)
    assert g.eval("SENT[1].target") == "Lia-Draenor"


# ---- editing the messages ---------------------------------------------------------------------------------------------------------
def items(g):
    return [(v.label, v.text) for v in g.eval("NS.db.quickItems").values()]


def test_the_default_messages_have_short_labels_and_there_are_eight(style):
    g = game(style)
    its = items(g)
    assert len(its) == 8 and its[0] == ("Hello", "Hey {name}! o/") and its[3] == ("Same quests?", "{shared}")
    assert all(len(label) <= 14 for label, _ in its)
    g.slash("quick add one too many")
    assert len(items(g)) == 8 and "holds 8 messages" in "\n".join(g.printed())


def test_add_edit_label_remove_move_reset(style):
    g = game(style)
    g.slash("quick remove 8")
    g.slash("quick remove 7")
    g.slash("quick add Anyone need a hand with {quest}?")
    assert items(g)[-1] == ("Anyone need a", "Anyone need a hand with {quest}?"), "the label is made from the first words"
    g.slash("quick add Help | Can you help me with {quest}?")
    assert items(g)[-1] == ("Help", "Can you help me with {quest}?")
    g.slash("quick edit 1 Hi {name}, nice to meet you")
    g.slash("quick label 1 Greet")
    assert items(g)[0] == ("Greet", "Hi {name}, nice to meet you")
    g.slash("quick move 8 1")
    assert items(g)[0][0] == "Help" and items(g)[1][0] == "Greet"
    g.slash("quick remove 1")
    assert len(items(g)) == 7 and items(g)[0][0] == "Greet"
    g.slash("quick reset")
    assert items(g)[0] == ("Hello", "Hey {name}! o/") and len(items(g)) == 8
    assert g.eval("QuestSharingDB.quickItems[1].text") == "Hey {name}! o/", "kept in the saved settings"


def test_labels_are_cut_to_fourteen_letters(style):
    g = game(style)
    g.slash("quick remove 8")
    g.slash("quick add A very very long label indeed | some text")
    assert len(items(g)[-1][0]) <= 14
    g.slash("quick label 1 " + "z" * 40)
    assert items(g)[0][0] == "z" * 14


def test_bad_edits_are_refused_politely(style):
    g = game(style)
    before = items(g)
    for cmd in ("quick edit 99 hello", "quick remove 99", "quick move 1 99", "quick move 9 1", "quick edit 1", "quick add   ",
                "quick add " + "x" * 201, "quick edit 1 " + "y" * 201, "quick label 99 hello", "quick label 1  "):
        g.slash(cmd)
    assert items(g) == before
    g.run("PRINTED = {}")
    g.slash("quick nonsense")
    assert "/qs quick [list]" in "\n".join(g.printed())


def test_lists_saved_by_earlier_versions_are_converted(style):
    g = Game(style, fresh=True)
    g.run("QuestSharingDB = { dbVersion = 2, quickItems = { 'Hello', 'We have these quests in common: {common}', 'Hey {name}! o/' } }")
    g.fire("ADDON_LOADED", "QuestSharing")
    assert items(g) == [("Hello", "Hello"), ("Same quests?", "{shared}"), ("Hello", "Hey {name}! o/")]
    g.run("QuestSharingDB = { dbVersion = 2, quickItems = { { label = 'Mine', text = 'My own' } } }")
    g.fire("ADDON_LOADED", "QuestSharing")
    assert items(g) == [("Mine", "My own")], "your own list is never replaced"


def test_defaults_are_a_fresh_copy_each_time(style):
    g = Game(style, fresh=True)
    g.run("QuestSharingDB = { dbVersion = 2 }")                  # a save from before quick chat existed
    g.fire("ADDON_LOADED", "QuestSharing")
    assert len(items(g)) == 8
    g.slash("quick edit 1 changed")
    assert g.eval("NS.defaultQuickItems()[1].text") == "Hey {name}! o/", "editing never changes the defaults"


# ---- the key binding ---------------------------------------------------------------------------------------------------------------
def test_bindings_file_is_valid_and_calls_the_ring(style):
    root = ET.parse(ADDON_DIR / "Bindings.xml").getroot()
    b = root.find("Binding")
    assert b.get("name") == "QUESTSHARING_QUICKCHAT" and b.get("runOnUp") == "true" and b.get("header") == "QUESTSHARING"
    g = game(style)
    target(g)
    assert g.eval("BINDING_HEADER_QUESTSHARING") == "Quest Sharing" and "Quick chat" in g.eval("BINDING_NAME_QUESTSHARING_QUICKCHAT")
    run = g.eval("function(code, state) local f = assert(loadstring(code)); setfenv(f, setmetatable({ keystate = state }, { __index = _G })); f() end")
    g.cursor(*CENTER)
    run(b.text, "down")
    assert g.wheel()[0].shown is True
    g.advance(0.6)
    point_slot(g, 1)
    run(b.text, "up")
    assert sent(g) == [("Hey Lia! o/", "WHISPER")]


# ---- the settings window's editor ------------------------------------------------------------------------------------------------------
def editor(g):
    return g.eval("NS._settingsWindow()").ed


def test_the_editor_lives_in_the_quick_chat_tab(style):
    g = game(style)
    g.slash("quick editor")
    W = g.eval("NS._settingsWindow()")
    ed = W.ed
    assert W.win.shown is True and W.tab == "quick" and ed.frame.shown is True
    assert ed.lines[1].text.text == "|cffffffff1.  [Hello]  Hey {name}! o/  |cff88ccff/s|r|r" and ed.lines[8].frame.shown is True
    g.eval("function(l) l.frame.scripts.OnMouseUp(l.frame, 'LeftButton') end")(ed.lines[3])
    assert ed.labelBox.text == "What I need" and ed.textBox.text == "I need to: {need}" and ed.lines[3].text.text.startswith("|cffffd100")
    assert "Looks like:" in ed.preview.text and "Wolf slain 3/8" in ed.preview.text
    ed.labelBox.text, ed.textBox.text = "My needs", "I still need: {need}"
    g.eval("function(b) b.scripts.OnEnterPressed(b) end")(ed.textBox)
    assert items(g)[2] == ("My needs", "I still need: {need}")
    g.eval("NS.editorMove")(-1)
    assert items(g)[1][0] == "My needs" and ed.selected == 2
    g.eval("NS.editorMove")(1)
    g.eval("NS.editorDelete")()
    assert len(items(g)) == 7 and ed.selected is None and ed.lines[8].frame.shown is False
    g.eval("NS.editorAdd")()
    assert items(g)[-1] == ("New", "New message") and ed.selected == 8
    g.eval("NS.editorReset")()
    assert len(items(g)) == 8 and items(g)[0][0] == "Hello"


def test_show_the_ring_button_opens_it_in_the_middle_of_the_screen(style):
    g = game(style)
    g.slash("quick editor")
    g.eval("NS.quickOpen")(True)
    frame, slots, _, _ = g.wheel()
    assert frame.shown is True
    assert (round(slots[1].button.point[4]), round(slots[1].button.point[5])) == (960, 540 + 118)
    key_up(g)
    assert frame.shown is True, "the preview stays open until you click or press Esc"


# ---- settings, defaults ----------------------------------------------------------------------------------------------------------------
def test_defaults_and_the_settings_window(style):
    g = Game(style, fresh=True)
    g.fire("ADDON_LOADED", "QuestSharing")
    assert (g.eval("NS.db.quick"), g.eval("NS.db.quickMode"), g.eval("NS.db.quickChannel")) == (True, "hold", "auto")
    idx = lambda key: g.eval("(function() for i, r in ipairs(NS.settingRows) do if r.key == '%s' then return i end end end)()" % key)   # noqa: E731
    g.eval("NS.settingsClick")(idx("quickMode"), "LeftButton")
    g.eval("NS.settingsClick")(idx("quickChannel"), "LeftButton")
    assert (g.eval("NS.db.quickMode"), g.eval("NS.db.quickChannel")) == ("toggle", "say")
    g.slash("quick remove 1")
    g.slash("reset")
    assert (g.eval("NS.db.quickMode"), g.eval("NS.db.quickChannel")) == ("hold", "auto") and len(items(g)) == 8


# ---- it must not lag the game -------------------------------------------------------------------------------------------------------------
def test_using_the_ring_costs_almost_nothing(style):
    g = game(style)
    g.join_party(["Anna"])
    g.run('ON_QUEST["party1"] = {[100] = true}')
    g.run("CALLS.GetInfo = 0")
    open_wheel(g)
    frame, slots, center, hint = g.wheel()
    for step in range(120):                                     # two seconds of waving the mouse around all eight slots
        point_slot(g, (step // 4) % 8 + 1, far=60 + step % 40)
        tick(g)
    entries_scan = 6                                            # header + quests in the mock's quest log
    calls = g.eval("CALLS.GetInfo")
    assert calls <= entries_scan * 40, f"{calls} quest-log reads for one use of the ring"
    # old behaviour for comparison: every slot filled in every 0.03 s would be 8 slots x 66 ticks x several scans
    assert calls < 8 * 66 * entries_scan / 10


def test_nothing_is_repainted_while_the_pointer_stays_on_one_slot(style):
    g = game(style)
    open_wheel(g)
    point_slot(g, 3)
    tick(g)
    frame, slots, center, hint = g.wheel()
    before = (slots[3].label.sets, center.sets)
    for step in range(50):
        point_slot(g, 3, far=70 + step % 20)
        tick(g)
    assert (slots[3].label.sets, center.sets) == before


def test_a_closed_ring_costs_nothing(style):
    g = game(style)
    g.advance(5)                                                # let the addon's own start-up work finish
    open_wheel(g)
    key_down(g)                                                 # opens and closes it
    g.run("CALLS.GetInfo = 0")
    g.advance(30)
    assert g.eval("CALLS.GetInfo") == 0, "a closed ring runs no code at all"


def test_the_whole_addon_idle_with_everything_on_stays_light(style):
    """The heaviest realistic state: a party, the tracker and the pin following you, the panel and the nameplate icons on."""
    g = Game(style, fresh=True)
    g.fire("ADDON_LOADED", "QuestSharing")
    g.fire("PLAYER_ENTERING_WORLD")
    g.run('ON_QUEST["party1"] = {[100] = true}')
    g.join_party(["Anna", "Bob"])
    if style == "modern":
        g.set_dist(q100=400, q101=900, q102=2500, q200=10000)
        g.run('ADD_PLATE("nameplate1", true)')
    g.advance(40)
    g.run("CALLS.GetInfo = 0")
    g.advance(60)
    scans = g.eval("CALLS.GetInfo") / 6                         # the mock's quest log has 6 lines
    assert scans <= 80, f"{scans:.0f} quest-log scans in one idle minute"
    g.slash("near off")
    g.slash("panel off")
    g.run("CALLS.GetInfo = 0")
    g.advance(60)
    assert g.eval("CALLS.GetInfo") == 0, "with the tracker and the panel off the addon reads nothing while idle"


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
