# 2026-11-17 — Dungeon quests stays empty / "won't open" on first load

**Status**: solved (mechanism reproduced in harness; native load time unmeasured)
**Severity**: high
**Tags**: DungeonQuests.lua DataWork.lua "Reading dungeon quests" empty list stuck loading tab won't open BUDGET_MS foreground budget pause resume v0.4.20

## Symptom
- Observed (user, 2026-11-17): Dungeon quests tab "does not open nor work properly"; picked: empty/stuck loading, tab won't open at all, wrong/missing quests.
- Expected: list usable soon after opening; closing/tab switch must not throw progress away.
- Where: `D.scan` → `ns.dataWork.start`; `f.suspend` (OnHide).
- Environment: v0.4.20; real QuestieDB catalogues ~4,244 (Classic) to ~8,000 quests.

## Reproduction
- Instrument `coroutine.yield` in harness: 21 fixture quests → 386 yields = **18.4 yields/quest** (every Q.get checkpoints).
- Model: 4,244 quests ≈ 78k yields; DataWork gives 2 ms / 100 ms (or 80 steps without profiler) → ~40 s–2 min, 8,000 quests up to ~3.5 min, list empty until ready.
- Close/Esc/other tab mid-scan: `f.suspend` cancelled job and reset `loading/ready` → reopen restarts from 0 (looks like it never opens).

## Root cause
- Explicit-open, visible browser was scheduled with the background anti-lag budget (2% CPU), and hiding discarded its partial work.
- Trap category: scope/lifecycle (background policy applied to foreground work); resource/state discarded on hide.

## Methodology (reusable)
1. User terse "dungeon loot" turned out to mean Dungeon quests — confirm which tab first (see addendum in 2026-11-17-dungeon-loot-does-not-open.md).
2. Tests pass with tiny fixtures; note test helper needed `advance(90)` even for 21 quests — a timing smell.
3. Count yields per record, then extrapolate with DataWork's budget to real catalogue sizes; don't rely on fixture wall time.
4. Check what hide does to in-flight work: cancel vs pause.
5. Fix pattern: per-job optional foreground budget in the shared scheduler (background jobs keep 2 ms and their step caps; slice ≤ largest requested budget), plus pause-on-hide / resume-on-open; master disable and Refresh still cancel.

## Fix
- Files: `QuestSharing/DataWork.lua` (`W.start(..., budget)`, per-job slice check, deferred jobs keep order), `QuestSharing/DungeonQuests.lua` (`FOREGROUND_MS=8`, suspend → `dataWork.pause`, `D.open` resumes, `D.close` → `stop()` cancel).
- Tests: `tests/test_data_budget.py` foreground-budget test; `tests/test_dungeon_quests.py` pause/resume + foreground-slice tests, updated close expectation.
- Commit / PR: local, uncommitted. Workaround? No (decision logged in decisions.md 2026-11-17).

## Verification
- Failed first: dungeon 56/62, budget 17/18 (foreground/background equal 13/13).
- After: dungeon 62/62, budget 18/18; full 46 suites / 1,746 checks; Lua 5.1 syntax + `git diff --check` pass.
- Not verified: native load time with real QuestieDB (expected ~4x faster: ~10–55 s for 4k–8k quests, still not instant).

## If it shows up again
- Still slow: consider streaming direct dungeon quests before chain expansion (user's option 3), or yield per quest instead of per read.
- "Wrong/missing quests" was also reported — not addressed; needs a dungeon name + expected quest.
- Separate reproduced, unreported defect: `QUEST_LOG_UPDATE` handler calls `D.refresh()` → `ns.closeQuestMenu()`, so the right-click menu closes itself 0.2 s after any quest-log update.
