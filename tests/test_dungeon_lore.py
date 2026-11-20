"""Dungeon Journal lore (round 3, stream L): tools/build_dungeon_lore.py and the generated QuestSharing/DungeonLore.lua."""
import csv
import importlib.util
import pathlib
import re
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from test_dungeon_quests import game

STYLES = ("modern", "classic")
LORE = ROOT / "QuestSharing" / "DungeonLore.lua"
CACHE = pathlib.Path("/tmp/ejdata")

spec = importlib.util.spec_from_file_location("build_dungeon_lore", ROOT / "tools" / "build_dungeon_lore.py")
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


def write_csv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


INST_H = ["ID", "Name_lang", "Description_lang", "MapID"]
ENC_H = ["Name_lang", "Description_lang", "ID", "JournalInstanceID", "OrderIndex"]
SEC_H = ["ID", "Title_lang", "BodyText_lang", "JournalEncounterID", "OrderIndex", "ParentSectionID", "Type",
         "SpellID", "IconFileDataID", "DifficultyMask"]


def mini_tables(tmp):
    """A tiny journal: a classic and a reworked Blackrock Depths, the Deadmines with a Cataclysm boss, a stage heading."""
    write_csv(tmp / "JournalInstance.csv", INST_H, [
        [63, "Deadmines", "Old |cFFFF0000gold|r mines.", 36],
        [228, "Blackrock Depths", "Classic depths.", 230],
        [1301, "Blackrock Depths", "Reworked depths.", 2792],
        [1197, "Uldaman: Legacy of Tyr", "Dragonflight.", 2451],
        [500, "Somewhere Else", "Not ours.", 1],
    ])
    write_csv(tmp / "JournalEncounter.csv", ENC_H, [
        ["Edwin VanCleef", "Defias leader.", 10, 63, 2],
        ["Rhahk'Zor", "Ogre.", 11, 63, 1],
        ["Helix Gearbreaker", "Cataclysm goblin.", 12, 63, 3],
        ["Lord Roccor", "Classic Roccor.", 20, 228, 1],
        ["Magmus", "Classic Magmus.", 21, 228, 2],
        ["Lord Roccor", "Reworked Roccor.", 30, 1301, 1],
        ["Ghost", "Not ours.", 40, 500, 1],
    ])
    long = "VanCleef stabs his target for $14874s1 Physical damage every $14874t1 sec. " + "Again and again. " * 12
    write_csv(tmp / "JournalEncounterSection.csv", SEC_H, [
        [1, "Rupture", long, 10, 1, 0, 2, 0, 132302, -1],
        [2, "Shadowstep", "Steps behind a player within $15657a1 yards.", 10, 2, 0, 2, 15657, 0, -1],
        [3, "Overview", "Not an ability.", 10, 0, 0, 3, 0, 0, -1],
        [4, "Heroic Thing", "Only on heroic.", 10, 3, 0, 2, 0, 0, 14],
        [5, "Allies", "Calls |Hspell:1|h[Thugs]|h for help.", 10, 4, 0, 2, 0, 0, -1],
        [6, "Vanish", "Vanishes.", 10, 5, 0, 2, 0, 0, -1],
        [7, "Fifth", "One too many.", 10, 6, 0, 2, 0, 0, -1],
        [8, "Stage One", "A heading.", 11, 1, 0, 0, 0, 0, -1],
        [9, "Slam", "Rhahk'Zor slams $[!16 hard$]$[16 mythic only$].", 11, 1, 8, 2, 0, 0, -1],
        [10, "Ground Tremor", "Stuns.", 20, 1, 0, 2, 6524, 0, 1],
        [11, "Reworked", "New stuff.", 30, 1, 0, 2, 0, 0, -1],
    ])
    return gen.fetch(tmp)  # every CSV is cached: no download


def built():
    with tempfile.TemporaryDirectory() as d:
        return gen.build(mini_tables(pathlib.Path(d)))


def test_norm_lower_case_no_punctuation_no_leading_the():
    assert gen.norm("The Deadmines") == "deadmines"
    assert gen.norm("Mr. Smite") == "mr smite"
    assert gen.norm("Rhahk'Zor") == "rhahkzor"
    assert gen.norm('Eric "The Swift"') == "eric the swift"
    assert gen.norm("Crowd Pummeler 9-60") == "crowd pummeler 9 60"
    assert gen.norm("Dire Maul - Capital Gardens") == "dire maul capital gardens"


def test_clean_drops_tokens_colour_codes_and_links():
    assert gen.clean("Deals $6304s2 Physical damage.") == "Deals Physical damage."
    assert gen.clean("Stuns all players within $6524a1 yards for $6524d.") == "Stuns all players nearby."
    assert gen.clean("A |cFF2959D3|Hspell:1|h[Fire Nova]|h|r hits.") == "A Fire Nova hits."
    assert gen.clean("Hits $[!16 hard$]$[16 mythic$].") == "Hits hard."
    assert gen.clean("Hits up to $1234x1 players.") == "Hits several players."
    assert "$" not in gen.clean("Grows by $1234s1% and ${$s1*2} more.")


