# 2026-11-17 — Journal tabs open as a black page (EditBox:SetFont without flags)

**Status**: solved in source; native WoW confirmation pending; unreleased
**Severity**: high
**Tags**: EquipmentUI.lua font() E.box SetFont flags EditBox "Usage: SetFont" DungeonQuests.lua build() black page empty window "Character level" "All factions" "All classes" Adventurer's Journal v0.4.20 v0.4.21 harness

## Symptom
- Observed (user, v0.4.21): Dungeon quests "db search stays all black", only Character level and All factions / All classes visible, nothing else.
- Expected: dungeon dropdown row, level/completed/My character buttons, search, status, 5 quest rows, parchment details pane, Previous/Next/Refresh.
- Where: `QuestSharing/EquipmentUI.lua` `font()` → `E.box`; callers `E.page`/host `build()` (`controls.min`), `DungeonQuests.lua` `build()` (`window.level`), `buildMenu()` (`menu.search`).
- Environment: real client (Classic Era API docs); the harness did not see it. Introduced with the journal restyle in v0.4.20 (`U.box` → `E.box`).

## Reproduction
- Harness with client-accurate `SetFont` (EditBox requires flags): every dungeon/loot test fails with `Usage: EditBox:SetFont(fontFile, height, flags)`; new regression test 0/64 without fix.

## Root cause
- `font()` called `text:SetFont(file, size)` with nil flags. Allowed for FontString, error for EditBox. The first `E.box` throws mid-build; `window`/`host` were already assigned, so every reopen reuses the half-built page (controls created before the box survive: top dropdowns + "Character level" label/box).
- Trap category: type vs runtime mismatch (API signature differs per widget) + test mock lacking the method so a `if x.SetFont` guard hid the path.

## Methodology (reusable)
1. Map "what is visible" to build order: visible controls = those created before the first failing call. Last visible = `U.box` label inside `E.box` → error is inside `E.box` after `U.box`.
2. `git diff v0.4.19 v0.4.21` of the build: only change at that point is `U.box` → `E.box` (adds `E.surface`, `font`, `SetTextInsets`).
3. Grep `SetFont(`: other modules pass `""` flags; `EquipmentUI` does not. Dropdown labels (FontStrings) use the same `font()` and render → widget-specific.
4. Confirm against Blizzard docs (`Gethe/wow-ui-source` classic_era `SimpleEditBoxAPIDocumentation` flags Nilable=false vs `SimpleFontStringAPIDocumentation` Nilable=true).
5. Harness had no `SetFont` → guard skipped it in all tests. Made the harness enforce the real signature, reproduced, then fixed.

## Fix
- Files changed: `QuestSharing/EquipmentUI.lua` (`font()` passes `""` flags), `tests/harness.py` (`CreateFrame` records kind; `SetFont` enforces EditBox flags), `tests/test_dungeon_quests.py` (full-build regression test).
- Commit / PR: local, uncommitted. Workaround? No.

## Verification
- Regression test fails without fix (0/64, exact Usage error), passes with it; full 46 suites / 1,766 checks; diff check clean. Native client not re-run.

## If it shows up again
- Partial window = an error during `build()`. Ask for `/qs errors`; compare visible controls against build order.
- Any new `SetFont` on an EditBox/ScrollingMessageFrame: always pass flags. Keep harness signatures strict when adding mock methods.
