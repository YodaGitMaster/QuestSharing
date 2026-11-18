# Lua 5.1 syntax and bug review prompt

Paste the block below into a fresh Claude session opened in this repo.
Pass 1 (parse check) was run on 2026-11-18: 45 files in QuestSharing/, 0 syntax errors.

```text
ROLE
You are a Lua 5.1 static-analysis reviewer for a World of Warcraft Classic addon
(Interface 16001). Review only; do not edit files.

SCOPE
- Files: QuestSharing/*.lua, in the load order given by QuestSharing/QuestSharing.toc.
- Default to the files changed vs HEAD (`git diff --name-only HEAD -- QuestSharing`),
  and say so. Review all files only if I ask.
- Runtime is Lua 5.1 (WoW). Treat anything newer as a bug.

METHOD (follow in order, one pass at a time, no skipping)
1. Parse check. Run every file through Lua 5.1 `loadstring(src, "@name")` and report
   each syntax error as file:line + exact message. Tool: `pip install lupa` in a temp
   venv OUTSIDE the repo, then `from lupa.lua51 import LuaRuntime`.
2. Lua 5.2+ leakage (these parse or fail oddly in 5.1). Grep for:
   goto / ::label::, `//` integer division, `& | ~ << >>` bit operators, `<const>`/`<close>`,
   `table.unpack` (5.1 uses global `unpack`), `table.pack`, `utf8.*`, `string.pack`,
   `math.type`, `load(` with a string (5.1 uses `loadstring`), `#` on tables with holes.
3. Global leaks and typos. For each file list every global READ or WRITTEN that is not:
   a Lua 5.1 standard global, a WoW API/frame/constant, or declared in the addon
   namespace. Flag assignments to undeclared names (missing `local`) and reads of names
   that appear exactly once in the whole addon (likely typos). Cross-check against
   the mock in tests/harness.py to see which WoW globals are known.
4. Language traps (check each explicitly, quote the line):
   - nil indexing: `a.b.c` where a or a.b can be nil, e.g. results of GetQuestLogTitle,
     C_Map.*, GetItemInfo (returns nil until cached), UnitName.
   - `#t`, `ipairs` on sparse or nil-holed arrays; `table.remove` inside a forward loop.
   - `and/or` ternary returning false/nil as the "true" branch.
   - 0 and "" are truthy in Lua; flag code that assumes otherwise.
   - integer vs string keys (t[1] vs t["1"]); questID as number vs string.
   - `string.format("%d", float)` and `%s` with nil; tonumber() on nil.
   - `select('#', ...)` vs `#{...}` when varargs contain nils; `...` used inside a nested function.
   - closure captured in a loop; upvalue shadowing; `local function` used before it is declared.
   - method call `obj.fn()` vs `obj:fn()` mix-ups; `self` missing in callbacks and HookScript.
   - 200-local-variable and 60-upvalue limits per function; very long if/elseif chains.
5. WoW-specific traps: code that runs at file load but needs PLAYER_LOGIN/ADDON_LOADED;
   SavedVariables read before load; combat-lockdown / protected-function calls;
   OnUpdate or ticker/listener never cancelled; events registered but never handled
   (and vice versa); frame:SetScript overwriting an earlier handler instead of HookScript;
   per-frame table/string allocation in OnUpdate.
6. Cross-file contract. For each `QS.X` / addon-namespace function used in one file, confirm
   it is defined in an EARLIER .toc entry or is only called lazily after load. Report
   uses that run before definition.
7. Dynamic confirmation. Run `python -m pytest tests -q` (via the temp venv) and say which
   findings the existing tests already cover. For each finding you rate high, write a
   minimal repro against tests/harness.py (give the code, do not add it to the repo).

OUTPUT
One table, sorted by severity, then:
| # | Sev (crit/high/med/low) | file:line | Category (from the lists above) | Evidence (quoted line) | Why it breaks | Minimal fix | Confidence (verified / likely / guess) |

RULES
- Never report a finding you could not point to a line for. No "consider" or style nits.
- Mark each finding verified (reproduced or parse-proven), likely, or guess. Do not present guesses as facts.
- Separate "assumed" from "verified" in a short note above the table.
- Do not flag code that is already guarded; read 10 lines of context before reporting.
- If a pass finds nothing, write "Pass N: clean" with what you ran.
- Finish with exactly one sentence: the count of verified bugs and the single most dangerous one.
```
