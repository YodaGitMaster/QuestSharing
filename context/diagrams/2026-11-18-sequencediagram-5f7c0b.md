# sequenceDiagram

Captured 2026-11-18T21:30:12.932Z - run r-20261118-222955-7f9f

```mermaid
sequenceDiagram
    participant Me as You (Quest Sharing)
    participant LFG as Party finder
    participant Them as Listed healer
    Me->>LFG: search (click)
    LFG-->>Me: name, level, class, roles, no item level
    alt they also run Quest Sharing
        Me->>Them: hidden addon whisper "item level?"
        Them-->>Me: "ilvl 31"
        Me->>Me: ilvl >= your minimum? → invite
    else they are within about 28 yards
        Me->>Them: inspect their gear
        Them-->>Me: their equipped items → average item level
    else neither
        Me->>Me: no item level (skip or invite, your choice)
    end
```
