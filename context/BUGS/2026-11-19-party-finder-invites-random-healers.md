# 2026-11-19 — Party finder invites random healers

**Status**: solved (in source, mock tests; not checked in game)
**Severity**: medium
**Tags**: LFGInvite.lua, party finder, C_LFGList, auto-invite, activityIDs, HasActiveEntryInfo, GetActiveEntryInfo, random healers, listing

## Symptom
- Observed: the spyglass invited any solo healer in the results, for any dungeon, even with no group listing.
- Expected: invite only while my group is listed with an activity, and only healers listed for that activity.
- Where: `QuestSharing/LFGInvite.lua` (`searchArgs`, `L.matches`, `L.scan`).

## Reproduction
- Not listed (or listed for The Deadmines), click the spyglass: a healer listed for Wailing Caverns got invited.

## Root cause
- The search used the Blizzard window's category (or Dungeons) and never read my listing; matching checked role only, not the result's `activityIDs`.
- Trap category: missing precondition / type vs runtime (search filter assumed to be exact).

## Methodology (reusable)
1. Read Blizzard classic_era `LFGListInfoDocumentation.lua`: `HasActiveEntryInfo`, `GetActiveEntryInfo().activityIDs`, `GetActivityInfoTable(id).categoryID`, `LfgSearchResultData.activityIDs`, event `LFG_LIST_ACTIVE_ENTRY_UPDATE`.
2. Read `Blizzard_LFGVanilla_Browse.lua`: `SearchActiveEntry` searches the listing's activities, and the list still checks each result (`matchesFilters`), so the server filter is not exact -> filter client-side too.
3. Fix pattern: gate on own listing; search like SearchActiveEntry; require a shared activity per result.

## Fix
- Files changed: `QuestSharing/LFGInvite.lua` (+ picker `LFGFinderUI.lua`, `MinimapButton.lua`, `Settings.lua` texts), `tests/test_lfg_invite.py`.
- Workaround? no.

## Verification
- `tests/test_lfg_invite.py`: not listed -> no search/invite; other dungeon's healer skipped; listing switched -> that dungeon's healer invited; search args = listing's activities.

## If it shows up again
- `/qs lfg` with debug log: check "search category N for <name>" lines; check solo results really carry `activityIDs` on Forever (if empty, nobody is invited -> fall back to category match).
