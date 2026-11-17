# 2026-11-17 — Dungeon loot browser does not open / misbehaves

**Status**: closed — not a bug (user meant Dungeon quests; see addendum)
**Severity**: medium
**Tags**: Loot.lua EquipmentUI.lua Settings.lua "Browse drops" "Instance drops" /qs loot AtlasLootClassic DungeonsAndRaids LoadOnDemand QuestieDB v0.4.20

## Symptom
- Observed (user, verbatim): "dungeon loot does not open nor work properly when opened". No error text, entry point or screenshot yet.
- Expected: journal opens on Instance drops tab, lists dungeons and blue+ equipment with sources.
- Environment: installed v0.4.20 (assumed); provider (AtlasLoot vs QuestieDB) unknown.

## Reproduction attempts (all PASS, no defect found)
- tests/test_loot.py 58/58 (modern+classic).
- Harness probe of every entry point: `/qs loot`, `/qs loot blade`, Settings `settingsAction` "Browse drops", journal tab from Rewards and from Dungeon quests, close/reopen mid-scan, tab switch mid-scan, inside Deadmines auto-focus.
- Scale probe: 20 dungeons, ~5.8k rows, half uncached — results stream in, no errors.
- **Real AtlasLootClassic** (HoliestWoW `d3c4e07`, 2026-09-28) `ItemDB.lua` + `DungeonsAndRaids/data.lua` executed in harness via LoadOnDemand mock: 30 dungeons (incl. Forever 16560/16611/16732/16919, DM E/N/W, SM wings), 1,371 equipment items, 0 errors, IS_FOREVER true and false.

## Methodology (reusable)
1. Run tests via `/tmp/questsharing-test-env/bin/python` (lupa 2.8); harness `g.slash()` takes text WITHOUT `/qs` prefix (easy false positive).
2. Real-data smoke: `git clone --depth 1 https://github.com/HoliestWoW/AtlasLootClassic /tmp/qs-atlas-src`; probe script `/tmp/qs-loot-probe/real2.py` (may expire). Shim needs: `AtlasLoot.Locales/IngameLocales` identity metatables, `Data.ContentPhase.IsActive`, `Data.AutoSelect.AddInstanceTable`, `Loader.IsMapsModuleAviable/LoadModule`, `Button:CreateFormatTable`, `GameVersion_GE/LT`, `ReturnForGameVersion`, `_G` `ATLASLOOT_*` fallback, `string.split`; run data.lua outside pcall first — U.call pcall hides load errors.
3. Verified contract: `GetItemTable` returns rows, format table with `[1]=="Item"` (Set tables skipped), difficulty data; can return a string addon name when a linked module is not loaded (skipped as non-table). ContentType index → `GetContentTypes()[i][1] == AL["Dungeons"]`.
4. Ruled out: QuestieDB fallback detection matches Questie.lua `canEnumerate`; window plumbing (`E.page/E.show/E.visible`) consistent; 0.4.17+ helper swap (`E.button/E.listButton/E.text`) keeps `SetLabel`.

## If it shows up again / next steps
- Ask: entry point used; what "does not open" looks like (nothing / error / behind Settings); what the open window shows (stuck "Reading … tables", "Install compatible AtlasLoot…", empty list, clicks dead); AtlasLoot installed + version; `/qs doctor` Copy all.
- Unchecked: native strata/overlap with Settings window (both `S.window` "dialog"); old AtlasLoot builds without `ItemDB.Storage`; combat deferral path in live client.

---
## Addendum 2026-11-17 — misidentified feature
- What happened: user clarified "i speak about dungeon quests" — the report was about the Dungeon quests tab, not instance loot.
- Instance loot browser: no defect found (all checks above stand).
- New status: closed / not a bug. Real bug tracked in `2026-11-17-dungeon-quests-slow-first-load.md`.
