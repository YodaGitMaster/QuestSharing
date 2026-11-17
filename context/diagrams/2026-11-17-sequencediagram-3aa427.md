# sequenceDiagram

Captured 2026-11-17T19:20:12.447Z - run r-20261117-201437-90ab

```mermaid
sequenceDiagram
    participant User
    participant Entry as /qs loot · Settings "Browse drops" · "Instance drops" tab
    participant Loot as Loot.lua L.open/L.scan
    participant UI as EquipmentUI E.show("dungeons")
    participant AL as AtlasLoot ItemDB (LoadOnDemand)
    User->>Entry: open
    Entry->>Loot: ns.loot.open()
    Loot->>UI: build page + show journal   %% "does not open"? ← BUG? (unverified)
    Loot->>AL: LoadAddOn DungeonsAndRaids → GetItemTable per boss
    AL-->>Loot: rows (or nothing → "Install compatible AtlasLoot…")  %% "not working"? ← BUG? (unverified)
    Loot->>UI: item names load 10 per 0.1 s; blue+ gear appears
```
