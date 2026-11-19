# flowchart

Captured 2026-11-19T15:24:29.565Z - run r-20261119-162030-ccf6

```mermaid
flowchart LR
    K["Item key (e.g. Q)"] -->|SetBindingClick| B["QuestSharingItemButton<br/>always hidden now"]
    B --> U[Uses the nearest quest's item]
    X["Icon below the middle of the screen"] -. removed .-> B
```
