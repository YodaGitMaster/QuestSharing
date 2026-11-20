# Insights

## 2026-11-20 — Dungeon Journal round 3 (run r-20261120-114959-1c34)
- WoW Forever (build 1.60.1) has no Encounter Journal DB2 tables; retail tables on wago.tools are the only source. Retail descriptions describe the current (Cataclysm-era or later) version: e.g. Shadowfang Keep's text names Lord Godfrey, who is not in the classic dungeon. Review dungeon descriptions for such mismatches before an in-game look.
- Matching journal instances by name alone picks wrong entries (two Blackrock Depths, reworked Uldaman/UBRS). Break ties by boss overlap with a known classic boss list.
- System python lacks SSL certs here; fetch wago.tools CSVs with curl (cache /tmp/ejdata).
- A query helper that defaults its scope to a filter (`filters.dungeon`) silently returns nothing when that filter is 0 ("All dungeons"). Callers that know the scope must pass it.

## 2026-11-20 — Dungeon Journal round 2 (run r-20261120-111056-9c21)
- Rendering the real frame tree to PNG (`tools/render_journal.py`) caught layout bugs the text tests missed: quest filter bar + status + 2 search boxes on the home, a grid narrower than the page, white status strip (colour must be colour x vertex). Render before asking for an in-game look.
- EJ boss art file names are not consistent: some keep spaces (`UI-EJ-BOSS-Mutanus the Devourer`), some drop them (`UI-EJ-BOSS-EdwinVanCleef`). Try every variant via `GetFileIDFromPath`; paths are case-insensitive.
- Hidden filters must not shape a visible view: the home card counts used the dungeon page's hidden `filters.faction`, so counts shrank with no cue. Read only controls visible on the same view.
- Async jumps (item click while the boss list loads) need a pending slot that is cleared on every navigation, or a late answer moves the user to another tab.

## 2026-11-19 — UX review run r-20261119-095449-ea8e (cross-cutting patterns, `context/ux-review-2026-11-19.md`)
- **Settings links rot when tabs are reorganised.** Hard-coded old tab ids/names: 'optional' in `QuestPlanner.lua:1129` (UX-09), 'party' for the finder (UX-05, now fixed), "Optional" tab in `Fishing.lua:222` (UX-07), "Send the message at once" in `Diagnostics.lua:432`, "General > Copy logs" in README. Build every pointer from `ns.settingPath` / tab constants, and add a harness test per "open settings" control that asserts the landing heading.
- **Silent state changes are the most common defect.** Auto messages dropped in Draft mode (UX-01), finish announce gated on a hidden switch (UX-06), toggles answer with an unrelated status dump (UX-08), silent clamping (UX-14, UX-50), silent goal/camp changes (UX-13, UX-21). Rule: every state change prints one line with the Settings label and the effective value.
- **Destructive or overriding actions lack confirmation or protection.** One-click reset incl. custom quick chat (UX-04), Clear records (UX-11), key binding over movement (UX-03), teammate overwriting my waypoint (UX-10). The key setters also unbind the old key before the protected-key check (found by the verifier). Use a second click / StaticPopup and protect what the player set.
- **One feature, many names; one colour, many meanings.** Quest guide has six names (UX-27), goal names differ (UX-28), journal, Party quests window, zone levels, fishing, invitation; gold = selected + to-take + heading, yellow "!" = in-log, grey = source + done, blue chat prefix. A player-facing glossary and a colour/icon legend in `Style.lua` would cover most style findings.
- **Empty or unavailable states look like "no results" and leak developer terms** (UX-16, 19, 20, 26, 31, 40, 43, 51; "bounded search", "enumerable catalogue", "preQuestSingle", "ilvl", "bag 0"). Each empty state should say why in plain words and give one next step.
- Process note: the verifier refuted UX-05 because a parallel session had already applied reviewer #2's party-finder findings to the working tree. Check `git diff` before fixing any review finding.

## 2026-11-19 — In-game rules confirmed by the v0.4.26 report
- `Frame:SetPropagateKeyboardInput()` is protected under combat lockdown (ADDON_ACTION_BLOCKED on every key). Any keyboard frame must skip it in combat and reset it on `PLAYER_REGEN_DISABLED`.
- Unit API values (UnitName, UnitIsPlayer, UnitIsFriend) can be secret in combat on interface 16001: `..` works, but `==`/`~=`/boolean tests raise "attempt to compare ... secret string value". Check `issecretvalue` (guarded) before comparing.
- Classic item data: Trade Goods are 7/0 for leather, hides, cloth, ore, stone and meat (only herbs are 7/9), elementals 5/0 Reagent. Never gate on modern subclasses 5-10; build test mocks from the real QuestieDB values.
- The "addon last ran a timer set at X" line in blocked-action reports names the previous addon activity, not the cause.

## 2026-11-17 — Decouple run r-20261117-234605-6ba9 (streams D1–D3)
- **One decision, one cost source.** Feeding an optional, asynchronous provider (SPF walk costs) into a choice that also has a fallback cost (straight line) makes the result depend on whether the provider is installed and when it answers. That needed a lock and a second solve, and still risked flips. Use the optional provider only for its own visible feature (the Follow arrow) and plan with a single source.
- **Measure when two requirements look compatible.** The builder measured the actual cost gap (camp B only about 10 s cheaper at POS 0.56) and showed that "stickiness without SPF" and "keep the 0.56 switch" cannot both hold. Flag a conflict like this with numbers instead of quietly satisfying one side.
- **Unbounded background work needs a priority, not just a budget.** One resume per job per turn still let a 0.7 s-CPU refine take a share of every slice from map search and the dungeon scan. DataWork `"idle"` keeps normal jobs at >= 90 % of their solo pace (D6).
- **Frame levels relative to a host must be restated, not set once.** The map canvas and its pins can re-level after creation. Restate on every draw and on show, and compare before writing so steady redraws cost nothing (D8, `BUGS/2026-11-17-guidance-map-numbers-hidden.md`).
- Harness gap: the mock `FontString` has no `GetFont`, so the locale font file branch in `QuestGuidance.makeMarker` is untested.

## 2026-11-17 — Fix-all run r-20261117-215940-e171 (streams A/B/C)
- **A moving input needs memory, not just a better rule.** The step-one bug (nearest spawn to the player) and its regression (camp re-chosen from first-leg costs on every 3 s re-plan) are the same trap. Remember the chosen value, and switch only past a documented margin (D1: 25 % and 20 s).
- **Read shared UI state when you use it, not when a long job starts.** `refine()` captured the selected step at job start, and a cooperative job runs for seconds. Any background job that swaps `route` must read `selectionLocked`/`route[selected]` at the swap.
- **Classic quest-log indices move.** A UI table that holds a log entry across QUEST_LOG_UPDATE (menus, callbacks) must refresh `index` in place or close. Matching by quest ID is not enough. Round-1 review caught "Offer it to the party" pushing [200] instead of [2], by testing on classic.
- **Keep long-lived work apart from per-keystroke work.** Cancelling one job on every keystroke threw away the whole catalogue index. A persistent index job plus a per-query match job, started by typing (not map open), keeps the no-preload guarantee and gives about 0.3 s suggestions.
- **Latency bugs need a clock in the harness.** Without `debugprofilestop` the harness runs 80 steps per pump and uses tiny fixtures, so a 3-8 s delay is invisible. The new Classic-size tests (10k NPCs / 15k items, mock clock) are the regression guard. Contention tests need the same approach (`test_map_search_and_dungeon_scan_keep_half_their_pace_while_the_guide_replans`).
- **Review rounds paid off.** Streams A and C each needed a second round for blocking issues. The reviewers' mutation checks (revert the fix in memory, and the new test must fail) confirmed that the new tests are not vacuous.
- During stream B, another session edited `VendorMap.lua` (`ensureUI` now uses `S.panel`/`S.inset` from the Style.lua restyle). With parallel sessions, keep foreign hunks and say so in the step output.

## 2026-11-17 — Bug audit of all 34 BUGS reports (run r-20261117-212533-cf04)
- Method: 6 groups (equipment/spell, UI/settings, planner Nov 16, planner Nov 17, guidance/map, data/dungeon), each with a checker and then an independent refuter.
  - The checker re-ran the covering suites (`tests/` with `/tmp/qs-test-env/bin/python`), cited file:line evidence and wrote scratch repros under `/tmp/bugaudit-*`.
  - The refuter re-ran the suites, mutation-tested the fix (revert it in a scratch copy and the covering test must fail) and probed variants.
  - Final verdict = the refuter's `corrected_verdict` wherever it disagreed with the checker.
  - Full suite 1766/1766.
- Results: 29 holds, 3 partially_fixed, 1 regressed (`2026-11-17-planner-step-one-on-player.md`), 1 open (`2026-11-17-map-search-missing-database.md`).
- Mutation checks show the covering tests are not vacuous: reverted fixes reproduce the reports' pre-fix counts (e.g. loot 38/58 without the slot gate; usability 28/30 without the apply() cancel).
- The brief's "uncommitted planner diff" was stale: it is committed (f1b34e9, f9bb992). The audit range was d2387c3 (= v0.4.21) to HEAD.
- Most new risk comes from f1b34e9's background `quest-improve` / `refine()`:
  - Selection reset: refine captures the selection key at job start (`QuestPlanner.lua:924`) and sets `selected=1` after solve (`:927`). A map click, row click or Next during the job therefore snaps the guide back while the waypoint stays on the clicked stop. This contradicts CHANGELOG Unreleased ("keeping your selected step"). Fix: read the key after solve() returns, then add a test that clicks while `NS.dataWork.busy('quest-improve')`. The refuter of `2026-11-17-guidance-map-click-event-argument.md` rated that report partially_fixed for this reason; no addendum has been written yet.
  - SPF camp flicker and mixed-creature camp loss: see the addendum in the step-one report.
  - CPU contention: DataWork gives each job one resume per turn whatever that resume costs (`DataWork.lua:62-86`). improve resumes reach 2.4-3.9 ms because evaluate()/remember() (`QuestOptimizer.lua:570`, `:633-641`) replay paths without yielding. Result: vendor search runs at 5-9% of solo speed, the dungeon 8 ms scan at 74-75%, and the reward index slows about as much as vendor search. Options: per-job time accounting in DataWork.pump, checkpoints inside evaluate/remember, pausing quest-improve while a foreground or map job is queued, or not restarting it on small movement rebuilds.
  - Unverified (code reading only): "Camp busy 5 min" (`QuestPlanner.lua:1667`) keys waitingAt by the chosen point, but planOptions (`:885`) reads the default `stop.point`, so it may do nothing for alternative camps.
- Misattributed root cause: the user's "won't open / black" symptom in `2026-11-17-dungeon-loot-does-not-open.md` ("not a bug") and `2026-11-17-dungeon-quests-slow-first-load.md` was the EditBox:SetFont-without-flags build failure. Under the strict harness, v0.4.20 and v0.4.21 fail test_loot (2/58) and test_dungeon_quests (0/64). The fix is f1b34e9 and is unreleased: toc 0.4.21, no tag contains it. Both reports are partially_fixed. The dungeon report's "wrong/missing quests" and its QUEST_LOG_UPDATE menu auto-close (`DungeonQuests.lua:475-477`, `:611-619`) are still open.
- Stale report bookkeeping, no behaviour impact:
  - settings-extra-tools-overflow: replaced by the v0.4.16 scroll redesign.
  - zone-levels-opt-in: the toggle is now in the Map tab (`Settings.lua:176`).
  - Shipped although the reports still say local: recruitment (7c3cc2c, v0.4.16), profession layout (cb45f17, v0.4.20), vendor-map (v0.4.19).
  - journal-black-page: committed in f1b34e9.
