# 2026-11-17 — DropDB percentage units

**Status**: solved
**Severity**: medium
**Tags**: Questie.lua itemDropRate DropDB 0.25 percent probability

## Symptom
- Observed: a DropDB value of 0.25 percent becomes 25 percent.
- Expected: retain percentages in the adapter, then divide by 100 exactly once for probability.
- Environment: Questie DropDB GetItemDroprate tuple {percent, source}.

## Reproduction
- Return {0.25, "cmangos"} for a known NPC/item pair.
- Previous adapter treats any number <=1 as a fraction and multiplies it by 100.

## Root cause
- Heuristic unit inference contradicts the provider's percentage contract.
- Trap category: type vs runtime mismatch.

## Methodology (reusable)
1. Inspect the producer's return contract and units.
2. Test values below one, exactly one, zero and over 100.
3. Normalize once at the probability consumer boundary, retaining the source label.
4. Reject unrecognized shapes and out-of-range values.

## Fix
- Files changed: QuestSharing/Questie.lua, tests/test_planner_facts.py.
- Local work, uncommitted and unpublished.
- Workaround? No.

## Verification
- Adapter outputs 0.25%, 1%, 0% and rejects 105%.
- Planner target probabilities are 0.0025, 0.01 and 0 with source provenance.
- Provider-facts suite passes on modern and Classic API styles.

## If it shows up again
- Check provider version/shape before introducing any inferred percentage/fraction conversion.
