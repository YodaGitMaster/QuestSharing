# 2026-11-17 — Optional database eager loading

**Status**: solved (reproduced database-work mechanism; live FPS pending)
**Severity**: high
**Tags**: lag login normal-play performance VendorMap.lua QuestPlanner.lua Questie.lua DataWork.lua Core.lua GetAllIds spawns v0.4.17

## Symptom
- Observed: user reports game “super slow and laggy” at login/normal play on v0.4.17; asks to check current unpublished preview too.
- Reproduced: enabled vendor search eagerly enumerates item/NPC lists while map closed; saved planner switch triggers whole quest discovery on login and same-zone events repeat it. Instrumented 1,000-quest baseline: 1,000 starter reads / 2,000 NPC reads during login; initial lifecycle/budget suite 0/7.
- Expected: optional catalogues load only on explicit visible demand; avoid repeated world discovery and unrelated spawn decoding.
- Environment: real addon Lua modules in Lua 5.1 harness, modern/classic API styles; no native WoW process/FPS available. Provider caches are independently owned.

## Reproduction
1. Save vendorSearch/questPlanner=true and log in; count GetAllIds and DB.Get calls.
2. Enable map search while map is hidden, then show blank map; count catalogue enumeration.
3. Open guide, fire repeated same-zone/quest events, or close it and fire events.
4. Search one trainer among 1,000 NPCs; count item enumeration and NPC spawn reads.

## Root cause
- Optional feature enablement was treated as demand for whole-catalogue discovery. Vendor indexing eagerly decoded all locations; planner zone events restarted discovery despite unchanged location. Separate fixed-record timer batches did not share a time budget.
- Trap category: scope/lifecycle; stale/absent cache; resource retention. New cancellation boundaries also required guarding coroutine replacement identity and map changes during yielded rendering.

## Methodology (reusable)
1. Instrument provider boundary calls before changing code; distinguish catalogue enumeration, scalar fields and spawn decoding from native frame time.
2. Reproduce cold saved-toggle startup and hidden/blank states, not only successful UI searches. Existing caches can hide first-read cost.
3. Trace event entry points into database work. Gate before GetAllIds, then separate reusable scalar metadata from query-local decoded locations.
4. Share cooperative scheduling across guide/map jobs. Yield outside provider pcall boundaries; use profiler budget plus a resume cap, pause combat by event rather than polling.
5. Preserve complete local-ID discovery independent of eligibility; reuse IDs with fresh eligibility/progress. Do not use zoneOrSort as an exclusive geographic index.
6. Exercise cancellation, hidden/combat resume, stale suggestions and map changes during rendering. Completion must compare job identity before removing an owner replaced from inside its own coroutine.
7. Re-run functional role aliases, explicit items, local map pins, prerequisites and guide navigation before packaging.

## Fix
- Files changed: QuestSharing/DataWork.lua, QuestSharing/QuestSharing.toc, QuestSharing/Core.lua, QuestSharing/QuestPlanner.lua, QuestSharing/Questie.lua, QuestSharing/VendorMap.lua; tests/docs.
- No catalogue preload on login/blank/closed map. Guide events require a visible session. Master disable cancels/closes guide.
- Shared soft 2ms / 100ms slices; cap 2,000 resumes with profiler or 80 without. Native/provider calls may individually exceed budget.
- Debounced map search, reusable roles/title words, item-link fallback only when needed, names only for buyable items, locations only for current candidates; clear/change releases locations, disable releases indexes.
- Guide keeps numeric quest IDs for last two discovered zones and a per-scan 256-source cache; explicit Refresh rediscovers.
- Reward/dungeon browsers already require explicit open; no changes to independent Questie loading/cache policy.
- Commit / PR: local unpublished preview; no push requested.
- Workaround? No.

## Verification
- tests/test_data_budget.py: 17/17, including cold startup, same-zone reuse, actual concurrent getters, combat/hidden pause, stale Tab cancellation, item fallback, master lifecycle, worker replacement and map change during pin batches.
- Instrumented 1,000-NPC trainer search: 1 NPC enumeration, 0 item enumeration, 1 matching spawn read; repeated idle draw does not read again; Clear releases our spawn references.
- Instrumented 1,001-quest discovery with repeated remote giver: 1 quest enumeration, 3 distinct NPC spawn reads.
- Full 40 suites / 1,461 checks pass; changed-module Lua syntax and diff whitespace checks pass. Core syntax executed in actual Lua 5.1 harness (host luac uses different Lua version).
- Native FPS, installed provider costs and independent Questie startup remain unverified; do not equate synthetic read reductions with measured FPS.

## If it shows up again
- Confirm installed build: user was still on v0.4.17, while fixes are in unpublished preview.
- Count database reads with tools closed and at cold login; distinguish Quest Sharing calls from Questie's own startup.
- Check owner job validity/resume, generation and identity before blaming data size. A single provider decode/enumeration or native render operation may overshoot a soft budget.
- Inspect other active features' direct per-quest reads separately; e.g. quest-item helpers intentionally inspect current quests and are not world catalogue scans.