- Test gaps found:
  - No committed test for: `/qs plan next`, the distant same-creature no-merge case, explicit-nil or numeric-string Questie levels, the city guard, SPF together with alternatives, mixed-creature camps, a click during quest-improve, Classic-size suggestion latency, or quest-improve contention.
  - Planner UI tests run in modern style only.

## 2026-11-17 — Quest planner: "where" and "which" are different questions
- QuestieDB spawn lists hold every individual spawn; common mobs have lone spawns across the whole zone. Any "nearest spawn to the player" choice therefore lands at the player's feet and follows them (3 s movement re-plan). Choose among camps (grouped spawns), never single spawns.
- "Has a point on this map" is not "belongs to this map". Membership comes from Questie `zoneOrSort` (positive = zone area, negative = class/profession/event category). Location rules only decide whether the work can be done here.
- Removing a guard that no longer changes the *plan* can still change the *report*: the log-quest association guard also keeps unrelated log quests out of `/qs plan why` (`test_planner_facts.py` caught it).
- No fixture before this set `zoneOrSort`; a quest without one is "unknown" and must keep the old location rules, or older Questie builds without ZoneDB would lose every quest.

## 2026-11-17 — Search appearance belongs in the shared explorer
- Native red buttons, Quickslot2 item surrounds, dialog grain and QuestBG parchment provide client-owned WoW styling without shipped art or global UI changes. Keep selected-row/text-state semantics; use explicit dark ink for parchment (yellow quest links need conversion).
- Shared skin can stay inside EquipmentUI and its3consumers; untouched data scans, item comparisons, filters and menus already have meaningful integration coverage. Larger13px row/detail text still fits existing48px item/102px quest rows.
- Isolated v0.4.19+4files passes44suites/1,627checks,42Lua parses and source/CRC checks. Browser3tab emulation inspected; native texture/font rendering cannot be claimed from browser approximation.
- Recommend4file overlay over complete baseline package to avoid rolling back concurrently installed profession/diagnostic updates. Overlay34,536bytes/SHA256 `ec1462c387e53ccf39eb214b5abf012a1801b73cdaacde0675fe2980b3ed43fa`; complete baseline preview44files/233,999bytes/SHA256 `f11e760ae4377ff5a8276b7d364507d70aee0b2d306a126de9f48886a811439a`.

## 2026-11-17 — Diagnostic readability follow-up
- Concatenating raw doctor flags, stacks and logs solves capture but creates a wall of text; auto-selecting it also obscures reading. Open an unselected overview, keep raw detail optional, copy the complete snapshot regardless of view.
- Keep capability/setup notes separate from actual recorded errors. Opening reports should not repeat the same details into chat or generate fresh log noise.

## 2026-11-17 — Wetlands standalone vendor smoke
- Latest-version user reports standalone QuestieDB, query `vendor`, outdoor Wetlands; loaded-data report still absent. Do not ask them to install full Questie as an assumed remedy.
- Loaded existing `/tmp/questsharing-dungeon-{npc,item}db.lua` raw Classic source through schema-based adapters, then removed Questie/QuestieLoader and set ZoneDB area11->UI1437. Actual map module produced20 pins/6 suggestions/zero errors on both API styles. Includes Engineering Supplies at26.4,25.8 outside Menethil. Raw baseline is not the user's installed Forever dataset/native UI.
- Checked primary upstream docs: https://github.com/Questie/QuestieDB/blob/master/docs/api.md entity globals/GetAllIds and standalone support ZoneDB, and QuestieDB.toc with no Questie dependency. Remaining fault boundary needs `/qs questie` output/panel status, not more synthetic matching changes.

## 2026-11-17 — Readability requires the correct host and information hierarchy
- User explicitly rejects the released companion despite 1,617 prior data/layout checks passing. Assert requested frame ownership, all-row navigation and text hierarchy; fixed bounds alone cannot establish visual usability.
- Forever CraftingPage exposes RecipeList/SchematicForm and `SelectRecipe(info,true)`, allowing an embedded full list and native learned-recipe controls without fighting show-unlearned resets. Never pass static/synthetic unavailable recipeInfo into native schematic code.
- A native hidden-list rebuild can auto-select a learned recipe behind an unlearned source overlay. Keep the visible selection authoritative and clear/validate native controls before showing the overlay; exercise this event ordering in tests.
- Lua `return line:gsub(...)` returns replacement count too; shortSource must parenthesize it when exporting strings to tools or passing to strict UI functions.
- Prefer same-faction vendor locality and hide repeated provenance/opposite-faction supplement lines from selected source copy; preserve the complete factual source reference separately.

## 2026-11-17 — Chain relation and task are independent
- Clear row labels need two dimensions: chain prerequisite/dungeon step/follow-up versus Talk only, item delivery/collection, combat, exploration, event or unknown. Do not replace chain identity with Talk only; many preparation steps have both.
- Prerequisite reverse links identify a chain start even when it has no own preQuest; include known explicit next links and preserve IDs for identical titles. Branches need previous/next names, not fabricated step N/M.
- An empty NPC/object objective list alone is insufficient for Talk only: check exploration, extra objectives, source items, event/escort bit and given/starter items. Actual raw Classic quest65Talk Wiley,132/141letterdelivery,155escort,166VanCleefheadcollection validate distinctions.
- User confirmed selector works after initial complaint; only-All options reproduced before scan completion/missing provider, but no live defect established and no dropdown patch made.
- Stable-package checks301/301 across7suites, focused58/58, all42Lua parses and raw4,244quest smoke pass. `dist/QuestSharing-dungeon-clarity-preview-2026-11-17.zip` contains only DungeonQuests.lua runtime delta over v0.4.19;44entries/232,804bytes/SHA256 `fde50fb793c24d64eec4e74c31da87813a8372ffc75968394826e38edb2438b0`. Native visuals unverified.

## 2026-11-17 — Empty map search can hide a missing database
- `VendorMap.indexRoles/indexItems` coerce absent `Q.ids` to `{}` and mark indexes ready, caching an empty result even if a database appears later. Detect enumeration capability before starting the worker; distinguish dependency failure from legitimate no-local-match feedback.
- `Q.available()` checks **quest** records; it cannot gate NPC/item search because a valid standalone provider may expose only NPC/item tables. Use `Q.canEnumerate("npc") or Q.canEnumerate("item")` without executing GetAllIds.
- Reproduced misleading no-seller state with all provider globals nil on modern/classic; tests verify absent, old, global/Lib-only, late and lost providers. A no-data fixture must restore ZoneDB mapping support alongside entity tables when verifying late pins.

## 2026-11-17 — Diagnostic copying
- Previous window switched between doctor/errors/log; display caps hid all but 10 errors and 1000 log lines despite storage retaining 30/~3000. Combined report must read full buffers, not concatenate already-truncated views.
- Preserve a selected report as a snapshot; refresh explicitly. Native clipboard remains user-driven via Select all + Ctrl+C/Cmd+C.

## 2026-11-17 — v0.4.19 release verification
- Published latest stable https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.19 at `d0b859820f9b8fdb0a100e2bdc69b5363574a605`; main/annotated tag verified remotely. Uploaded/downloaded ZIP equals local tested build and source bytes; published notes match exactly.
- Current workspace passes all 44 self-running suites / 1,617 checks and compilation of all 42 runtime Lua modules with Lua 5.1; diff whitespace clean.
- Install ZIP contains exactly 44 Lua/TOC/XML entries, all byte-identical to source; TOC lists every runtime Lua module and embedded Cooking MIT attribution is retained. CRC passes, 231,769 bytes, SHA256 `f1a6e29d91fddeef01408f44132b703ff0a18ad3a055ac4170feb6ed094ab46e`.
- No game client available; native rendering, live providers, profession learned states and protected deletion remain pending. These limits are included in 0.4.19 release notes.

## 2026-11-17 — Forever Cooking reference and rank upgrades
- Forever's Camelot `Professions.GenerateCraftingDataProvider` resets unlearned filtering false; a separate catalogue avoids filter loops. `GetRecipeInfo(spellID).learned` is useful only for explicit available answers from the player's own Cooking source; absence is unknown, not missing.
- Recipe counts differ by source: Profit pinned build1.60.1.70888 has133 Cooking records, WoWFDB lists123. Display as dated reference records with unconfirmed entries, not an asserted obtainable-recipe count.
- Item food drops in installed Questie use `npcDrops`; NPC `minLevel`/`maxLevel` plus `spawns` answer mob/zone questions without enumerating the item database. Real raw data resolves Chunk of Boar Meat -> Stonetusk Boar5-6 in Elwynn, with alternate NPCs.
- Guides support practical fish routes more often than exact minimum/no-getaway thresholds; keep these separate and preserve AnglerAtlas provisional/zone-estimate labels.

## 2026-11-17 — Guidance follow-up validation
- U.call returns only three values; never route GetMapRectOnMap's four bounds through it. Preserve local API arity instead of weakening coordinate validation or changing a shared wrapper.
- Missing-on-first-open measurements require throttled repair; active-frame retry can recover a target without re-opening or adding a timer. Tests must measure increments after opening because Game.advance now executes active frame updates.
- Summary truncation needs selected-entry coverage, and grouped marker position must follow the selected point. Color-only highlight misses the wrong-number/wrong-point defect.
- Package only known runtime entries: the workspace gained an unrelated, unlisted CookingReference.lua draft during validation. Verified baseline ZIP + QuestGuidance overlay includes the completed runtime and excludes draft files; all entries match current source.

## 2026-11-17 — Hover rewards and compact quest locations
- XP belongs to active-flavor `Support.Get("QuestXP").db[id]` as `{questLevel,baseXP}`, not the quest entity. Legacy QuestieLoader QuestXP.db is a safe fallback. Label base XP; keep missing distinct from zero and avoid unrelated selected-log reward APIs.
- Item rewards are reverse Item.questRewards links, including non-equipment; they do not distinguish fixed/choice, amounts or cash. Build once only after first hover through shared DataWork, then reuse. Late worker/item-cache events must check currently hovered visible row; leaving/closing cannot reopen tooltip.
- Cache pickup/all NPC-object turn-in projections; first giver plus alternate count stays in four-line 84px row, all givers/locations in tooltip/detail. Six rows at 88px spacing fit existing 530px list without overlap.
- Actual raw Classic quest 166 smoke: 2,600 base XP; reward IDs 2041 Tunic of Westfall, 2042 Staff of Westfall, 6087 Chausses of Westfall. Provider row smoke omits runtime corrections and native rendering remains unverified.
- Validation: 48/48 focused and full 43 suites / 1,573 checks, Lua 5.1 syntax and diff checks; preview rebuilt with 41 byte-matched files / 212,263 bytes, SHA256 `b1e11d89fa922b92ef919742af741481210aa83aa28aec67d5b738be16be7efe`.

