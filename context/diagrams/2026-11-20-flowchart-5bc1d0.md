# flowchart

Captured 2026-11-20T14:41:29.842Z - run r-20261120-154111-fa74

```mermaid
flowchart LR
    A[slotInfo per bag] --> B[describe: topic/class/quality]
    B --> C[ORDERS sortBy]
    C --> D[T.plan: target slot per item]
    D --> E[sortStep moves]
    C -.new.-> F[group layout: pad to row start]
    F -.new.-> D
```
