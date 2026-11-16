# 2026-11-16 — Quest planner text overlaps while scrolling

**Status**: solved
**Severity**: medium
**Tags**: QuestPlanner.lua, ScrollFrame, wrapped text, row overlap, unreadable

## Symptom
- Observed: Scrolling the planner makes long quest text overlap and become unreadable.
- Expected: Each row and all wrapped text remain separate while scrolling.
- Where: `QuestSharing/QuestPlanner.lua:showPlanRows`.
- Environment: Quest Sharing, Interface 16001.

## Reproduction
- Display long quest names or multiple pickup lines in the planner, then scroll through the rows.

## Root cause
- Detail strings wrapped to multiple lines, but every row stayed 53 pixels high, started 56 pixels after the previous row, and the scroll child height was calculated from a fixed row size.
- Trap category: type/layout size mismatch.

## Methodology (reusable)
1. Check font-string wrap settings and widths.
2. Compare measured title/detail heights with row spacing and scroll-child height.
3. Derive each row's height from its rendered strings and accumulate row positions for the scroll child.

## Fix
- Files changed: `QuestSharing/QuestPlanner.lua`, test harness and planner UI tests.
- Commit / PR: Quest Sharing v0.4.18.
- Workaround? no.

## Verification
- `tests/test_quest_planner_ui.py` checks wrapped pickup text, row spacing and content height.
- Native rendering remains pending live-client validation.

## If it shows up again
- Recheck the string width/wrap settings, `GetStringHeight()` use, each next-row offset, and final scroll-child height together.
