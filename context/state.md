# State
Last updated: 2026-11-13

## Active task
- Implemented user's request to exclude green quality and lower from both equipment tabs; version 0.4.6.
- Final validation and package passed; push/publication verification pending under ongoing release authorization.

## Last completed
- All 28 suites / 1,091 checks passed; source-verified 30-file ZIP `dist/QuestSharing-0.4.6.zip`, SHA256 `8efb93d2f4bdb21766d1ffd6c96eb59711bede03e363ff5c33c65d8c51d02dec`.
- EquipmentUI.matches now requires confirmed native quality >=3 (Rare/blue), covering quest rewards, dungeon results and source choices; Reset filters preserves the minimum.
- Unknown-quality equipment stays hidden until native item-cache events refresh it. Header and README explain the rule.
- Added five integration cases across both API styles; failing-before verification then 36/36 shared-explorer cases passed. Optional 42/42 and loot 58/58 passed.
- Baseline fixture gear is now Rare; explicit low-quality cases verify grey/white/green exclusion. No provider, window, eligibility or SavedVariables changes.

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
- v0.4.5: https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.5
- Tag `fdea2529e34811b6dc8b13125fb5b66c14d5ac37`; ZIP 148,397 bytes; SHA256 `9c447ef0f5f30eb456992e698e1b63386608154d7ced95b8631fd6f3f70e802c`.
- Main also includes a documentation follow-up recording publication. Previous release tags and ZIPs preserved.
