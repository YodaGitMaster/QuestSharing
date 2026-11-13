# State
Last updated: 2026-11-13

## Active task
- User requested Seek fellow adventurers directly after Tell the party in the quest right-click menu.
- Completed in version 0.4.4; pushed main/tag and published the stable release with verified install ZIP.

## Last completed
- Published v0.4.4 at `0c1a51246fbe943e099a9a55ab8a41e2e1738454`; downloaded asset matches source-verified local ZIP (29 addon files).
- Confirmed existing action was row 3, then moved it to row 2 (before Offer it to the party).
- Updated existing menu-order expectation and user documentation. Selecting the action still opens that quest's invitation composer.
- Targeted verification: 60/60 menu and 32/32 adventure checks passed on modern/classic paths; diff whitespace clean.
- Previous full baseline (v0.4.3): all 27 suites / 1,055 checks passed.
- v0.4.3 equipment-only loot filter remains in place; no changes to it in this work block.

## Implemented tools
- Optional tab in `/qs settings`; fishing layer and quest reward browser default off.
- `/qs fishing`: persistent per-water editor; `/qs fishing on`: world-map layer, with Alt-click placement where supported. Water notes survive settings reset and are deleted explicitly.
- `/qs rewards`: equipment rewards by class/level/faction, slot/search filters, native comparisons and quest routes; requires recent QuestieDB and enum tables.
- `/qs adventure [quest ID or title]`: editable role-play invitation for chosen chat; Prepare fills a draft, Enter sends.
- `/qs loot [search]`: instance equipment, encounter filter, item/name/ID/boss search, supplier/difficulty and native comparisons.
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
- v0.4.4: https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.4
- Tag `0c1a51246fbe943e099a9a55ab8a41e2e1738454`; ZIP 144,598 bytes; SHA256 `893ba47c0cc1b68c523a9fa3c140b716b6d66d3c168d4f01ac05d33b2715e92d`.
- Main also includes a documentation follow-up recording publication. Previous release tags and ZIPs preserved.
