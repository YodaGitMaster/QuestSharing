"""The "tracker follows you" feature: the quest tracker (list on the right) is kept filled with the quests
closest to you (distance mode) or with the quests of your zone (zone mode).    python tests/test_tracker.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")
# squared distances (yards squared) to the four default quests: 100 and 101 close, 102 further, 200 far away
NEAR_100_101 = dict(q100=400, q101=900, q102=2500, q200=10000)


def modern(count=2, watched=(), dist=NEAR_100_101, on=True):
    g = Game("modern")
    g.start()
    g.run("WATCHED = {%s}" % ", ".join(f"[{q}] = true" for q in watched))
    g.set_dist(**dist)
    g.slash(f"near {count}")
    if on:
        g.slash("near on")
    return g


# ---- distance mode ----------------------------------------------------------------------------------------------
def test_tracks_the_closest_quests_and_removes_the_others_first():
    g = modern(watched=(200,))
    assert g.watched() == [100, 101]
    log = g.watch_log()
    assert log[0] == "-200" and set(log[1:]) == {"+100", "+101"}, log          # frees the slot before adding


def test_turning_it_off_puts_the_old_list_back():
    g = modern(watched=(200,))
    g.slash("near off")
    assert g.watched() == [200] and g.eval("NS.db.nearSaved") is None and g.eval("NS.db.near") is False
    log = len(g.watch_log())
    g.advance(30)
    assert len(g.watch_log()) == log, "no more changes after it is off"


def test_a_small_gain_does_not_swap_quests():
    g = modern()
    g.set_dist(q100=400, q101=900, q102=800, q200=10000)                         # 102 is a bit closer than 101
    g.advance(30)
    assert g.watched() == [100, 101]


def test_a_clearly_closer_quest_swaps_in_after_two_looks_in_a_row():
    g = modern()
    g.set_dist(q100=400, q101=900, q102=50, q200=10000)
    g.advance(2.3)
    assert g.watched() == [100, 101], "seen once: wait for confirmation"
    g.advance(2.3)
    assert g.watched() == [100, 102]


def test_a_short_detour_does_not_reshuffle_the_list():
    g = modern()
    calls = len(g.watch_log())
    g.set_dist(q100=400, q101=900, q102=50, q200=10000)
    g.advance(2.3)                                                                # one look at the detour
    g.set_dist(**NEAR_100_101)                                                    # ...and you are back
    g.advance(30)
    assert g.watched() == [100, 101]
    assert len(g.watch_log()) == calls, "the tracker was never touched, not even briefly"


def test_the_list_follows_you_as_you_move_to_another_zone():
    g = modern()
    g.set_dist(q100=9000, q101=9500, q102=9800, q200=100)                         # you walked into Westfall
    g.advance(10)
    assert g.watched() == [100, 200], g.watched()                                 # 200 is close, 100 keeps its slot (stickiness)


def test_quests_on_another_continent_are_ignored():
    g = modern(on=False)
    g.run("OFF_CONTINENT[100] = true")
    g.slash("near on")
    assert g.watched() == [101, 102]


def test_a_finished_quest_is_tracked_when_its_turn_in_is_closest():
    g = modern(on=False, dist=dict(q100=900, q101=50, q102=2500, q200=10000))
    g.run("BYID(101).complete = true")
    g.slash("near on")
    assert 101 in g.watched()


def test_count_command_and_its_limits():
    g = modern(count=3)
    assert g.watched() == [100, 101, 102]
    g.slash("near 99")
    assert g.eval("NS.db.nearCount") == 25, "modern tracker limit"
    g.slash("near 0")
    assert g.eval("NS.db.nearCount") == 1


def test_it_waits_during_combat_and_in_instances():
    g = modern(on=False)
    g.run("IN_COMBAT = true")
    g.slash("near on")
    g.advance(10)
    assert g.watched() == []
    g.run("IN_COMBAT = false; IN_INSTANCE = true")
    g.advance(10)
    assert g.watched() == []
    g.run("IN_INSTANCE = false")
    g.advance(5)
    assert g.watched() == [100, 101]


def test_it_looks_every_two_seconds_not_continuously():
    g = modern()
    g.run("DISTANCE_CALLS = 0")
    g.advance(10)
    assert g.eval("DISTANCE_CALLS") <= 6 * 4, g.eval("DISTANCE_CALLS")             # at most ~5 looks x 4 quests


def test_it_is_off_by_default_and_never_touches_the_tracker():
    g = Game("modern")
    g.start()
    g.set_dist(**NEAR_100_101)
    g.join_party(["Anna"])
    g.fire("ZONE_CHANGED_NEW_AREA")
    g.fire("QUEST_ACCEPTED", 100)
    g.advance(60)
    assert g.watch_log() == [] and g.eval("NS.db.near") is False


# ---- you stay in charge --------------------------------------------------------------------------------------------
def test_changing_the_tracker_yourself_pauses_it_for_five_minutes():
    g = modern()
    g.advance(10)
    g.run("WATCHED[200] = true")                                                   # you added a quest by hand
    g.fire("QUEST_WATCH_LIST_CHANGED")
    assert "paused for 5 minutes" in "\n".join(g.printed())
    g.advance(120)
    assert 200 in g.watched(), "it does not fight you"
    g.advance(200)
    g.advance(6)
    assert 200 not in g.watched(), "after the pause it takes over again"


def test_resume_command_ends_the_pause_early():
    g = modern()
    g.advance(10)
    g.run("WATCHED[200] = true")
    g.fire("QUEST_WATCH_LIST_CHANGED")
    g.slash("near resume")
    assert 200 not in g.watched()


def test_the_games_own_tracking_of_a_new_quest_and_our_own_changes_do_not_count_as_you():
    g = modern(on=False)
    g.slash("near on")
    g.fire("QUEST_WATCH_LIST_CHANGED")                                             # fired by our own changes
    g.advance(5)
    g.fire("QUEST_ACCEPTED", 100)                                                  # the game auto-tracks the quest
    g.fire("QUEST_WATCH_LIST_CHANGED")
    assert "paused" not in "\n".join(g.printed())


def test_a_new_or_removed_quest_refreshes_the_list_right_away():
    g = modern()
    g.run("table.insert(QUESTS, 5, { id = 300, title = 'Fresh', level = 4, objectives = {} })")
    g.set_dist(q100=400, q101=900, q102=2500, q200=10000, q300=10)
    g.fire("QUEST_ACCEPTED", 300)
    g.advance(1.2)
    assert 300 in g.watched()


def test_it_comes_back_after_a_reload():
    g = Game("modern")
    g.run("QuestSharingDB = { near = true, nearCount = 2 }")
    g.set_dist(**NEAR_100_101)
    g.fire("ADDON_LOADED", "QuestSharing")
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(8)
    assert g.watched() == [100, 101]


# ---- zone mode and clients without distances --------------------------------------------------------------------------
def test_zone_mode_tracks_the_quests_of_the_zone_you_are_in():
    g = Game("classic")
    g.start()
    g.run("WATCHED = { [200] = true }")
    g.slash("near on")
    assert g.eval("NS.nearMode()") == "zone"
    assert g.watched() == [100, 101, 102], g.watched()
    g.run('ZONE = "Westfall"')
    g.fire("ZONE_CHANGED_NEW_AREA")
    g.advance(1.5)
    assert g.watched() == [200]
    g.slash("near off")
    assert g.watched() == [200], "the old list (just 200) is back"


def test_classic_tracker_limit_is_respected():
    g = Game("classic")
    g.start()
    for i in range(8):
        g.run("table.insert(QUESTS, 2, { id = %d, title = 'Quest %d', level = 3, objectives = {} })" % (700 + i, i))
    g.slash("near 99")
    assert g.eval("NS.db.nearCount") == 5
    g.slash("near on")
    assert len(g.watched()) == 5


def test_zone_mode_can_be_chosen_on_a_modern_client_and_distance_falls_back_on_classic():
    g = Game("modern")
    g.start()
    assert g.eval("NS.nearMode()") == "distance"
    g.slash("near mode zone")
    assert g.eval("NS.nearMode()") == "zone"
    c = Game("classic")
    c.start()
    c.slash("near mode distance")
    assert c.eval("NS.nearMode()") == "zone", "no distance information here"


def test_a_client_without_tracker_calls_says_so():
    g = Game("modern")
    g.start()
    g.run("C_QuestLog.AddQuestWatch = nil")
    g.slash("near on")
    assert g.eval("NS.db.near") is False
    assert "no calls to change the quest tracker" in "\n".join(g.printed())


# ---- commands and probe -------------------------------------------------------------------------------------------------
def test_command_help_status_and_probe():
    g = Game("modern")
    g.start()
    g.run("PRINTED = {}")
    g.slash("near bogus")
    g.slash("status")
    g.slash("probe")
    text = "\n".join(g.printed())
    assert "/qs near [on|off]" in text and "near off" in text
    assert "tracker control (/qs near): yes | distance to quests: yes | mode in use: distance" in text
    c = Game("classic")
    c.start()
    c.run("PRINTED = {}")
    c.slash("probe")
    assert "distance to quests: NO | mode in use: zone | tracker holds up to 5" in "\n".join(c.printed())


if __name__ == "__main__":
    import inspect
    failed = total = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        total += 1
        try:
            fn()
            print("ok  ", name)
        except Exception as e:                       # noqa: BLE001
            failed += 1
            print("FAIL", name, type(e).__name__, str(e)[:400])
    print(f"\n{total - failed}/{total} passed")
    raise SystemExit(1 if failed else 0)
