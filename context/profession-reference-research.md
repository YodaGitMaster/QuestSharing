# Forever Cooking and profession reference
Last updated: 2026-11-17

## User request and interpretation
- Show unlearned Cooking recipes and acquisition sources, ingredient farm zones/levels/mobs/fishing skills, and a static all-profession upgrade tab covering both factions.
- User confirms the game's native profession window and explicitly rejects v0.4.19's separate companion as unreadable. Current redesign embeds the scrollable Cooking list, in-place unlearned acquisition pane, native learned-recipe crafting and Upgrades page inside ProfessionsFrame; separate companion is abandoned.
- Published with user-authorized v0.4.19 on 2026-11-17; original research/implementation block was local-only. See state.md for verified release details.

## Sources
- Recipe facts: https://github.com/ExcEssIv3/profit/tree/6e74500005e80750081b215a0b6dc82748f0ac9f
  - `export/recipes.json`, client build `1.60.1.70888`; includes source hints assembled upstream from client data and Zockify.
  - MIT, copyright 2026 seth. Full notice embedded in generated `CookingReference.lua`; no upstream runtime code copied.
  - 133 Cooking records, 229 referenced item names. This is a reference snapshot, not a guarantee every record is obtainable; unknown sources, incomplete ingredients and unsupported learned states stay labelled.
  - Rebuild: `python3 tools/build_cooking_reference.py [local-recipes.json]`; pinned URL default. No runtime downloads.
- Cross-check only: https://wowfdb.com/professions/cooking/recipes/ lists 123 client records with yellow thresholds (not necessarily learn thresholds); do not conflate counts or thresholds.
- Forever rank guides, checked 2026-11-17 (all warn higher-level testing may still be beta-derived):
  - https://www.wow-professions.com/forever/alchemy-leveling-guide
  - https://www.wow-professions.com/forever/blacksmithing-leveling-guide
  - https://www.wow-professions.com/forever/enchanting-leveling-guide
  - https://www.wow-professions.com/forever/engineering-leveling-guide
  - https://www.wow-professions.com/forever/leatherworking-leveling-guide
  - https://www.wow-professions.com/forever/tailoring-leveling-guide
  - https://www.wow-professions.com/forever/mining-leveling-guide
  - https://www.wow-professions.com/forever/herbalism-leveling-guide
  - https://www.wow-professions.com/forever/skinning-leveling-guide
  - https://www.wow-professions.com/forever/cooking-leveling-guide
  - https://www.wow-professions.com/forever/first-aid-leveling-guide
  - https://www.wow-professions.com/forever/fishing-leveling-guide
  - https://www.wow-professions.com/forever/fishing-and-cooking-leveling-guide
- Native API/UI primary source:
  - https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProfessionsTemplates/Camelot/Blizzard_Professions.lua
  - https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUIDocumentation.lua
  - https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUITypesDocumentation.lua
  - `ProfessionInfo.professionID` and `TradeSkillRecipeInfo.learned` verified. Forever's GenerateCraftingDataProvider resets SetShowUnlearned(false); leave native filters alone.

## Data boundaries
- Only read own Cooking (185), rejecting linked/guild/NPC/changing sources. Read 12 IDs per timer slice, combat pause and generation cancellation. Native GetAllRecipeIDs/GetFilteredRecipeIDs supplement static records only where IsRecipeInSkillLine(id,185) is explicitly true; no Questie catalogue enumeration or filter setters.
- Unlearned means explicit `learned=false`; nil/error/unavailable is labelled in the source pane. Both remain readable grey in the list; learned rows are gold and route actual native recipeInfo to CraftingPage.SelectRecipe. No known-state SavedVariables, preventing cross-character bleed.
- Installed Questie direct item `npcDrops`, `vendors`, `questRewards` plus NPC `minLevel`, `maxLevel`, `spawns`; no whole-DB scan. At most six drop NPCs/two displayed locations each, three sellers for ingredient tips; labels say when more exist.
- Seven guide-backed example fish waters; entry/no-getaway values left unknown unless supported. Guide-route recommended skill is explicitly separate from minimum entry skill. AnglerAtlas optional zone estimates/provisional flags preserved.
- The catalogue does not invent sources for missing Forever recipes or claim exhaustive farm coverage; named guide sellers supplement starter-fish gaps.
- Modern tooltip processor when available, guarded legacy tooltip event fallback; only actual ingredient IDs are decorated, excluding recipe books.

## Verification
- Current redesign: 56 focused checks; isolated full released-baseline44 suites /1,639 checks;43 Lua5.1 modules compile. CRC/source-verified45-file ZIP235,638 bytes, SHA256 `ccd81b685db1b58623559321ab2ebe2cf5a8af2c19ce712f7b146aed4ccd6298`. This supersedes original companion UI checks below. Preview exports actual model content with labelled illustrative learned states; browser inspected grey rows, source pane, Upgrades, direct Alliance choice and ingredient farming detail with no horizontal overflow.
- Native source paths additionally checked: `Blizzard_Professions/Camelot/Blizzard_ProfessionsFrame.xml`, `Blizzard_Professions/Blizzard_ProfessionsCrafting.lua` (SelectRecipe and ValidateControls), `Blizzard_ProfessionsTemplates/Blizzard_ProfessionsRecipeList.lua` and RecipeSchematicForm.lua. Tabs/list/source overlays use existing parent frames, native template controls and posthooks; no global method/filter replacement.
- Final focused suite 34/34; full 44 suites / 1,617 checks; 42 Lua5.1 modules compile; diff whitespace check and instrumented control/frame bounds pass on both harness APIs.
- Focused integration covers Known/Missing/Unconfirmed, own/linked/changing sources, pending-open cancellation, switch-to-Cooking, combat/close/master disable, factions/ranks, tooltip APIs, search/pages and sources.
- Real raw Classic Questie source smoke: all 133 recipe acquisition lookups and all ingredient lookups complete without runtime errors; Chunk of Boar Meat shows Stonetusk Boar 5-6 in Elwynn, plus other drop NPCs. Raw fixture excludes live Forever corrections.
- Native game rendering, source API completeness and actual learned-state availability still require an in-game check.
