# 2026-11-17 — Map suggestions need a readable background

**Status**: solved
**Severity**: low
**Tags**: VendorMap.lua suggestions transparent text background frame strata opacity map autocomplete

## Symptom
- Observed: user says suggestions are very hard to read because they are transparent and need a background.
- Expected: readable text on a solid background above map details.
- Where: `QuestSharing/VendorMap.lua:ensureUI`, suggestionBox and suggestion rows.
- Environment: user confirms Quest Sharing v0.4.17 in Stormwind capital; local vendor work remains unpublished. Native client unavailable.

## Reproduction
- Instrument real popup creation in Lua harness and type `gene` to show suggestions.
- Before fix: background RGBA `(0.025,0.04,0.065,0.98)`, no explicit frame strata/level, 268px rows and 264px GameFontHighlightSmall text.
- User's visual failure is reported directly; actual map/background occlusion cannot be rendered in the mock.

## Root cause
- Popup styling did not guarantee an opaque surface above map content: slightly translucent fill and inherited frame layering allowed competition with map artwork; small narrow text also limited readability.
- Exact native occlusion remains an inference. The patch establishes explicit opacity and layer ordering rather than claiming visually verified compositing.
- Trap category: scope/layer ownership; no async or search matching changes needed.

## Methodology (reusable)
1. Check actual shared Style.fill behavior before assuming no background exists; capture texture RGBA and popup strata/level.
2. Separate alpha from draw order: raising only opacity does not resolve a background obscured by another frame.
3. Reuse existing equipment-dropdown TOOLTIP strata/map-level+40 pattern on own popup only; avoid changing protected map frames or global styling.
4. Use a fully opaque border and dark inner surface, larger explicit white text and rows sized to the popup.
5. Inspect instrumented opacity/layer/text/geometry and click dismissal on both API mocks; state native-rendering limitation rather than equating mocks with a game screenshot.

## Fix
- Files changed: `QuestSharing/VendorMap.lua`, README/changelog and continuity notes.
- Popup 316x142, dark opaque background/border, TOOLTIP strata and world-map level+40, clamped/mouse enabled.
- Six 300x22 rows, 296px GameFontHighlight text with explicit white color.
- Commit / PR: local/unpublished; no release requested.
- Workaround? No.

## Verification
- Existing map suite: 52/52 checks; matching, trainer/vendor discovery and selection behavior preserved.
- One-off instrumented checks on modern/classic: both fills alpha=1; popup above map; larger white text; rows fit bounds; clicking selects and dismisses.
- `luac -p QuestSharing/VendorMap.lua`, `git diff --check`: pass.
- Native WoW appearance remains unverified. No permanent implementation-mirroring test added for this visual-only patch.

## If it shows up again
- Confirm installed addon version includes the local changes; user currently runs v0.4.17.
- Check popup and ancestor effective alpha, strata/levels, map overlays and inherited font colors separately.
- Capture actual in-game appearance to distinguish compositing from font scaling/contrast problems.
