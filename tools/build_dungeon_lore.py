import json
"""Regenerate QuestSharing/DungeonLore.lua: dungeon and boss text from Blizzard's Encounter Journal.

Source: the retail client tables JournalInstance, JournalEncounter and JournalEncounterSection as CSV from
https://wago.tools/db2/<table>/csv (the WoW Forever build 1.60.1 has no journal tables). Blizzard text, shipped like
Questie ships Blizzard quest text. Only our dungeons (QuestSharing/DungeonQuestData.lua D.names) and their classic
bosses are written, so the file stays small. The addon never downloads anything at runtime.

Usage: python3 tools/build_dungeon_lore.py [cache_dir]   (default /tmp/ejdata; missing CSVs are fetched with curl,
because the system python may lack SSL certificates)
"""
import csv
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "QuestSharing" / "DungeonLore.lua"
DATA = ROOT / "QuestSharing" / "DungeonQuestData.lua"
URL = "https://wago.tools/db2/{}/csv"
TABLES = ("JournalInstance", "JournalEncounter", "JournalEncounterSection")
MAX_ABILITIES, MAX_TEXT = 4, 140

# Retail reworks of a dungeon we know in its classic form: never used (their bosses and lore are another dungeon).
REWORKS = {1197: "Uldaman: Legacy of Tyr (Dragonflight)", 559: "Upper Blackrock Spire (Warlords)"}
# Journal instances that are part of one of our dungeons under another name.
EXTRA_INSTANCES = {"scarlet monastery": ["scarlet halls"]}

