"""Regenerate QuestSharing/DungeonBossData.lua: the official boss list of every dungeon, in fight order.

Sources (research inputs, read-only, never shipped):
  --bosses    R1 boss list per area (Blizzard DungeonEncounter of the WoW Forever client 1.60.1.70959, matched to npc IDs)
  --coverage  R2 per-boss Encounter Journal art and display IDs ("<area>:<name>" -> record)
  --present   R2 list of "<area>:<name>" whose EJ art file is present in the Forever client
  --displays  f_CreatureDisplayInfo.csv of the Forever client (validates display IDs)
  --cache     Wowhead /classic/ NPC pages (raw HTML, <npcID>.html), fetched with curl once, then reused
  --suggest   Wowhead /forever/ search suggestions (raw JSON, <quoted name>.json), fetched with curl once, then reused

Missing npc IDs: a boss whose R1 row has no npcIDs is looked up in the Wowhead Forever search suggestions
(https://www.wowhead.com/forever/search/suggestions-template?q=<name>; results with "type": 1 are npcs). Only an npc
whose name equals the boss name exactly is taken; in Forever-only areas (area >= 16000) ids >= 200000 win, elsewhere
the classic ids win. The suggestions endpoint is not a database page, so it is not WAF-blocked like /forever/npc=.
Cross-check: for every boss of a Forever-only area the QuestieDB npc ID (R1 npcIDs/altNpcIDs) is compared with the
suggestions id and mismatches are printed. IDs are never changed by the cross-check.

Only measurements and IDs are written; no media. The output is deterministic: running the script again (also with
--offline, which reads the Wowhead caches only and never touches the network) gives a byte-identical file.

Usage: python3 -I tools/build_boss_data.py [--offline] [--out PATH] [--bosses ...] [--coverage ...] [--present ...]
                                           [--displays ...] [--cache DIR] [--suggest DIR]
"""
import argparse
import csv
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "QuestSharing" / "DungeonBossData.lua"
DATA = ROOT / "QuestSharing" / "DungeonQuestData.lua"
BUILD = "1.60.1.70959"
DATA_DATE = "2026-11-20"  # date of the research inputs; fixed so re-runs stay byte-identical
UA = "Mozilla/5.0"
WOWHEAD = "https://www.wowhead.com/classic/npc={}"  # never /forever/ (WAF-blocked)
FOREVER_NPC = 200000  # npc IDs from here on exist only in Forever: no Wowhead classic page
SUGGEST = "https://www.wowhead.com/forever/search/suggestions-template?q={}"  # search JSON, not a database page
NPC_TYPE = 1  # suggestions "type" of an npc result

# npcs whose drops belong to an official boss (one evidence line each).
LOOT_NPCS = {
    643: [642],  # Sneed rides Sneed's Shredder (642); AtlasLoot and QuestieDB list the encounter's drops on the Shredder
}

# Known false EJ matches: the client art of that name shows another creature. The classic-area rule already excludes
# both; the set keeps them out even if the rule changes.
NO_EJ = {"16544:Mana Devourer", "16611:The Butcher"}
CLASSIC_AREA = 16000  # areas below this are the original dungeons; above are Forever-only
# Accepted retail-version art (same boss, later look): 2017:Baron Rivendare (Lord Aurius Rivendare), 1176:Gahz'rilla,
# 2017:Malor the Zealous (Commander Malor), 2017:Archivist Galford (Instructor Galford), 2017:Cannon Master Willey
# (Willey Hopebreaker).

KEYS = ("name", "order", "encounterID", "npcID", "npcIDs", "altNpcIDs", "npcName", "lootNpcIDs", "group", "members",
        "optional", "ejFile", "displayID")


