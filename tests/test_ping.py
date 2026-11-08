"""Pinging quest targets: one key (or the ring) pings the nearest creature your quests need with the Attack ping, or the
quest object you face with "look here"; anti-spam until it is dead or the chosen time passed.   python tests/test_ping.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern",)          # the classic client in these tests has no ping system (see the last tests)
MACRO_ATTACK = "/targetexact %s\n/ping [@target] attack"


def plain(t):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def game(style="modern"):
    g = Game(style)
    g.start()
    g.slash("auto off")
    g.join_party(["Anna"])
    g.advance(3)
    return g


def button(g):
    return g.eval("NS.pingButton()")


def press(g):
    g.eval("PRESS")(button(g))


def pings(g):
    return list(g.eval("PINGS").values())


# ---- the nearest quest creature ------------------------------------------------------------------------------------
def test_a_quest_creature_within_reach_comes_first_then_the_one_in_front_of_you(style):
    g = game(style)
    g.run('ADD_CREATURE("nameplate1", "Kobold Vermin", true, 300, 300, true)')     # near, off to the side
    g.run('ADD_CREATURE("nameplate2", "Kobold Worker", true, 960, 540, false)')    # far, right in front
    g.run('ADD_CREATURE("nameplate3", "Harvest Golem", false, 960, 540, true)')    # not for a quest
    assert g.eval("NS.nearestQuestCreature()") == "Kobold Vermin"
    g.run('ADD_CREATURE("nameplate4", "Kobold Miner", true, 950, 530, true)')      # near and in front
    assert g.eval("NS.nearestQuestCreature()") == "Kobold Miner"
    g.run("CREATURES.nameplate4.dead = true")
    assert g.eval("NS.nearestQuestCreature()") == "Kobold Vermin", "dead ones do not count"


def test_the_button_is_loaded_with_the_nearest_one_outside_combat(style):
    g = game(style)
    g.run('ADD_CREATURE("nameplate1", "Kobold Vermin", true, 960, 540, true)')
    g.advance(1.5)
    b = button(g)
    assert b.attrs.macrotext == MACRO_ATTACK % "Kobold Vermin" and b.attrs["qs-kind"] == "unit"


def test_with_no_quest_creature_it_pings_the_quest_object_you_face(style):
    g = game(style)
    g.advance(1.5)
    assert button(g).attrs.macrotext == "/ping [@softinteract,exists]" and button(g).attrs["qs-kind"] == "object"
    g.run('SOFTINTERACT = "Kobold Crate"')
    press(g)
    assert pings(g) == ["look:Kobold Crate"]
    g.slash("pingobjects off")
    g.advance(1.5)
    assert button(g).attrs.macrotext == ""


# ---- one press, one ping ---------------------------------------------------------------------------------------------------
def test_a_press_targets_it_and_pings_attack(style):
    g = game(style)
    g.run('ADD_CREATURE("nameplate1", "Kobold Vermin", true, 960, 540, true)')
    g.advance(1.5)
    press(g)
    assert pings(g) == ["attack:Kobold Vermin"] and g.eval("TARGET.name") == "Kobold Vermin"


def test_anti_spam_until_it_is_dead(style):
    g = game(style)
    g.run('ADD_CREATURE("nameplate1", "Kobold Vermin", true, 960, 540, true)')
    g.advance(1.5)
    press(g)
    press(g)
    assert pings(g) == ["attack:Kobold Vermin"], "still alive: held back"
    assert "ping held back" in "\n".join(g.printed())
    g.run("TARGET.dead = true; CREATURES.nameplate1.dead = true")
    g.run('ADD_CREATURE("nameplate2", "Kobold Worker", true, 960, 540, true)')
    g.advance(1.5)
    press(g)
    assert pings(g) == ["attack:Kobold Vermin", "attack:Kobold Worker"], "the one before died: the next one"


def test_outside_combat_it_unlocks_after_the_chosen_time(style):
    g = game(style)
    g.run('ADD_CREATURE("nameplate1", "Kobold Vermin", true, 960, 540, true)')
    g.slash("settings")
    idx = g.eval("(function() for i, r in ipairs(NS.settingRows) do if r.key == 'pingGap' then return i end end end)()")
    assert g.eval("NS.db.pingGap") == 10
    g.eval("NS.settingsClick")(idx, "RightButton")                 # 10 -> 5 seconds
    assert g.eval("NS.db.pingGap") == 5
    g.advance(1.5)
    press(g)
    g.advance(3)
    press(g)
    assert len(pings(g)) == 1, "3 seconds: still waiting"
    g.advance(2.5)
    press(g)
    assert len(pings(g)) == 2, "5 seconds passed"


def test_in_combat_only_a_dead_target_or_shift_unlocks_it(style):
    g = game(style)
    g.run('ADD_CREATURE("nameplate1", "Kobold Vermin", true, 960, 540, true)')
    g.advance(1.5)
    press(g)
    g.run("IN_COMBAT = true")
    g.advance(30)
    press(g)
    assert len(pings(g)) == 1, "no clock in combat: the time rule waits until combat ends"
    g.run("SHIFT = true")
    press(g)
    g.run("SHIFT = false")
    assert len(pings(g)) == 2, "Shift pings anyway"
    g.run('CREATURES.nameplate1.dead = true; ADD_CREATURE("nameplate2", "Kobold Worker", true, 960, 540, true)')
    g.advance(2)
    assert g.eval("NS.nearestQuestCreature()") == "Kobold Worker"
    assert button(g).attrs.macrotext == MACRO_ATTACK % "Kobold Vermin", "in combat the button keeps what it had"
    g.run("IN_COMBAT = false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(1.5)
    assert button(g).attrs["qs-gate"] == 0


# ---- the key -------------------------------------------------------------------------------------------------------------
def test_the_ping_key(style):
    g = game(style)
    g.slash("pingkey G")
    assert g.eval("BINDINGS.G") == "CLICK QuestSharingPingButton:LeftButton" and g.eval("NS.pingKeyName()") == "G"
    g.run('BINDINGS["CTRL-S"] = "TOGGLESOUND"')
    g.slash("pingkey CTRL-S")
    assert g.eval("BINDINGS['CTRL-S']") == "TOGGLESOUND"
    g.slash("pingkey none")
    assert g.eval("NS.pingKeyName()") is None


def test_the_ping_key_can_be_set_in_the_settings_by_pressing_it(style):
    g = game(style)
    g.slash("settings")
    g.eval("NS.settingsTab")("tracker")
    W = g.eval("NS._settingsWindow()")
    row = next(W.rows[n] for n in range(1, 19) if W.rows[n].frame.shown and plain(W.rows[n].text.text) == "Ping key")
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(row.button)
    assert "press a key" in row.button.text
    g.eval("NS.captureKeyPressed")("G")
    assert g.eval("BINDINGS.G") == "CLICK QuestSharingPingButton:LeftButton" and row.button.text == "G"
    assert g.eval("NS.quickKeyName()") is None, "the quick chat key is not touched"


# ---- the ring --------------------------------------------------------------------------------------------------------------
def test_a_ping_slot_on_the_ring(style):
    g = game(style)
    g.run('ADD_CREATURE("nameplate1", "Kobold Vermin", true, 960, 540, true)')
    g.slash("quick remove 7")                                      # make room on the ring (8 at most)
    g.slash("quick add Ping | @ping")
    g.advance(1.5)
    n = len(g.eval("NS.quickItems()"))
    assert g.eval(f"NS.quickItems()[{n}].text") == "@ping"
    g.eval("NS.quickOpen")(True)
    frame, slots, center, hint = g.eval("NS._quickWheel()")
    b = button(g)
    same = g.eval(f"(function() local _, slots = NS._quickWheel(); return NS.pingButton().point[2] == slots[{n}].button end)()")
    assert same is True, "the secure button lies over the ping slot"
    press(g)
    assert pings(g) == ["attack:Kobold Vermin"] and frame.shown is False, "a click pings and closes the ring"
    assert b.point[1] == "TOPLEFT" and b.point[4] == -200, "and the button goes back off screen"


def test_in_combat_the_ring_slot_points_to_the_key(style):
    g = game(style)
    g.slash("quick remove 7")
    g.slash("quick add Ping | @ping")
    g.advance(1.5)
    g.run("IN_COMBAT = true")
    g.eval("NS.quickOpen")(True)
    b = button(g)
    assert b.point[4] == -200, "secure buttons cannot be moved in combat"
    n = len(g.eval("NS.quickItems()"))
    g.run("PRINTED = {}")
    g.eval("NS.quickClick")(n)
    assert "ping key" in "\n".join(g.printed())


# ---- a client without the ping system --------------------------------------------------------------------------------------
def test_without_a_ping_system_nothing_breaks():
    g = Game("classic")
    g.start()
    g.advance(5)
    assert g.eval("NS.pingSupported()") is False and g.eval("NS.pingButton()") is None
    g.run("PRINTED = {}")
    g.slash("pingkey G")
    assert "no ping system" in "\n".join(g.printed()) and g.eval("BINDINGS.G") is None
    lines = "\n".join(g.eval("NS.doctorLines()").values())
    assert "[--] pings: this client has no ping system" in lines
    assert len(g.eval("NS.db.errors") or {}) == 0


def test_the_doctor_names_the_ping_key(style):
    g = game(style)
    g.slash("pingkey G")
    assert "[OK] pings: the game's ping system is here, ping key G" in "\n".join(g.eval("NS.doctorLines()").values())


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
