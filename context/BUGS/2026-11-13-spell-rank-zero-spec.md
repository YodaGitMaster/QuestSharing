# 2026-11-13 — Active zero specialization skipped spell ranks

**Status**: solved
**Severity**: medium
**Tags**: SpellRanks.lua GetSpellTabInfo offSpecID 0 Lua truthiness spell rank legacy C_SpellBook

## Symptom
- Observed during unreleased 0.4.10: legacy action buttons did not upgrade although higher learned ranks were enumerated.
- Expected: active player skill lines participate; non-active specializations do not.
- Environment: Lua 5.1, legacy GetSpellTabInfo returns offSpecID=0; modern path also tested with zero.

## Reproduction
- Spell book contains Healing Touch ranks 1, 2 and 10; action slot holds rank 1; active tab reports offSpecID=0; enable the feature.
- Initial test run failed the zero-spec cases on both API styles and most legacy upgrade workflows (20/36 total passed).

## Root cause
- `not offSpecID` rejected numeric zero, which is truthy in Lua; the value means an active/general tab in the legacy API.
- Trap category: falsy/null trap and API runtime-shape mismatch.

## Methodology (reusable)
1. Exercise both API shapes using real Lua, with actual numeric zero instead of a convenient nil fixture.
2. Compare successful modern entry enumeration with failed legacy line enumeration to isolate the gate before rank comparison or placement.
3. Verify the sentinel against primary integration code (Myslot's legacy spell-book enumeration).
4. Accept nil/false/zero explicitly as non-offspec and retain exclusion of positive specialization IDs.

## Fix
- Files changed: QuestSharing/SpellRanks.lua; tests/test_spell_ranks.py.
- Release: v0.4.10; no workaround, persistence change or rank heuristic.

## Verification
- Dedicated tests: 36/36 after initial corrections, expanded to 44/44 including exclusion of positive offspec IDs; both API styles.

| Wanted | Done | Match |
|---|---|---|
| Active zero spec upgrades learned ranks | Explicit zero sentinel check | ✅ |
| Other specs remain excluded | Positive offspec line test | ✅ |

| Quality check | Result |
|---|---|
| Only planned module/tests affected | ✅ |
| Reproduced before correction | ✅ |
| Modern and legacy paths verified | ✅ |
| Minimal predicate correction | ✅ |

## If it shows up again
- Inspect actual offSpecID values and Lua truthiness; do not change learned-rank comparisons to compensate for an empty catalogue.
