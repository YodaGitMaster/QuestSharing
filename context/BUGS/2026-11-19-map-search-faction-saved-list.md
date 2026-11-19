# 2026-11-19 — Map search empty outside the city (faction-filtered saved NPC list)

**Status**: solved in source (uncommitted); live cause unconfirmed
**Severity**: medium
**Tags**: VendorMap.lua mapSearchNPCs QuestSharingCache Work.saved faction friendlyToFaction npcFriendly Hillsbrad fish General Goods no results saved list account-wide

## Symptom
- Observed: user in Hillsbrad (Southshore, in front of the fish seller) types `fish`, `general good`: nothing. Search works in the city.
- Expected: Hal McAllister (Fish Merchant), Donald Rabonne (Fisherman), Sarah Raycroft (General Goods) pinned.
- Where: QuestSharing/VendorMap.lua `indexRoles`, QuestSharing/DataWork.lua `W.saved/W.save`.

## Reproduction
- Real Classic NPC data (`/private/tmp/qdbrepo/QuestieDB-master/data/Classic/classicNpcDB.lua`) in harness, map 1424, zone 267->1424: fresh scan finds 2 fish pins + suggestions on both styles -> matching/zone mapping fine.
- Same game: scan as Alliance (list saved, 1,686 IDs), `_release()`, switch to Horde: `general goods` -> 0 pins (Kayren Soothallow, H, missing). Reverse holds.

## Root cause
- `mapSearchNPCs` keeps only NPCs friendly to the scanning character's faction, but was saved under scope "" in account-wide `QuestSharingCache`. Another-faction character reuses it and never sees its own faction's NPCs.
- Trap category: stale cached value / scope (cache key missing a filter input).

## Methodology (reusable)
1. Load real QuestieDB data into the harness first; it separates data/mapping problems from code-path problems.
2. Harness has no `UnitFactionGroup`, so faction filters are silently off in tests: set it explicitly.
3. For any saved ID list: check every filter applied before saving is part of its scope key (faction, class, flavor).
4. Dead ends: zone map (267->1424 present in support/Zones and Forever), faction field values, matching words — all fine.

## Fix
- `indexRoles` reads/writes scope `playerFaction or "any"`. Old "" list is ignored.
- Test: `test_saved_npc_list_is_kept_per_faction` (fails before, passes after). Vendor suite 112/112.

## If it shows up again
- Ask for the status text under the search box and `/qs questie`. Try `/qs memory purge`.
- Check other `Work.save` callers for filters not in the scope key.
- Other open suspect for outdoors-only: DataWork contention with quest-plan/quest-improve (see 2026-11-17-map-search-missing-database.md audit addendum).
