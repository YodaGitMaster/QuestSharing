# 2026-11-17 — Guidance map click event argument

**Status**: solved
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
