"""Beta: add the people in your party to your friends list.      python tests/test_friends.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")


def party(style, names=("Anna", "Bob"), auto=False, pre=""):
    g = Game(style, pre)
    g.start()
    g.slash("auto off")                       # no quest sharing noise in these tests
    if auto:
        g.slash("friends on")
    g.join_party(list(names))
    return g


def printed(g):
    return "\n".join(g.printed())


# ---- /qs friends (manual) ------------------------------------------------------------------------------------
def test_the_command_adds_everybody_in_the_party_one_by_one(style):
    g = party(style, ("Anna", "Bob", "Cy"))
    g.slash("friends")
    g.advance(10)
    assert g.friends() == ["anna", "bob", "cy"]
    calls = g.friend_calls()
    assert [c[0] for c in calls] == ["Anna", "Bob", "Cy"]
    assert all(b[2] - a[2] >= 1.4 for a, b in zip(calls, calls[1:])), "one add every 1.5 seconds"
    assert "added: Anna, Bob, Cy" in printed(g)


def test_the_note_names_the_zone_and_fits_the_limit(style):
    g = party(style)
    g.slash("friends")
    g.advance(10)
    note = g.friend_calls()[0][1]
    assert note == "Quest Sharing: Elwynn Forest" and len(note) <= 48


def test_friends_and_ignored_players_are_skipped_and_reported(style):
    g = party(style, ("Anna", "Bob", "Cy"))
    g.run("FRIENDS.anna = true; IGNORED.bob = true")
    g.slash("friends")
    g.advance(10)
    assert [c[0] for c in g.friend_calls()] == ["Cy"]
    text = printed(g)
    assert "already friends: Anna" in text and "ignored: Bob" in text and "added: Cy" in text


def test_nobody_to_add_says_so(style):
    g = party(style, ("Anna",))
    g.run("FRIENDS.anna = true")
    g.slash("friends")
    assert g.friend_calls() == [] and "nobody to add" in printed(g)


def test_the_games_answers_are_reported(style):
    g = party(style, ("Anna", "Bob", "Cy"))
    g.run('FRIEND_OVERRIDE.anna = "notfound"; FRIEND_OVERRIDE.bob = "faction"')
    g.slash("friends")
    g.advance(10)
    text = printed(g)
    assert "not found: Anna" in text and "other faction: Bob" in text and "added: Cy" in text


def test_other_friend_messages_are_not_mistaken_for_answers(style):
    g = party(style, ("Anna",))
    g.run("FRIEND_REPLY = 'hold'")
    g.slash("friends")
    g.fire("CHAT_MSG_SYSTEM", "|Hplayer:Anna|h[Anna]|h has come online.")
    g.fire("CHAT_MSG_SYSTEM", "Anna added to friends.")
    g.run("FRIENDS.anna = true")
    g.advance(10)
    assert "added: Anna" in printed(g)


def test_a_list_that_is_already_full_is_not_even_tried(style):
    g = party(style, ("Anna", "Bob"))
    g.run("FRIEND_EXTRA = 100")
    g.slash("friends")
    g.advance(10)
    assert g.friend_calls() == [] and "no room: Anna, Bob" in printed(g)


def test_when_the_game_says_the_list_is_full_it_stops_trying(style):
    g = party(style, ("Anna", "Bob", "Cy"))
    g.run("FRIEND_REPLY = 'hold'")                           # we think there is room; the game disagrees
    g.slash("friends")
    g.fire("CHAT_MSG_SYSTEM", "Your friends list is full.")
    g.advance(10)
    assert len(g.friend_calls()) == 1, "after 'your friends list is full' it does not try the others"
    assert "your list is full: Anna" in printed(g)


def test_answers_that_arrive_later_are_still_read(style):
    g = party(style, ("Anna", "Bob"))
    g.run("FRIEND_REPLY = 'hold'")
    g.slash("friends")
    g.advance(2)
    g.fire("CHAT_MSG_SYSTEM", "Anna added to friends.")
    g.run("FRIENDS.bob = true")                              # added, but the message was missed
    g.advance(10)
    text = printed(g)
    assert "added: Anna, Bob" in text


def test_no_answer_and_no_friend_is_reported_honestly(style):
    g = party(style, ("Anna",))
    g.run("FRIEND_REPLY = 'hold'")
    g.slash("friends")
    g.advance(10)
    assert "no answer: Anna" in printed(g)


def test_a_player_from_another_realm(style):
    g = party(style, ("Anna", "Bob"))
    g.run('REALMS.Bob = "Draenor"')
    g.slash("friends")
    g.advance(10)
    if style == "modern":
        assert [c[0] for c in g.friend_calls()] == ["Anna", "Bob-Draenor"]
    else:
        assert [c[0] for c in g.friend_calls()] == ["Anna"] and "other realm: Bob" in printed(g)


def test_a_nearly_full_list_limits_the_adds_but_manual_may_fill_it(style):
    g = party(style, ("Anna", "Bob", "Cy"))
    g.run("FRIEND_EXTRA = 97")                               # 97 of 100
    g.slash("friends")
    g.advance(10)
    assert len(g.friend_calls()) == 3, "by hand you may use the last slots"
    g2 = party(style, ("Anna", "Bob", "Cy"), auto=True)
    g2.run("FRIEND_EXTRA = 93")                              # automatic mode keeps 5 slots free: 100 - 93 - 5 = 2
    g2.advance(40)
    assert [c[0] for c in g2.friend_calls()] == ["Anna", "Bob"]
    assert "no room: Cy" in printed(g2) and "not adding more than fits" in printed(g2)


# ---- when it cannot or should not run ----------------------------------------------------------------------------
def test_messages_for_no_party_a_raid_a_switched_off_addon_and_a_client_without_the_call(style):
    g = Game(style)
    g.start()
    g.slash("friends")
    assert "not in a party" in printed(g)
    g.join_party(["Anna"])
    g.run("RAID = true")
    g.slash("friends")
    assert "not a raid" in printed(g)
    g.run("RAID = false")
    g.slash("off")
    g.slash("friends")
    assert "switched off" in printed(g) and g.friend_calls() == []
    g.slash("on")
    g.run("C_FriendList.AddFriend = nil" if style == "modern" else "AddFriend = nil")
    g.slash("friends")
    assert "no call to add friends" in printed(g)


# ---- automatic (beta) -------------------------------------------------------------------------------------------------
def test_automatic_mode_is_off_by_default(style):
    g = party(style)
    g.advance(60)
    assert g.eval("NS.db.friends") is False and g.friend_calls() == []


def test_automatic_mode_adds_the_party_after_a_pause_and_later_only_newcomers(style):
    g = party(style, ("Anna", "Bob"), auto=True)
    g.advance(7)
    assert g.friend_calls() == [], "waits for the party to settle"
    g.advance(8)
    assert [c[0] for c in g.friend_calls()] == ["Anna", "Bob"]
    g.join_party(["Anna", "Bob", "Cy"])
    g.advance(20)
    assert [c[0] for c in g.friend_calls()] == ["Anna", "Bob", "Cy"], "only the newcomer is added"
    g.advance(300)
    assert len(g.friend_calls()) == 3, "and never again on a timer"


def test_automatic_mode_skips_random_dungeon_groups_but_the_command_still_works(style):
    g = party(style, auto=True)
    g.run("INSTANCE_GROUP = true")
    g.advance(30)
    assert g.friend_calls() == [] and "random / instance group" in printed(g)
    g.slash("friends")
    g.advance(10)
    assert len(g.friend_calls()) == 2


def test_automatic_mode_ignores_a_party_you_were_already_in(style):
    g = Game(style)
    g.slash("auto off") if False else None
    g.run('SET_PARTY({"Anna"})')
    g.fire("ADDON_LOADED", "QuestSharing")
    g.slash("friends on")
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(40)
    assert g.friend_calls() == []


def test_automatic_mode_respects_the_master_switch_and_leaving(style):
    g = party(style, auto=True)
    g.slash("off")
    g.advance(40)
    assert g.friend_calls() == []
    g2 = party(style, auto=True)
    g2.advance(3)
    g2.leave_party()
    g2.advance(40)
    assert g2.friend_calls() == [], "the party broke up before the pause ended"


def test_leaving_and_forming_a_new_party_starts_fresh(style):
    g = party(style, ("Anna",), auto=True)
    g.advance(20)
    g.leave_party()
    g.join_party(["Anna"])
    g.advance(20)
    assert len(g.friend_calls()) == 1, "Anna is already a friend now: nothing is added twice"
    assert "already friends" in printed(g)


# ---- settings, status, probe ------------------------------------------------------------------------------------------
def test_the_beta_switch_in_the_settings_window_and_status(style):
    g = Game(style, fresh=True)
    g.fire("ADDON_LOADED", "QuestSharing")
    assert g.eval("NS.db.friends") is False, "beta: off by default"
    idx = g.eval("(function() for i, r in ipairs(NS.settingRows) do if r.key == 'friends' then return i end end end)()")
    assert "(beta)" in g.eval(f"NS.rowText(NS.settingRows[{idx}])") and "[OFF]" in g.eval(f"NS.rowText(NS.settingRows[{idx}])")
    g.eval("NS.settingsClick")(idx, "LeftButton")
    assert g.eval("NS.db.friends") is True
    g.slash("reset")
    assert g.eval("NS.db.friends") is False, "reset keeps the beta option off"
    g.run("PRINTED = {}")
    g.slash("status")
    assert "friends(beta) off" in printed(g)


def test_probe_reports_the_friends_support(style):
    g = Game(style)
    g.start()
    g.run("PRINTED = {}")
    g.slash("probe")
    assert "friends (beta): add call yes | reply messages recognised: 7 | friends 0/100 | automatic: off" in printed(g)


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
