"""Tank aggro: my threat % as a plain number on each enemy nameplate while I fight.
     python tests/test_aggro.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

# THREAT[unit] = { tanking, scaled% }; FIGHTING[unit] = in combat; PLAYER_FIGHTING = me in combat
MOCK = """
THREAT, FIGHTING, PLAYER_FIGHTING = {}, {}, false
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


def game(style="modern", pre=MOCK):
    g = Game(style, pre=pre)
    g.start()
    g.slash("auto off")
    return g


def mob(g, unit, pct, tanking=False, fighting=True):
    g.run(f'ADD_CREATURE("{unit}", "Mob {unit}", false, 960, 540, true); '
          f'FIGHTING["{unit}"] = {"true" if fighting else "false"}; THREAT["{unit}"] = {{ {"true" if tanking else "false"}, {pct} }}')


def fight(g):
    g.run("PLAYER_FIGHTING = true; IN_COMBAT = true")
    g.fire("PLAYER_REGEN_DISABLED")
    g.advance(0.3)


def end_fight(g):
    g.run("PLAYER_FIGHTING = false; IN_COMBAT = false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(0.3)


def label(g, unit):
    return g.eval(f"NS.aggro.labelFor(PLATES.{unit})")


def text(g, unit):
    f = label(g, unit)
    return f.text.text if f and f.shown else None


def test_off_by_default_with_a_settings_row():
    g = game()
    assert g.eval("NS.db.aggroPlates") is False
    assert g.eval("(function() for _, r in ipairs(NS.settingRows) do if r.key == 'aggroPlates' then return r.tab end end end)()") == "general"
    mob(g, "nameplate1", 40)
    fight(g)
    assert label(g, "nameplate1") is None, "nothing while it is off"


def test_each_enemy_in_the_fight_shows_my_aggro_as_a_number():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 100, tanking=True)
    mob(g, "nameplate2", 35)
    mob(g, "nameplate3", 0)
    fight(g)
    assert [text(g, f"nameplate{i}") for i in (1, 2, 3)] == ["100%", "35%", "0%"]
    assert g.eval("rawget(PLATES.nameplate1, 'aggro')") is None, "nothing is written onto the game's nameplate"


def test_an_old_client_without_the_nameplate_api_shows_nothing_and_does_not_error():
    g = game("classic")
    g.slash("aggro on")
    fight(g)
    assert g.eval("NS.aggro.supported()") is False and len(g.eval("NS.db.errors") or {}) == 0


def test_the_number_follows_the_threat():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 30)
    fight(g)
    g.run("THREAT.nameplate1 = { false, 72 }")
    g.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    g.advance(0.2)
    assert text(g, "nameplate1") == "72%"
    g.run("THREAT.nameplate1 = { true, 100 }")               # no event: the tick finds it
    g.advance(0.6)
    assert text(g, "nameplate1") == "100%"


def test_no_number_out_of_a_fight_for_dead_or_idle_enemies():
    g = game()
    g.slash("aggro on")
    mob(g, "nameplate1", 30)
    mob(g, "nameplate2", 30, fighting=False)
    mob(g, "nameplate3", 30)
    g.run("CREATURES.nameplate3.dead = true")
    g.advance(1)
    assert text(g, "nameplate1") is None, "I am not fighting"
    fight(g)
    assert text(g, "nameplate1") == "30%" and text(g, "nameplate2") is None and text(g, "nameplate3") is None
    end_fight(g)
    assert text(g, "nameplate1") is None, "gone when the fight ends"


def test_switching_off_hides_the_numbers_and_on_says_what_it_can_see():
    g = game()
    g.slash("aggro on")
    assert "threat data from the game: yes" in "\n".join(g.printed())
    mob(g, "nameplate1", 30)
    fight(g)
    g.slash("aggro off")
    assert text(g, "nameplate1") is None
    g.slash("aggro on")
    assert text(g, "nameplate1") == "30%"
    g.slash("off")
    g.advance(0.6)
    assert text(g, "nameplate1") is None, "the master switch too"


def test_a_client_without_threat_data_says_so_and_nothing_errors():
    g = game(pre=MOCK + "UnitDetailedThreatSituation = nil")
    g.slash("aggro on")
    assert "NO (this client cannot show aggro)" in "\n".join(g.printed())
    mob(g, "nameplate1", 30)
    fight(g)
    assert label(g, "nameplate1") is None and len(g.eval("NS.db.errors") or {}) == 0


def test_the_old_versions_saved_nameplate_value_is_put_back_once():
    g = game()
    g.run('NS.db.aggroCVarSaved = "0"; CVARS.nameplateShowEnemies = "1"')
    g.fire("PLAYER_ENTERING_WORLD")
    assert g.eval("CVARS.nameplateShowEnemies") == "0" and g.eval("NS.db.aggroCVarSaved") is None
    g.run('CVARS.nameplateShowEnemies = "1"')
    g.fire("PLAYER_ENTERING_WORLD")
    assert g.eval("CVARS.nameplateShowEnemies") == "1", "only once"


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
