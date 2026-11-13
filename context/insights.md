# Insights

## 2026-11-13 — Learned spell ranks and action bars
- Verified modern spell-book entry/skill-line fields and pickup arguments against [Blizzard Forever spell-book declarations](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua); rank subtext comes from [spell API declarations](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua).
- [Myslot's action-bar import implementation](https://github.com/tg123/myslot/blob/master/Myslot.lua) confirms public GetActionInfo/PickupSpell/PlaceAction/ClearCursor workflow and legacy offSpecID=0. No third-party code/data bundled.
- Initial dedicated tests reproduced active-zero specialization rejection and unreadable-cursor mutation; corrected explicit zero handling and fallible cursor/combat guards before publication. Rank 10 must beat rank 2 numerically, and action spell IDs may refer to ranks hidden from the current book view.
- Verification: all 32 suites / 1,213 checks pass, including 48 spell-rank workflows. Tests cover combat beginning during pickup, occupied/unreadable cursor, wrong pickup/no-op/refused/partial placement, normal hidden/form pages, offspec/future/passive filtering, event coalescing and other addons changing target slots synchronously.
- No game client available; live native bar permissions and actual spell-book payloads remain in-game QA items, with refusal/unsupported behavior explicitly reported by the feature.

## 2026-11-13 — Current dungeon context
- Blizzard's [instance API declaration](https://github.com/Gethe/wow-ui-source/blob/classic/Interface/AddOns/Blizzard_APIDocumentationGenerated/InstanceDocumentation.lua) confirms instanceID is GetInstanceInfo's eighth return; optionalUI.call intentionally returns only three, so use protected direct invocation here.
- Actual compatible AtlasLoot catalogue has several Scarlet Monastery entries sharing ID 189 and Dire Maul entries with omitted/commented ID 429, area 2557 and SubAreaIDs; ID-only matching needs localized subarea disambiguation and a tie guard.
- Pending initial focus must survive asynchronous indexing but be canceled on manual navigation/close. Reopening recaptures current location; item-data refreshes do not recenter the browser.
- All 31 suites / 1,165 checks pass, including 24 current-instance/Extra tools workflows. An additional timing case showed dirty live-search fields must suppress focus before the debounce callback; reproduced and corrected before publication.
- Published v0.4.9 at `3cd7ddb9ebd5f3b8e8955b8a6fee919e0e235698`; downloaded 154,927-byte ZIP matches local source-verified build, SHA256 `82e65efb4ddbb59836315320c838eef78659ecf013b84ce507d3f237318774da`.

## 2026-11-13 — Native equipment stat filtering
- Blizzard's [generated item API declaration](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua) confirms C_Item.GetItemStats accepts an item link and may return no result. Older clients expose global GetItemStats; runtime detection/fallback is necessary.
- Three explicit AND conditions avoid hidden filter state and additional windows. Inclusive minimums use native units; missing/zero/malformed values cannot satisfy a positive bonus condition.
- Cache successful stat tables only; item info events clear cache before existing page refresh handlers. Unavailable data can recover without restarting or reindexing the catalogue.
- Existing mocks lack both stat APIs; dedicated fixtures exercise each API explicitly. Approximate widget render checked stat-row spacing; native game rendering remains unverified.
- Verification: all 30 suites / 1,141 checks pass, including 20 new stat checks across modern and legacy API paths.
- Published v0.4.8 at `50d41cad29bc5aa4119d964d91668bec4e75f89e`; downloaded ZIP byte-matches local source-verified build, SHA256 `3940b4a035ca9dceaf48ba9b95ffc066284e2f2081ea323543788decb5a02330`.

## 2026-11-13 — Equipment navigation redesign
- Most friction came from interaction design: cycling controls, Enter-only searches, page buttons and extra clicks for details. Direct/searchable dropdowns, live input and stable automatic selection address those paths.
- One unnamed popup is reused for all choices and stays open through background data refreshes; manual selection/tab change/close dismiss it. Filter reset cancels debounced callbacks so stale text cannot jump pages later.
- 30 usability workflow checks cover both API styles, including direct class/source choices, debounce, sorting/My level, wheel/arrow boundaries, cache-preserved selection, no-results recovery and hidden-tab search return.
- Native edit-box API verified against [Blizzard generated API documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleEditBoxAPIDocumentation.lua); optional SetAltArrowKeyMode(false) supports arrow navigation without capturing global keys.
- Caught and fixed delayed Apply callbacks resetting pagination after a scroll; the new workflow case failed on both API styles before cancelling both input serials at the common commit path. See `context/BUGS/2026-11-13-debounced-filter-reapply.md`.
- Final all-suite validation: 29 scripts / 1,121 checks passed; built/source-verified 30-file v0.4.7 ZIP.
- Published v0.4.7 at `13d718f`; downloaded 152,730-byte asset matches the tested ZIP (SHA256 `f8b13b1b34f17348296fe718f7e399c8dc2301ec8401f73ea28df78e46d779b9`).
- Mixed wheel/keyboard dropdown case also failed before correction; keep the Enter cursor inside the visible option slice. See `context/BUGS/2026-11-13-dropdown-offscreen-selection.md`.
- Reviewed approximate native-widget geometry previews under `/tmp/questsharing-equipment-{quests,dungeons}.png`; these are layout approximations, not game screenshots.

## 2026-11-13 — Minimum Rare equipment quality
- One shared predicate covers quests, dungeon results and source choices. Added confirmed native quality >=3 before type/slot/level filters; unknown quality is hidden until cache events supply it.
- New integration cases failed before the filter (26/36 shared-explorer checks passed), then 36/36 passed. Optional 42/42 and loot 58/58 also passed.
- Existing fixtures used quality 2 for all equipment; changed baseline gear to Rare and added explicit mixed-quality boundary cases rather than discarding existing feature coverage.
- Existing uncached quest test now expects hidden gear until native details arrive, then verifies its return.
- Final all-suite validation: 28 scripts / 1,091 checks passed. Built/source-verified v0.4.6 ZIP, 30 files.
- Published v0.4.6 at `401c950`; downloaded 148,480-byte asset matches the tested local ZIP (SHA256 `8efb93d2f4bdb21766d1ffd6c96eb59711bede03e363ff5c33c65d8c51d02dec`).

## 2026-11-13 — Unified equipment explorer
- User clarified that Forever dungeons must remain included; exclude raids/world bosses via actual dungeon identity, not merely a positive InstanceID or UIMapType.Dungeon.
- Verified AtlasLoot [content category API](https://github.com/HoliestWoW/AtlasLootClassic/blob/master/AtlasLootClassic/ItemDB/ItemDB.lua) and [Classic/Forever catalogue](https://github.com/HoliestWoW/AtlasLootClassic/blob/master/AtlasLootClassic_DungeonsAndRaids/data.lua).
- Actual provider smoke after classification: 30 dungeon entries / 1,655 raw source rows, zero Lua errors; item 5191 -> Edwin VanCleef / The Deadmines / Normal once native item details are available.
- Dire Maul wings have commented-out InstanceID in the compatible catalogue; accept their known area rather than losing them. Hall of Thanes map placeholder is explicitly unverified; do not add it to the Questie fallback area registry.
- EquipmentUI owns the only top-level gear window; quest/drop details are child panels. Shared session filters survive tabs; scan cancellation is explicit because the mock does not propagate OnHide automatically.
- Native numeric class/subclass metadata supports item types; fallback unset class/subclass zero cannot be treated as a known axe subclass.
- All 28 suites / 1,081 checks passed. New `tests/test_equipment.py`: 26 integration checks across classic/modern paths, including cross-link raid exclusion and unknown metadata.
- Approximate previews in `/tmp/questsharing-equipment-{quests,dungeons}.png` derive positions from actual mocked native widgets; they are not game-client screenshots. Real rendering remains unverified.
- Built source-verified v0.4.5 install ZIP: 30 files.
- Published stable v0.4.5 at `fdea252`; downloaded 148,397-byte asset matches local bytes (SHA256 `9c447ef0f5f30eb456992e698e1b63386608154d7ced95b8631fd6f3f70e802c`).

## 2026-11-13 — Invitation menu ordering
- Existing invitation action was row 3 after Offer it to the party; user requested it directly after Tell the party.
- Moved to row 2. Existing 60 menu and 32 adventure checks passed across modern/classic paths.
- Runtime change only reorders existing actions; no new frames, chat or state behavior.
- Published v0.4.4 at `0c1a512`; downloaded asset byte-matches source-verified 29-file ZIP (SHA256 `893ba47c0cc1b68c523a9fa3c140b716b6d66d3c168d4f01ac05d33b2715e92d`).

## 2026-11-13 — Equipment-only instance drops
- Provider filtering correctly found dungeon sources, but all positive item IDs reached results; both providers needed the same equipment predicate.
- Original loot fixture gave cloth a weapon slot and explicitly tested its inclusion; corrected realistic slots and expected scope.
- Common `Rewards.itemInfo().slot` is sufficient to classify weapons and wearable gear without adding API/provider dependencies; unknown details stay hidden until cache events.
- Failed-first regression suite then passed 58 loot cases; all 27 suites / 1,055 checks passed. Built and source-verified v0.4.3 ZIP (29 files).
- Published correction v0.4.3 at `72d7d35`; downloaded release ZIP matches tested local bytes (SHA256 `af209ddb41dc6ca695b1364b56c00c3dade5ef7281b385ae19010ccbec0f0cd1`).

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