## 2026-11-17 — Dungeon quest identity versus shared item drops
- User means all associated quests for one dungeon, including outdoor pickups/preparation/follow-ups; this is independent of reward equipment and current quest-log membership.
- Upstream raw Classic data smoke: 4,244 quest IDs, 580 associated quest records after chain expansion; Deadmines includes Defias preparation, Red Silk Bandanas, Collecting Memories, Oh Brother, Underground Assault, The Unsent Letter and Test of Righteousness. No runtime corrections loaded in this smoke.
- Any-dungeon-drop inference incorrectly brought ordinary wool/leather/food/crafted turn-ins into every dungeon where materials drop. Require objective-item sources to be exclusively known dungeon areas unless the quest has another direct dungeon association; include explicit dungeon categories and actual NPC/object objectives independently. Permanent mixed NPC/object source regression checks cover this boundary.
- Synthetic absent-log entries need a catalogue flag: Classic quest links/objectives/share APIs take log indices, so calling them for an unaccepted quest can target the wrong selection or fail. Reuse actual entries when accepted; catalogue entries keep where/how/chain/pickup actions and explain unavailable log-only actions.
- Validation: 32 new checks across both API styles; full current workspace 43 suites / 1,557 checks, Lua 5.1 syntax and diff checks pass. No native WoW rendering/FPS claim. Separate source/CRC-verified 41-file preview at `dist/QuestSharing-dungeon-quests-preview-2026-11-17.zip` (211,093 bytes; SHA256 `4708720803b38d3002bd4ac539034950f499c6bc09388889246172358b71d927`).

## 2026-11-17 — Review leftover quest items conservatively
- `Item.startQuest` and positive native bag questID protect unaccepted quest starters; `Item.relatedQuests` complements active quest objective/source/special-item requirements, with native IsOnQuest covering hidden reverse matches.
- Keep completed quests in the item requirement snapshot until removed from the log: readiness to hand in does not make their items leftovers. Quest class/native flags provide positive quest-item evidence; ordinary reagents should not become cleanup candidates merely because they lack active matches.
- Pickup may invoke synchronous callbacks: recheck quest/combat/master state after pickup and cursor identity immediately before destructive calls. Refused native deletion returns cursor item via ClearCursor; never retry deletion on a timer.
- New cleanup stays entirely on demand: visible bag/quest/combat events invalidate review without reading bags or catalogues. 34 focused checks and 43-suite / 1,557-check full run pass; native WoW still required to verify protected APIs and appearance.

## 2026-11-17 — Direction and route overlay boundaries
- World coordinates from C_Map run north/west, while zone fractions run east/south. Use metric world deltas or native width/height; normalized map fractions alone distort bearing and cannot give yards.
- A hidden arrow frame receives no native OnUpdate; temporary position loss must retain an active retry path rather than hide itself permanently. Explicit guide close removes updates entirely.
- Own map layers avoid pin providers and host-map writes. Plain markers use hover plus global mouse down/up; Core prepends event name, so handlers accept (_,button). Group colocated/nearby steps and cycle rather than stacking inaccessible buttons.
- Cache geometry by route revision/displayed map/size/scale; spatial buckets avoid pairwise grouping across every stop. Reuse line/marker pools, make background labels opaque, and retain exact quest selection on arrival.

## 2026-11-17 — Optional database cost and lifecycle
- Provider caching does not make broad enumeration free; first reads decode/cache data. Eager map index warmed every vendor spawn and item name even on a closed map; saved planner setting triggered world quest discovery on login and same-zone events repeated it.
- Gate work on visible user demand before calling GetAllIds; queue discovery and route work through one cooperative timer, with per-field yields outside pcall. A record/native call may still exceed a soft budget.
- Reuse scalar NPC roles, only current-query locations, last-two-zone quest IDs and a per-scan 256-source cache. Do not treat quest zoneOrSort as an exclusive geographic index.
- Mock 1,000-NPC trainer search reads one matching NPC spawn and zero item IDs; login/blank-map and hidden guide events enumerate no catalogues. Native FPS and provider-independent startup cost remain unmeasured.
- Coroutine replacement must be guarded by job identity at completion; pausing after resolving a query must still resume rendering when map reopens. New-query debounce must discard stale Tab suggestions immediately.
- 2026-11-17: user reports `vendor` produces no results in the Barrens while using a previous version. Actual v0.4.17/v0.4.18 VendorMap both return 0 pins for generic `vendor` on the existing seller fixture; current module returns 5 on both API styles. Focused suite 76/76 passes; preview ZIP contains identical fixed module. Release/version gap reproduced independently of zone; actual Barrens records/native rendering remain unverified.

## 2026-11-17 — Compact guide and real-output emulation
- User supplied Zygor screenshots to clarify presentation. Reproduce interaction hierarchy and dark compact guide style with own branding/assets: one emphasized current step, muted future steps, header navigation/counter, position lock and mini mode.
- `P.navigate` reviews/waypoints only; guide navigation must never masquerade as quest completion. Auto quest events still rebuild eligibility/progress. Lock must gate drag handlers as well as SetMovable.
- Emulate from actual Lua route/row output rather than a separate hand-invented route. Generator walks eight sample steps via P.navigate and exports actual strings/coordinates. Sample names/locations are explicitly illustrative, not the player's live quest log.
- Browser inspection: one active + five upcoming rows, no root horizontal overflow; next changes 1/8 to 2/8, mini leaves one row, lock toggles, close/reopen works. Native tests cover same controls. First clipped screenshot API returned empty background; full getScreenshot capture succeeded, then cropped surrounding whitespace only.
- Visualize bundled renderer missing assets/visualize.css; self-contained inspection wrapper works. Native WoW fonts/compositing remain unverified. Full 39 suites / 1,444 checks, Lua/JS syntax and whitespace pass.

## 2026-11-17 — Flexible role matching
- Explicitly requested after `skinner trainer` failed literal lookup. Role aliases cover common English profession worker/training names; plurals/punctuation and query order normalize consistently for both hints and pins.
- Avoid unrestricted fuzzy matching: at most one spelling edit across role tokens, minimum five ASCII letters; include insertion/deletion/replacement/adjacent swaps and canonical worker alias forms. Non-ASCII/short tokens do not receive typo matching.
- Cache normalized NPC title words, preserve raw localized labels. Prioritize literal/alias role or item pins on displayed map; remote exact hits must not suppress a local approximate role. Rank approximate suggestions after literal role and item suggestions.
- Item names remain literal and selected items exact. No provider records/spawns invented. Generic vendor typos still request seller-only results.
- Baseline first new workflows 56/64; final focused 76/76, all 37 suites / 1,406 checks, syntax/diff clean. Earlier no-synonym finding is now superseded in local code; installed user build remains v0.4.17.

## 2026-11-17 — Skinner vs Skinning search wording
- Current `matchesWords` requires each literal query token within a title/item. In both API harnesses, Skinning Trainer matches `skinning trainer` and `skin trainer`, not `skinner trainer`; no synonym alias exists. Keep this limitation explicit rather than promise natural-language profession understanding.

## 2026-11-17 — Map popup readability and confirmed installed version
- Solid-looking color values alone do not guarantee visible popup backgrounds: map content can compete with sibling-frame draw order. Existing popup had 0.98 alpha and no explicit strata/level. Raised only own popup using existing EquipmentUI dropdown pattern; background and border now fully opaque, rows wider/taller, text larger/white.
- Instrumented real frame creation on modern/classic confirms opacity, explicit layer above map, text format, bounds and click dismissal; native compositing remains unverified. Focused 52/52 and syntax/diff checks pass; no added permanent tests for this visual-only change.
- User confirms Stormwind capital and installed v0.4.17. Actual v0.4.17 module reproduces linked Druid Trainer/unlinked Paladin Trainer asymmetry; local module finds both. Prior fixes have not been installed/published.

## 2026-11-17 — Trainer release/local comparison
- Published v0.4.18 still indexes only Item.vendors. A Druid Trainer linked by an item and an unlinked Paladin Trainer reproduce asymmetric discovery; current local NPC-title index finds both with identical map/data.
- Search contains no Druid/Paladin-specific branch. Do not infer class discrimination from an item-derived coverage gap.
- Exact full title is deliberately omitted from autocomplete (`key == lower(query)`), while matching pins remain. Ask whether missing means suggestions, pins or both before changing matching.
- Added six trainer workflows; focused suite 52/52 passes. No runtime edits in this follow-up; actual user map/version/data remain unverified.

## 2026-11-17 — Vendor means seller category, not a literal title word
- User clarifies `vendor` -> all sellers and `general vendor` -> general seller roles, strictly on displayed map. Earlier fix retained literal title matching; new failing workflows reproduce this omission (30/40 baseline pass).
- Normalize seller nouns once for matching and suggestions; preserve seller-only suggestion kind so choosing `General` does not include General Commander or unrelated item names.
- A nonempty NPC title is not seller evidence. Use explicit item links, guarded active-flavor vendor flags, or known merchant-title words; index untitled flagged sellers too. No fixed flag bit: provider flavors differ; RequireContract(4) guards enum use.
- Verification: focused 46/46, full 37 suites / 1,376 checks, Lua syntax and whitespace checks pass. Native rendering/installed data completeness remain unverified.

## 2026-11-16 — Vendor search omissions and scope
- An Item.vendors-derived NPC index cannot support complete title search: known General Goods NPCs with no reverse item links disappear. Enumerate NPC subName independently while preserving explicit item links for item queries.
- Suggestions must use the same valid-coordinate projection as pins; globally correct suggestions can still feel broken when the current zone has no matching points.
- Keep suggestion kind through submission: category text can also occur in an unrelated item name; selected items should use exact names.
- Style.button uses a custom visible label; dynamic text must use SetLabel. Native SetText can pass a mock field check without changing the visible label.
- A cancelled generation's callback must not clear shared loading for its replacement; exercise overlapping timer batches rather than only end-state cancellation.
- Verified: baseline 4/18; final focused 30/30; full 37 suites / 1,360 checks. Native map/installed Questie behavior remains unverified.

## 2026-11-16 — SPF can provide walk costs as well as map guidance
- Current public Shortest Path Forever API v2.3 adds `EstimateWalks`: asynchronous walk-yard costs from one position to up to 256 targets on the same walking map, with cancellation and explicit loading/no-data/unreachable results. `Navigate`/`NavigateRoute` hand off guidance and SPF draws its own route; `Guidance()` exposes current-leg bends.
- Implemented as optional explicit click-to-follow plus walk-cost promotion of the first eligible outing; full outing optimization needs more cost queries. Cave heights and strict dry-land routing remain constraints.
- Evidence and compatibility details: `context/quest-planner-routing-and-validation-plan.md`; official API docs: https://github.com/cjber/shortest-path-forever/blob/main/docs/api.md.

## 2026-11-15 — Missing creature badge was blocked by game nameplates
- User-provided `/qs doctor` output from Quest Sharing 0.4.13 reports quest creature icons `[OK]` but explicitly says enemy nameplates are off and recommends `/qs highlight cvars on`. With no enemy nameplates, the addon has no creature plate to overlay; `markMobs` being on alone cannot display the badge.
- The same report's 30 secret-string errors name `Friends.lua`, `Share.lua`, and `Diagnostics.lua`, not the marker path; treat these as a separate issue.
- This diagnosis needs no code change. Menu discoverability improvement should group the creature badge and the nameplate-settings helper together.
- Follow-up: user says the badge is still missing. The original diagnosis was a prerequisite failure in the captured snapshot, not proof that the CVar command took effect or that a given unit qualifies. Verify fresh helper/nameplate status and active quest-unit matching before changing code.
- Follow-up: user says `/qs doctor` still reports enemy nameplates off after the advice. `Highlight.lua:setHighlightCVars` deliberately refuses to set CVars during combat and prints “game settings cannot be changed in combat; try again afterwards”; obtain that command's actual response before concluding the setter is broken.
- Follow-up: user reports visible yellow enemy health bars while doctor still says nameplates are off. This contradicts the prior assumption that no plates are present; separate actual visible plates from the raw CVar check via `/qs highlight` before investigating marker matching.
- 2026-11-16: verified release `v0.4.15` ZIP includes the `markMobs` setting row under Tracker. New quest-automation rows appear first in that tab, pushing **Finding objectives** and its creature-marker option lower; the setting is immediately after **Pin the nearest quest in the world**.
- 2026-11-16: `markMobs` is an independent checkbox (default on); clicking once toggles the gold quest badge off or on. `/qs highlight mobs off` turns it off directly. Plain-language copy now states this visibly.

