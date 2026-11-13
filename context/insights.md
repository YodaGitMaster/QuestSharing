# Insights

## 2026-11-13 — Equipment-only instance drops
- Provider filtering correctly found dungeon sources, but all positive item IDs reached results; both providers needed the same equipment predicate.
- Original loot fixture gave cloth a weapon slot and explicitly tested its inclusion; corrected realistic slots and expected scope.
- Common `Rewards.itemInfo().slot` is sufficient to classify weapons and wearable gear without adding API/provider dependencies; unknown details stay hidden until cache events.
- Failed-first regression suite then passed 58 loot cases; all 27 suites / 1,055 checks passed. Built and source-verified v0.4.3 ZIP (29 files).

## 2026-11-13 — Release 0.4.2 published
- Re-ran all 27 suites: 1,043 checks passed; rebuilt and verified 29 addon files.
- Pushed main and annotated v0.4.2 tag at `5dbb839`; published stable release with ZIP and all changes since v0.3.9.
- GitHub asset digest and downloaded bytes match local ZIP: SHA256 `f1839bca6f8d0c0cc15239c7a9e090fbd69be72424664341b61776700ef0abfb`.
- Release: https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.2

## 2026-11-13 — Instance drop browser
- All 27 suites passed: 1,043 checks, including 46 instance-loot cases; final local install package is `dist/QuestSharing-0.4.2.zip`.
- Verified AtlasLoot contracts in [ItemDB.lua](https://github.com/HoliestWoW/AtlasLootClassic/blob/master/AtlasLootClassic/ItemDB/ItemDB.lua) and [encounter data](https://github.com/HoliestWoW/AtlasLootClassic/blob/master/AtlasLootClassic_DungeonsAndRaids/data.lua).
- Actual Forever-compatible ItemDB.lua + data.lua smoke-loaded into the Lua harness: 34 instance records and 2,635 distinct item/source/difficulty entries; item 5191 correctly resolves to Edwin VanCleef in The Deadmines. No Lua errors in that run.
- Reference files and smoke runner are under `/tmp/questsharing-loot-reference`; no third-party code/data is copied into the addon package.
- AtlasLoot item rows use column 2 for item ID; ExtraList also marks real Trash tables, so only IgnoreAsSource and non-Item format tables should be excluded.
- Questie dungeon sources can use either {-1,-1} sentinel spawns or normal coordinates on a Dungeon map; both need support.
- Harness frame Hide() does not fire OnHide automatically; cancellation tests explicitly invoke the hook to simulate the game's lifecycle.

## 2026-11-13 — Invitations and quest-overlay removal
- Role-play composer implemented in `Adventure.lua`; 32 integration checks cover wording, UTF-8 limits, channel routes, preview, preserved drafts and stale quest rejection.
- User interrupted final packaging to request removal of quest map/minimap symbols. Deleted `QuestMap.lua`, its TOC entry and all runtime/UI hooks; old saved `questMap` flag is cleared on load.
- Kept the five how-to chat cases in `test_questmap.py`; replaced retired rendering expectations with removal guards. Final suite: 26 scripts / 997 checks, all passed.
- Version 0.4.1 combines invitation work and map-symbol removal; only local packaging, no remote publication.

## 2026-11-13
- Existing settings had six tabs and no Optional category; now seven tabs fit within the 660px window.
- Confirmed QuestieDB API/schema: [API](https://github.com/Questie/QuestieDB/blob/master/docs/api.md), [item fields](https://github.com/Questie/QuestieDB/blob/master/src/meta/itemMeta.lua), [quest fields](https://github.com/Questie/QuestieDB/blob/master/src/meta/questMeta.lua).
- Numeric QuestieDB getters use zero for unset values. `GetAllIds()` is shared/read-only. Item reward links live in `Item.questRewards`.
- Forever race masks include bits 32/33; 32-bit `bit.band` would truncate valid races. Provider enums carry active-flavor mappings.
- AnglerAtlas Forever 0.1.9 source inspected from its [release](https://www.curseforge.com/wow/addons/angler-atlas/files/9455093); live adapter smoke-loaded its actual Data.lua in the Lua harness (Elwynn: minimum 1, two fish). Reference files only in `/tmp/questsharing-angler-reference`, not vendored.
- AnglerAtlas source warns that new Forever zone skill, catches and map placeholders are unverified. Zone summaries cannot establish a per-water catalogue.
- Protected map-opening guard existed before this task; preserve it rather than weakening its test. Game map must be opened by the user.
- Test runtime installed in isolated `/tmp/questsharing-test-env` (`lupa` 2.8, Lua 5.1), because host Python had no lupa.

## 2026-11-12
- The user supplied the original Global Working Protocol, including the Continuity System; earlier searches had not located that original text.
- Cursor's local `aicontext.personalContext` field was empty when checked; project rules existed in Desktop/CursorRules.
- User explicitly wants continuity used all the time and supplied rules applied when needed.

## 2026-11-11
- Local tracking refs alone are insufficient evidence of a published GitHub Release; query the release list.
- `python` was absent; `python3 build_release.py` successfully built the 0.3.9 asset (25 addon files).
