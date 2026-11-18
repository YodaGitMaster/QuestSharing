# 2026-11-17 — Guide step numbers on the world map are hard to read and sometimes under the map

**Status**: solved in source (2026-11-17, BPMN run r-20261117-234605-6ba9 stream D3; uncommitted, unreleased); native WoW check pending
**Severity**: medium
**Tags**: QuestGuidance.lua drawMap makeMarker stack setLevel QuestSharingRouteOverlay SetFrameLevel SetFrameStrata canvas+10 canvas+2000 9900 WorldMapFrame OnShow HookScript GameFontHighlightSmall SetFont OUTLINE SetShadowOffset map step numbers hidden under map pins unreadable marker

## Symptom
- Observed: the quest guide's numbered stops on the world map are hard to read (small text, low contrast on light and dark map art), and sometimes they sit under the map, covered by native or other addon pins.
- Expected: every step number draws above the map's pins and reads clearly at any zoom.
- Where: `QuestSharing/QuestGuidance.lua`: `drawMap()`, `makeMarker()`, the marker loop; overlay frame `QuestSharingRouteOverlay`.
- Environment: the world map canvas (`WorldMapFrame.ScrollContainer.Child`) holds native/addon pins hundreds of levels above itself, and the client can re-level the canvas after our overlay is created.

## Reproduction
- Harness (`tests/test_quest_guidance.py`, `LEVELS` fixture): canvas at level 3, a native pin at 503. Open the guide with the map shown.
- Before the fix (tests written first, both failed): overlay level = child+10 = 13, below the native pin at 503; `pin.text.font` was nil (template font only, no size or outline set). By the old code, a canvas re-level (`RAISE_CANVAS`) was never followed, because the level was set only when the canvas frame itself changed.

## Root cause
- Stacking: `layer:SetFrameLevel(child + 10)` ran once, only when the canvas changed, and each pin got `layer+1/+2`. Native pins live hundreds of levels above the canvas, and a later canvas re-level was never followed, so our numbers ended up under them.
- Readability: the pin text used the small `GameFontHighlightSmall` template with no outline, on a low-contrast face, so numbers were thin and faded into the map art.
- Trap category: scope/lifecycle (a value set once at creation that the host changes later) + an assumed layer order that was never checked against native pin levels.

## Methodology (reusable)
1. Write the failing tests first, with a harness that records strata/levels and counts `SetFrameLevel` calls: a native pin far above the canvas, a canvas raise, a map hide/show, and a canvas near the level ceiling.
2. The key signal: the overlay level (13) against the native pin (503). The order was fixed relative to the canvas at creation, not relative to what actually shares the canvas.
3. Restate the stacking on every draw and every map show, not once. Compare before writing, so the 4 Hz stationary redraw makes no level calls (the test checks that the `LEVEL_SETS` count stays the same over 20 ticks).
4. Readability is measurable in the harness: font size >= 13, flags contain `OUTLINE` (never nil, since the client rejects nil flags on some widgets; see `2026-11-17-journal-black-page-editbox-setfont.md`), opaque black shadow, near-black face, bright border, on-screen size >= 30x24 at zoom 0.5, 1 and 3.
5. Ruled out: map pin pools/data providers (kept out on purpose: protected/secure gamepad paths, see decisions "Selected-step arrow and route positioning"); a fixed huge level (the client caps frame levels, so clamp).

## Fix
- Files changed: `QuestSharing/QuestGuidance.lua`, `tests/test_quest_guidance.py`.
- Stacking: new local helpers `setLevel(frame, level, strata)` and `stack()`. `stack()` reads the canvas strata and level and sets overlay = `min(9900, canvasLevel + 2000)`, legend = overlay+1, each marker = overlay+2 (selected stop overlay+3), all in the canvas strata. It writes only values that differ.
  - Runs on every `drawMap` (cached early-return path and after the marker loop), and on `WorldMapFrame` OnShow through `pcall(wm.HookScript, wm, "OnShow", stack)`, installed once when the overlay is first created (no login cost; same pattern as `Marker.lua`).
  - Removed: the one-off `layer:SetFrameLevel(child+10)` and the per-pin `SetFrameLevel(layer+1/+2)`.
- Readability (`makeMarker` + marker loop): the font keeps the template's locale font file (`GetFont`, then `STANDARD_TEXT_FONT`, then `Fonts\\FRIZQT__.TTF`) at 14 px with `"OUTLINE"`; shadow offset (1,-1), black, alpha 1. Pin = black 1 px edge, 2 px bright border (grey 0.85, gold 1/0.82/0 when selected), dark solid face (0.05/0.06/0.07, selected 0.17/0.1/0.02), white or gold (`|cffffd100`) text. Size min 32x26, width `#label*8+16`, kept constant on screen through `SetScale(1/scale)`.
- Commit / PR: local, uncommitted. No CHANGELOG line yet.
- Workaround? no.

## Verification
- New tests (modern + classic), written first and failing on the old code: `test_map_step_numbers_stay_above_native_pins_on_every_redraw_and_map_show`, `test_map_step_numbers_use_large_outlined_text_bright_border_and_dark_face`.
- review_d3@1 approved; final_check@1 verified the whole tree. Suite counts were not passed to the context step.
- Native WoW rendering not verified.

## If it shows up again
- Compare `QuestSharingRouteOverlay` level with the highest native pin level on the canvas (`/fstack` in game). If a provider puts pins above canvas+2000, raise the offset (still clamped at 9900).
- Check that `stack()` still runs on the cached early-return path of `drawMap` and that the OnShow hook was installed (it only installs when `WorldMapFrame.HookScript` exists).
- Known non-blocking items from review_d3:
  - The 26x22 grouping cell (`drawMap`, cell math ~:215/:219) did not grow with the 32x26 pins. With multi-number labels pins overlap: `10/11` next to an ungrouped `12` 27 px away overlap by 17 px (6 px with the old widths). Both sit at overlay+2, so their draw order is undefined. Follow-up: size the cell to the pin's on-screen footprint, or give same-level pins a fixed order.
  - The overlay at canvas+2000 may now draw above the player arrow and any `WorldMapFrame` overlay buttons in the map area that sit below that level in the same strata. Check in game.
  - The harness mock has no `FontString:GetFont`, so the locale-font branch is untested; the test only sees the fallback path.

---
## Addendum 2026-11-18 — follow-up: neighbouring markers overlapped
- What happened: review_d3 found the larger pins (32 px min, `#label*8+16`) still used the 26x22 grouping cell, so `10/11` and `12` 27 px apart overlapped by 17 px and hid a digit.
- Fix: merge pass in `QuestGuidance.lua` drawMap after grouping — any two groups whose drawn footprints (label width + 8 px slack for the selected-step swap, 28 px height) would overlap merge into one sorted label. Test `test_neighbouring_step_markers_never_overlap_and_merge_instead` (failed first with the 17 px overlap; guidance 46/46).
- Result / status: solved in source; native rendering pending (also check the overlay vs the player arrow).
