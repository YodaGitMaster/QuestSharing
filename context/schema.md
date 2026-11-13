# Schema
Last updated: 2026-11-13

## Addon loading and persistence
- `QuestSharing/QuestSharing.toc`: Interface 16001, version 0.4.14; declares file load order and SavedVariables.
- Lua modules receive `local ADDON, ns = ...`; `ns` is the shared namespace, not a class.
- `Core.lua`: `ns.defaults`; `ns.db` initially copies defaults. On `ADDON_LOADED`, missing settings are filled and `ns.db` aliases saved `QuestSharingDB`; current `dbVersion = 3`.
- SavedVariables: `QuestSharingDB` (settings), `QuestSharingLog` (debug log); persisted by the game.
- Optional dependencies: Questie, QuestieDB, AnglerAtlas, AtlasLootClassic, AtlasLootContinued; game API differences handled by `ns.compat` in `Compat.lua`.

## Runtime shapes
- `Share.lua`: `ns.known[questID][lowercasedMemberName] = status`; `ns.offered[questID][lowercasedMemberName] = true` after an offer reaches a member.
- `Sync.lua`: addon channel messages separated by `|`; `H|1` hello, `L|i|n|entries` quest-list parts, `P|entry` quest update. Entry: `questID:complete(0/1):objectives`; consult encoder/parser before changing wire format.

## Optional tools (2026-11-13)
- `zoneLevels`: SavedVariables boolean, default false; `ns.zoneLevels` owns read-only click-through badges and a selected/hovered-zone panel. `range(id)` returns min?,max?,source?: City/Sanctuary for known non-leveling maps, otherwise validates C_Map.GetMapLevels bounds 1..1000 and caches native success. Empty/zero/invalid native data uses a verified guide; unknown maps remain unknown. Fallbacks are not cached so late native data supersedes them; refresh clears native cache.
- ZoneLevels local guides: UI-map-ID -> `{min,max,source?}`. 39 Classic brackets, Zephras/Riverglades published guides (default source "Zone guide"), Hyjal/Shen'dralas known quest-level spans (source "Known quests", incomplete coverage explicitly labelled). Local places map: six city IDs plus Moonglade Sanctuary. No runtime Questie/LibTourist dependency or database scan.
- `zoneLevelsOptInMigrated`: SavedVariables migration marker, not a user setting/default. ADDON_LOADED forces zoneLevels=false and sets this true once if missing/non-true; later explicit true/false choices survive reload. Reset leaves the marker intact and resets zoneLevels=false. dbVersion remains 3.
- Map zone records: `{id,name,x,y,min?,max?,source?}` from native GetMapChildrenInfo(Zone,true) and GetMapRectOnMap; only finite normalized rectangles and outdoor Zone map types qualify. World/cosmic views prompt navigation rather than stacking all world zones. Guide/known-quest source prefixes appear in the hovered/selected panel; City/Sanctuary badges replace meaningless question marks.
- One view per observed map canvas `{canvas,labels,zones,panel,heading,text}`; previous canvas hidden, frames pooled, sizes/zoom read while visible. Own frames do not receive mouse input. No map navigation/native pin calls or quest minimap symbols. Tick 0.25s while map is shown, 1s otherwise; rebuild zone data every 2s and retry missing data.
- `autoSpellRanks`: SavedVariables boolean, default false; existing missing-default fill, no dbVersion change. `ns.spellRanks` exposes update(report), schedule(report), settingChanged(), status().
- Spell-rank catalogue is session-only: exact localized spell name -> highest numeric learned rank `{id,name,rank,index,ambiguous?}`, plus spellID -> entry; modern C_SpellBook or legacy player bank only. Passive, future/off-spec, unranked and ambiguous highest ranks are excluded.
- Out-of-combat normal action-slot replacements use confirmed spell IDs and learned numeric ranks; verify picked-up cursor, revalidate target after pickup callbacks, and read back placed action. Scan at least 180 standard slots (or greater native MAX_ACTION_BUTTONS, capped at 1000), independently of visible page counts; unsupported slots are ignored. Macros/items/pet actions/empty slots remain. Combat/temporary bars/busy cursor defer to events; client refusals pause until reload.
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
- RewardOption source: `{itemID,name,info,link?,itemLevel,slot,questID,questName,questLevel,requiredLevel,zone,cached}`; ephemeral, filtered before name grouping.
- Grouped quest result: representative RewardOption fields plus common EquipmentGroup fields below and `routes[]={questID,questName,questLevel,requiredLevel,zone,itemIDs,seenIDs}`; routes unique by quest ID, ordered by ID. Detail preserves every eligible route; map action uses routes[1].
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
- Session-only shared filters: `{category, subtype, slot, mode, min?, max?, sort, stats={{},{},{}}}`. Categories: All equipment, Weapons, Armor, Accessories; mode: Required level or Item level; inclusive bounds 0..1000, blank = unbounded. Sort: Highest item level (default), Lowest required level, Name A–Z.
- Each `stats[i]` is `{stat?,min?}`; nil stat disables a condition. All three conditions use AND; minimum whole 1..100000, blank = 1. `applyStat(index,label,minimum)` validates without replacing the last valid state on failure. Any stat (`""`) clears one condition; reset clears all and cancels pending edits.
- `GetItemStats(link)` / `C_Item.GetItemStats(link)` supplies native token -> number tables. Prefer modern API, fallback to legacy on nil/error. Cache successful tables by link; clear on GET_ITEM_INFO_RECEIVED before page refresh. Missing/malformed bonus values never match. No stat API calls without active conditions; no SavedVariables changes.
- Native item metadata adds `kind`/`sub` numeric item class/subclass. QuestieDB supplies known fallback metadata; unclassified subtypes stay unknown. Required level 0 remains valid.
- `page(key)`, `show(key)`, `visible(key)`, `close(key?)`: only one child page is active; hiding/switching calls its suspend function to cancel timers. Pages have `refresh` and `suspend` callbacks.
- `matches(info, fallback?)`: first requires confirmed native numeric quality >=3 (Rare/blue); unknown quality and grey/white/green are hidden. This floor is fixed and Reset filters cannot remove it. Then applies the common type/subtype/slot/range predicate; quest eligibility remains separate. Quest/Loot render seven item cards per page and reuse inline scrollable route/source panels.
- `dropdown`: reusable unnamed child popup, direct/searchable choices, ten visible options, scroll/arrow/Enter/Escape; class values retain tokens with localized display labels. No Blizzard dropdown templates.
- `liveBox` / `searchBox`: 180ms debounce, serial cancellation, `dirty`, `flush` and `cancel`; hidden pages do not apply pending work and resume dirty fields on return. Enter applies; Escape/search Clear clears immediately.
- `sortResults`, `go`/`goInstances`, `wheel`, `navigation`: shared ordering and bounded paging; keyboard stays scoped to focused edit boxes rather than capturing game-wide movement keys.
- EquipmentGroup: representative source fields plus `{key,sources[],itemIDs[],versions[]}`. `key` = trimmed, color-stripped lowercase item name; sources retain filtered raw records sorted by module source ordering; itemIDs/one-source-per-ID versions sort numerically. Representative is highest native item level, lowest item ID on ties, first sorted source for identical IDs. No raw/provider table mutation.
- `groupItems` runs after filtering; `versionLines` labels distinct IDs and native levels when a name has multiple versions. Counts/pages use grouped results, sorting uses representative metadata.
- Result selection uses stable normalized name keys, survives visible refreshes/new versions, and falls back to the first visible result. Inline detail panels update automatically; empty/loading states replace stale details.
- Clear filters clears shared controls plus active search/location/source; quest character eligibility stays, near-level restriction is removed and completed quests hidden. My level caps item required level at native UnitLevel without a minimum.
- No standalone reward/loot/route/source top-level windows remain; shared tab filters survive tab switches, not logout.

