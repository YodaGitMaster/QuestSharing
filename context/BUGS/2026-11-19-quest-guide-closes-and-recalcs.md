# 2026-11-19 — Quest guide closes itself and recalculates at random

**Status**: solved
**Severity**: high
**Tags**: QuestPlanner.lua, quest guide, scheduleRefresh, scan, clearPlan, BAG_UPDATE_DELAYED, UPDATE_FACTION, SKILL_LINES_CHANGED, SPELLS_CHANGED, OnUpdate rebuildProgress, currentZone, mine, cave, micro map, OnHide, panelDismissed, steps disappear

## Symptom
- Observed: "quest guide continue to always close itself and re-calc"; steps randomly disappear.
- Expected: guide stays on; recalculates when a quest is done (accepted, progressed, abandoned).
- Where: `QuestSharing/QuestPlanner.lua` (`scheduleRefresh`, `scan`, `P.open` OnUpdate, panel OnHide, `selectStop`/`P.pin`/`P.follow`).
- Environment: Classic Era, Questie; real game not checked.

## Reproduction
- Mock planner (`tests/test_quest_planner_ui.py` `planner_game`): fire `BAG_UPDATE_DELAYED`, advance 0.651 s -> visible rows 2 -> 0 (full rescan, `route={}`), then back to 2.
- `MAP_ID` = a mapType 5 "Fargodeep Mine" + `ZONE_CHANGED` -> rows 0; back outside -> full rebuild.
- Moving `POS` 0.03 every 3.1 s -> one replan per step.

## Root cause
- Four high-frequency events forced a full `scan()`, and `scan()` cleared `route` before the async rebuild; sub-maps (mine/cave/town/dungeon) returned no zone and `clearPlan` wiped the guide; an OnUpdate re-sorted the route while walking; OnHide ended the session even when the game (not the user) hid the UI.
- Trap category: lifecycle / over-eager invalidation (state reset on noise) + mutation before replacement.

## Methodology (reusable)
1. List every path that hides the panel or ends the session (`panel:Hide`, `panelDismissed`, `sessionActive=false`) and every path that calls `scan()`; grep other modules for the panel name (none).
2. Instrument, don't guess: wrap `ns.dataWork.start` to count "quest-plan" starts per event; sample visible rows right after the debounce timer but before the work pump.
3. Separate "replan" from "blank": a replan is fine if the old steps stay; the visible symptom was the empty `route` during the rebuild.
4. Fix pattern: replan only on events that change the plan's inputs (quest log membership/progress, level, zone, rep requirement flips via a signature `repGates()`); keep the previous result on screen until the new one replaces it; treat "not on a zone map" as paused, not as "new zone".
5. Dead end: UIParent hide in the harness does not fire children's OnHide; tested by hiding the panel directly.
6. Walking replan removal was a user decision (asked; the old behaviour was intentional for nearest-camp choice).

## Fix
- Files changed: `QuestSharing/QuestPlanner.lua`; tests `test_quest_planner_ui.py` (+5), `test_quest_optimizer.py`, `test_quest_planner_zone_steps.py`, `test_planner_facts.py`.
- Commit / PR: uncommitted.
- Workaround? no.

## Verification
- 5 new tests reproduce each cause and pass; full suite 0 FAIL.

## If it shows up again
- New `ns.on(...)` lines with `scheduleRefresh(true, ...)`; anything that sets `route = {}` before a rebuild finishes; `clearPlan` calls reached when `currentZone()` is nil; an OnUpdate added to the panel.
