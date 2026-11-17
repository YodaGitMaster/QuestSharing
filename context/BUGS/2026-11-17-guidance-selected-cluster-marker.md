# 2026-11-17 — Selected clustered stop was hidden by the marker summary

**Status**: solved in source; native rendering pending
**Severity**: low
**Tags**: QuestGuidance.lua grouped-marker selectedStop map position label

## Symptom
- Observed in follow-up tests: selecting step 8 in an eight-stop cluster still labels the highlighted pin `1/2/3+`, anchored at the cluster's first stop.
- Expected: the selected step number remains visible and the highlighted pin uses that step's exact position.
- Environment: actual Lua 5.1 modules, modern/classic API styles.

## Reproduction
- Create eight nearby stops at x=`0.55+i/1000`, y=`0.45`; select index 8. Both styles failed selected-number/position expectations before patch.

## Root cause
- Group summaries always showed the first three entries and used the first point, independent of current selection.
- Trap category: presentation state inconsistent with selection.

## Methodology (reusable)
1. Exercise selection beyond a summary's truncation boundary with nearby but nonidentical coordinates.
2. Assert both the visible selected number and marker placement, not just highlight color.
3. Preserve grouping/cycling and summary size; replace the third visible number with the selected one when necessary, and place the active group at the selected point.

## Fix
- Files: QuestSharing/QuestGuidance.lua; tests/test_quest_guidance.py.
- No changes to route ordering, waypoint coordinates or quest progress.
- Commit / PR: local/unpublished. Workaround: no.

## Verification
- Guidance 40/40 across both styles; full 43 suites / 1,583 checks; zoom reuse, group cycling, right-click/drag-off/combat and arrival checks pass; Lua syntax/diff pass.
- Native rendering remains unverified.

## If it shows up again
- Check the selected index against summary cutoffs and the projected point used for active markers; do not disable grouping to expose hidden entries.
