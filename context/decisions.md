# Decisions

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
