# State
Last updated: 2026-11-13

## Active task
- Zone questing ranges corrected to opt-in/off by default and published as v0.4.12; remote tag and downloaded install ZIP verified.
- Standing preference: Extra tools additions stay optional and default off unless explicitly requested otherwise.

## Last completed
- 2026-11-13: user-requested push verified on main; origin already contained all feature/release changes, with no pending runtime edits.
- Published v0.4.12 at `c86b34294ced23ddf904ac73f50e0fce01baae73`; downloaded 32-file ZIP byte-matches source-verified build.
- Changed zoneLevels default to false and added once-only opt-in migration; later choices persist and Reset returns to off. Renderer unchanged.
- All 33 suites / 1,247 checks pass, including 34 zone-level workflows; diff whitespace clean.
- Published v0.4.11 at `f18d8258a33bee3270967c6afdaaf57c258a31ef`; downloaded 32-file ZIP byte-matches source-verified build.
- Added zoneLevels=true, Extra tools toggle, native continent zone badges and selected/hovered outdoor-zone panel; click-through own frames only, unknown data labelled, existing quest/minimap overlays remain retired.
- Zone data comes from client C_Map APIs including supported Forever zones; no bundled speculative ranges or Questie dependency. Settings layout still fits.
- All 33 suites / 1,243 checks pass, including 30 map-level workflows; diff whitespace clean. Native game map rendering/coverage still needs in-game QA.
- Published v0.4.10 at `6e16bc4b6252dfc7e27399a781525e9201f3b729`; downloaded 31-file ZIP byte-matches source-verified build.
- Added autoSpellRanks=false, Extra tools toggle/check-now, modern/legacy learned-rank enumeration and verified cursor swaps across normal bar pages; combat/cursor/temporary-bar deferral and client-refusal pause.
- Reproduced and corrected active-zero offSpecID and unreadable-cursor cases before publication; reusable reports in context/BUGS. Optional settings layout still fits.
- All 32 suites / 1,213 checks pass, including 48 spell-rank workflows; diff whitespace clean. Additional native-slot range and synchronous pickup ownership checks cover form pages and other addons changing slots.
- Rechecked push/release on user request: origin/main matches local publication documentation, v0.4.9 is the latest stable published release and its uploaded ZIP digest matches the verified build; no new runtime changes require another release.
- Published v0.4.9 at `3cd7ddb9ebd5f3b8e8955b8a6fee919e0e235698`; downloaded 30-file ZIP byte-matches source-verified build.
- Current dungeon automatically selected/revealed on open; waits for catalogue, respects manual browsing, resolves provider subzones and preserves shared gear filters.
- Settings label changed to Extra tools; tab widths rebalanced within existing window, internal id `optional` retained.
- All 31 suites / 1,165 checks pass, including 24 current-dungeon/label workflows; diff whitespace clean. Reproduced/corrected initial-focus versus pending-search race before release.
- Published v0.4.8 at `50d41cad29bc5aa4119d964d91668bec4e75f89e`; downloaded 30-file ZIP matches the tested source-verified build byte for byte.
- Implemented three shared AND stat conditions, searchable selectors/live inclusive minimums, clear/reset, lazy native API compatibility and event-invalidated cache; Rare+/eligibility/dungeon scope retained.
- Updated live architecture/schema/decisions and checked approximate widget geometry; no native client available.
- All 30 suites / 1,141 checks pass, including 20 new stat workflows; diff whitespace clean.
- Published v0.4.7 at `13d718f8212f084b7748c8f311d8ea5a2113664d`; downloaded asset matches the tested local ZIP byte for byte.
- Searchable direct dropdowns replace sequential cycling for filters/class/faction/source; one child popup supports search, wheel and keyboard confirmation.
- Live search/range/character inputs, Clear controls, My level, sorting, wheel/arrow list navigation, automatic/stable inline selection and helpful empty/loading states.
- Clear filters recovers from combined searches/location/source and broadens quest levels without losing character context or Rare+.
- Brighter readable rarity hues/strips, persistent selection, difficulty labels and accurately named Map directions action; game-wide keys are not captured.
- All 29 suites / 1,121 checks passed, including 30 usability workflows; diff whitespace clean.
- Built source-verified 30-file `dist/QuestSharing-0.4.7.zip`; SHA256 `f8b13b1b34f17348296fe718f7e399c8dc2301ec8401f73ea28df78e46d779b9`.
- Caught/reproduced/fixed two unreleased navigation defects (delayed Apply reset and offscreen dropdown focus); reusable reports in context/BUGS.
- Reviewed approximate native-widget geometry; actual game rendering remains unverified.

## Implemented tools
- Extra tools tab in `/qs settings`; fishing layer and quest reward browser default off.
- World-map questing ranges: default off; enable via Extra tools toggle for native continent badges and selected/hovered-zone panel. World/cosmic overview prompts choosing a continent/zone; missing client data is unknown.
- Extra tools > Auto-update spells to highest learned rank: default off; upgrades existing player spell buttons across normal/hidden/form pages on enable/login/learning/action changes; Check spell ranks now reports results. Waits during combat/temporary bars/dragging; macros/pet/items remain; refusal pauses until reload.
- `/qs fishing`: persistent per-water editor; `/qs fishing on`: world-map layer, with Alt-click placement where supported. Water notes survive settings reset and are deleted explicitly.
- `/qs rewards`: shared explorer quest tab; equipment rewards by class/level/faction, slot/search filters, native comparisons and quest routes; requires recent QuestieDB and enum tables.
- `/qs adventure [quest ID or title]`: editable role-play invitation for chosen chat; Prepare fills a draft, Enter sends.
- `/qs loot [search]`: shared explorer dungeon tab; Classic/Forever dungeon equipment, encounter filter, item/name/ID/boss search, supplier/difficulty and native comparisons; opening automatically focuses the recognized current dungeon.
- Quest objective/turn-in symbols removed from both maps; old saved `questMap` setting discarded.

## Remaining limits
- No game client available: GUI rendering, installed-module loading, chat routing, Alt-click placement, live item-cache timing, native spell-rank/action-bar permissions and zone-level map/data coverage need in-game checks.
- Complete instance loot requires a compatible installed AtlasLoot DungeonsAndRaids catalogue; QuestieDB is a labelled partial fallback. No third-party dataset bundled.
- Fishing water fish/skills are user-entered; optional AnglerAtlas supplies separate zone summaries, with provisional Forever data labelled.
- Reward class equipment families follow Classic rules; native tooltips remain authoritative for item restrictions and build suitability. Not every quest condition is evaluated.

## Verification environment
- `/tmp/questsharing-test-env/bin/python`: lupa 2.8 / Lua 5.1. Host Python lacks lupa.
- Actual AtlasLoot source smoke test from v0.4.2: 34 instances / 2,635 raw item-source entries; `/tmp/questsharing-loot-reference`.
- AnglerAtlas reference `/tmp/questsharing-angler-reference`; no reference data bundled.
- Never open/redraw Blizzard's protected world map from addon code; print directions instead.

## Published release
- v0.4.12: https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.12
- Tag `c86b34294ced23ddf904ac73f50e0fce01baae73`; ZIP 160,979 bytes; SHA256 `0378057a6fd6fef839d3743de0382a72096c61d74b84be0e6d25327e161c4cd0`.
- Main also includes a documentation follow-up recording publication. Previous release tags and ZIPs preserved.
