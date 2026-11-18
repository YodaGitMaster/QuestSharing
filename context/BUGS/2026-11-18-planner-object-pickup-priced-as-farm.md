# 2026-11-18 — Pick-one-item-from-the-world quests priced as a 60 s farm, far cluster chosen

**Status**: solved in source; unreleased; native WoW check pending
**Severity**: medium
**Tags**: quest planner, QuestOptimizer, farmAt, targetLocation, objectDrops, object pickup, "Work time estimated; the quantity or drop rate is unknown.", Heavenly Bloom, Bloom of the Heavens, REAL_CAMP, road insertion

## Symptom
- Observed (user): a quest like "Bloom of the Heaven(s)" — pick up just one item — "is never considered". Reproduced with a fixture (item whose only source is a world object): the quest IS planned but (1) its step says "Work time estimated; the quantity or drop rate is unknown." = 60 s for a few-second pickup; (2) with one flower 2 map units from the player and a pair 0.4 units away, the guide chose the far pair; (3) a pickup on the way is never taken on the way.
- Expected: a pickup costs a few seconds per item, goes to the nearest object, and can be taken on the route; the step reads "Pick up X".
- Where: `QuestPlanner.lua` `targetLocation` (camp rule), `QuestOptimizer.lua` `farmAt` / `service` / `sitesFor`.
- Environment: item objective (`objectives[3]`) whose `objectDrops` are objects, no creature drops; no drop-rate data for objects.
- Note: no quest named "Bloom of the Heaven(s)" exists in QuestieDB Classic or Forever data (closest: Serpentbloom, Peacebloom); fixed for the whole class, quest name unverified.

## Reproduction
- Fixture in `tests/test_quest_planner_zone_steps.py` (`PICKUP`): object 900 at (52,52) alone and (90,90),(91,91); item 900 `objectDrops={900}`; one-item quest. Before: waypoint (0.9,0.9), workSeconds 63, "Work time estimated" in the step.

## Root cause
- `farmAt` treated every `loot` objective as a creature farm: no creature id -> no drop rate -> `{unknown=true}` -> 60 s default, and "farm" stops are excluded from road insertion. `targetLocation` applied the creature camp rule (`REAL_CAMP`, biggest camp) to objects, dropping a lone point when a 2-point cluster exists.
- Trap category: wrong model for a different source kind (reusing mob logic for objects).

## Methodology (reusable)
1. Confirmed the quest type exists in the data path (adapter `plannerTargets` -> `itemSources` includes `objectDrops`), then reproduced with the real planner harness instead of reading code only.
2. Priced work per source kind: object pickups are interactions (`interactionSeconds` x count), not rolls.
3. For "any one of them will do" sources every local spawn is a destination; the camp rule belongs to creature grinds only.
4. Carried `sourceKind` through stop rows, alternatives, busy-camp promotion and the optimizer's returned stop so each site is priced by its own kind (a mixed item can come from a chest or a mob).

## Fix
- Files changed: `QuestSharing/QuestPlanner.lua` (`targetSummary` wording, `targetLocation` objects bypass camps, `sourceKind` on rows/alternatives/`avoidBusyCamps`), `QuestSharing/QuestOptimizer.lua` (`farmAt` returns nil for object loot, `site.pickup`, `service` prices pickups, `advance` adds the item to the simulated inventory, `located` copies `sourceKind`), tests in `test_quest_planner_zone_steps.py` (3) and `test_quest_optimizer.py` (1), CHANGELOG `## Unreleased`.
- Workaround? no.

## Verification
- 4 new tests failed first, pass now on both client styles; planner/optimizer/guide/UI/path/facts/budget/guidance/gather suites pass; Lua 5.1 compile OK.

## If it shows up again
- Not covered yet: more items needed than object spawn points (respawn wait), item from a mob AND an object with different odds (priced per chosen site), objects needing a long cast or key. Respawn data plan: `context/insights.md` 2026-11-18 (cmangos creature table; objects have `gameobject` spawn rows with `spawntimesecs`).
