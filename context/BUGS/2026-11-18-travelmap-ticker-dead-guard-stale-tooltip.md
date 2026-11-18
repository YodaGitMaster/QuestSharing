# 2026-11-18 — TravelMap ticker dies on error, dead block guard, stale tooltip

**Status**: solved (static review + existing tests; not checked in the WoW client)
**Severity**: medium
**Tags**: TravelMap.lua, tick, ns.after, ns.trying, ns.isBlocked, "travelmap", OnLeave, hide(), U.hideTip, timer

## Symptom
- Observed: none seen in game; found by running tools/lua-syntax-review-prompt.md on the new overlay.
- Expected: overlay keeps refreshing after one error, turns itself off after repeated failure, no tooltip left behind.
- Where: QuestSharing/TravelMap.lua (`tick`, `T.draw`, `hide`). Same `tick` pattern exists in VendorMap.lua:867 (not changed).
- Environment: Classic Era map (WorldMapFrame.ScrollContainer.Child); timers in Core.lua OnUpdate.

## Reproduction
- Make `T.draw` throw once (e.g. nil `child` field after a Blizzard map change): `tick` never reschedules itself.

## Root cause
- Core.lua timer loop does `table.remove(timers, i)` BEFORE `xpcall(t.fn)`. `tick` called `T.draw()` first and `ns.after(...)` last, so a throw skipped the reschedule.
- `ns.isBlocked("travelmap")` can only become true via `ns.trying(what, "travelmap")`; nothing called it (same dead guard in VendorMap "vendormap", ItemSources "itemsources").
- `hide()` hid the layer while a pin was hovered; hidden frames get no OnLeave, so the GameTooltip stayed.
- Trap category: lifecycle / resource cleanup; error-recovery ordering.

## Methodology (reusable)
1. For any self-rescheduling timer, read how the scheduler dispatches: is the entry removed before or after the call? Here before, so reschedule must come first.
2. For every `isBlocked("x")`, grep for the setter `ns.trying(..., "x")`; a guard with no setter is dead.
3. For any `hide()` that can run while a hover is active, check that the OnLeave cleanup is also done there.
4. Dead ends: no 5.2+ syntax, no unknown globals, cross-file exports (V.pointOnMap, U.tip, S.fill) all exist.
5. Fix pattern: reschedule before work; call `ns.trying` at the redraw step only (not every tick: it appends to the log); guard tooltip cleanup with `if hovered` (hide() runs every tick while the map is closed).

## Fix
- Files changed: QuestSharing/TravelMap.lua
- Commit / PR: uncommitted
- Workaround? no

## Verification
- loadstring parse ok; all 49 tests/test_*.py pass (run as scripts). No new test added for the throw path.

## If it shows up again
- Overlay stops updating until /reload: look for a throwing `T.draw` and `ns.recentCalls`/Diagnostics output.
- Apply the same reschedule-first and `ns.trying` fix to VendorMap.lua tick/draw (still open there).
