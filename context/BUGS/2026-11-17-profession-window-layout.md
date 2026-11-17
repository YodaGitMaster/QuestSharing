# 2026-11-17 — Profession GUI opens a separate unreadable companion

**Status**: solved (implementation and emulation; native game check pending)
**Severity**: medium
**Tags**: Professions.lua, ProfessionUI.lua, QuestSharingProfessions, ProfessionsFrame, cooking, separate window, unreadable, grey recipes, GUI

## Symptom
- Observed: user says "it should use the same wow panel not a new one", "impossible to read", and "all reciped gray out which i dont now and level and where" after v0.4.19.
- Expected: existing WoW profession window, all recipes in one scrolling list, grey clickable unlearned entries, readable skill/source fields and native profession styling.
- Where: old `Professions.lua:build/open`, `Style.button`, `OptionalUI.text`.
- Environment: Interface16001, v0.4.19; Forever CraftingPage/RecipeList/SchematicForm.

## Reproduction
- In actual Lua harness with own Cooking API fixture, emit TRADE_SKILL_SHOW and advance timers.
- Before: `_window().frame.name == "QuestSharingProfessions"`, parent is not ProfessionsFrame, six 26px-spaced Style.button rows using GameFontHighlightSmall, pipe-concatenated fields and repeated source/provenance lines.
- Native game visual unreadability is user-observed; the harness reproduces window ownership and layout choices, not actual WoW pixels.

## Root cause
- Treated "the game's profession window" as permission to launch a companion. The separate 740x610 window duplicated native navigation while a six-row paged layout and dense small-font copy prevented scanning.
- Prior tests established frame bounds/data paths, not the requested ownership, information hierarchy or readability; no native visual validation was available before release.
- Trap category: scope/lifecycle ownership, layout/data presentation mismatch, confirmation bias from passing data tests.

## Methodology (reusable)
1. Read continuity/prior GUI and scroll-overlap reports; reproduce the actual frame's parent, row pool, text style and entry event before editing.
2. Read Forever's primary UI source rather than infer Retail behavior: native CraftingPage.RecipeList, SchematicForm and SelectRecipe(info,skipSelectInList) are usable. Camelot resets show-unlearned false; changing global filters risks rebuild loops.
3. Reject another reskinned standalone window, a filter toggling loop and synthetic recipeInfo injected into native crafting. User explicitly authorized full GUI redesign; implement embedded child views while retaining factual/source model.
4. Embed a pooled scrolling list over RecipeList; route only live learned recipeInfo to native SelectRecipe. Clear transaction/native selection before an unlearned source pane so previous recipe crafting cannot remain active behind it.
5. Exercise native background auto-selection while an unlearned row is selected: visible list selection must stay authoritative through native Refresh. Test long sources by measuring text and ingredient offsets, not fixed assumed line counts.
6. Export actual model content to an explicitly illustrative preview; inspect grey rows, source hierarchy, Upgrades/factions, ingredient detail and overflow; preserve the limitation that this isn't a native game screenshot.

## Fix
- Files changed: `QuestSharing/Professions.lua`, new `ProfessionUI.lua`, TOC, scoped Settings wording, `tests/test_professions.py`, preview tools and continuity/user documentation.
- One native host; 44px scroll rows, 14px name/skill and source-pane text, 12px secondary source, 18px title, separate columns and structured selection detail.
- Upgrades stays inside ProfessionsFrame (also over the profession overview); all12 professions and direct faction choices. Normal native recipes/crafting remain available.
- No filter toggles, runtime downloads, auto-crafting or standalone fallback. Native unsupported -> tell user to open K/choose profession.
- Commit/PR: local redesign preview; no publication requested in this turn.
- Workaround? No.

## Verification
- 56 focused integration checks pass on both mock API styles: native ownership/no standalone, full-list scrolling, fonts/grey rows, own/linked/source guards, source formatting/factions, live-only recipes, native known-recipe handoff, cleared crafting state, background refresh selection, overview access, tooltips, combat/close/disable and long-copy content flow.
- Final baseline-suite/package figures are recorded in context/state.md; package is built from released source plus profession changes to avoid bundling concurrent unrelated local work.
- Browser preview inspected: 133 actual model records with illustrative learned states, grey RGB170/169/165, no horizontal overflow; Recipes/Upgrades, Alliance choice and material detail work. Screenshot `profession-redesign-preview.jpg` in the chat visualization directory.
- Native WoW fonts, gamepad focus, frame geometry/other profession addons and actual learned-state coverage still need live validation.

## If it shows up again
- Assert frame ancestry first; no UIParent-owned QuestSharingProfessions frame should exist.
- Check native page fields and frame levels against the installed Forever UI build; verify native minimize/maximize geometry and conflicting profession addons.
- Reproduce native automatic selection and clear crafting transaction before showing unknown/unlearned rows; don't manufacture recipeInfo for native schematic calls.
- Check actual font sizes/contrast and measured wrapped text heights; a passing bounds test alone cannot prove readability.
