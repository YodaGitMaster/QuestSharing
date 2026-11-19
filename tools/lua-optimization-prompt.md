# Lua 5.1 speed optimization prompt (review + apply)

Paste the block below into a fresh Claude session opened in this repo.
It differs from `lua-performance-review-prompt.md` in that it applies the safe fixes itself.
First run: 2026-11-19 (results in context/insights.md and context/decisions.md).

```text
ROLE
You optimize the speed of a World of Warcraft Classic addon written in Lua 5.1
(Interface 16001, folder QuestSharing/). You find hot code, prove a change is faster,
apply it with identical behaviour, and keep every test green.

RUNTIME FACTS
- Lua 5.1 inside the game: no LuaJIT, no 5.2+ syntax (no goto, //, bit ops, table.unpack).
- ~16 ms per frame; garbage collection stalls the frame, so fewer new tables/strings matter.
- Questie catalogue sizes: ~10k quests, ~20k npcs, ~25k items. Quest log <= 25 entries,
  bag <= 36 slots, party <= 5.

STEP 1 - HOT PATHS
Rank code by how often it runs and only optimize A, B, C:
  A. every frame: OnUpdate scripts, the Core.lua timer pump (ns.after), DataWork pump.
  B. frequent events: QUEST_LOG_UPDATE, BAG_UPDATE*, UNIT_*, NAME_PLATE_*,
     GET_ITEM_INFO_RECEIVED, WORLD_MAP_UPDATE, tooltip hooks, OnTextChanged in search boxes.
  C. per-id work inside catalogue scans (DataWork jobs in DungeonQuests, Rewards,
     VendorMap, QuestPlanner, QuestOptimizer, TrainerIndex, GatherSources).
  D. once per open/command: skip unless one call is O(n^2) over a catalogue.

STEP 2 - STRATEGIES (only these)
1. Dictionary/set instead of a linear search; reverse index instead of "loop all, filter".
2. Fewer loops: merge passes, break O(n*m) nesting with a map, no re-sort when unchanged.
3. Hoist loop-invariant work (lowercasing/splitting a query, GetTime, ns.db, enum lookups).
4. No new tables/closures inside hot loops (ipairs({a,b}), {...}, function() end per item).
5. No table.remove(t, 1) for queues that grow or pop in a loop: head index or ring buffer.
6. table.concat instead of s = s .. x in loops; no string.format per frame if text unchanged.
7. Memoize a pure repeated read, cleared on a named event, with a size bound.
8. Throttle/coalesce bursts of events into one update on the next tick.
9. Local aliases (local find = string.find) only inside A/C loops.

STEP 3 - PROVE, THEN APPLY
For each candidate:
  a. Quote file:line, path class (A/B/C), realistic n.
  b. Benchmark old vs new in Lua 5.1 with lupa (/tmp/qs-test-env/bin/python,
     from lupa.lua51 import LuaRuntime; os.clock over enough iterations for >= 50 ms).
  c. APPLY only if: measured saving >= 20 % on that code, behaviour identical, the diff is
     small and local. Otherwise REPORT ONLY (with the reason).
  d. After each applied change: run that module's tests as scripts
     (/tmp/qs-test-env/bin/python tests/test_<name>.py -> "N/N passed").
     A failure means behaviour changed: revert that change.
Finish with every tests/test_*.py run once, sequentially (parallel runs time out).

RULES
- Other sessions edit this tree: re-read a file right before editing it; edit only the
  lines of the finding; never revert someone else's change.
- No refactors, renames, or style changes bundled in. Comments only for a non-obvious why.
- Never change what the player sees, what is sent to chat, or saved-variable shapes.

OUTPUT
1. Table: | # | file:line | A/B/C | strategy | old -> new (measured) | APPLIED / REPORT ONLY + reason |
2. Hot paths checked with nothing worth changing.
3. Test result: files and total checks passed.
4. Update context/: decisions.md (what was applied and why), insights.md (measured
   numbers), state.md (status line). CHANGELOG only if a player could notice it.
```
