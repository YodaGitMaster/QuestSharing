# Schema
Last updated: 2026-11-13

## Addon loading and persistence
- `QuestSharing/QuestSharing.toc`: Interface 16001, version 0.4.6; declares file load order and SavedVariables.
- Lua modules receive `local ADDON, ns = ...`; `ns` is the shared namespace, not a class.
- `Core.lua`: `ns.defaults`; `ns.db` initially copies defaults. On `ADDON_LOADED`, missing settings are filled and `ns.db` aliases saved `QuestSharingDB`; current `dbVersion = 3`.
- SavedVariables: `QuestSharingDB` (settings), `QuestSharingLog` (debug log); persisted by the game.
- Optional dependencies: Questie, QuestieDB, AnglerAtlas, AtlasLootClassic, AtlasLootContinued; game API differences handled by `ns.compat` in `Compat.lua`.

## Runtime shapes
- `Share.lua`: `ns.known[questID][lowercasedMemberName] = status`; `ns.offered[questID][lowercasedMemberName] = true` after an offer reaches a member.
- `Sync.lua`: addon channel messages separated by `|`; `H|1` hello, `L|i|n|entries` quest-list parts, `P|entry` quest update. Entry: `questID:complete(0/1):objectives`; consult encoder/parser before changing wire format.

## Optional tools (2026-11-13)
- `ns.db.fishingMap` / `ns.db.rewardBrowser`: new booleans, default `false`; filled by existing missing-default migration, dbVersion remains 3.
- `ns.db.fishingWaters[id]`: local positive numeric ID -> `{name, map, x, y, minSkill?, safeSkill?, fish, notes}`.
  - `map`: positive integral UiMapID; `x` and `y`: 0..100.
  - Skill fields: whole numbers 0..10000, absent when unknown; no-getaway >= minimum when both known.
  - `name` <=80 chars; comma-separated `fish` <=500 chars; free `notes` <=300 chars.
  - User-recorded data; preserved by settings reset, never transmitted to party members.
- `AnglerAtlas.MM:GetModule("DATA")`: runtime-only adapter for `mapToZoneID`, `zones[zoneID].{name,fishingLevel,fishStats,isForeverZone}`, `fish[id].name`.
  - Summary stays separate from water records; Forever provisional flag retained; no bundled catalogue.
- `ItemDB.GetAllIds()`: shared read-only ascending item ID list; recent QuestieDB needed.
- Equipment index: `{id,kind,sub,quests,name,level,required}` from item `class`, `subClass`, `questRewards`, `name`, `itemLevel`, `requiredLevel`.
- RewardOption: `{itemID,name,link?,itemLevel,slot,questID,questName,questLevel,requiredLevel,zone,cached}`; ephemeral, sorted by item level descending.
- Filter defaults: own class/level/faction, all slots, quest level from level-10 to level+3, completed quests hidden, text empty.
- `LibQuestieDB.Enum.{classKeys,factionRaceMasks,raceMaskById}`: required for reliable eligibility; use arithmetic mask intersection to preserve bits above 31.
- `Questie.lua` starter spawn records now include `area` alongside `zone,x,y,dungeon`, including item-drop starters.

## Quest invitations (2026-11-13)
- `ns.adventure`: `entries`, `message`, `route`, `prepare`, `open`, `command`, `close`; loaded after OptionalUI.
- Session-only composer: selected quest ID, wording index 1..3, editable preview and channel input; no SavedVariables changes.
- `message(e, style)`: fresh unfinished log entry -> invitation <=255 bytes. Keeps full quest link when possible, omits zone for quests outside current area, falls back to UTF-8-safe plain title for unusually long links.
- `route(input)`: `prefix, isCurrent` or `nil, error`; accepts current, standard chat aliases, whisper recipient and joined channel number/name (`GetChannelName` when available).
- `prepare(e, text, route)`: revalidates quest and byte limit, then preserves/appends to active chat for current or calls ChatFrame_OpenChat with channel prefix. Never sends automatically.
- Explicit channel changes refuse nonempty existing drafts; duplicate quests and combined drafts >255 bytes are rejected without mutation.
- Entry points: quest right-click menu (8 rows total; invitation is row 2, immediately after Tell the party how I am doing), Optional settings action, `/qs adventure [quest ID | exact title | quest link]`.