def test_cut_keeps_short_text_and_cuts_long_text_near_the_limit():
    assert gen.cut("Short.", 140) == "Short."
    text = "word " * 60
    out = gen.cut(text.strip(), 140)
    assert len(out) <= 143 and out.endswith("...")
    out = gen.cut("One sentence here. " * 20, 140)
    assert out.endswith(".") and len(out) <= 141


def test_classic_instance_wins_and_reworks_are_skipped():
    dungeons, bosses, report = built()
    assert dungeons[1584]["description"] == "Classic depths."      # the instance whose bosses match ours
    assert bosses["lord roccor"]["description"] == "Classic Roccor."
    assert 1337 not in dungeons                                    # Uldaman: only the Dragonflight rework here
    assert dungeons[1581]["description"] == "Old gold mines."      # colour codes removed


def test_only_our_classic_bosses_are_written():
    dungeons, bosses, report = built()
    assert "edwin vancleef" in bosses and "rhahkzor" in bosses and "magmus" in bosses
    assert "helix gearbreaker" not in bosses, "a Cataclysm boss of the reworked Deadmines"
    assert "ghost" not in bosses, "a boss of a dungeon we do not have"


def test_abilities_top_level_at_most_four_cut_and_spell_ids():
    dungeons, bosses, report = built()
    edwin = bosses["edwin vancleef"]["abilities"]
    assert [a["name"] for a in edwin] == ["Rupture", "Shadowstep", "Allies", "Vanish"]  # no overview, no heroic-only, max 4
    assert edwin[0]["spellID"] == 14874 and edwin[0]["icon"] == 132302   # spell from the $-token
    assert edwin[1]["spellID"] == 15657 and edwin[1]["text"] == "Steps behind a player nearby."
    assert edwin[2]["text"] == "Calls Thugs for help."
    assert all(len(a["text"]) <= 143 and "$" not in a["text"] for a in edwin)
    slam = bosses["rhahkzor"]["abilities"]
    assert [a["name"] for a in slam] == ["Slam"] and slam[0]["text"] == "Rhahk'Zor slams hard."  # under a stage heading


def test_clean_leaves_no_orphan_words_and_ends_a_line_with_a_stop():
    assert gen.clean("Inflicting $1s1 Shadow damage for $1d and reducing speed.") == "Inflicting Shadow damage and reducing speed."
    assert gen.clean("Additional Nature damage for $2s2 to all players.") == "Additional Nature damage to all players."
    assert gen.clean("Instantly dealing $3s1% of his normal damage.") == "Instantly dealing part of his normal damage."
    assert gen.clean("Healing himself for ${$4E1*100}% of damage dealt.") == "Healing himself for part of damage dealt."
    assert gen.clean("Takes a sip of soup, restoring $s1% of his health.") == "Takes a sip of soup, restoring part of his health."
    assert gen.clean("Strikes, reducing $s2% of their armor.") == "Strikes, reducing part of their armor."
    assert gen.clean("Burns an enemy for $5s2 Fire damage.") == "Burns an enemy for Fire damage."
    assert gen.clean("Course: Advanced Studies\n\nThe recent defeat.") == "Course: Advanced Studies. The recent defeat."
    assert gen.clean("Done.\n\nNext.") == "Done. Next."
    assert gen.clean("Attacks in a whirlwind that lasts $450515d. While he rages.") == "Attacks in a whirlwind. While he rages."
    assert gen.clean("Flurry can stack up to 3 times and lasts for $17687d.") == "Flurry can stack up to 3 times."
    assert gen.clean("Damage is increased by $1s2%.  This effect lasts for $14872d.") == "Damage is increased."
    assert gen.clean("A whirlwind of steel that lasts $50228d., inflicting damage.") == "A whirlwind of steel, inflicting damage."


def test_creature_heading_only_for_its_own_boss():
    by_parent = {}
    for row in [
        {"ID": "1", "Title_lang": "Commander Durand", "ParentSectionID": "0", "Type": "0", "BodyText_lang": ""},
        {"ID": "2", "Title_lang": "Flash of Steel", "ParentSectionID": "1", "Type": "2", "BodyText_lang": "Strikes."},
        {"ID": "3", "Title_lang": "High Inquisitor Whitemane", "ParentSectionID": "0", "Type": "0", "BodyText_lang": ""},
        {"ID": "4", "Title_lang": "Holy Smite", "ParentSectionID": "3", "Type": "2", "BodyText_lang": "Smites."},
    ]:
        by_parent.setdefault((7, int(row["ParentSectionID"])), []).append(row)
    assert [a["name"] for a in gen.abilities(7, by_parent, "High Inquisitor Whitemane")] == ["Holy Smite"]
    assert [a["name"] for a in gen.abilities(7, by_parent, "Someone Else")] == ["Flash of Steel", "Holy Smite"]
    assert "Lord Aurius Rivendare" not in gen.ALIASES, "the son, not classic Baron Rivendare"


