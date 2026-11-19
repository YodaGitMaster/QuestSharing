# sequenceDiagram

Captured 2026-11-19T08:42:42.642Z - run r-20261119-094226-f8bb

```mermaid
sequenceDiagram
    participant You
    participant L as LFGInvite.lua
    You->>L: Find (solo = 4 free spots)
    L->>L: matches sorted by level: Zed 27 healer, Ann 26 healer, Bram 25 dps, Lia 24 healer
    L-->>Zed: invite + whisper
    L-->>Ann: invite + whisper  %% second healer ← no limit per role
    L-->>Bram: invite + whisper
    L-->>Lia: invite + whisper  %% third healer ← no limit per role
```
