# flowchart

Captured 2026-11-20T09:48:32.411Z - run none

```mermaid
flowchart LR
  H[Home: dungeon cards with loading-screen art] -->|click a card| P[Dungeon page: LFG icon, name, LV, entrance pin]
  P --> Q[Quests: list + parchment page, rewards with hover/compare, XP pills]
  P --> B[Bosses: round portraits, level badges, drops with hover/compare]
  P --> M[Map: client dungeon map, floors, zoom, pan]
  P --> R[Route: get-them-all steps, click = map pin]
  P -->|"< Dungeons"| H
```