def test_shipped_text_has_no_orphan_words():
    text = LORE.read_text(encoding="utf-8").split("function L.norm")[0]
    bad = re.findall(r".{30}\b(?:for|dealing|restoring|healing|increasing|reducing) (?:and|to|of)\b.{10}", text)
    assert not bad, bad
    assert "Flash of Steel" not in re.search(r'^b\["high inquisitor whitemane"\].*$', text, re.M).group(0)
    assert "Aurius" not in text
    assert not re.search(r"Course: [^.\"]*[a-z0-9] [A-Z][a-z]+ recent", text)
    for ability in re.findall(r'text="([^"]*)"', text):
        assert not re.search(r"\b(?:that|which|and|for)\s*[.,;]", ability), ability
        assert not re.search(r"\blasts\.|This effect\.", ability), ability
        assert not re.search(r"(\w+) damage and (?:an )?additional \1 damage", ability), ability


def test_written_lua_has_the_api():
    dungeons, bosses, report = built()
    with tempfile.TemporaryDirectory() as d:
        out = pathlib.Path(d) / "DungeonLore.lua"
        gen.write(dungeons, bosses, out)
        text = out.read_text()
    assert text.startswith("-- Dungeon and boss lore") and "GENERATED" in text
    assert "function L.dungeon(area, name)" in text and "function L.boss(name)" in text


def test_shipped_file_api(style):
    g = game(style, open_tab=False)
    L = g.eval("NS.dungeonLore")
    assert L.dungeon(1581, None).description.startswith("It is said the Deadmines")
    assert L.dungeon(None, "The Deadmines").description == L.dungeon(1581, None).description  # by name too
    assert L.dungeon(0, "deadmines") is not None
    assert L.dungeon(16919, "The Hall of Thanes").description.startswith("Hidden beneath the High Seat")  # Forever: hand-written intro
    edwin = L.boss("Edwin VanCleef")
    assert edwin.description.startswith("Formerly the leader") and len(list(edwin.abilities.values())) >= 1
    assert L.boss("edwin  vancleef") is not None and L.boss("Mr. Smite") is not None
    assert L.boss("Baelog") is not None and L.boss('Eric "The Swift"') is not None  # the Lost Dwarves group
    assert L.boss("Helix Gearbreaker") is None and L.boss("") is None and L.boss(None) is None
    assert not g.eval("NS.db.errors")


def test_lua_norm_matches_the_generator(style):
    g = game(style, open_tab=False)
    for name in ("The Deadmines", "Mr. Smite", "Rhahk'Zor", 'Eric "The Swift"', "Crowd Pummeler 9-60",
                 "Nekrum & Sezz'ziz", "Groyat, the Blind Hunter", "Zul'Farrak"):
        assert g.eval("NS.dungeonLore.norm")(name) == gen.norm(name), name


def test_shipped_file_is_small_and_clean():
    text = LORE.read_text(encoding="utf-8")
    assert len(text) < 150_000
    assert "$" not in re.sub(r'"[^"]*%[^"]*"', "", text.split("function L.norm")[0])  # no $-tokens in the data
    assert not re.search(r"\|c[0-9a-fA-F]{8}|\|H|\|T", text)
    assert "ForeverDungeonJournal" not in text
    for m in re.finditer(r"abilities=\{(.*?)\}\}", text):
        assert m.group(1).count("{name=") <= 4
    for m in re.finditer(r'text="((?:[^"\\]|\\.)*)"', text):
        assert len(m.group(1)) <= 150, m.group(1)
    keys = re.findall(r"^d\[(\d+)\]", text, re.M)
    ours = {int(a) for a, _ in gen.our_dungeons()}
    assert keys and all(int(k) in ours for k in keys)


def test_shipped_file_matches_the_generator_when_the_cache_is_there():
    if not all((CACHE / (t + ".csv")).exists() for t in gen.TABLES):
        print("   (skipped: no /tmp/ejdata cache)")
        return
    dungeons, bosses, report = gen.build(gen.fetch(CACHE))
    with tempfile.TemporaryDirectory() as d:
        out = pathlib.Path(d) / "DungeonLore.lua"
        gen.write(dungeons, bosses, out)
        assert out.read_text(encoding="utf-8") == LORE.read_text(encoding="utf-8"), "run tools/build_dungeon_lore.py"
    assert len(dungeons) >= 19 and len(bosses) >= 100


if __name__ == "__main__":
    import inspect
    failed = total = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        styles = STYLES if "style" in inspect.signature(fn).parameters and inspect.signature(fn).parameters["style"].default is inspect._empty else (None,)
        for style in styles:
            total += 1
            try:
                fn(style) if style else fn(); print("ok", name, style or "")
            except Exception as exc:
                failed += 1; print("FAIL", name, style or "", type(exc).__name__, str(exc)[:500])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
