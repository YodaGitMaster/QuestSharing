# sequenceDiagram

Captured 2026-11-18T09:41:12.973Z - run r-20261118-103648-37b6

```mermaid
sequenceDiagram
    participant Timer as ns.after timers (Core.lua:215)
    participant Tick as TravelMap tick()
    participant Draw as T.draw()
    Timer->>Timer: table.remove(timer) BEFORE running it
    Timer->>Tick: xpcall(tick)
    Tick->>Draw: T.draw()
    Draw--xTick: throws (map API change, nil child, ...)  ← BUG
    Note over Tick: ns.after(..., tick) never reached
    Note over Timer: ticker is gone until /reload; only WORLD_MAP_UPDATE can redraw
```
