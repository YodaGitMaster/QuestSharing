# 2026-11-17 — Planner predictive work timing

**Status**: solved
**Severity**: medium
**Tags**: QuestPlanner.lua QuestOptimizer.lua green quest roadside shared kills future quests drops prerequisites

## Symptom
- Observed: a green quest beside the current route is left for later without a cost explanation.
- Expected: compare doing work now with accepting or unlocking compatible future work first, and explain an actual cost difference.
- Environment: zone-local planner, Questie/QuestieDB, native game unavailable.

## Reproduction
- Start at a camp with an active 10-kill quest.
- A local hub offers a missing 5-item/25% quest at the same camp and a prerequisite unlocking another 8-kill quest there.
- Prior runtime groups outings by distance and prerequisite depth. It does not price shared farming and cannot explain its timing by a work-time comparison.
- New public-entry fixture reproduces this through real provider records, live objectives and the guide.

## Root cause
- The route model scores geographical outings without a simulated accepted set or probabilistic incremental work.
- Trap category: data-model mismatch and incomplete cost model.

## Methodology (reusable)
1. Distinguish omission from postponement, then inspect the actual cost terms.
2. Reproduce with exact source IDs, acceptance gates and an independently calculated overlap expectation.
3. Schedule per-quest atomic actions before display grouping, so a merged nearby camp cannot invent prerequisites or credit.
4. Compare schedules over the same quest coverage, preserving pickup/work/hand-in gates and log slots.
5. Test the opposite decision with a known unavailable pickup, plus sequential follow-ups and incompatible branches.

## Fix
- Files changed: QuestSharing/QuestOptimizer.lua, QuestSharing/QuestPlanner.lua, QuestSharing/Questie.lua, TOC, focused tests and documentation.
- Local work, uncommitted and unpublished.
- Workaround? No.

## Verification
- Eight-quest simulation completes all 8 quests with 20.09471893 expected kills versus 30.01849365 nearest-ready.
- Same-work forecast 420.94718933 seconds versus 520.18493652 seconds.
- Public provider-to-guide overlap, active-parent constraints, expiry, capacity, four modes, movement/cache reuse and close cancellation verified in Lua 5.1 on both API styles.
- An unavailable pickup makes immediate work win. A follow-up requiring a hand-in receives no retroactive kill credit.
- Native Forever timing/data/UI validation remains pending.

## If it shows up again
- Check selected goal and optional color range, active pickup gates, exact local source identity, count/rate provenance, report exclusions and the actual cost comparison.
- Missing quantity or rate remains estimated, which can change the recommended order.
