# State
Last updated: 2026-11-13

## Active task
- User clarified instance drop search should show equipment only; corrected in version 0.4.3, validated and packaged.
- Completed push and stable v0.4.3 publication; remote tag and downloaded ZIP verified, no release work remains.

## Last completed
- Published v0.4.3 at `72d7d3528629ca2c24c518275440195be3b0a703`; downloaded GitHub ZIP matches the verified local package byte for byte.
- Reproduced Silken Cloth leakage on modern/classic paths; corrected unrealistic fixture slots and added failing-first tests.
- `Loot.lua` now requires recognized `Rewards.itemInfo().slot` for results and encounter choices. Weapons and wearable gear remain; materials, consumables, bags and unknown classifications stay hidden.
- Existing asynchronous item-cache events reveal equipment after details load; provider indexing, batching and source attribution remain intact.
- All 27 suites / 1,055 checks passed, including 58 loot cases; `git diff --check` clean.
- Built `dist/QuestSharing-0.4.3.zip`: 29 addon files match source; SHA256 `af209ddb41dc6ca695b1364b56c00c3dade5ef7281b385ae19010ccbec0f0cd1`.
- Reusable report: `context/BUGS/2026-11-13-instance-loot-non-equipment.md`; live architecture/schema updated.

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
