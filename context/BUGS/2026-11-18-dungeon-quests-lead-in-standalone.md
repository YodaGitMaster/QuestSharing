# 2026-11-18 — Dungeon quests: "go and speak to X" lead-in quests treated as standalone / still offered

**Status**: solved (mock tests only; not checked in the game against the user's DB)
**Severity**: medium
**Tags**: DungeonQuests.lua, chain, lead-in, breadcrumb, nextQuestInChain, breadcrumbForQuestId, breadcrumbs, availableUntilCompleted, "Standalone quest", Seeking Caitlin, talk only

## Symptom
- Observed: a quest that only sends you to another quest (user's example "Seeking Caitlin ...", "go to Menethil Harbor and pick up the dungeon quest") was missing from the dungeon's list or shown as "Standalone quest", and not marked as unavailable after the quest it leads to was done.
- Expected: it is listed with the dungeon quest it points to as a chain (nested above it), and ticked/greyed "Not needed" once the later quest is done.
- Where: `QuestSharing/DungeonQuests.lua` (`D.scan` link/include, `chainLabel`).
- Environment: Questie data. Classic data has ~110 quests whose `nextQuestInChain` target does NOT list them as a prerequisite (optional lead-ins); newer DBs also use `breadcrumbForQuestId` (27) / `breadcrumbs` (28) / `availableUntilCompleted` (33). Questie's own meaning of `nextQuestInChain`: "if the next quest is active/finished, this quest is not available any more".

## Reproduction
- Quest 30 `nextQuestInChain=31`, quest 31 is a dungeon quest with no `preQuest*` -> 30 was not in the dungeon list. Test: `LEADIN` data in `tests/test_dungeon_quests.py`.

## Root cause
- `include()` only walked *backwards through preQuestSingle/Group* from dungeon quests, so lead-ins that exist only as `next`/breadcrumb pointers on the earlier quest were never pulled in; breadcrumb and availableUntil fields were never read.
- Trap category: assumed-vs-verified data model (only one of several ways the source encodes "leads to").

## Methodology (reusable)
1. Found the data key meanings in the QuestieDB source (`src/meta/questMeta.lua`) instead of guessing; parsed `data/Classic/classicQuestDB.lua` with lupa to count `next` links without a matching prerequisite (110 of 1,431).
2. The exact quest name from the user is not in the bundled Classic/TBC data (only NPC "Caitlin Grassman"), so the fix is generic for the whole class of links.
3. Fix pattern: record every "leads to" pointer as a required chain link, remember which ones are *not* real prerequisites (`chainLead`), and let `include()` pull those into the dungeon with role "Lead-in" (label "optional lead-in").

## Fix
- Files changed: `QuestSharing/DungeonQuests.lua`, `tests/test_dungeon_quests.py`, CHANGELOG, README.
- Workaround? no.

## Verification
- 3 new tests (lead-ins listed, nested above their quest, greyed/ticked after the later quest is done, real prerequisites not mislabelled). Full suite green.

## If it shows up again
- Ask for the quest ID and dump its raw record (`/qs questie` or `QuestDB.Get(id, key)` for keys 12,13,22,27,28,33,36). If none of those point at the other quest, the data has no link and nothing can be derived.
- Not handled on purpose: `disabledByQuest` (only while the other quest is in the log), `exclusiveTo`, `parentQuest`.
