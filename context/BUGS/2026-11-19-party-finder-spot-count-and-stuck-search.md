# 2026-11-19 — Party finder: joined players counted twice, declines hold a spot, stuck search

**Status**: solved (in source, mock tests; not checked in game)
**Severity**: medium
**Tags**: LFGInvite.lua, freeSpots, pending invite, GROUP_ROSTER_UPDATE, ERR_DECLINE_GROUP_S, CHAT_MSG_SYSTEM, LFG_LIST_SEARCH_RESULTS_RECEIVED, searching flag, INSPECT_READY, ItemLevel.lua

## Symptom
- Found in a review pass (not reported in game): (1) after an invited player joined, `freeSpots()` counted them in the party AND as a pending invite for 60 s -> "party is full" one player early; (2) a declined invite held its spot 60 s; (3) if the game never sent search results, `searching` stayed true and every later Find was ignored until /reload; (4) inspect via mouseover lost the result if the mouse moved before INSPECT_READY.

## Root cause
- One table (`invited`) served two meanings (skip memory and spot holder); no completion path for refused invites; a busy flag with no timeout; a unit token captured at request time.
- Trap category: stale state / resource lifecycle (flag never reset), mutation of shared meaning.

## Methodology (reusable)
1. Walk each user story end to end (invite -> accept / decline / no answer; search -> answered / never answered) and ask what every state variable holds afterwards.
2. Split state by meaning; give every "busy" flag a timeout; resolve units by GUID at answer time.
3. Turn the game's `ERR_*_S` format strings into patterns (escape magic chars, then `%s` -> `(.+)`), with English fallbacks. Gotcha: match the literal `%s` with the pattern `"%%s"`, not `"%%%%s"`.

## Fix
- Files changed: `QuestSharing/LFGInvite.lua`, `QuestSharing/ItemLevel.lua`, `QuestSharing/LFGFinderUI.lua`, tests `test_lfg_invite.py`, `test_item_level.py`.

## Verification
- New tests: joined player no extra spot, decline frees spot + chat line, search timeout, picker blocker/last action, inspect after mouse moved.

## If it shows up again
- Non-English clients: check the `ERR_*` globals exist (fallbacks are English only). Debug log lines `lfg:`.
