# sequenceDiagram

Captured 2026-11-19T10:22:49.765Z - run r-20261119-112237-1267

```mermaid
sequenceDiagram
    participant You
    participant Game
    participant Addon as Quest Sharing (Lua memory)
    You->>Game: enter or leave a dungeon (loading screen)
    Game->>Addon: PLAYER_ENTERING_WORLD / ZONE_CHANGED events
    Note over Addon: Lua memory is not wiped, so all 7 catalogues stay loaded
    Addon-->>You: reopened windows are instant
    You->>Game: /reload or log out
    Game->>Addon: wipes all addon memory
```
