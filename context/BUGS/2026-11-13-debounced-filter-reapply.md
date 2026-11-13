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
