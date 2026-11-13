# State
Last updated: 2026-11-13

## Active task
- Completed equipment usability redesign for 0.4.7; final regression/package passed and publication verification pending.
- Existing ongoing push/release authorization applies; no additional feature work remains.

## Last completed
- Searchable direct dropdowns replace sequential cycling for filters/class/faction/source; one child popup supports search, wheel and keyboard confirmation.
- Live search/range/character inputs, Clear controls, My level, sorting, wheel/arrow list navigation, automatic/stable inline selection and helpful empty/loading states.
- Clear filters recovers from combined searches/location/source and broadens quest levels without losing character context or Rare+.
- Brighter readable rarity hues/strips, persistent selection, difficulty labels and accurately named Map directions action; game-wide keys are not captured.
- All 29 suites / 1,121 checks passed, including 30 usability workflows; diff whitespace clean.
- Built source-verified 30-file `dist/QuestSharing-0.4.7.zip`; SHA256 `f8b13b1b34f17348296fe718f7e399c8dc2301ec8401f73ea28df78e46d779b9`.
- Caught/reproduced/fixed two unreleased navigation defects (delayed Apply reset and offscreen dropdown focus); reusable reports in context/BUGS.
- Reviewed approximate native-widget geometry; actual game rendering remains unverified.

## Implemented tools
- Optional tab in `/qs settings`; fishing layer and quest reward browser default off.
- `/qs fishing`: persistent per-water editor; `/qs fishing on`: world-map layer, with Alt-click placement where supported. Water notes survive settings reset and are deleted explicitly.
- `/qs rewards`: shared explorer quest tab; equipment rewards by class/level/faction, slot/search filters, native comparisons and quest routes; requires recent QuestieDB and enum tables.
- `/qs adventure [quest ID or title]`: editable role-play invitation for chosen chat; Prepare fills a draft, Enter sends.
- `/qs loot [search]`: shared explorer dungeon tab; Classic/Forever dungeon equipment, encounter filter, item/name/ID/boss search, supplier/difficulty and native comparisons.
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
- v0.4.6: https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.6
- Tag `401c9508c14088f9464dd6c06033e8e23fe04a3c`; ZIP 148,480 bytes; SHA256 `8efb93d2f4bdb21766d1ffd6c96eb59711bede03e363ff5c33c65d8c51d02dec`.
- Main also includes a documentation follow-up recording publication. Previous release tags and ZIPs preserved.