def lua_str(s):
    """Lua 5.1 string.format('%q', s)."""
    out = ['"']
    for ch in s:
        if ch in '"\\':
            out.append("\\" + ch)
        elif ch == "\n":
            out.append("\\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\0":
            out.append("\\000")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua_val(v):
    if v is True:
        return "true"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        return "{" + ",".join(lua_val(x) for x in v) + "}"
    raise TypeError(repr(v))


def area_names():
    text = DATA.read_text(encoding="utf-8")
    block = text[text.index("D.names = {"):]
    block = block[:block.index("\n}")]
    return {int(a): n for a, n in re.findall(r'\[(\d+)\]\s*=\s*"((?:[^"\\]|\\.)*)"', block)}


def norm(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def ej_stem(path):
    """'interface/encounterjournal/ui-ej-boss-the ravenian.blp' -> 'theravenian'."""
    stem = (path or "").replace("\\", "/").rsplit("/", 1)[-1].lower()
    stem = stem[:-4] if stem.endswith(".blp") else stem
    return norm(stem[len("ui-ej-boss-"):] if stem.startswith("ui-ej-boss-") else stem)


def ej_file(creature, by_name, boss):
    """creatures[0] art wins, unless its file stem names neither the boss nor that creature and a by-name file exists
    (Gahz'rilla's creature art is ui-ej-boss-ghazan, Magistrate Barthilas's is The Ravenian's)."""
    fdid, other = creature.get("fdid"), by_name.get("fdid")
    if fdid and other and creature.get("file") and ej_stem(creature["file"]) not in {norm(boss), norm(creature.get("name"))}:
        return other
    return fdid or other


def load_displays(path):
    try:
        with open(path, newline="", encoding="utf-8") as f:
            return {int(r["ID"]) for r in csv.DictReader(f)}
    except OSError:
        return None


def parse_display(html):
    m = re.search(r'data-mv-display-id="(\d+)"', html) or re.search(r"displayId = (\d+)", html)
    return int(m.group(1)) if m else None


def suggest_npc(answer, name, forever):
    """npc id from a suggestions answer whose name equals `name` exactly (type 1 results only), else None.
    Several exact hits: Forever-only areas prefer ids >= FOREVER_NPC, other areas prefer classic ids; then answer order."""
    hits = [r["id"] for r in (answer or {}).get("results") or []
            if r.get("type") == NPC_TYPE and r.get("name") == name and isinstance(r.get("id"), int)]
    if not hits:
        return None
    return sorted(hits, key=lambda i: (i >= FOREVER_NPC) != forever)[0]  # stable: answer order breaks ties


def is_json(text):
    """True when `text` parses as JSON (a suggestions answer, not a WAF challenge page)."""
    try:
        json.loads(text)
        return True
    except ValueError:
        return False


def suggest_file(name):
    """Cache file name of a suggestions query: the URL-quoted name (no path separators)."""
    return urllib.parse.quote(name, safe="") + ".json"


class Wowhead:
    def __init__(self, cache, offline, suggest=None):
        self.cache = pathlib.Path(cache)
        self.suggest_cache = pathlib.Path(suggest) if suggest else None
        self.offline = offline
        self.last = 0.0
        self.fetched = self.failed = 0

    def fetch(self, url, path, ok_codes, what, valid=None):
        """curl `url` (>= 1 s between requests, 3 tries, backoff 2 and 4 s); cache the raw body in `path` when the
        HTTP code is in `ok_codes` and `valid(text)` (if given) accepts it. Returns the body text or None."""
        path.parent.mkdir(parents=True, exist_ok=True)
        for attempt in range(3):
            wait = 1.0 - (time.monotonic() - self.last)
            if wait > 0:
                time.sleep(wait)
            r = subprocess.run(["curl", "-sSL", "-A", UA, "--max-time", "30", "-w", "\n%{http_code}", url],
                               capture_output=True)
            self.last = time.monotonic()
            body, _, code = r.stdout.rpartition(b"\n")
            code = int(code or 0) if code.strip().isdigit() else 0
            if r.returncode == 0 and code in ok_codes:
                text = body.decode("utf-8", "replace")
                if valid is None or valid(text):  # validate before caching: a bad body never reaches the cache
                    path.write_text(text, encoding="utf-8")
                    self.fetched += 1
                    return text
                print(f"  wowhead {what}: unexpected body (http {code}), not cached", file=sys.stderr)
            if attempt < 2:
                time.sleep(2 ** (attempt + 1))  # backoff 2, 4 s; no sleep after the last failed try
        self.failed += 1
        print(f"  wowhead {what}: no answer (curl {r.returncode}, http {code})", file=sys.stderr)
        return None

    def page(self, npc):
        path = self.cache / f"{npc}.html"
        if path.exists():
            return path.read_text(encoding="utf-8", errors="replace")
        if self.offline:
            return None
        # definitive answers are cached (a 404 page has no model)
        return self.fetch(WOWHEAD.format(npc), path, (200, 404), f"npc={npc}")

    def display(self, npc):
        html = self.page(npc)
        return parse_display(html) if html else None

    def suggestions(self, name):
        """Raw suggestions answer (dict) for `name`, from --suggest or fetched once; None when unavailable."""
        if self.suggest_cache is None:
            return None
        path = self.suggest_cache / suggest_file(name)
        text = None
        if path.exists():
            text = path.read_text(encoding="utf-8", errors="replace")
        elif not self.offline:
            text = self.fetch(SUGGEST.format(urllib.parse.quote(name)), path, (200,), f"suggestions q={name}",
                              valid=is_json)
        try:
            return json.loads(text) if text else None
        except ValueError:  # e.g. a WAF challenge page with HTTP 200 cached by an older run
            if self.offline:  # --offline only reads the cache: warn, never delete
                print(f"  wowhead suggestions q={name}: cached entry is not JSON (kept, --offline)", file=sys.stderr)
            else:
                print(f"  wowhead suggestions q={name}: cached entry is not JSON, dropped", file=sys.stderr)
                path.unlink(missing_ok=True)
            return None


def fill_npc(web, src, ids, key, forever, report):
    """npc IDs of one boss. Without QuestieDB ids: the exact-name npc of the Wowhead Forever suggestions (or []).
    With ids in a Forever-only area: cross-check them against the suggestions and only report a mismatch."""
    if not ids:
        found = suggest_npc(web.suggestions(src["name"]), src["name"], forever)
        if found is None:
            report["missing"].append(key)
            return []
        report["filled"].append(f"{key} -> {found}")
        return [found]
    if forever:
        lookup = src.get("npcName") or src["name"]
        found = suggest_npc(web.suggestions(lookup), lookup, forever)
        known_ids = set(ids) | {int(i) for i in src.get("altNpcIDs") or []}
        if found is None:
            report["unchecked"].append(f"{key} (questie {ids[0]}, no exact suggestion for {lookup!r})")
        elif found not in known_ids:
            report["mismatch"].append(f"{key} questie {ids} vs suggestions {found}")
    return ids


def build(args):
    bosses = json.loads(pathlib.Path(args.bosses).read_text(encoding="utf-8"))
    coverage = json.loads(pathlib.Path(args.coverage).read_text(encoding="utf-8"))
    present = set(json.loads(pathlib.Path(args.present).read_text(encoding="utf-8"))["present"])
    known = load_displays(args.displays)
    names = area_names()
    web = Wowhead(args.cache, args.offline, args.suggest)
    stats = dict(bosses=0, npcID=0, ejFile=0, displayID=0, rejected=0, fromCoverage=0, fromWowhead=0, fromSuggest=0)
    rejected = []
    report = {"filled": [], "missing": [], "mismatch": [], "unchecked": []}

    out = {}
    for area in sorted(bosses, key=int):
        a = int(area)
        forever = a >= CLASSIC_AREA
        rows = []
        for src in sorted(bosses[area], key=lambda b: b["order"]):
            b = {"name": src["name"], "order": src["order"], "encounterID": src["encounterID"]}
            ids = [int(i) for i in src.get("npcIDs") or []]
            key = f"{area}:{src['name']}"
            ids = fill_npc(web, src, ids, key, forever, report)
            if ids and not src.get("npcIDs"):
                stats["fromSuggest"] += 1
            if ids:
                b["npcID"], b["npcIDs"] = ids[0], ids
            if src.get("altNpcIDs"):
                b["altNpcIDs"] = [int(i) for i in src["altNpcIDs"]]
            if src.get("npcName") and src["npcName"] != src["name"]:
                b["npcName"] = src["npcName"]
            loot = [n for i in ids for n in LOOT_NPCS.get(i, [])]
            if loot:
                b["lootNpcIDs"] = loot
            if src.get("group"):
                b["group"] = True
            if src.get("members"):
                b["members"] = list(src["members"])
            if "flags" in src and not (int(src["flags"]) & 1024):
                b["optional"] = True

            rec = coverage.get(key, {})
            creatures = rec.get("creatures") or []
            if key in present and a < CLASSIC_AREA and key not in NO_EJ:
                fdid = ej_file(creatures[0] if creatures else {}, rec.get("ejFileByName") or {}, src["name"])
                if fdid:
                    b["ejFile"] = int(fdid)

            wanted = {norm(src["name"]), norm(src.get("npcName"))} | {norm(m) for m in src.get("members") or []}
            wanted.discard("")
            disp, origin = None, None
            for c in creatures:
                if c.get("displayInForever") is True and c.get("displayID") and norm(c.get("name")) in wanted:
                    disp, origin = int(c["displayID"]), "fromCoverage"
                    break
            if disp is None and ids and ids[0] < FOREVER_NPC:
                disp = web.display(ids[0])
                origin = "fromWowhead"
            if disp is not None:
                if known is None or disp in known:
                    b["displayID"] = disp
                    stats[origin] += 1
                else:
                    stats["rejected"] += 1
                    rejected.append(f"{key} {disp}")

            stats["bosses"] += 1
            for k in ("npcID", "ejFile", "displayID"):
                stats[k] += k in b
            rows.append(b)
        out[a] = rows

    lines = [
        f"-- Official boss list per dungeon, in fight order (Blizzard DungeonEncounter, WoW Forever client {BUILD}).",
        "-- GENERATED by tools/build_boss_data.py, do not edit: python3 -I tools/build_boss_data.py [--offline]",
        f"-- Data: {DATA_DATE}. ejFile = FileDataID of the client's Encounter Journal art (classic dungeons only);",
        "-- displayID = creature display, checked against the Forever CreatureDisplayInfo table.",
        "local ADDON, ns = ...",
        "local B = {}",
        "ns.dungeonBossData = B",
        "-- [area] = { {name=, order=, encounterID=, npcID=, npcIDs=, ...}, ... } in fight order",
        "B.bosses = {",
    ]
    for a, rows in out.items():
        lines.append(f"    [{a}] = {{ -- {names.get(a, '?')}")
        for b in rows:
            lines.append("        { " + ", ".join(f"{k} = {lua_val(b[k])}" for k in KEYS if k in b) + " },")
        lines.append("    },")
    lines += ["}", "function B.list(area) return B.bosses[tonumber(area) or area] end", ""]
    web.report = report
    return "\n".join(lines), stats, rejected, out, web


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--bosses", default="/tmp/bossdata/bosses.json")
    p.add_argument("--coverage", default="/tmp/bossdata/portraits/coverage.json")
    p.add_argument("--present", default="/tmp/bossdata/portraits/ej_presence.json")
    p.add_argument("--displays", default="/tmp/ejdata/f_CreatureDisplayInfo.csv")
    p.add_argument("--cache", default="/tmp/bossdata/wowhead/")
    p.add_argument("--suggest", default="/tmp/bossdata/suggest/",
                   help="Wowhead Forever search suggestions cache (raw JSON per query)")
    p.add_argument("--offline", action="store_true", help="Wowhead cache only, no network")
    p.add_argument("--out", default=str(OUT))
    args = p.parse_args(argv)
    text, stats, rejected, out, web = build(args)
    pathlib.Path(args.out).write_text(text, encoding="utf-8")
    print(f"wrote {args.out} ({len(text.encode('utf-8'))} bytes)")
    print("bosses {bosses}, with npcID {npcID}, with ejFile {ejFile}, with displayID {displayID} "
          "(coverage {fromCoverage}, wowhead {fromWowhead}), rejected displayIDs {rejected}".format(**stats))
    if not args.offline:
        print(f"wowhead pages fetched {web.fetched}, failed {web.failed}")
    rep = web.report
    print(f"npc ids from suggestions {stats['fromSuggest']}, still without npc {len(rep['missing'])}, "
          f"forever cross-check mismatches {len(rep['mismatch'])}, unchecked {len(rep['unchecked'])}")
    for label in ("filled", "missing", "mismatch", "unchecked"):
        for line in rep[label]:
            print(f"  {label} {line}")
    for r in rejected:
        print("  rejected", r)
    for a, rows in out.items():
        print(f"  {a:>5} bosses {len(rows):>2}  npcID {sum('npcID' in b for b in rows):>2}  "
              f"ejFile {sum('ejFile' in b for b in rows):>2}  displayID {sum('displayID' in b for b in rows):>2}")


if __name__ == "__main__":
    main()
