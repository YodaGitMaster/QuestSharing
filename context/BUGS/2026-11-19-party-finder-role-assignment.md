# 2026-11-19 — Party finder: wrong role choice for hybrids and other matching gaps

**Status**: solved (in source, mock tests; not checked in game)
**Severity**: medium
**Tags**: LFGInvite.lua, matches, roleWord, rolesFor, roleOpen, roleTaken, supercharge, hybrid, druid, activityID, GetSearchResultLeaderInfo, ipairs nil

## Symptom
- Found in an algorithm review: (1) a druid listed healer+damage was tagged "healer" (first wanted role) and skipped once the healer spot was full, though damage was open; (2) after the 2 s item-level wait only free spots were re-checked, not the role; (3) supercharge invited more healers although a healer had joined; (4) party members who joined outside our invites never counted toward any role; (5) results/listing with a single `activityID` matched nothing; (6) no fallback when `GetSearchResultPlayerInfo` is missing.

## Root cause
- Role chosen once at match time instead of at invite time against current needs; checks not repeated after an async wait; client API shape assumed (plural fields only).
- Trap category: stale value after async wait; type vs runtime mismatch (API shape); ipairs stopping at nil.

## Methodology (reusable)
1. Trace one result through every gate (activity -> solo -> player info -> role -> need -> item level -> invite) and ask "what if the player fits several branches?" and "what changed during each wait?".
2. Keep all eligible options on the candidate (`m.roles`) and decide at commit time against live state.
3. After any wait (timer/answer), re-run every precondition that can change, not just one.
4. Accept both old and new API shapes at boundaries (`activityIDs or { activityID }`, player info -> leader info).

## Fix
- Files changed: `QuestSharing/LFGInvite.lua`; tests in `tests/test_lfg_invite.py` (hybrid open role, scarcer role, supercharge vs members, pure-damage members, old API shape, role re-check after wait).

## Verification
- `tests/test_lfg_invite.py` 62/62; full suite green. The leader-info fallback test caught an `ipairs({nil, f})` bug in the first fix.

## If it shows up again
- Debug log `lfg:` lines show "invite NAME (role, ilvl)". If a hybrid comes as the wrong role, check `ROLE_ORDER` and `memberRoleOf` (UnitGroupRolesAssigned may be NONE on Classic).