# The classic bosses of each dungeon (AtlasLoot / in-game names). Only these are written, so the Cataclysm bosses of
# a reworked dungeon (Helix Gearbreaker in the Deadmines) never show. Dungeons not listed keep every journal boss.
CLASSIC_BOSSES = {
    "ragefire chasm": ["Taragaman the Hungerer", "Oggleflint", "Jergosh the Invoker", "Bazzalan"],
    "wailing caverns": ["Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas", "Skum", "Lord Serpentis",
                        "Verdan the Everliving", "Mutanus the Devourer", "Deviate Faerie Dragon"],
    "deadmines": ["Rhahk'Zor", "Miner Johnson", "Sneed's Shredder", "Sneed", "Gilnid", "Mr. Smite",
                  "Captain Greenskin", "Edwin VanCleef", "Cookie"],
    "shadowfang keep": ["Rethilgore", "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale",
                        "Odo the Blindwatcher", "Fenrus the Devourer", "Wolf Master Nandos", "Archmage Arugal",
                        "Deathsworn Captain"],
    "blackfathom deeps": ["Ghamoo-ra", "Lady Sarevess", "Gelihast", "Lorgus Jett", "Baron Aquanis",
                          "Twilight Lord Kelris", "Old Serra'kis", "Aku'mai"],
    "stockade": ["Targorr the Dread", "Kam Deepfury", "Hamhock", "Bazil Thredd", "Dextren Ward",
                 "Bruegal Ironknuckle"],
    "gnomeregan": ["Grubbis", "Viscous Fallout", "Electrocutioner 6000", "Crowd Pummeler 9-60",
                   "Dark Iron Ambassador", "Mekgineer Thermaplugg"],
    "razorfen kraul": ["Roogug", "Aggem Thorncurse", "Death Speaker Jargba", "Overlord Ramtusk",
                       "Agathelos the Raging", "Blind Hunter", "Charlga Razorflank", "Earthcaller Halmgar"],
    "scarlet monastery": ["Interrogator Vishas", "Bloodmage Thalnos", "Houndmaster Loksey", "Arcanist Doan",
                          "Herod", "High Inquisitor Fairbanks", "Scarlet Commander Mograine",
                          "High Inquisitor Whitemane", "Ironspine", "Azshir the Sleepless", "Fallen Champion"],
    "razorfen downs": ["Tuten'kash", "Mordresh Fire Eye", "Glutton", "Ragglesnout", "Amnennar the Coldbringer",
                       "Plaguemaw the Rotting"],
    "uldaman": ["Revelosh", "Baelog", "Olaf", "Eric \"The Swift\"", "Ironaya", "Obsidian Sentinel",
                "Ancient Stone Keeper", "Galgann Firehammer", "Grimlok", "Archaedas"],
    "zulfarrak": ["Antu'sul", "Theka the Martyr", "Witch Doctor Zum'rah", "Nekrum Gutchewer",
                   "Shadowpriest Sezz'ziz", "Sergeant Bly", "Hydromancer Velratha", "Ruuzlu",
                   "Chief Ukorz Sandscalp", "Gahz'rilla", "Zerillis", "Dustwraith"],
    "maraudon": ["Noxxion", "Razorlash", "Lord Vyletongue", "Celebras the Cursed", "Landslide", "Tinkerer Gizlock",
                 "Rotgrip", "Princess Theradras", "Meshlok the Harvester"],
    "temple of atalhakkar": ["Atal'alarion", "Dreamscythe", "Weaver", "Avatar of Hakkar", "Jammal'an the Prophet",
                              "Ogom the Wretched", "Morphaz", "Hazzas", "Shade of Eranikus", "Spawn of Hakkar"],
    "blackrock depths": ["High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar", "Ring of Law",
                         "Pyromancer Loregrain", "Lord Incendius", "Warder Stilgiss", "Fineous Darkvire",
                         "Bael'Gar", "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx",
                         "Ribbly Screwspigot", "Plugger Spazzring", "Ambassador Flamelash", "The Seven", "Magmus",
                         "Emperor Dagran Thaurissan", "Princess Moira Bronzebeard"],
    "blackrock spire": ["Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone", "Mother Smolderweb",
                        "Urok Doomhowl", "Quartermaster Zigris", "Halycon", "Gizrul the Slavener",
                        "Overlord Wyrmthalak", "Bannok Grimaxe", "Spirestone Butcher", "Pyroguard Emberseer",
                        "Solakar Flamewreath", "Goraluk Anvilcrack", "Warchief Rend Blackhand", "Gyth", "The Beast",
                        "General Drakkisath", "Jed Runewatcher"],
    "dire maul": ["Pusillin", "Lethtendris", "Hydrospawn", "Zevrim Thornhoof", "Alzzin the Wildshaper",
                  "Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris", "Immol'thar", "Prince Tortheldrin",
                  "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush",
                  "Cho'Rush the Observer", "King Gordok", "Tsu'zee"],
    "stratholme": ["Timmy the Cruel", "Malor the Zealous", "Cannon Master Willey", "Archivist Galford", "Balnazzar",
                   "The Unforgiven", "Hearthsinger Forresten", "Postmaster Malown", "Baroness Anastari",
                   "Nerub'enkan", "Maleki the Pallid", "Magistrate Barthilas", "Ramstein the Gorger",
                   "Baron Rivendare", "Skul", "Stratholme Courier"],
    "scholomance": ["Kirtonos the Herald", "Jandice Barov", "Rattlegore", "Marduk Blackpool", "Vectus",
                    "Ras Frostwhisper", "Instructor Malicia", "Doctor Theolen Krastinov", "Lorekeeper Polkelt",
                    "The Ravenian", "Lord Alexei Barov", "Lady Illucia Barov", "Darkmaster Gandling"],
}
# Journal encounter name -> the classic name(s) it covers (group encounters and renamed bosses).
ALIASES = {
    "The Lost Dwarves": ["Baelog", "Olaf", "Eric \"The Swift\""],
    "Nekrum & Sezz'ziz": ["Nekrum Gutchewer", "Shadowpriest Sezz'ziz"],
    "Wardens of the Dream": ["Dreamscythe", "Weaver", "Morphaz", "Hazzas"],
    "Warlord Ramtusk": ["Overlord Ramtusk"],
    "Groyat, the Blind Hunter": ["Blind Hunter"],
    "Commander Malor": ["Malor the Zealous"],
    "Willey Hopebreaker": ["Cannon Master Willey"],
    "Instructor Galford": ["Archivist Galford"],
}
# Not aliased: "Lord Aurius Rivendare" (encounter 456) is the son, another character than classic Baron Rivendare.


def norm(name):
    """Same as L.norm in DungeonLore.lua: lower case, apostrophes/quotes/dots dropped, other punctuation a space,
    a leading "the " dropped. ASCII only, like Lua's %w."""
    s = str(name or "").lower()
    s = re.sub(r"['\".`]", "", s)
    s = re.sub(r"[^a-z0-9]+", " ", s).strip()
    return s[4:] if s.startswith("the ") else s


