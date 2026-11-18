# 2026-11-17 — Map search hides missing database

**Status**: solved in source (2026-11-17, run r-20261117-215940-e171: the "no suggestions while typing" regression is fixed; uncommitted/unreleased); native WoW validation pending. The user's live empty-result cause is still unverified (no `/qs questie` report yet).
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

---
## Addendum 2026-11-17 — audit
- Source: BPMN run r-20261117-212533-cf04 (check_g5 + refute_g5). Verdict **open**; the refuter agreed. VendorMap.lua last changed in cb45f17 (v0.4.20), so v0.4.21 and HEAD f9bb992 behave the same.
- Still fixed: `Q.canEnumerate` (`Questie.lua:374-378`), the missing/outdated QuestieDB messages (`VendorMap.lua:626-635`) and the reset on provider loss (`:186-194`). test_vendor_map.py passes 88/88 on modern and classic.
- Still broken, unchanged mechanism: OnTextChanged (`VendorMap.lua:551-562`) cancels vendor-search, sets `resolved=nil` through clearLocations (`:181`) and hides the box (`:559`). After the 0.18 s debounce, V.draw calls startSearch (`:647-650`). startSearch (`:317-338`) indexes every NPC with one yield each (`:138-150`), every item for seller and item queries (`:152-177`) and the spawns of every candidate (`:330-334`). Only then does it set `resolved` and call refreshSuggestions, which returns early while `resolved==nil` (`:456`). `Work.start('vendor-search')` passes no budget (`:321`), so it stays on the 2 ms / 80-step slice (`DataWork.lua:5`, `:44-67`).
- Measured delay from the last keystroke to the first suggestion, at Classic size, typing 10 keys/s, with a 2 ms clock charging 4 µs per scalar read and 10 µs per table read:
  - Checker `/tmp/bugaudit-g5/repro_suggest_delay.py` (10,122 NPCs, 14,899 items): gene 2.9 s, linen 7.7 s, vendor 7.9 s, warm gener 0.8 s. With no clock (80 steps per pump): 20.3, 50.3, 54.0 and 7.7 s.
  - Refuter `/tmp/bugaudit-refute-g5/suggest_latency.py` (10,000 NPCs, 15,000 items): gene 2.5 s, linen 5.7 s, warm 0.7 s. With no clock: 16.0, 36.6 and 11.0 s.
  - In both runs the panel shows 0 rows and "Searching vendor data in small batches…" one second after typing, on both styles.
- Test gap: `test_typing_during_batched_loading_refreshes_pins_and_suggestions` passes but allows 20 s for 600 NPCs, so it cannot catch this. The budgeted Classic-size latency test is still missing.
- New aggravation from unreleased f1b34e9: the planner's background `quest-improve` job (`QuestPlanner.lua:922-935`, IMPROVE_STEPS 250000) shares the DataWork queue. DataWork gives each job one resume per turn whatever that resume costs (`DataWork.lua:62-86`), and improve resumes reach 2.4-3.9 ms. In a real-clock probe the vendor search ran at 5-9% of its solo speed while the guide refined (`/tmp/bugaudit-refute-g6/probes/contention.py`).
- Result / new status: open. The proposed fix from the previous addendum is not implemented and still awaits user approval.

---
## Addendum 2026-11-17 — typing latency fixed in source (fix-all run)
- What happened: BPMN run r-20261117-215940-e171 carried out stream B (B1–B4) of `context/fix-plan-2026-11-17.md`. The user approved the plan. A builder made the change, and the reviewer approved it in round 1. Only `QuestSharing/VendorMap.lua` and `tests/test_vendor_map.py` changed.
- Why the previous state failed: UI feedback waited for a whole-catalogue background job, and every keystroke threw that job away.
- New approach + methodology:
  1. Split long-lived work from per-query work. A persistent `vendor-index` job (`startIndex`) indexes roles, and items when a query needs them.
     - It starts on the first typed character, from OnTextChanged. Nothing is read on login or a blank map; the no-preload guarantee holds.
     - Keystrokes never cancel it. Only `resetIndex()` does (disable or provider loss).
     - Its valid() needs `indexToken`, the map shown and a non-empty query, and `V.draw` pauses it while the map is hidden.
     - Budget is `FOREGROUND_MS=8` once the user typed. DataWork already pauses all jobs in combat.
  2. `vendor-search` now only matches and hydrates. Decoded spawns stay in `cached` across keystrokes, bounded at `SPAWN_CACHE=2000` NPCs plus the current query's matches. The cache clears on a map change, on Clear and through `resetIndex`.
  3. Suggestions are incremental. `hydrate()` refreshes suggestions at the first local match and each time the local count doubles. `keepMatching` keeps earlier suggestions that still match while the user types. The status shows `Indexing N / M NPCs…`, `… items…` and `Finding locations: N / M matches…`.
  4. Budgeted Classic-size tests use a mock clock, which closes the old harness gap (no `debugprofilestop`, 600 NPCs). They are `test_classic_size_suggestions_arrive_quickly_while_typing` and `test_classic_size_item_query_indexes_items_once_and_suggests_local_items`.
- Result per CHANGELOG `## Unreleased`: the first suggestion arrives about 0.3 s after typing stops (was about 3 s); item queries take about 1.4 s (was about 8 s). This is harness timing, not native.
- Related: stream A4 (optimizer yields every 32 simulated actions; quest-improve no longer restarts on small moves) removes most of the quest-improve contention noted in the audit addendum.
- If it shows up again: check that OnTextChanged does not call `Work.cancel("vendor-index")`. Check that `clearResults()` (per query) is used, not `clearLocations()`/`dropSpawns(nil)`. Check that the index job gets the 8 ms budget (`typed=true`).
- Result / new status: solved in source (uncommitted, unreleased). Native check pending: type in the map search in Stormwind. The user's separate live empty-result report still needs `/qs questie` output.
