# 2026-11-16 — Quest recruitment opens an unnecessary editor

**Status**: solved
**Severity**: low
**Tags**: QuestSharing/Menu.lua Adventure.lua Panel.lua World chat recruitment invitation Seek fellow adventurers Ask in chat extra menu composer

## Symptom
- Observed: user wants a simple quest-group question in chat; the recruitment action opens another menu/editor instead.
- Expected: right-click a quest, choose a clear action, then send a short linked question in the chosen game chat.
- Where: Menu.lua row 2 (`Seek fellow adventurers`) -> Adventure.open -> optional composer.
- Environment: reproduced on both modern/classic Lua 5.1 harness paths; native game unavailable.

## Reproduction
- Load the addon with an unfinished quest, open its quest menu and choose row 2.
- Before fix: `Adventure._window().frame.shown == true`; zero chat drafts and zero sent messages.
- Failing workflow test first: `test_menu_action_fills_a_simple_question_without_opening_another_window`, failed on both clients with `the extra invitation editor must not open`.

## Root cause
- The default recruitment entry point explicitly opens the full role-play composer, requiring another Prepare chat step before chat is filled. Existing chat preparation already supports direct insertion.
- Trap category: UI flow / entry-point mismatch; no async, stale quest, or missing chat API failure was required to reproduce it.

## Methodology (reusable)
1. Trace the specific click handler and inspect which destination it calls; distinguish an intentional editor from failed game-chat delivery.
2. Reproduce the clicked quest action on both API paths and inspect composer visibility, chat drafts and sent messages separately.
3. Write a failing user-flow test before modifying runtime; require a linked simple question in chat and no composer creation.
4. Reuse existing preparation/routing validation instead of building a second sender. Keep optional editing reachable separately.
5. Exercise current custom-channel attributes, clicked-versus-nearest quest, draft/duplicate/full-chat boundaries, completed quests, missing APIs, and long UTF-8 titles.

## Fix
- Runtime files changed: QuestSharing/Adventure.lua, QuestSharing/Menu.lua, QuestSharing/Panel.lua.
- Row 2: **Ask in chat to do this quest** -> `Adventure.ask(e)` -> `Anyone need [quest]? Wanna group up?` -> existing `prepare(..., "current")`.
- Current-channel selection is retained; choose World first to use it. Player presses Enter; no automatic public message.
- Optional role-play editor remains under Extra tools and `/qs adventure`.
- Tests: tests/test_adventure.py, tests/test_menu.py, tests/test_features.py; README/changelog/continuity docs updated.
- Commit / PR: local, unreleased.
- Workaround? no.

## Verification
- Adventure tests: 44/44; menu tests: 60/60, modern/classic.
- Full 34-file run covered 1,314 checks; only two old-tooltip assertions failed initially. Updated their expected wording and reran test_features.py: 96/96. All 1,314 checks pass across the run plus affected-suite rerun.
- `git diff --check` clean. Actual game chat focus/channel behavior still needs native client QA.

### Wanted vs. Done
| # | Wanted | Done | Match? |
|---|---|---|---|
| 1 | Direct simple recruitment question | Right-click action fills linked question without composer | ✅ |
| 2 | Use selected chat, including World | Active custom-channel attributes preserved in both API-path tests | ✅ |
| 3 | Keep drafts and other menu actions working | Duplicate/full/stale checks and other menu workflows pass | ✅ |

### Quality
| Check | Pass? |
|---|---|
| Only planned runtime files changed for this fix | ✅ |
| Original extra-editor symptom resolved in reproduced workflow | ✅ |
| No new test failures; actual game unavailable | ✅ |
| Minimal diff; reuse existing prepare rather than refactor routing | ✅ |

## If it shows up again
- Check that Menu.lua row 2 calls Adventure.ask rather than Adventure.open.
- Inspect the active chat box's type/target/channel before assuming text was routed to World.
- Preserve native draft attributes when inserting into an active box; avoid slash-prefix channel changes over existing text.
