# 2026-11-19 — Space-bookmark key frame blocked in combat (SetPropagateKeyboardInput)

**Status**: solved (mock tests only, not checked in the real game)
**Severity**: high (1,600+ blocked-action errors per session, error notice spam)
**Tags**: ADDON_ACTION_BLOCKED, SetPropagateKeyboardInput, BagTools.lua:167, BagTools.lua:168, OnKeyDown, bagBookmarks, InCombatLockdown, protected function, combat lockdown

## Symptom
- Observed: `tried to call the protected function Frame:SetPropagateKeyboardInput() from BagTools.lua:168` (also :167 in an older build), "in combat: yes", on almost every key pressed in a fight. v0.4.26 Stormwind report: 1,605 of 1,634 occurrences.
- Expected: no errors; bookmarking with Space works out of combat only.
- Where: `QuestSharing/BagTools.lua` keyboard frame `keys` (OnKeyDown).
- Environment: interface 16001, `bagBookmarks=true` (default on).

## Reproduction
- Bookmarks on, start a fight, press any key.

## Root cause
- OnKeyDown called `self:SetPropagateKeyboardInput(not taken)` for every key. That call is protected under combat lockdown, so the game blocked it on each key.
- Trap category: scope / lifecycle (a protected API called in a context where it is forbidden); decisions.md 2026-11-18 had it as "not verified in game".

## Methodology (reusable)
1. Grouped the report by message: only 2 distinct bugs behind 30 entries; this one is ~98 % of the occurrences.
2. The stack ends in `[C] SetPropagateKeyboardInput` called from the OnKeyDown closure, "running: no timer or event of the addon" = a key press; "in combat: yes" in every entry.
3. The "last ran a timer set at ..." line (Fishing, ZoneLevels, Track...) is noise: it only names the previous addon activity.
4. Fix pattern: never call a protected setter in lockdown. Return early from OnKeyDown in combat, call the setter only when the value changes, and reset it to `true` on `PLAYER_REGEN_DISABLED` (fires just before lockdown) so all keys reach the game during the fight.

## Fix
- Files changed: `QuestSharing/BagTools.lua` (`propagate()` guard + PLAYER_REGEN_DISABLED reset), `tests/test_bagtools.py` (`test_the_key_frame_never_touches_keyboard_propagation_in_a_fight`).
- Commit / PR: uncommitted.
- Workaround? no. Space bookmarking does nothing in a fight (intended).

## Verification
- New test fails on the old code, passes on the new; test_bagtools 80/80; full suite 0 FAIL.

## If it shows up again
- Check whether the blocked call happens at `PLAYER_REGEN_DISABLED` (lockdown already active on this client?) → then also stop the keyboard frame on bag close instead.
- Any other `SetPropagateKeyboardInput` / `EnableKeyboard` caller (Settings.lua key capture) needs the same combat guard.
