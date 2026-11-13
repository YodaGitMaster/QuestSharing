# Decisions

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
