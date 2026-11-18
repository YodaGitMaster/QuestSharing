# 2026-11-17 — Dungeon quests stays empty / "won't open" on first load

**Status**: solved in source (2026-11-17, run r-20261117-215940-e171: menu auto-close and quest-improve contention fixed, uncommitted/unreleased), except "wrong/missing quests", which is still blocked on a user example; native WoW validation pending. History: the budget/pause fix shipped in v0.4.21; the real "won't open" cause was EditBox:SetFont (fixed in f1b34e9).
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

---
## Addendum 2026-11-17 — audit: root cause misattributed, parts still open
- What happened: bug audit (BPMN run r-20261117-212533-cf04; checker + refuter agree on partially fixed). The 8 ms foreground budget + pause-on-hide fix is present since v0.4.21 and its tests pass (dungeon 64/64, budget 18/18).
- Why the previous fix did not hold for the user: in v0.4.20/v0.4.21 `build()` threw at the first `E.box` (EditBox:SetFont without flags) — all 64 dungeon tests fail on those sources under the strict harness — so the tab never finished building and no scan ran. Budget was real but secondary. Real fix: f1b34e9 (unreleased); see `2026-11-17-journal-black-page-editbox-setfont.md`.
- Still open: (1) "wrong/missing quests" never addressed (needs dungeon + expected quest); (2) `QUEST_LOG_UPDATE` → `D.refresh()` → `ns.closeQuestMenu()` closes the right-click menu 0.2 s after any quest-log update; (3) new contention: the planner's background `quest-improve` job (f1b34e9) slows the 8 ms scan to ~74-75 % and the background reward index to ~5-9 % of solo speed (real-clock probe) while the guide refines after movement.
- Result / new status: partially fixed; items 1-3 open.

---
## Addendum 2026-11-17 — menu and contention fixed in source (fix-all run)
- What happened: BPMN run r-20261117-215940-e171, streams C1 and A4 of `context/fix-plan-2026-11-17.md`. Stream C had a builder, a reviewer whose round 1 had a blocking issue, a fix and a round-2 approval.
- Item 2 (menu closes 0.2 s after QUEST_LOG_UPDATE), fixed. Changes in `QuestSharing/DungeonQuests.lua`:
  - `D.menu` records `menuEntry`/`menuQuest`, and the event handler calls `D.refresh(true)`. Called with no argument, `D.refresh` still closes the menu, as filters, search, My character and All quests expect. `D.go`, row.choose, `f.suspend` and `D.scan` still close it too.
  - With `keepMenu`, only our own open menu is considered (`menu.entry==menuEntry`). Menus from other windows (e.g. Panel, quest 100 in the probe) survive.
  - The menu closes when its quest leaves the results, or when its log membership changes (`(live==nil)~=(menuEntry.catalogue==true)`, i.e. abandoned or newly accepted).
  - Review round 1 found the blocking classic bug. On classic, menu actions act on `entry.index`, which shifts when quests are added or removed above it, so "Offer it to the party" pushed quest [200] instead of [2]. The fix copies `index/complete/title` from `C.findEntry` into the same `menuEntry` table, so the callbacks holding it act on the right quest.
  - Tests (`tests/test_dungeon_quests.py`): `test_quest_log_update_keeps_open_menu_until_its_quest_leaves_results`, `test_quest_log_update_leaves_menus_from_other_windows_alone`, `test_kept_menu_acts_on_its_own_quest_after_the_log_shifts`. Reviewer mutation checks: a HEAD-like `D.refresh` fails tests 1–2, and removing the in-place refresh fails test 3.
  - Known limits: the code reads the shared menu through `ns._questMenu()`, a test-only accessor in `Menu.lua` (guarded), and a proper accessor needs a `Menu.lua` change. A menu kept open keeps the item list it was built with.
- Item 3 (quest-improve contention), fixed in source by A4: `evaluate()` yields every 32 simulated actions, and quest-improve runs again only after real input changes or >= 0.1 map units of movement. Test `test_map_search_and_dungeon_scan_keep_half_their_pace_while_the_guide_replans` (`tests/test_data_budget.py`).
- Item 1 (wrong/missing quests, C2): not attempted, still blocked. Needs a dungeon, the missing or wrong quest, and faction/level.
- Result / new status: solved in source except C2 (uncommitted, unreleased). Native check pending: in game, open the Dungeon quests and Instance drops tabs, and check the quest menu stays open while you kill or loot.
