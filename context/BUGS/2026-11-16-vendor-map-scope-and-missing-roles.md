# 2026-11-16 — Vendor map scope and missing roles

**Status**: solved
**Severity**: medium
**Tags**: VendorMap.lua General Goods search suggestions missing sellers Item.vendors Npc.subName map scope

## Symptom
- Observed: user reports map/search feels inconsistent: choosing General Goods should show all matching sellers on a non-world map, but some searches seem not to find things and icons do not make the result clear.
- Expected: displayed-map scope shared by suggestions and pins; all matching known NPC titles; explicit item-search feedback.
- Where: `QuestSharing/VendorMap.lua`; read-only data from `Questie.lua`.
- Environment: WoW modern/classic API paths mocked under Lua 5.1. Exact live user map/item example requested but not supplied during work; native game unavailable.

## Reproduction
- Fixture: two General Goods NPCs in Elwynn, only one referenced by an item's vendors list; Tailor plus Silken Thread in Westfall; a local Trade Supplies NPC selling General Goods Crate.
- Search General Goods: unlinked NPC missing. Choose the role suggestion: item-name match also adds the Trade Supplies NPC.
- Type `ta` in Elwynn: remote Tailor suggested despite no local pin.
- Type Silken Thread in Elwynn: immediately offers nearest remote seller instead of an explicit local zero.
- Baseline focused suite: 4/18 pass after correcting the test's Lua proxy equality lookup; 14 failures reproduce behavior gaps.

## Root cause
- Vendor index was derived exclusively from reverse item seller links; NPC titles with no link never entered it. Suggestions searched the entire index, pins projected onto the displayed map, and selected suggestion `kind` was discarded before matching. Default zero-local-result behavior automatically used remote fallback.
- Trap categories: data-shape/coverage mismatch; scope mismatch; stale/cancelled async work could also reset a replacement scan's loading state.

## Methodology (reusable)
1. Read continuity/decisions and existing map-related bug reports before diagnosing; confirm actual index source and projection code rather than assume missing icons are rendering failures.
2. Use deliberately different item-link and NPC-title coverage. An NPC whose role and coordinates exist but is absent from Item.vendors distinguishes indexing omissions from provider coordinate gaps.
3. Put matching names in a different map and collide a category phrase with an item name; exercise the real suggestion click to expose scope and semantic-kind loss independently.
4. Share the validated map projection for suggestions/pins; enumerate NPC roles independently; carry role/item intent through click, Tab and Enter. Keep explicit item seller links authoritative for item searches.
5. Exercise >120 records and disable/re-enable while callbacks remain queued. Old-generation callbacks must return without modifying the new scan's loading state.
6. Inspect shared UI helpers: Style buttons display custom `label` text and require `SetLabel`, not native `SetText`; tests check the visible label, not just a mock field.

## Fix
- Files changed: `QuestSharing/VendorMap.lua`, `tests/test_vendor_map.py`, README/changelog and continuity notes.
- Three cancellable 120-record stages: item links, NPC titles, and seller metadata/spawns. NPC-only catalogues support role searches; item-only catalogues retain previous partial coverage.
- Map-local suggestions and pins share projection/coordinate validation; selected roles exclude item-name matches and selected items match the exact item name.
- Panel names displayed map and reports query/location count. Hover repeats query; missing seller links explain vendor-only coverage. Elsewhere explicitly requests nearest same-continent fallback; separate Waypoint click places it. Map/query changes restore local scope.
- Commit / PR: local/uncommitted; no publication requested.
- Workaround? No; decisions recorded in `context/decisions.md`.

## Verification
- Focused: 30/30 checks, modern and classic paths, including item-only/NPC-only providers, parent-map aggregation, malformed coordinates, clear, Escape, kind preservation, map changes, explicit remote action, async completion and cancellation.
- Full repository scripted runner: 37/37 suites, 1,360/1,360 checks.
- `luac -p QuestSharing/VendorMap.lua` and `git diff --check`: pass.
- Original mechanisms reproduced and corrected in Lua harness. Native rendering, actual installed Questie coverage and user's exact live search remain unverified.

## If it shows up again
- Check whether installed Questie exposes NPC/item enumeration, NPC subName/spawns and explicit Item.vendors links; never infer that missing item links prove an item cannot be bought.
- Compare displayed UI map with spawn area-to-map mapping; inaccessible/dungeon/invalid coordinates cannot produce pins.
- Reproduce with actual suggestion kind and compare typed query vs selected item/category. Check map-change refresh and stale scan callbacks separately.
- Other addons' map icons are outside VendorMap's owned pin pool; clearing this search only clears its own pins.

