# flowchart

Captured 2026-11-20T11:10:11.963Z - run r-20261120-120959-eea8

```mermaid
flowchart LR
    Engine[WoW engine] -->|draws blips itself| Minimap[Minimap dots]
    Addon[Addon] -.->|no API to recolor one dot ← BLOCKED| Minimap
    Addon -.->|UnitPosition = nil for enemies ← BLOCKED| Engine
```
