# State
Last updated: 2026-11-13

## Active task
- Implemented 0.4.5 shared equipment explorer, item type/slot/level range filters and dungeon-only scope.
- User clarified: include Forever dungeons as well as Classic; exclude raids and world bosses.
- Completed push and stable v0.4.5 release; remote tag and downloaded install ZIP verified, no release work remains.

## Last completed
- Published v0.4.5 at `fdea2529e34811b6dc8b13125fb5b66c14d5ac37`; remote asset matches the source-verified package byte for byte.
- Added EquipmentUI.lua: one host, two child pages, icons/quality colors, selected rows and inline route/source details. Shared filters use numeric metadata and inclusive Required level / Item level bounds.
- Updated Rewards/Loot to use shared pages and cancel pending work on close/tab changes. Existing character eligibility and native comparisons preserved.
- Actual compatible AtlasLoot source smoke: 30 Classic/Forever dungeon entries / 1,655 raw source rows, zero Lua errors; Cruel Barb verified against Edwin VanCleef after native item details supplied.
- Final validation: all 28 suites / 1,081 checks passed, including 26 shared-explorer, 42 optional and 58 loot cases; diff whitespace clean.
- Built `dist/QuestSharing-0.4.5.zip`: 30 source-matching addon files; SHA256 `9c447ef0f5f30eb456992e698e1b63386608154d7ced95b8631fd6f3f70e802c`.
- Inspected approximate layout previews derived from actual mocked frame geometry; real game rendering remains unavailable.

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
