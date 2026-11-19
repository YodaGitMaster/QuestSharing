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

---
## Addendum 2026-11-18 — recurred: user's "Seeking Caitlin" still offered for the dungeon
- What happened: after the first fix the user still saw Seeking Caitlin as a quest to retrieve (gold border, not greyed) although the dungeon quest was done.
- Why the previous fix did not hold (probable, NOT verified on the user's data): `finished()` only propagated through *required* links; a lead-in that is one of several `preQuestSingle` alternatives of the dungeon quest was `required=false`, so it never turned grey. The quest itself is not in the Forever/TBC QuestieDB I could fetch (no "Caitlin" quest), so the real record was never seen.
- New approach: also treat a quest as finished/not needed when ALL quests it leads to are done (`count>0 and everyDone`). Two tests with an "any of" pair. Details panel now prints "- done" next to chain neighbours.
- Result / new status: workaround-level fix pending user confirmation (status stays open until the user sees it in game). If still wrong: need the quest ID (right panel "(quest NNN)") of Seeking Caitlin and of the dungeon quest, plus whether the dungeon quest shows a green check.

---
## Addendum 2026-11-18 (2) — real root cause found: Questie has NO link for Seeking Caitlin
- Real record (QuestieDB master `src/corrections/Forever/generated/foreverBaseQuest.lua`): quest 95737 "Seeking Caitlin": startedBy {{3970}} (Llana), finishedBy {{1480}} (Caitlin Grassman, Menethil Harbor), objectivesText "Speak with Caitlin Grassman in Menethil Harbor.", zoneOrSort EXCAVATION_SITE_WETLANDS, NO preQuest/next/breadcrumb fields. Wowhead shows no series either. The quest it leads to, 95647 "Lost in the Thicket Things", is startedBy {{1480}} in the same zone, also without any link. IDs 9xxxx are Forever-only quests; they are not in `data/Forever/foreverQuestDB.lua` of the data branch, only in `src/corrections/Forever/`.
- Why the earlier fixes did not hold: they all followed link fields that do not exist for this quest.
- Methodology: fetched the user's quest page (wowhead forever/quest=95737), then grepped the QuestieDB repo tarball (codeload.github.com/Questie/QuestieDB tar.gz) for the quest id to read the real record and the quests started by the same NPC.
- Fix: `D.scan` infers a lead-in: talk-only (no objectives/trigger/items/event), no own prerequisite or next, finishes at an NPC (not its own starter) who starts dungeon quest(s) of the same area, same race mask, with no prerequisite -> `link(seed,t,required=(one target),lead)`. Panel shows "guessed (Questie has no link)".
- Status: solved in mock tests; verify in game with quest 95737 / 95647.
- If it recurs: check other NPC-based false positives (an NPC who ends a talk-only quest and starts an unrelated dungeon quest).

---
## Addendum 2026-11-19 — scan of the real Forever data, one false positive fixed
- Scan script (`/tmp/leadscan/scan.py`, rerun on a QuestieDB master tarball): base `data/Forever/foreverQuestDB.lua` (4,244) + Forever-only `src/corrections/Forever/generated/foreverBaseQuest.lua` (1,607) = 5,851 quests; dungeon areas from `support/Forever/Zones/dungeons.lua` (231 ids). Dungeon membership approximated by `zoneOrSort` only (the addon also uses objective spawns, so in-game counts can be a bit higher).
- Results: A) `nextQuestInChain` lead-ins not listed as prerequisite: 110 total, 9 into a dungeon quest (e.g. 2041 Speak with Shoni -> 2040 Underground Assault, 2861 Tabetha's Task -> 2846 Tiara of the Deep). B) breadcrumb fields: 0. C) no link, inferred from the NPC: 8 before the fix, 6 after (95737 Seeking Caitlin, 95663 Dragonmaw Rumors, 4 Alterac Valley quests).
- False positive found: 95795 "Fallen in the Fen" (finishedBy Dorin Songblade, NO NPC starter; it is the chain's last "return" step) was paired with 95772 "Songblade Search" (started by Dorin) -> would have greyed the final step once Songblade Search was taken. Fix: an inferred lead-in must have an NPC starter (`#seed.starters>0`). Side effect: 84555 Nostro's Compendium (no NPC starter) is no longer inferred; accepted, conservative.

