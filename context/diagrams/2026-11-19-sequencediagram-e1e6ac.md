# sequenceDiagram

Captured 2026-11-19T15:26:33.252Z - run r-20261119-162136-55c2

```mermaid
sequenceDiagram
    participant Alt as Character of the other faction
    participant Cache as QuestSharingCache (shared by all characters)
    participant You as Your Alliance character
    Alt->>Cache: first full scan saves "mapSearchNPCs"<br/>(only NPCs friendly to its faction)
    You->>Cache: later session reads the saved list
    Cache-->>You: list has no Alliance NPCs ← BUG
    You->>You: "fish" in Hillsbrad → 0 pins
```
