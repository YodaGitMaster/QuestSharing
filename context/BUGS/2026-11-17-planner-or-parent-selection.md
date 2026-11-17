# 2026-11-17 — Planner OR parent selection

**Status**: solved
**Severity**: medium
**Tags**: QuestPlanner.lua, QuestOptimizer.lua, preQuestSingle, OR prerequisite, selected route

## Symptom
- Observed: a selected quest could follow the first graph-selected prerequisite and continue unrelated work after the selected hand-in.
- Expected: choose the cheaper feasible parent branch and stop the selected route at the target hand-in.
- Where: `buildGraph`, `questActions`, `QuestOptimizer.compile`, `attempt`.
- Environment: local zone with two alternative prerequisite chains, one with near pickup and far objective.

## Reproduction
- Give the selected child a turn-in gate with parent IDs 1 and 2. Place parent 1's work far away, parent 2's pickup/work/turn-in near the child. Compare the selected route's completed IDs and action order.

## Root cause
- Discovery chose one OR parent and hard dependencies treated that choice as mandatory. Selected scoring could keep greedy actions after its target was complete.
- Trap category: type versus runtime model mismatch; state/goal boundary.

## Methodology (reusable)
1. Inspect the provider's OR gate separately from graph reachability and atomic action dependencies.
2. Preserve all gate choices in the candidate and evaluate them against simulated claimed/open/finished state at pickup.
3. Seed both parent branches and snapshot selected-mode plans at a selected hand-in.
4. Verify the lower-cost higher-ID parent wins; verify the other branch is absent.

## Fix
- Files changed: `QuestSharing/QuestPlanner.lua`, `QuestSharing/QuestOptimizer.lua`, `tests/test_quest_optimizer.py`.
- Commit / PR: local workspace, uncommitted.
- Workaround? no.

## Verification
- `test_selected_quest_chooses_cheaper_or_prerequisite` passes modern/classic; focused optimizer 32/32 and full harness 1,731 checks pass before the final event regression was added.

## If it shows up again
- Inspect `q.gates`, atomic pickup dependencies and selected-mode snapshots; a graph discovery parent must not become a forced route parent for an OR gate.
