# 2026-11-16 — Quest planner panel cannot be moved

**Status**: solved
**Severity**: medium
**Tags**: QuestPlanner.lua, planner panel, drag, movable, dockPanel

## Symptom
- Observed: The user cannot move the quest planner panel.
- Expected: Drag the panel and keep its new position during the session.
- Where: `QuestSharing/QuestPlanner.lua`; shared drag behavior in `Style.lua:S.window`.
- Environment: Quest Sharing, Interface 16001.

## Reproduction
- Open `/qs plan` and try dragging the panel.

## Root cause
- `ensurePanel()` set the shared movable window to immovable and removed its drag handlers. `dockPanel()` also reset placement whenever the panel opened or refreshed.
- Trap category: lifecycle / state reset.

## Methodology (reusable)
1. Trace `S.window()` defaults before changing panel code; it already provides clamped movement and an `onMoved` callback.
2. Search every call to the docking function, not only the first-open path.
3. Preserve the default dock until the user moves the panel; then skip docking for the rest of the session.

## Fix
- Files changed: `QuestSharing/QuestPlanner.lua`.
- Commit / PR: Quest Sharing v0.4.18.
- Workaround? no.

## Verification
- `tests/test_quest_planner_ui.py` confirms movement handlers are present and reopening retains the manually set position.
- Native WoW drag behavior remains pending live-client validation.

## If it shows up again
- Check for any planner path that calls `SetMovable(false)`, clears drag handlers, or invokes docking after `panel.onMoved` fires.
