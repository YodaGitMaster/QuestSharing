# flowchart

Captured 2026-11-21T03:28:22.875Z - run r-20261121-041134-dd71

```mermaid
flowchart LR
  S((Resolver built)) --> RV[Review resolver] -->|changes| FX[Fix] --> RV
  RV -->|approved| I[Integrate, render, docs] --> F[Final review] --> E((done))
```
