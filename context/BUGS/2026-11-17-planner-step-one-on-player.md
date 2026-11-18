# 2026-11-17 — Quest guide step 1 sits on the player and follows them

**Status**: solved in source (2026-11-17, run r-20261117-215940-e171: SPF camp flip and mixed-creature camp loss fixed; then run r-20261117-234605-6ba9: camp choice no longer uses SPF at all; uncommitted/unreleased); native WoW validation pending. History: the lone-spawn fix shipped in v0.4.21; f1b34e9 regressed it (see the audit addendum).
**Severity**: high
**Tags**: QuestPlanner.lua targetLocation nearestPoint playerPoint objective spawn camp groupCamps REAL_CAMP CLUSTER_DISTANCE "starts from me as point 1" step 1 follows player rebuildProgress OnUpdate siteMemory preferredSites avoidBusyCamps SPF EstimateWalks camp flip

## Symptom
- Observed: user reports the quest algorithm "start[s] from me as point 1 which is wrong". Step 1 (and its map pin) lands on the player's own position; after walking it re-appears on the player again.
- Expected: step 1 is a real destination (a giver, or the area where the mobs/objects actually are); your position is only the route's origin.
- Where: `QuestSharing/QuestPlanner.lua` `targetLocation()` -> `nearestPoint()`; movement re-plan in `P.open()` OnUpdate.
- Environment: QuestieDB lists every spawn of an NPC/object separately; common mobs have lone spawns scattered over the whole zone.

## Reproduction
- Active local kill quest; mob has a 6-spawn camp at 30,30 plus lone spawns at 50.4,50.3 and 70.3,70.2; player at 50,50.
- Before fix: step 1 at 50.4,50.3 (on the player). Move player to 70,70 and wait 3 s: step 1 at 70.3,70.2 (on the player again). The camp never appears.

## Root cause
- An objective's location was the single spawn closest to `playerPoint`. With scattered lone spawns there is nearly always one at the player's feet, and the panel re-plans every 3 s after >= 0.025 map units of movement, so the step re-snaps to the new position.
- Trap category: wrong key (distance to the player used as "where the work is") + value recomputed from a moving input.

## Methodology (reusable)
1. Rule out the renderers first: the map overlay (`QuestGuidance.drawMap`) only draws route stops, and the optimizer never inserts the origin as a stop. So a stop "at me" must come from stop point data.
2. Trace stop points to their producer: pickups/turn-ins use `nearestSource()` (givers have about 1 spawn), objectives use `targetLocation()` -> `nearestPoint()` over every spawn.
3. Reproduce with the real Lua planner: a camp plus lone spawns, then move the mocked player and advance past the 3 s re-plan. The step following the player confirms the mechanism.
4. Fix pattern: represent where the work is independently of the player. Group spawns into camps, then use the player only to pick among real camps (the user chose "nearest real camp" over "biggest camp").
5. Ruled out: the optimizer (`QuestOptimizer.lua`) and guidance overlay need no change; SPF first-leg costs only refine travel from the origin.