## Retired quest overlay (2026-11-13)
- `QuestMap.lua` deleted and removed from load order. No `ns.questMap` runtime table, renderer, refresh timers or setting row.
- `QuestSharingDB.questMap` is removed at ADDON_LOADED, even when previously true; dbVersion stays 3.
- Legacy `/qs questmap ...` explains the removal and cannot enable overlays.

## Shared equipment explorer (2026-11-13)
- `EquipmentUI.lua` loads after OptionalUI and before Rewards/Loot; `ns.equipmentUI` owns one `QuestSharingEquipment` top-level window.
- Session-only shared filters: `{category, subtype, slot, mode, min?, max?}`. Categories: All equipment, Weapons, Armor, Accessories; mode: Required level or Item level; inclusive bounds 0..1000, blank = unbounded.
- Native item metadata adds `kind`/`sub` numeric item class/subclass. QuestieDB supplies known fallback metadata; unclassified subtypes stay unknown. Required level 0 remains valid.
- `page(key)`, `show(key)`, `visible(key)`, `close(key?)`: only one child page is active; hiding/switching calls its suspend function to cancel timers. Pages have `refresh` and `suspend` callbacks.
- `matches(info, fallback?)`: first requires confirmed native numeric quality >=3 (Rare/blue); unknown quality and grey/white/green are hidden. This floor is fixed and Reset filters cannot remove it. Then applies the common type/subtype/slot/range predicate; quest eligibility remains separate. Quest/Loot render seven item cards per page and reuse inline scrollable route/source panels.
- No standalone reward/loot/route/source top-level windows remain; shared tab filters survive tab switches, not logout.

## Instance loot search (2026-11-13)
- `ns.loot`: `open`, `close`, `scan`, `search(text, instanceKey?, encounter?)`, `instances(text?)`; session-only data, no SavedVariables.
- LootDrop: `{itemID,item,instanceKey,instanceName,who,difficulty,provider,sourceID,kind}`; `item` references shared local item cache `{id,name,cached,info?}`.
- Visibility: loot results and encounter choices require shared native `item.info.slot` to be recognized by `Rewards.lua`; unknown/unloaded items and non-equipment remain hidden. Item-cache events refresh eligibility.
- Instance record: `{key,name,count}`. Atlas key = module/content; Questie fallback key = `area:<AreaTable ID>`.
- Dungeon identity: AtlasLoot public content type must identify Dungeons when present; known Classic/Forever instance IDs cover older providers. Raid flags/content types, oversized groups, unknown IDs without classification and zero-ID extras excluded. Missing InstanceID supported only for recognized dungeon areas (Dire Maul). Cross-encounter links must target an eligible dungeon.
- Primary provider: compatible `AtlasLoot.ItemDB.Storage` or `AtlasLootContinued.ItemDB.Storage`, modules named `*DungeonsAndRaids*`, content classified as an eligible dungeon.
  - Encounter `items[bossID]`: name, `IgnoreAsSource`, numeric difficulty keys, optional cross-encounter `link`.
  - Public `GetItemTable(module,content,boss,diff)` resolves difficulty aliases/links and returns row list, format and difficulty metadata.
  - Positive numeric `row[2]` is an item ID; header strings and non-Item formats are excluded. IgnoreAsSource tables excluded; Trash ExtraList retained.
- Fallback: QuestieDB `Item.GetAllIds`, `npcDrops`/`objectDrops`; source spawns need `{-1,-1}` dungeon marker or a mapped `UIMapType.Dungeon` map. Outdoor mobs, raid interiors and unknown areas are excluded by a known dungeon-area registry; map type alone is insufficient. Forever Hall of Thanes has an unverified provider map placeholder and is not added to the fallback area registry. Coverage explicitly partial.
- Index batches: <=100 rows/items per timer; native names: <=10 unique item IDs per 0.1s timer. `Rewards.itemInfo` is the shared native item metadata reader.
- `GET_ITEM_INFO_RECEIVED` updates the local cache and debounces refresh. Closed browsers cancel unfinished indexing/names; reopening retries uncached names.
- GUI entry points: Optional settings action, quest reward browser button, `/qs loot [search]`. No map symbols or automatic chat added.

## Artifacts
- `build_release.py`: reads manifest version and matching CHANGELOG section; packages Lua/TOC/XML into `dist/QuestSharing-<version>.zip`, rooted at `QuestSharing/`; writes `dist/RELEASE_NOTES.md`.
- `tests/harness.py`: WoW API mocks and real addon loading through `lupa.lua51.LuaRuntime`.
