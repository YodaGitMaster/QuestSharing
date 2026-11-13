# 2026-11-13 — Instance loot included non-equipment

**Status**: solved
**Severity**: medium
**Tags**: Loot.lua Rewards.lua Silken Cloth instance loot weapons armor equipment slots GET_ITEM_INFO_RECEIVED

## Symptom
- Observed: instance search listed everything, including Silken Cloth and other materials.
- Expected: only dropped weapons and wearable equipment; retain suppliers and instance search.
- Where: `QuestSharing/Loot.lua` search and encounter choices; version 0.4.2.
- Environment: both modern and classic API mocks reproduce the issue.

## Reproduction
- Load the loot test fixture and run `/qs loot`; item 10004 (Silken Cloth) appears under Trash.
- Search Silken Cloth directly: the material still appears.

## Root cause
- The index accepted every positive item ID from a valid drop source and search checked only text/instance/encounter. No equipment eligibility predicate existed.
- Previous tests explicitly included non-equipment and the fixture incorrectly assigned a weapon slot to cloth; corrected both to reflect the user's clarified scope.
- Trap category: type vs runtime mismatch; incomplete domain filtering.

## Methodology (reusable)
1. Read the existing provider contracts and reproduce through the real Lua module before changing runtime code.
2. Verify the unwanted item has a valid dungeon drop source; provider selection and source parsing are working, so filtering belongs in the common result path.
3. Give fixtures realistic equipment slots and assert failures for materials, bags, unknown items and both providers before implementing the fix.
4. Reuse `Rewards.itemInfo().slot` as the common recognized equipment classification; avoid localized type names, guessed item names or separate provider rules.
5. Hide unknown classifications until item data arrives; test cache events and reopening so asynchronous data cannot leak unfiltered candidates or permanently hide loaded gear.
6. Test all supported equipment slots and preserve genuine equipment from Trash/chest groups. Encounter choices use the same eligibility condition.

## Fix
- Runtime: `QuestSharing/Loot.lua`; manifest version 0.4.3.
- Supporting changes: `tests/test_loot.py`, README, changelog and continuity notes.
- Commit / PR: recorded in git history under the 0.4.3 correction.
- Workaround? no.

## Verification
- Before fix: Silken Cloth visible on modern/classic paths; new equipment-only assertions failed (38/58 loot checks passed).
- After fix: 58/58 loot checks and all 27 suites / 1,055 checks passed.
- Verified 0.4.3 install ZIP: 29 files match addon source, retired quest renderer absent.
- Game-client rendering remains unverified; no client available.

## If it shows up again
- Inspect `Rewards.itemInfo().slot` for the unwanted item and ensure both search and encounter paths require it.
- Check for an unsupported new equipment slot before expanding the slot map; do not admit unknown items as a fallback.
- Retest uncached gear and non-gear through GET_ITEM_INFO_RECEIVED and browser reopening.