def fetch(cache):
    cache.mkdir(parents=True, exist_ok=True)
    for t in TABLES:
        path = cache / (t + ".csv")
        if path.exists() and path.stat().st_size > 0 and not path.read_text(encoding="utf-8")[:1] == "{":
            continue  # cached (an error answer such as {"errors": ...} is fetched again)
        print("fetching", URL.format(t))
        tmp = path.with_suffix(".csv.tmp")  # a failed or cut download never replaces the cached file
        try:
            subprocess.run(["curl", "-sSfL", "-o", str(tmp), URL.format(t)], check=True)
            tmp.replace(path)
        finally:
            tmp.unlink(missing_ok=True)
    return {t: list(csv.DictReader(open(cache / (t + ".csv"), encoding="utf-8"))) for t in TABLES}


def our_dungeons():
    text = DATA.read_text(encoding="utf-8")
    block = text[text.index("D.names = {"):]
    block = block[:block.index("\n}")]
    return [(int(a), n) for a, n in re.findall(r'\[(\d+)\]\s*=\s*"([^"]+)"', block)]


def keep_difficulty(spec):
    """$[1,2 text$] shows on the listed difficulties, $[!16 text$] on all others; classic dungeons are normal (1)."""
    ids = [p for p in re.split(r"[,\s]+", spec.lstrip("!")) if p]
    return ("1" not in ids) if spec.startswith("!") else ("1" in ids)


def clean(text):
    s = str(text or "")
    s = re.sub(r"\|c[0-9a-fA-F]{8}", "", s).replace("|r", "")
    s = re.sub(r"\|H[^|]*\|h\[?([^|\]]*)\]?\|h", r"\1", s)
    s = re.sub(r"\|T[^|]*\|t", "", s)
    s = re.sub(r"\$\[([!0-9,\s]+?)\s(.*?)\$\]", lambda m: m.group(2) if keep_difficulty(m.group(1)) else "", s, flags=re.S)
    s = s.replace("$]", "").replace("$bullet;", " ")
    # a blank line ends a sentence ("Course: Advanced Studies\n\nThe recent defeat...")
    s = re.sub(r"(?<=[^\s.!?:;,])[ \t]*\r?\n[ \t]*\r?\n\s*", ". ", s)
    # number tokens: drop them with the words that only make sense with a number
    tok = r"\$\d*[a-zA-Z]+\d*"
    # "dealing $s1% of his normal damage", "healing himself for ${$E1*100}% of damage dealt": the share is unknown
    # "restoring $s1% of his health", "reducing $s2% of their armor": the same, after the verb
    s = re.sub(r"\s(for|dealing|restoring|healing|increasing|reducing)\s+(?:" + tok + r"|\$\{[^}]*\})%\s+of\s", r" \1 part of ", s)
    s = re.sub(r"\$\{[^}]*\}%?", "", s)
    s = re.sub(r"\s(?:with)?in\s+(?:a\s+)?" + tok + r"(?:\s*-\s*" + tok + r")?\s+(?:yards?|yd)(?:\s+radius)?", " nearby", s)
    s = re.sub(r"\s(?:every|for|over|after|lasting)\s+" + tok + r"\s*(?:sec(?:onds?)?|min(?:utes?)?)\.?(?=[\s,.;]|$)", "", s)
    s = re.sub(r"\sup\s+(?:to\s+)?" + tok + r"(?=\s)", " several", s)
    s = re.sub(r"\sby\s+" + tok + r"%?", "", s)
    # an amount or duration after for / over before a joining word ("Shadow damage for $s1 and reducing")
    s = re.sub(r"\s(?:for|over)\s+" + tok + r"%?(?=\s+(?:and|to|of|or)\b)", "", s)
    s = re.sub(r"\$[@<]?\w+>?%?", "", s)
    # words left dangling before punctuation; repeated, because "lasts for $Xd." loses "for" and then "lasts", and
    # "a whirlwind that lasts $Xd." then loses "that"
    orphan = r"\s(?:for|by|of|every|over|to|up to|after|lasts|lasting|that|which|and)\s*(?=[.,;])"
    while re.search(orphan, s):
        s = re.sub(orphan, "", s)
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"(?:(?<=[.!?] )|^)This effect\s*\.\s*", "", s)  # "This effect lasts for $Xd." says nothing more
    s = re.sub(r"\b(?:for|dealing) (?=(?:and|to|of)\b)", "", s)  # an orphan left by a token we could not place
    s = re.sub(r"\s+([.,;:!?)])", r"\1", s)
    s = re.sub(r"\.(?=[,;])", "", s)  # "lasts $Xd., inflicting" in the source
    # "an additional $s2 Nature damage over $d" loses both tokens and reads "and an additional Nature damage"
    s = re.sub(r"\b(?:an )?additional (\w+) damage(?=[.,;]| and\b)", r"more \1 damage over time", s)
    s = re.sub(r"\(\s*\)", "", s)
    return s.strip()


