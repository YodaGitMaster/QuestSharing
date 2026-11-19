# sequenceDiagram

Captured 2026-11-19T08:38:35.541Z - run r-20261119-093539-cfa3

```mermaid
sequenceDiagram
    participant You
    participant L as LFGInvite.lua
    participant Lia as Lia (listed healer)
    You->>L: Find
    L->>Lia: group invite
    L->>Lia: /w "Hi! I invited you to my group for The Deadmines as healer."
    Note over L: whisper only after a successful invite, through the existing chat guard
```