## 2026-11-15 — Quest dialog action boundaries
- Blizzard's live QuestFrame source handles `QUEST_DETAIL`, `QUEST_PROGRESS`, and `QUEST_COMPLETE`; accept uses `AcceptQuest()`, ready progress uses `CompleteQuest()`, and reward confirmation uses `GetQuestReward(itemChoice)`. Source: [QuestFrame.lua](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/QuestFrame.lua).
- Its reward handler selects item 1 only when there is exactly one choice; it asks the player when choices remain and opens a confirmation for turn-ins that cost money. QuestSharing follows those boundaries and keeps ambiguous/payment cases manual.

## 2026-11-15 — Routing implementation canceled
- User selected a Shortest Path Forever integration earlier, clarified that the UI should live in QuestSharing, then explicitly stopped and scrapped the active plan. Keep its prior feasibility and source study as reference; make no runtime changes unless asked to resume.
- A built-in routing prototype was removed before release. Its terrain/source volume and cave-floor questions are documented in `shortest-path-source-study.md`; this was not a shipped implementation.

## 2026-11-15 — Publication checkpoint
- Current runtime equals published v0.4.14; only routing research/continuity notes were pending. All 34 suites / 1,291 checks pass; rebuilt/downloaded ZIPs source-match and byte-match the recorded digest. Existing release/tag retained.
- Temporary test venv had expired; recreated with lupa 2.8. No repo dependency changes needed.

## 2026-11-14 — Walkable quest routing exists for Forever
- Cave follow-up: generated target heights come from classic-db spawn z (generator maps 0/1), and API auto lookup requires npc or explicit z. Player floor inference can remain unknown after reload/teleport; upstream test explicitly falls back to horizontal arrival while unknown. Multi-floor graph support is not a guarantee of correct cave quest targeting.
- Source study (`context/shortest-path-source-study.md`): terrain graph is the hard dependency; pure Lua algorithms alone cannot infer walkability. Found 3x swimming preference, checked smoothing preserving lake detours, NPC extra-height catalogue, movement-based player-floor inference, 2 ms shared search budget, pooled/rotated/clipped map drawing, and preview geometry that is not proof of a legal path. Source tests include actual Stormwind gate, Dun Algaz tunnel and Loch Modan routes; inspected, not executed.
- Full-doc reading: namigator README explicitly does not honor client-side movement restrictions; server navmesh routes are not automatically player-walkable. Forever baker uses player-oriented slope/step/floor rules. Provider live-navigation-verification.md explicitly leaves some real-client checks pending; headless tests establish neither secure UI nor live loading performance.
- User clarification: research scope is WoW-specific pathfinder documentation, not general academic algorithms; prioritize Forever baker/API and WoW movement-map generation/debugging sources.
- Follow-up: published HPA* research (Botea et al., 2004) supports large-map acceleration; Cui/Shi (2011) illustrates navmesh vs waypoints using WoW's Halaa. Established algorithms/engineering examples do not establish current Forever addon accuracy; source details and fetch limits recorded in routing research.
- Shortest Path Forever ships compressed collision-derived walking graphs; hierarchical A*/8-yard grids, slopes, directed drops/floors, water costs, and world-map/minimap rendering. Public Navigate/NavigateRoute can accept destinations from our existing Questie.lua adapter.
- QuestieDB NPC `waypoints` means NPC movement paths, not a player navigation mesh. Current Q.nearest is normalized 2D proximity only.
- Fastest journey differs from shortest dry-land walk: transport, swimming and preference costs may apply; no explicit strict walking-only API option found. Estimate omits endpoint terrain searches and cannot establish exact reachability.
- Research and proposed bridge: `context/walkable-routing-research.md`; runtime unchanged, in-game validation outstanding.

## 2026-11-13 — Empty native zone levels caused map-wide question marks
- Native GetMapLevels may return nothing; valid client/API availability alone does not establish data coverage. Zero metadata reproduces all-unknown badges on both API mocks; user's affected scope is every zone.
- Standalone guides now cover 39 Classic questing maps and Zephras/Riverglades. Hyjal/Shen'dralas use explicitly labelled known-quest spans, not invented official brackets; six cities and Moonglade have meaningful role labels.
- Checked every Classic guide/map ID against author source; Forever IDs verified against QuestieDB mappings. Reference checkout/downloads stay in `/tmp/questsharing-zone-reference`, not the addon package.
- Do not cache a fallback as native success: late API data must replace it without needing a manual refresh.
- All 34 suites / 1,291 checks pass, including 50 zone workflows and a zero-metadata 50-map badge scenario; native game rendering remains unverified.
- Published latest stable v0.4.14 at `73831bc7880ca8bcaab56af17ce4f020b4cff92a`; downloaded 163,779-byte ZIP matches source-verified 32-file build, SHA256 `d272c5586915eb3de82d0a2242dc4a715a1ed7cc56f408491f995326e1c6a5b8`.

## 2026-11-13 — Equipment identity differs from source identity
- Reproduced three Captain's Blade rows for two mobs/two modes and two Druid Staff rows for two quests. Raw exact-source dedup was correct; presentation needed a second grouping layer.
- Group after every filter, by normalized name; retain raw source arrays and all matching IDs. Highest native level/lowest ID selects the comparison version; stable name key survives cache arrivals.
- Supplier lists combine modes per dungeon/mob/provider; quest lists preserve independent routes/requirements. Hover previews bounded at six; full scrollable details remain in the same window.
- Existing paging fixtures incorrectly used repeated sources of one item as different results; replaced with distinct equipment and kept separate raw-source coverage.
- All 34 suites / 1,275 checks pass, including 28 grouping workflows; native rendering still requires the game client.
- Published v0.4.13 at `1bf2789ca1d7ddbbc7ee9039e4f06cb22a525361`; downloaded latest-stable 162,652-byte ZIP matches the 32-file source-verified build, SHA256 `f22e068e8c9403c2b566f9f13811267ea7636820f9b782e1ebbd0262c1e187e3`.

## 2026-11-13 — Optional means off until explicitly enabled
- User corrected the map-range default: all future Extra tools additions should be opt-in unless explicitly requested otherwise.
- Reproduced six failing modern/legacy assertions for fresh installs, v0.4.11 saved true values and Reset. A changed default cannot distinguish an old auto-enabled saved value from an explicit choice; the once-only migration marker requires a new choice and then preserves it.
- Verification: all 33 suites / 1,247 checks pass, including 34 zone-level workflows; the renderer is unchanged.
- Published v0.4.12 at `c86b34294ced23ddf904ac73f50e0fce01baae73`; downloaded 160,979-byte ZIP matches local source-verified build, SHA256 `0378057a6fd6fef839d3743de0382a72096c61d74b84be0e6d25327e161c4cd0`.

## 2026-11-13 — Native zone level ranges
- Verified [Blizzard Forever map API declarations](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua): GetMapLevels returns player min/max before pet min/max; GetMapRectOnMap returns minX,maxX,minY,maxY, requiring a four-value protected read rather than optionalUI.call's three-value helper.
- Native zone descendants, rectangles and player ranges avoid inaccurate static Classic/Forever mappings. UI map type Zone filters out dungeon level ranges; world/cosmic overviews avoid stacking every world's zone labels.
- New 30-check integration suite covers supported custom/Forever maps, unknown/recovering data, player-vs-pet ranges, hover reset, scale/resize, stale-label cleanup, delayed map load, canvas replacement, settings persistence and no native map mutations. Actual game rendering/data coverage remains unverified.
- All 33 suites / 1,243 checks pass; settings geometry still fits and native map/protected-call guards remain intact. Range precedes zone name in the panel so long localized names cannot hide the level value.
- Published v0.4.11 at `f18d8258a33bee3270967c6afdaaf57c258a31ef`; downloaded 160,895-byte ZIP matches local source-verified build, SHA256 `b822023e6024808c72639b328b5e00538d1154f26268bc781cfd29ec25bfe4ea`.

