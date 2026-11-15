# 2026-11-15 — Extra tools settings exceed the window

**Status**: solved
**Severity**: medium
**Tags**: QuestSharing/Settings.lua, Extra tools, settings window, layout overflow, test_look.py

## Symptom
- Observed: `test_rows_are_laid_out_top_to_bottom_without_overlapping_and_fit_in_the_window` failed for both modern and classic paths with `AssertionError ('optional', 676)`.
- Expected: each settings tab's rows remain above the window's 600px content boundary.
- Where: `QuestSharing/Settings.lua`, Extra tools settings tab.
- Environment: local Quest Sharing 0.4.15 release checks; 630px settings window, top content offset 98px.

## Reproduction
- Add the three quest automation setting rows (section header and two described switches) to the already full Extra tools tab.
- Run `tests/test_look.py`; the optional-tab bottom reaches 676px and fails both client styles.

## Root cause
- The new settings added about 98px of vertical content to a tab that had no spare space; `refreshSettings()` places rows linearly and the fixed-height window has no scrolling.
- Trap category: layout capacity / unverified UI bounds.

## Methodology (reusable)
1. Run the per-tab layout assertion before packaging; it checks gaps, overlap and the bottom margin for both client styles.
2. Compare the failing tab's measured bottom against `W.win.height - 30`; here optional was 676px against a 600px limit.
3. Measure candidate tabs before moving controls. Tracker was at 414px before the added 98px section, fitting at approximately 512px with 88px remaining.
4. Put quest offer/turn-in switches under Tracker's related quest behavior section instead of expanding the full settings window or adding scrolling. Keep their persistence and defaults unchanged.

## Fix
- Files changed: `QuestSharing/Settings.lua`, `README.md`, `CHANGELOG.md`.
- Commit / PR: pending release commit.
- Workaround? no.

## Verification
- `tests/test_look.py`: 42/42 passed (both styles); all 34 test files passed, 1,291 checks total.
- Built `dist/QuestSharing-0.4.15.zip`; package test confirmed TOC files are present and no test files were packaged.
- Whitespace check passed. Native game rendering remains unverified.

## If it shows up again
- When adding setting rows, run the tab-height assertion in `tests/test_look.py` for all tabs and both client styles.
- If a tab approaches the 600px content boundary, move related controls to a tab with measured space or implement a deliberate scrolling design; do not only increase the window height without checking short screens.

---
