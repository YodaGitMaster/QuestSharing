# 2026-11-17 — Guidance submap rectangles lost the fourth bound

**Status**: solved in source; native rendering pending
**Severity**: medium
**Tags**: QuestGuidance.lua OptionalUI.lua U.call GetMapRectOnMap submap projection return-values

## Symptom
- Observed in follow-up tests: the guide draws zone stops, but a verified Sentinel Hill submap shows none.
- Expected: project local stops into the submap and omit stops outside its bounds.
- Environment: actual Lua 5.1 modules, modern/classic API styles; no live WoW process.

## Reproduction
- Plan Westfall; display child map 2001 whose parent is 1436 and rectangle is `{0.5,0.6,0.4,0.5}`; pickup/hand-in at `{0.55,0.45}` should project to `{0.5,0.5}`. Both API styles failed before patch.

## Root cause
- OptionalUI.call returns at most three values, but GetMapRectOnMap returns four. The missing bottom bound makes every ancestry transform fail validation.
- Trap category: runtime data shape / boundary contract mismatch.

## Methodology (reusable)
1. Test displayed child maps as well as the source zone and unrelated-map rejection.
2. Inspect rectangle values before validation rather than relaxing the ancestry/coordinate guards.
3. Compare shared wrapper return arity with the native API; use a local pcall preserving four values.
4. Retain negative sibling-map tests and zoom/pool reuse checks.

## Fix
- Files: QuestSharing/QuestGuidance.lua; tests/test_quest_guidance.py.
- Preserve all four bounds locally; no shared helper/provider changes.
- Commit / PR: local/unpublished. Workaround: no.

## Verification
- Guidance 40/40 across both API styles; full 43 suites / 1,583 checks; Lua 5.1 syntax/diff pass.
- Native map compositing/gamepad behavior remains unverified.

## If it shows up again
- Check wrapper arity first, then source/target ancestry, finite rectangle bounds and displayed map ID; do not admit sibling maps.