def cut(text, limit):
    if len(text) <= limit:
        return text
    head = text[:limit + 1]
    stop = head.rfind(". ")
    if stop >= limit * .6:
        return head[:stop + 1]
    return head[:head.rfind(" ")].rstrip(",;:") + "..."


def spell_of(section):
    sid = int(section.get("SpellID") or 0)
    if sid:
        return sid
    m = re.search(r"\$(\d{2,7})[a-zA-Z]", section.get("BodyText_lang") or "")
    return int(m.group(1)) if m else None


def abilities(enc_id, by_parent, boss=None):
    """The normal-difficulty abilities of an encounter. When a creature heading is titled like `boss`, only that
    heading is walked (Whitemane's encounter also holds Commander Durand's abilities)."""
    out = []
    top = by_parent.get((enc_id, 0), [])
    mine = {int(s["ID"]) for s in top if boss and norm(s.get("Title_lang")) == norm(boss)
            and by_parent.get((enc_id, int(s["ID"])))}

    def normal(s):  # a mask without the normal-difficulty bit: heroic / mythic only
        mask = int(s.get("DifficultyMask") or -1)
        return mask in (-1, 0) or bool(mask & 1)

    def add(s):
        if not normal(s):
            return
        title = (s.get("Title_lang") or "").strip()
        body = clean(s.get("BodyText_lang"))
        if not title or not body or len(out) >= MAX_ABILITIES:
            return
        out.append({"name": title, "text": cut(body, MAX_TEXT), "spellID": spell_of(s),
                    "icon": int(s.get("IconFileDataID") or 0) or None})

    for s in top:
        kind = s.get("Type")
        if kind == "3":  # overview
            continue
        if kind == "2" or not by_parent.get((enc_id, int(s["ID"]))):
            add(s)
        elif mine and int(s["ID"]) not in mine:
            continue  # another creature's heading
        else:  # a stage or creature heading: its own abilities are the boss's top level
            for child in by_parent.get((enc_id, int(s["ID"])), []):
                if child.get("Type") == "2":
                    add(child)
    return out


def instances_for(name, instances, encounters):
    key = norm(name)
    wanted = {key, "lower " + key, "upper " + key} | set(EXTRA_INSTANCES.get(key, []))
    found = [i for i in instances if int(i["ID"]) not in REWORKS
             and (norm(i["Name_lang"]) in wanted or norm(i["Name_lang"]).startswith(key + " "))]
    classic = {norm(b) for b in CLASSIC_BOSSES.get(key, [])}

    def overlap(inst):
        names = set()
        for e in encounters.get(int(inst["ID"]), []):
            names.add(norm(e["Name_lang"]))
            names.update(norm(a) for a in ALIASES.get(e["Name_lang"], []))
        return len(names & classic)

    # the same name twice (a retail rework next to the classic one): the one whose bosses match ours wins
    best = {}
    for inst in found:
        n = norm(inst["Name_lang"])
        if n not in best or overlap(inst) > overlap(best[n]):
            best[n] = inst
    order = sorted(best.values(), key=lambda i: (norm(i["Name_lang"]) != key, int(i["ID"])))
    return order


def build(tables):
    instances = tables["JournalInstance"]
    encounters = {}
    for e in sorted(tables["JournalEncounter"], key=lambda e: (int(e["OrderIndex"]), int(e["ID"]))):
        encounters.setdefault(int(e["JournalInstanceID"]), []).append(e)
    by_parent = {}
    for s in sorted(tables["JournalEncounterSection"], key=lambda s: (int(s["OrderIndex"]), int(s["ID"]))):
        by_parent.setdefault((int(s["JournalEncounterID"]), int(s["ParentSectionID"])), []).append(s)

    dungeons, bosses, report = {}, {}, []
    # Forever-only dungeons have no journal entry: their intro is written by hand from Wowhead's guides
    # (tools/dungeon_intros.json). Classic dungeons keep Blizzard's own description.
    intros = json.loads((ROOT / "tools" / "dungeon_intros.json").read_text(encoding="utf-8")) if (ROOT / "tools" / "dungeon_intros.json").exists() else {}
    for area, name in our_dungeons():
        if name in intros:
            dungeons[area] = {"name": name, "description": intros[name], "instance": 0}
            continue
        found = instances_for(name, instances, encounters)
        key = norm(name)
        classic = CLASSIC_BOSSES.get(key)
        wanted = {norm(b): b for b in classic} if classic else None
        got = []
        for inst in found:
            desc = clean(inst.get("Description_lang"))
            if desc and area not in dungeons:
                dungeons[area] = {"name": name, "description": desc, "instance": int(inst["ID"])}
            for e in encounters.get(int(inst["ID"]), []):
                desc = clean(e.get("Description_lang"))
                targets = [e["Name_lang"]] + ALIASES.get(e["Name_lang"], [])
                for t in targets:
                    k = norm(t)
                    if wanted is not None and k not in wanted:
                        continue
                    abil = abilities(int(e["ID"]), by_parent, t)
                    if not desc and not abil:
                        continue
                    entry = {"description": desc, "abilities": abil}
                    old = bosses.get(k)
                    if old and len(old["abilities"]) >= len(abil):
                        continue  # a duplicate encounter (difficulty copy): keep the richer one
                    bosses[k] = entry
                    if k not in got:
                        got.append(k)
        report.append((area, name, [i["Name_lang"] for i in found], area in dungeons,
                       len(got), len(classic) if classic else None))
    return dungeons, bosses, report


