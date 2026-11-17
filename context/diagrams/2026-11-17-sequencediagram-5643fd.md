# sequenceDiagram

Captured 2026-11-17T19:48:49.591Z - run r-20261117-204723-95d0

```mermaid
sequenceDiagram
    participant Planner as QuestPlanner.buildRoute
    participant QA as questActions()
    participant Opt as QuestOptimizer.optimize
    participant Path as QuestPlannerPath
    Planner->>QA: build stops
    Note over QA: Every location is fixed here, measured from the player:<br/>pickup/turn-in = nearestSource()<br/>objective = targetLocation() nearest real camp
    QA-->>Planner: stops (point fixed) + dependencies
    Planner->>Opt: optimize(catalog, stops, opts)
    Note over Opt: 1. greedy nearest legal action (baseline)<br/>2. re-runs with different starting hints<br/>3. beam search, only if ≤40 actions
    Opt-->>Planner: ordered stops + report
    Planner->>Path: real walking cost, first leg only
    Path-->>Planner: costs → solve() again
```
