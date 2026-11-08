"""Making quest objectives easy to find: quest icons over creatures, pinning the nearest quest, the game-settings helper.
     python tests/test_highlight.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

BADGE = "Interface\\TargetingFrame\\PortraitQuestBadge"
NEAR = dict(q100=400, q101=900, q102=2500, q200=10000)


def game(style="modern"):
    g = Game(style)
    g.start()
    g.slash("auto off")
    return g


def printed(g):
    return "\n".join(g.printed())


def marker(g, unit):
    return g.eval(f"NS.markerFor(PLATES.{unit})")


# ---- quest icons over creatures ----------------------------------------------------------------------------------
def test_a_quest_creature_gets_a_marker_and_other_creatures_do_not():
    g = game()
    g.run('ADD_PLATE("nameplate1", true); ADD_PLATE("nameplate2", false)')
    m = marker(g, "nameplate1")
    assert m.shown is True and m.texture.texture == BADGE
    assert (m.point[1], m.point[4], m.point[5]) == ("BOTTOM", 0, 2), "above the top of the nameplate"
    assert g.eval("NS.markerFor(PLATES.nameplate1).point[2] == PLATES.nameplate1.UnitFrame") is True
    assert marker(g, "nameplate2") is None


def test_the_marker_goes_away_when_the_objective_is_done_and_comes_back():
    g = game()
    g.run('ADD_PLATE("nameplate1", true)')
    g.run('RELATED["nameplate1"] = false')
    g.fire("QUEST_LOG_UPDATE")
    g.advance(0.7)
    assert marker(g, "nameplate1").shown is False
    g.run('RELATED["nameplate1"] = true')
    g.advance(2.5)                                           # no event this time: the safety-net look finds it
    assert marker(g, "nameplate1").shown is True


def test_a_removed_nameplate_loses_its_marker_and_a_recycled_one_is_reused():
    g = game()
    g.run('ADD_PLATE("nameplate1", true); SAVED_PLATE = PLATES.nameplate1; SAVED_MARKER = NS.markerFor(PLATES.nameplate1)')
    m = marker(g, "nameplate1")
    g.run('REMOVE_PLATE("nameplate1")')
    assert m.shown is False, "the creature went away"
    # the game recycles the same nameplate frame for another creature
    g.run('PLATES.nameplate1 = SAVED_PLATE; RELATED.nameplate1 = false; FIRE("NAME_PLATE_UNIT_ADDED", "nameplate1")')
    assert marker(g, "nameplate1").shown is False, "an unrelated creature on a recycled nameplate shows nothing"
    g.run('RELATED.nameplate1 = true')
    g.fire("UNIT_QUEST_LOG_CHANGED", "player")
    g.advance(0.7)
    assert marker(g, "nameplate1").shown is True
    assert g.eval("NS.markerFor(PLATES.nameplate1) == SAVED_MARKER") is True, "the same marker frame is reused"
    assert g.eval("rawget(PLATES.nameplate1, 'QuestSharingMarker')") is None, "nothing is written onto the game's nameplate"


def test_icons_are_our_own_frames_and_combat_never_touches_a_nameplate():
    g = game()
    g.run('ADD_PLATE("nameplate1", true)')
    frames_before = len(g.eval("FRAMES"))
    g.run("IN_COMBAT = true")
    g.run('ADD_PLATE("nameplate2", true)')                          # a creature that shows up during the fight
    g.advance(3)
    assert marker(g, "nameplate2") is None and len(g.eval("FRAMES")) == frames_before, "nothing is made in combat"
    assert marker(g, "nameplate1").shown is True, "existing icons stay (they are ours: showing them is not restricted)"
    assert len(g.eval("NS.db.errors") or {}) == 0
    g.run("IN_COMBAT = false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(1.5)
    assert marker(g, "nameplate2").shown is True, "and after the fight it gets its icon"


def test_markers_can_be_switched_off_and_on():
    g = game()
    g.run('ADD_PLATE("nameplate1", true)')
    g.slash("highlight mobs off")
    assert marker(g, "nameplate1").shown is False and g.eval("NS.db.markMobs") is False
    g.slash("highlight mobs on")
    assert marker(g, "nameplate1").shown is True
    g.slash("highlight mobs")                                # no argument toggles
    assert marker(g, "nameplate1").shown is False


def test_a_game_that_hides_values_from_addons_does_not_cause_errors():
    g = game()
    g.run("RELATED_ERROR = true")
    g.run('ADD_PLATE("nameplate1", true)')
    g.fire("QUEST_LOG_UPDATE")
    g.advance(5)
    assert marker(g, "nameplate1") is None
    assert len(g.eval("NS.db.errors") or {}) == 0


def test_a_client_without_nameplates_just_says_so():
    g = game("classic")
    g.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    g.advance(5)
    g.run("PRINTED = {}")
    g.slash("highlight")
    assert "not available on this client" in printed(g) and len(g.eval("NS.db.errors") or {}) == 0


# ---- pin the nearest quest in the world --------------------------------------------------------------------------------
def following(count=2, dist=NEAR):
    g = game()
    g.set_dist(**dist)
    g.slash(f"near {count}")
    g.slash("near on")
    return g


def test_the_nearest_quest_is_pinned_at_once():
    g = following()
    assert g.eval("SUPER") == 100 and g.super_log() == [100]


def test_a_small_gain_does_not_move_the_pin_but_a_clear_one_does_after_two_looks():
    g = following()
    g.set_dist(q100=400, q101=300, q102=2500, q200=10000)
    g.advance(30)
    assert g.super_log() == [100], "101 is only a little closer"
    g.set_dist(q100=400, q101=50, q102=2500, q200=10000)
    g.advance(2.3)
    assert g.eval("SUPER") == 100, "seen once: wait for confirmation"
    g.advance(2.3)
    assert g.eval("SUPER") == 101 and g.super_log() == [100, 101]


def test_a_short_detour_never_moves_the_pin():
    g = following()
    g.set_dist(q100=400, q101=50, q102=2500, q200=10000)
    g.advance(2.3)
    g.set_dist(**NEAR)
    g.advance(30)
    assert g.super_log() == [100]


def test_choosing_another_quest_yourself_pauses_the_pin_for_ten_seconds():
    g = following()
    g.run("SUPER = 200")                                     # you pinned a quest by hand
    g.advance(2.3)
    assert "pin: paused for 10 seconds" in printed(g) and g.eval("SUPER") == 200
    g.advance(5)
    assert g.eval("SUPER") == 200, "it does not fight you"
    g.advance(8)                                             # the pause is over
    g.advance(2.3)
    g.advance(2.3)
    assert g.eval("SUPER") == 100


def test_resume_ends_a_pin_pause_early():
    g = following()
    g.run("SUPER = 200")
    g.advance(2.3)
    g.slash("near resume")
    g.advance(2.3)
    g.advance(2.3)
    assert g.eval("SUPER") == 100


def test_the_games_own_pin_of_a_new_quest_is_not_mistaken_for_you():
    g = following()
    g.fire("QUEST_ACCEPTED", 100)
    g.run("SUPER = 300")                                     # the game pins the quest you just accepted
    g.advance(5)
    assert "pin: paused" not in printed(g)


def test_switching_off_gives_back_the_quest_you_had_pinned():
    g = game()
    g.set_dist(**NEAR)
    g.run("SUPER = 102")
    g.slash("near 2")
    g.slash("near on")
    assert g.eval("SUPER") == 100
    g.slash("near off")
    assert g.eval("SUPER") == 102


def test_the_pin_can_be_switched_off_on_its_own():
    g = following()
    g.slash("highlight pin off")
    assert g.eval("SUPER") == 0 or g.eval("SUPER") != 100 or g.eval("NS.db.nearPin") is False
    log = len(g.super_log())
    g.set_dist(q100=900, q101=50, q102=2500, q200=10000)
    g.advance(30)
    assert len(g.super_log()) == log and g.eval("NS.db.nearPin") is False


def test_no_pin_in_zone_mode_in_combat_or_on_a_client_without_the_call():
    g = game()
    g.set_dist(**NEAR)
    g.slash("near mode zone")
    g.slash("near on")
    g.advance(10)
    assert g.super_log() == [], "zone mode has no distances to pin by"
    g2 = game()
    g2.set_dist(**NEAR)
    g2.run("IN_COMBAT = true")
    g2.slash("near on")
    g2.advance(10)
    assert g2.super_log() == []
    g3 = game("classic")
    g3.slash("near on")
    g3.advance(10)
    assert g3.eval("NS.canPin()") is False and len(g3.eval("NS.db.errors") or {}) == 0


# ---- the game-settings helper -----------------------------------------------------------------------------------------
def test_the_helper_switches_settings_on_and_puts_yours_back():
    g = game()
    g.run('CVARS.nameplateShowEnemies = "0"')
    g.slash("highlight cvars on")
    assert g.eval("CVARS.nameplateShowEnemies") == "1" and g.eval("CVARS.SoftTargetIconGameObject") == "1"
    assert g.eval("NS.db.cvarSaved.nameplateShowEnemies") == "0" and g.eval("NS.db.cvarSaved.SoftTargetIconGameObject") == "0"
    g.slash("highlight cvars off")
    assert g.eval("CVARS.nameplateShowEnemies") == "0" and g.eval("CVARS.SoftTargetIconGameObject") == "0"
    assert g.eval("NS.db.cvarSaved") is None and g.eval("NS.db.highlightCVars") is False


def test_the_helper_is_off_by_default_and_never_touches_settings_unasked():
    g = Game("modern", fresh=True)
    g.fire("ADDON_LOADED", "QuestSharing")
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(10)
    assert g.eval("NS.db.highlightCVars") is False and g.eval("CVAR_LOG") is None or len(g.eval("CVAR_LOG")) == 0


def test_the_helper_waits_for_the_end_of_combat():
    g = game()
    g.run("IN_COMBAT = true")
    g.slash("highlight cvars on")
    assert g.eval("NS.db.highlightCVars") is False and g.eval("CVARS.SoftTargetIconGameObject") == "0"
    assert "cannot be changed in combat" in printed(g)


def test_settings_this_client_does_not_have_are_skipped():
    g = game()
    g.run("CVARS.SoftTargetIconGameObject = nil")
    g.slash("highlight cvars on")
    assert g.eval("CVARS.SoftTargetIconGameObject") is None, "a setting that does not exist is not created"


def test_the_helper_reapplies_its_settings_after_a_reload():
    g = game()
    g.slash("highlight cvars on")
    g.run('CVARS.SoftTargetIconGameObject = "0"')            # something reset it
    g.fire("PLAYER_ENTERING_WORLD")
    assert g.eval("CVARS.SoftTargetIconGameObject") == "1"


# ---- settings window, doctor ------------------------------------------------------------------------------------------------
def test_the_new_rows_and_defaults():
    g = Game("modern", fresh=True)
    g.fire("ADDON_LOADED", "QuestSharing")
    assert (g.eval("NS.db.markMobs"), g.eval("NS.db.nearPin"), g.eval("NS.db.highlightCVars")) == (True, True, False)
    keys = [g.eval(f"NS.settingRows[{i}].key") for i in range(1, int(g.eval("#NS.settingRows")) + 1)]
    for k in ("markMobs", "nearPin", "highlightCVars"):
        assert k in keys, k
    g.slash("highlight cvars on")
    g.slash("reset")
    assert g.eval("NS.db.highlightCVars") is False and g.eval("CVARS.SoftTargetIconGameObject") == "0", "reset undoes the helper too"


def test_doctor_reports_the_highlight_features():
    g = game()
    g.slash("doctor")
    text = g.eval("NS._reportWindow()")[1].text
    assert "[OK] quest icons above creatures that are part of your quests" in text
    assert "[OK] pin the nearest quest in the world" in text
    g.run('CVARS.nameplateShowEnemies = "0"')
    assert "BUT enemy nameplates are off: /qs highlight cvars on" in "\n".join(g.eval("NS.doctorLines()").values())
    c = game("classic")
    c.slash("doctor")
    ctext = c.eval("NS._reportWindow()")[1].text
    assert "[--] quest icons above creatures" in ctext and "[--] pin the nearest quest" in ctext


if __name__ == "__main__":
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