def lua_str(s):
    s = str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "")
    return '"' + s + '"'


RUNTIME = r'''
-- lower case, apostrophes/quotes/dots dropped, other punctuation a space, a leading "the " dropped
function L.norm(name)
    local s = string.lower(tostring(name or ""))
    s = string.gsub(s, "['\"%.`]", "")
    s = string.gsub(s, "[^%w]+", " ")
    s = string.gsub(s, "^%s+", ""); s = string.gsub(s, "%s+$", "")
    s = string.gsub(s, "^the ", "")
    return s
end

local byName
-- {description=} for the dungeon by area ID, else by its name; nil when the journal has none
function L.dungeon(area, name)
    local d = area and L.dungeons[tonumber(area) or area]
    if d then return d end
    if name == nil then return nil end
    if not byName then
        byName = {}
        for _, row in pairs(L.dungeons) do if row.name then byName[L.norm(row.name)] = row end end
    end
    return byName[L.norm(name)]
end

-- {description=, abilities={{name=, text=, spellID=, icon=}, ...}} or nil
function L.boss(name)
    if type(name) ~= "string" or name == "" then return nil end
    return L.bosses[L.norm(name)]
end
'''


def write(dungeons, bosses, path=OUT):
    out = ["-- Dungeon and boss lore from Blizzard's Encounter Journal. GENERATED by tools/build_dungeon_lore.py: do not edit.",
           "-- Source: wago.tools db2 JournalInstance / JournalEncounter / JournalEncounterSection (retail client tables).",
           "local ADDON, ns = ...",
           "local L = {}",
           "ns.dungeonLore = L",
           "L.dungeons, L.bosses = {}, {}",
           "local d, b = L.dungeons, L.bosses"]
    for area in sorted(dungeons):
        row = dungeons[area]
        out.append("d[%d] = {name=%s, description=%s}" % (area, lua_str(row["name"]), lua_str(row["description"])))
    for k in sorted(bosses):
        row = bosses[k]
        parts = []
        for a in row["abilities"]:
            fields = ["name=" + lua_str(a["name"]), "text=" + lua_str(a["text"])]
            if a["spellID"]:
                fields.append("spellID=%d" % a["spellID"])
            if a["icon"]:
                fields.append("icon=%d" % a["icon"])
            parts.append("{" + ", ".join(fields) + "}")
        out.append("b[%s] = {description=%s, abilities={%s}}" % (lua_str(k), lua_str(row["description"]), ", ".join(parts)))
    path.write_text("\n".join(out) + "\n" + RUNTIME.lstrip("\n"), encoding="utf-8")


def main(argv):
    cache = pathlib.Path(argv[1]) if len(argv) > 1 else pathlib.Path("/tmp/ejdata")
    dungeons, bosses, report = build(fetch(cache))
    write(dungeons, bosses)
    with_text = sum(1 for r in report if r[3])
    ours = sum(r[5] for r in report if r[5])
    got = sum(r[4] for r in report if r[5])
    for area, name, inst, has, n, total in report:
        print("%6d %-28s %-3s bosses %s/%s  %s" % (area, name, "yes" if has else "-", n, total if total else "-", ", ".join(inst)))
    print("dungeons with text: %d/%d; classic bosses with text: %d/%d; boss entries: %d; %s: %d bytes"
          % (with_text, len(report), got, ours, len(bosses), OUT.name, OUT.stat().st_size))


if __name__ == "__main__":
    main(sys.argv)
