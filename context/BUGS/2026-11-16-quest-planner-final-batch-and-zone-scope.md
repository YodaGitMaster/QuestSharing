# 2026-11-16 — Quest planner freezes at the final batch

**Status**: solved in source; game verification pending
**Severity**: medium
**Tags**: QuestPlanner.lua Reading nearby quests 5160/5233 final batch render Lua local scope current zone city map

## Symptom
- Observed: quest planner stays on “Reading nearby quests… 5160 / 5233”. User also wants the planner limited to the current zone and disabled in towns.
- Expected: scan finishes and displays a plan; town maps do not start a scan; entering a town stops an active scan.
- Where: `QuestSharing/QuestPlanner.lua` scan timer, render binding and map scope.
- Environment: WoW addon, Questie/QuestieDB loaded; native client report. Current zone/client map was not supplied.

## Reproduction
- Open `/qs plan` and wait for the final Questie ID batch; reported progress remains 5160/5233.

## Root cause
- `scan()` was defined before `local function render(zone)`. Lua resolves that earlier `render` reference as a global, so the last timer batch finished its data loop and then attempted to call a nil global; the UI kept its previous batch progress text.
- The planner also had no town/current-zone guard around scanning and waypoint actions.
- Trap category: scope/lifecycle; async completion called a name outside its intended local binding.

## Methodology (reusable)
1. Trace the progress update and final batch completion separately; a frozen counter can be stale UI after work finishes.
2. Check Lua lexical scope at the call site, not only the later function definition. A local declared later does not bind an earlier function body.
3. Verify Questie adapter capabilities before assuming a zone-indexed quest catalogue; this adapter exposes enumerable IDs only.
4. Add map guards at async boundaries and user actions, because the player can move while a scan is pending or after it completes.

## Fix
- Files changed: `QuestSharing/QuestPlanner.lua`, README/changelog and continuity notes.
- Forward-declare `render`; require an outdoor Zone map and reject city maps; recheck each timer batch; clear the plan in towns and restart after outdoor zone changes; validate selection and waypoint actions against the plan map.
- Questie ID enumeration remains batched over all IDs because no zone-only list is exposed; only local starter candidates enter the plan.
- Commit / PR: local, unreleased.
- Workaround? no.

## Verification
- `luac -p QuestSharing/QuestPlanner.lua`: pass.
- `git diff --check`: pass.
- Test suite not run; native WoW reproduction and UI behavior not available in this environment.

### Wanted vs. Done
| # | Wanted | Done | Match? |
|---|---|---|---|
| 1 | Scan completes past 5160/5233 | Final batch now calls the intended local `render` binding | ✅ in source; in-game confirmation pending |
| 2 | Planner only works in current outdoor zone, not town | Start, batch, selection and waypoint checks enforce map scope | ✅ in source; in-game confirmation pending |

### Quality
| Check | Pass? |
|---|---|
| Only planned QuestPlanner runtime file changed for this fix | ✅ |
| Root cause corrected and syntax valid | ✅ |
| Native in-game symptom confirmed absent | ❌ unavailable here |
| Diff whitespace clean and changes minimal | ✅ |

## If it shows up again
- Confirm the last batch reaches `render(zone)` and that its declaration remains forward-declared above `scan`.
- Check Lua errors for `attempt to call global 'render'` and whether timer batches continue.
- Check `C_Map.GetMapInfo`, `C_Map.IsCityMap`, player position and current map type if a town scan starts or a zone switch leaves stale stops.

---
## Addendum 2026-11-17 — Worldwide quests leak into Westfall
- What happened: user on v0.4.17 reports a Westfall plan containing quests all around the world and requests actionable Go/Take/Complete/Hand-in steps.
- Why previous zone guard was insufficient: `project()` accepted `GetMapRectOnMap(source,currentZone)` for any source without verifying ancestry or rectangle bounds. Unrelated zero rectangles produced apparently local (0,0) points; plausible unrelated rectangles also leaked. Active quests were admitted before checking local actions.
- Reproduction: real Lua planner plus Westfall and foreign starter/objective/turn-in records, with zero/plausible rectangles. Before patch, foreign quest names and active work appear at (0,0). New initial zone/instruction suite 0/14 passes.
- Method: prove map ancestry independently of returned geometry, validate finite coordinates and positive bounded child transforms; new candidates require local pending work and known hand-ins, active candidates only local actions. `canFinishHere` gates turn-ins and prerequisite lookahead. Clear old steps before zone debounce, cancel prior SPF estimates at scan start, and rescan on completion flags so newly ready local hand-ins appear.
- Presentation: numbered Go-to steps using known native place names or giver/objective fallback, per-plan quest numbers, and every per-quest task shown. No new protected map operations.
- Verification: final zone/step suite 28/28 (modern/classic), planner UI 6/6, SPF 10/10; full 38 suites / 1,434 checks, Lua syntax and diff checks pass. Native game and exact live provider records unavailable. User subsequently requests reference-led guide UI/emulation; preserve these scope rules during that continuation.
- Result / status: solved locally; not published/installed. A preview archive was built but must be rebuilt after the newly requested guide presentation changes.

### UI continuation verified 2026-11-17
- Reference-led compact native guide and actual-planner-output browser emulation now complete. Same zone/dependency fixtures remain green; full 39 suites / 1,444 checks pass, including 10 new guide-control checks. Browser interactions inspected; native game still pending.
- Final rebuilt preview: `dist/QuestSharing-preview-2026-11-17.zip`, 37 source-matching files, SHA256 `65c94ab8fa1d8cc2a38eb83cdafb721de25269e15788d9be48f5988ba98be1b4`. Unpublished preview retains TOC version 0.4.18 and includes prior authorized vendor fixes.
