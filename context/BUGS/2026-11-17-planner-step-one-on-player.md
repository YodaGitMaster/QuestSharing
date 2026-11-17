# 2026-11-17 — Quest guide step 1 sits on the player and follows them

**Status**: solved in source; native WoW validation pending; unreleased
**Severity**: high
**Tags**: QuestPlanner.lua targetLocation nearestPoint playerPoint objective spawn camp groupCamps REAL_CAMP CLUSTER_DISTANCE "starts from me as point 1" step 1 follows player rebuildProgress OnUpdate

## Symptom
- Observed: user reports the quest algorithm "start[s] from me as point 1 which is wrong". Step 1 (and its map pin) lands on the player's own position; after walking it re-appears on the player again.
- Expected: step 1 is a real destination (a giver, or the area where the mobs/objects actually are); your position is only the route's origin.
- Where: `QuestSharing/QuestPlanner.lua` `targetLocation()` -> `nearestPoint()`; movement re-plan in `P.open()` OnUpdate.
- Environment: QuestieDB lists every spawn of an NPC/object separately; common mobs have lone spawns scattered over the whole zone.

## Reproduction
- Active local kill quest; mob has a 6-spawn camp at 30,30 plus lone spawns at 50.4,50.3 and 70.3,70.2; player at 50,50.
- Before fix: step 1 at 50.4,50.3 (on the player). Move player to 70,70 and wait 3 s: step 1 at 70.3,70.2 (on the player again). The camp never appears.

## Root cause
- An objective's location was the single spawn closest to `playerPoint`. With scattered lone spawns there is nearly always one at the player's feet, and the panel re-plans every 3 s after >= 0.025 map units of movement, so the step re-snaps to the new position.
- Trap category: wrong key (distance to the player used as "where the work is") + value recomputed from a moving input.

## Methodology (reusable)
1. Rule out the renderers first: the map overlay (`QuestGuidance.drawMap`) only draws route stops, and the optimizer never inserts the origin as a stop. So a stop "at me" must come from stop point data.
2. Trace stop points to their producer: pickups/turn-ins use `nearestSource()` (givers have about 1 spawn), objectives use `targetLocation()` -> `nearestPoint()` over every spawn.
3. Reproduce with the real Lua planner: a camp plus lone spawns, then move the mocked player and advance past the 3 s re-plan. The step following the player confirms the mechanism.
4. Fix pattern: represent where the work is independently of the player. Group spawns into camps, then use the player only to pick among real camps (the user chose "nearest real camp" over "biggest camp").
5. Ruled out: the optimizer (`QuestOptimizer.lua`) and guidance overlay need no change; SPF first-leg costs only refine travel from the origin.

## Fix
- Files changed: `QuestSharing/QuestPlanner.lua` (`groupCamps`, `REAL_CAMP`, `targetLocation`), `tests/test_quest_planner_zone_steps.py`, README, CHANGELOG (Unreleased), context notes.
- Camps: per map, the densest untaken spawn seeds a camp of the free spawns within `CLUSTER_DISTANCE` (0.065, grid-bucketed); the member nearest the camp centroid marks it. A camp is real at >= min(3, the target's biggest camp on any map). The nearest real local camp wins, and the camps are cached on the target for the scan.
- Commit / PR: local, uncommitted.
- Workaround? no.

## Verification
- New tests (both modern/classic): lone spawns never outrank the 30,30 camp, including after moving; with two real camps the step stays at 30,30 at 52,52 and switches to 80,80 only at 75,75.
- Zone suite 38/38; full 46 suites 1,756/1,756; 44 Lua modules compile; `git diff --check` clean; preview tool still yields 8 steps. A synthetic 20-quest x 600-spawn scan plans in 0.18 s in the harness.
- Native WoW behavior not verified.

## If it shows up again
- Check whether a new caller picks objective points with `nearestPoint()` instead of `targetLocation()`.
- Check whether `target.camps` is computed before `frameMap` is set (camps cache local projections for one scan).
- If a real mob with tight lone spawns lands wrong, compare its spawn spacing with `CLUSTER_DISTANCE` and `REAL_CAMP`.
