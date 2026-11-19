# 2026-11-19 — "Where to gather" missing for Light Leather and most gathering items

**Status**: solved (mock tests + real QuestieDB data; client GetItemInfoInstant values not checked in game)
**Severity**: medium
**Tags**: GatherSources.lua, isGathering, GetItemInfoInstant, subclass 0, Trade Goods, Light Leather 2318, Light Hide 783, Copper Ore 2770, Linen Cloth 2589, Elemental Earth 7067, objectDrops, Battered Chest, itemSources, SkinningData

## Symptom
- Observed: hovering Light Leather (and hides, cloth, ore, meat) shows no "Where to gather" lines; herbs (Peacebloom) do.
- Expected: top-3 zones for every gathered item.
- Where: `QuestSharing/GatherSources.lua` `G.isGathering`, `collect()` object filter.
- Environment: Classic/Forever data (QuestieDB `foreverItemDB`), interface 16001.

## Reproduction
- Hover Light Leather in bags with `itemSources` on.

## Root cause
- The gate required item class 7 with subclass 5-10 (the modern Cloth/Leather/Metal/Meat/Herb/Elemental subclasses). Classic item data files all of those under 7/0 "Trade Goods" except herbs (7/9); elementals are 5/0 "Reagent". So `isGathering` returned false before the (correct) bundled skinning table was ever read. The object-node filter also keyed on subclass 7/9/10, so ore lost its vein.
- Trap category: type vs runtime mismatch (code written against modern enum values; tests mocked the same assumed values, so they passed).

## Methodology (reusable)
1. 2026-11-18 follow-up had already fixed the DATA side (SkinningData.lua has 2318). The data was present -> the gate before it had to be the cause.
2. Read the real QuestieDB record (`/tmp/qdbrepo/QuestieDB-master/data/Forever/foreverItemDB.lua`, keys 12=class, 13=subClass): 2318 = 7/0. Counted all 45 skinning items: 23 are 7/0, 18 are 15/0, none 7/6. Herbs 7/9 -> explains "some work".
3. The tests mocked `GetItemInfoInstant` with modern subclasses (7/6), so they could not catch it. Lesson: mock enums from the real data files, not from API docs of another client.
4. Fix pattern: gate on the data (skinning table entry, or 7/0, 7/5-10, 5/0) and filter object sources by NAME (chest/strongbox/crate/box/locker/...) instead of by subclass. Crafted 7/0 goods just find no source and show nothing.

## Fix
- Files changed: `QuestSharing/GatherSources.lua`, `tests/test_gather_sources.py` (4 new tests, Classic 7/0 + 5/0 fixtures; the leather fixture now points at a chest as in the real data), `CHANGELOG.md`.
- Commit / PR: uncommitted.
- Workaround? no.

## Verification
- New tests fail on the old code (8 FAIL), pass on the new: gather 28/28; full suite 0 FAIL.
- Not verified: that the live client's `GetItemInfoInstant(2318)` also returns 7/0 (Questie data is from the same 1.12 DB, so very likely). `/qs gather 2318` prints the class/subclass if it still fails.

## If it shows up again
- Run `/qs gather <id>`: it prints class/subclass, Questie drops and skinning count.
- A container name the word list misses (e.g. "Footlocker" variants, "Strongbox" spelled otherwise) shows up as a gathering spot -> add the word in `CONTAINER_WORDS`.
- Hover cost: 7/0 and 5/0 items now start a cached DataWork job each; watch for lag on first hover of very common goods.