## 2026-11-13 — Learned spell ranks and action bars
- Verified modern spell-book entry/skill-line fields and pickup arguments against [Blizzard Forever spell-book declarations](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua); rank subtext comes from [spell API declarations](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua).
- [Myslot's action-bar import implementation](https://github.com/tg123/myslot/blob/master/Myslot.lua) confirms public GetActionInfo/PickupSpell/PlaceAction/ClearCursor workflow and legacy offSpecID=0. No third-party code/data bundled.
- Initial dedicated tests reproduced active-zero specialization rejection and unreadable-cursor mutation; corrected explicit zero handling and fallible cursor/combat guards before publication. Rank 10 must beat rank 2 numerically, and action spell IDs may refer to ranks hidden from the current book view.
- Verification: all 32 suites / 1,213 checks pass, including 48 spell-rank workflows. Tests cover combat beginning during pickup, occupied/unreadable cursor, wrong pickup/no-op/refused/partial placement, normal hidden/form pages, offspec/future/passive filtering, event coalescing and other addons changing target slots synchronously.
- No game client available; live native bar permissions and actual spell-book payloads remain in-game QA items, with refusal/unsupported behavior explicitly reported by the feature.
- Published v0.4.10 at `6e16bc4b6252dfc7e27399a781525e9201f3b729`; downloaded 158,346-byte ZIP matches local source-verified build, SHA256 `4c158c2b8ae663bde1a772ce31ece6183f262cd40438d56db82457a435f2969f`.

## 2026-11-13 — Current dungeon context
- Blizzard's [instance API declaration](https://github.com/Gethe/wow-ui-source/blob/classic/Interface/AddOns/Blizzard_APIDocumentationGenerated/InstanceDocumentation.lua) confirms instanceID is GetInstanceInfo's eighth return; optionalUI.call intentionally returns only three, so use protected direct invocation here.
- Actual compatible AtlasLoot catalogue has several Scarlet Monastery entries sharing ID 189 and Dire Maul entries with omitted/commented ID 429, area 2557 and SubAreaIDs; ID-only matching needs localized subarea disambiguation and a tie guard.
- Pending initial focus must survive asynchronous indexing but be canceled on manual navigation/close. Reopening recaptures current location; item-data refreshes do not recenter the browser.
- All 31 suites / 1,165 checks pass, including 24 current-instance/Extra tools workflows. An additional timing case showed dirty live-search fields must suppress focus before the debounce callback; reproduced and corrected before publication.
- Published v0.4.9 at `3cd7ddb9ebd5f3b8e8955b8a6fee919e0e235698`; downloaded 154,927-byte ZIP matches local source-verified build, SHA256 `82e65efb4ddbb59836315320c838eef78659ecf013b84ce507d3f237318774da`.

## 2026-11-13 — Native equipment stat filtering
- Blizzard's [generated item API declaration](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua) confirms C_Item.GetItemStats accepts an item link and may return no result. Older clients expose global GetItemStats; runtime detection/fallback is necessary.
- Three explicit AND conditions avoid hidden filter state and additional windows. Inclusive minimums use native units; missing/zero/malformed values cannot satisfy a positive bonus condition.
- Cache successful stat tables only; item info events clear cache before existing page refresh handlers. Unavailable data can recover without restarting or reindexing the catalogue.
- Existing mocks lack both stat APIs; dedicated fixtures exercise each API explicitly. Approximate widget render checked stat-row spacing; native game rendering remains unverified.
- Verification: all 30 suites / 1,141 checks pass, including 20 new stat checks across modern and legacy API paths.
- Published v0.4.8 at `50d41cad29bc5aa4119d964d91668bec4e75f89e`; downloaded ZIP byte-matches local source-verified build, SHA256 `3940b4a035ca9dceaf48ba9b95ffc066284e2f2081ea323543788decb5a02330`.

## 2026-11-13 — Equipment navigation redesign
- Most friction came from interaction design: cycling controls, Enter-only searches, page buttons and extra clicks for details. Direct/searchable dropdowns, live input and stable automatic selection address those paths.
- One unnamed popup is reused for all choices and stays open through background data refreshes; manual selection/tab change/close dismiss it. Filter reset cancels debounced callbacks so stale text cannot jump pages later.
- 30 usability workflow checks cover both API styles, including direct class/source choices, debounce, sorting/My level, wheel/arrow boundaries, cache-preserved selection, no-results recovery and hidden-tab search return.
- Native edit-box API verified against [Blizzard generated API documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleEditBoxAPIDocumentation.lua); optional SetAltArrowKeyMode(false) supports arrow navigation without capturing global keys.
- Caught and fixed delayed Apply callbacks resetting pagination after a scroll; the new workflow case failed on both API styles before cancelling both input serials at the common commit path. See `context/BUGS/2026-11-13-debounced-filter-reapply.md`.
- Final all-suite validation: 29 scripts / 1,121 checks passed; built/source-verified 30-file v0.4.7 ZIP.
- Published v0.4.7 at `13d718f`; downloaded 152,730-byte asset matches the tested ZIP (SHA256 `f8b13b1b34f17348296fe718f7e399c8dc2301ec8401f73ea28df78e46d779b9`).
- Mixed wheel/keyboard dropdown case also failed before correction; keep the Enter cursor inside the visible option slice. See `context/BUGS/2026-11-13-dropdown-offscreen-selection.md`.
- Reviewed approximate native-widget geometry previews under `/tmp/questsharing-equipment-{quests,dungeons}.png`; these are layout approximations, not game screenshots.

## 2026-11-13 — Minimum Rare equipment quality
- One shared predicate covers quests, dungeon results and source choices. Added confirmed native quality >=3 before type/slot/level filters; unknown quality is hidden until cache events supply it.
- New integration cases failed before the filter (26/36 shared-explorer checks passed), then 36/36 passed. Optional 42/42 and loot 58/58 also passed.
- Existing fixtures used quality 2 for all equipment; changed baseline gear to Rare and added explicit mixed-quality boundary cases rather than discarding existing feature coverage.
- Existing uncached quest test now expects hidden gear until native details arrive, then verifies its return.
- Final all-suite validation: 28 scripts / 1,091 checks passed. Built/source-verified v0.4.6 ZIP, 30 files.
- Published v0.4.6 at `401c950`; downloaded 148,480-byte asset matches the tested local ZIP (SHA256 `8efb93d2f4bdb21766d1ffd6c96eb59711bede03e363ff5c33c65d8c51d02dec`).

## 2026-11-13 — Unified equipment explorer
- User clarified that Forever dungeons must remain included; exclude raids/world bosses via actual dungeon identity, not merely a positive InstanceID or UIMapType.Dungeon.
- Verified AtlasLoot [content category API](https://github.com/HoliestWoW/AtlasLootClassic/blob/master/AtlasLootClassic/ItemDB/ItemDB.lua) and [Classic/Forever catalogue](https://github.com/HoliestWoW/AtlasLootClassic/blob/master/AtlasLootClassic_DungeonsAndRaids/data.lua).
- Actual provider smoke after classification: 30 dungeon entries / 1,655 raw source rows, zero Lua errors; item 5191 -> Edwin VanCleef / The Deadmines / Normal once native item details are available.
- Dire Maul wings have commented-out InstanceID in the compatible catalogue; accept their known area rather than losing them. Hall of Thanes map placeholder is explicitly unverified; do not add it to the Questie fallback area registry.
- EquipmentUI owns the only top-level gear window; quest/drop details are child panels. Shared session filters survive tabs; scan cancellation is explicit because the mock does not propagate OnHide automatically.
- Native numeric class/subclass metadata supports item types; fallback unset class/subclass zero cannot be treated as a known axe subclass.
- All 28 suites / 1,081 checks passed. New `tests/test_equipment.py`: 26 integration checks across classic/modern paths, including cross-link raid exclusion and unknown metadata.
- Approximate previews in `/tmp/questsharing-equipment-{quests,dungeons}.png` derive positions from actual mocked native widgets; they are not game-client screenshots. Real rendering remains unverified.
- Built source-verified v0.4.5 install ZIP: 30 files.
- Published stable v0.4.5 at `fdea252`; downloaded 148,397-byte asset matches local bytes (SHA256 `9c447ef0f5f30eb456992e698e1b63386608154d7ced95b8631fd6f3f70e802c`).

## 2026-11-13 — Invitation menu ordering
- Existing invitation action was row 3 after Offer it to the party; user requested it directly after Tell the party.
- Moved to row 2. Existing 60 menu and 32 adventure checks passed across modern/classic paths.
- Runtime change only reorders existing actions; no new frames, chat or state behavior.
- Published v0.4.4 at `0c1a512`; downloaded asset byte-matches source-verified 29-file ZIP (SHA256 `893ba47c0cc1b68c523a9fa3c140b716b6d66d3c168d4f01ac05d33b2715e92d`).

## 2026-11-13 — Equipment-only instance drops
- Provider filtering correctly found dungeon sources, but all positive item IDs reached results; both providers needed the same equipment predicate.
- Original loot fixture gave cloth a weapon slot and explicitly tested its inclusion; corrected realistic slots and expected scope.
- Common `Rewards.itemInfo().slot` is sufficient to classify weapons and wearable gear without adding API/provider dependencies; unknown details stay hidden until cache events.
- Failed-first regression suite then passed 58 loot cases; all 27 suites / 1,055 checks passed. Built and source-verified v0.4.3 ZIP (29 files).
- Published correction v0.4.3 at `72d7d35`; downloaded release ZIP matches tested local bytes (SHA256 `af209ddb41dc6ca695b1364b56c00c3dade5ef7281b385ae19010ccbec0f0cd1`).

## 2026-11-13 — Release 0.4.2 published
- Re-ran all 27 suites: 1,043 checks passed; rebuilt and verified 29 addon files.
- Pushed main and annotated v0.4.2 tag at `5dbb839`; published stable release with ZIP and all changes since v0.3.9.
- GitHub asset digest and downloaded bytes match local ZIP: SHA256 `f1839bca6f8d0c0cc15239c7a9e090fbd69be72424664341b61776700ef0abfb`.
- Release: https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.2

## 2026-11-13 — Instance drop browser
- All 27 suites passed: 1,043 checks, including 46 instance-loot cases; final local install package is `dist/QuestSharing-0.4.2.zip`.
- Verified AtlasLoot contracts in [ItemDB.lua](https://github.com/HoliestWoW/AtlasLootClassic/blob/master/AtlasLootClassic/ItemDB/ItemDB.lua) and [encounter data](https://github.com/HoliestWoW/AtlasLootClassic/blob/master/AtlasLootClassic_DungeonsAndRaids/data.lua).
- Actual Forever-compatible ItemDB.lua + data.lua smoke-loaded into the Lua harness: 34 instance records and 2,635 distinct item/source/difficulty entries; item 5191 correctly resolves to Edwin VanCleef in The Deadmines. No Lua errors in that run.
- Reference files and smoke runner are under `/tmp/questsharing-loot-reference`; no third-party code/data is copied into the addon package.
- AtlasLoot item rows use column 2 for item ID; ExtraList also marks real Trash tables, so only IgnoreAsSource and non-Item format tables should be excluded.
- Questie dungeon sources can use either {-1,-1} sentinel spawns or normal coordinates on a Dungeon map; both need support.
- Harness frame Hide() does not fire OnHide automatically; cancellation tests explicitly invoke the hook to simulate the game's lifecycle.

## 2026-11-13 — Invitations and quest-overlay removal
- Role-play composer implemented in `Adventure.lua`; 32 integration checks cover wording, UTF-8 limits, channel routes, preview, preserved drafts and stale quest rejection.
- User interrupted final packaging to request removal of quest map/minimap symbols. Deleted `QuestMap.lua`, its TOC entry and all runtime/UI hooks; old saved `questMap` flag is cleared on load.
- Kept the five how-to chat cases in `test_questmap.py`; replaced retired rendering expectations with removal guards. Final suite: 26 scripts / 997 checks, all passed.
- Version 0.4.1 combines invitation work and map-symbol removal; only local packaging, no remote publication.

## 2026-11-13
- Existing settings had six tabs and no Optional category; now seven tabs fit within the 660px window.
- Confirmed QuestieDB API/schema: [API](https://github.com/Questie/QuestieDB/blob/master/docs/api.md), [item fields](https://github.com/Questie/QuestieDB/blob/master/src/meta/itemMeta.lua), [quest fields](https://github.com/Questie/QuestieDB/blob/master/src/meta/questMeta.lua).
- Numeric QuestieDB getters use zero for unset values. `GetAllIds()` is shared/read-only. Item reward links live in `Item.questRewards`.
- Forever race masks include bits 32/33; 32-bit `bit.band` would truncate valid races. Provider enums carry active-flavor mappings.
- AnglerAtlas Forever 0.1.9 source inspected from its [release](https://www.curseforge.com/wow/addons/angler-atlas/files/9455093); live adapter smoke-loaded its actual Data.lua in the Lua harness (Elwynn: minimum 1, two fish). Reference files only in `/tmp/questsharing-angler-reference`, not vendored.
- AnglerAtlas source warns that new Forever zone skill, catches and map placeholders are unverified. Zone summaries cannot establish a per-water catalogue.
- Protected map-opening guard existed before this task; preserve it rather than weakening its test. Game map must be opened by the user.
- Test runtime installed in isolated `/tmp/questsharing-test-env` (`lupa` 2.8, Lua 5.1), because host Python had no lupa.

## 2026-11-12
- The user supplied the original Global Working Protocol, including the Continuity System; earlier searches had not located that original text.
- Cursor's local `aicontext.personalContext` field was empty when checked; project rules existed in Desktop/CursorRules.
- User explicitly wants continuity used all the time and supplied rules applied when needed.

## 2026-11-11
- Local tracking refs alone are insufficient evidence of a published GitHub Release; query the release list.
- `python` was absent; `python3 build_release.py` successfully built the 0.3.9 asset (25 addon files).
# 2026-11-16 — Item sources and vendor search
- QuestieDB `Item.vendors` gives NPC IDs; `Npc.subName` is the localized role/title and `Npc.spawns` gives map coordinates. This supports category-only item hints and vendor map pins.
- QuestieDB item records have no `craftedBy` field, and object records have no gathering-profession field. Their `objectDrops` IDs plus localized object names support only a cautious mining-node heuristic; craft/gather labels are not complete.
- A whole-catalogue search needs current QuestieDB's enumerable item IDs. The index scans in timer batches and remains session-only; direct tooltip lookups do not need the catalogue scan.
- Vendor search matches all typed words as substrings, so a partial word like `tail` finds titles such as `Senior Master Tailor`. Suggestions list matching title words first, then full roles and item names; click or Tab completes and searches the selected text.
- Closest fallback can compare normalized map points on one continent using `C_Map.GetMapRectOnMap`; those coordinates are a geographic approximation, not a travel or walkability route. Cross-continent proximity is not claimed.

## 2026-11-16 — Quest data feasibility for quest optimizer
- QuestieDB documents quest, NPC, item, and object records plus support datasets for zone/UI-map mappings and drop tables; Quest records expose prerequisites and objective data through the public API.
- Quest Sharing's `Questie.lua` already reads quest starters, `preQuestSingle`/`preQuestGroup`, kill/loot/object/explore objectives, NPC/object spawn points, and turn-ins. Its existing target helpers cap some alternate drop/kill-credit sources, so they are display-oriented and not yet a complete optimizer index.
- This is enough to support a useful best-known quest planner, not a promise of complete data or optimal walkable routes. The planner still must evaluate player eligibility/progress, missing data, and travel across terrain, caves, and floors.
- Sources reviewed: QuestieDB public API and support-data docs; Questie's QuestieDB integration guide.
- Follow-up (2026-11-16): Questie runtime has `QuestieDB.GetItemDroprate(itemId, npcId)` backed by its DropDB; basic QuestieDB Item `npcDrops`/`objectDrops` fields are source lists, not percentages. Quest Sharing currently has no drop-rate lookup. Treat recorded percentages as estimates/data-specific, and show unknown when absent.

## 2026-11-16 — Quest optimizer prior art
- Existing projects validate the concept in distinct ways: Dreamway makes prerequisite-aware quest batches manually; QuestFlow and QuestRoute group live objectives into geographic stops; QuestTrail describes camp/area clustering plus walkable paths; Factoruide simulates and searches a whole leveling route.
- Useful first design: prerequisite graph + player state => eligible quest actions => merge exact shared targets, then nearby objective areas => score path/farming/travel effort => short stable look-ahead route. Treat quest pickups and turn-ins as explicit stops and preserve player control.
- QuestRoute's documented heuristic is nearest-neighbor plus 2-opt with drop chance penalties; Factoruide documents greedy/region construction and local-search route improvements. Reuse ideas only; inspect licenses before copying code or data.
- Details and source links: `context/quest-optimization-research.md`.

## 2026-11-16 — Settings clarity and layout verification
- Settings confusion came from mixed purposes and hidden cycling interactions: quest markers, tracker selection and quest-dialog actions now have separate categories; every switch names its visible effect.
- `markMobs` draws the game's gold quest badge over a unit nameplate; describe it as ! over quest enemies and state that enemy nameplates must be visible. Shared quest-log stars (`markers`) are a separate feature.
- Settings descriptions/labels must use measured wrapped heights; Quick chat editor must be in the same scroll body. A fixed row pool previously risked silently losing controls after row 18; allocate for all rows.
- Full suite initially failed in unrelated diagnostics because the existing ItemSources.lua calls GameTooltip:HookScript while the mock lacked it. Reproduced with HEAD Settings.lua, then supplied real hook registration in harness; no unrelated feature code changed.
- Verification: 34 files / 1,302 checks pass (11 new settings workflows); layout simulation uses real Lua row positions/text plus Arial font metrics. Actual game appearance/font, clipping and mouse-wheel routing remain for in-game QA.

## 2026-11-16 — Recruitment should go straight to game chat
- The extra recruitment window was caused by a deliberate Menu.lua -> Adventure.open call, not a chat API failure. Reproduce entry-point behavior before blaming delivery.
- `Adventure.question` creates the short linked question; `Adventure.ask` reuses existing current-chat preparation. No need for another sender, settings, or migration.
- Preserve active custom-chat attributes so World selection remains selected; no auto-detect/fallback to another audience. Optional role-play editor stays available separately.
- Tests: 44 invitation/direct-question checks; 60 menu checks; full 34-file run plus tooltip-suite rerun yields 1,314 passing checks. Native game flow remains unverified.


## 2026-11-16 — Quest planner first pass
- Separate quest unlock logic from travel order: any-of and all-of prerequisite edges form layers; stops form a second graph, with quest action dependencies attached to pickups/objectives/turn-ins.
- Shared exact NPC/object IDs are safe merge keys; proximity grouping is a heuristic, so a nearby camp can serve multiple quests without claiming identical objective credit.
- Questie readiness combines requirements beyond prerequisites; only current actionable and explicitly prerequisite-blocked candidates should enter this local plan. Unknown state is not guessed.
- Quest Sharing can provide a useful route list and waypoints from Questie points, but map geometry is not pathfinding. Keep cave/floor routing and drop-weighted travel-time optimization as explicit future work.

## 2026-11-16 — Quest planner scan completion and zone scope
- A Lua local function declared below `scan()` does not bind references compiled earlier; the final timer batch resolved `render` globally and errored after progress reached 5160/5233. Forward-declare the local before both functions.
- Questie adapter exposes all quest IDs via `GetAllIds`, not a zone-indexed quest list; batch catalogue traversal but retain only quests with starter points in the current mapped outdoor zone.
- Recheck map type/city status during async work and before map actions so entering town stops the scan and old route stops cannot create waypoints.

## 2026-11-16 — Quest route panel near the tracker
- The plan is more useful as a persistent, readable stop list than as a centered long-form dialog: keep it near the right-side objective tracker, make stops scrollable, and put waypoint action on each row.
- Avoid embedding custom blocks into Blizzard's tracker internals; position a separate addon frame beside its tracker frame and retain a fallback position when that frame is unavailable.

## 2026-11-16 — Quest plan should begin at zone arrival
- User story: arrive in a zone, reconcile active/completed quests, find locally available quests filtered by character eligibility, group giver errands, then group shared work and turn-ins into outings measured from the player's current position.
- The pickup→objective→turn-in chain must contribute to route cost. Nearest-stop-only ordering can recommend a long giver detour for one quest without comparing its full outing to the nearby alternatives.
- Keep all confirmed eligible quests discoverable; label distant isolated giver groups as long detours instead of silently omitting them. Replan on zone and meaningful quest-log changes while preserving the selected useful stop.
- Implemented: enablement opens/builds the panel; login/zone entry and quest-list changes schedule debounced replanning; objective counts update stop text without traversing all Questie IDs again.
- Outing scoring joins giver/work/turn-in chains plus shared/prerequisite stops, estimates the full trip from the player, and favors groups that serve more quests. It remains a map-distance estimate, not walkable routing or farming-time optimization.

- Published v0.4.16 on 2026-11-16: commit `7c3cc2c1f821aa71204c1ce7dc1b99f0fb9e740b`, tag `v0.4.16`, release https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.16. The uploaded 36-file ZIP matches the local build byte for byte (SHA256 `4f709ffd200182bb90432de74e7d171d514fc75f4d8d0fe0541ee71c91161fb7`). README now documents planner behavior and limitations and links to this release. Tests were not run; native game behavior remains unverified.


## 2026-11-16 — Vendor map search clear state
- The search edit box redraws on `OnTextChanged`; clearing text must hide every pooled pin before returning from the empty-query branch, and clear any saved pin result/closest waypoint state.
- The old item flow switched to a Sellers tab and list while other query types stayed on the map. Keep one map result view and show autocomplete near the input instead.
# 2026-11-16 — Quest planner robustness findings
- Questie source identity is not a reliable geographic cluster key: the same NPC/object can spawn at multiple distant camps.
- Existing repository tests are self-running scripts with an in-file `Game` harness; pytest collection is not supported and yields missing `style` fixture errors.
- Route lifecycle review found no additional confirmed issue in debounce, generation cancellation, town/map gating, or progress-only rebuild paths; native client calls still need in-game validation.

## 2026-11-16 — Local quest voice acting
- ForeverVO already demonstrates local Chatterbox generation + talking-head queue; its capture/generate/restart pipeline avoids promising live file discovery.
- Qwen3-TTS documents VoiceDesign then reusable Base clone prompts; instruction control varies by checkpoint, so voice consistency and acting control must be evaluated together.
- Native Forever speech APIs plus third-party Windows model voices suggest a live path, but actual voice enumeration/control remains unverified.
- Chatterbox current README says retired research since August 2026; Fish official requirements list 24 GB S2-Pro / 48 GB Drama 3 GPU paths. GPU unknown; do not promise local real-time acting or game FPS.
- Existing QuestSharing auto-accept can close the offer immediately; separate narration must capture before acceptance or reliably retrieve text afterward.

## 2026-11-16 — Quest planner arrival, level filter and panel layout
- Questie starter records are sources (`id`, `name`, `spawns[]`); `nearestPoint()` accepts flat points. Passing the wrong shape silently removes giver candidates. Use `nearestSource()` and cover the empty-active-log route.
- On the user's WoW Forever/API 16001 client, use the game's `GetQuestDifficultyColor` result against `QuestDifficultyColors`; quest difficulty is relative to player level and cannot be replaced with a fixed quest-level bracket.
- Variable wrapped text needs variable row height, cumulative vertical offsets, and matching scroll-child height. A fixed wheel step can remain a small navigation increment.
- Quest Sharing's protected-map safety rule forbids opening or navigating Blizzard's map from code. Use the supported native waypoint for right-click and let the player open the map normally.

## 2026-11-17 — Quest narration interface boundary
- Native SpeakText exposes voice/text/rate/volume/overlap, not arbitrary acting directions or NPC metadata; local speech adapter must own configured model profiles and any extra controls.
- Windows adapter can call localhost model server; Lua cannot directly use that HTTP endpoint. Model audio returns through speech engine, not as a Lua WAV buffer.
- Stop/replay sentence and exact pause/resume are different capabilities; native timing/ownership/queue behavior needs client testing. Offline sound manifest remains a separate viable integration path.

## 2026-11-17 — Green quests beside the planned route
- User asks why a green quest on the way can be omitted. Verified QuestPlanner.scan/newCandidate/statusFor: green/yellow is only a level gate; new pickups also need a local starter, supported eligibility and locally mapped unfinished work/known hand-in. One remote or unmapped required target rejects a new quest even if its giver is beside the route. Active quests may still contribute local work/local ready hand-ins. Eligible ready local quests are not intentionally dropped for route proximity; no named quest/reproduction was supplied, so no specific omission diagnosed or runtime change made.

## 2026-11-17 — Settings tool hierarchy
- Extra tools mixed utility actions with equipment searches and profession references; database controls also lived under Map & search. Dedicated Browser DB plus one card per tool makes scope explicit.
- Existing bool-row dispatch can be retained while adding an independent primary action: no setting migration or feature-module rewrite is needed.
- Tool-card layout in the real harness: Extra tools667px /7 rows (five cards/two headers), Browser DB985px /10 rows (seven cards/three headers), both clipped to the existing484px scroll viewport. Browser preview confirms readable card grouping and final controls are reachable.

## 2026-11-17 — Predictive timing versus omission
- The user's roadside example concerns postponement as well as catalogue omission. Eligibility checks alone cannot explain the best timing.
- Same source/camp is insufficient without acceptance and compatible credit. Sequential follow-ups cannot inherit earlier farming.
- DropDB tuple values are percentages even below one, with source labels. Zero is evidence of an unusable source.
- Eight-quest executed fixture predicts 99.23774719 seconds saved from bundling, with identical 160-second travel. A known unavailable pickup reverses the recommended start.
- A dry streak under a fixed independent probability does not itself worsen the expected next-drop wait. Actual remaining counts drive replanning; statistical rate learning remains unsupported.

## 2026-11-17 — Predictive prerequisite and character-state evidence
- A graph can use one parent to establish reachability without forcing that parent in the route; retaining the full gate choices lets a selected quest choose the lower-cost branch. A selected objective must snapshot at its hand-in, or greedy continuation adds irrelevant quests.
- QuestieDB quest fields `requiredMinRep`, `requiredMaxRep` and `requiredSkill` are pairs; `requiredRanks` is an OR list of pairs; `reputationReward` is a list of signed faction-point pairs. The local active-flavor provider must be read rather than importing raw base data. Native reputation `currentStanding`/legacy faction value uses the same absolute scale; Forever `C_SkillInfo.GetSkillLineInfoByID.rank` supplies an ID-based rank.
- The full Lua harness passed 1,731 checks after this work, with both modern/classic adapter fixtures. Actual client behavior, travel availability and performance remain unmeasured.

## 2026-11-17 — Search and uncertainty verification
- Tiny exhaustive enumeration independently matches the optimizer's all, selected, XP and time-budget goals on a six-action fixture. An artificial one-check budget still returns the seeded eight-quest route and reports exhaustion.
- Eight-quest harness result remains 420.95 seconds with eight hand-ins; beam uses 4,013 checks and does not exhaust. Host Lua harness averages ~19.7ms per all-mode solve across 100 runs; the actual game work is cooperatively sliced and must be profiled in WoW.
- Two simultaneous different item objectives at one NPC can overlap, but marginal drop rates alone cannot give their joint completion time. The additive count stays an estimate with `uncertain=true`; two streams also expose a plausible camp range from the maximum versus sum of their separate expectations.

## 2026-11-17 — Map suggestions vs DataWork budget
- Harness tests run DataWork without `debugprofilestop` (80 steps/pump, no time limit) and small catalogues, so they cannot reveal in-game latency. Model client cost by defining `debugprofilestop` and advancing it per provider read; use Classic Era counts 10,122 NPCs / 14,899 items / 4,257 quests / 6,666 objects.
- At 2 ms/100 ms, a one-NPC-per-yield scan of the Era NPC catalogue takes about 4 s of wall time; adding the item catalogue and worldwide seller spawns takes about 12 s for `vendor`. Interactive UI must not wait on whole-catalogue jobs.
- Real QuestieDB (v1.1.2, contract 4) publishes `_G.<Type>DB` = `LibQuestieDB.<Type>` with `Get/GetAllIds/Exists` standalone; table reads return fresh copies, scalar reads are cached after the first.

## 2026-11-17 — QuestOptimizer vs planner input (analysis, no code change)
- `QuestOptimizer.optimize` only **orders** fixed stops; it never chooses *where* an action happens. `QuestPlanner.questActions()` fixes every point first, all relative to the player: pickup/turn-in = `nearestSource()`, objective = `targetLocation()` nearest real camp. So a camp near the turn-in, or one shared with another quest, cannot be picked by the optimizer.
- Search = greedy nearest-legal-action baseline + seeded re-runs (previous plan, road insertion, any-of gate branches, up to 10 shared-camp seeds, up to 12 goal seeds when <=220 atoms) + beam search (width 20) **only when <=40 atoms** (~13 quests). Real zones are usually above 40, so the result is best-of-seeded-greedy; no 2-opt/local-search pass (QuestRoute and Factoruide both have one).
- Shared kill credit needs an identical `campKey(point, npc)`. Camps are clustered per target from that target's own sources, so two quests on the same mob can land on different marks and lose the sharing bonus.
- Travel: walking-path cost only for the first leg (`QuestPlannerPath`), every later leg straight-line * map size / run speed. Fixed 10 s per kill and 3 s per interaction; drop rates only where Questie has them.

## 2026-11-17 — Optimizer gap fixes: measured effect
- Synthetic zone benchmark (`/tmp/qs_bench.py`, random points, lupa Lua 5.1): seeded greedy already = nearest-first; local search cut travel 6.1% (20 quests, converged in 0.9 s CPU) and 4.5% (50 quests, 3.6 s CPU to converge; 1.2% within the 250k default). Real Westfall gains unmeasured.
- First version replayed every candidate from action 1 and restarted the scan after each improvement: 250k steps bought only 1-4 moves. Counting real steps (with pruning), checkpoints every 8 actions and a cyclic scan made 20 quests converge within budget.
- Planner shared-kill e2e fixture: drop from two mobs + kill quest on one of them went from 30 expected kills (separate camps) to 20.09 (shared joint expectation).
- 2026-11-17: Client API differs by widget: `EditBox:SetFont` requires `flags` (Nilable=false), `FontString:SetFont` does not (Blizzard_APIDocumentationGenerated, classic_era + live). Always pass `""`. Harness frames previously lacked `SetFont`, so `if x.SetFont` guards silently skipped the call in tests; harness now enforces the signature by `CreateFrame` kind. Lesson: a `if obj.Method then` guard + a mock without that method = untested native path.
- 2026-11-17: Button textures set with SetNormalTexture/SetPushedTexture are shown again by the client on state changes, so `b.bg:Hide()` does not stick; draw button art as plain textures and swap pushed art in OnMouseDown/OnMouseUp. Harness fills (SetColorTexture) are no-ops, so check opacity by wrapping `NS.style.fill` in tests (see tests/test_classic_style.py).
- 2026-11-18: Lua trap found by the travel-map tests: `return a and a.f and a.f(...)` truncates a multi-value return to ONE value (here `pointOnMap` -> x only, y nil -> arithmetic on nil). Call the function in its own `return f(...)`. Also: the test harness never fires PLAYER_LOGIN, so any `ns.on("PLAYER_LOGIN", ... tick)` loop needs `g.fire("PLAYER_LOGIN")` in the test; the mock frames have no `GetParent`, so track parents in a local.
- 2026-11-18: Two sessions can edit the same working tree (here: VendorMap.lua/Questie.lua item-search rework while the travel/trainer map was built); a failing old test may come from the other session. Check with `NS.db.<my setting>=false` or a temp copy (`mktemp -d`, cp, swap one file from `git show HEAD:`) before blaming your own change. DataWork "idle" jobs are paused (not cancelled) when `valid()` is false, so they need an explicit `Work.resume` from the draw loop. Questie `subName` is the reliable key for trainers ("<Profession|Class> Trainer"); `friendlyToFaction` ("A", "H", "AH") filters by faction.

# 2026-11-18 — Gathering sources and tooltip hooks
- `OnTooltipSetItem` is not fired for Professions-window item tooltips on Interface 16001; use `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)` (data.id is the item) with the script hook only as fallback. Fixed in `ItemSources.lua`, used by `GatherSources.lua`.
- `U.call` returns only 3 values; `GetItemInfoInstant` needs 7 (class is the 6th), so call it through `pcall` directly.
- Addon code must not open or re-centre Blizzard's world map (`ToggleWorldMap`, `SetMapID`): `test_box` forbids it (taint). Print "open your world map (M)" instead.
- Ctrl+right-click on any item: `GLOBAL_MOUSE_DOWN` plus the item GameTooltip currently shown covers bags and custom frames; `ns.on` pcalls RegisterEvent, so an unknown event is harmless. Unverified in game.
- Do not run `git stash` to compare against HEAD in this repo: it stashes all of the user's uncommitted work.

## 2026-11-18 — Bag helpers
- Re-planning before every single move (and doing only the first) makes the bag sort self-healing: loot arriving, a locked slot or a refused move never leave a stale move list. A stable tie-break on the old position makes an already tidy bag cost zero moves, which is what lets the automatic mode converge instead of looping on its own `BAG_UPDATE_DELAYED` events.
- The mock harness needs `C_Container.GetContainerItemInfo` / `PickupContainerItem` / `CursorHasItem` overridden per test (see `tests/test_bagtools.py` WORLD); the shared mock only returns `{ itemID }`.
- Settings window fit: the General tab took one extra header ("During a fight") and `test_look` lists General's headers exactly; Quest items took four rows without overflowing. A 15th tab or long descriptions would break the fit tests.
- QuestieDB (Classic/Forever) has no skinning loot: `npcDrops` of hides/leather is nil and `objectDrops` holds containers (Battered Chest etc.). Verify data assumptions against `https://raw.githubusercontent.com/Questie/QuestieDB/HEAD/data/Forever/foreverItemDB.lua` before building features on a Questie field; item field order there is name, npcDrops, objectDrops, itemDrops, startQuest, questRewards...
- A silent early return is a bug-report trap: every gate in a user-triggered action should say why it did nothing (once).

## 2026-11-18 — Tests were overwriting the published zip
- `tests/test_extras.py::test_the_release_zip_is_ready_to_install` called `build_release.build()` with the default output, so every test run rewrote `dist/QuestSharing-<version>.zip` with the current (often unreleased) code. `dist/QuestSharing-0.4.22.zip` held BagTools/ChatLock/SkinningData, which are not in the release. Fix: `build(out=tmpdir)`; the script also refuses to replace an existing version without `--force`.
- Audit method that worked for dead code (no luacheck/lua installed): regex every `function ns.x`/`X.x =` and count `.x`/`:x` uses across `QuestSharing/` and `tests/`; zero hits = dead, test-only hits = keep. Unused locals: names that occur once in their file.

## 2026-11-18 — Memory map (static estimate, not measured)
- Always resident ~2-3 MB (50 Lua files 1.04 MB source, static data tables, ~90 frame sites, debug log). On-demand catalogues 4-12 MB while loaded: DungeonQuests, Rewards, VendorMap. QuestieDB's own cache grows with every id/field our scans read (probably a few MB, unmeasured).
- The mock test harness never fires `PLAYER_LOGIN`, so timers started there (VendorMap `tick`) do not run in tests unless the test fires it itself.
- Next: user runs `/reload`, `/qs memory`, opens each catalogue, closes, waits 2+ minutes, `/qs memory` again; put the real numbers here.


## 2026-11-18 — Data sources for drop % and rare/timed spawns (research, no code)
- Drop %: QuestieDB `support/Forever/DropTables/classicItemDrops.lua` = `{itemID = {npcID = percent}}`, "automatically generated from wowhead data based upon objective data from our DB" (only items that quest objectives reference); Questie also merges a cmangos ("pserver") table + `itemDropCorrections`. Runtime access: `QuestieDB.GetItemDroprate(itemId, npcId)` (already used by the planner).
- NPC record (`src/meta/npcMeta.lua`, 15 fields): has `rank` (Enum.npcRanks, cmangos creature_template.rank: rare / rare-elite exist), `spawns`, `waypoints`, `npcFlags`, `zoneID`. NO respawn time, NO day/event/holiday condition.
- Respawn timers live in the cmangos emulator DB: `creature.spawntimesecsmin/max` per spawn point; random pick among several creatures at one point = `spawn_group_entry.Chance`; event/holiday/worldstate conditions = `spawn_group` + conditions (CONDITION_ACTIVE_GAME_EVENT / HOLIDAY / WORLDSTATE). Not in any in-game API; Wowhead has no public API (comments only). "Every other day" style rotations are not modelled anywhere found.
- Possible in-game signals (unverified on Forever): `UnitClassification(unit)` = rare/rareelite for a seen unit; creature GUID carries npcID + spawn UID, so deaths/sightings can be timed by the addon itself.

## 2026-11-18 — Respawn time + mob count: measured on the real cmangos classic-db (research, no code)
- Source: `cmangos/classic-db` `Full_DB/ClassicDB_1_12_1_z2815.sql.gz` (13 MB gz, public). Table `creature`: one row per spawn point with `id`, `map`, position, `spawntimesecsmin`, `spawntimesecsmax`, `spawndist`. Parsed 66,310 rows / 7,422 creature ids (copy kept only at /tmp/cmangos-data/db.sql.gz; untrusted download, not in repo).
- Respawn: 300 s is the most common (27,682 rows), then 7200 s (7,638 rows, 499 ids always exactly 2 h), 275/120/180/333 s. 403 ids use a random window (min != max). 620 ids >= 4 h. 241 ids have 1-11 day timers, e.g. Gorefang 24-48 h, Mazzranache 24-48 h, Swiftmane 24-32 h, Zaricotl 24-48 h (3 spawn points), Geomancer Flintdagger 24-48 h. 1,000,000 s = scripted/one-shot, not a real timer.
- Mob count = number of spawn points of the id (e.g. npc 6: 31 points / 180 s; npc 114: 35 / 300 s; npc 589: 6 / 300 s; Rabbit 464). Questie `spawns` already lists the same points; our camp grouping already counts them.
- Depletion model to add to the optimizer (currently unlimited mobs, 10 s each): with N mobs, respawn R, kill time k, K kills needed: time = (ceil(K/N)-1) * max(R, N*k) + lastCycleKills * k. Example K=40 (10 teeth at 25 %), N=8, R=300 s, k=10 s: 1280 s vs 400 s naive (3.2x).
- Caveats: data is 1.12.1 emulator data (Forever may differ; unknown new creatures fall back to defaults), other players compete for mobs, spawn_group pools mean fewer mobs alive than points, a rare "may already be up or dead" (only a per-realm observation tells).
- Build route: offline script -> small Lua data module (npcId -> min, max, spawn count; skip the 300 s default), load-on-demand like other data modules; attribute cmangos (Questie already merges cmangos drop data).

## 2026-11-18 — Party finder and item levels (Classic API limits)
- Blizzard classic_era `LFGListInfoDocumentation.lua`: `C_LFGList.Search` HasRestrictions (click/key only); `LfgSearchResultPlayerInfo` = name, level, areaName, className, classFilename, specName, assignedRole, lfgRoles, isLeader, isLeaver: no item level. No applicant API (GetApplicants/InviteApplicant absent).
- Blizzard's own browse list invites solo results with `InviteToGroup(leaderName)`; solo = `numMembers == 1`; no auto refresh in its code.
- Armory cannot be reached from an addon (no network); only inspect (~28 yd) or addon-to-addon messages give other players' gear.
- Test harness: `tests/test_look.py rows()` used to read only 18 rows; tabs with more rows need the all-rows version.

## 2026-11-19 — Lua: ipairs over a list of maybe-nil values
- `ipairs({ A.f1, A.f2 })` stops at the first nil, so a fallback after a missing function is never reached. Iterate names (`for _, k in ipairs({"f1","f2"}) do local f = A[k]`) instead. Same for `{ info.activityID }` (fine only because it is the sole element).

## 2026-11-19 — Party finder listing gate
- Blizzard's browse list does not trust the server's activity filter: `matchesFilters` re-checks each result's `activityIDs` (non-matching rows drawn greyed). Any addon matching on activity must intersect client-side too.
- `LFGBrowseMixin:SearchActiveEntry` = category of the first non-zero listed activity + only activities of that category; reusing that rule keeps addon searches identical to the game's "search my listing".

- 2026-11-19: Tank aggro: addons cannot select a target in combat (TargetUnit protected; secure button attributes locked in combat), so "auto-select lowest aggro" can only be a visual mark. Nameplates are the only way to list nearby enemies; threat comes from UnitDetailedThreatSituation("player", unit). The test harness frame mock has no SetTextColor: colour text with |cff..|r codes.

## 2026-11-19 — Speed pass 1 measurements (lupa Lua 5.1, /tmp/qsbench/bench.py)
- matchesWords over 25k item names: 25.0 -> 12.9 ms per scan pass (-48 %).
- Questie field miss (QuestDB.Get nil, fallback to QuestieLoader): 60k misses 85.7 -> 61.6 ms (-28 %). Misses are common: most quests have no breadcrumbs/availableUntil etc.
- Dungeon scan prerequisite loop, 10k quests: 5.1 -> 1.6 ms per pass (-69 %), and ~20k fewer short-lived tables per scan.
- Suite after the pass: 54 test files, 2,199 checks + test_aggro (no summary line, all ok), all green.
- test_aggro.py prints no "N/N passed" line; a loop that greps for it must not treat a missing line as a pass.

- 2026-11-19: Full-suite runs can fail on files another session is editing at that moment (test_bagtools, test_lfg_invite). Before blaming your change, rerun the file and run it with your module removed from `harness.FILES`.

- 2026-11-19: QuestieDB catalogue scans that stop on hide must keep a resume closure (or a paused DataWork job); bumping `generation` or resetting `loading` in OnHide silently turns every reopen into a full re-read. Grep OnHide/suspend handlers for `generation = generation + 1` when "it reloads every time" is reported.
- 2026-11-19: SetRaidTarget is #protected (warcraft.wiki.gg API_SetRaidTarget: "can only be called from secure code"; changed to Protected in patch 12.0.0, 2026-01-20; page lists the forever build). Addon code (timers, events, even an insecure click handler) cannot place raid marks. Only a secure path works: a macro the player triggers, e.g. /tm [@mouseover] 8 on a key binding; it can only mark target/mouseover, never a unit the addon picks in combat (secure attributes are locked in combat). Matches the 0.3.3 refusal and the NEVER list in tests/test_box.py. The automatic X/skull in Aggro.lua (A.marks) must be removed or replaced.

## 2026-11-19 — Dungeon route
- Questie spawn points carry `map` only through `Q.uiMapOf(area)` (ZoneDB areaIdToUiMapId); test data must use AREA ids (Elwynn 12) and a mocked ZoneDB, or `point.map` is nil and nothing routes.
- Real-data scan (Forever, 5,851 quests): 9 one-way `nextQuestInChain` lead-ins into dungeon quests, 0 breadcrumb fields, 6 lead-ins with no link at all (Seeking Caitlin, Dragonmaw Rumors, 4 Alterac Valley). Script `/tmp/leadscan/scan.py` (not in repo).
- Grouping same-NPC pickups and dropping <5 s walk hops cut a sample route from 24 to 11 steps; the readability win is larger than any order tweak.


- 2026-11-19: To persist a QuestieDB catalogue cheaply, save the IDs a full scan KEPT, not the records: the next session reruns the same code over only those IDs (identical results, fresh localized names). The kept set must include everything the output reads, not just the result rows (DungeonQuests: quests linked to/from a record, or chain names vanish). Validate with a two-session test: serialize QuestSharingCache from game 1 into game 2's pre-script (tests/test_saved_lists.py `saved_file`).

## 2026-11-19 — Coldridge Valley reference case
- Real QuestieDB data found model gaps that synthetic tests never showed: units (map fractions vs yards), level forecast (quest XP only, one level), category filing (class quests). Synthetic fixtures test the code; a real zone tests the model.
- The optimizer itself was already near-optimal (0.8 % from annealing); the large wins (1,541 -> 1,211 s, 10 -> 14 quests) came from what it is told (which quests, which XP, which distances), not from more search.
- More search budget changed nothing (local optimum at ~37.5k moves for 250k-5M budgets). Spend effort on the cost model, not on the search.
- When mocking Questie, emulate `IsDoableVerbose` + `DoableStates`; with only `IsDoable` every chain follow-up looks "unknown".
- 2026-11-19 network view (`tools/coldridge-network.html`): all 10 Coldridge camps (>= 5 spawns, 100 yd) serve 2+ quests. Burly Rockjaw Trogg spawns in 8 of 10 camps (A New Threat fills itself). Whelps + Grik'nir share camp A4, but The Stolen Journal unlocks only after The Troll Cave hand-in, so the chain forces a second trip there. Felix's 3 objects sit in whelp camps (A2, A5, A8) but the quest needs level 3, so it cannot ride along with the whelp kills at level 1-2.
- 2026-11-19 shared camps view: in the harness a hidden parent does not make child textures report hidden (`IsShown` is the own flag), so map-layer tests must check the overlay frame's `shown`, not each circle.
- 2026-11-19 preview of real WoW windows: the harness keeps only the last SetPoint and drops colours; `tools/preview_camp_window.py` patches CreateFrame to record all anchors, colours, alpha, fonts and justify, then resolves layout itself. Reuse it for any new window to see layout bugs (overlapping headers, hidden labels) before an in-game check.

## 2026-11-19 — Forever dungeons
- Wowhead Forever list pages are JS-only (curl 403 / WebFetch empty), but `https://www.wowhead.com/forever/search/suggestions-template?q=NAME` returns JSON (zone ids, guide ids), and guide pages (`/forever/guide=ID`) carry the markup in `printHtml("...")` with `[quest=ID]` and `[zone=ID]` tags.
- 9 new Forever dungeons (guide 34783): Hall of Thanes 16919 (13-18), Ruins of Lordaeron 16611 (15-20), Excavation Site 16732 (24-29), City of Dalaran 16544 (28-33), Drowned City 16550 (35-40), Krol'dok Stronghold 16842 (40-45), Alcaz Prison 16620 (48-53), Blackmaw Hold 16554 (55-60), Shaper's Terrace 16667 (58-60). QuestieDB files quests for only Shaper's Terrace (as 16985) among the last five.


- 2026-11-19: "The guide closes and re-calcs by itself" = noisy events (BAG_UPDATE_DELAYED, UPDATE_FACTION, SKILL_LINES_CHANGED, SPELLS_CHANGED) passed force=true to scheduleRefresh, and scan() emptied `route` before rebuilding; plus sub-maps (mines are mapType 5) made currentZone nil -> clearPlan. Measure with a counter on ns.dataWork.start("quest-plan") and visible rows right after the 0.65 s debounce (advance 0.651) before the job pump runs.

- 2026-11-19: Saved ID lists in account-wide `QuestSharingCache` must include every filter applied before saving in their scope key (faction, class). `mapSearchNPCs` lacked faction -> other-faction alts saw no own-faction sellers. Harness has no `UnitFactionGroup`; set it in tests or faction filters are silently off.

- 2026-11-20: A believable offline preview of WoW frames is possible: patch the lupa mock (record every SetPoint anchor, SetAllPoints, SetScrollChild, SetColorTexture, SetAlpha), resolve absolute rects in Lua, and paint with PIL. Real Blizzard textures and the UI fonts (fonts/frizqt__.ttf 615960, fonts/morpheus.ttf 615962) download as BLP/TTF from `https://wago.tools/api/casc/<FileDataID>?download`; the FileDataID comes from the community listfile. PIL reads BLP2. macOS system python3 lacks SSL certs, so fetch through `curl`. Preview art stays in /tmp and is never shipped.
- 2026-11-20: Blizzard EJ boss portraits are not named consistently: older files use spaces (`ui-ej-boss-mutanus the devourer`), newer ones do not (`ui-ej-boss-edwinvancleef`). Look up both spellings.
- 2026-11-20: Turning aggro numbers on prints A.status() (threat API, enemy nameplates CVar, visible plate count). Ask the user for that line first when they say aggro shows nothing in game.

- 2026-11-20 release candidate 0.4.29: all 68 self-running suites / 2,870 checks pass, with exit code + FAIL output + summary/completed-case verification; 66 Lua 5.1 compilations pass. Runtime equals cutpdf/main 703ff0d except TOC version. Prior changelog sections preserved; build_release.py unchanged. Native game unavailable.
