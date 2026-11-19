# sequenceDiagram

Captured 2026-11-19T09:37:30.789Z - run r-20261119-095449-ea8e

```mermaid
sequenceDiagram
    participant User
    participant DQ as DungeonQuests.lua
    participant Work as ns.dataWork
    User->>DQ: first open → D.scan() reads the quest DB once
    User->>DQ: close (f.suspend)
    DQ->>Work: pause the quest scan and the reward scan (nothing is deleted)
    User->>DQ: reopen, any time later
    DQ->>Work: continue the paused scan, or show the list at once
    User->>DQ: Settings → Items & dungeons → "Purge"
    DQ->>DQ: D.purge() → release(); reads again now if the window is open, otherwise on next open
```
