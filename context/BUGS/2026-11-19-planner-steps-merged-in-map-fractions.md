# 2026-11-19 — Quest guide merges two NPCs 185 yards apart into one step

**Status**: solved
**Severity**: medium
**Tags**: QuestPlanner, visibleStops, groupCamps, CLUSTER_DISTANCE, TAKEIN_DISTANCE, map fraction, yards, GetMapWorldSize, Mountaineer Thalos, Balir Frosthammer, Coldridge Valley, Dun Morogh

## Symptom
- Observed: Quest guide step "Hand in to Balir Frosthammer" also listed "Turn in Senir's Observations to Mountaineer Thalos", with Balir's coordinates (29.7, 71.3). Thalos stands at 33.5, 71.8.
- Expected: two steps, each at its NPC.
- Where: `QuestSharing/QuestPlanner.lua` `visibleStops` (and `groupCamps`, mixed-camp rule).
- Environment: large zone maps (Dun Morogh 4,925 x 3,283 yd). Found by the Coldridge Valley reference test on real QuestieDB data.

## Reproduction
- `tests/test_coldridge_valley.py::test_two_hand_ins_185_yards_apart_stay_two_steps`: quests 170 and 282 ready in the log; the two hand-ins are consecutive.

## Root cause
- Radii were fixed map fractions (stop merge 0.045, camp 0.065). On Dun Morogh 0.045 ~ 220 yd, so NPCs 185 yd apart collapsed into one step at the first NPC's point.
- Trap category: type vs runtime mismatch (unit: map fraction treated as a distance).

## Methodology (reusable)
1. Ran the guide on real data and checked every pickup/hand-in point against its NPC's spawn (test R6). Thalos's hand-in had the wrong point.
2. The debug text showed the atom kept Thalos's quest but the step used the previous stop's point -> grouping, not data.
3. `visibleStops` merges consecutive stops of one kind within `TAKEIN_DISTANCE`; converted 0.045 to yards with the map size -> 220 yd > 185 yd.
4. Fix pattern: measure grouping in yards via `C_Map.GetMapWorldSize` (cached per map), keep the old fractions only when the size is unknown.
5. Dead end: the main route test alone did not catch it later, because the refined route no longer puts the two hand-ins next to each other; a dedicated two-hand-in test was added.

## Fix
- Files changed: `QuestSharing/QuestPlanner.lua` (`yardScale`, `within`, `CLUSTER_YARDS` 100, `TAKEIN_YARDS` 45, `groupCamps` in yards), `tests/test_coldridge_valley.py`.
- Commit / PR: uncommitted (2026-11-19).
- Workaround? no.

## Verification
- Test fails with `yardScale` disabled, passes with it. Full suite 62 files green.

## If it shows up again
- Check a map's world size is known (`C_Map.GetMapWorldSize`); without it the fraction fallback returns.
- Two givers in one building (~45 yd) should still be one step; if they split, `TAKEIN_YARDS` is too small.
