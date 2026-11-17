# 2026-11-17 — Map search hides missing database

**Status**: solved (dependency feedback and late-provider mechanism; user's live cause unverified)
**Severity**: medium
**Tags**: VendorMap.lua Questie.lua QuestieDB missing database empty search no known seller late provider canEnumerate

## Symptom
- Observed: user says map search shows nothing and does not explain whether Questie is required.
- Reproduced: with all Questie/provider globals nil, blank map says to type vendor; typing vendor says `No known seller for "vendor".` and blames vendor links.
- Expected: explain database requirement and diagnostic steps; reserve no-match messages for a usable provider.
- Where: QuestSharing/VendorMap.lua, QuestSharing/Questie.lua; misleading standalone claim in README.md.
- Environment: real Lua modules under Lua 5.1 harness, modern/classic API styles; no live WoW client.

## Reproduction
1. Enable vendorSearch and open the map with QuestDB/NpcDB/ItemDB/LibQuestieDB/QuestieLoader/Questie globals absent.
2. Inspect blank search help, type vendor and inspect status and pins.
3. Restore provider entity tables and ZoneDB mapping support without changing query; original code retains its empty index.

## Root cause
- Missing enumeration returned nil, coerced to an empty catalogue; indexing then marked ready. No preflight separated absent/non-enumerable data from a legitimate zero result. The empty cache also blocked late-provider recovery.
- Trap category: falsy/null trap; scope/lifecycle; stale cached value.

## Methodology (reusable)
1. Read prior vendor-map and eager-loading reports; distinguish dependency/readiness failure from matching/projection defects.
2. Remove providers entirely in the real harness and compare blank-query versus submitted-query feedback; do not assume the user's live cause from a matching symptom.
3. Test standalone NPC/item providers separately from Q.available(), which checks quest records. Preserve older item-only and newer NPC-only coverage; no full Questie requirement.
4. Inspect enumeration method presence without calling it so dependency feedback does not undo the no-login/no-blank-scan performance fix.
5. Check absent, non-enumerable, Lib-only, late and lost providers. Restore ZoneDB support alongside entity tables in a late-provider test, otherwise pin failure is a fixture mapping omission.
6. Share the existing reset across disable/provider loss to remove stale indexes, pins and suggestions; retain text so the same query can recover.

## Fix
- Files changed: QuestSharing/Questie.lua, QuestSharing/VendorMap.lua, QuestSharing/Settings.lua, tests/test_vendor_map.py, README.md, CHANGELOG.md, context notes.
- Added Q.canEnumerate(kind); missing/outdated feedback with QuestieDB-only support and /qs questie, reset on provider loss and retry when available.
- Commit / PR: local/unpublished; no release/version bump requested.
- Workaround? No; dependency remains intentional (context/decisions.md entry 2026-11-17).

## Verification
- Baseline new scenarios: 78/88 map checks, ten failures across modern/classic; after fix 88/88 pass.
- Related: data budget17 + settings55 + optional42 + quest-map15 =129 checks pass; total217.
- Questie.lua, VendorMap.lua and Settings.lua compile under actual Lua 5.1; git diff whitespace check passes.
- Native rendering and exact live cause remain unverified; user asked for query, displayed map, installed version and Questie availability, no reply yet.

## If it shows up again
- Run /qs questie and check exact installed version/map/query; distinguish missing database, partial enumeration, no seller links and zero local coordinates.
- Check the Quest Sharing panel in the map's bottom-right corner; it is separate from other map search widgets.
- If GetAllIds exists but throws or returns malformed data, method presence alone does not prove readable records; inspect provider errors/readiness before modifying matching.

---
## Addendum 2026-11-17 — Standalone DB still empty in Wetlands
- What happened: after dependency clarification, user says QuestieDB alone is installed/enabled but search does not work; latest Quest Sharing and outdoor Wetlands confirmed, query `vendor`. `/qs questie` report not supplied yet.
- Why previous work did not establish success: earlier patch fixes missing-data feedback only and remains unpublished; fixture tests do not identify this installed/live failure. The explanation that DB alone suffices was too definite about actual operation without checking loaded/readable records.
- New approach + methodology: verify primary provider API/TOC for standalone support; run real raw NPC/item data through actual map module with full Questie globals removed and Wetlands mapping. Differentiate known baseline coverage from installed Forever corrections and native frames.
- Evidence: real raw Classic baseline returns20 seller locations/6 suggestions on modern/classic; zero logged errors. Includes non-town seller2682 at26.4,25.8. QuestieDB API/TOC has standalone entity/ZoneDB support; no requirement for full Questie found.
- Result / new status: dependency-feedback mechanism stays solved locally; user's live empty result remains open, awaiting `/qs questie` output and text below Quest Sharing's bottom-right map search. No speculative runtime change or new release.

---
## Addendum 2026-11-17 — v0.4.20: no suggestions while typing (regression vs v0.4.17)
- What happened: user on v0.4.20 says map search still not working; typing used to give suggestions, now nothing. Also: "before was showing icon if questie (not db) is not loaded, not what we want" (meaning unclear; asked).
- Verified against real QuestieDB source (`/tmp/qs-questiedb-src/repo`, v1.1.2, contract 4): `_G.NpcDB/ItemDB` = `LibQuestieDB.Npc/Item`, `GetAllIds`, `RequireContract(4)` all present standalone, so the `Q.canEnumerate` gate passes and no Questie is needed. Not the cause when QuestieDB loads.
- Mechanism found (reproduced in harness, not in client): v0.4.17 computed suggestions synchronously in OnTextChanged from a prebuilt index. v0.4.19+ only calls `refreshSuggestions` at the end of the `vendor-search` job (`startSearch`). `refreshSuggestions` returns early while `resolved == nil`, and every keystroke clears `resolved` and hides the box. The first job indexes all NPCs one per yield (plus all items for seller/item queries), then reads spawns for every worldwide match, at a 2 ms / 100 ms DataWork budget.
- Evidence: `/tmp/qs-repro/repro_suggest.py`, `repro_vendor.py` with Classic Era counts (10,122 NPCs / 14,899 items per QuestieDB read-performance.md) and `debugprofilestop` advanced 4 µs/scalar and 10 µs/table read. First suggestion after typing stops: `gen` 2.5 s, `linen` 9 s, cold `vendor` 12 s (23 s at 2× cost). Warm `gene` 0.5 s. Status shows only "Searching vendor data in small batches…" meanwhile. Test suites never see this because the harness has no `debugprofilestop` (80 steps/pump, no time budget) and uses ≤600 NPCs.
- Trap category: scope/lifecycle (UI feedback depends on whole-catalogue background job) + stale/cleared cache per keystroke.
- Result / new status: open. Delay mechanism reproduced; user's live "never" vs "slow" not confirmed. No code changed; fix plan proposed (warm index on visible map, suggestions from in-memory index, keep last suggestions + progress text, larger slice only while map open/out of combat, budgeted Classic-size test).
