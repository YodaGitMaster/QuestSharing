# stateDiagram-v2

Captured 2026-11-19T09:26:48.629Z - run r-20261119-095449-ea8e

```mermaid
stateDiagram-v2
    [*] --> Grey : enemy nobody is fighting
    Grey --> Coloured : the fight starts (red / orange / green)
    Coloured --> White : lowest next to you, in a fight
    White --> White : another one only 1-9 points lower, the mark stays
    White --> Coloured : another is 10+ lower, or you grabbed it (100 %)
```
