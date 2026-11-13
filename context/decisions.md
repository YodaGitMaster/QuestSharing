# Decisions

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
