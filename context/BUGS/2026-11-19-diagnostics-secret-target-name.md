# 2026-11-19 — Target logger compares a secret target name

**Status**: solved (mock tests only, `issecretvalue` behaviour not checked in the real game)
**Severity**: medium (29 errors per session, Lua error notices)
**Tags**: secret string value, attempt to compare local 't', while execution tainted by 'QuestSharing', Diagnostics.lua:323, PLAYER_TARGET_CHANGED, UnitName, issecretvalue, taint

## Symptom
- Observed: `Interface/AddOns/QuestSharing/Diagnostics.lua:323: attempt to compare local 't' (a secret string value, while execution tainted by 'QuestSharing')`, source PLAYER_TARGET_CHANGED (target nearest enemy, click-targeting, action button) in the v0.4.26 report.
- Expected: the debug log writes a target line, never an error.
- Where: `QuestSharing/Diagnostics.lua` PLAYER_TARGET_CHANGED handler.
- Environment: interface 16001, `debug=true`.

## Reproduction
- Debug log on, change target during combat.

## Root cause
- The client returns secret values for unit data (UnitName etc.) in some situations. Concatenating them works (the result stays secret), but comparing `t ~= lastTarget` raises in addon code.
- Trap category: type vs runtime mismatch (an API value that looks like a string but cannot be compared).

## Methodology (reusable)
1. Line 323 is the comparison, not the read: the concatenation on 321 succeeded, so secrets survive `..` but fail `~=`/`==`/boolean tests.
2. insights.md 2026-11-15 shows the same error class earlier in Friends.lua/Share.lua → any handler that compares/tests unit values can hit it.
3. Fix pattern: check `issecretvalue` (guarded, may not exist) on every unit value before comparing or testing it; replace with a placeholder; `pcall` around the block as a fallback. Keeps secret strings out of SavedVariables too.

## Fix
- Files changed: `QuestSharing/Diagnostics.lua`, `tests/test_log.py` (`test_a_target_name_the_game_keeps_secret_is_logged_as_hidden_without_an_error`).
- Commit / PR: uncommitted.
- Workaround? no.

## Verification
- New test fails on the old code, passes on the new; test_log 51/51; full suite 0 FAIL.
- Checked other PLAYER_TARGET_CHANGED handlers: ItemLevel.lua returns on InCombatLockdown before reading the name; Aggro.lua only schedules a refresh. No change needed.

## If it shows up again
- If the error moves to another line in the same handler, `UnitExists` itself may return a secret: test it with `secret()` too.
- Grep other `UnitName(` / `UnitIsFriend(` results that are compared, used as table keys, or tested in combat paths (Friends.lua, Share.lua, Quick.lua).
