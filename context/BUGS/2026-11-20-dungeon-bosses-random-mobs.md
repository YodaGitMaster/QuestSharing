# 2026-11-20 — Bosses tab lists random mobs as bosses

**Status**: solved (in source, mock harness + renders only; not checked in game)
**Severity**: medium
**Tags**: Bosses tab, DungeonBossesUI.lua, Loot.lua, L.bossesOf, officialRows, atlasBosses, questieBosses, AtlasLoot ExtraList, trash, chest, DungeonEncounter, DungeonBossData.lua, build_boss_data.py, "many random mobs are bosses"

## Symptom
- Observed (user, 2026-11-20): "many random mobs are bosses". The Bosses page of a dungeon listed trash, rares, helpers (Sneed's Shredder), chests and event NPCs, in drop-source order, not fight order.
- Expected: only the dungeon's official bosses, in fight order, each with its drops.
- Where: `QuestSharing/Loot.lua` `L.bossesOf(name, done, area)` (`atlasBosses` AtlasLoot path, `questieBosses` QuestieDB fallback), shown by `QuestSharing/DungeonBossesUI.lua`.
- Environment: both with AtlasLoot (trash / ExtraList / chest tables become rows) and without it (every QuestieDB npc with a dungeon drop becomes a row).

## Reproduction
- Open Dungeon quests -> any dungeon (e.g. The Deadmines 1581) -> Bosses tab. Rows like "Chest", trash mobs and the Shredder appear between real bosses.

## Root cause
- `L.bossesOf` built the list from **drop sources**: every AtlasLoot encounter table and every QuestieDB npc that drops an item in that dungeon became a "boss". There was no authoritative boss list at all.
- Trap category: type vs runtime mismatch (a "drop source" was treated as a "boss"; the data never said boss).

## Methodology (reusable)
1. Read-only scout of every path that creates a row (AtlasLoot path, QuestieDB fallback, objects/chests) and which one a player hits with and without AtlasLoot. Both paths listed non-bosses, so a filter on one path would not fix it.
2. Key signal: no source in the code knew which npcs are bosses. A name or rank heuristic (elite, rare) would still let rares and helpers in. An authoritative list was needed.
3. Source chosen: Blizzard `DungeonEncounter` table of the WoW Forever client build 1.60.1.70959 (official encounters, OrderIndex = fight order), matched to npc IDs. Generated offline by `tools/build_boss_data.py` into `QuestSharing/DungeonBossData.lua` (28 areas, 241 bosses). Dead ends: the Forever build has no Encounter Journal tables; Wowhead `/forever/npc=` pages are WAF-blocked (use `/classic/npc=` and the `/forever/search/suggestions-template` JSON only).
4. Fix pattern: "the official list is the only source of rows, drop sources only attach items" (`officialRows` in Loot.lua). Each raw drop row joins the first official boss matching by `npcIDs`/`altNpcIDs`/`lootNpcIDs`, else by plain name (`name`, `npcName`, group `members`); unmatched rows are dropped. Bosses with no drops stay (empty items). Exceptions by hand with one evidence line each: `LOOT_NPCS = {643: [642]}` (Sneed's drops sit on Sneed's Shredder). Areas without an official list and calls without `area` keep the old (legacy) answer.
5. Portrait rules found on the way: EJ art only in classic areas (`area < 16000`) plus a `NO_EJ` set (`16544:Mana Devourer`, `16611:The Butcher`) because Forever-only areas have same-named art of other creatures; `displayID`/`level` are never taken from a row matched only by `lootNpcIDs` (Sneed must not get the Shredder's model).

## Fix
- Files changed: `tools/build_boss_data.py` (new), `QuestSharing/DungeonBossData.lua` (generated), `QuestSharing/Loot.lua` (`officialRows`, `finish` exit helper, `atlasBosses` npcIDs + `table.maxn` walk), `QuestSharing/DungeonBossesUI.lua` (portrait chain, calm layout), `QuestSharing/JournalTheme.lua` (`T.round` ring opt, `T.badge` flat), tests `tests/test_dungeon_boss_data.py`, `tests/test_dungeon_journal_bosses.py` (`test_official_*`), `tests/test_dungeon_journal_bosses_ui.py`.
- Commit / PR: uncommitted (runs r-20261120-194708-fb95 dungeon-bosses-fix, r-20261120-220008-0d88 dungeon-bosses-finish; finished by r-20261121-041134-dd71).
- Workaround? no. Decision D16.

## Verification
- test_dungeon_boss_data 20/20, test_dungeon_journal_bosses 88/88, test_dungeon_journal_bosses_ui 34/34, test_dungeon_quests 138/138, loot 58/58 (2026-11-21). Generator `--offline` output byte-identical to the shipped file. Renders `context/renders/bosses.png`, `bosses_forever.png`.
- Not checked in game.

## If it shows up again
- A dungeon with odd rows: check `ns.dungeonBossData.list(area)` returns a table for that area ID; no list = legacy path (drop sources again).
- A real boss with no drops: its drops sit on another npc; add a `LOOT_NPCS` line with evidence and regenerate (`python3 -I tools/build_boss_data.py --offline`).
- A boss missing from the list: compare with `DungeonEncounter` of the current client build; a new build may add encounters.
