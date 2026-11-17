# 2026-11-17 — Multiple drop confidence

**Status**: solved
**Severity**: medium
**Tags**: QuestOptimizer.lua, service, campWork, multiple loot streams, uncertain

## Symptom
- Observed: two accepted quests collecting different items from one NPC could receive an additive expected-kill estimate with `report.uncertain=false`.
- Expected: identify the missing joint drop distribution and label the estimate uncertain.
- Where: `QuestOptimizer.service` and report replay.
- Environment: both quests accepted before the first farm action, same NPC/camp and known separate item rates.

## Reproduction
- Put two active loot objectives at one camp with separate item IDs and rates, then optimize their hand-ins. Read the report's uncertainty flag and second action reason.

## Root cause
- The simulator intentionally did not combine two drop streams, but did not carry the missing joint distribution into uncertainty.
- Trap category: type versus runtime model mismatch.

## Methodology (reusable)
1. Check acceptance windows and whether the first farm action could have credited the second item.
2. Distinguish compatible kill counters, one loot stream, and separate loot streams.
3. Keep the additive estimate but mark the latter uncertain and explain why.
4. Verify with two active quests sharing a camp.

## Fix
- Files changed: `QuestSharing/QuestOptimizer.lua`, `tests/test_quest_optimizer.py`.
- Commit / PR: local workspace, uncommitted.
- Workaround? no.

## Verification
- `test_two_active_drop_streams_keep_joint_probability_uncertain` passes both client API styles; optimizer 34/34 passes.

## If it shows up again
- Inspect `campWork` acceptance timing and `report.uncertain`; separate rates alone do not establish a joint rate or an exact overlap saving.

---
## Addendum 2026-11-17 — bounded two-stream estimate
- What happened: an uncertainty flag alone did not price the plausible overlap range requested by the optimizer plan.
- New approach + methodology: when exactly two accepted item streams share a camp, report a lower bound equal to the larger separate expectation and an upper bound equal to their sum; remove the pair bound if a third stream enters the camp.
- Result / new status: solved for the two-stream bound; full joint distributions still unavailable from marginal provider rates.
