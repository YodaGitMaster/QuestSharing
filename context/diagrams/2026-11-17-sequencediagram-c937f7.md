# sequenceDiagram

Captured 2026-11-17T19:30:44.496Z - run r-20261117-202156-ec45

```mermaid
sequenceDiagram
    participant User
    participant D as DungeonQuests.lua
    participant Work as DataWork.lua
    participant Q as QuestieDB
    User->>D: open Dungeon quests
    D->>Work: start scan (about 18 reads per quest)
    Work->>Q: 2 ms per 100 ms: ~40 s to 3½ min for 4–8k quests, list empty  ← BUG
    User->>D: close / Esc / other tab while waiting
    D->>Work: cancel, so the next open starts from 0  ← BUG
    Note over D,Work: Fixed: 8 ms per 100 ms while the tab is visible; hiding pauses, reopening resumes
```
