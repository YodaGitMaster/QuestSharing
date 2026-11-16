# Decisions

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
