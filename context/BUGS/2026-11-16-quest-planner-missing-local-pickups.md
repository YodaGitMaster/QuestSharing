# 2026-11-16 — Quest planner misses local pickup quests

**Status**: solved
**Severity**: high
**Tags**: QuestPlanner.lua, Questie starter, quest giver, nearestPoint, nearestSource, new-zone plan

## Symptom
- Observed: A new-zone plan can fail to list available quests when the character has no matching active quests.
- Expected: Show each eligible local quest pickup and its giver even when the quest log is empty.
- Where: `QuestSharing/QuestPlanner.lua:scan`, `newCandidate`.
- Environment: QuestieDB with mapped `startedBy` NPC/object spawns.

## Reproduction
- Start with an empty quest log and a Questie quest with a known starter spawn in the current outdoor zone; enable the planner.

## Root cause
- The planner passed Questie starter source records (`{id,name,spawns}`) to `nearestPoint()`, which expects flat `{map,x,y}` points. The resulting nil start point filtered out the new candidate. `buildRoute()` already uses `nearestSource()` for the same data shape.
- Trap category: declared/runtime data shape mismatch.

## Methodology (reusable)
1. Trace one candidate from `plannerStarters()` through point selection and the scan filter.
2. Compare the actual source shape with the helper's expected input.
3. Reuse the source-aware helper that walks each source's spawn list; add an empty-quest-log case to prevent active quests from masking the failure.

## Fix
- Files changed: `QuestSharing/QuestPlanner.lua`, planner UI tests.
- Commit / PR: Quest Sharing v0.4.18.
- Workaround? no.

## Verification
- `tests/test_quest_planner_ui.py` starts with no matching active quests and confirms mapped, in-range giver pickups appear line by line.
- Native data and layout remain pending live-client validation.

## If it shows up again
- Verify Questie `startedBy` source records contain projected `spawns`, then ensure scan uses `nearestSource()` rather than `nearestPoint()` on those source records.
