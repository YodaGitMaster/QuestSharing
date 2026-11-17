# 2026-11-17 — Guidance retained missing map measurements

**Status**: solved in source; native rendering pending
**Severity**: medium
**Tags**: QuestGuidance.lua targetWorld mapSize Distance-unavailable cache retry

## Symptom
- Observed in follow-up tests: if map measurements are absent on first open, the arrow stays unavailable after the APIs become ready.
- Expected: recover without closing the guide or changing steps; retain low background cost.
- Environment: actual Lua 5.1 modules, modern/classic native API mocks.

## Reproduction
- Open guide with GetWorldPosFromMapPos returning nil and no GetMapWorldSize. Enable valid world projection while keeping the same selected step; subsequent updates previously remained “Distance unavailable”.

## Root cause
- Missing target measurements were cached until selection changed; live player measurement retries could never repair the absent target.
- Trap category: stale cache / lifecycle.

## Methodology (reusable)
1. Vary resource availability after initial render; a permanently unavailable fixture misses this failure.
2. Distinguish selected target cache from freshly read player position.
3. Retry only missing required measurements using the existing active HUD loop, with a one-second throttle and no new timer/database reads.
4. Count retries relative to a completed open: the harness now executes visible frames' OnUpdate during Game.advance, so startup already includes legitimate retry time.

## Fix
- Files: QuestSharing/QuestGuidance.lua; tests/test_quest_guidance.py.
- refreshMetrics reuses successes; metricWait throttles retries and clears with the guide. Known fallback metrics avoid needless projection reads.
- Commit / PR: local/unpublished. Workaround: no.

## Verification
- Recovery and throttling/close checks pass on both API styles; guidance 40/40, full 43 suites / 1,583 checks, budget 17/17, Lua 5.1 syntax/diff pass.
- Native API timing and FPS remain unmeasured.

## If it shows up again
- Compare target/player availability and metricWait before changing cache policy; ensure closed frames have no OnUpdate or retry timer.
