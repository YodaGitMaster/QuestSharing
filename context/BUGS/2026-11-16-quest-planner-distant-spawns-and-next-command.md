# 2026-11-16 — Quest planner distant spawn camps and next command

**Status**: solved
**Severity**: low
**Tags**: QuestPlanner.lua, QuestPlanner, sourceKey, spawn camps, `/qs plan next`, empty route

## Symptom
- Observed: review found a route could merge objective locations far apart when they shared one Questie NPC/object source ID; `/qs plan next` could call pin after selection failed.
- Expected: objective stops merge only when their locations are close; next only pins a successfully selected stop.
- Where: `QuestSharing/QuestPlanner.lua` (`findOrAddStop`, `P.command`).
- Environment: Questie can associate one source ID with multiple spawn coordinates; route can become empty or stale after map/quest changes.

## Reproduction
- Give two objective targets the same sole source ID with spawn camps farther apart than `CLUSTER_DISTANCE`; route previously treated the shared ID as sufficient to reuse the first stop.
- Run `/qs plan next` with no route or after a zone change causes `selectStop` to reject the old route.

## Root cause
- The `sourceKey` match bypassed the geographic-distance threshold.
- The command ignored the boolean result from `selectStop` and always called `P.pin`.
- Trap category: wrong grouping key; unchecked failure return.

## Methodology (reusable)
1. Trace route clustering from Questie spawn rows through `findOrAddStop`; compare the full source identity against the actual coordinate distance.
2. Trace `/qs plan next` through `selectStop` and `P.pin`, including empty-route and changed-zone returns.
3. Distinguish plain `pytest` collection from the repository's documented runner: each `tests/test_*.py` file runs its own `Game` harness directly.
4. Require both geographic proximity and stop-kind equality to merge; only pin after selection succeeds.

## Fix
- Files changed: `QuestSharing/QuestPlanner.lua`.
- Commit / PR: local unreleased changes; none.
- Workaround? no.

## Verification
- All 34 documented harness suites pass: 1,314 checks.
- `luac -p QuestSharing/QuestPlanner.lua QuestSharing/Settings.lua` passes; `git diff --check` passes.
- Native WoW client behavior remains unverified.

## If it shows up again
- Inspect `findOrAddStop` to ensure any source identity optimization still observes the coordinate threshold.
- Inspect callers of `selectStop` to ensure failure does not proceed to waypoint placement.

---