## Fix
- Files changed: `QuestSharing/QuestPlanner.lua` (`groupCamps`, `REAL_CAMP`, `targetLocation`), `tests/test_quest_planner_zone_steps.py`, README, CHANGELOG (Unreleased), context notes.
- Camps: per map, the densest untaken spawn seeds a camp of the free spawns within `CLUSTER_DISTANCE` (0.065, grid-bucketed); the member nearest the camp centroid marks it. A camp is real at >= min(3, the target's biggest camp on any map). The nearest real local camp wins, and the camps are cached on the target for the scan.
- Commit / PR: local, uncommitted.
- Workaround? no.

## Verification
- New tests (both modern/classic): lone spawns never outrank the 30,30 camp, including after moving; with two real camps the step stays at 30,30 at 52,52 and switches to 80,80 only at 75,75.
- Zone suite 38/38; full 46 suites 1,756/1,756; 44 Lua modules compile; `git diff --check` clean; preview tool still yields 8 steps. A synthetic 20-quest x 600-spawn scan plans in 0.18 s in the harness.
- Native WoW behavior not verified.

## If it shows up again
- Check whether a new caller picks objective points with `nearestPoint()` instead of `targetLocation()`.
- Check whether `target.camps` is computed before `frameMap` is set (camps cache local projections for one scan).
- If a real mob with tight lone spawns lands wrong, compare its spawn spacing with `CLUSTER_DISTANCE` and `REAL_CAMP`.

---
## Addendum 2026-11-17 — audit
- Source: BPMN run r-20261117-212533-cf04 (check_g4 + refute_g4). Verdict **regressed**; the refuter agreed. Audited d2387c3 (= v0.4.21) against HEAD f9bb992. The optimizer work is committed in f1b34e9/f9bb992, not uncommitted.
- Still fixed: lone strays never become steps. Without SPF the step is stable and matches d2387c3 (both switch to 80,80 at POS 0.56). groupCamps/REAL_CAMP are at `QuestPlanner.lua:628-680` and targetLocation at `:687-731`. Zone suite 38/38 and optimizer 46/46 pass.
- Regression 1, the step flips with SPF: every movement re-plan rebuilds `firstLeg = {}` (`QuestPlanner.lua:848`). `solve(0)` first renders the straight-line camp, then the quest-costs re-solve (`:936-955`) swaps in the camp that is cheaper to walk to. Repro: `/tmp/bugaudit-g4/walk4.py` shows 30,30 -> 80,80 -> 30,30 -> 80,80 over re-plans at POS 0.50/0.47/0.44, and `/tmp/bugaudit-r4/rwalk.py new spf 3` renders 0.30,0.30 at t+0.1 and then 0.80,0.80 at t+0.5 on every re-plan. d2387c3 stays on 30,30 until 0.56. With FACTOR 1.5 the flip only happens at POS 0.53. This is the same trap as the original bug (a value recomputed from a moving input), now in the site choice of optimizer `place()` (`QuestOptimizer.lua:223-239`).
- Regression 2, mixed-creature camps are dropped: targetLocation now clusters per creature (`QuestPlanner.lua:691-718`, threshold `:715`). A local 2+2 camp of two creatures stops counting as real once either creature has a 3-spawn camp elsewhere, so the objective and the whole quest disappear. `/tmp/bugaudit-g4/mixed.py`: d2387c3 gives "Step 1: Go to the Mire Scale area 30.5, 31.0", HEAD gives no steps. `/tmp/bugaudit-r4/rmixed.py` variant A: HEAD has 0 rows, d2387c3 goes to 25.5,66.0. Variant C: HEAD sends the player to a far camp at 85,15 instead of the mixed camp at 48.5,53.0 next to them.
- Related (mocks only): quest-costs now runs `solve(IMPROVE_STEPS=250000)` before it renders (`:921-933`). That is about 1.1 s of CPU in lupa for 20-30 quests, roughly 55 s at 2 ms per 100 ms, so the 3 s movement re-plan cancels it and the SPF-refined route may never show while the player moves. Pre-existing: the stability rule at `QuestOptimizer.lua:773-774` needs `preferred[2]==best[2]`, so `stabilitySeconds=10` only damps exact ties.
- Test gap: no test combines SPF with alternatives, or covers mixed-creature camps.
- Fix options (not implemented): count every source on a map toward a camp's size, then attribute creatures per camp; keep the previous firstLeg costs across re-plans, offer alternatives only once SPF costs exist for all of them, or add hysteresis to the site choice; render the SPF-costed `solve(0)` first and run local search afterwards.
- Result / new status: regressed. Unreleased (f1b34e9); v0.4.21 behaves correctly. Not verified in the native client.

---
## Addendum 2026-11-17 — regressions fixed in source (fix-all run)
- What happened: BPMN run r-20261117-215940-e171 carried out stream A of `context/fix-plan-2026-11-17.md` (A2, A3, plus the A4 refine changes). It took a builder, a reviewer whose round 1 had blocking issues, a fix and a round-2 review. Then integration and a final review of the whole tree.
- Why the previous fix did not hold: it made camps independent of the player. But f1b34e9's site choice in optimizer `place()` was recomputed every re-plan, from first-leg costs that change as the player moves (straight-line, then SPF walking). That is the same trap as the original bug: a value recomputed from a moving input.
- New approach + methodology:
  1. Give the site choice memory. The planner keeps `siteMemory={map,sites[stop.key]=O.siteKey(point)}`, taken from the walking-costed solve (or any solve when SPF is absent). It passes this to the optimizer as `options.preferredSites`.
  2. Add hysteresis. `place()` keeps the held site unless another is cheaper by >= 25 % **and** >= 20 s (`SWITCH_SHARE`, `SWITCH_SECONDS` in `QuestOptimizer.lua`). See decisions.md D1.
  3. Only walking costs may switch. With SPF, `options.lockSites` holds the remembered camps in the straight-line `solve(0)` until `EstimateWalks` answers. A failed estimate, or an SPF without `EstimateWalks`, lifts the lock, so it plans as without SPF.
  4. Mixed camps: `targetLocation()` also pools all sources per map. A per-creature camp counts as real when it has >= min(3, largest) spawns or lies within `CLUSTER_DISTANCE` of a real pooled camp. Per-creature marks are kept, so shared-kill keys stay identical across quests.
  5. The quest-costs path now runs `solve(0)` with walking costs, renders, and only then refines. So the SPF-costed route shows while the player moves.
- Tests (`tests/test_quest_planner_zone_steps.py`, both styles):
  - `test_walking_with_spf_never_flips_the_objective_camp_back_and_forth`
  - `test_failed_walking_estimate_lets_a_nearer_camp_win_again`
  - `test_spf_without_walking_estimates_plans_camps_as_without_spf`
  - `test_objective_camp_timeline_without_spf_is_unchanged`
  - `test_mixed_creature_camp_stays_real_when_one_creature_gathers_elsewhere`
  - `test_nearby_mixed_camp_beats_a_far_single_creature_camp`
- If it shows up again: check whether `siteMemory` is written by a straight-line solve while SPF is available (it should not be). Check whether `lockSites` stays set after a failed estimate. Compare the camp's cost gap with the 25 % / 20 s margin.
- Result / new status: solved in source (uncommitted, unreleased, CHANGELOG `## Unreleased` > `### Fixed`). Native check pending: walk in Westfall with SPF and confirm there is no A→B→A camp flip.

---
## Addendum 2026-11-17 — camp choice no longer depends on SPF (decouple run)
- What happened: BPMN run r-20261117-234605-6ba9 (process "decouple", outcome "Planner decoupled") removed Shortest Path Forever from planning altogether. The guide plans with straight-line travel only; SPF is used only for the explicit Follow arrow (`Path.follow` → `Navigate`). See decisions.md D5–D7.
- Why the previous fix was replaced: the fix-all design (`lockSites` until `EstimateWalks` answered, `siteMemory` written only by a walking-costed solve, a `quest-costs` re-solve) still made the camp depend on whether SPF was installed and on when its async answer arrived. Two cost sources for one choice kept the flip risk alive and added a second solve per re-plan.
- New approach + methodology:
  1. One cost source: `planOptions()` uses only straight-line `travelSeconds`. `QuestPlannerPath.lua` keeps only `Path.available()` and `Path.follow()`; `EstimateWalks`, `firstLeg`, `walkCosted`, `lockSites` and the `quest-costs` job are gone.
  2. Memory with or without SPF: `siteMemory={map,sites}` is written by every solve and passed as `options.preferredSites` on the same map. The 25 % / 20 s margin in `place()` (D1) is unchanged.
  3. A camp forced by "Camp busy" is not remembered: `avoidBusyCamps()` returns `narrowed`, `planOptions` marks the stop in `forced`, and `solve()` skips forced stops when writing `siteMemory`. When the wait ends, the camp chosen before the mark returns. "Clear camp wait" also resets `siteMemory`, so the camp is chosen afresh from where the player stands.
- Behaviour change (accepted): stickiness now applies without SPF too, so the no-SPF timeline is no longer "switch at POS 0.56". `TWO_CAMPS`, walk 0.50→0.53→0.56→0.65→0.56→0.53→0.44→0.53 gives A,A,A,B,B,B,A,A (at 0.56 B is only about 10 s cheaper, about 124 s vs 134 s travel plus about 80 s work). The builder measured this and flagged that the brief's "keep 0.56" and "stickiness without SPF" could not both hold; stickiness won.
- Tests (`tests/test_quest_planner_zone_steps.py`, both styles): `test_objective_camp_switches_only_when_clearly_cheaper_and_never_flips_back`, `test_spf_is_never_asked_for_walks_and_the_guide_plans_as_without_it` (every SPF build gives the same plans and texts, `SPF_ESTIMATES == 0`), `test_busy_default_camp_gives_way_to_a_free_alternative`, `test_clear_camp_wait_chooses_the_camp_afresh_from_where_you_stand`, `test_camp_chosen_before_a_busy_mark_returns_when_the_wait_ends`. Also `tests/test_quest_planner_path.py` `test_bridge_offers_only_follow_and_no_walking_estimates`, `test_planner_never_asks_spf_for_walks_and_follow_button_routes_the_selected_step`, and `tests/test_quest_optimizer.py` `test_local_search_gate_holds_with_any_spf_build`, `test_route_shows_at_once_then_local_search_follows_with_or_without_spf`.
- Superseded "If it shows up again" checks: `siteMemory` written by a straight-line solve and `lockSites` after a failed estimate no longer apply. Instead check: is anything other than `travelSeconds` feeding site cost? Is a busy-forced camp being written to `siteMemory`? Does "Clear camp wait" still reset it?
- Result / new status: solved in source (uncommitted, unreleased). Native check: walk in Westfall with and without SPF installed; the camp must not flip, and both must give the same steps.
