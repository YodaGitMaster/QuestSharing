# State
Last updated: 2026-11-13

## Active task
- User requested Seek fellow adventurers directly after Tell the party in the quest right-click menu.
- Implemented in version 0.4.4; validated and ready to push/publish under the ongoing release authorization.

## Last completed
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
- v0.4.3: https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.3
- Tag `72d7d3528629ca2c24c518275440195be3b0a703`; ZIP 144,596 bytes with verified SHA256 above.
- Main also includes a documentation follow-up recording publication. Previous 0.4.2 tag and ZIP preserved.
