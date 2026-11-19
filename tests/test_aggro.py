"""Tank aggro on nameplates: my threat % above each enemy in combat, the lowest-aggro enemy next to me marked.
     python tests/test_aggro.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

# THREAT[unit] = { tanking, scaled% }; FIGHTING[unit] = in combat; PLAYER_FIGHTING = me in combat
MOCK = """
THREAT, FIGHTING, PLAYER_FIGHTING, DISTANCE_ERROR = {}, {}, false, false
PORTRAITS = {}
function SetPortraitTexture(tex, unit) tex.portraitOf = unit; PORTRAITS[#PORTRAITS + 1] = unit end
function UnitAffectingCombat(u)
    if u == "player" then return PLAYER_FIGHTING end
    return FIGHTING[u] == true
end
function UnitDetailedThreatSituation(me, u)
    local t = THREAT[u]
    if not t then return nil end
    return t[1], t[1] and 3 or 1, t[2], t[2], t[2] * 10
end
"""


def game(style="modern"):
    g = Game(style, pre=MOCK)
    g.start()
    g.slash("auto off")
    return g


def mob(g, unit, pct, near=True, tanking=False):
    g.run(f'ADD_CREATURE("{unit}", "Mob {unit}", false, 960, 540, {"true" if near else "false"}); '
          f'FIGHTING["{unit}"] = true; THREAT["{unit}"] = {{ {"true" if tanking else "false"}, {pct} }}')


def fight(g):
    g.run("PLAYER_FIGHTING = true; IN_COMBAT = true")
    g.fire("PLAYER_REGEN_DISABLED")
    g.advance(0.5)


def label(g, unit):
    return g.eval(f"NS.aggro.labelFor(PLATES.{unit})")


def shown_text(g, unit):
    import re
    return re.sub(r"\|c\w{8}|\|r", "", label(g, unit).text.text)


def test_off_by_default_and_has_a_settings_row_in_general():
    g = game()
    assert g.eval("NS.defaults.aggroPlates") is False and g.eval("NS.db.aggroPlates") is False
    assert g.eval("(function() for _, r in ipairs(NS.settingRows) do if r.key == 'aggroPlates' then return r.tab end end end)()") == "general"
    mob(g, "nameplate1", 40)
    fight(g)
    assert label(g, "nameplate1") is None, "nothing drawn while the setting is off"


def test_each_enemy_shows_my_aggro_and_the_lowest_near_one_is_marked():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 100, tanking=True)
    mob(g, "nameplate2", 35)
    mob(g, "nameplate3", 80)
    mob(g, "nameplate4", 5, near=False)          # lowest, but far away: not the pick
    fight(g)
    assert shown_text(g, "nameplate1") == "100%"
    assert shown_text(g, "nameplate3") == "80%"
    assert shown_text(g, "nameplate4") == "5%" and label(g, "nameplate4").shown is True
    assert shown_text(g, "nameplate2") == "Losing aggro 35%"
    assert label(g, "nameplate1").text.text.startswith("|cffff3030"), "red: I hold it"
    assert label(g, "nameplate2").text.text.startswith("|cff9d9d9d"), "the marked one is grey"
    assert label(g, "nameplate1").flame.shown is True and label(g, "nameplate2").flame.shown is False
    assert g.eval("NS.aggro.pick") == "nameplate2"
    assert g.eval("rawget(PLATES.nameplate2, 'aggro') or rawget(PLATES.nameplate2.UnitFrame, 'aggro')") is None, "nothing is written onto the game's nameplate"


def test_the_mark_moves_when_threat_changes_and_needs_two_near_enemies():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 30)
    mob(g, "nameplate2", 40)
    fight(g)
    assert g.eval("NS.aggro.pick") == "nameplate1"
    g.run('THREAT.nameplate1 = { true, 100 }')
    g.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    g.advance(0.3)
    assert g.eval("NS.aggro.pick") == "nameplate2" and shown_text(g, "nameplate2") == "Losing aggro 40%"
    g.run('CREATURES.nameplate1.near = false')     # only one enemy left next to me: no pick
    g.advance(0.4)
    assert g.eval("NS.aggro.pick") is None and shown_text(g, "nameplate2") == "40%"


def test_dead_enemies_are_ignored_and_enemies_out_of_the_fight_show_zero_but_are_never_marked():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 20)
    mob(g, "nameplate2", 50)
    mob(g, "nameplate3", 10)
    g.run('CREATURES.nameplate3.dead = true; FIGHTING.nameplate2 = false; THREAT.nameplate2 = nil')
    fight(g)
    assert label(g, "nameplate1").shown is True
    assert shown_text(g, "nameplate2") == "0%", "not fighting: 0 %, still shown"
    assert label(g, "nameplate3") is None
    assert g.eval("NS.aggro.pick") is None, "only one enemy in the fight"


def test_numbers_show_all_the_time_and_go_away_only_when_the_setting_is_switched_off():
    g = game()
    g.slash("aggro on")
    g.run('ADD_CREATURE("nameplate1", "Wolf", false, 960, 540, true); ADD_CREATURE("nameplate2", "Bear", false, 960, 540, true)')
    g.advance(1.2)
    assert shown_text(g, "nameplate1") == "0%" and shown_text(g, "nameplate2") == "0%", "out of a fight too"
    assert label(g, "nameplate1").text.text.startswith("|cffffffff"), "white: nobody is fighting it yet"
    assert label(g, "nameplate1").flame.shown is False
    assert g.eval("NS.aggro.pick") is None, "no mark outside a fight"
    mob(g, "nameplate1", 20)
    mob(g, "nameplate2", 50)
    fight(g)
    assert label(g, "nameplate1").shown is True
    g.run("PLAYER_FIGHTING = false; IN_COMBAT = false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(1.2)
    assert label(g, "nameplate1").shown is True and g.eval("NS.aggro.pick") is None, "still shown after the fight"
    fight(g)
    assert label(g, "nameplate1").shown is True
    g.slash("aggro off")
    assert label(g, "nameplate1").shown is False and label(g, "nameplate2").shown is False
    g.slash("aggro on")                              # back on in the middle of the fight
    g.advance(0.4)
    assert label(g, "nameplate1").shown is True


def test_a_refused_distance_question_counts_the_enemy_as_near_and_nothing_errors():
    g = game()
    g.slash("aggro on")
    g.run('CheckInteractDistance = function() error("protected in combat") end')
    mob(g, "nameplate1", 40, near=False)
    mob(g, "nameplate2", 70, near=False)
    fight(g)
    assert g.eval("NS.aggro.pick") == "nameplate1"
    assert len(g.eval("NS.db.errors") or {}) == 0


def test_the_master_switch_hides_everything():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 20)
    mob(g, "nameplate2", 50)
    fight(g)
    g.slash("off")
    g.advance(0.4)
    assert label(g, "nameplate1").shown is False


# ---- enemy nameplates are switched on for you ------------------------------------------------------------------
def test_switching_aggro_on_turns_enemy_nameplates_on_and_off_puts_yours_back():
    for style in ("modern", "classic"):
        g = game(style)
        g.run('CVARS.nameplateShowEnemies = "0"')
        g.slash("aggro on")
        assert g.eval("CVARS.nameplateShowEnemies") == "1" and g.eval("NS.db.aggroCVarSaved") == "0"
        assert "enemy nameplates switched on" in "\n".join(g.printed())
        g.slash("aggro off")
        assert g.eval("CVARS.nameplateShowEnemies") == "0" and g.eval("NS.db.aggroCVarSaved") is None


def test_nameplates_already_on_are_left_alone():
    g = game()
    g.slash("aggro on")
    g.slash("aggro off")
    assert g.eval("CVARS.nameplateShowEnemies") == "1" and len(g.eval("CVAR_LOG")) == 0


def test_in_combat_the_change_waits_for_the_fight_to_end():
    g = game()
    g.run('CVARS.nameplateShowEnemies = "0"; IN_COMBAT = true; PLAYER_FIGHTING = true')
    g.slash("aggro on")
    assert g.eval("CVARS.nameplateShowEnemies") == "0", "the game refuses it in combat"
    assert "after this fight" in "\n".join(g.printed())
    g.run("IN_COMBAT = false; PLAYER_FIGHTING = false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(1)
    assert g.eval("CVARS.nameplateShowEnemies") == "1"
    assert len(g.eval("NS.db.errors") or {}) == 0


def test_the_quest_marker_helper_and_aggro_do_not_undo_each_other():
    g = game()
    g.run('CVARS.nameplateShowEnemies = "0"')
    g.slash("aggro on")
    g.slash("highlight cvars on")
    g.slash("highlight cvars off")                 # the helper puts its values back: aggro still needs nameplates
    assert g.eval("CVARS.nameplateShowEnemies") == "1"
    g.slash("aggro off")
    assert g.eval("CVARS.nameplateShowEnemies") == "0", "your own value in the end"
    g.slash("aggro on")
    g.slash("highlight cvars on")
    g.slash("aggro off")                           # the helper still needs them: they stay on until it is off
    assert g.eval("CVARS.nameplateShowEnemies") == "1"
    g.slash("highlight cvars off")
    assert g.eval("CVARS.nameplateShowEnemies") == "0"


def test_the_master_switch_puts_your_nameplates_back():
    g = game()
    g.run('CVARS.nameplateShowEnemies = "0"')
    g.slash("aggro on")
    g.slash("off")
    assert g.eval("CVARS.nameplateShowEnemies") == "0"


# ---- review round: no false alarms, readable next to quest badges, a word when the client cannot -----------------
def test_no_alarm_when_the_lowest_near_enemy_is_orange_coming_back():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 100, tanking=True)
    mob(g, "nameplate2", 60)
    fight(g)
    assert g.eval("NS.aggro.pick") is None and shown_text(g, "nameplate2") == "60%"
    assert label(g, "nameplate2").text.text.startswith("|cffff9a1a")


def test_no_mark_when_every_near_enemy_is_already_on_me():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 100, tanking=True)
    mob(g, "nameplate2", 100, tanking=True)
    fight(g)
    assert g.eval("NS.aggro.pick") is None
    assert shown_text(g, "nameplate1") == "100%" and shown_text(g, "nameplate2") == "100%"


def test_colours_read_like_heat_and_the_flame_shows_only_at_100():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 10)
    mob(g, "nameplate2", 40)
    mob(g, "nameplate3", 85)
    mob(g, "nameplate4", 100, tanking=True)
    fight(g)
    assert shown_text(g, "nameplate1") == "Losing aggro 10%" and label(g, "nameplate1").text.text.startswith("|cff9d9d9d"), "lowest: grey alarm"
    assert label(g, "nameplate2").text.text.startswith("|cff33ff33"), "below 50 %, about to leave me: green"
    assert label(g, "nameplate3").text.text.startswith("|cffff9a1a"), "medium: orange"
    mob(g, "nameplate5", 50)
    g.advance(0.4)
    assert label(g, "nameplate5").text.text.startswith("|cffff9a1a"), "50 % is already medium"
    assert label(g, "nameplate4").text.text.startswith("|cffff3030"), "I hold it: red"
    assert [label(g, f"nameplate{i}").flame.shown for i in (1, 2, 3, 4)] == [False, False, False, True]
    assert label(g, "nameplate4").flame.texture == "Interface\\Icons\\Spell_Fire_Fire"


def test_the_label_sits_above_the_quest_badge_when_there_is_one():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 30)
    g.run('ADD_CREATURE("nameplate2", "Quest mob", true, 960, 540, true); FIGHTING.nameplate2 = true; THREAT.nameplate2 = { false, 60 }')
    assert g.eval("NS.markerFor(PLATES.nameplate2):IsShown()") is True
    fight(g)
    assert label(g, "nameplate1").point[5] == 2, "right on top of a plain nameplate"
    assert label(g, "nameplate2").point[5] == 32, "above the gold quest badge"


def test_a_client_without_threat_says_so_once():
    g = Game("modern", pre=MOCK + "UnitDetailedThreatSituation = nil")
    g.start()
    g.slash("aggro on")
    g.slash("aggro off")
    g.slash("aggro on")
    assert "\n".join(g.printed()).count("does not tell addons the threat") == 1


# ---- several big marks: the lowest and every near one within 10 points of it -----------------------------------
def marked(g):
    return sorted(g.eval("NS.aggro.picks").values())


def test_every_near_enemy_close_to_the_lowest_is_marked():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 12)
    mob(g, "nameplate2", 18)
    mob(g, "nameplate3", 22)                     # exactly 10 above the lowest: still marked
    mob(g, "nameplate4", 45)
    mob(g, "nameplate5", 5, near=False)          # far away: never marked
    mob(g, "nameplate6", 100, tanking=True)
    fight(g)
    assert marked(g) == ["nameplate1", "nameplate2", "nameplate3"]
    assert g.eval("NS.aggro.pick") == "nameplate1", "the lowest one"
    assert [shown_text(g, f"nameplate{i}") for i in (1, 2, 3)] == ["Losing aggro 12%", "Losing aggro 18%", "Losing aggro 22%"]
    assert label(g, "nameplate4").text.text.startswith("|cff33ff33") and shown_text(g, "nameplate4") == "45%"
    assert shown_text(g, "nameplate5") == "5%" and shown_text(g, "nameplate6") == "100%"


def test_close_numbers_swapping_places_keep_the_same_marks():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 32)
    mob(g, "nameplate2", 31)
    mob(g, "nameplate3", 90)
    fight(g)
    assert marked(g) == ["nameplate1", "nameplate2"]
    g.run("THREAT.nameplate1 = { false, 29 }")
    g.advance(0.4)
    assert marked(g) == ["nameplate1", "nameplate2"], "both stay marked"
    g.run("THREAT.nameplate1 = { true, 100 }")               # grabbed: no longer marked
    g.advance(0.4)
    assert marked(g) == ["nameplate2"]


def test_no_marks_outside_a_fight():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 10)
    mob(g, "nameplate2", 12)
    g.advance(1.2)
    assert marked(g) == []


# ---- the tank's story: walk in, they aggro, a spell pulls one off, you hit it back -----------------------------------
def colour(g, unit):
    return label(g, unit).text.text[:10]


WHITE, RED, GREEN, ORANGE, GREY = "|cffffffff", "|cffff3030", "|cff33ff33", "|cffff9a1a", "|cff9d9d9d"


def test_the_room_story_white_then_red_then_green_then_orange():
    g = game()
    g.slash("aggro on")
    # 1. you walk into the room: nobody is fighting them -> all white
    g.run('ADD_CREATURE("nameplate1", "Defias", false, 960, 540, true); ADD_CREATURE("nameplate2", "Defias", false, 960, 540, true)')
    g.advance(1.2)
    assert colour(g, "nameplate1") == WHITE and colour(g, "nameplate2") == WHITE
    # 2. you pull: both aggro on you -> red with the flame
    for u in ("nameplate1", "nameplate2"):
        g.run(f'FIGHTING.{u} = true; THREAT.{u} = {{ true, 100 }}')
    fight(g)
    assert colour(g, "nameplate1") == RED and colour(g, "nameplate2") == RED
    assert label(g, "nameplate1").flame.shown is True
    # 3. the mage's spell pulls one away -> green (and marked big: grab it)
    g.run("THREAT.nameplate2 = { false, 20 }")
    g.fire("UNIT_THREAT_LIST_UPDATE", "nameplate2")
    g.advance(0.3)
    assert colour(g, "nameplate2") == GREY and shown_text(g, "nameplate2") == "Losing aggro 20%"
    assert label(g, "nameplate2").portrait.shown is True and label(g, "nameplate2").ring.shown is True
    assert label(g, "nameplate2").flame.shown is False
    # 4. you hit it -> orange
    g.run("THREAT.nameplate2 = { false, 75 }")
    g.advance(0.4)
    assert colour(g, "nameplate2") == ORANGE and shown_text(g, "nameplate2") == "75%", "coming back: orange, alarm off"
    assert label(g, "nameplate2").portrait.shown is False and label(g, "nameplate2").ring.shown is False
    # 5. it is back on you -> red again
    g.run("THREAT.nameplate2 = { true, 100 }")
    g.advance(0.4)
    assert colour(g, "nameplate2") == RED and shown_text(g, "nameplate2") == "100%", "on you again: no mark"
    # 6. the fight is over and the room is quiet -> white again
    for u in ("nameplate1", "nameplate2"):
        g.run(f'FIGHTING.{u} = false; THREAT.{u} = nil')
    g.run("PLAYER_FIGHTING = false; IN_COMBAT = false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(1.2)
    assert colour(g, "nameplate1") == WHITE and colour(g, "nameplate2") == WHITE


# ---- the alarm: portrait, pulsing red ring, "Losing aggro" -----------------------------------------------------------
def test_the_alarm_shows_the_portrait_in_a_pulsing_red_ring_only_on_marked_enemies():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 100, tanking=True)
    mob(g, "nameplate2", 15)
    mob(g, "nameplate3", 30, near=False)
    fight(g)
    f = label(g, "nameplate2")
    assert f.portrait.shown is True and f.portrait.portraitOf == "nameplate2", "the mob's own portrait"
    assert f.ring.shown is True and f.ring.texture == "Interface\\Buttons\\UI-ActionButton-Border"
    assert list(f.ring.vertex.values())[:3] == [1, 0.1, 0.1], "tinted red"
    on_update = g.eval("function(f, dt) f.scripts.OnUpdate(f, dt) end")
    seen = set()
    for _ in range(12):
        on_update(f, 0.1)
        seen.add(round(f.ringAlpha, 1))
    assert min(seen) <= 0.4 and max(seen) >= 0.9, "it pulses dim -> bright"
    for u in ("nameplate1", "nameplate3"):
        assert label(g, u).portrait.shown is False and label(g, u).ring.shown is False
    assert label(g, "nameplate1").flame.shown is True and f.flame.shown is False, "flame and alarm never on the same mob"
    g.run("THREAT.nameplate2 = { true, 100 }")                # grabbed: the alarm stops
    g.advance(0.4)
    assert f.portrait.shown is False and f.ring.shown is False and f.scripts.OnUpdate is None


if __name__ == "__main__":
    failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print("ok  ", name)
            except Exception as e:  # noqa: BLE001
                failed += 1
                print("FAIL", name, repr(e))
    sys.exit(1 if failed else 0)
