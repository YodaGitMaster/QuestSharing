"""Tools as modules (Modules.lua): each tool can be switched off in Settings > General > Tools.
     python tests/test_modules.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game, FILES, ADDON_DIR  # noqa: E402


def game(pre=""):
    g = Game("modern")
    if pre:
        g.run(pre)
    g.start()
    return g


def started_with(saved):
    """the saved settings hold `saved` before the addon loads (as after a /reload)"""
    g = Game("modern")
    g.run('QuestSharingDB = { near = false, panel = false, dbVersion = 3, welcomed = "x", %s }' % saved)
    g.fire("ADDON_LOADED", "QuestSharing")
    g.fire("PLAYER_ENTERING_WORLD")
    return g


def test_every_file_after_modules_lua_says_its_module():
    untagged_ok = {"Compat.lua", "Core.lua", "Modules.lua", "SkinningData.lua", "CookingReference.lua",
                   "DungeonQuestData.lua", "DungeonLore.lua", "DungeonBossData.lua"}   # generated data: no events
    for f in FILES:
        if f in untagged_ok:
            continue
        assert "ns.inModule(" in (ADDON_DIR / f).read_text(), f + " has no ns.inModule line"


def test_every_module_is_on_by_default_and_has_a_settings_switch():
    g = game()
    ids = list(g.eval("(function() local t = {} for _, m in ipairs(NS.MODULES) do t[#t+1] = m.id end return t end)()").values())
    assert len(ids) >= 10
    for i in ids:
        assert g.eval('NS.db.module_%s' % i) is True, i
        assert g.eval('NS.moduleOn("%s")' % i) is True
        assert g.eval('(function() for _, r in ipairs(NS.settingRows) do if r.key == "module_%s" and r.tab == "general" then return true end end end)()' % i), i


def test_an_off_module_hears_no_events_and_its_timers_are_dropped():
    g = game()
    g.run('NS.inModule("bags"); NS.on("QS_TEST_EVENT", function() HEARD = (HEARD or 0) + 1; NS.after(1, function() TICKED = true end) end); NS.inModule(nil)')
    g.fire("QS_TEST_EVENT")
    assert g.eval("HEARD") == 1
    g.run('NS.setSetting("module_bags", false)')
    g.advance(2)
    assert g.eval("TICKED") is None, "the timer set while on is dropped once the module is off"
    g.fire("QS_TEST_EVENT")
    assert g.eval("HEARD") == 1, "no event while off"
    g.run('NS.setSetting("module_bags", true)')
    g.fire("QS_TEST_EVENT")
    g.advance(2)
    assert g.eval("HEARD") == 2 and g.eval("TICKED") is True


def test_handlers_and_timers_keep_their_module_and_no_stale_tag_is_left():
    g = game()
    assert g.eval("NS.currentModule") is None, "the last loaded file's tag must not stick"
    g.run('NS.inModule("quick"); NS.on("QS_OUTER", function() NS.on("QS_INNER", function() INNER = (INNER or 0) + 1 end) end); NS.inModule(nil)')
    g.fire("QS_OUTER")
    g.run('NS.setSetting("module_quick", false)')
    g.fire("QS_INNER")
    assert g.eval("INNER") is None, "a handler registered inside a quick handler belongs to quick"
    assert g.eval("NS.currentModule") is None


def test_commands_of_an_off_module_say_it_is_off():
    g = game()
    g.run('NS.setSetting("module_dungeons", false)')
    before = len(g.printed())
    g.slash("dungeons")
    g.slash("bossdump")
    out = g.printed()[before:]
    assert sum("is switched off" in l for l in out) == 2, out
    assert g.eval("NS.dungeonQuests.open()") is None
    assert any("Dungeon journal" in l for l in g.printed()[before:])


def test_background_refreshes_of_an_off_module_stay_quiet():
    g = started_with("module_bags = false")
    assert g.eval('NS.moduleOn("bags")') is False, "the saved switch is read at load"
    before = len(g.printed())
    g.run("NS.bagTools.refresh()")
    assert g.printed()[before:] == []


def test_settings_rows_of_an_off_module_are_dimmed_with_the_module_name():
    g = game()
    row = '(function() for _, r in ipairs(NS.settingRows) do if r.key == "%s" then return r end end end)()'
    assert g.eval("NS.settingNeedsOff(%s)" % (row % "autoSortBags")) is None
    g.run('NS.setSetting("module_bags", false)')
    assert g.eval("NS.settingNeedsOff(%s)" % (row % "autoSortBags")) == "Bags"
    assert g.eval("NS.settingNeedsOff(%s)" % (row % "module_bags")) is None, "the switch itself stays usable"
    g.run('NS.setSetting("module_combat", false)')
    assert g.eval("NS.settingNeedsOff(%s)" % (row % "aggroPlates")) == "Fight tools"


def test_switching_a_module_says_to_reload():
    g = game()
    before = len(g.printed())
    g.run('NS.setSetting("module_finder", false)')
    assert any("switched off" in l and "/reload" in l for l in g.printed()[before:])


def test_other_modules_keep_working_when_one_is_off():
    g = started_with("module_dungeons = false, module_guide = false")
    g.join_party(["Anna"])
    g.advance(10)
    assert len(g.eval("NS.db.errors") or {}) == 0


def test_every_module_off_still_loads_and_runs_without_errors():
    g = Game("modern")
    ids = list(g.eval("(function() local t = {} for _, m in ipairs(NS.MODULES) do t[#t+1] = m.id end return t end)()").values())
    g = started_with(", ".join("module_%s = false" % i for i in ids))
    g.fire("PLAYER_LOGIN")
    g.join_party(["Anna"])
    g.advance(10)
    for cmd in ("dungeons", "sort", "plan", "lfg", "quick", "settings", "status", "help"):
        g.slash(cmd)
    assert len(g.eval("NS.db.errors") or {}) == 0, g.eval("NS.db.errors")


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
    print()
    print("%d failed" % failed if failed else "all passed")
    sys.exit(1 if failed else 0)
