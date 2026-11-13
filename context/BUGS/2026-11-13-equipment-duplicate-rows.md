# 2026-11-13 — Equipment explorer duplicate rows

**Status**: solved
**Severity**: medium
**Tags**: EquipmentUI.lua Loot.lua Rewards.lua duplicate items same name multiple bosses sources quest rewards difficulty grouping

## Symptom
- Observed: the same equipment appeared multiple times in the explorer, once per source/difficulty or reward quest.
- Expected: one row per equipment name, with all matching mobs or quests listed together inline.
- Where: instance drops and quest rewards in the shared Equipment explorer, v0.4.12.
- Environment: reproduced using real Lua modules on both modern/classic API mocks.

## Reproduction
- Give Captain's Blade to Cookie as well as VanCleef's Normal/Heroic tables; `/qs loot` shows three rows for that item.
- Give Druid Staff questRewards={8000,8001}; `/qs rewards` shows two rows for the staff.
- Initial 18 grouping assertions failed before the runtime change.

## Root cause
- Raw catalogue entries intentionally preserve item/source/difficulty relationships, but the UI rendered those raw records directly and used source-specific selection keys.
- Tests previously treated multiple source rows as correct and even used repeated copies of a single item to test paging. The required presentation identity is the item name, independent of source or ID.
- Trap category: data-shape/domain mismatch; source identity confused with equipment presentation identity.

## Methodology (reusable)
1. Reproduce through the actual Lua catalogue and inspect item IDs, mobs, modes and quest IDs separately from the visible row count.
2. Rule out parser duplication: raw exact item/source/mode entries were already deduplicated, but different legitimate sources still needed preservation.
3. Keep providers/raw indices unchanged; apply all existing filters before grouping so an ineligible same-name variant cannot leak sources, quality, stats or quest routes.
4. Group by normalized equipment name, retaining source arrays and versions; choose highest native level then lowest ID deterministically for the native comparison tooltip.
5. Collapse each dungeon/mob/provider entry's difficulty labels; retain all quest locations/prerequisites. Use the existing scrollable pane, bounded hover previews and stable name selection.
6. Update provider tests to inspect retained sources, while visible counts assert unique items. Use genuinely distinct equipment for paging tests rather than weakening navigation checks.
7. Verify identical-name/different-ID items, cache arrivals, character eligibility, Rare+, stat/level/source searches and full routes on both API paths.

## Fix
- Runtime: `QuestSharing/EquipmentUI.lua`, `QuestSharing/Loot.lua`, `QuestSharing/Rewards.lua`; release version 0.4.13.
- Supporting files: focused grouping suite, adjusted source/paging fixtures, manifest/changelog/README and continuity docs.
- Scope: presentation grouping only; provider discovery, raw indices, saved settings, map behavior and dungeon scope unchanged.
- Risk: merging names can conceal differing IDs; details explicitly list versions/levels and identify the comparison version.
- Commit: `1bf2789ca1d7ddbbc7ee9039e4f06cb22a525361`; release https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.13
- Workaround? no.

## Verification
- All 34 suites / 1,275 checks pass, including 28 grouping workflows; `git diff --check` clean.
- Install ZIP: 32 entries byte-match runtime source, retired QuestMap renderer absent.
- Published latest stable v0.4.13; remote tag matches implementation commit and downloaded ZIP byte-matches verified local build.
- Native game rendering and real item-cache timing require in-game QA; no game client available.

### Wanted vs. Done
| # | Wanted | Done | Match? |
|---|---|---|---|
| 1 | One row per equipment name | Both tabs group names, including different IDs | ✅ |
| 2 | All mobs listed together | Full inline supplier list; each mob once with combined modes | ✅ |
| 3 | Keep useful quest/source details | All eligible routes, versions and native comparisons retained | ✅ |
| 4 | Preserve filters and navigation | Filter-before-group, unique counts/paging, stable name selection | ✅ |

### Quality
| Check | Pass? |
|---|---|
| Only planned runtime modules and supporting release/docs/tests changed | ✅ |
| Original duplicate-row reproduction resolved on both API mocks | ✅ |
| No automated regressions: all 1,275 checks pass | ✅ |
| Minimal scope: no provider/setting/map refactor | ✅ |
| Native visual check | Unverified; needs game client |

## If it shows up again
- Inspect whether the visible result passed through EquipmentUI.groupItems after every filter, and compare its normalized name key.
- Check sources/suppliers/routes rather than deleting raw provider records to hide duplicates.
- Retest a same-name variant arriving asynchronously and source searches that should exclude other versions.
