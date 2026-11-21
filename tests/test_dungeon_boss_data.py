"""DungeonBossData.lua: the generated official boss list (tools/build_boss_data.py). No network."""
import csv
import os
import pathlib
import re
import subprocess
import sys
import tempfile
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from test_loot import game

STYLES = ("modern", "classic")
ROOT = pathlib.Path(__file__).resolve().parents[1]
LUA = ROOT / "QuestSharing" / "DungeonBossData.lua"
GEN = ROOT / "tools" / "build_boss_data.py"
DISPLAYS = pathlib.Path("/tmp/ejdata/f_CreatureDisplayInfo.csv")
BOSSES = pathlib.Path("/tmp/bossdata/bosses.json")
AREAS = (209, 491, 717, 718, 719, 721, 722, 796, 1176, 1337, 1477, 1581, 1583, 1584, 2017, 2057, 2100, 2437, 2557,
         16544, 16550, 16554, 16611, 16620, 16667, 16732, 16842, 16919)
DEADMINES = ["Rhahk'Zor", "Sneed", "Miner Johnson", "Gilnid", "Captain Greenskin", "Mr. Smite", "Cookie",
             "Edwin VanCleef"]


def arr(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def all_bosses(g):
    data = g.eval("NS.dungeonBossData.bosses")
    return {int(a): arr(data[a]) for a in data.keys()}


def find(g, area, name):
    return next(b for b in arr(g.eval(f"NS.dungeonBossData.list({area})")) if b.name == name)


def test_file_loads_and_lists_every_dungeon(style):
    g = game(style)
    assert not g.eval("NS.db.errors")
    data = all_bosses(g)
    assert sorted(data) == sorted(AREAS)
    assert sum(len(v) for v in data.values()) == 241
    assert [b.name for b in arr(g.eval("NS.dungeonBossData.list(1581)"))] == DEADMINES
    assert [b.name for b in arr(g.eval("NS.dungeonBossData.list('1581')"))] == DEADMINES
    assert g.eval("NS.dungeonBossData.list(12345)") is None
    assert g.eval("NS.dungeonBossData.list(nil)") is None


def test_order_and_npc_ids(style):
    g = game(style)
    for area, rows in all_bosses(g).items():
        assert [b.order for b in rows] == list(range(1, len(rows) + 1)), area
        for b in rows:
            assert isinstance(b.name, str) and b.name and isinstance(b.encounterID, int)
            if b.npcID is not None:
                assert b.npcIDs is not None and b.npcID == b.npcIDs[1], (area, b.name)
            else:
                assert b.npcIDs is None, (area, b.name)


def test_hand_fields_groups_and_optional(style):
    g = game(style)
    sneed = find(g, 1581, "Sneed")
    assert 642 in arr(sneed.lootNpcIDs)
    dwarves = find(g, 1337, "The Lost Dwarves")
    assert dwarves.group is True and len(arr(dwarves.members)) == 3 and "Baelog" in arr(dwarves.members)
    for area, name in ((1584, "Ring of Law"), (1584, "The Seven"), (1584, "The Vault")):
        assert find(g, area, name).group is True
    assert find(g, 16732, "Highland Horror").optional is True
    assert find(g, 1581, "Edwin VanCleef").optional is None
    assert find(g, 719, "Geilhast").npcName == "Gelihast"
    assert find(g, 1581, "Rhahk'Zor").match is None                     # R1's match field is dropped


def test_ej_art_only_in_classic_dungeons(style):
    g = game(style)
    data = all_bosses(g)
    for area, rows in data.items():
        for b in rows:
            if b.ejFile is not None:
                assert area < 16000 and isinstance(b.ejFile, int) and b.ejFile > 0, (area, b.name)
    assert find(g, 16544, "Mana Devourer").ejFile is None
    assert find(g, 16611, "The Butcher").ejFile is None
    assert sum(b.ejFile is not None for rows in data.values() for b in rows) > 100
    # the creature's art names another boss: the art by boss name wins (review follow-up)
    assert find(g, 1176, "Gahz'rilla").ejFile == 607604            # ui-ej-boss-gahzrilla, not ui-ej-boss-ghazan
    assert find(g, 2017, "Magistrate Barthilas").ejFile == 607704  # his own art, not The Ravenian's 607791


def generator():
    import importlib.util
    spec = importlib.util.spec_from_file_location("build_boss_data", GEN)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_generator_ej_file_choice_and_retry_sleeps(style):
    if style != "modern":
        return
    gen = generator()
    by_name = {"fdid": 2}
    assert gen.ej_file({"fdid": 1, "file": "interface/encounterjournal/ui-ej-boss-ghazan.blp", "name": "Gahz'rilla"},
                       by_name, "Gahz'rilla") == 2
    assert gen.ej_file({"fdid": 1, "file": "interface/encounterjournal/ui-ej-boss-baelog.blp", "name": "Baelog"},
                       by_name, "The Lost Dwarves") == 1            # the stem names the creature: kept
    assert gen.ej_file({"fdid": 1, "file": "x/ui-ej-boss-the ravenian.blp", "name": "The Ravenian"}, {}, "The Ravenian") == 1
    assert gen.ej_file({"fdid": 1, "file": "x/ui-ej-boss-other.blp", "name": "Me"}, {}, "Me") == 1  # nothing better
    assert gen.ej_file({}, by_name, "Me") == 2
    # three failed tries: backoff 2 and 4 s between them, no sleep after the last
    sleeps = []

    class Done:
        returncode, stdout = 6, b"\n000"
    run, sleep = gen.subprocess.run, gen.time.sleep  # the shared modules: restored below
    gen.subprocess.run = lambda *a, **k: Done()
    gen.time.sleep = sleeps.append
    try:
        import contextlib, io
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stderr(io.StringIO()):
            web = gen.Wowhead(tmp, offline=False)
            web.last = -1e9
            assert web.page(1) is None and web.failed == 1
    finally:
        gen.subprocess.run, gen.time.sleep = run, sleep
    assert [s for s in sleeps if s >= 2] == [2, 4], sleeps


def test_missing_npc_ids_from_wowhead_suggestions(style):
    g = game(style)
    ezra = find(g, 2017, "Ezra Grimm")                              # R1 had no npc: Wowhead suggestions, exact name
    assert ezra.npcID == 11058 and arr(ezra.npcIDs) == [11058]
    # Wowhead Forever suggestions have no npc named exactly "The Butcher" / "Infurnus" (2026-11-21): no guess is
    # shipped (not "Gronok the Butcher" 263749). If a later run finds them, they must be single, consistent ids.
    for area, name in ((16611, "The Butcher"), (16919, "Infurnus")):
        b = find(g, area, name)
        if b.npcID is not None:
            assert isinstance(b.npcID, int) and arr(b.npcIDs) == [b.npcID], (area, name)


def test_generator_suggestion_pick(style):
    if style != "modern":
        return
    gen = generator()
    answer = {"results": [
        {"type": 5, "id": 5214, "name": "Ezra Grimm"},               # a quest of that name: not an npc
        {"type": 1, "id": 3886, "name": "Razorclaw the Butcher"},    # not the exact name
        {"type": 1, "id": 11058, "name": "Ezra Grimm"},
        {"type": 1, "id": 250001, "name": "Ezra Grimm"},
        {"type": 1, "id": 11059, "name": "Ezra Grimm"},
    ]}
    assert gen.suggest_npc(answer, "Ezra Grimm", forever=False) == 11058     # classic area: first classic id
    assert gen.suggest_npc(answer, "Ezra Grimm", forever=True) == 250001     # Forever area: ids >= 200000 win
    assert gen.suggest_npc(answer, "ezra grimm", forever=False) is None      # exact match only
    assert gen.suggest_npc(answer, "The Butcher", forever=True) is None
    assert gen.suggest_npc({"results": []}, "Infurnus", forever=True) is None
    assert gen.suggest_npc(None, "Infurnus", forever=True) is None
    assert gen.suggest_file("Rath'mael") == "Rath%27mael.json" and "/" not in gen.suggest_file("a/b")
    # offline: cache only, never the network
    run = gen.subprocess.run
    gen.subprocess.run = lambda *a, **k: (_ for _ in ()).throw(AssertionError("network used offline"))
    try:
        with tempfile.TemporaryDirectory() as tmp:
            web = gen.Wowhead(tmp, offline=True, suggest=tmp)
            assert web.suggestions("Infurnus") is None and web.page(11058) is None
            pathlib.Path(tmp, "Ezra%20Grimm.json").write_text('{"results":[{"type":1,"id":11058,"name":"Ezra Grimm"}]}')
            assert gen.suggest_npc(web.suggestions("Ezra Grimm"), "Ezra Grimm", False) == 11058
    finally:
        gen.subprocess.run = run


def test_display_ids_are_valid(style):
    g = game(style)
    ids = [(a, b.name, b.displayID) for a, rows in all_bosses(g).items() for b in rows if b.displayID is not None]
    assert ids and all(isinstance(d, int) and d > 0 for _, _, d in ids)
    if not DISPLAYS.exists():
        return
    with open(DISPLAYS, newline="", encoding="utf-8") as f:
        known = {int(r["ID"]) for r in csv.DictReader(f)}
    bad = [x for x in ids if x[2] not in known]
    assert not bad, bad[:5]


def test_no_addon_paths_no_false_and_small(style):
    text = LUA.read_text(encoding="utf-8")
    assert "AddOns" not in text and "Interface\\" not in text
    assert not re.search(r"\bfalse\b", text)
    assert len(text.encode("utf-8")) < 60 * 1024
    assert "match =" not in text


def test_generator_offline_reproduces_the_shipped_file(style):
    if style != "modern" or not BOSSES.exists():
        return
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "DungeonBossData.lua")
        r = subprocess.run([sys.executable, "-I", str(GEN), "--offline", "--out", out],
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stderr[-2000:]
        assert pathlib.Path(out).read_bytes() == LUA.read_bytes()


if __name__ == "__main__":
    failed = total = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        for style in STYLES:
            total += 1
            try:
                fn(style); print("ok", name, style)
            except Exception as exc:
                failed += 1; print("FAIL", name, style, type(exc).__name__, str(exc)[:500])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