---
## Addendum 2026-11-17 — Clarified generic vendor queries
- What happened: user specifies all maps: `vendor` should highlight every local vendor; `general vendor` should highlight local general vendors. The earlier test set verified title matching but never tested these literal user phrases.
- Why the previous fix did not hold: map scoping was correct, but matching still required every query word to occur literally in a title/item. General Goods does not contain `vendor`; `general vendor` therefore failed. Untitled NPCs with a vendor flag were absent, while treating every title as a seller would incorrectly include trainers and captains.
- Reproduction: add five workflow tests for generic nouns, category+noun, map switches, suggestions and older provider fallback; baseline 30/40 checks pass, with all ten new cases failing across modern/classic.
- New approach + methodology: interpret vendor/seller/merchant nouns as seller intent, with remaining words narrowing the role; retain that intent in suggestion clicks/Enter. Independently verify seller eligibility from Item.vendors, provider NPC vendor bit, or recognizable English merchant role words. Use a deliberately different vendor bit (1024) and a mixed-bit flag in fixtures to catch guessed constants and equality-only bit tests; include titled non-sellers and untitled sellers.
- Provider contract: verified `npcFlags` field in https://github.com/Questie/QuestieDB/blob/master/src/meta/npcMeta.lua and active-flavor flags/RequireContract(4) in https://github.com/Questie/QuestieDB/blob/master/docs/api.md#active-class-keys-and-npc-flags . Unsupported flags retain link/title coverage without guessing a flavor's bit.
- Extra checks: suggestion selection must not admit General Commander; a provider rejecting contract 4 must degrade cleanly; explicit item searches can still contain vendor words.
- Result / new status: solved locally; focused 46/46, full 37 suites / 1,376 checks; Lua syntax and diff checks pass. Pins still use displayed-map projection; native WoW and actual provider coverage unverified. No release/push requested.

---
## Addendum 2026-11-17 — Druid found, Paladin Trainer missing
- What happened: user reports Druid Trainer appears but typing Paladin Trainer does not find it. Asked displayed map, whether suggestions/pins/both are missing, and whether installed addon is v0.4.18; answers pending.
- Why the previous fix may not have reached the user: local vendor-search work is still unpublished; v0.4.18 retains the item-linked-only index. The runtime contains no class-specific exclusion.
- Reproduction: identical fixture with Druid Trainer in item seller links and Paladin Trainer only in NPC titles/spawns. Substitute published `git show v0.4.18:QuestSharing/VendorMap.lua` through read-only Path.read_text patch in a temporary harness process. Release returns Druid NPC 1 twice, Paladin absent; current local returns Druid NPC 1 twice and Paladin NPC 2 once. Partial `paladin tra` additionally produces a local suggestion only in current code.
- New approach + methodology: compare installed/released code against unshipped changes before assuming another algorithm bug; reproduce identical provider records/maps and vary only module source. Keep scope local and use provider NPC enumeration for trainers independent of item links.
- Verification: three tests on both client styles cover exact Druid/Paladin queries plus Enter, unlinked Paladin suggestion/click/waypoint, and removal when browsing a different zone. Focused suite 52/52 passes. No new runtime changes; last full suite was 37 files / 1,376 checks before these six additional checks.
- Result / new status: known release mechanism addressed by existing local fix; user's exact live cause remains unverified until map/version/data are confirmed. Do not present this as shipped or assume every map has a Paladin Trainer.

---
## Addendum 2026-11-17 — Flexible profession and role wording
- What happened: user asks whether `skinner trainer` finds a trainer; reproduced no match against Skinning Trainer on both API styles, while `skinning trainer` and `skin trainer` matched. User explicitly requests elasticity.
- Additional live context: user confirms Stormwind capital and installed v0.4.17. A read-only substitution of actual v0.4.17 module also reproduces item-linked Druid/unlinked Paladin asymmetry; current local NPC indexing finds both. Exact installed Questie records remain unverified.
- Why earlier matching did not cover this: independent substring checks recognized partial spelling, not profession synonyms, plurals, punctuation or misspellings.
- New approach + methodology: normalize known English worker/profession/trainer aliases and plural/punctuation/stop words into cached NPC role words, shared between search and suggestions. Only if no literal/alias role or item pin exists on displayed map, allow a single insertion/deletion/replacement/adjacent swap across role tokens (ASCII words >=5 letters). Compare reverse worker-name forms too so `skiner` can resolve via `skinner` -> Skinning. Keep raw title labels and explicit item matching unchanged.
- Priorities: exact local role/item matches suppress approximate pins; remote exact results cannot suppress local fallback. Exact suggestions rank first. Generic seller nouns accept a small typo while retaining seller-only eligibility and map filtering.
- Reproduction before implementation: 56/64 checks passed; failures included worker-name aliases, plurals/punctuation and misspelled class/trainer words. Negative boundary checks are mandatory to catch overly broad matches.
- Verification: focused 76/76 across both API paths; full 37 suites / 1,406 checks. Tests cover ten professions, typo edits/swaps, alias typos, generic vendor typo semantics, suggestion rank/click, local-vs-remote priority, exact item preservation, non-ASCII literal tokens, short/unrelated queries and map changes. Lua syntax and whitespace checks pass.
- Result / new status: solved locally; not released or installed into user's v0.4.17. Native UI/provider coverage still needs in-game validation. This is bounded role matching, not arbitrary natural-language understanding.

---
## Addendum 2026-11-17 — Barrens report on previous version
- What happened: user reports no results for `vendor` in the Barrens and confirms using a previous version.
- Methodology: substitute actual tagged VendorMap sources into the same read-only Lua harness fixture, varying only module source; compare generic `vendor` pins on modern/classic paths.
- Evidence: v0.4.17 = 0 pins; v0.4.18 = 0 pins; current local = 5 pins on both API styles. Current focused suite passes 76/76. This confirms the unshipped generic-query fix addresses the reproduced release behavior; it does not verify actual Barrens provider records.
- Delivery: existing `dist/QuestSharing-preview-2026-11-17.zip` contains a byte-identical current VendorMap; archive SHA256 `65c94ab8fa1d8cc2a38eb83cdafb721de25269e15788d9be48f5988ba98be1b4`. No new code, install, push or release performed.
- Result / new status: fixed in local preview; old releases still reproduce the search failure; native game verification remains pending.
