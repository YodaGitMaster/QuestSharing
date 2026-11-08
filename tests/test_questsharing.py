"""Tests of the real addon files, run in Lua 5.1 against a mock of the WoW API, for both the modern
(C_QuestLog) and the classic (GetQuestLogTitle) quest APIs.     python tests/test_questsharing.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")
LINK100 = "|cffffff00|Hquest:100:3|h[Wolves Among Us]|h|r"
LINK101 = "|cffffff00|Hquest:101:2|h[Report to Goldshire]|h|r"
LEFT100 = "still need: Wolf slain 3/8, Wolf Pelt 0/4"
MODERN_TRACKER = "QUEST_TRACKER_MODULE = { OnBlockHeaderClick = function() end }"


def party_game(style, names=("Anna",), on_quest=None, pre=""):
    """A started game with a party already formed and the settle time passed (nothing pushed yet)."""
    g = Game(style, pre)
    g.start()
    for unit, ids in (on_quest or {}).items():
        for qid in ids:
            g.run(f'ON_QUEST["{unit}"] = ON_QUEST["{unit}"] or {{}}; ON_QUEST["{unit}"][{qid}] = true')
    g.join_party(list(names))
    return g


# ---- quest log ---------------------------------------------------------------------------------
def test_entries_headers_completion_and_area(style):
    g = Game(style)
    rows = g.eval("(function() local t = {} for _, e in ipairs(NS.compat.entries()) do "
                  "t[#t+1] = e.questID .. '|' .. e.header .. '|' .. tostring(e.complete) .. '|' .. tostring(NS.compat.inArea(e)) end "
                  "return table.concat(t, ';') end)()").split(";")
    assert rows == ["100|Elwynn Forest|false|true", "101|Elwynn Forest|true|true",
                    "102|Elwynn Forest|false|true", "200|Westfall|false|false"], rows


def test_objective_text_parsing(style):
    g = Game(style)
    parse = g.eval("NS.compat.parseObjective")
    assert tuple(parse("Wolf slain: 3/8")) == ("Wolf slain", 3, 8)
    assert tuple(parse("3/8 Wolf slain")) == ("Wolf slain", 3, 8)
    assert tuple(parse("Speak with the Marshal")) == ("Speak with the Marshal", None, None)


# ---- the status message --------------------------------------------------------------------------
def entry(g, qid):
    return g.eval(f"NS.compat.findEntry({qid})")


def test_status_in_progress_and_done(style):
    g = Game(style)
    e = entry(g, 100)
    assert g.eval("NS.statusText")(e)[0] == LEFT100
    text, done = g.eval("NS.statusText")(entry(g, 101))
    assert done is True and text == "I'm done with this one, ready to turn in!"
    assert g.eval("NS.statusMessage")(e) == f"{LINK100} - {LEFT100}"        # nobody else has it: no icon


def test_status_gets_icon_and_names_when_party_has_the_quest(style):
    g = party_game(style, ("Anna", "Bob"), on_quest={"party1": [100]})
    assert g.eval("NS.statusMessage")(entry(g, 100)) == f"{{rt1}} {LINK100} - {LEFT100} (Anna has it too!)"
    g.run('ON_QUEST["party2"] = {[100] = true}')
    assert g.eval("NS.statusMessage")(entry(g, 100)).endswith("(Anna, Bob have it too!)")
    assert g.eval("NS.statusMessage")(entry(g, 101)) == f"{LINK101} - I'm done with this one, ready to turn in!"


def test_status_always_fits_one_chat_message(style):
    g = Game(style)
    objs = ", ".join('{ text = "Rare Herb Number %d: 0/10", finished = false, numFulfilled = 0, numRequired = 10 }' % i for i in range(40))
    g.run("QUESTS[#QUESTS+1] = { id = 300, title = 'Huge', level = 5, objectives = { %s } }" % objs)
    msg = g.eval("NS.statusMessage")(entry(g, 300))
    assert len(msg) <= 255 and "...|" not in msg and "..." in msg and msg.startswith("|cffffff00|Hquest:300:5"), (len(msg), msg)


# ---- sharing when a party forms ----------------------------------------------------------------------
def test_joining_a_party_shares_the_zone_quests_one_by_one(style):
    g = Game(style)
    initial = 200 if style == "modern" else 6                         # the player had Westfall's quest open
    g.run(f"SELECTED = {initial}")
    g.start()
    g.join_party(["Anna"])
    g.advance(4.8)
    assert g.pushed() == [], "waits for the party to settle"
    g.advance(0.6)
    assert g.pushed() == [100]
    g.advance(3.0)
    assert g.pushed() == [100], "one quest every 4 seconds"
    g.advance(1.5)
    assert g.pushed() == [100, 101]
    g.advance(30)
    assert g.pushed() == [100, 101], "102 cannot be shared, 200 is in another zone"
    assert g.eval("SELECTED") == initial, "the player's own quest-log selection is put back"


def test_login_inside_a_party_does_not_share(style):
    g = Game(style)
    g.run('SET_PARTY({"Anna"})')
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(30)
    assert g.pushed() == []
    g.join_party(["Anna", "Bob"])                                       # but a new member does
    g.advance(6)
    assert g.pushed() == [100]


def test_quests_everyone_has_are_not_pushed_but_announced(style):
    g = party_game(style, on_quest={"party1": [100]})
    g.advance(60)
    assert g.pushed() == [101], g.pushed()
    sent = g.sent()
    assert sent == [(f"Hey Anna! Looks like we have these quests in common: {LINK100} Let's do them together :)", "PARTY")], sent


def test_a_false_from_the_game_is_not_trusted(style):
    g = party_game(style)                                               # API says "not on it" for everything
    g.advance(8)
    assert g.pushed() == [100, 101][:len(g.pushed())] and 100 in g.pushed()


def test_already_on_that_quest_reply_means_in_common(style):
    g = party_game(style)
    g.advance(5.3)
    assert g.pushed() == [100]
    g.reply("Sharing quest with Anna.")                                 # info only
    g.reply("Anna is already on that quest.")
    g.advance(60)
    assert g.pushed() == [100, 101]
    sent = g.sent()
    assert len(sent) == 1 and LINK100 in sent[0][0] and LINK101 not in sent[0][0] and "Anna" in sent[0][0], sent


def test_accepted_declined_and_the_other_replies(style):
    g = party_game(style, ("Anna", "Bob", "Cy", "Dee"))
    g.advance(5.3)
    for line in ("Anna has accepted your quest.", "Bob has declined your quest.", "Cy has already completed that quest.",
                 "Dee is busy.", "Eve's quest log is full.", "Anna has come online."):
        g.reply(line)
    assert (g.eval("NS.known[100].anna"), g.eval("NS.known[100].bob"), g.eval("NS.known[100].cy"), g.eval("NS.known[100].dee")) == \
        ("accepted", "declined", "done", "busy"), "every answer is understood"
    assert not any(w in "\n".join(g.printed()) for w in ("Anna accepted", "Bob declined", "come online")), \
        "no line per answer: that was a lot of chat"
    g.advance(60)
    text = "\n".join(g.printed())
    assert "shared 2 quests with the party: Anna took 1, 1 declined, 2 could not take it right now" in text, text
    assert g.sent() == [], "accepted / declined are not 'in common'"
    assert tuple(g.eval("NS.partyHas")(entry(g, 100)).values()) == ("Anna",), "who accepted now has the quest"


def test_replies_belong_to_the_quest_pushed_last(style):
    g = party_game(style)
    g.advance(5.3)
    g.reply("Anna has declined your quest.")                            # about quest 100
    g.advance(4.2)
    assert g.pushed() == [100, 101]
    g.reply("Anna has accepted your quest.")                            # about quest 101
    assert g.eval("NS.known[100].anna") == "declined" and g.eval("NS.known[101].anna") == "accepted"


def test_instance_groups_use_instance_chat(style):
    g = party_game(style, on_quest={"party1": [100]})
    g.run("INSTANCE_GROUP = true")
    g.advance(60)
    assert g.sent()[0][1] == "INSTANCE_CHAT"


def test_raids_are_not_supported(style):
    g = Game(style)
    g.start()
    g.run("RAID = true")
    g.join_party(["Anna"])
    g.advance(20)
    assert g.pushed() == [] and g.sent() == []
    g.slash("share")
    assert g.pushed() == [] and "5-player party" in "\n".join(g.printed())


def test_switched_off_does_nothing(style):
    g = Game(style)
    g.start()
    g.slash("off")
    g.join_party(["Anna"])
    g.advance(30)
    assert g.pushed() == [] and g.sent() == []


def test_manual_share_when_auto_is_off(style):
    g = Game(style)
    g.start()
    g.slash("auto off")
    g.join_party(["Anna"])
    g.advance(30)
    assert g.pushed() == []
    g.slash("share")
    assert g.pushed() == [100]


def test_stop_cancels_a_running_share(style):
    g = party_game(style)
    g.advance(5.3)
    g.slash("stop")
    g.advance(30)
    assert g.pushed() == [100] and g.eval("NS.isSharing()") is False
    assert "sharing stopped" in "\n".join(g.printed())


def test_leaving_the_party_cancels_and_forgets(style):
    g = party_game(style)
    g.advance(5.3)
    g.reply("Anna has accepted your quest.")
    g.leave_party()
    g.advance(30)
    assert g.pushed() == [100] and g.eval("NS.isSharing()") is False
    assert g.eval("next(NS.known) == nil") is True


def test_a_new_member_triggers_another_round_that_skips_what_everyone_has(style):
    g = party_game(style, on_quest={"party1": [100, 101]})
    g.advance(14)
    assert g.pushed() == []                                              # run 1: everybody already had both
    g.run('ON_QUEST["party2"] = {[100] = true}')
    g.join_party(["Anna", "Bob"])
    g.advance(8)
    assert g.pushed() == [101], g.pushed()


def test_area_all_shares_every_pushable_quest(style):
    g = Game(style)
    g.start()
    g.slash("area all")
    g.join_party(["Anna"])
    g.advance(5.3 + 4 * 3)
    assert g.pushed() == [100, 101, 200]


def test_many_quests_in_common_are_split_into_short_messages_sent_two_seconds_apart(style):
    g = Game(style)
    g.run("QUESTS = {{ header = 'Elwynn Forest' }}")
    for i in range(12):
        g.run("QUESTS[#QUESTS+1] = { id = %d, title = 'A rather long quest title number %d', level = 7, objectives = {} }" % (500 + i, i))
    g.start()
    g.run('ON_QUEST["party1"] = {}; for _, q in ipairs(QUESTS) do if q.id then ON_QUEST["party1"][q.id] = true end end')
    g.join_party(["Anna"])
    seen = []                                                           # time at which each message appeared
    for tenth in range(0, 400):
        g.advance(0.1)
        while len(seen) < len(g.sent()):
            seen.append(tenth / 10)
    sent = g.sent()
    assert len(sent) >= 3 and all(len(m) <= 255 for m, _ in sent), [len(m) for m, _ in sent]
    assert all(m.startswith("Hey Anna!") for m, _ in sent)
    assert sum(m.count("|Hquest:") for m, _ in sent) == 12, "every quest is announced exactly once"
    gaps = [round(b - a, 1) for a, b in zip(seen, seen[1:])]
    assert all(gap >= 1.9 for gap in gaps), gaps


# ---- clicking a quest in the tracker --------------------------------------------------------------------
def click_modern(g, qid, button="LeftButton"):
    g.eval("function(id, b) QUEST_TRACKER_MODULE.OnBlockHeaderClick(QUEST_TRACKER_MODULE, { id = id }, b) end")(qid, button)


def test_tracker_click_fills_the_chat_box_for_the_party():
    g = party_game("modern", pre=MODERN_TRACKER)
    click_modern(g, 100)
    assert g.opened() == [f"/p {LINK100} - {LEFT100}"]


def test_tracker_click_without_a_party_has_no_channel():
    g = Game("modern", MODERN_TRACKER)
    g.start()
    click_modern(g, 101)
    assert g.opened() == [f"{LINK101} - I'm done with this one, ready to turn in!"]


def test_tracker_click_puts_no_icon_code_in_the_chat_box():
    g = party_game("modern", on_quest={"party1": [100]}, pre=MODERN_TRACKER)
    click_modern(g, 100)
    assert g.opened() == [f"/p {LINK100} - {LEFT100} (Anna has it too!)"], "no raw {rt1} in the box"
    g.run("CLOSE_CHAT()")
    g.slash("mode send")
    click_modern(g, 100)                                                # sent at once, the game draws the star
    assert g.sent() == [(f"{{rt1}} {LINK100} - {LEFT100} (Anna has it too!)", "PARTY")]


def test_clicking_more_quests_adds_them_to_the_chat_box():
    g = party_game("modern", pre=MODERN_TRACKER)
    click_modern(g, 100)
    click_modern(g, 101)
    assert g.opened() == [f"/p {LINK100} - {LEFT100}"], "the box is opened once"
    assert g.eval("EDITBOX.text") == f"{LINK100} - {LEFT100} + {LINK101} - I'm done with this one, ready to turn in!"
    assert g.eval("EDITBOX.chat") == "/p", "still for the party"


def test_the_same_quest_is_not_added_twice():
    g = party_game("modern", pre=MODERN_TRACKER)
    click_modern(g, 100)
    click_modern(g, 100)
    assert g.eval("EDITBOX.text") == f"{LINK100} - {LEFT100}"
    assert "already in the chat box" in "\n".join(g.printed())


def test_what_you_typed_is_kept_and_the_status_goes_after_it():
    g = party_game("modern", pre=MODERN_TRACKER)
    g.run('ACTIVE_BOX = EDITBOX; EDITBOX.text = "brb, my progress:"')
    click_modern(g, 100)
    assert g.eval("EDITBOX.text") == f"brb, my progress: + {LINK100} - {LEFT100}" and g.opened() == []


def test_after_sending_or_closing_the_box_the_next_click_starts_fresh():
    g = party_game("modern", pre=MODERN_TRACKER)
    click_modern(g, 100)
    g.run("CLOSE_CHAT()")                                                # Enter or Esc
    click_modern(g, 101)
    assert g.eval("EDITBOX.text") == f"{LINK101} - I'm done with this one, ready to turn in!" and len(g.opened()) == 2


def test_a_full_chat_box_is_not_overfilled():
    g = party_game("modern", pre=MODERN_TRACKER)
    g.run('ACTIVE_BOX = EDITBOX; EDITBOX.text = string.rep("x", 200)')
    click_modern(g, 100)
    assert g.eval("EDITBOX.text") == "x" * 200, "it would not fit in one message: nothing is cut or lost"
    assert "chat box is full" in "\n".join(g.printed())


def test_tracker_click_is_ignored_for_other_buttons_modifiers_and_when_off():
    g = party_game("modern", pre=MODERN_TRACKER)
    click_modern(g, 100, "RightButton")
    g.run("SHIFT = true")
    click_modern(g, 100)
    g.run("SHIFT = false; CTRL = true")
    click_modern(g, 100)
    g.run("CTRL = false")
    click_modern(g, 999)                                                # not in the quest log
    g.slash("click off")
    click_modern(g, 100)
    assert g.opened() == []
    g.slash("click on")
    click_modern(g, 100)
    assert len(g.opened()) == 1


def test_tracker_click_modes_send_and_print():
    g = party_game("modern", pre=MODERN_TRACKER)
    g.slash("mode send")
    click_modern(g, 100)
    assert g.sent() == [(f"{LINK100} - {LEFT100}", "PARTY")] and g.opened() == []
    g.slash("mode print")
    click_modern(g, 100)
    assert any("still need" in m and "{rt1}" not in m for m in g.printed())
    g.run("PRINTED = {}")
    g.run('ON_QUEST["party1"] = {[100] = true}')
    click_modern(g, 100)
    assert any("UI-RaidTargetingIcon_1" in m for m in g.printed())


def test_classic_watch_frame_click():
    pre = "function WatchFrameLinkButtonTemplate_OnClick(self, button) end"
    g = party_game("classic", pre=pre)
    click = g.eval("function(t, i, b) WatchFrameLinkButtonTemplate_OnClick({ type = t, index = i }, b) end")
    click("QUEST", 2, "LeftButton")
    click("ACHIEVEMENT", 2, "LeftButton")
    assert g.opened() == [f"/p {LINK100} - {LEFT100}"]


def test_hooks_install_once_and_when_the_tracker_loads_late():
    g = Game("modern")
    g.start()
    assert g.eval("NS.hooks.tracker") is None
    g.run(MODERN_TRACKER)
    for _ in range(3):
        g.fire("ADDON_LOADED", "Blizzard_ObjectiveTracker")
        g.fire("PLAYER_ENTERING_WORLD")
    assert g.eval("NS.hooks.tracker") is True
    click_modern(g, 100)
    assert len(g.opened()) == 1, "hooked exactly once"


def test_shift_click_link_gets_the_status_appended(style):
    g = party_game(style)
    g.run("ACTIVE_BOX = EDITBOX")
    link = g.eval("LINK(BYID(100))")
    g.eval("ChatEdit_InsertLink")(link)
    assert g.eval("EDITBOX.text") == f"{link} - {LEFT100}"
    g.run('EDITBOX.text = ""; ON_QUEST["party1"] = {[100] = true}')
    g.eval("ChatEdit_InsertLink")(link)
    assert g.eval("EDITBOX.text") == f"{link} - {LEFT100} (Anna has it too!)", "no raw {rt1} in the box"
    g.run('EDITBOX.text = ""')
    g.eval("ChatEdit_InsertLink")("|cff1eff00|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r")
    assert g.eval("EDITBOX.text") == "|cff1eff00|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r", "items are left alone"
    g.slash("link off")
    g.run('EDITBOX.text = ""')
    g.eval("ChatEdit_InsertLink")(link)
    assert g.eval("EDITBOX.text") == link


def test_shift_click_with_no_chat_box_open_does_nothing(style):
    g = Game(style)
    g.start()
    g.eval("ChatEdit_InsertLink")(g.eval("LINK(BYID(100))"))
    assert g.eval("EDITBOX.text") == ""


# ---- settings, commands, robustness ---------------------------------------------------------------------------
def test_slash_commands_change_settings(style):
    g = Game(style)
    g.start()
    g.slash("gap 7")
    assert g.eval("NS.db.gap") == 7
    g.slash("gap 1")
    assert g.eval("NS.db.gap") == 2, "never faster than one quest per 2 seconds"
    g.slash("mode send")
    assert g.eval("NS.db.mode") == "send"
    g.slash("mode nonsense")
    assert g.eval("NS.db.mode") == "send"
    g.slash("auto")                                                      # no argument toggles
    assert g.eval("NS.db.auto") is False
    g.slash("chat off")
    assert g.eval("NS.db.chat") is False
    g.run("PRINTED = {}")
    g.slash("help")
    assert any("/qs share" in m for m in g.printed())


def test_saved_variables_are_merged_with_the_defaults(style):
    g = Game(style)
    g.run("QuestSharingDB = { gap = 9 }")
    g.fire("ADDON_LOADED", "QuestSharing")
    assert g.eval("NS.db.gap") == 9 and g.eval("NS.db.auto") is True and g.eval("QuestSharingDB.mode") == "box"
    g.fire("ADDON_LOADED", "SomeOtherAddon")
    assert g.eval("NS.db == QuestSharingDB") is True


def test_a_client_that_does_not_know_an_event_still_loads(style):
    g = Game(style, pre="UNKNOWN_EVENTS.GROUP_JOINED = true")
    g.start()
    g.join_party(["Anna"])
    g.advance(6)
    assert g.pushed() == [100]


def test_chat_off_keeps_quiet_but_still_shares(style):
    g = party_game(style, on_quest={"party1": [100]})
    g.slash("chat off")
    g.advance(60)
    assert g.sent() == [] and g.pushed() == [101]


def test_probe_reports_what_the_client_supports(style):
    g = party_game(style, on_quest={"party1": [100]}, pre=MODERN_TRACKER if style == "modern" else "")
    g.run("PRINTED = {}")
    g.slash("probe")
    text = "\n".join(g.printed())
    assert "game interface 16001" in text
    assert ("modern (C_QuestLog)" if style == "modern" else "classic (GetQuestLogTitle)") in text
    assert "see who is on a quest: yes" in text and "push a quest: yes" in text
    assert "game reply messages recognised: 9" in text
    assert "live test: is Anna on 'Wolves Among Us'? -> true" in text
    assert ("tracker yes" in text) == (style == "modern")


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
                print("FAIL", label, type(e).__name__, str(e)[:300])
    print(f"\n{total - failed}/{total} passed")
    raise SystemExit(1 if failed else 0)
