# State
Last updated: 2026-11-13

## Active task
- Current-dungeon focus and Extra tools label completed and published as v0.4.9; remote tag and downloaded install ZIP verified.
- No remaining feature work; native game-client QA remains unavailable in this environment.

## Last completed
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
- `/qs fishing`: persistent per-water editor; `/qs fishing on`: world-map layer, with Alt-click placement where supported. Water notes survive settings reset and are deleted explicitly.
- `/qs rewards`: shared explorer quest tab; equipment rewards by class/level/faction, slot/search filters, native comparisons and quest routes; requires recent QuestieDB and enum tables.
- `/qs adventure [quest ID or title]`: editable role-play invitation for chosen chat; Prepare fills a draft, Enter sends.
- `/qs loot [search]`: shared explorer dungeon tab; Classic/Forever dungeon equipment, encounter filter, item/name/ID/boss search, supplier/difficulty and native comparisons; opening automatically focuses the recognized current dungeon.
- Quest objective/turn-in symbols removed from both maps; old saved `questMap` setting discarded.

## Remaining limits
- No game client available: GUI rendering, installed-module loading, chat routing, Alt-click placement and live item-cache timing need in-game checks.
- Complete instance loot requires a compatible installed AtlasLoot DungeonsAndRaids catalogue; QuestieDB is a labelled partial fallback. No third-party dataset bundled.
- Fishing water fish/skills are user-entered; optional AnglerAtlas supplies separate zone summaries, with provisional Forever data labelled.
- Reward class equipment families follow Classic rules; native tooltips remain authoritative for item restrictions and build suitability. Not every quest condition is evaluated.

## Verification environment
- `/tmp/questsharing-test-env/bin/python`: lupa 2.8 / Lua 5.1. Host Python lacks lupa.
- Actual AtlasLoot source smoke test from v0.4.2: 34 instances / 2,635 raw item-source entries; `/tmp/questsharing-loot-reference`.
- AnglerAtlas reference `/tmp/questsharing-angler-reference`; no reference data bundled.
- Never open/redraw Blizzard's protected world map from addon code; print directions instead.

## Published release
- v0.4.9: https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.9
- Tag `3cd7ddb9ebd5f3b8e8955b8a6fee919e0e235698`; ZIP 154,927 bytes; SHA256 `82e65efb4ddbb59836315320c838eef78659ecf013b84ce507d3f237318774da`.
- Main also includes a documentation follow-up recording publication. Previous release tags and ZIPs preserved.
