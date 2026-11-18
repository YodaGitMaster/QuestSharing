# flowchart

Captured 2026-11-18T11:27:21.868Z - run r-20261118-121722-e833

```mermaid
flowchart LR
    S[Settings > Map: Whose boats, zeppelins and towns to show] -->|all / Alliance / Horde| F[allowed faction]
    F --> Stops[transport pins + lines]
    F --> Tip[dungeon hover: closest town]
    Neutral[neutral = white pin, white line] --> Stops
    Z[pin level canvas+5000, stop above dungeon above trainer] --> Stops
```
