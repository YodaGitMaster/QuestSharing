# Decisions

## 2026-11-19 — Speed pass 1 (tools/lua-optimization-prompt.md)
- Rule: apply only with a Lua 5.1 benchmark saving >= 20 %, identical behaviour, small local diff; else report only.
- Applied: (1) `VendorMap.lua` matchesWords splits the query once per new query (one-entry cache), not once per item name. (2) `Questie.lua` questieModule keeps the found QuestieDB module while the same QuestieLoader table is installed; a failed/not-started lookup is not kept. (3) `DungeonQuests.lua` scan: prerequisite and breadcrumb loops unrolled, no `ipairs({a or {}, b or {}})` / `{number(x)}` tables per quest.
- Report only: per-frame handlers are already throttled (0.04-3 s); QuestGuidance drawMap already skips unchanged views; DataWork `table.remove(queue,1)` and Core timer list have n < ~10; `ns.after` calls `debugstack` per timer (WoW API, cannot benchmark outside the game); ItemSources tooltip reads are per new item only; QuestOptimizer/QuestPlanner work is step-budgeted, so a cheaper step buys more search, not less CPU - left alone without in-game profiling; hud `SetText` every 0.1 s could skip unchanged text (unmeasurable here).

## 2026-11-18 — Party finder auto-invite
- One search per click/key (C_LFGList.Search HasRestrictions in classic_era source), no timer scan; invite solo players (numMembers==1) by lfgRoles via C.invite; healers on by default, own-window watching (lfgWatch) off by default so browsing never invites by surprise. Rows live in the Party window tab (no 16th tab fits). Gear number not built: no ilvl in LFG data; only addon-message (Quest Sharing users) or inspect (nearby) possible, waiting on user.

## 2026-11-19 — Role need vs supercharge
- Normal mode now respects a dungeon party shape (1/1/3) so a healer-only search invites one healer; user asked for an opt-in "supercharge" that invites all matches because one may not answer. Supercharge capped at 10 per click (chat + invite throttles) and does not count open invites as taken spots; no auto-kick of extra accepters (rude, and protected/uncertain) - the tooltip warns instead.

## 2026-11-19 — Invite whisper
- Default ON (user asked for it); editable text with {dungeon}/{role}; reuses `ns.chatAllowed` + `ns.trying("chat")` so a refused automatic message switches chat off once and is logged, instead of erroring on every invite.

