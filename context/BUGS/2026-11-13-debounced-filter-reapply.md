# 2026-11-13 — Delayed range filter reset the current page

**Status**: solved
**Severity**: medium
**Tags**: EquipmentUI.lua liveBox applyRange debounce Apply pagination page reset timer cancellation

## Symptom
- Observed during 0.4.7 implementation: typing a bound, clicking Apply and scrolling immediately could jump back to page one when the earlier delayed callback ran.
- Expected: Apply commits the range once; subsequent navigation stays where the user put it.
- Environment: Lua 5.1 modern/classic API harnesses; new usability controls, not present in previously published versions.

## Reproduction
- Open 18 eligible quest rewards; type Max=20, click Apply, wheel to page two within 180ms, advance 300ms.
- Before correction, selected quest and page changed back; both API styles failed the new workflow regression.

## Root cause
- Explicit Apply committed the range but left both edit boxes' debounce callbacks queued; a later identical filter update reset pagination.
- Trap category: race condition / stale callback; two submission paths owned the same pending edit.

## Methodology (reusable)
1. Exercise a complete editing-and-navigation workflow, not merely a filter predicate or a delayed callback in isolation.
2. Reproduce the timing window by advancing a deterministic clock after explicit Apply and page navigation.
3. Verify the unexpected refresh uses the same already-committed range, ruling out input parsing and pagination boundaries.
4. Cancel pending debounce work at the common commit function before applying the new range. This covers Enter, button Apply and timed commits consistently.

## Fix
- `QuestSharing/EquipmentUI.lua`: common range commit cancels both input serials before applying.
- Regression in `tests/test_usability.py` fails before and passes after correction on both API paths.
- Release: v0.4.7; no workaround or SavedVariables changes.

## Verification
- Released at `13d718f8212f084b7748c8f311d8ea5a2113664d`, v0.4.7; 29 suites / 1,121 checks passed and published ZIP byte-matched.
- Focused regression: 26/28 before correction, 28/28 after.
- Full-suite and published asset verification recorded in context/state.md.

| Wanted | Done | Match |
|---|---|---|
| Apply commits once | Both pending range callbacks invalidated | ✅ |
| Scrolling retains current page | Delayed clock advance preserves selected result | ✅ |

| Quality check | Result |
|---|---|
| Only planned runtime change | ✅ |
| Symptom reproduced and resolved | ✅ |
| Both API styles pass | ✅ |
| Minimal fix; no refactor | ✅ |

## If it shows up again
- Inspect all explicit and debounced paths to the same commit function; they must share cancellation.
- Include navigation or selection after submission in the reproduction, then advance past the debounce interval.

## Addendum 2026-11-13 — Pending search versus initial dungeon focus
- New variant during unreleased 0.4.9: opening a 250-row catalogue and immediately typing Captain allowed indexing to finish before the 180ms live-search callback; automatic focus cleared the new text and selected Wailing Caverns.
- Previous range-submit fix still holds; this new asynchronous writer was in Loot.lua and did not own the edit-box debounce. Trap: race condition between initial catalogue focus and pending manual input.
- Reproduced on both API styles in test_instance_focus.py (22/24 before correction). Apply the same methodology: type, complete background indexing, advance beyond debounce, inspect final query and selected dungeon together.
- Fix: initial focus discards its target and yields when either search field is dirty, leaving the user's pending callback intact. No common debounce, provider or range-filter change.
- Result: 24/24 focused checks pass; original range/pagination suites remain covered by the full verification run. Status: solved.

| Wanted | Done | Match |
|---|---|---|
| Typing during catalogue load stays authoritative | Initial focus yields to dirty edit boxes | ✅ |
| Normal first opening still selects current dungeon | No pending input continues through normal matching | ✅ |

| Quality check | Result |
|---|---|
| Only planned runtime files changed | ✅ |
| Symptom reproduced before correction | ✅ |
| Modern and classic paths verified | ✅ |
| Minimal fix, no unrelated refactor | ✅ |
