# Lua 5.1 speed review prompt

Paste the block below into a fresh Claude session opened in this repo.
Leads in the LEADS section were found by grep on 2026-11-19 and are NOT verified.

```text
ROLE
You are a Lua 5.1 performance reviewer for a World of Warcraft Classic addon
(Interface 16001, folder QuestSharing/). Goal: find where the code can run faster
or make less garbage, using only the main optimization strategies below.
Review first; change nothing until I approve a list.

SCOPE
- Files: QuestSharing/*.lua, load order in QuestSharing/QuestSharing.toc.
- Runtime is Lua 5.1 inside the game: no LuaJIT, no 5.2+ features, a ~16 ms frame,
  and a garbage collector that stalls the frame when much garbage is made.
- Keep behaviour identical. Speed only, not style, not features, not memory layout
  for its own sake.
- Other sessions edit this tree. Re-read a file right before you cite or change it.

STEP 1 - FIND THE HOT PATHS (do this before judging any loop)
A slow loop that runs once when a window opens matters less than a cheap one that runs
every frame. Rank each code path by how often it runs:
  A. every frame: SetScript("OnUpdate"), the timer pump in Core.lua (ns.after),
     QuestGuidance hud update, QuestPlanner panel OnUpdate, Quick.lua ring, Menu.lua.
  B. frequent events: QUEST_LOG_UPDATE, BAG_UPDATE(_DELAYED), UNIT_*, NAME_PLATE_*,
     GET_ITEM_INFO_RECEIVED, WORLD_MAP_UPDATE, tooltip hooks (OnTooltipSetItem etc.),
     CHAT_MSG_*, typing in search boxes (OnTextChanged).
  C. per-id inside a catalogue scan: DataWork jobs in DungeonQuests, Rewards, VendorMap,
     QuestPlanner, QuestOptimizer, TrainerIndex, GatherSources (run over thousands of
     Questie ids).
  D. once per open or per command.
List the A/B/C paths you found with file:line. Review A, B and C. Skip D unless a
single D call is clearly slow (for example O(n^2) over a whole catalogue).

STEP 2 - CHECK EACH HOT PATH AGAINST THESE STRATEGIES (only these)
1. Dictionary instead of a search. A loop that scans a list to find or test one value
   (`for _, x in ipairs(list) do if x == v`) -> a set/map keyed by that value, built once.
   Also reverse indexes: if code loops over all A to find the ones linked to B, keep B -> {A}.
2. Fewer loops / fewer passes. Two or more passes over the same list that could be one;
   nested loops that are O(n*m) where a map makes them O(n+m); a sort done on every
   refresh when the order did not change; work redone each keystroke that the previous
   keystroke already did.
3. Hoist invariant work out of loops. Anything computed inside the loop that does not
   depend on the loop variable: string.lower of the query, splitting a query into words,
   GetTime(), ns.db lookups, enum tables, building the same pattern string.
4. No new tables or closures inside hot loops. `ipairs({a, b})`, `{...}` literals,
   `function() ... end` created per iteration, string keys built by `..` per item.
   Reuse a table (wipe it) or unroll the two cases.
5. Queues without table.remove(t, 1). It shifts the whole array: O(n) per pop. Use a
   head index (or a ring buffer) when the list can grow past ~20 items or pops in a loop.
6. String building. `s = s .. x` in a loop is O(n^2) garbage: collect parts and
   table.concat once. string.format inside a per-frame path: only when the text changed.
7. Cache with invalidation. A pure, repeated read (Questie field, GetItemInfo,
   C_Map.GetMapInfo, a computed distance) -> memo table, cleared on the event that makes
   it stale, bounded in size. Name the invalidating event; no event = no cache.
8. Throttle and coalesce. A handler that does full work on every event of a burst
   (BAG_UPDATE fires per slot, QUEST_LOG_UPDATE several times per change) -> mark dirty
   and do the work once on the next timer tick. Per-frame work that only needs ~10 Hz ->
   accumulate dt.
9. Local aliases in the hottest loops only. `local find = string.find`, upvalue for
   ns.db / a module table, in A or C paths. Not worth doing anywhere else; do not report
   it for D paths.
Do not report: micro-style changes outside hot paths, rewrites of algorithms that are
correct and not hot, or anything that changes what the player sees.

STEP 3 - PROVE IT (no finding without this)
- Quote the exact lines (file:line).
- State how often it runs (A/B/C) and the size of n in practice (for example: Questie
  has ~10k quests, ~20k npcs, ~25k items; the quest log has <= 25 entries; a bag has
  <= 36 slots). A small n with a rare call is not a finding.
- Give current vs proposed cost (big-O or "allocs per call").
- For every C-path or A-path finding, measure: a micro-benchmark in Lua 5.1 via lupa
  (`/tmp/qs-test-env/bin/python`, `from lupa.lua51 import LuaRuntime`, os.clock over
  10k-100k iterations), old vs new code side by side. Report the two timings.
  If you cannot measure, mark it UNMEASURED.

OUTPUT (review pass)
One table, ranked by (how often it runs) x (measured or estimated saving), biggest first:
| # | file:line | path A/B/C | strategy # | now | proposed | measured old -> new | risk |
Then, per row, a 2-4 line before/after sketch. End with the list of hot paths you
checked and found nothing in, so I know they were looked at.
Cap the table at the 15 most valuable findings.

FIX PASS (only after I approve row numbers)
- One finding per change, minimal diff, no unrelated cleanup.
- Same behaviour: run the related test files as scripts
  (`/tmp/qs-test-env/bin/python tests/test_<name>.py`, each ends with "N/N passed"),
  then every tests/test_*.py. A failing test is a behaviour change: revert or explain.
- Caches added: name the event that clears them, and the size bound.
- Add one CHANGELOG `## Unreleased` line only if the player can notice it (smoother map,
  faster search). Log each chosen trade-off in context/decisions.md.

LEADS (from grep, unverified; check them, do not assume them)
- VendorMap.lua matchesWords (~line 24): lowercases and splits the query on every call,
  and it is called per item name over the whole item catalogue (strategy 3).
- DungeonQuests.lua scan (~line 270 and ~295): `ipairs({r.beforeAny or {}, r.beforeAll or {}})`
  builds two to three tables per quest per pass, and again per include() call (strategy 4).
- DungeonQuests.lua link(): `"Quest "..after` string per edge (strategy 4/6).
- DataWork.lua pump: `table.remove(queue, 1)` per step, up to 2000 steps a slice (strategy 5).
- Core.lua ns.cancel: linear scan of the whole timer list per cancel; timer pump walks
  all timers every 0.1 s (strategies 1/5). Count how many timers live at once first.
- Core.lua:150 / :372, Friends.lua:117, Share.lua:185: table.remove(t, 1) queues (strategy 5;
  likely small n - confirm before reporting).
- Quick.lua:68, Rewards.lua:63, QuestCleanup.lua:140, Panel.lua:204: linear "is it in the
  list" checks (strategy 1; report only if on a hot path).
- 63 table.sort calls across the addon: check which run per refresh or per keystroke (strategy 2).
- QuestPlanner.lua and QuestOptimizer.lua: route building and per-stop distance checks
  (strategies 2/7). These are the largest files; check their inner loops first.
```