## 2026-11-19 — Party finder needs a listing; picker on the spyglass
- Hard prerequisite (user): own active listing with an activity; no toggle. Mirrors Blizzard `LFGBrowseMixin:SearchActiveEntry` (category of first activity, only that category's activities) + client-side activity intersection because Blizzard's list also re-checks results (`matchesFilters`).
- Classes saved as an exclusion set (`lfgClassOff`) so the default is "all classes" and new roles need no migration; kept out of ns.defaults (table defaults break reset and the every-default-has-a-control test).
- Order = highest level first (user default), then known item level. Spyglass left click opens the picker instead of searching; the key binding keeps the instant search.

## 2026-11-18 — Item levels for the party finder
- GearScore/TacoTip model (inspect nearby + cache + share between users of the addon) chosen; armory query rejected: addons have no network, SavedVariables only sync on /reload/logout, so an external Battle.net API script cannot answer in time (and Forever coverage unknown).
- Ask-first waits only when a minimum item level is set (no delay for "any"). Unknown default = invite (never silently lose a healer); user can pick skip.
- Separate prefix QSILVL (works outside a party, independent of the `sync` switch); answering is behind `ilvlShare` (default on).

## 2026-11-19 — Save QuestieDB ID lists to disk (QuestSharingCache) so a new session skips the full scans
- User approved after the options table: persist only the IDs each full scan kept, not the records (tens of KB, not MB; records stay fresh and localized).
- Invalidation: stamp = game build + Quest Sharing/Questie/QuestieDB versions (GetAddOnMetadata "Version"); mismatch wipes all. "Refresh data" buttons (D.scan(true), R.scan(true), L.scan(true)) do a full scan and overwrite; Purge deletes the whole file; each module purge forgets its own list.
- Dungeon quests save records PLUS any quest linked to/from a record (prereqs, nextQuestInChain, breadcrumbs, availableUntilCompleted, inferred lead-ins): with records only, chain names to non-dungeon quests would be lost (`linkedIDs`).
- Abandoned: saving map-search vendor items (learning pass read every item's vendor list on the first search, breaking test_data_budget's "vendor links only for matching names" rule). NPC role list is saved instead (the expensive pass). Gather sources not saved (per-item, already cheap).
- Planner zone lists keyed by zone+race+class+level, keep 40 (level change = new key, same as the in-memory rule).
- Not checked in game: SavedVariables write size, real QuestieDB version strings.

## 2026-11-19 — All QuestieDB catalogues: load once per session, one Purge (supersedes the 2026-11-18 120 s grace entirely)
- User: "do the same for all other database operations (the db is always one QuestieDB)" -> one shared Purge, not one per module.
- Registry `ns.dataWork.onPurge(name, fn)` / `W.purge()` / `W.purgeNames()` in DataWork.lua; `ns.purgeData()` (Diagnostics.lua) runs it + garbage pass; Settings row "Free the loaded quest database data" (browser tab, button Purge) and `/qs memory purge|free`.
- Registered: Dungeon quests (D.purge), Quest rewards (R.purge), Dungeon loot (L.purge), Map search (V.purge = resetIndex), Trainers (I._reset + revision), Where to gather (cache), Quest guide zone lists (zoneQuestIDs/zoneScope/zoneOrder).
- Pause instead of discard on hide: Rewards `batch` and Loot `step`/`pumpNames` store a `resumeScan`/`resumeLoot` closure when hidden; R.open/L.open run it. VendorMap `releaseWhenIdle` removed. Planner 2-zone cap removed (ID lists are small).
- Kept as is: planner route is still recomputed per open (depends on position and log, not a DB read); gather cache still cleared on PLAYER_LEVEL_UP and zone lists re-read on a level change (results depend on level). Switching a feature or the addon off still frees its catalogue.

## 2026-11-19 — Dungeon quests: load once per session, purge from Settings (first step; generalised by the entry above)
- User: reopening the dungeon finder re-read the DB every time; wants "load it once and purge in settings".
- Chosen: `DungeonQuests.lua` no longer calls `releaseLater`; hide (`f.suspend`) pauses both `OWNER` and `REWARDS_OWNER` jobs (rewards were cancelled+wiped before). `D.open` resumes rewards when ready. `D.purge()` = `release()` + rescan if visible. Settings row `browser` tab, button "Purge". `D.close` (addon switched off) still frees.
- Scope: session only (Lua memory is wiped on /reload/logout). Not persisted to SavedVariables: large, and goes stale when Questie updates. Quest rewards (Rewards.lua) and map search (VendorMap.lua) keep the 120 s grace below.

## 2026-11-18 — Memory: free the big catalogues after 2 minutes closed
- Problem: Dungeon quests (`records`, chain tables), Quest rewards (`index`) and map search (`vendors`, `itemRows`) were built on demand and never freed; a paused half-read dungeon scan even kept its coroutine locals alive.
- Chosen (user, 2026-11-18): grace period of 120 s after the window/map closes, then free; reopening inside it is instant, later it rescans. Alternatives dropped: free at once (every reopen rescans, the slow first scan), manual `/qs memory free` only.
- Mechanism: `ns.dataWork.releaseLater(owner, seconds, fn)` / `keep(owner)` / `releasePending(owner)` in `DataWork.lua` (one `ns.after` timer per owner). `DungeonQuests.release()` and `Rewards.release()` run from the hide handler (guarded: skip if the window is visible again); `D.open`/`R.open` call `keep`. Map search has no window: `VendorMap.lua` `releaseWhenIdle` runs in its own `tick` and calls the existing `resetIndex()` after 120 s with the map hidden or the search box empty.
- Switching Quest rewards off now frees the half-read index (test_optional expectation changed from 100 kept rows to 0).
- Debug log cap `LOG_MAX` 3000 -> 1000 (stays on by default, user choice).
- Not freeable from here: QuestieDB's own per-(id, field) cache that our scans fill. Static data (CookingReference, SkinningData, TravelData) and frames left alone: .toc files load eagerly, small gain.
- New `/qs memory` (`ns.memoryLines` in Diagnostics.lua): `GetAddOnMemoryUsage` for QuestSharing/Questie after a garbage pass + loaded/free per catalogue + log size.

## 2026-11-18 — Gathering-item sources in tooltips + Ctrl+right-click map marks
- New `GatherSources.lua`, gated by the existing `itemSources` setting (no new switch). Gathering = `GetItemInfoInstant` class 7 (Trade Goods), subclass 5-10 (cloth, leather, metal & stone, meat, herb, elemental).
- "Concentration" = number of known spawn points of one creature name in one zone (Questie has no density or drop-rate-ranked list); best creature per zone, top 3 zones. Drop % shown only when `Q.itemDropRate` has it. Friendly creatures (friendlyToFaction has my faction) skipped; dungeon spawns skipped (no map).
- Computation is a DataWork job (`gather-sources:<id>`, 6 ms budget), cached per item: common hides have hundreds of droppers. Cap 400 sources, 40 pins per zone.
- Ctrl+right-click via `GLOBAL_MOUSE_DOWN` + the item GameTooltip currently shown, so it works in bags and the Professions window alike (`HandleModifiedItemClick` would miss custom frames). Deduped within 0.3 s.
- Abandoned: opening the map/jumping to the zone from code (`ToggleWorldMap`, `WorldMapFrame:SetMapID`): taint risk, `test_box` forbids it. We print "open your world map (M)" and set the game waypoint instead.
- 2026-11-18 follow-up (user: Light Leather showed nothing): QuestieDB `foreverItemDB` has NO skinning loot (Light Hide 783: npcDrops nil, objectDrops = Battered Chests; Light Leather 2318 likewise), so hides/leather can never come from Questie. Added bundled `SkinningData.lua` (45 items, 3,059 creature links, 27 KB) generated by `tools/build_skinning_data.py` from CMaNGOS classic-db `creature_template.SkinningLootId` -> `skinning_loot_template`, chance >= 1%, stored as tenths of a percent. Creature names, levels and spawns still come from Questie. Data is factual drop tables from a GPL project; attributed in README/script header. `objectDrops` only count for metal/stone, herb and elemental (otherwise they are chests/bags). Ctrl OR Cmd (Mac). `/qs gather` + one-time chat hints replace silent failure.
- 2026-11-19: SUPERSEDES the subclass 5-10 gate above. Classic item data uses 7/0 for leather/hides/cloth/ore/meat and 5/0 for elementals; gathering = skinning-table entry, 7/0, 7/5-10 or 5/0. Object sources are filtered by container NAME (chest, strongbox, crate, box, locker, coffer, cache, barrel, sack, bag, trunk), not by subclass. Rejected: a hand list of item IDs (hundreds, goes stale).
- 2026-11-19: Gather ranking (user: top 3 with name, location, %, by my level and faction). Fit = creature minLevel <= level+3 (low creatures are fine for gathering) AND zone not a home zone of the other faction. HOME is a short hand list (Elwynn, Dun Morogh, Teldrassil, Westfall, Loch Modan, Darkshore / Durotar, Mulgore, Tirisfal, Barrens, Silverpine): contested zones stay open because their status is not certain from memory. Score = spawns x chance. Non-fitting zones are never mixed with fitting ones; they show only when nothing fits (empty tooltip judged worse). Rejected: hiding non-fitting entirely; ranking by level distance (low mobs are good for leather).
- ItemSources.lua itself moved to the `TooltipDataProcessor` post-call (the old `OnTooltipSetItem` script is not fired for Professions window tooltips on Interface 16001).

## 2026-11-17 — Foreground budget for the Dungeon quests scan (user choice)
- User chose "Faster + keep progress" over "keep progress only" and "stream results".
- `DataWork.start(owner, run, valid, finished, budget)`: optional per-job budget in ms; jobs without one keep the shared 2 ms / 80-step slice even when a foreground job runs. Only DungeonQuests uses it (8 ms), and only while its page is visible (valid() pauses otherwise).
- Hide pauses (keeps partial coroutine/tables in memory); master disable and Refresh data cancel. Rewards hover scan keeps cancel-on-hide.
- Rejected for now: streaming partial results (bigger change); per-quest instead of per-read yields (little gain under the time-based profiler budget).

## 2026-11-17 — Quest planner: zone membership and objective camps (user choices)
- **Scope = this zone's quests.** Membership comes from Questie `zoneOrSort` -> `uiMapOf()`, accepting the current map or a descendant of it. A spawn that happens to be here does not make a quest belong here. Negative sorts (class, profession, event) and other zones are left out even with a local giver or mob; reasons go to `coverage.external` for `/qs plan why`.
- **Exception:** an active quest from another zone appears only for its local hand-in, once it is ready (log `complete`, or a breadcrumb with no objectives in the log or in Questie).
- **Fallback:** `zoneOrSort` missing, 0, or not mapped (e.g. old Questie without ZoneDB) -> keep the pre-change location rules, so quests don't silently vanish.
- **Objective place = nearest real camp.** Group the target's spawns per map into camps: the densest unassigned spawn seeds a camp of the spawns within `CLUSTER_YARDS` 100 yd (2026-11-19; `CLUSTER_DISTANCE` 0.065 map fraction only when the map size is unknown); the camp's point is the member nearest its centroid. A camp is real when its size >= min(3, the target's largest camp on any map). Choose the real local camp nearest the player. The chosen camp depends on the player only through "which camp is nearest", so a step switches only when another camp gets closer.
- Rejected: biggest camp (stable, but can send you far past a nearby camp); nearest single spawn (old behaviour: step 1 lands on the player and follows them).

## 2026-11-17 — WoW-style search journal
- User requests a more beautiful WoW feel across existing searches. Scope all3shared explorer tabs; keep data/filters/actions/layout destinations and avoid globally changing Settings/profession/map tools.
- EquipmentUI owns themed button/list-button/field/text/surface helpers; Rewards/Loot/DungeonQuests switch their UI creation to those. Use existing-client dialog/QuestBG/Quickslot2/native red-button art, Friz/locale fonts, warm opaque panels, gold states and dark parchment ink. Retain button scripts/disabled states, larger popup layering and existing outer dialog/scaling; no new runtime assets/providers/timers.
- Darken only gold/yellow quest-link codes inside parchment detail output so they remain readable; source text/IDs/hyperlinks and other features remain intact. Dungeon detail scroll uses690px panel height; old equipment panels default550.
- Verify release-based isolated snapshot because current workspace has concurrent diagnostics/profession/optimizer changes.44suites/1,627checks pass,42Lua modules compile and CRC/source package pass. First snapshot Extras failure was missing copied root build_release.py, not runtime; copied release root fixture and35/35rerun pass. Current workspace full run had3diagnostic-related assertions outside scope; do not claim that mixed run passed or overwrite others' work.
- Browser layout emulation exports real Lua row/details (27raw Deadmines quests;2reward/4loot fixtures) and approximates native art. All3tabs/rowselection visually inspected; native WoW validation remains pending. Source tools are not shipped.
- Provide4file UI overlay for existing v0.4.19+ installation so user retains other previews/updates; also keep full stable-baseline preview separately. No new release requested. Preview screenshot: `/Users/francesco/.codex/visualizations/2026/11/17/01a1e8ac-7734-78d1-bcb9-43551860a2d8/search-journal-preview.png`; emulation `search-journal.html`, browser tab1 on localhost8792, server exec43787.

## 2026-11-17 — Readable troubleshooting overview with complete copying
- User says combined diagnostics remain messy and asks for friendly issue reading plus copying everything; continuation authorizes completing the redesign.
- Keep one window, but open a plain-language overview with numbered newest-first issues, timestamps/repeat counts, friendly paused-feature names and separate client/setup notes. Do not label client limitations as additional addon errors or guess root causes.
- One frozen snapshot has overviewText/fullText/showingDetails. Full report contains every retained message/stack/log, section headings and one labelled setting per line. Copy all always switches to/selects fullText; Ctrl+C/Cmd+C is the user's native clipboard action. Toggling views never refreshes or drops records.
- Larger14px text/4px spacing, no initial selection/focus, explicit full/overview toggle and Refresh. Opening log/errors/doctor no longer dumps technical text to chat. Preserve existing slash clear semantics, bounded storage, logging defaults and unrelated local work. Native game rendering remains unverified; no publication requested.
- Verification: diagnostic47/47; frozen HEAD baseline plus Core/Diagnostics, scoped General settings rows and affected tests passes44 suites /1,629 checks,42 Lua5.1 compilations. Snapshot path recorded in state.md. Shared-workspace test transiently encountered concurrent settings/optimizer work; latest broad run44 existing suites pass, new planner-facts0/8 remains unrelated in-progress work. No unrelated fix/reset performed.

## 2026-11-17 — Replace rejected companion with an embedded native profession GUI
- User approves the redesigned preview with "yes like this"; this is the accepted GUI direction. Preserve its structure in subsequent changes; native game testing remains pending.
- User rejects the separate small-text companion and explicitly requests a full rethink inside the same game panel. This supersedes the earlier companion-window decision; existing authorization covers the redesign, with no new approval checkpoint or publication implied.
- Reproduce native-parent mismatch/six-row paging before edits. Split model/lifecycle in Professions.lua from ProfessionUI.lua; render own child list/source/Upgrades panes inside ProfessionsFrame, retaining native shell/close/position and native learned-recipe crafting.
- One scrollable catalogue, 44px rows, separate Recipe/Skill/source fields, grey clickable unlearned recipes. Main source pane uses measured 14px text, 18px heading and structured requirement/source/ingredient sections; keep provenance in reference docs rather than repeat it in every visible dish.
- Reject native filter loops and synthetic recipeInfo injection. Only pass live learned info to `CraftingPage:SelectRecipe(info,true)`; unlearned selection clears native transaction/selection and validates controls. Visible row remains authoritative when Blizzard rebuilds/auto-selects from its hidden filtered list.
- Upgrades is a ProfessionsFrame child accessible from any profession and overview; direct faction buttons. If native UI isn't available, instruct K/choose profession; never recreate the rejected standalone fallback.
- Native recipe IDs supplement the static reference with positively matched live Cooking records. No Questie catalogue scan; guard own/linked/changing sources, 12-read slices, combat/close cancellation. Current faction gets preferred vendor locality in short labels.
- Package on released c2f5a06 plus only task-owned profession runtime and scoped Settings copy because concurrent unrelated local changes are in flight; preserve them in the workspace. Tested snapshot `/tmp/questsharing-profession-native-verify-20261117`; final counts/hash in state.md.
- Visualize skill used for an actual-model-data preview with explicitly illustrative learned states; browser inspection isn't native WoW verification. Reload its full skill before editing the preview in a later session.

## 2026-11-17 — Separate dungeon chain status from task type
- User confirms dungeon selector works, then requests clarity between chain quests and NPC conversation steps. Initial-only All dungeons reproduced while catalogue loads, but user resolved it; no speculative dropdown fix.
- Chain membership and task are independent: a prerequisite can be Talk only, item delivery or an escort. Build reciprocal previous/next mappings once from known prerequisite/next links, expose role within selected dungeon and show linked names/IDs in hover/detail. No invented linear numbers on branching chains.
- Lazy cached task classifier uses structured objectives, exploration, extra/required-source work, event specialFlags and provided/starter items; native active objectives are a conservative fallback. NPC hand-in with no work -> Talk only; object/unknown explicit. Invalidate cached task labels on visible debounced log changes. Text plus color communicates purpose; no extra login catalogue scan or filters.
- Five102px rows at106px spacing keep independent task and existing pickup/turn-in lines inside530px. Other explorer tabs unchanged.
- Validate/package against isolated v0.4.19 runtime snapshot plus current DungeonQuests.lua, since profession redesign is active concurrently. Seven affected suites301checks (58 dungeon); all42 Lua modules compile; raw Classic quest smoke65Talk Wiley,155escort,166collection; source/CRC verification pass. New44-file clarity preview; existing stable release/assets unchanged, no new push/release requested. Native rendering remains pending.

## 2026-11-17 — Map-search dependency feedback
- User reports empty map searches and uncertainty about Questie requirement. Reproduced absent-data state on modern/classic harness: misleading instructions/no-known-seller with zero pins. README installation section also incorrectly promised every other feature worked without Questie.
- Require enumerable NPC **or** item database through global/LibQuestieDB providers; full Questie/quest DB is not required. Check method presence only before blank/query render, preserving no-catalogue-work startup and partial-provider support.
- Explain missing data versus non-enumerable installed data; show QuestieDB-only support and `/qs questie`, update/enable/reload guidance. Reuse existing disable reset for provider loss; preserve query for late retry. No bundled data, matching changes or new dependency.
- 88 map checks + 129 related checks pass; local/unpublished. Exact installed version, query/map and provider state requested asynchronously; no reply yet. Native in-game cause/rendering unverified; other concurrent profession/diagnostic/dungeon changes preserved.

## 2026-11-17 — Default diagnostics and one copyable report
- User requests logging/errors/troubleshooting on by default and one window to copy everything at once.
- `debug=true`; once-only `diagnosticsDefaultMigrated` enables existing saved false settings, then preserves subsequent explicit off. Error capture stays independent of debug.
- All three existing entry commands and one General action share a fixed combined snapshot. Include doctor checks, sorted defaults-backed settings, blocked features, full retained errors/stacks and full retained debug buffer; keep bounded storage, remove narrower display caps.
- Refresh is explicit so new events cannot overwrite selected text during copying. Combined clear empties both lists; existing slash clear arguments retain their respective-list behavior. No release requested; preserve concurrent profession/dungeon work.
- Verified diagnostic suite41/41, complete current workspace44 suites /1,661 checks, 43 Lua5.1 compilations and diff checks; native game layout remains unverified.

## 2026-11-17 — Publish current workspace as v0.4.19
- User explicitly requests "push and release", authorizing commit/push/publication of the completed local guide, map search, data-loading, dungeon quest, cleanup and profession work; supersedes earlier local-only packaging decisions.
- Follow existing main/annotated-tag/GitHub Release workflow; retain all earlier immutable tags/assets. GitHub connector lacks release creation and binary upload, so use git/gh.
- Promote Unreleased notes, bump TOC and README links to 0.4.19, run all self-running test scripts and Lua 5.1 compilation, source/CRC-verify package, then verify remote tag/main and downloaded asset bytes.
- Include continuity/research/testing/tools in source control; install ZIP includes only runtime Lua/TOC/XML, preserving embedded MIT attribution. Native game behavior remains unverified and is stated in release notes.
- Completed: release commit/tag target `d0b859820f9b8fdb0a100e2bdc69b5363574a605`, atomic main/tag push; https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.19 is latest stable. All 44 suites / 1,617 checks, 42 Lua compilations and diff checks pass. Downloaded 44-file ZIP byte-matches source/local build and passes CRC; 231,769 bytes, SHA256 `f1a6e29d91fddeef01408f44132b703ff0a18ad3a055ac4170feb6ed094ab46e`; published notes match.

## 2026-11-17 — Cooking and static profession-upgrade companion
- User authorizes recipe discovery/farming hints and a both-faction/all-profession upgrade reference; confirms "crafting menu" means the game's native profession window. Repository has only a water editor, so add native-window companion buttons and fishing-editor Cooking entry point.
- Isolated read-only companion because Forever's native provider resets `SetShowUnlearned(false)`; never fight its filters. Native child guide buttons open the companion's Cooking/Upgrades tabs; `/qs cooking`, `/qs professions` and Extra tools provide fallback access.
- Bundle a small generated factual Cooking subset of pinned MIT Profit data, retaining full license notice; 133 reference records includes unconfirmed/unknown entries. Guide facts fill starter-fish source gaps and provide ranks for all 12 professions, both factions. Record date/provenance and guides' beta caveat; no guessed missing sources.
- Enable `professionGuide` by default as expressly requested; explicit off switch/master disable removes all integration. No login scans or new saved learned-state cache. Read own Cooking only, 12 static recipe IDs per slice; false is Missing, nil unknown, combat pause and generation cancellation.
- Farming uses hovered ingredient's direct installed Questie source records, existing zone ranges, seven guide-backed fish examples and optional AnglerAtlas estimates. Do not bundle Questie data, equate an area's fishing recommendation with its entry threshold, or label recipe books as ingredients.
- Verification: 34 focused checks; 44 suites / 1,617 checks; 42 Lua 5.1 modules compile; real raw Classic Questie smoke resolves all recipe/ingredient lookups without errors. Native game validation remains pending; local preview only.

## 2026-11-17 — Dungeon quest hover and row locations
- Completed: 48 focused checks, full 43 suites / 1,573 checks, Lua 5.1 syntax/diff checks and actual raw-data XP/reward smoke pass. Rebuilt 41-file preview source/CRC verified; native rendering unverified.
- User asks for XP/rewards on mouseover and pickup/drop locations in the row; interpret drop as quest turn-in and state that assumption. Keep previous dungeon search/menu/filter behavior.
- Six 84px rows provide separate pickup and turn-in lines, with alternate counts and full giver lists on hover/detail. Cache per-record source projection rather than reread on each repaint.
- Read active-flavor QuestXP support `{questLevel,baseXP}` (legacy module fallback), explicitly label base XP, preserve zero versus unknown. Do not infer buff/level adjustments or display another selected quest’s XP. API verified against https://github.com/Questie/QuestieDB/blob/master/docs/api.md and upstream Database/QuestXP/QuestieXP.lua.
- Quest records do not expose guaranteed/choice item rewards: use existing Item.questRewards reverse links, all item qualities/types. First hover starts a budgeted item-link scan; completion and item-cache events refresh only active tooltip. No login/initial-open item enumeration; combat pause, tab/close cancellation and completed-index reuse. Label choices possible; no invented amounts, cash or guarantee of every reward together.

## 2026-11-17 — Dungeon quests include inside and outside work
- Completed: new 32/32 checks; current full workspace 43 suites / 1,557 checks; Lua 5.1 syntax/diff checks and raw Classic dataset smoke pass. Separate 41-file unpublished preview source/CRC verified; see state.md for path/hash.
- User explicitly requests another dungeon search: all quests associated with a selected dungeon, inside and outside, filtered by Horde/Alliance/class/level, usual right-click menu and pickup map actions. Implementation authorized; no publication requested.
- Third shared explorer tab and `/qs dungeons`; default all factions/classes/levels/completion. My character narrows these; All quests broadens while retaining dungeon. Equipment-only controls hidden/scoped to old tabs, no reward-quality restriction on quests.
- Reuse known Classic/Forever dungeon area registry, Questie enumerable fields/location links, prerequisite ancestors and explicit follow-ups. Label outdoor preparation/follow-up entries rather than promise immediate eligibility. Faction masks do not restrict to the current race.
- Real upstream Classic data smoke (4,244 quests) exposed false dungeon membership from shared wool/leather/food/crafted-material drop sources: reject objective-item inference when any known source is outdoor/unknown. Explicit dungeon category and actual dungeon NPC/object/quest-starter links still count. Smoke now produces 580 associated quests; Deadmines contains expected Defias chain/outer-mine quests/Paladin quest and excludes cloth donations/ordinary tradeskill turn-ins. Raw data smoke omits runtime provider corrections; installed coverage remains authoritative.
- DataWork explicit-open worker, per-field checkpoints, combat/close cancellation, 256-source association cache; no login scan, item enumeration or new SavedVariables. Reuse completed index; debounce quest-log detail/completion refresh.
- Extend Menu.lua with optional item list and dynamic row pool. Catalogue entries skip native quest-log-index calls; unavailable log actions explain why. Use real log entry after acceptance. Pickup actions reuse native waypoint and print M/map directions; never open/redraw protected map or pin sentinel coordinates.

## 2026-11-17 — Leftover quest item cleanup
- User requests another utility to delete quest items left in carried bags without a quest currently held. Implement an explicit Extra tools action and `/qs cleanup`; no persistent toggle, background scans or bulk deletion.
- Absence of an active match is a review candidate, not proof of uselessness: show future-use caveat and confirm one whole stack permanently. Keep quest starters even when not accepted; protect ready-to-hand-in quests as well as unfinished ones and every zone.
- Require Questie coverage of active quests and recognized item records; skip unknown items/native metadata, protect source/objective/special item IDs and native/reverse active associations. Do not enumerate a catalogue or inspect bank inventory. Ordinary materials remain outside cleanup unless the game marks them as quest items.
- Native field/API references verified: [Questie Item schema](https://github.com/Questie/QuestieDB/blob/master/src/meta/itemMeta.lua) documents `startQuest`, `relatedQuests`, `class`; [game item API declarations](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua) document GetItemInfoInstant classID; [game bag UI source](https://github.com/tekkub/wow-ui-source/blob/live/FrameXML/ContainerFrame.lua) shows legacy quest flags. API adapters remain local to cleanup.
- Destructive boundary: rebuild fresh requirements, compare original slot/ID/count/link, refuse unreadable/busy cursor/combat/disabled addon, pick up and check cursor identity before deleting. Refusal restores item with ClearCursor and explains manual fallback. Native client protection must still be checked in game.
- Recheck requirements/combat/master state after pickup callbacks and read cursor identity again immediately before deletion; native IsOnQuest also protects reverse links to hidden active quests. Focused 34/34 checks pass on modern and actual legacy container APIs; full 43 suites / 1,557 checks, all 39 Lua modules compile and diff checks pass. Preview CRC and source byte-match pass: 41 entries / 211,033 bytes, SHA256 `47171646474e853f996f6b3fd9353ade8616762a770d810e7ed109f200b251cb`. No publication or version bump; native game rendering/protected deletion remains pending.

## 2026-11-17 — Selected-step arrow and route positioning
- Follow-up on “continue”: reproduced/fixed three guidance defects (lost fourth map bound, permanently cached missing metrics, selected cluster number/position hidden by summary). Local-only fixes in QuestGuidance plus focused tests/docs; preserve shared U.call and unrelated workspace work.
- Verification: guidance 40/40, full current workspace 43 suites / 1,583 checks; all 39 shipped Lua modules compile. At 320px the emulation has root/content width 320 and guide width 310; compact Next updates instruction/heading, viewport override reset, screenshot quest-guidance-compact-320.png saved. Native WoW/FPS pending.
- Current download: `dist/QuestSharing-guidance-preview-2026-11-17.zip`, 41 source-matching runtime entries / 212,490 bytes, SHA256 `d1ad05c14fdaab50167ab466622b3eee321c8d531334f7020658fbef63810729`. Base is verified completed dungeon-hover preview, overlaying only QuestGuidance; unlisted/in-progress CookingReference.lua is excluded. Other preview files unchanged; no release/version bump.
- User requests screenshot-like waypoint arrow and map connections. Implement original native HUD above guide, per-step action/destination, true direct yards/facing; no gate/portal instructions inferred without routing data. Stop arrival never completes/advances a quest.
- QuestGuidance owns plain overlay frames/lines only, no map pin provider or host-map writes; grouped colocated numbers cycle on global mouse release, avoiding map button scripts scanned by secure gamepad UI. Hide map overlay in combat. Native waypoint remains explicit; optional SPF draws terrain-aware guidance.
- Preview package: 39 source-matching entries / 199,913 bytes, SHA256 `e74b50907fbbbc98e09c326357e03375882e238594841cf55cca77c26de5dbab`; TOC stays 0.4.18/unpublished, no third-party art/data bundled.
- Validation: 30 guidance checks across both API styles, full 41 suites / 1,491 checks; browser next/position selection updates direction/caption/distance; screenshot saved. Native texture orientation, game rendering and FPS unverified. Regression methodology: context/BUGS/2026-11-17-guidance-map-click-event-argument.md.
- Scope: new QuestGuidance + TOC and planner lifecycle handoff, tests/harness API support, reference preview/docs. No new DB or timer scans; cache target world point and view geometry; arrow updates only while active. World coordinates north/west as verified in upstream SPF UI/Route.lua; guard missing world size/facing and unavailable projection.

## 2026-11-17 — Lightweight optional database tools
- User reports login/normal-play lag on v0.4.17; explicitly requests optimization of current preview too. Instrument actual addon read counts before changes: 1,000 quests -> 1,000 quest starter reads/2,000 NPC reads on login; same-zone events repeat enumeration; hidden map refresh builds vendor catalogue.
- No DB discovery on saved-toggle login or blank/closed map. User opens guide or types search to request work; close/disable/combat pauses heavy work. Keep completed small indexes, hydrate NPC locations only when matching search, debounce typing and cache query/map projection.
- Shared DataWork queue yields between records, aims for 2ms combined slices (one native read may exceed this), max 2,000 resumptions with profiler or 80 without profiler, no idle/combat polling. Use bounded session caches rather than repeatedly rebuilding the world catalogue.
- Planner discovers current-zone quest IDs on first explicit open, then reuses those IDs for quest/level updates and same-zone movement. Eligibility/progress remain fresh; explicit Refresh can rediscover data. Cache source records within discovery to avoid repeated giver-spawn reads.
- Scope: DataWork.lua + TOC, QuestPlanner/VendorMap/Questie, one Core master-disable lifecycle hook, tests/docs. Reward/dungeon browsers are already explicit-open-only; their scan implementations stay unchanged. Preserve user-authorized UI/search changes. Questie itself is an independent addon; do not modify its data or globally flush its cache. Native FPS must be checked in game.
- Reuse scalar role metadata until disabled; role-first search avoids the item catalogue. Broad seller searches read vendor links to preserve linked-but-untitled sellers even with partial flag coverage. Current-query locations are dropped on query change/clear; provider-owned caches remain outside our ownership.
- Cancellation tests exposed a worker replacing itself: completion must compare job identity before deleting its owner entry, or the replacement is lost. Map rendering checks displayed map after yields to avoid old-zone pins. Master disable cancels/closes the guide without reopening on enable.
- Validation: 17/17 performance checks; full 40 suites / 1,461 checks; syntax/diff checks. Rebuilt unpublished preview has 38 source-matching files / 194,742 bytes, SHA256 `3a5d2fe72e3b3b5adb6c919a1138b234db348babbfc7ff9dc30df6c5c20e3fa4`. Native FPS pending.
- Verified provider cost model: https://github.com/Questie/QuestieDB/blob/master/docs/read-performance.md ; broad reads warm scalar/decoded caches, so avoid reads rather than merely hiding UI.

## 2026-11-17 — Reference-led compact guide and interactive emulation
- User asks to emulate the UI so it can be seen, then supplies two Zygor reference screenshots and says this is how it should look. Authorized continuation includes native QuestPlanner presentation and an interactive visual preview.
- Preserve Quest Sharing identity; use compact opaque dark/gold guide chrome, active step emphasis, muted upcoming steps, previous/next, collapse/expand and session lock controls. Keep actual zone/dependency fixes; use harness-generated Westfall sample steps, explicitly not live character data.
- Preview uses visualize skill's contained mockup contract and thread visualization directory; no external requests or Zygor asset reuse. Verify interactions in browser and native behavior with Lua harness. Full live WoW rendering remains unavailable.
- Implemented one current + up to five upcoming steps, navigation that reviews/waypoints without marking quests complete, session-only lock and mini mode. Existing native waypoint/SPF handles guidance; no separate compass engine introduced.
- Browser inspected actual output-driven emulation, including mini and close/reopen. Bundled render.py could not find visualize.css, so use self-contained iframe wrapper for local inspection; output fragment remains compatible with inline rendering. A crop-only screenshot preserves original pixels for proof of the visible browser result.
- Package preview separately as `QuestSharing-preview-2026-11-17.zip`; do not overwrite/publish an immutable GitHub release or bump TOC solely for this preview. Byte-match all 37 entries to tested current source. Local preview includes prior authorized vendor fixes too.

## 2026-11-17 — Planner stays in zone and gives actionable steps
- User in Westfall reports worldwide quests and wants instructions: go to a town, take named quests, then complete grouped quests at a work site.
- Reproduced with Westfall/foreign Questie rows and native-style zero rectangles: global quest names appear at (0,0). `project` accepted any map rectangle; active quests entered without local-action eligibility. Do not trust rectangle existence as map membership.
- Plan: require same map or verified descendant ancestry plus finite normalized non-degenerate transforms; filter new quests with remote required work/turn-in, retain only local work/ready hand-ins for active quests; suppress premature turn-ins/future chains when required work cannot finish here.
- Present numbered Go-to steps, use native known place names or giver/objective fallback, stable quest numbers and every task grouped under its quest. Keep waypoint/SPF behavior and dependency-aware ordering; verify same-giver follow-ups and zone/progress transitions.
- Scope: QuestPlanner.lua, focused planner tests, README/changelog and continuity. No vendor runtime changes; native provider/UI unknown and installed user version remains v0.4.17. Existing authorization covers implementation; no publication requested.
- Bias/trap checks: deliberately accept both zero and plausible unrelated rectangles in fixtures; check source-map ancestry independently; distinguish a local starter from a locally completable quest; exercise async zone changes and incomplete off-zone objectives.

## 2026-11-17 — Flexible role search authorized
- After confirming `skinner trainer` was not recognized, user explicitly requests elasticity. Add English worker/profession and trainer/instructor aliases, plural/word-order/punctuation tolerance, and one insertion/deletion/replacement/adjacent swap across a role phrase.
- Bound typo matching to ASCII tokens of at least five characters; no approximate short/localized tokens. Cache canonical title words in NPC index; reverse alias forms support small typos in worker names without broad edit-distance scans.
- Literal/alias matches and item matches on displayed map take priority over spelling-fallback pins. Suggestions use same role matching with lower ranking for spelling fallbacks. Exact selected items retain literal exact-name behavior; no invented NPCs/coordinates or widened map scope.
- Scope: VendorMap.lua, existing test_vendor_map.py and docs. Existing data discovery/UI work preserved; no package/release requested.

## 2026-11-17 — Readable suggestions above the map
- User reports transparent, hard-to-read autocomplete text and requests a background. Instrumented real popup creation: alpha 0.98, no explicit strata/level, small text/268px rows. Native compositing not available; background occlusion by map artwork is a plausible cause, not visually confirmed.
- Local visual fix only: fully opaque dark panel with border, TOOLTIP strata and map-level+40 (same existing pattern as equipment dropdowns), mouse handling, clamping, 22px rows and larger explicit white text. No shared Style changes or matching changes.
- User also confirms installed version is **0.4.17**, example map **Stormwind capital**; trainer search should be general across classes. Existing local NPC-title fix is not installed/published. Exact live Questie records and missing suggestions vs pins remain unverified.

## 2026-11-17 — Trainer follow-up: compare release before patching again
- User reports Druid Trainer visible but Paladin Trainer missing. Exact live map, whether suggestions/pins are missing, and installed version remain pending.
- Run identical two-trainer fixture against `git show v0.4.18:QuestSharing/VendorMap.lua` and current module via read-only loader substitution: release only finds item-linked Druid; local finds both classes. This reproduces the reported pattern without claiming the installed data/version is verified.
- Keep current runtime; no speculative class-specific aliases, invented coordinates, data corrections or worldwide fallback. Add trainer-specific regression coverage/documentation to the existing index fix. Do not claim shipped: vendor-search fixes remain local/unpublished.

## 2026-11-17 — Generic vendor queries mean local seller categories
- User clarifies `vendor` = all known sellers on displayed map, `general vendor` = matching general seller roles on that same map. Earlier literal-title matching did not satisfy this; existing local-scope implementation stays.
- Add seller noun parsing (`vendor(s)`, `seller(s)`, `merchant(s)`, optional `all`); remaining words narrow seller roles rather than item names. Carry seller-only intent when choosing suggestions.
- Discover untitled sellers from provider NPC vendor flags after guarded RequireContract(4); use active-flavor Enum.npcFlags.VENDOR, never a guessed numeric mask. Item links and recognizable English goods/supplies/store/vendor titles retain fallback seller coverage when flags unavailable. Other titled NPCs remain searchable by role but are excluded from generic all-vendors results without seller evidence.
- Scope: VendorMap.lua, focused workflow tests, existing bug-report addendum and user/continuity docs. Preserve voice research and release work. Coordinate scope stays in shared mappedPoint projection; no new worldwide rendering.
- Provider references verified: https://github.com/Questie/QuestieDB/blob/master/docs/api.md#active-class-keys-and-npc-flags and https://github.com/Questie/QuestieDB/blob/master/src/meta/npcMeta.lua .

## 2026-11-16 — Map-local seller search consistency
- User expects choosing General Goods to show matching NPCs on the displayed map, with understandable item-search results.
- Verified mechanism: index only visits Item.vendors; suggestions ignore map scope; suggestion kind is discarded; zero local pins automatically offer a remote waypoint.
- Plan: batch-enumerate NPC titles as well as item seller links; share coordinate eligibility for suggestions/pins; preserve selected role/item kind; name map/query/count in feedback; require explicit Elsewhere for nearest fallback. Reset remote mode on map/query changes.
- Files: VendorMap.lua, tests/test_vendor_map.py, README/changelog and continuity notes. Leave Questie adapter, item tooltip, settings and existing planner/release work alone.
- Trap checks: retain timer generation cancellation; clear stale suggestions/pins and render cache on scope/map changes; retain item-linked fallback for providers without NPC enumeration. Main risk: larger catalogue scan; keep work in 120-record batches rather than one final unbounded NPC pass.

## 2026-11-16 — Separate local quest voice-acting addon investigation
- Research only; preserve QuestSharing runtime. Windows confirmed; GPU/VRAM unknown. User explicitly prioritises high-quality expressive local acting over generic reading.
- Recommend auditioning Qwen3-TTS character design/delivery against Chatterbox before choosing a backend; Whisper is speech recognition, not synthesis.
- Compare quality-first pre-generated local packs with a conditional live Windows speech-engine route; optical companion is a more complex fallback. No live bridge compatibility or acting-quality benchmark established.
- See `quest-narration-research.md`; separate project and implementation remain proposals.

## 2026-11-16 — Optional Shortest Path Forever routing
- Keep quest selection, prerequisites, outing groups and UI in Quest Sharing; use SPF only as an optional walk-cost/guidance provider through its published API.
- Use explicit Follow with SPF / `/qs plan follow` for `Navigate`; use `EstimateWalks` (v2 minor 3+) to promote the first outing by reachable walking-yard cost. Keep current map-distance ordering and native waypoint without a supported provider.
- Do not bundle SPF code or data. Don't assert strict no-swimming or correct cave floors when Questie gives only 2D coordinates. See `quest-planner-routing-and-validation-plan.md`.
- Implemented locally; release waits for real-client checks.

## 2026-11-16 — Local quest planner first pass
- Implement the user's graph idea as two connected views: prerequisite gates (`preQuestSingle` = any, `preQuestGroup` = all) determine which quest layers can unlock; a stop graph connects shared exact sources and nearby objective points.
- Keep the planner in Quest Sharing as an opt-in Extra tools action and `/qs plan`; default `questPlanner=false`, no route data persisted and no automatic quest acceptance.
- Scan QuestieDB's enumerable quest catalogue in small `ns.after` batches. Use Questie's own readiness check where available; include active log quests and nearby quests Questie reports ready or prerequisite-blocked. Unknown eligibility remains excluded.
- Build pickups, objectives and turn-ins as explicit stops. Schedule only dependency-ready stops, then use nearest straight map distance to choose among them. Keep drop-rate percentages informational; do not pretend this first score estimates farming time.
- Do not add Shortest Path Forever or claim walkability in this pass. User-facing route says map-distance estimate; no cave/floor traversal. Follow up with in-game QA and terrain routing research before claiming a walkable route.
- Scope preserves earlier user authorization to build the planner; published as Quest Sharing v0.4.16 after the user explicitly requested push/release. README includes the release link and full behavior/limits guide.

## 2026-11-16 — Quest planner stays in the current outdoor zone
- Require a mapped outdoor `Zone` and reject city maps before requesting Questie quest IDs. Recheck each async batch, selection and waypoint action; stop in towns and rebuild after outdoor zone changes.
- Keep Questie ID enumeration batched because the current adapter has no zone-indexed ID method; filter plan candidates by starter location in the current zone.
- Fix the frozen final progress state by forward-declaring `render` before `scan` closes over it; Lua otherwise binds the later local function name as a global at the earlier reference.
- Local/unreleased; preserve the independent pending VendorMap edits. No in-game verification available.

## 2026-11-16 — Put the quest plan beside the quest tracker
- Replace the large center dialog and separate Previous/Next/Set waypoint controls with a compact scrollable panel docked beside the game's objective tracker.
- Show each stop's kind, coordinates, action summary and related quest names in a clickable row. A click revalidates zone/map and immediately sets the waypoint; Refresh rebuilds the plan and close hides only the panel.
- Keep the panel independent of Blizzard tracker internals; dock to the tracker frame when present, with a screen-corner fallback. The game tracker remains visible and unmodified.
- Local/unreleased; actual frame placement, clipping and waypoint click behavior need in-game verification.

## 2026-11-16 — Build and refresh zone plans automatically
- When the optional planner is enabled, open/build after login or outdoor zone entry. Debounce quest events; compare active quest IDs, completion state and objective counts so partial progress updates route rows without rescanning every Questie ID.
- Full catalogue scans follow zone changes, accept/remove/turn-in, and level-up changes. Preserve the selected stop if it remains; if it disappears, keep the next useful route index.
- Connect each quest's giver, work sites and turn-in; merge outings sharing a stop or prerequisite edge. Estimate a nearest-neighbour map-distance trip from the player, then normalize by square root of represented quest count; schedule an outing together while respecting stop dependencies.
- This heuristic does not account for terrain, kill time or XP value and does not promise a global optimum. Local/unreleased.

## 2026-11-15 — Optional quest dialog automation (published)
- Add independent `autoAcceptQuests=false` and `autoCompleteQuests=false` controls under Tracker; a player can enable either action without enabling the other.
- Use the game's `QUEST_DETAIL`, `QUEST_PROGRESS` and `QUEST_COMPLETE` events with the same quest APIs used by the built-in UI; never synthesize clicks on Blizzard frames.
- Only auto-advance when `IsQuestCompletable()` says the progress stage is ready. Claim automatically only when there are zero/one choice rewards and no required money payment; leave uncertain/multi-choice cases to the player.
- Require Quest Sharing's master switch and no combat. New settings use the existing missing-default migration; no dbVersion bump.
- Place both controls under Tracker > Quest offers and turn-ins, because the Extra tools tab overflowed the fixed-height settings window; Tracker has adequate space and the options concern quest behavior. Both remain off by default.
- User authorized push/release of 0.4.15 on 2026-11-15. Initial release check found optional-tab overflow; after approval, moved the rows into Tracker and reran all 1,291 checks. Published release/tag `v0.4.15` from `5a15985ac9b5fcd2fe7990ed6ced28609d6ee72c`; downloaded ZIP matches the local build byte for byte.

## 2026-11-15 — Routing implementation plan canceled
- User explicitly said to stop and scrap the active plan. No route feature is implemented or ongoing.
- Before canceling, the user had selected a Shortest Path Forever integration and clarified that route entry points should live inside QuestSharing. Do not reinterpret that as permission to bundle the engine; ask only if the user later resumes the feature and its scope is unclear.
- Removed the uncommitted built-in-engine attempt and restored runtime/build files to the v0.4.14 baseline. Keep the earlier feasibility/source-study documents as research only.

## 2026-11-15 — Save research and verify the current publication
- User requested push/release before continuing. Current addon is still v0.4.14, already published as latest stable; runtime/build/changelog have no changes from that tag.
- Commit/push all completed routing research and continuity notes to main; preserve immutable v0.4.14 rather than invent a version bump or replace its asset for documentation-only changes.
- Re-run 34 suites / 1,291 checks, rebuild and source-check the ZIP, verify remote tag and latest release, download and byte-compare the published asset. All pass; no new runtime release required.

## 2026-11-14 — Routing research recommendation (not implemented)
- User requested feasibility research only. Recommend an optional, default-off Shortest Path Forever bridge using existing quest destinations and provider-owned calculation/rendering, instead of building/bundling a new terrain system.
- No implementation, dependency, settings or release changes authorized by this research task. Existing map restrictions and retired overlays remain as implemented.
- Do not advertise strict dry-land walking or mathematically exact shortest paths: documented API optimizes a multimodal estimated journey and has no explicit walk-only request option.
- Evidence, source links, integration contracts and remaining validation: `context/walkable-routing-research.md`.

## 2026-11-13 — Native level metadata needs a standalone fallback
- User reports `???` in every zone. Reproduced with GetMapLevels returning 0,0 on modern/classic paths; API also explicitly permits no return. Previous native-only implementation and happy-path mocks did not establish real coverage.
- Keep native validated bounds preferred and cached. Add 39 Classic outdoor brackets checked against LibTourist Classic Era revision 246 (`d2380757a8fe2b1cb2d341817e36e1cd0bccee3a`, MIT; author repo https://repos.curseforge.com/wow/libtourist-classic-era). These are general Zone guide ranges; no runtime library dependency or copied library implementation.
- Forever sources: Blizzard news 24302071 confirms Zephras 1–12; news 24315820 describes Riverglades mid-30s to mid-40s, represented as a labelled 35–45 Zone guide. Exact native metadata still wins.
- QuestieDB commit `4dde6c43201b15c0b0f370cf85e7259e1922322a`, `src/corrections/Forever/generated/foreverBaseQuest.lua`: 36 zone-tagged Mount Hyjal quests at 56–60, 19 Shen'dralas quests at 38–43. These are computed spans of those known records, explicitly labelled Known quests, not claimed complete/recommended zone bounds. Real UI map IDs verified from the same provider's Forever zone mappings: Hyjal2482, Zephras2521, Riverglades2548, Shen'dralas2652; no AreaTable/UI-map-ID confusion.
- Label six cities and Moonglade as City/Sanctuary. Unknown future maps remain unknown; never guess from neighboring maps. Fallbacks are not cached, allowing native data to arrive later. Only ZoneLevels runtime changes; default off, protected map behavior and all other tools retained. Release 0.4.14 under ongoing publication authorization.

## 2026-11-13 — One explorer row per equipment name
- Group only after existing quality/gear/stat/level/search/source/quest-eligibility filters. Preserve raw indices and every matching source; avoid losing other bosses when collapsing the presentation.
- Shared EquipmentUI.groupItems normalizes case, color codes and outer whitespace; stable name key preserves selection when sources or item versions arrive. Highest native item level then lowest item ID chooses a deterministic comparison version; all matching item IDs/levels remain visible in details.
- Loot groups suppliers by dungeon/mob name/provider, combines difficulty labels and lists every supplier inline. Quest groups routes by quest ID, preserving locations/prerequisites/extra requirements. The map action explicitly refers to the first listed quest when multiple routes exist.
- No new windows/settings/migrations; Rare+ and dungeon scope unchanged. Publish 0.4.13 under ongoing publication authorization.

## 2026-11-13 — Extra tools must remain optional
- User clarified "always as optional thing": Extra tools additions default off unless the user explicitly asks otherwise; record this as the standing preference for future features.
- Correct zoneLevels=true from 0.4.11 to false. Changing defaults alone would leave the previously auto-enabled SavedVariables value active, so add a once-only zoneLevelsOptInMigrated marker that resets the old state to off before defaults fill. Subsequent explicit choices persist; reset returns to off without rerunning migration.
- Preserve the existing Extra tools toggle and renderer. No broader core-feature default changes and no dbVersion increment. Publish 0.4.12 under ongoing authorization.

## 2026-11-13 — Questing ranges on world-map zones
- User requests a questing level range for each world-map zone. Enable zoneLevels by default, with an Extra tools toggle; no SavedVariables version bump. Continent views show outdoor-zone range badges, selected/hovered zones show a compact panel; world/cosmic maps prompt choosing a continent/zone.
- Use native C_Map.GetMapLevels player bounds, GetMapChildrenInfo(Zone,true), GetMapRectOnMap and GetMapInfoAtPosition. This covers client-supported Forever zones without bundling speculative data or requiring Questie. Unknown data is explicitly unknown; ranges are general map recommendations, not class/faction quest eligibility.
- Render own mouse-disabled frames only; never open/navigate/refresh Blizzard's protected map or acquire its pins. Retired quest objective/turn-in/minimap overlays stay removed. Existing fishing layer remains separate.
- Reuse per-canvas label pools, compensate zoom, clear stale labels on map/canvas changes, cache positive ranges and retry unknown data. Poll only shown maps at 0.25s; idle at 1s. Release 0.4.11 under ongoing publication authorization.

## 2026-11-13 — Opt-in highest learned action-bar spell ranks
- User requests auto-update to maximum spell rank as an Extra tools option; default off, no training/purchase and no macro editing. Check-now action reports changes or deferral/unsupported status without additional windows.
- Enumerate learned active player spell-book entries using modern C_SpellBook or legacy tabs; match exact localized name and numeric rank, not spell ID order or book position. Skip passive/future/off-spec/unranked entries and ambiguous highest ranks; read existing action metadata when old ranks are collapsed out of the book.
- Check all normal native slots (including duplicate/hidden/form pages); preserve macros/items/pet/empty actions and avoid temporary/vehicle bars. Auto events are debounced; internal pickup/place events do not recurse.
- Do not derive slot limits from visible pages: scan at least 180, retaining larger native limits and ignoring unsupported reads. Revalidate the target after synchronous pickup events so another addon's changed slot wins.
- Defer during combat, temporary bars or occupied cursor. An unreadable cursor is not empty; do not touch bars. Validate pickup payload and slot readback, clear only the addon's swapped cursor, and retain cursor on unexpected mutation for recovery. Client refusal pauses this feature until reload; use existing diagnostics.
- Saved setting `autoSpellRanks=false` uses missing-default migration; dbVersion remains 3. Existing ongoing publication authorization applies to 0.4.10.

## 2026-11-13 — Current dungeon focus and Extra tools
- User requests current-instance focus on opening Instance drops and renaming Optional to Extra tools. Existing publication authorization continues for 0.4.9.
- Use native GetInstanceInfo eighth return for instanceID, plus exact localized names/subzones for legacy/Questie fallback and provider SubAreaIDs to distinguish wings. Compatible Dire Maul tables omit InstanceID but document 429 alongside area 2557.
- Resolve focus once after catalogue completion or immediately when ready; reveal navigation page and clear stale text/source without resetting shared gear filters. Preserve explicit slash search. Manual choices cancel pending focus so background refresh never overrides browsing.
- Yield to dirty search fields before focusing; a pending 180ms search must remain authoritative when indexing finishes first. Reproduced timing variant recorded in the debounce bug report.
- Unknown/ambiguous/raid/outdoor context preserves browsing. Keep tab id `optional`, change displayed label and rebalance widths to fit existing settings geometry; no SavedVariables migration.

## 2026-11-13 — Shared equipment stat filters
- User requested stat filters for both tools. Add three visible AND conditions with searchable bonus choice and live inclusive minimum; default blank threshold 1, Any stat clears one, Clear filters clears all.
- Keep controls inside the shared explorer; enlarge height from 760 to 828 and preserve body dimensions with existing automatic screen scaling. No additional top-level windows.
- Read native stat token/number tables lazily by item link; modern API preferred, legacy fallback, successful results cached and invalidated before item-event refresh. Missing data never qualifies; no localized tooltip parsing or guessed proc/set effects.
- Show clear unavailable-API feedback and explain rating units. Keep fixed Rare+, existing quest eligibility and Classic/Forever dungeon scope. No provider/schema persistence changes.
- Release as 0.4.8 under ongoing publication authorization.

## 2026-11-13 — Equipment usability
- User says both equipment tools are clunky/hard to navigate. Verified sequential cycling controls, Enter-only searches, button-only pagination and selection clearing on every refresh.
- Replace choices with one reusable searchable child popup; direct options beat forcing repeated clicks through class/type/source lists. Use plain frames, preserving client compatibility and avoiding Blizzard dropdown templates.
- Debounce search and numeric input by 180ms; keep Enter/Apply and explicit Clear. Hidden-page edits resume on return; canceled/reset text must not apply stale callbacks.
- Keep bounded pages internally but add mouse-wheel browsing and focused-search Up/Down navigation. Do not intercept game-wide keys. Preserve stable selection and show first-result details automatically.
- Offer sorting and My level as direct shortcuts. Clear filters includes active search/dungeon/source and broadens quest levels while preserving character context and Rare+.
- Improve name contrast while retaining rarity hues/strips, show difficulty on duplicate sources, and label the map action accurately because opening Blizzard's map from addon code remains prohibited.
- Release as 0.4.7 under ongoing publication authorization; no provider/dataset, SavedVariables, quality-floor or dungeon-scope changes.

## 2026-11-13 — Blue quality and above
- User requested avoidance of green quality or lower; apply a fixed native quality >=3 minimum to both equipment tabs and source choices.
- Put the check in the common EquipmentUI.matches predicate; Reset filters cannot bypass it. Do not add a toggle that restores unwanted qualities.
- Require confirmed native quality rather than guessing unknown items from names, color strings or provider fallback data. Existing item-cache events refresh loaded gear.
- Update unrelated fixtures to Rare quality so existing functional coverage remains meaningful; new mixed-quality cases cover the actual threshold, provider paths, reset and asynchronous data.
- Release as 0.4.6 under the ongoing publication authorization.

## 2026-11-13 — One equipment explorer and dungeon scope
- User requested improved graphics, one window for quest/instance equipment, item type and level filters, and exclusion of random encounters and raids.
- User explicitly answered the scope question: include Forever dungeons too. Use AtlasLoot's public localized Dungeons category, with verified known IDs for older catalogues; Questie fallback requires known dungeon areas. Never infer a dungeon solely from a map-type enum (raids share it).
- Reuse one top-level host with lazy quest/dungeon child pages and inline detail panels; native comparison tooltips remain. Tab changes and close cancel unfinished scans/names.
- Shared category/subtype/slot filters and inclusive bounds; offer Required level and Item level explicitly to remove ambiguity. Invalid ranges preserve the last valid range. Native numeric metadata avoids locale-dependent item-type text.
- Keep quest class/faction/character level and quest eligibility distinct from shared equipment filters. No SavedVariables migration or provider dataset bundling.
- Accept Dire Maul's known area when its compatible provider omits InstanceID. Exclude the unverified Hall of Thanes area placeholder from the partial Questie fallback; its primary AtlasLoot dungeon is included by instance/category.
- Release as 0.4.5 under the ongoing publication authorization.

## 2026-11-13 — Invitation menu placement
- User requested Seek fellow adventurers immediately after Tell the party in the quest right-click menu.
- Move its existing action to row 2, before Offer it to the party; keep selected-quest invitation behavior.
- Update existing menu-order assertion and documentation; release as 0.4.4 under the ongoing push/release authorization.

## 2026-11-13 — Restrict instance loot to equipment
- User clarified that instance results should contain equipment drops such as weapons and armor; previous all-item scope included unwanted materials.
- Reuse `Rewards.itemInfo().slot` (recognized weapon/wearable slots) in loot search and encounter choices for both providers. Includes jewelry, trinkets, shields and offhands; excludes bags/quivers and non-equipment.
- Hide unclassified items until the game returns full equipment details; existing item-cache events refresh results. Never guess gear from names or show unknown candidates temporarily.
- Keep raw provider indexing and throttled item requests intact; avoid separate provider filters or a broad scan refactor.
- Package correction as 0.4.3; preserve the immutable published v0.4.2 artifact.

## 2026-11-13 — Publish 0.4.2
- User explicitly requested push and release, superseding earlier local-only packaging decisions.
- Publish current main as v0.4.2 and attach the validated install ZIP; include all changes since the last published v0.3.9.
- Use git/gh for tag, release and binary upload; the connected GitHub tools do not provide release creation or asset upload.
- Verify the published tag commit and downloaded asset checksum; keep game-client and provider coverage limits in the release notes.

## 2026-11-13 — Instance drop search
- User requested GUI search of instance drops and their suppliers.
- Add a dedicated instance browser with instance list, item/ID/boss text search, encounter filter, source details and native item comparisons; link from Optional settings and reward browser, plus `/qs loot`.
- Use compatible installed AtlasLoot DungeonsAndRaids encounter data at runtime rather than bundling a possibly stale or mismatched Forever loot dataset.
- Use QuestieDB only as a visibly partial fallback. Its item/NPC/object links do not establish complete dungeon loot coverage; include only known instance sources.
- Resolve AtlasLoot difficulty aliases and linked tables through its public GetItemTable method. Retain group names such as Trash rather than inventing a specific NPC; omit drop-rate claims.
- Index only on demand, in batches, and throttle native item-name requests. Load optional AtlasLoot dungeon modules only on request and out of combat; retry after combat when necessary.
- Reuse Rewards.itemInfo for native item metadata; no broad reward-browser refactor or SavedVariables migration.
- Package locally as 0.4.2; no commit/push/release requested.

## 2026-11-13 — Remove quest map symbols
- User requested removal of quest symbols from the minimap and world map while invitation work was being finalized.
- Remove the complete light quest overlay renderer and its TOC/settings/diagnostic hooks, rather than only changing a default that existing saves could override.
- Clear the old `questMap` saved setting on load. Retain a legacy command response explaining removal; no re-enable path.
- Keep shared Questie how-to/quest-location data for chat and reward routes. Scope is the addon's objective/turn-in overlay, not external addons' or the game's own markers.
- Include removal together with the already-authorized role-play invitations in local version 0.4.1.

## 2026-11-13 — Role-play quest recruitment
- Add a dedicated editable invitation composer reachable from quest right-click, Optional settings and `/qs adventure`; leave saved quick-chat messages unchanged.
- Three generated role-play wordings include the actual quest link and current zone only when the quest belongs to that area.
- Support any existing chat via current-channel insertion, plus explicit standard chats, whispers and joined channels by number/name.
- Preparing an invitation always fills chat for Enter, regardless of global send mode; this respects the client's existing protected-chat constraints and gives the player control over destination and edited text.
- Preserve existing drafts; do not move their contents to another channel. Revalidate selected quests on prepare so completed/abandoned quests cannot be recruited.
- Local version 0.4.1; rebuild install ZIP without publishing remotely.

## 2026-11-13 — Optional fishing and reward tools
- User explicitly chose working addon features in a new Optional tab, rather than wishlist entries.
- Both default off. `/qs rewards` opens/enables the browser; `/qs fishing` edits notes and its layer is enabled separately.
- Fishing uses independent overlays, persistent per-water notes and optional runtime AnglerAtlas zone summaries. No third-party fishing dataset is bundled.
- Coverage limit: no verified automatic catalogue for every lake/river; individual water fish/skills are user-entered. AnglerAtlas Forever contains explicitly provisional estimates and placeholder new-zone IDs; keep summaries labelled and do not promote them into water facts.
- Use the provider's real item `questRewards` reverse links. Do not assume quest records contain item reward fields.
- Read item IDs only on demand, in batches of 100, with generation cancellation and debounced item-cache events. Do not mutate the provider's shared ID list.
- Class equipment families use Classic rules; item tooltips and comparison remain authoritative for build suitability and item-specific restrictions. Item level sorts results but does not certify upgrades.
- Keep map actions read-only: existing `tests/test_box.py` forbids opening Blizzard's map because its protected pin creation can be tainted. New buttons print map directions. Alt-click hooks read coordinates and create only our own editor/overlays.
- Water notes survive settings reset, preventing accidental deletion of manually gathered data; explicit delete removes a selected water.
- Bump local addon version to 0.4.0 for the new install ZIP; no remote publication authorized/requested.

## 2026-11-12 — Persistent working instructions
- Use `/Users/francesco/.codex/AGENTS.md` for Francesco's rules across projects; embed the rules so the Desktop copies are not a runtime dependency.
- Continuity applies to every work block; other protocols apply when relevant. Existing authorization counts as approval.
- Preserve original supplied text in `/Users/francesco/Desktop/MyRules/Originals/`; split Cursor rules remain in `MyRules/.cursor/rules/`.

## 2026-11-11 — Publish 0.3.9
- Pushing `main` alone did not publish a GitHub Release. Explicitly created release `v0.3.9` and attached the ZIP built by `python3 build_release.py`.
- Match existing release naming: `Quest Sharing 0.3.9`, asset `QuestSharing-0.3.9.zip`.
# 2026-11-16 — Item-source hints and vendor map search
- Use QuestieDB's item `vendors` IDs and NPC `subName`/`spawns` fields as the single seller source. Show the NPC category/title only, never its specific name in item hints.
- Search builds a lazy timer-batched index from the provider's enumerable item IDs. Results require an explicit item vendor link; do not infer vendors from recipes, drops, or gathering sources.
- QuestieDB has no mining-profession or recipe-crafting relationship in the item/object metadata. Label Mining only for linked object names matching known localized ore-node terms; present this as a partial hint, not complete source coverage.
- World map renders only addon-owned pins on Blizzard's current map. Clicking a seller pin sets a user waypoint. When none match the shown map, compare normalized coordinates only on the player's continent, label that fallback as geographically closest by map position, and offer a waypoint; do not claim a walkable route or compare separate continents.
- Add independent false-by-default `itemSources` and `vendorSearch` switches under Extra tools. Because this adds rows near the tab's vertical limit, settings rows live in a scroll frame instead of silently overflowing.
- Feature remains local/unreleased until the user requests publication; preserve the existing local settings-copy edits.

## 2026-11-16 — Partial vendor-title search and autocomplete
- Match each entered word as a substring in item names and vendor titles, so short input such as `tail` finds `Senior Master Tailor` too.
- Show live suggestions ordered as matching role words, full vendor titles, then item names. A click or Tab selects/completes and searches the suggestion; Enter still searches the text as typed.

## 2026-11-16 — Seller map and list views
- Show every matching Questie spawn on the current map; remove the earlier 80-pin cap. The scrollable Sellers view lists category/title, zone and coordinates, never NPC names, consistent with the original request.
- Selecting an item suggestion opens Sellers; exact buyable item names entered directly also open Sellers. The Map view keeps every pin visible. Item/reagent sellers are only returned from explicit Questie `Item.vendors` links.
- Ensure `OptionalUI.lua` loads before `ItemSources.lua` and `VendorMap.lua`; both capture the shared helper during initialization.

## 2026-11-16 — Settings redesigned around visible game actions
- User says all settings are chaotic and asks for explicit explanations such as adding ! over quest mobs; authorized implementation covers the whole settings UI.
- Replace cramped horizontal tabs with ten sidebar categories; separate Quest markers, Quest list and Accept & turn in, move location/source controls to Map & sellers. Keep old category IDs and all saved setting keys/defaults.
- Each switch explains its visible result and dependencies. Enemy ! and quest-log shared stars are distinguished; nameplate helper explains restoration when disabled.
- Show all named choices as direct buttons, On/Off alongside checkboxes, and real minus/plus buttons. Reuse existing handlers and feature code.
- Use measured wrapped text in a clipped scroll body; editor scrolls with its page. Preserve scroll during refresh, reset on category changes, expose scroll buttons/hint, scale window for small screens. Existing Extra tools remain opt-in.
- No publication requested; preserve unrelated local vendor/item-source work. Native in-game rendering remains unavailable.
- Verified all 34 suites / 1,302 checks after adapting old fixed-height assertions to the scroll viewport. Baseline ItemSources test errors were isolated with HEAD Settings.lua and resolved by adding the missing GameTooltip HookScript mock, without editing unrelated runtime modules.

## 2026-11-16 — Direct quest-group question from the right-click menu
- User reports the World-chat recruitment path opens an unwanted menu/editor and wants a simple question asking who needs the quest and wants to group.
- Reproduced on modern/classic harness: Menu.lua row 2 calls Adventure.open, creates the composer and leaves game chat empty. A failing workflow test confirms the extra window before edits.
- Replace row 2 with **Ask in chat to do this quest**; `Adventure.ask` reuses `prepare` with a short linked question and the current chat. No extra editor; player presses Enter to send. Destination preference was asked asynchronously; absent a reply, current chat was stated as the assumption so selecting World first uses World.
- Keep optional role-play editor under Extra tools and `/qs adventure`; no saved settings/default changes. Reuse draft preservation, duplicate detection, byte limits and unfinished-quest checks rather than duplicate chat-routing logic.
- Runtime scope: Adventure.lua, Menu.lua and Panel.lua tooltip; tests and user/continuity docs updated. No release requested.
- Verification: Adventure 44/44, menu 60/60; full 34-file run plus updated tooltip-suite rerun passes all 1,314 checks. Bug report: `context/BUGS/2026-11-16-quest-recruitment-extra-editor.md`; native client unavailable.


## 2026-11-16 — One map search view and immediate clear
- User finds Map and Sellers views confusing and wants one map-only search, a bottom-right search box with an icon inside, a Clear button, and pins removed when the query becomes empty.
- Keep item/vendor matching, suggestions, all matching map pins, Ctrl-right-click current-map search, and nearest mapped waypoint. Remove tab switching and the separate location list.
- Root cause: the empty-query early return in `VendorMap.draw()` changed the status but returned before hiding old pooled pins. Clear and manual deletion both need to enter the same empty-query path.
# 2026-11-16 — Quest planner route safety review
- Objective-stop merging is constrained by map-coordinate distance even when Questie source IDs match; a source can have separate camps around a zone.
- `/qs plan next` pins only when the requested stop selection succeeds, avoiding stale/empty-route waypoint attempts.
- Review verification uses each `tests/test_*.py` script directly, matching the repository's documented runner; plain pytest expects fixtures these files do not define.

## 2026-11-16 — Quest planner arrival and readable route panel
- Keep quest difficulty green/yellow relative to the player's level, using the game's quest difficulty color table; exclude missing or unrecognized colors rather than guessing. When all mapped local quests are gray, say the zone is too low level.
- Show available quest pickups line by line within giver stops even with an empty active quest log. Left-click sets a waypoint; right-click marks the location too. The player opens the World Map normally; Quest Sharing never opens or navigates it.
- Keep default tracker docking until the user drags the panel; then preserve the moved position for the session. Measure wrapped title/detail heights and derive each row offset and scroll-child height from the content.
- The first local quest list was hidden by a data-shape mismatch: `plannerStarters()` returns source records with `spawns`, not flat points. Use `nearestSource()` for these records.
- Published as Quest Sharing v0.4.18; see README and changelog. Native-client behavior remains to be checked.

## 2026-11-17 — Extra tools and Browser DB
- User requests clearer Extra tools and a separate Browser DB tab for all database searches. Keep five everyday utility cards in optional; move equipment/dungeon/profession lookups and item/vendor/source controls to browser. Map contains only zone levels/party positions.
- Reuse existing row kinds, saved setting keys and feature handlers. Bool cards merge their launch action into one card; explicit checkbox changes persistence, separate primary button opens the feature. No catalogue probing during settings rendering.
- Short titles, purpose, dependency note, measured wrapped text and spacing replace duplicate switch/action rows; read-only card bodies prevent accidental toggles.
- Verification: Settings59/59, layout42/42; full44 suites /1,677 checks, all43 Lua5.1 compilations and whitespace checks pass. Browser preview checks Extra tools, Browser DB top/bottom and final source controls; native font/texture/rendering remains an in-game check.

## 2026-11-17 — Predictive zone scheduling
- Latest user instruction authorizes implementation of the pasted design. Implement locally through the existing guide and scheduler.
- Use bounded constructive schedule search with a legal nearest-ready incumbent, waiting-aware order, shared-camp preparation, terminal alternatives and prior order. A complete graph replaces the four-layer cap.
- Keep actions per quest through simulation and combine only consecutive instructions for display. Enforce log slots and acceptance/expiry/exclusion gates.
- Default all acceptance levels and all compatible non-repeatable local quests. Explicit session-only alternatives select quest XP/hour, selected IDs or expected-time budget; optional green/yellow filter is user-visible.
- Use exact single-loot-stream plus kill expectation and conservative separate loot estimates. Unknown work uses 60 seconds, kills 10 seconds and interactions 3 seconds, all labelled estimates. Missing dimensions use an explicit illustrative scale.
- Defer unsupported future-level, inventory-consumption/capacity, flight/transport, reputation and custom event models with report reasons. They require verified live facts. Native game unavailable.
- Added implementation design and executed eight-quest simulation in predictive-quest-optimizer.md. No publication/version bump requested.

## 2026-11-17 — Planner resource-state implementation
- The current coding-plan work adds a carried-bag snapshot on explicit guide planning only. Only relevant item IDs are counted; bank data is excluded. Missing bag APIs or slot counts remain unknown.
- The optimizer simulates known quest-item gains, explicit consumed-item costs and a single observed XP threshold. It never infers consumed items from every loot objective. More levels and item costs without provider evidence remain unresolved.
- For complete-zone scoring, equal hand-in coverage is ordered by estimated elapsed time. The previous action-count tie break could prefer longer work for no quest-completion gain.

## 2026-11-17 — Conditional prerequisite and character gates
- Keep every QuestieDB prerequisite choice on the candidate while using one parent only to discover graph reachability; check the full AND/OR gates in the simulator at pickup. Selected routes may include either parent and stop at their selected hand-in.
- Read reputation as absolute faction points from native APIs for only local referenced IDs. Apply signed QuestieDB `reputationReward` at simulated hand-in. Missing values stay unknown; an unverified future pickup is excluded. QuestieDB `requiredMaxRep` is an exclusive upper threshold.
- Read profession rank by skill-line ID only where the client exposes that ID directly. No quest-driven skill gain is invented. Static rank requirements and OR rank alternatives can gate pickups; unsupported clients retain unknown eligibility.

## 2026-11-17 — Small-plan bounded search and loot confidence
- Keep the existing seeded route as a legal incumbent. For at most 40 atomic actions, branch within the shared 36,000-check budget and retain a 20-state beam; never replace the incumbent with a worse or infeasible branch. Report exhausted search explicitly. Larger zones keep seeded scheduling until a measured safe large-zone search exists.
- A separate item drop stream at an already-active shared camp has unknown joint probability. Preserve the conservative additive work estimate and set uncertainty with an explicit reason. Do not invent independence or correlated drops from separate marginal rates.
- The SPF first-stop test now gives both candidate quests a turn-in. A nearest-leg-only expectation for an unfinishable quest contradicts complete-zone scoring.

## 2026-11-17 — Publish the full tested preview as 0.4.20
- User explicitly requested push and release after receiving the predictive preview. That ZIP contains the entire current addon, including the other locally completed journal, diagnostics, profession, settings, dungeon and map changes. Publish this source-matched full build together as v0.4.20 rather than release a planner-only archive that would differ from what was tested.
- Keep native WoW and remaining optimizer model limits explicit in the release notes. Do not call the eight-batch algorithm fully complete.
- Publication verified: `cb45f17fae12ebf175c56322ec896727ae6ae3c8` is origin/main and annotated `v0.4.20` target; GitHub latest stable release is v0.4.20; downloaded 46-file asset matches both the local tested ZIP and every tagged source byte.

## 2026-11-17 — Closing QuestOptimizer gaps (site choice, shared camps, local search)
- **Site choice inside the optimizer**: planner sends the nearest real camp as default plus up to 3 more as `stop.alternatives`; optimizer `place()` picks per visit by travel + incremental work from the simulated position. Greedy per visit (not a joint site search) — cheap, and local search then reorders around it. Rejected: picking camps in the planner from the player (the old way; ignores route and sharing).
- **Per-creature camp clustering**: camps grouped per source NPC instead of mixing all of a target's sources, so every quest on the same creature gets identical camp points and the exact `campKey(point,npc)` sharing matches. Trade-off: a loot target dropping from two mixed mobs now gets one camp per mob.
- **Local search = or-opt (runs of 1-3) + 2-opt (segments ≤ window 10)**, first-improvement, cyclic scan, full re-simulation of each candidate from a checkpoint every 8 actions; exact pruning in `all` mode (same quests handed in, so slower total = reject). Budget counts simulated actions (default 250k ≈ 0.7 s CPU in lupa Lua 5.1).
- **Background refinement**: DataWork gives 2 ms per 0.1 s, so 0.7 s CPU ≈ 35 s wall. First route uses `solve(0)` and shows at once; Work job `quest-improve` re-solves with local search and swaps the route keeping selection. The Path walking-cost job (`quest-costs`) cancels and replaces `quest-improve`.
- **Not done**: pairwise walking costs (gap 5). SPF `EstimateWalks` is one origin → many targets, async; all pairs would mean n requests per replan. Later legs stay straight-line.
- Beam search threshold (≤40 actions) left as is: local search covers large zones; raising it only burns the 36k check budget.

## 2026-11-17 — Client-accurate SetFont in test harness
- `tests/harness.py` `CreateFrame` records the widget kind; `SetFont` errors for EditBox without flags (client Nilable=false), FontString flags optional. Chosen over a lenient mock so `if x.SetFont` guards cannot hide native-only failures. Addon code always passes `""` flags.

## 2026-11-17 — Classic WoW menu look for all windows
- User choice: Stone dialog (Esc menu / Interface Options) look, fully opaque on every window including on-screen HUDs. Rejected: parchment quest-log look, stone+parchment mix, keeping HUDs translucent.
- Opacity guaranteed by a solid base fill under the stone tile (texture alpha unknown); backdrop draws only the edge (no bgFile).
- Button art uses plain textures + OnMouseDown/Up instead of SetNormal/PushedTexture so callers hiding `b.bg` (planner text-only header buttons) stay hidden; avoided editing QuestPlanner.lua during concurrent work.
- Journal reading panes keep parchment (`E.surface(frame,true)`); dim selection/hover washes (<=0.25 alpha) over opaque bases are kept.

## D1 — 2026-11-17 — Camp hysteresis: 25 % and 20 s, and only walking costs may switch (fix-all run A2)
- **Partly superseded by D5/D7 (decouple run r-20261117-234605-6ba9):** the 25 % / 20 s margin stays; `lockSites`, "only walking costs may switch", the walk-costed-only `siteMemory` rule and "without SPF preferredSites is nil (switch at 0.56)" are gone.
- Choice: the optimizer gets `options.preferredSites[stop.key] = O.siteKey(point)`. `place()` keeps the held site unless another is cheaper by **both** `SWITCH_SHARE=0.25` of the held visit cost **and** `SWITCH_SECONDS=20` (`QuestOptimizer.lua` ~:236).
- With SPF available, `options.lockSites` keeps every reachable remembered site in the straight-line `solve(0)`. Only the walking-costed solve may switch, and then only past the margin.
- The planner writes `siteMemory={map,sites}` only from a walking-costed solve, or from any solve when SPF is absent or cannot estimate. It resets per map.
- Why: re-plans every 3 s change first-leg costs a little, and the straight-line and SPF costs differ. Without memory the step flipped A→B→A. Requiring both margins blocks flips on small and large visits alike. About a quarter of the visit cost still switches to a clearly better camp.
- Without SPF: `preferredSites`/`lockSites` are nil, so the old nearest-camp timeline is unchanged (switch at POS 0.56).
- A failed `EstimateWalks`, or an SPF without it, lifts the lock: the plan behaves as without SPF, and the margin still guards remembered camps.
- Busy camps (A5) beat stickiness: `avoidBusyCamps` runs before the optimizer.
- Not chosen (audit fix options): keeping the previous `firstLeg` costs across re-plans; offering alternatives only once SPF costs exist for all of them. The plan noted the risk that too much stickiness keeps a worse camp, which is why the margin is a documented constant.

## D2 — 2026-11-17 — Local search runs again only when its inputs change (fix-all run A4)
- **Partly superseded by D5/D6 (decouple run):** the `refinedPlan` gate and `YIELD_STEPS=32` stay. The `quest-costs` path and "recorded only after a walking-costed refine" are gone; "pausing quest-improve while another job is queued" (rejected below) is now done as DataWork idle priority (D6).
- Choice: `refinedPlan` stores the inputs of the last completed `quest-improve`: map, joined stop keys, and goal (mode, budget, `P.levelScope`, selected IDs, busy camp keys), plus origin.
- `refineNeeded` is true when there is no prior order (`#preferredIDs==0`), when any input differs, or when the player moved >= `REFINE_MOVE=0.1` map units. Otherwise `solve(0)` reuses the refined order through `preferredIDs`.
- With SPF, `refinedPlan` is recorded only after a walking-costed refine.
- quest-costs now runs `solve(0)` with walking costs, renders, then `refine("quest-improve")`. Before, it ran the full 250k-step local search before rendering.
- `evaluate()` yields every `YIELD_STEPS=32` simulated actions, so no optimizer resume replays a whole route inside one slice. The test bound is <= 64.
- Why: DataWork gives each job one resume per turn whatever that resume costs. Long improve resumes (2.4-3.9 ms) slowed vendor search to 5-9 % of its solo speed, and the 3 s movement re-plan restarted the 0.7 s-CPU search all the time.
- Not chosen (audit options): per-job time accounting in `DataWork.pump` (the plan keeps `DataWork.lua` untouched; fixes stay in callers); pausing quest-improve while a foreground or map job is queued.
- Accepted trade-off (from the plan): fewer refinements while moving; the route stays stable through `preferredIDs`.

## D3 — 2026-11-17 — Map search: persistent `vendor-index` job, separate from per-query `vendor-search` (fix-all run B1-B3)
- Choice: a `vendor-index` job (roles, then items once a query needs them) starts on the first typed character. Keystrokes never cancel it; only `resetIndex()` does (disable or provider loss).
  - Its valid() needs `indexToken`, the map shown and a non-empty query, so it pauses when the map is hidden or the box is emptied.
  - Budget is `FOREGROUND_MS=8` only after typing (`typed=true`). A programmatic `V.search` with no typing keeps the shared 2 ms slice.
- `vendor-search` (per query) only matches the in-memory index and hydrates candidates.
  - Decoded spawns persist in `cached` across keystrokes, bounded at `SPAWN_CACHE=2000` NPCs plus the current matches; past the bound, `dropSpawns(candidates)` keeps only the current query's.
  - The cache clears on a map change, on Clear and through `resetIndex`.
- Suggestions refresh at the first local match, then each time the local count doubles. Earlier suggestions stay visible while the user refines the text.
- Why: suggestions used to wait for the whole catalogue job, and every keystroke threw it away (about 3-8 s at Classic size). Indexing on map open would break the no-preload guarantee from the 2026-11-17 lightweight-database decision.
- Rejected: building the index on map open (preload); changing `DataWork.lua` or `Questie.lua` (the existing per-job budget argument was enough).

## D4 — 2026-11-17 — Dungeon quests: a kept-open menu follows its quest, not the log index (fix-all run C1)
- Choice: quest-log events call `D.refresh(true)`. It considers only our own open menu (`menu.entry==menuEntry`).
  - It closes the menu when its quest left the results, or when its log membership changed (`(live==nil)~=(menuEntry.catalogue==true)`).
  - Otherwise it copies `index/complete/title` from `C.findEntry` into the same `menuEntry` table, so `menu.entry==menuEntry` stays true and the item callbacks act on the current classic log index.
- `D.refresh()` with no argument (filters, search, buttons) still closes the menu.
- Why: on classic a quest-log index shifts when quests above it are added or removed. A kept menu would then act on another quest; review round 1 caught "Offer it to the party" pushing [200] instead of [2].
- Accepted limits: the shared menu is read through `ns._questMenu()`, a test accessor in `Menu.lua` (guarded; Menu.lua was out of scope). A kept menu keeps the item list it was built with.
- Superseded within the run: the first C1 patch only checked that the quest was still in the results. Round-1 review rejected it because of the stale classic index.
- Update (decouple run r-20261117-234605-6ba9): `Menu.lua` now has the proper accessor `ns.questMenuEntry()` (open menu's entry or nil); `DungeonQuests.lua` compares `ns.questMenuEntry()==menuEntry`. `ns._questMenu()` stays for the tests only.

## D5 — 2026-11-17 — SPF only draws the Follow arrow; it never feeds camp choice or route cost (decouple run r-20261117-234605-6ba9)
- Choice: `planOptions()` uses straight-line `travelSeconds` only (map world size / run speed). `QuestPlannerPath.lua` keeps `Path.available()` and `Path.follow()` (→ SPF `Navigate`); `EstimateWalks`, `firstLeg`, `walkCosted`, `options.lockSites` and the `quest-costs` job are removed. Every route is `solve(0)` → render, then optional idle `quest-improve`.
- Camp stickiness (`preferredSites` from `siteMemory`, 25 % / 20 s margin of D1) now applies with or without SPF.
- Why: two cost sources (straight line now, SPF walk later, async) for one decision made the camp depend on SPF presence and answer timing, needed a lock, and doubled solves per re-plan. One source makes the guide identical with or without SPF (tested across all SPF builds, `SPF_ESTIMATES == 0`).
- Brief conflict resolved: "stickiness without SPF" and "keep the no-SPF switch at POS 0.56" cannot both hold (measured: at 0.56 camp B is only about 10 s cheaper). Stickiness won. New `TWO_CAMPS` timeline for 0.50→0.53→0.56→0.65→0.56→0.53→0.44→0.53: A,A,A,B,B,B,A,A.
- Abandoned: the fix-all A2 design (lock remembered camps until walking costs arrive; only the walk-costed solve may switch); pairwise or first-leg SPF costs (gap 5 stays undone, now on purpose).
- Accepted trade-off: the plan ignores terrain (cliffs, water, caves). Follow with SPF still walks the real path to the selected step.

## D6 — 2026-11-17 — DataWork `"idle"` priority for the background local search (decouple run)
- Choice: `W.start(owner, run, valid, finished, budget, priority)`; `priority == "idle"` sets `job.idle`. In `pump()`, an idle job inside its slice is set aside (`waiting`) whenever `canRun(queue)` or `canRun(deferred)` finds a non-idle job that is current, not paused and `valid()`. If the others finish or pause mid-slice, waiting idle jobs get the rest of that slice. Idle jobs keep their order and the same budget, combat, cancel, pause, resume and busy rules. `requeue()` skips jobs paused while waiting.
- Only `quest-improve` (`QuestPlanner.lua` `refine()`) passes `"idle"`. With `priority` nil nothing changes (no `canRun` call).
- Why: DataWork gives each job one resume per turn; a 0.7 s-CPU refine shared the 2 ms slice with map search and the dungeon scan. Measured guard: a never-ending idle job leaves a normal job >= 90 % of its solo pace (`test_idle_job_that_never_ends_leaves_a_normal_job_at_least_90_percent_of_its_pace`).
- Requirement on callers: `canRun` calls other jobs' `valid()` without pausing them, so `valid()` should stay side-effect free.
- Still not done (D2): per-job time accounting in `pump`.

## D7 — 2026-11-17 — Camp memory skips stops whose camp "Camp busy" forced (decouple run)
- Choice: `avoidBusyCamps(stop, now)` also returns `narrowed` (any of the stop's camps was busy). `planOptions` collects those stop keys in `forced`; `solve()` writes `siteMemory.sites[stop.key]` only for objective stops not in `forced`. "Clear camp wait" resets `waitingAt` and `siteMemory`.
- Why: with memory always on (D5), recording the camp a busy mark forced would keep the player there after the 5-minute wait. Skipping it brings back the camp chosen before the mark; clearing lets the guide choose afresh from the player's position.
- Tests: `test_camp_chosen_before_a_busy_mark_returns_when_the_wait_ends`, `test_clear_camp_wait_chooses_the_camp_afresh_from_where_you_stand`, `test_busy_default_camp_gives_way_to_a_free_alternative` (each with and without SPF builds).

## D8 — 2026-11-17 — Map step numbers: overlay at canvas+2000, restated on every draw and map show (decouple run, stream D3)
- Choice: `QuestGuidance.lua` `stack()` sets overlay `QuestSharingRouteOverlay` = `min(9900, canvasLevel+2000)`, legend +1, markers +2 (selected +3), all in the canvas strata, writing only values that differ. Runs on every `drawMap` (also the cached path) and on `WorldMapFrame` OnShow (`pcall(HookScript)`, installed once at overlay creation).
- Why: native/addon pins sit hundreds of levels above the canvas and the client can re-level the canvas later; a level set once at creation (old child+10) ended up under them. Compare-before-write keeps the 4 Hz stationary redraw free of level calls. 9900 clamps below the client's frame-level ceiling.
- Still avoided: a map pin data provider/pool (kept out for secure gamepad paths, see "Selected-step arrow and route positioning"). The OnShow hook is installed lazily, so login cost stays zero.
- Open risk (review_d3, non-blocking): the overlay may now cover the player arrow or map overlay buttons in the same strata; pins grew to min 32x26 but the 26x22 grouping cell did not. Bug report: `BUGS/2026-11-17-guidance-map-numbers-hidden.md`.

## D9 — 2026-11-19 — One name per feature, second click for destructive actions (ux-fix run r-20261119-104206-0145)
- One-name rule (UX-27/29/45/62/63): player-visible text (windows, Settings labels, chat, help, README, CHANGELOG) uses exactly one name per feature: **Quest guide**, **Party quests window**, **Adventurer's Journal**, **Party finder**, **Zone levels**, **Fishing spots** (plus **Quest invitation** for the `/qs adventure` window). Not "quest planner/optimizer/route guide", "equipment explorer", "Seek fellow adventurers", "Optional" tab. Goal/level names come from one table: `QuestPlanner.lua` `P.goalNames` / `P.scopeNames` (= Settings labels). Leftovers still open: see `context/ux-review-2026-11-19.md` "Still open".
- Destructive actions need a second click (UX-04/11): Settings action rows with `confirm` (Reset settings, Clear errors, Clear logs) and the report window's Clear records arm on the first click ("Click again to reset/clear") and run only on a second click within 5 s; the label/hint go back after 5 s. Chosen over a StaticPopup: no new frame/taint path, testable in the harness, same pattern for all rows.
- Exception kept: `/qs reset` slash command resets at once (typing it is explicit; `tests/test_friends.py` depends on it).
- Settings toggles that have no effect in the current mode are greyed with `inactiveNote` and print one line when switched on (UX-01), instead of silently doing nothing.
- Every on/off slash command prints one line `ns.settingLine(key)` = Settings label + state + `ns.settingPath`; the key-style dump is only for `/qs status` (other tests pin its text).
- Key choice for item/ping/party finder/quick chat keys: warn in plain words what the key used to do (`ns.keyUsedToDo`), protected check BEFORE unbinding the old key. Not done: refusing movement keys or asking for a second press (beyond the suggestion; left for the user).
- Bag cleanup (UX-12): keep the list by ignoring the self-caused BAG_UPDATE for 2 s, NOT an automatic re-scan (keeps the "no background scans" rule above, `tests/test_quest_cleanup.py:151`).
- Process lesson: batches were file-disjoint, so any text owned by a file outside a batch (mostly `Settings.lua`/`Core.lua`, B1) was left as an orchestrator TODO; the final review then found those leftovers. Next time give the label/help-text owner (B1) a second pass after B2-B5 report their splits.

## D10 — 2026-11-19 — Low UX round choices (ux-low run r-20261119-113937-c955)
- Quest guide step clicks (UX-47): one action for both buttons (select + waypoint, also in combat); separate right-click "mark on map" (`showStopOnMap`) dropped instead of giving right-click a new job.
- Quest rewards tab (UX-54): opening it (button, tab, `/qs rewards`) no longer writes `rewardBrowser`, like Dungeon loot / Dungeon quests. `Rewards.lua` keeps `lastBrowser` and closes/frees only on master off or a true->false change, so a repeated `/qs on` does not close an open tab (review_b5@1 regression). Cost: `/qs rewards off` while already false does nothing. Settings row + `/qs rewards on|off` kept for now: removing them is the user's call.
- Chat prefix (UX-75): gold `|cffffd100` hard-coded in `Core.lua` with a comment, because `Style.lua` (S.GOLD) loads after Core.lua.
- Guide step notes (UX-60): `report.stepNotes` (actionable only: shared kill credit, wait time) is a separate field; `report.reasons` keeps every note for the report/debug text.
- Not changed on purpose: `travelFaction` default stays "all" (UX-49) - changing a default needs the user.
- 2026-11-19 SUPERSEDED by the user ("can u fix them?" = yes to both decisions): `travelFaction` default is now "mine" (own faction, a 4th choice "My faction"; existing saved "all" stays). `rewardBrowser` switch removed entirely: Quest rewards is a plain action card like Instance drops; only the master switch off closes the tab, so `lastBrowser` is gone.
- Finding ids: the key-unbind bug found in verification is UX-76 (renamed from a clashing "UX-47"); new ids continue after UX-76.

## 2026-11-18 — Tuning run stopped; trade-off choices (user)
- Stability margin capped: keep the previous route unless the new one saves >= max(12 s, min(5 %, 60 s)) or hands in more quests. Why: uncapped 5 % meant 90-180 s on long plans and discarded real improvements.
- Whole-route polish up to 40 actions, 12-action horizon beyond. Why: removing the beam made a 36-action zone 7 % slower (= nearest-first); whole-route local search at that size costs well under 1 s CPU.
- User chose to stop after the failed run: E-plan (calibration, yards, planner API) deferred. The Quest guide tab ships only when the planner API (`applySettings`, `markCampBusy`, `clearCampWaits`, `showReport`, options -> tab) exists — do not release it half-wired without telling the user.
- Lesson: three builders running the full suite in parallel on this machine blew 35-55 min limits; next time run builders serially or give 90 min limits and have builders run only their own suites.

## 2026-11-18 — Settings window redone in classic gold (user request)
- User: "entire setting re-done for clarity, colour classic yellow WoW style". Scope = Settings.lua window only (plus the quick chat editor inside it); other windows and `Style.lua` unchanged.
- Palette (locals in Settings.lua): titles/labels/headings `S.GOLD` (ffd100), values `S.WHITE`, help `HELP` e6e6e6, notes `NOTE` b5a888 (parchment), unpicked choices `DIM` c8c8c8, greyed `S.GREY`. No blue (`S.BLUE`, 55ccff, 88ccff, bbc2cf, d0d5df, 9daabd removed from Settings.lua).
- Layout: sidebar = dark well with 5 gold group captions taken from the `group` field on the first tab of each group (tab order and ids unchanged, so no saved-variable or deep-link change). Tab step 28 px (was 40). Open tab = gold text + gold wash (`tab.bg`) + 3 px gold bar; others white. Settings area = dark well (`W.well`) behind the scroll frame. Cards keep the opaque brown plate and get a gold edge (`r.cardEdges`, toggled by `showCard`).
- Chose to keep the "[x] / [ ]" markers and green On / grey Off: they carry state, tests pin them, and the game uses green for enabled.
- Tests updated only where they pinned the old look: open/other tab colour (test_settings), tab spacing 40->28 (test_look), editor channel tag colour (test_quick), raw label compare now strips colour codes (test_items).

## 2026-11-18 — Quest guide tab finished; v0.4.22 (user)
- User chose "finish the tab" over hiding it. Settings are the single source of truth for goal/minutes/IDs/scope: `readSettings()` runs when the guide opens and in `applySettings()`; `/qs plan xp|budget|selected|range` write the saved keys (`saveGoal`) so command and tab never disagree.
- Chosen-quests goal with no IDs keeps the previous goal and prints a hint (no empty plan).
- Pace: median of last 40 samples, >= 5 needed, clamped (kill 4-40 s, talk 1-15 s); kill sample = gap between two rises of the same objective (1-90 s; a rise of n = n samples of gap/n); talk sample = QUEST_DETAIL/QUEST_COMPLETE to QUEST_ACCEPTED/QUEST_TURNED_IN (<= 60 s). Chosen over the planned yard-proximity timer: no position polling, no timers. Auto-accept gives ~0 s samples (clamped to 1 s).
- E4 (camp radius in yards) stays deferred; not needed by the tab.

## 2026-11-18 — Dungeon quest chain = indented bullets; "done" propagates backwards only through required links
- `chainPrev/chainNext` (id -> other -> required) are built in `D.scan` `link()`; required = sole prerequisite, an "all" group, or `nextQuestInChain`. An "any one of N" prerequisite is NOT required (finishing the later quest does not prove which earlier one was done).
- A step is ticked green when `completed(id)` or any required later step is `finished()`; ticked-by-later steps say "not needed" so the player does not travel to a giver with nothing left.
- SUPERSEDED same day (user: nesting belongs in the LEFT list, description only for the clicked step): `D.search` now reorders results parent-first with `depthOf[id]` (indent 22 px/level, max 4); rows of finished steps get the ReadyCheck icon + grey text; the right panel shows only Done status + previous/next chain quests. The right-panel chain tree was removed.
- Panel picture removed only on the Dungeon quests details frame (`journalSurface.grain:Hide()`); Loot/Rewards panels keep it (shared `E.details`).

## 2026-11-18 — Map search pin = red X raid marker
- Gold coin read as a random item, not a destination. Chose `UI-RaidTargetingIcon_7` (red X): built into every client, no new art file, universally read as "go here". One pin for all kinds (no per-kind icon).

## 2026-11-18 — Travel map: static data, own module, towns = flight-master towns
- No dungeon-entrance or transport data existed; Questie's ZoneDB entrance format could not be verified offline (data lives in LibQuestieDB) -> typed static tables in `TravelData.lua`, so the overlay works without Questie and is testable. Cost: coordinates are from memory (~1-3 % off); flagged in README/tooltips/settings note.
- One pin per entrance building (Blackrock Mountain lists BRD/LBRS/UBRS/MC/BWL; Scarlet Monastery 4 wings; Ahn'Qiraj 2).
- "Closest waypoint (town)" read as: town with a flight master usable by the faction (neutral towns count for both), straight-line on the entrance's continent (vertical scaled 2/3). Boat/zeppelin hops are not factored in.
- Lines only on hover, only when both ends project onto the shown map (so overseas boat lines need the Azeroth map); tooltip says so otherwise.
- Default ON (user asked for it visible), unlike the other opt-in map tools.

## 2026-11-18 — Map search pins: icon by NPC kind (replaces the single red X)
- Pin icon derives from the NPC's Questie `subName` title via ordered substring rules (class > profession > service > generic trainer > bag). Substring rules, not Questie flags, because the title is what the user searched and is already indexed. Class trainers use the in-game class sheet (`CLASS_ICON_TCOORDS`) with a book fallback.
- Not done: item icon for item searches (pin has no item reference); legend.

## 2026-11-18 — My trainers layer lives in TravelMap, index in TrainerIndex
- Auto trainers are a separate lifecycle from the search (which is gated on a typed query and opt-in), so a new `TrainerIndex.lua` scans once (idle priority, only with a zone/continent map open) and `TravelMap.lua` draws; pins hide while a search is active to avoid duplicates.
- Index everything once (all professions + classes), filter by what the player knows at draw time, so learning a profession needs no rescan.
- "Profession and faction trainers" read as: my professions + my class, only NPCs friendly to my faction. Zone/continent maps only (Azeroth overview skipped: too crowded).
- Food vendors lost the cooking icon so Cooking trainers are distinct from them.

## 2026-11-18 — Scoped QuestieDB reads: cheap checks first, big tables only for what passes
- QuestieDB caches every `(id, field)` read for the session (`docs/read-performance.md`), and has no zone/level index. So the saving is not enumerating less but reading less per id: single numbers/strings first (`Q.questGate`, `Q.npcFriendly`, item `name`), tables (`startedBy`, `spawns`, `vendors`) only for ids that pass. `Q.me()` snapshots level/race/class/faction once per scan.
- Planner: gate (race/class, level > player+1, past max level, quest filed on another continent) before `plannerStarters`; counted in `coverage.skipped`, shown in `/qs plan why` and the debug text. Active log quests bypass. Id list cache (`zoneScope`) stores the level it was built for: a level-up rescans. Cost: skipped quests are no longer listed individually under `blocked`. Slack of 1 level keeps the "XP can unlock it" path.
- Dungeon quests: opens as `defaults(true)` (my character). Scan scope = filters at scan start (`scope`); `D.refresh` rescans when a filter widens past it (`covers`). The gate ignores `requiredMaxLevel` (`noMax`) so a lower level filter still works on the same scan. Reward scan on hover (all items, `questRewards`) NOT changed: no quest->reward link in QuestieDB.
- Map search: item scan is per typed words (`itemWords`, `wordsCover`): name read per item, `vendors` read only for matches, rows memoised in `itemRows`. Seller queries ("vendor") need no item scan when the provider has the vendor flag (`mask`); without the flag they scan all items to link sellers (old behaviour). Trusting the flag means an unflagged NPC that only appears in some item's `vendors` is no longer a "vendor" result (fixture NPC 3 got the flag). NPCs friendly only to the other faction (`friendlyToFaction`) get no row. Not done: NPC `zoneID` as a location gate (best-guess zone, would drop multi-zone NPCs).
- Not touched: `TrainerIndex.lua` (another session's in-flight work) still reads `subName` of every NPC and `spawnList` for each trainer; it already stores `friendlyToFaction` and could use `Q.npcFriendly` before `spawnList`.

## 2026-11-18 — Travel faction filter scope
- `travelFaction` filters transports and the dungeon closest-town list only; dungeons are faction-less and trainers keep their own rule (my faction). Neutral always shown. Chosen over a 4th "my faction" option to match the user's three choices (Horde, Alliance, all).
- Neutral colour = white (user request), so pin letters switch to black for contrast.
- 2026-11-18: lead-ins (`nextQuestInChain` / `breadcrumbForQuestId` / `breadcrumbs` / `availableUntilCompleted` pointers that are not real prerequisites) tracked in `chainLead`; `include()` adds them to the dungeon with role "Lead-in". `disabledByQuest`, `exclusiveTo`, `parentQuest` deliberately not used. See BUGS/2026-11-18-dungeon-quests-lead-in-standalone.md.

## 2026-11-18 — Bag helpers and chat lock
- Request: chat input off in combat, auto-sell gray, Space-over-item bookmark that blocks selling, auto-arrange bags by topic "including the one bag". Built as `BagTools.lua` + `ChatLock.lua`; each has its own setting.
- Defaults: only `bagBookmarks` is on (inert until Space is pressed over a bag item). `autoSellGray`, `autoSortBags`, `chatLock` are OFF: they spend money, move items or change input, same rule as `autoAcceptQuests`. Flip in `ns.defaults` if the user wants them on.
- "Including the one bag" read as: the backpack is included and ALL bags are ONE ordered list of slots (backpack first). Quivers / profession bags (bag family ~= 0) are skipped; bank untouched. Not split/merge stacks (extra risk; same items sort adjacent, bigger stack first).
- Topics (class IDs): quest (class 12 or `ns.bagItemFor`) > consumable 0 > equipment 2,4 > materials 3,5,7,8 > recipes 9 > other > gray (quality 0) last. Then class, subclass, quality desc, name, id, count desc, old position (stable: an ordered bag makes zero moves).
- Arranging re-plans before EVERY move and does the first move only (self-healing against loot arriving); swap = pickup A, pickup B, pickup A again if the cursor holds B's item; waits while a slot `isLocked`; stops on combat, a held item, 3 identical repeated moves (game refused) or 400 moves. Automatic run waits 3 s of quiet bags (`BAG_UPDATE_DELAYED` debounce) and stays silent.
- Bookmark = item ID (Classic has no per-item GUID), so every stack of that item type is protected. Space handled by a keyboard frame that propagates every key except a Space that bookmarked something (so no jump). Hover found with `IsMouseOver` over `ns.bagEachSlot` (exported from `Bags.lua`).
- Auto-sell skips: bookmarked, `hasNoValue`, sell price 0, and any item `ns.bagItemFor` says a quest needs. Sells one item per 0.1 s only while the merchant window is open.
- Chat lock hooks `ChatEdit_ActivateChat` and each `ChatFrameNEditBox` `OnEditFocusGained`, and closes an open box on `PLAYER_REGEN_DISABLED`. Quick-chat ring with `quickSend` uses `SendChatMessage` directly, so it still works; its "draft into the box" mode is blocked in combat on purpose.
- Not verified in the real game (mock tests only): `SetPropagateKeyboardInput` during combat, `CursorHasItem`/`isLocked` timing on swaps, `ChatEdit_DeactivateChat` on an always-shown box.

## 2026-11-18 — Remove the profession Upgrades guide
- User: profession upgrades "not useful now". Removed the whole feature instead of hiding it: Upgrades tab/panel and tab bar, Settings card, `D.professions` rank/trainer data, preview-tool view, tests. Supersedes the 2026-11-17 "static profession-upgrade companion" decision above.
- Kept: Cooking recipe list, fish waters, vendor places, cooking sources, `professionGuide` setting (now means the Cooking list only), trainer icons on the map (separate `TrainerIndex.lua`).
- `/qs professions` with no argument now opens Cooking (was Upgrades); `on|off` unchanged. Old saves need no migration.

## 2026-11-18 — Build script allowlist, no old-save migrations
- `build_release.py` ships only .toc-listed files + `QuestSharing.toc` + `Bindings.xml`; anything else in `QuestSharing/` is skipped and printed; an unlisted .lua/.xml fails the build. Never overwrites an existing `dist/QuestSharing-<version>.zip` without `--force`. Reason: tests overwrote the published zip with unreleased code.
- Dropped the one-time upgrade steps for saves older than 0.4.12 (user asked to remove the "legacy" list items 1 and 2). Consequence: an ancient save keeps its old `near/panel/chat/announce/pickup/zoneLevels/debug` values; `dbVersion` is still stored for any future migration.
- Progressive versions (same day): the build refuses a version that already has a git tag `vX.Y.Z`, skips ahead of or goes back from the last tag (allowed next: patch+1, minor+1.0, major+1.0.0), a CHANGELOG not newest-first (`Unreleased` first), or a newer zip in `dist/`. `python build_release.py --bump [patch|minor|major]` raises `## Version` in the .toc and turns the CHANGELOG `## Unreleased` notes into the new section; it refuses while the current version has no tag. Without git, the previous release is taken from the CHANGELOG. Tests build with `policy=False` so they never depend on release state.


## 2026-11-19 Tank aggro: mark, not auto-target
- User asked to auto-select the lowest-aggro mob. Addons cannot call TargetUnit in combat and secure buttons cannot be re-pointed in combat, so Aggro.lua marks the pick (`>> N% <<`) and the user Tabs/clicks.
- Pick only when 2+ enemies are within ~10 yd ("pulling many"); far enemies still show their %.
- Rejected: auto raid marks with SetRaidTarget (would overwrite the group's marks). Possible follow-up if the user wants it.
- 2026-11-19 user picked option 1 (of: auto nameplates / target-only list / both): the aggro setting switches enemy nameplates on itself. Rejected the nameplate-free list, which misses untargeted mobs (the ones a tank needs). Aggro keeps its own saved CVar copy, separate from Highlight's `cvarSaved`, so turning one helper off never hides the other's nameplates.
- 2026-11-19 review round: no mark when the lowest near enemy is already at 100 % (every mob on you = nothing to fix, a red mark would be a false alarm). Red is reserved for the marked mob; not-on-you mobs are orange so the mark stands out.
- 2026-11-19 round 3: user asked for heat colours (green = little aggro, red = you hold it) and always-visible numbers; supersedes the earlier green = on-you / red = mark scheme. Marked enemy keeps its heat colour, stands out by large font + `>> <<`. Flame = Spell_Fire_Fire icon (border trimmed) beside the number at 100 %, not a portrait.
- 2026-11-19 round 5: the marked lowest-aggro enemy is white (user), no longer its heat colour.
- 2026-11-19 review round: idle enemies grey (still always shown, as the user asked) so green keeps meaning 'leaving you'; white mark keeps its enemy unless another candidate is 10+ points lower (anti-flicker). Long lines kept: the codebase already has many >120.
- 2026-11-19: several white marks (user picked 'close to the lowest'): lowest + every near in-fight enemy <100 % within 10 points. The band also removes flicker, so the SWITCH_BY sticky-mark rule was dropped.

## 2026-11-19 — Quest guide plans for the player alone (user)
- User: "quest optimizer should not care about party." The Quest guide / QuestOptimizer never uses party members' quests, progress or goals; no party goal, no party-aware planning.
- Why: keeps the guide focused and predictable; party coordination lives in the Party quests window, sharing and the party finder.
- How to apply: reviews must not raise party stories against the guide (UX-02 re-scoped to the solo problem: quest IDs are never shown, names not accepted; severity high -> medium). The earlier "party-aware planning" idea (2026-11-17) is dropped, not deferred.
- 2026-11-19 room story (user): white = untouched/idle (replaces grey), then red/green/orange follow the fight. The lowest-near marks keep the big `>> <<` but use the heat colour, so white only ever means 'not fighting yet'. My reading: the arrows were kept since the user's original goal was finding the mob to grab.
- 2026-11-19 alarm (user: lowest grey, portrait, 'losing aggro', pulsing red border, 'not confusing'): one mark type only (arrows removed); alarm only below 50 % so orange keeps meaning 'coming back' (resolves the clash with the room story); red ring pulses while the 'on you' red number is steady and they never share a mob (marked < 50 %).
- 2026-11-19 group marks: 'significantly lower' = 20 health points (constant SKULL_BY, only the wait is a setting as asked). X moves only when no living visible enemy carries an X (also respects a hand-placed X). Others' marks are never taken; the tank's own mob may take OUR skull (one mark per mob). Separate switch, default off, because it is outward-facing (party sees it).
- 2026-11-19 (user): group marks wait 10 s into each fight (a setting, like the skull wait) and are placed only in a party or raid.
- 2026-11-19 ABANDONED: automatic group marks (X on my target, skull on lowest health). SetRaidTarget is #protected (secure code only); a secure macro could only mark target/mouseover. User chose to discard the feature entirely, not a one-key or hint-only version. Do not re-explore unless Blizzard lifts the protection.

## 2026-11-19 — Dungeon 'get them all' route
- Separate pure module `DungeonRoute.lua` instead of extending `QuestOptimizer` (zone-local, farming model). Costs are estimates (ground 1.25 terrain factor, flight 30 yd/s x1.3 + 10 s, ride + 60 s wait, hearth 30 s).
- User choices: route pickups + talk-only lead-ins; kill/collect prerequisites only listed. Flights: learned at flight masters; unknown set = assume all; check box forces assume all.
- Pickups at the same NPC are grouped into one step; walk hops < 5 s dropped.



## D11 — Optimizer reference case: Coldridge Valley (2026-11-19, user request)
User: "first zone gnome ... loop until you find the optimized solution, and then use this as usecase how should behave the optimizer in general". Test: `tests/test_coldridge_valley.py` on real Classic QuestieDB rows (`tools/build_coldridge_fixture.py`). Solo only (party rule above).
Loop (each round = run the guide, read the route as a player, fix the model):
1. Mock lacked `IsDoableVerbose` -> 7 chain quests "unknown". Fixed the test mock (real Questie reports the block reason), not the addon.
2. 10 quests, 1,017 s: Thalos (33.5,71.8) hand-in shown at Balir's spot -> radii in map fractions (0.045 of Dun Morogh ~220 yd). Fix: yards (E4). BUGS/2026-11-19-planner-steps-merged-in-map-fractions.md.
3. Level 3-4 quests (A Refugee's Quandary, Mornbrew pair) skipped at level 1. Fix: `LEVEL_AHEAD` 3 + XP closure + multi-level XP table. 13 quests, 1,541 s, but walked back from Kharanos.
4. Back-walk cause: level forecast counted quest XP only. Fix: kill XP. 1,250 s, valley finished first.
5. Class quest Glyphic Memorandum excluded ("Class, profession or event"). Fix: a class quest you can take is judged by where its giver is. 14 quests, 1,260 s first route / 1,211 s refined.
6. Optimality: local search converges at ~37.5k moves whatever the budget; independent simulated annealing (4 x 300k random or-opt / 2-opt / swap on `_evaluate`) best 1,201.9 s = 0.8 % better, under the 12 s stability margin. Accepted as optimized for this cost model.
**Rules the optimizer must keep in every zone (each guarded by a test that fails without its fix):**
- R1 Distances that group things (camps, merged steps) are yards, not map fractions.
- R2 The level forecast uses quest XP + kill XP over several levels; quests up to 3 levels ahead join where you reach them.
- R3 A class quest you can take is local when its giver is here.
- R4 Finish the zone's local work before hand-ins that leave it (no walk back in).
- R5 A follow-up at the same NPC is taken in the same visit.
- R6 Pickups and hand-ins point at the NPC's real spot.
- R7 The refined route is within 2 % of an independent search with the same cost model.
Not done (needs data): mob level per objective for kill XP (assumes your own level); real cost calibration in-game.

## D12 — Shared camps view in the addon (2026-11-19, user choices)
- Shows camps of the Quest guide's planned quests only (not every zone quest): matches what the player will do.
- Switch `campMap` in Settings > Quest guide (off by default) + `/qs plan camps [on|off|table]`; key avoids the `questPlanner*` prefix so toggling it never triggers a replan.
- Map + camps table window (the HTML's matrix). The network graph stays in the camp label tooltip (mobs x spawns - quest); a full node-link graph does not fit WoW's map UI.
- Camp = the guide's `groupCamps` (100 yd) on all planned objectives' spawns together, shown when >= 5 spawns (less clutter than the guide's 3). Blue = 2+ quests, grey = 1 (colour + the label tooltip, never colour alone).
- Only the small labels take the mouse; circles never block map clicks. Hidden in combat. Table: <= 14 rows, <= 8 columns (rest fold into "Other", no spawn dropped).
- Unverified: the circle texture's look in the real client.
- 2026-11-19 (user: "this is what i wanna see but in wow style inside"): the camps table became the full Shared camps window mirroring tools/coldridge-network.html (buttons, network, map, matrix). Network curves = 8 straight CreateLine pieces per link; map background = the zone's own map art (dimmed), plain inset when the client gives no art; givers within 14 px share one label; "Mountaineer" title dropped from short names.