## Instance loot search (2026-11-13)
- `ns.loot`: `open`, `close`, `scan`, `search(text, instanceKey?, encounter?)`, `instances(text?)`; session-only data, no SavedVariables.
- LootDrop: `{itemID,item,instanceKey,instanceName,who,difficulty,provider,sourceID,kind}`; `item` references shared local item cache `{id,name,cached,info?}`.
- Grouped loot result: representative LootDrop fields plus EquipmentGroup fields and `suppliers[]={who,instanceName,provider,modes[],ids[],seenModes,seenIDs}`; unique dungeon-key/mob/provider entries with sorted combined difficulties/IDs. Full list stays in the scrollable detail pane; native hover shows up to six sources and prompts click for the remainder.
- Visibility: loot results and encounter choices require shared native `item.info.slot` to be recognized by `Rewards.lua`; unknown/unloaded items and non-equipment remain hidden. Item-cache events refresh eligibility.
- Instance record: `{key,name,count,instanceID?,subzones?}`. Atlas key = module/content; Questie fallback key = `area:<AreaTable ID>`. `subzones` is a set of localized names from provider SubAreaIDs. Dire Maul area 2557 maps to verified instance ID 429 when the provider omits it.
- Open captures session-only `focusTarget={name,subzone,id?,text?}` for a party instance. Match compatible exact native IDs first, localized name/subzone second; ties are not selected arbitrarily. Apply after catalogue completion (or immediately if ready), reset stale search/source and reveal the chosen navigation page; preserve shared equipment filters and explicit slash search. Manual search/location/source/reset/suspend cancels pending focus; dirty search fields also block focus before their debounce fires. Outside/unknown/raid locations retain browsing.
- Settings tab id remains `optional` for compatibility; displayed title is **Extra tools**. Standard tabs use width 72, Quick chat 100, Pings & items 108, Extra tools 96; fits the 660-wide settings window.
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
