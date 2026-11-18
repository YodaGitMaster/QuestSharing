# flowchart

Captured 2026-11-18T08:32:39.895Z - run r-20261118-092642-81fc

```mermaid
flowchart TD
    Scan[D.scan link] --> Idx[chainPrev / chainNext: required links]
    Idx --> Fin[finished: done itself, or a required later step is done]
    Fin --> Tree[chainTree: indented bullets, green check]
    Tree --> Panel[right panel: plain yellow]
```
