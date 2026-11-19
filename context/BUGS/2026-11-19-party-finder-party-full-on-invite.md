# 2026-11-19 — Party finder: "Your party is full." while inviting

**Status**: solved in source (cause inferred, not reproduced in game; mock tests)
**Severity**: medium
**Tags**: LFGInvite.lua, ERR_GROUP_FULL, "Your party is full.", supercharge, SUPER_MAX, freeSpots, pending invites, PENDING, relisted duplicate

## Symptom
- Observed (user, in game): the invite worked and the healer joined, but chat showed "party is full".
- Expected: no error.
- Environment: Forever client; whether Supercharge was on is unknown (asked, not answered).

## Reproduction
- Mock only: Supercharge on, solo, 5+ matching healers -> 10 invites in one Find, while 1 member + 4 open invites already fill 5 spots.

## Root cause
- The game counts open invites as party spots; the addon's Supercharge deliberately ignored open invites and sent up to 10, so invites 5+ got ERR_GROUP_FULL.
- Trap category: type vs runtime mismatch (model of the server's capacity rule was wrong).

## Methodology (reusable)
1. List every source of the exact text (addon string vs game ERR_* string); the addon's own "the party is full" needs 5 counted, the user was 2 -> the game's error.
2. Find every path that sends invites and ask "can it exceed members + open invites?": supercharge cap, ask-first wait (deciding not counted in supercharge), duplicate names in one result pass, open invite freed at exactly the game's timeout.
3. Fix pattern: one capacity rule for every mode (members + open invites + players being asked), dedupe per pass, keep the hold a little longer than the game's timeout, translate the game error into a plain line.

## Fix
- Files changed: `QuestSharing/LFGInvite.lua` (freeSpots counts pending/deciding in all modes; supercharge cap = min(free spots, 10); `seen` dedupe; PENDING 60 -> 75; ERR_GROUP_FULL note), texts in `Settings.lua`, `LFGFinderUI.lua`, README, CHANGELOG; tests in `tests/test_lfg_invite.py` (+5).
- Workaround? no.

## Verification
- `tests/test_lfg_invite.py` 74/74; full suite green. Not checked in game.

## If it shows up again
- Ask whether Supercharge was on and get `/qs log` lines `lfg:` around it. If it appears in normal mode, check whether the game's invite timeout is longer than PENDING (75 s) on Forever.
