# sequenceDiagram

Captured 2026-11-19T15:18:33.569Z - run r-20261119-155136-ff68

```mermaid
sequenceDiagram
    participant Game
    participant Guide as Quest guide
    Game->>Guide: loot, rep gain, skill-up, spell change
    Note over Guide: before: full replan, steps empty for seconds ← BUG
    Note over Guide: now: nothing, unless your quest log changed
    Game->>Guide: you walk into a mine, cave or town
    Note over Guide: before: plan wiped, rebuilt from zero outside ← BUG
    Note over Guide: now: plan kept, "paused"
    Game->>Guide: you walk
    Note over Guide: before: steps re-sorted every 3 s ← BUG
    Note over Guide: now: steps stay fixed
    Game->>Guide: quest accepted, progressed, done or abandoned
    Guide->>Guide: recalculate; old steps stay visible until the new route is ready
```
