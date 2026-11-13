# State
Last updated: 2026-11-13

## Active task
- Completed user-requested push and GitHub release of version 0.4.2; no publication work remains.
- New settings tab: `/qs settings` > Optional; fishing layer and reward browser default off.
- `/qs fishing`: persistent per-water editor; `/qs fishing on`: world-map layer, with Alt-click placement where supported.
- Quest-objective and turn-in symbols removed from both maps: no renderer, setting or background refresh; old enabled saved settings are discarded.
- `/qs adventure [quest ID or title]`: role-play invitation preview for any chat channel; Prepare fills chat and Enter sends. Also on each quest menu and Optional settings.
- `/qs loot [search]`: GUI instance drop search, with instance list, encounter filter, item/name/ID/boss search, source details and native item comparison.
- `/qs rewards`: on-demand quest equipment browser; defaults to own class/level/faction, supports slot/search filters, item comparisons and quest routes.

## Last completed
- Added `QuestSharing/Loot.lua`, Optional settings entry, reward browser button and `/qs loot` command.
- Primary provider is compatible installed AtlasLoot DungeonsAndRaids; clearly labelled partial QuestieDB fallback uses known instance NPC/object drop sources.
- Loot tables indexed on request in batches; native item-name requests are throttled, cached names refresh asynchronously, and closing/disabling cancels unfinished work.
- All 27 suites passed: 1,043 tests, including 46 new loot integration cases; `git diff --check` clean.
- Actual Forever-compatible AtlasLoot ItemDB.lua/data.lua smoke-loaded: 34 instance records / 2,635 item-source entries, item 5191 (Cruel Barb) -> Edwin VanCleef / The Deadmines, no Lua errors.
- Updated README, changelog, schema, decisions, insights and live architecture.
- Built local install ZIP: `dist/QuestSharing-0.4.2.zip` (29 addon files); quest map renderer remains absent.
- Committed release implementation as `5dbb839731f7ce33ff2bd1c6f5fb4353b6dd06cc`; pushed main and annotated tag `v0.4.2`.
- Published stable GitHub release with combined notes for 0.4.0–0.4.2 and `QuestSharing-0.4.2.zip` (144,509 bytes).
- Downloaded the published ZIP and confirmed byte equality with the tested local artifact; SHA256 `f1839bca6f8d0c0cc15239c7a9e090fbd69be72424664341b61776700ef0abfb`.

## Remaining work / limits
- Loot GUI rendering, installed AtlasLoot module loading and live native item-data timing need an in-game check; no game client is available here.
- Full instance loot coverage requires a compatible installed AtlasLoot catalogue; QuestieDB alone is partial, and no third-party loot data is bundled.
- Real-game verification of invitation chat routing, window layout, Alt-click fishing placement, item data and comparison tooltips is still required; no game client is available here.
- Fishing coverage gap: per-water fish/skills are user-entered, not a complete automatic catalogue for every location. Optional installed AnglerAtlas supplies separate zone summaries; some Forever data is explicitly provisional.
- Reward browser requires recent QuestieDB item enumeration and active-flavor class/faction/race enum tables.
- Equipment family filter uses Classic rules; item-specific restrictions, Forever proficiency changes and build suitability need tooltip comparison. Quest conditions beyond displayed level/class/race are not fully evaluated.
- Water records are retained on settings reset and only deleted explicitly.

## Verification environment
- `/tmp/questsharing-test-env/bin/python` with `lupa` 2.8 / Lua 5.1; host Python lacked lupa.
- Third-party reference only: `/tmp/questsharing-angler-reference`; no third-party dataset is bundled.
- Important existing guard: never open/redraw Blizzard's world map from addon code; protected pin creation can be tainted. New map buttons print directions.

## Current release
- Published v0.4.2: https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.2
- Tag resolves to `5dbb839731f7ce33ff2bd1c6f5fb4353b6dd06cc`; GitHub confirms stable published release and uploaded install ZIP.
- Main also includes a documentation follow-up recording publication verification. Previous published version was v0.3.9 (`0c3b168`).
