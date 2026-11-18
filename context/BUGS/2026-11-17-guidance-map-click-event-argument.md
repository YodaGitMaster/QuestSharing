# 2026-11-17 — Guidance map click event argument

**Status**: solved in source (2026-11-17): the arity fix holds, and the f1b34e9 selection race is fixed (uncommitted/unreleased); native WoW validation pending
**Severity**: medium
**Tags**: QuestGuidance.lua Core.lua GLOBAL_MOUSE_DOWN GLOBAL_MOUSE_UP map waypoint event argument

## Symptom
- Observed during new, unpublished guidance integration: map marker tooltip appears, but a click never selects its step or sets a waypoint; 2/26 initial guidance checks fail on modern/classic.
- Expected: global matching left-button down/up on a hovered own marker selects/cycles the stop and uses planner waypoint behavior.
- Environment: Lua 5.1 harness loading actual addon; no published/live regression claimed.

## Reproduction
- Open guide/map with pickup and turn-in at the same location, hover their shared marker, dispatch GLOBAL_MOUSE_DOWN/UP with LeftButton; selection remains pickup and WAYPOINT stays nil.

## Root cause
- Core dispatches registered handlers with event name first. A one-argument callback read GLOBAL_MOUSE_UP as the button and rejected it.
- Trap category: type/runtime contract mismatch at shared dispatcher boundary.

## Methodology (reusable)
1. Test the UI action through the actual dispatcher rather than calling internal selection directly.
2. Inspect hovered marker, selected index and resulting native waypoint separately; working tooltip narrowed failure to event delivery.
3. Read Core's dispatch call and compare callback arity; preserve `(event,...)` even when the event is unused.
4. Add positive click/cycle and negative drag-off/right/combat cases across API styles.

## Fix
- Files changed: QuestSharing/QuestGuidance.lua, tests/test_quest_guidance.py.
- Global mouse handlers accept `(_,button)`; no map click scripts/pin provider introduced.
- Commit / PR: local unpublished preview.
- Workaround? No.

## Verification
- Guidance suite 30/30 on modern/classic: map selection updates native waypoint and highlighted step; grouped marker cycles; right-click/drag-off/combat do not select.
- Full 41 suites / 1,491 checks pass; Lua syntax and diff checks pass. Native game rendering/gamepad interaction pending.

## If it shows up again
- Check ns.on callback arguments first, then hover/press identity, layer visibility and combat guards; do not bypass the dispatcher in the regression test.

---
## Addendum 2026-11-17 — audit: new variant (selection race)
- What happened: bug audit (BPMN run r-20261117-212533-cf04). The `(_, button)` arity fix holds and all click/cycle/drag-off/right-click/combat tests pass. The refuter reproduced a new way to lose a map click (both clients): clicking step 2 while the background `quest-improve` job runs → after the job the guide snaps back to step 1 while the native waypoint stays on step 2.
- Why the previous fix did not cover it: different root cause, added in f1b34e9 (absent in v0.4.21). `refine()` in `QuestPlanner.lua` (~:922-933) captures `selectionLocked`/`route[selected]` identity at job START, then after `solve(IMPROVE_STEPS)` sets `selected = 1` and restores only that stale key. Same race hits list-row clicks and Next/Previous (all go through `selectStop`). Independently reproduced 3 times (g3 checker, g3 refuter, g5 refuter).
- New approach: read the selection key right before `route = visibleStops(...)` swaps the route (after the optimizer returns); add a test that clicks while `NS.dataWork.busy("quest-improve")`.
- Result / new status: open (not fixed yet).

---
## Addendum 2026-11-17 — selection race fixed in source (fix-all run)
- What happened: BPMN run r-20261117-215940-e171, stream A1 of `context/fix-plan-2026-11-17.md`.
- Fix pattern: read state at the moment you use it, not when a long job starts. `solve()` in `QuestPlanner.lua` (~:991-997) now reads `selectionLocked` and `stopIdentity(route[selected])` right before `route = visibleStops(...)` swaps the route. `refine()` no longer captures anything at job start. `selected` resets to 1 only when nothing is locked or the locked stop no longer exists. The same rule applies on the quest-costs path, because it shares `solve()`.
- Test: `test_step_chosen_during_background_refinement_survives_the_route_swap` (`tests/test_quest_optimizer.py`). It selects a step while `quest-improve` is busy; after the swap, both the selection and the waypoint still match.
- If it shows up again: look for any new background job that caches `route[selected]` before yielding. All selection paths (map click, list row, `/qs plan next`) go through `selectStop`.
- Result / new status: solved in source (uncommitted, unreleased). Native check pending: in game, click a map step while the guide refines.
