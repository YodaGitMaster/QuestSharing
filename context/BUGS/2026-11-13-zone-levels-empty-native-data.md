# 2026-11-13 — Zone levels show question marks everywhere

**Status**: solved
**Severity**: medium
**Tags**: ZoneLevels.lua GetMapLevels missing empty zero 0 0 ??? question marks zone questing levels fallback Forever map

## Symptom
- Observed: user sees `???` for every zone on the world map.
- Expected: useful questing level ranges across known zones, with the layer still optional/off by default.
- Where: ZoneLevels.lua, v0.4.13.
- Environment: no game client available; exact native client values not captured. Empty/zero API metadata reproduces the reported map-wide behavior through actual Lua modules on modern/classic mocks.

## Reproduction
- Enable zoneLevels, show the continent, make C_Map.GetMapLevels return 0,0 for every zone.
- Before fix, Elwynn/Westfall and every other label show `?`; selected zones report range unavailable.
- 14 new missing-data/fallback checks failed before runtime changes (34/48 passed).

## Root cause
- The renderer had only one source for levels: native GetMapLevels. The declared API may return nothing and some maps have zero/invalid metadata; validation correctly rejected it, but no fallback existed.
- Earlier tests assumed useful native values and explicitly expected known zones to stay unknown without them. The runtime coverage assumption was never verified in-game.
- Trap category: env/config and API/data-shape assumptions; availability confused with populated data.

## Methodology (reusable)
1. Read prior zone opt-in report; verify that saved settings and geometry work before changing defaults or map rendering.
2. Separate numeric range resolution from badge placement: question marks still occupy correct zones, pointing to missing values rather than geometry.
3. Read the actual client API declaration; reproduce nil, throwing, zero, reversed and fractional values instead of trusting happy-path mocks.
4. Add fallback data keyed by UI map ID, verified independently from native metadata. Keep native ranges preferred, with fallback origin clearly labelled.
5. Audit IDs and ranges against primary sources; distinguish published guide brackets from spans inferred from known quest records. Do not silently treat partial quest data as a complete official zone recommendation.
6. Keep fallbacks uncached so delayed native values supersede them. Preserve unknown future areas, localized names, city/sanctuary semantics and off-by-default lifecycle.
7. Test the reported broad scope: 50 known maps render without question marks when native ranges are all zero; verify no map mutation and no regression in other tools.

## Sources and scope
- [Forever client Map API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua): GetMapLevels MayReturnNothing=true.
- [LibTourist Classic Era author project](https://www.wowace.com/projects/libtourist-classic-era), revision246 commit `d2380757a8fe2b1cb2d341817e36e1cd0bccee3a`: all 39 Classic numeric brackets checked by exact map ID; MIT source attribution retained, no runtime library dependency.
- [Blizzard Skyborne guide](https://worldofwarcraft.blizzard.com/en-us/news/24302071/): Zephras1–12. [Blizzard Forever launch](https://worldofwarcraft.blizzard.com/en-us/news/24315820): Riverglades mid-30s to mid-40s (general guide35–45).
- [QuestieDB source snapshot](https://github.com/Questie/QuestieDB/blob/4dde6c43201b15c0b0f370cf85e7259e1922322a/src/corrections/Forever/generated/foreverBaseQuest.lua): computed positive questLevel spans for zone-tagged records: Hyjal36quests56–60, Shen'dralas19quests38–43. These are labelled Known quests, incomplete by definition.
- [Forever UI map IDs](https://github.com/Questie/QuestieDB/blob/4dde6c43201b15c0b0f370cf85e7259e1922322a/support/Forever/Zones/uiMapIdToAreaId.lua): IDs2482/2521/2548/2652 verified; AreaTable IDs must not be substituted.

## Fix
- Runtime: QuestSharing/ZoneLevels.lua only; supporting tests, release metadata and continuity documentation.
- Native valid bounds cached/preferred; fallback Zone guide/Known quests spans for 43 questing maps; role labels for six cities and Moonglade.
- Defaults, migration, map navigation, click-through behavior and retired quest/minimap overlays unchanged.
- Commit / PR: v0.4.14 publication pending.
- Workaround? no; this is a supported fallback path documented in context/decisions.md.

## Verification
- All 34 suites / 1,291 checks pass; 50 zone checks cover missing/throwing/invalid APIs, all-map zero values, localization, late native recovery, unknown data, opt-in behavior, geometry and protected-map guards.
- Install ZIP: 32 runtime files byte-match tested source, retired QuestMap renderer absent; SHA256 `d272c5586915eb3de82d0a2242dc4a715a1ed7cc56f408491f995326e1c6a5b8`.
- Native in-game visuals and actual client return values remain unverified; user should install the corrected release and open the map normally.

### Wanted vs. Done
| # | Wanted | Done | Match? |
|---|---|---|---|
| 1 | Useful known-zone levels when native data is empty | Verified standalone guides and labelled known-quest spans | ✅ |
| 2 | No map-wide question marks | 50-map zero-metadata reproduction now shows ranges or role labels | ✅ |
| 3 | Optional behavior retained | Existing default false, toggle/migration tests pass | ✅ |
| 4 | Late native data and future unknown maps handled honestly | Native recovery supersedes fallback; unverified maps remain unknown | ✅ |

### Quality
| Check | Pass? |
|---|---|
| Only planned resolver/data/render-source fields and support docs/tests changed | ✅ |
| Original broad-scope reproduction resolved in actual Lua mocks | ✅ |
| No automated side effects: all1,291 checks pass | ✅ |
| Minimal scope: no settings/provider/map-navigation refactor | ✅ |
| Native game rendering | Unverified; requires game client |

## If it shows up again
- Confirm installed version and UI map IDs; inspect missing native ranges separately from failed child-zone geometry.
- Check the fallback table by UI map ID, not translated name or AreaTable ID.
- Re-test empty values and recovery, not just a mock returning ideal native numbers.
- Expand verified coverage with documented provenance; do not assign guesses to new maps or cache partial fallbacks permanently.
