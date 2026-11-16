# 2026-11-16 — Quest planner empty-level and candidate-shape errors

**Status**: solved
**Severity**: high
**Tags**: QuestPlanner.lua, Questie.lua, plannerQuest, q.data, tonumber, missing questLevel, Lua argument expected

## Symptom
- Observed: enabling the planner with valid Questie records records an error instead of building route stops. Reproduction logs included `QuestPlanner.lua:362: attempt to index local 'data' (a nil value)` and, with a quest lacking optional level fields, `Questie.lua:482: bad argument #1 to 'tonumber' (value expected)`.
- Expected: quests with valid names and locations still plan when optional level fields are absent.
- Where: `QuestSharing/QuestPlanner.lua:buildRoute`; `QuestSharing/Questie.lua:Q.plannerQuest`.
- Environment: Lua 5.1; recent Questie enumerable quest IDs; valid quest starter/objective data; optional level fields omitted.

## Reproduction
- Enable Quest planner with one active Questie quest having spawn and objective data. The candidate stores Questie projection fields directly, then `buildRoute` reads `q.data.targets` and errors.
- Remove `questLevel` or `requiredLevel` from the Questie record. Lua's `field()` helper may return zero values; passing that directly to `tonumber` results in a zero-argument call.

## Root cause
- `newCandidate` returns the Questie projection with planner fields attached, not `{data=projection}`; `buildRoute` dereferenced a nonexistent nested field.
- Optional Questie values were passed as the sole argument to `tonumber` without first supplying a fallback, which fails when `field()` returns no values.
- Trap category: declared data shape did not match runtime shape; missing/nil argument boundary.

## Methodology (reusable)
1. Exercise the actual Questie projection and full `scan -> buildGraph -> buildRoute` lifecycle with a minimal zone map and Questie catalogue.
2. Follow the first error into the exact candidate creator; compare its return fields with every consumer instead of inferring an intended wrapper.
3. Keep optional data absent in the fixture to catch no-value Lua function returns, not just explicit `nil` values.
4. Read the projection directly in `buildRoute` and supply a numeric fallback before `tonumber`.

## Fix
- Files changed: `QuestSharing/QuestPlanner.lua`, `QuestSharing/Questie.lua`, `tests/harness.py`, `tests/test_quest_planner_path.py`.
- Commit / PR: local unreleased changes; none.
- Workaround? no.

## Verification
- Focused planner/SPF suite: 10/10.
- Full documented runner: 35 suites / 1,324 checks pass.
- `luac -p` on changed runtime Lua files and `git diff --check` pass.
- Native WoW/SPF map drawing remains unverified.

## If it shows up again
- Compare `newCandidate`'s return shape to `buildRoute`'s reads before adding nested wrappers.
- Test missing, explicit-nil and numeric-string Questie level values through the real catalogue scan.

---
