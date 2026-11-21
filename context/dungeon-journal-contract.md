# Dungeon Journal look — stream contract (2026-11-20)

Plan (read it first): `/Users/cozzolif/.claude/plans/melodic-orbiting-kahn.md`. Screenshots of the target look:
`/tmp/dj_images/dj1.png` (home cards), `dj2.png` (quests page), `dj3.png` (bosses), `dj4.png` (map).
Also read `context/architecture.md` and the files you own.

## Hard rules
- **Inspiration only.** Do not open, copy or adapt code or media from `/tmp/dj_addon` (Dungeon Journal by Exehn,
  no licence). Use only the sizes, palette and client texture paths written in the plan and here.
- **Client textures only.** No new image files, and no `Interface\AddOns\ForeverDungeonJournal` path anywhere.
  Blizzard art by client path or FileDataID is fine.
- **Own only your files** (listed below). Never edit another stream's file; if you need something from it, use the
  API below. If it is missing, add a local fallback and report it in `notes`.
- Lua 5.1, WoW API calls wrapped in `pcall` / `U.call` as the existing code does; no globals except frame names.
- Tests: plain-script runner (see `tests/test_dungeon_quests.py` `__main__`), run with
  `/tmp/qs-test-env/bin/python tests/<file>.py`. Both client styles (`modern`, `classic`). Reuse the game helper
  `from test_dungeon_quests import game, filters, plain, HOVER_DATA, SEEKING`.
- Keep the existing features: chain nesting, ✓ / ! / gold border states, keyword colours, filters (Hide completed,
  Hide in my log), the route planner, item rewards, click-to-pin places.

## Files and owners
| Stream | Owns (edit only these) | Test file |
|---|---|---|
| A theme + home | `QuestSharing/JournalTheme.lua`, `QuestSharing/DungeonHomeUI.lua` | `tests/test_dungeon_journal_home.py` |
| B quests page + shell | `QuestSharing/DungeonQuests.lua`, `QuestSharing/JournalItems.lua` | `tests/test_dungeon_journal_quests.py` (+ keep `tests/test_dungeon_quests.py`, `tests/test_dungeon_route.py` passing; update their UI assertions) |
| D bosses & drops | `QuestSharing/Loot.lua` (only add `L.bossesOf`), `QuestSharing/DungeonBossesUI.lua` | `tests/test_dungeon_journal_bosses.py` |
| M map + route pages | `QuestSharing/DungeonMapUI.lua`, `QuestSharing/DungeonRouteUI.lua` | `tests/test_dungeon_journal_map.py` |

`QuestSharing.toc` already lists every file (stubs exist). Nobody edits the toc.

## API (stubs exist; owners replace the stub bodies, keep the signatures)

### `ns.journalTheme` (A, `JournalTheme.lua`)
- `T.C` palette roles: `frame, content, border, header, left, right, row, rowSelected, lootRow` = `{r,g,b,a}`;
  `title, text, muted` = `{r,g,b}` (default palette from the plan).
- `T.panel(frame, role, edge)`: `WHITE8X8` fill in `T.C[role]`, `Tooltips\UI-Tooltip-Border` edge (default 12),
  faint `QuestFrame\QuestBG` under it. Returns `frame`.
- `T.parchment(frame)`: full `QuestFrame\QuestBG` page (the quest detail look).
- `T.button(parent, label, width, onClick, tip)` → Button (dark, gold label, `UI-QuestTitleHighlight` hover).
- `T.tab(parent, label, icon, width, onClick)` → Button with `:SetSelected(bool)`.
- `T.pill(parent, kind, text)` → Frame; `kind` = `"xp"` (purple), `"money"`, `"rep"` (green). `:SetText(text)`.
- `T.crest(parent, faction, size)` → Texture (`UI-PVP-Alliance` / `UI-PVP-Horde`, cropped).
- `T.badge(parent, level, size)` → Frame (dark round disc + ring + number). `:SetLevel(n)`.
- `T.tick(parent, size)` → Texture (`ReadyCheck-Ready`).
- `T.round(texture, parent, size)`: masks a texture round (`TempPortraitAlphaMask`) with a gold ring.
- `T.cardArt(area)` → `file, l, r, t, b` (loading-screen path or FileDataID + crop) or nil, from the plan's table.
- `T.lfgIcon(area)` → path or nil (`Interface\LFGFrame\LFGIcon-<Dungeon>`).

### `ns.journalItems` (B, `JournalItems.lua`)
- `I.attach(button, itemIDOrFunc)`: on enter, `GameTooltip:SetOwner(button,"ANCHOR_RIGHT")`,
  `SetHyperlink("item:"..id)`, compare tooltips while Shift is held (`GameTooltip_ShowCompareItem`); on leave, hide
  both; click: CHATLINK (shift) → `HandleModifiedItemClick` / `ChatEdit_InsertLink`, ctrl → `DressUpItemLink`.
- `I.button(parent, width, height)` → Button with icon (38 px, crop .08–.92) + quality-coloured name + subtitle;
  `:SetItem(itemID, subtitle)` (uses `GetItemInfo`, icon fallback `INV_Misc_QuestionMark`); already `attach`ed.

### `ns.dungeonQuests` (B, `DungeonQuests.lua`) — additions
- `D.summaries()` → list of `{area, name, minLevel, maxLevel, total, open, done, alliance, horde}` for every
  dungeon with quests (after the scan; `{}` before). `open` = can take now and not done/in log.
- `D.openDungeon(area, tab)` (tab = `"quests"|"bosses"|"map"|"route"`, default `"quests"`), `D.home()`.
- `D.entranceOf(area)` → `{label, point={map,x,y}}` or nil (already local; export it).
- `D.routePlan(area, assumeAll, callback(result, doFirst, later))` (runs the planner as today) and
  `D.routeStepText(step)` (today's `stepText`), `D.minutes(seconds)`.
- `D.pinPlace(place)` (today's `pinPlace`).
- Page shell inside the Dungeon quests page frame: a home view and a dungeon view. The dungeon view has a
  header (name, LV, LFG icon, entrance-pin button), tabs Map / Bosses / Quests / Route (`T.tab`) and a content
  area of **1000 × 560** at TOPLEFT 16, -140 of the page frame. Each page module is built lazily into a child
  frame of that area.

### Page modules (each `build(parent, width, height)`, `show(area)`, `hide()`)
- `ns.dungeonHomeUI` (A, `DungeonHomeUI.lua`): `H.build(parent, width, height, onOpen)` builds the home
  (search box, crest filter buttons, the two hide check boxes are passed in by the shell, card grid). `onOpen(area)`
  is called when a card is clicked. `H.refresh(summaries)` repaints the cards.
- `ns.dungeonBossesUI` (D): `B.build(parent, w, h)`, `B.show(area, dungeonName)`, `B.hide()`.
- `ns.dungeonMapUI` (M): `M.build(parent, w, h)`, `M.show(area, dungeonName)`, `M.hide()`.
- `ns.dungeonRouteUI` (M): `R.build(parent, w, h)`, `R.show(area, dungeonName)`, `R.hide()`; uses `D.routePlan`,
  `D.routeStepText`, `D.minutes`, `D.pinPlace`.

### `ns.loot` (D, `Loot.lua`) — addition
- `L.bossesOf(dungeonName, done)`: async-safe. Returns `{ {name, npcID, displayID, level, items = {itemID, ...}}, ... }`
  in encounter order when the AtlasLoot or Questie loot index is ready; otherwise starts the existing scan and
  calls `done(list)` when it finishes. With no loot source it returns `{}` and `nil, "reason"`.

## Report (every builder)
`{files: [...], summary, tests: "N/M passed", notes}`. `notes` lists stubs you relied on and anything unverified.

## Integration follow-ups (from the stream reviews, 2026-11-20) — the integrate step fixes these
- M: `DungeonMapUI.lua` `showNoMap` hides every floor button through `hideAll`. One floor without art strands the
  user. Keep the floor buttons when `#state.floors > 1`, and hide only the tiles.
- M: `showNoMap` changes the pin label only through `SetLabel`. Use the same chain as the floor buttons
  (`SetLabel`, then `label:SetText`, then `SetText`).
- A: home search matches dungeon names only. Let it also match quest titles: give `D.summaries()` rows a `quests`
  list of titles (or add `H.setMatcher`), and make the home search use it.
- A: `T.tab` with `UIPanelButtonTemplate`: the icon may overlap the centred label on narrow tabs. Shift the font
  string right by the icon width.
- A/B: the shell must call `H.refresh(D.summaries())` after the scan, and anchor the two hide check boxes to
  `H._frame().bar`.
- D: in `Loot.lua`, when a background `bossesOf` scan is cancelled (`L.purge`, or a new `L.scan` generation),
  reset `background = false` and answer the pending `bossWaiters` with `({}, nil, note)`.
- D: `L.scan()` from `bossesOf` calls `E.dismissMenu()`. Skip that on background scans.
- D: when the scan finishes inside the first synchronous `step()`, return the flushed list from `bossesOf`.
- Not code (in-game checklist): the Hall of Thanes FileID 7963781, the LFGIcon names, the GoldRing path, the
  QuestBG and EJ crops, `GetFileIDFromPath` on Forever, the AtlasLoot `DisplayIDs` / `Level` fields, and the
  CLASSIC map table (uiMapIDs, folder names, floor counts), and the QuestieDB quest key `rewardMoney` used by the quest page money pill
  (if it does not exist, the pill never shows).

## Round 2 (2026-11-20): closer to the Dungeon Journal look + previews
Previews of the current state: `context/renders/{home,quests,bosses,map}.png` (made by `tools/render_journal.py`).
Same hard rules as above (inspiration only, client textures only, own only your files).

### Stream T: theme, home, bosses (owns `JournalTheme.lua`, `DungeonHomeUI.lua`, `DungeonBossesUI.lua`, tests `tests/test_dungeon_journal_home.py`, `tests/test_dungeon_journal_bosses.py`)
- Home grid fills the page width: columns = 2, card width = (page width - margins - gap) / 2 (about 488 px in 1000), art crop
  kept; still 126 px tall, 138 px rows.
- Home search box gets a clear button (`Interface\Buttons\UI-StopButton`), and is the ONLY search on the home page
  (the shell hides its own search there, see stream Q).
- New helpers (exact names): `T.glow(parent, size)` → ADD-blended `Interface\Cooldown\star4` behind a done tick, used on
  done cards; `T.classIcon(parent, size, classToken)` → `Interface\GLUES\CHARACTERCREATE\UI-CHARACTERCREATE-CLASSES`
  with `CLASS_ICON_TCOORDS[classToken]`; `T.dungeonIcon(parent, size)` → atlas "Dungeon" via SetAtlas, fallback
  `Interface\Icons\INV_Misc_Rune_01`; `T.chainIcon(parent, size)` → a client chain/link icon (verify the path exists in
  `/tmp/listfile/lf.csv`, e.g. an `Interface\Icons\*chain*` icon), with a fallback.
- Bosses: the EJ portrait lookup tries both spellings, with spaces (`UI-EJ-BOSS-Mutanus the Devourer`) and without
  (`UI-EJ-BOSS-EdwinVanCleef`); also the lower-case variants are irrelevant (paths are case-insensitive).

### Stream Q: shell + quests page + items (owns `DungeonQuests.lua`, `JournalItems.lua`, tests `tests/test_dungeon_journal_quests.py`, `tests/test_dungeon_quests.py`, `tests/test_dungeon_route.py`)
- Home view: hide the quest-only filter bar (search, Level, Quest levels, Class, Faction, My character, All quests) and
  the status line; keep Refresh data and the two hide check boxes; the home card search (stream T) drives the cards.
  `D.summaries()` respects Hide completed / Hide quests in my log and the faction crest filter where it makes sense.
- Quest rows: `T.classIcon` next to the crests for class-only quests; `T.dungeonIcon` when the quest is picked up
  inside the dungeon; `T.chainIcon` when the quest is part of a chain (tooltip lists the chain). Use nil guards: until
  stream T lands, skip the icon.
- Quest page: a class-only label ("WARRIOR / PALADIN ONLY" in the class colours, with class icons) when the quest has
  a class restriction; a **Share** button (green when the quest is in your log and shareable, grey otherwise, tooltip
  why) that calls the existing quest menu's share action; fix the status strip colour (it must use the badge tint, not
  white: colour × vertex).
- Items: clicking a reward or drop item that a boss of the current dungeon drops opens the Bosses tab with that boss
  selected (`ns.loot.bossesOf` + `ns.dungeonBossesUI.select(bossName)` if present, nil-guarded); the item tooltip gets
  a gold line "Drops from <boss>" when known.
- The 'Plan route' button on the Quests page opens the Route tab instead of the old window.

### Stream P (after both): previews (owns `tools/render_journal.py`, `context/renders/*`)
- Re-render home, quests (normal quest + a class quest + a done/chain quest), bosses (with an EJ portrait), map, route,
  into `context/renders/*.png`, and an `context/renders/index.html` gallery showing them side by side with the Dungeon
  Journal reference screenshots copied from `/tmp/dj_images` (reference only, labelled "reference: Dungeon Journal by
  Exehn", kept out of the addon folder).

### Round 2 follow-ups from the reviews (the previews/integration step fixes these code items)
- T: `DungeonBossesUI.lua` `B.show` done(): clear `view.want` when the name is not in the loaded list (no stale boss
  selection carried into another dungeon).
- T: home clear button: guard `Interface\Buttons\UI-StopButton` with `T.hasFile` and a fallback (a plain "x" label), so a
  missing texture never leaves an invisible button.
- Q: `homeFaction()`: on the home use only the home crest filter (`H._frame().faction`), never the hidden
  `filters.faction`.
- Q: clear `pendingOpen` on quest change, tab change and item OnLeave (no surprise jump to Bosses when a late boss list
  arrives).
- Q: repaint the Share button on `GROUP_ROSTER_UPDATE` / `QUEST_LOG_UPDATE` while a quest page is open.
- Q: clear `window.levelError` on `D.home()`, or word the home message so it says where to fix it.
- 2026-11-20: all six follow-ups above are in the code (checked: `B.show` clears `view.want`, `DungeonHomeUI.lua` "x" fallback,
  `homeFaction()` home crest only, `pendingOpen` cleared, `repaintShare` on both events, `D.home()` clears `levelError`).

### Round 2 result (2026-11-20, run r-20261120-111056-9c21, outcome "Round 2 done")
- Built and approved: streams T and Q, previews P, final review. Uncommitted. Mock harness + PIL renders only.
- Gallery: `context/renders/index.html` (renders home, quests, quests_class, quests_chain, bosses, map, route next to
  the Dungeon Journal reference shots in `context/renders/reference/`). Re-render: `/tmp/qs-test-env/bin/python
  tools/render_journal.py` (dumps), then `python3 tools/render_journal.py paint`.

### Round 2 in-game checklist (unverified)
- `Interface\Buttons\UI-StopButton` on Classic Era / Forever (else the "x" fallback shows).
- `Interface\Cooldown\star4` glow look (ADD, green tint) on done cards.
- `UI-CHARACTERCREATE-CLASSES` sheet + `CLASS_ICON_TCOORDS` on both clients.
- Atlas "Dungeon" (`SetAtlas` / `C_Texture.GetAtlasInfo`) on Classic Era; else the rune fallback.
- Chain icons `Spell_Frost_ChainsOfIce` / `INV_Misc_WartornScrap_Chain` (listfile only, not seen in game).
- EJ boss art name variants (spaces / no spaces / no punctuation) per dungeon; `GetFileIDFromPath` on Forever.
- Share button: green state and the share action with a real party; colour follows join/leave.
- Item click -> Bosses tab with the right boss; "Drops from" tooltip line.
- Home: card counts with the crest filter and hide boxes; no quest filters / second search visible.
- Plan route -> Route tab.

## Round 3 (2026-11-20): lore, user-story polish, previews
Previews of the current state: `context/renders/index.html`. Same hard rules (inspiration only, client textures only,
own only your files). Blizzard Encounter Journal text may be shipped (like Questie ships Blizzard quest text).

### Stream L: lore (owns `tools/build_dungeon_lore.py`, `QuestSharing/DungeonLore.lua`, `QuestSharing/DungeonBossesUI.lua`,
`QuestSharing/DungeonHomeUI.lua`, tests `tests/test_dungeon_lore.py`, `tests/test_dungeon_journal_bosses.py`, `tests/test_dungeon_journal_home.py`)
- `tools/build_dungeon_lore.py`: download `https://wago.tools/db2/{JournalInstance,JournalEncounter,JournalEncounterSection}/csv`
  (retail; the Forever build 1.60.1 has no journal tables) with curl (system python lacks SSL certs; CSVs already cached in
  /tmp/ejdata/*.csv), match our dungeons (names in `QuestSharing/DungeonQuestData.lua` `D.names`) and their bosses by
  name (normalised: lower case, no punctuation), and write `QuestSharing/DungeonLore.lua`: `L.dungeons[area] = {description}`,
  `L.bosses[normalised name] = {description, abilities = {{name, text, spellID}, ... at most 4, top-level sections only,
  text cut to ~140 chars, $-tokens and |cff codes removed}}`. Classic version of the dungeon wins when retail has a
  reworked one (prefer the instance whose encounter names match ours). Keep the file small (only our dungeons/bosses).
- API (stub exists): `L.dungeon(area, name)` → `{description}` or nil, `L.boss(name)` → `{description, abilities}` or nil.
- Bosses page right panel: under the boss name, the description (parchment-readable, 2–5 lines), "Abilities" with spell
  icon (`GetSpellTexture(spellID)` or `C_Spell.GetSpellTexture`, fallback `INV_Misc_QuestionMark`) + name + short text
  (hover = the full text), "Needed for" = quests of this dungeon that ask to kill this boss (match the boss npcID with quest
  objectives: `ns.dungeonQuests.questsForNpc(npcID)` — stream U adds it; nil-guarded), and a facts line (level, rare,
  number of drops). With no journal entry: facts and quests only, no empty headings.
- Home card hover: tooltip with the dungeon name, level range, quest counts and the journal description.

### Stream U: user-story polish (owns `QuestSharing/DungeonQuests.lua`, `QuestSharing/JournalItems.lua`,
`QuestSharing/JournalTheme.lua`, `QuestSharing/DungeonMapUI.lua`, `QuestSharing/DungeonRouteUI.lua`, tests
`tests/test_dungeon_journal_quests.py`, `tests/test_dungeon_quests.py`, `tests/test_dungeon_route.py`, `tests/test_dungeon_journal_map.py`)
- Walk these user stories on every page (read the code and `context/renders/*.png`) and fix what gets in the way:
  "I want every quest of this dungeon", "is this quest still worth taking", "which boss drops my upgrade",
  "where do I go next", "plan my route", "which floor is this boss on". List what you changed and why.
- Known items: (1) the quest filter bar on the dungeon page takes two rows: make it compact (one row, or a
  "Filters" toggle that shows the rest), keeping every filter reachable; (2) "Talk only" shows under objectives that
  need items: show the task kind only when it adds information; (3) the druid class icon reads dark at 16 px: give
  class icons a small class-coloured ring or background; (4) homeFaction() comment; (5) a test for clearing pendingOpen
  on a tab / dungeon change; (6) export `D.questsForNpc(npcID)` (quests of the open dungeon whose objectives kill that npc)
  for stream L; (7) show the dungeon journal description (`ns.dungeonLore.dungeon`, nil-guarded) as one muted line under
  the dungeon name in the header.

### Stream P (after L and U): previews (owns `tools/render_journal.py`, `context/renders/*`)
- Clip scroll children in the renderer; render home with search text (clear button visible) and the bosses page with a
  description and abilities; re-render all scenes and update `index.html`.

### Round 3 follow-ups from the reviews (the previews/integration step fixes these code items)
- U: the Filters popover covers part of the tabs and only the Filters button closes it. Close it on Escape and on a
  click outside (or move it below the tab row).
- U: `DungeonMapUI.lua` `M.refresh()` resets the chosen floor. Keep `state.floor` when `M.show` is called again for the
  same area.
- U: `D.openQuest` returns false for a quest hidden by the filters. Offer "All quests" (reset the filters, then open
  it) so a "Needed for" click from the Bosses page always lands on the quest.
- U: the "home" case of the pending-boss-click test reopens the dungeon before `BOSS_DONE()`. Fire `BOSS_DONE()` while
  still on the home and assert that no boss was selected.
- L: `DungeonBossesUI.lua` `B.neededFor` must pass the area: `questsForNpc(boss.npcID, view.area)`. Otherwise "Needed
  for" disappears when `filters.dungeon` is 0. Add a test that checks the area is passed.
- L: `tools/build_dungeon_lore.py`: Cookie reads "restoring of his health". Extend the orphan-word rule to
  `restoring|healing|increasing|reducing <tok>% of` → `<verb> part of`, regenerate, and extend the shipped-text test.
- L (optional): `fetch()` should download to a `.tmp` file and rename it only on success.
- All follow-ups above were fixed in the run (fix_l / fix_final rounds), checked in code 2026-11-20.

### Round 3 result (2026-11-20, run r-20261120-114959-1c34, outcome "Round 3 done")
- Streams L and U approved, lore after 1 fix round; final review approved after 2 fix rounds. Uncommitted. Mock harness + PIL renders only. Decision D15.
- `QuestSharing/DungeonLore.lua`: 19 dungeons, 123 bosses. Regenerate: `python3 tools/build_dungeon_lore.py` (cache /tmp/ejdata).
- Previews: `context/renders/{home,home_search,quests,quests_class,quests_chain,bosses,map,route}.png`, gallery `index.html`.

### Round 3 in-game checklist (unverified)
- Ability icons: `GetSpellTexture` / `C_Spell.GetSpellTexture` for retail spellIDs on Forever, and the stored FileDataID `icon`; else `INV_Misc_QuestionMark`.
- Lore text fits the classic dungeon: retail descriptions describe reworked versions (Shadowfang Keep names Lord Godfrey). Read each dungeon description once.
- Boss name matches: hand-mapped group encounters (The Lost Dwarves -> Baelog/Olaf/Eric, Nekrum & Sezz'ziz, Wardens of the Dream, ...) show text on the right boss.
- "Needed for" lists every kill quest (only quests of the current scan are counted) and a click lands on the quest, also with filters on.
- Filters popover: does not hide tabs while in use; Esc and click outside close it; "Filters (N)" count right.
- Home card tooltip and header lore line: length and readability on parchment / dark header.
- Class icon ring (class-coloured square 1 px around 16 px icon) readable for druid.
- Map keeps the picked floor after a refresh.

## Bosses fix (2026-11-20)
Run `r-20261120-194708-fb95`. Goal: the Bosses tab lists only the **official** bosses of the dungeon in fight order,
with real portraits where the client has them, on a calm page. Three builder streams with disjoint files: D (data), L (logic), U (ui).
Research inputs (read-only, never shipped): `/tmp/bossdata/bosses.json` (R1), `/tmp/bossdata/portraits/{coverage.json,ej_presence.json,casc.json,wowhead_display.py}` (R2),
`/tmp/ejdata/f_CreatureDisplayInfo.csv` (Forever display validator), renders `/tmp/bossdata/out/noatlas_*.png` and `/tmp/dj_images/dj3.png` (R3).

### Hard rules (restated, apply to every stream)
- **Dungeon Journal is inspiration only.** Do not open, copy or adapt code, data tables (its npc->display IDs) or media from `/tmp/dj_addon`.
  Only the measurements and methods written here.
- **Client textures only.** No new image files, no `Interface\AddOns\...` paths. Blizzard art by client path or FileDataID.
- **Lua 5.1** (no `goto`, no `//`, no integer ops, no `bit32`); WoW API calls wrapped in `pcall` / `U.call` as the code does; no new globals.
- **Downloads with `curl`** (system python lacks SSL certs), cached under `/tmp/bossdata/`; generators run with `python3 -I`.
- **Tests are plain scripts** (`__main__` runner, both styles `modern` + `classic`), run with `/tmp/qs-test-env/bin/python tests/<file>.py`.
- Own only your files. Nobody edits `QuestSharing.toc` (`DungeonBossData.lua` is already listed at :57, after `Loot.lua`), `tools/render_journal.py`,
  `context/renders/*`, `DungeonQuests.lua`, `JournalItems.lua`, `DungeonLore.lua`, or any `context/*.md` except this contract (read-only for builders).

### Files and owners
| Stream | Owns (edit only these) | Must not touch |
|---|---|---|
| D data | `tools/build_boss_data.py` (new), `QuestSharing/DungeonBossData.lua` (replace the stub), `tests/test_dungeon_boss_data.py` (new) | `Loot.lua`, `DungeonBossesUI.lua`, `JournalTheme.lua`, any other test |
| L logic | `QuestSharing/Loot.lua` (only `L.bossesOf`, `atlasBosses`, `questieBosses`, `flushBosses`, `cancelBosses` and new local helpers next to them), new test functions appended to `tests/test_dungeon_journal_bosses.py` | `L.scan`, `bosses()` (:179, loot browser), the loot browser UI, `DungeonBossesUI.lua`, the page/UI tests in that file (from `test_page_rows_portrait_chain_and_badges` on) |
| U ui | `QuestSharing/DungeonBossesUI.lua`, `T.round` and `T.badge` in `QuestSharing/JournalTheme.lua` (nothing else in that file), `tests/test_dungeon_journal_bosses_ui.py` (new) | `Loot.lua`, `DungeonBossData.lua`, `T.C`, `T.panel`, other theme functions, `tests/test_dungeon_journal_bosses.py`, `tests/test_dungeon_journal_home.py` |

Streams run in parallel, so each stream's tests **mock the other streams' output** (L injects `NS.dungeonBossData.bosses[area]`; U replaces
`NS.loot.bossesOf` with a stub that returns official-shaped rows). No stream's tests may depend on another stream's unfinished code.

### Shared data shape (the API between the streams)
`ns.dungeonBossData` (D writes, L and U read):
- `B.bosses[area] = { boss, ... }` keyed by our area ID (the `D.names` keys: 209, 491, 717, 718, 719, 721, 722, 796, 1176, 1337, 1477, 1581, 1583, 1584,
  2017, 2057, 2100, 2437, 2557, 16544, 16550, 16554, 16611, 16620, 16667, 16732, 16842, 16919), array in fight order (`order` 1..n).
- `B.list(area)` -> that array, or `nil` when the area is unknown (keep the stub signature; `tonumber(area)`).
- boss fields (absent when unknown, never `false`):
  - `name` (string, the official encounter name, e.g. `"The Seven"`), `order` (1-based), `encounterID` (number)
  - `npcID` (= `npcIDs[1]`), `npcIDs` (best first), `altNpcIDs` (demoted same-name candidates), `npcName` (QuestieDB name when it differs, e.g. `"Gelihast"`)
  - `lootNpcIDs` (npcs whose drops belong to this boss; hand table in the generator, at least Sneed 643 -> `{642}` Sneed's Shredder)
  - `group = true` + `members = {"Baelog","Olaf",...}` for group encounters (The Lost Dwarves, Ring of Law, The Seven, The Vault)
  - `optional = true` when R1's `flags` lacks bit 1024 (e.g. Highland Horror)
  - `ejFile` (number, FileDataID of `interface/encounterjournal/ui-ej-boss-*.blp`), `displayID` (number, validated)

Row shape returned by `ns.loot.bossesOf` (L writes, U and `DungeonQuests.dropsIndex` read): every official boss field above copied through, plus
`official = true`, `items = {itemID, ...}` (unique; may be empty), `level` (number or nil). Legacy rows (no official list) keep today's shape
`{name, npcID, displayID, level, items}` without `official`.

### Stream D: data (`tools/build_boss_data.py` -> `QuestSharing/DungeonBossData.lua`)
- Inputs: `--bosses /tmp/bossdata/bosses.json` (R1, default), `--coverage /tmp/bossdata/portraits/coverage.json`, `--present /tmp/bossdata/portraits/ej_presence.json`,
  `--displays /tmp/ejdata/f_CreatureDisplayInfo.csv`, `--cache /tmp/bossdata/wowhead/`. Flags `--offline` (cache only, no network) and `--out` (default the Lua file).
- Per boss: copy `name, order, encounterID, npcIDs, altNpcIDs, npcName, group, members`; `npcID = npcIDs[1]`; `optional = true` when R1 has `flags`; add `lootNpcIDs` from a
  hand table in the script (`LOOT_NPCS = {643: [642]}`; add others only with evidence, one comment each). Drop R1's `match` field.
- `ejFile`: the coverage record's `creatures[0].fdid` or `ejFileByName.fdid`, only if the key `"<area>:<name>"` is in `ej_presence.json` `present`,
  only for classic areas (`area < 16000`), and never for the known false positives (`16544:Mana Devourer`, `16611:The Butcher`, enforced by a
  `NO_EJ` set even though the area rule already covers them). Retail-version art (Baron Rivendare, Gahz'rilla) is accepted; list them in a comment.
- `displayID`, first hit wins, then validated (must be an `ID` in `f_CreatureDisplayInfo.csv`, else dropped and counted):
  1. coverage `creatures[*].displayID` with `displayInForever == true` whose `name` matches the boss (or a member for groups);
  2. Wowhead **classic** page for `npcID < 200000`: `curl -sSL -A Mozilla/5.0 https://www.wowhead.com/classic/npc=<id>`, parse
     `data-mv-display-id="N"` (fallback `displayId = N`), cache the raw HTML in `--cache/<id>.html`, sleep >= 1 s between requests, retry 3x with backoff.
     Never request `/forever/` database pages (WAF-blocked). With `--offline`, use the cache only.
  Forever-only bosses (`npcID >= 200000`) get no displayID in this round (in-game resolver is a follow-up, below).
- Lua output: header comment (source build 1.60.1.70959, generator command, date), then `B.bosses = { [1581] = { -- The Deadmines` with one boss per line,
  keys in the fixed order above, strings `%q`-escaped, areas sorted, deterministic (re-running gives a byte-identical file). Keep `B.list`. No other API.
  Size target < 60 KB. Print a summary: bosses, with npcID, with ejFile, with displayID, rejected displayIDs.
- `tests/test_dungeon_boss_data.py` (reads the generated file; no network): the file loads in the harness (`from test_loot import game`, `NS.dungeonBossData.list(1581)`);
  28 areas and 241 bosses; Deadmines names in order `Rhahk'Zor, Sneed, Miner Johnson, Gilnid, Captain Greenskin, Mr. Smite, Cookie, Edwin VanCleef`;
  `order` is 1..n per area; Sneed has `lootNpcIDs` with 642; The Lost Dwarves is `group` with 3 members; every `npcID == npcIDs[1]`; no `ejFile` in areas
  >= 16000; every `displayID` is in `f_CreatureDisplayInfo.csv` (skip that check when the CSV is missing); no `AddOns` path and no `false` values;
  the generator with `--offline --out <tmp>` reproduces the shipped file byte for byte (skip when `/tmp/bossdata/bosses.json` is missing).

### Stream L: logic (`QuestSharing/Loot.lua`)
**Rule (R4):** when `area` is given and `ns.dungeonBossData.list(area)` is a non-empty table, the official list is the **only** source of rows, in its order;
drop sources only attach items. Every drop row that matches no official boss is dropped (trash, rares not in the list, helpers, chests, event NPCs).
Without `area`, or with no official list, `L.bossesOf` behaves exactly as today (legacy path; the existing name-only tests stay green).
- New local `officialRows(area, raw)` -> array: for each official boss in order, a new table with all boss fields copied, `official = true`, `items = {}`.
  `ids = npcIDs ∪ altNpcIDs ∪ lootNpcIDs`; `names = plainName` of `name`, `npcName` and each of `members`. For each raw row (in raw order), assign it to the
  **first** official boss (by order) where any of `raw.npcIDs or {raw.npcID}` is in `ids`, else where `plainName(raw.name)` is in `names`; each raw row joins
  at most one boss. Merge its items unique, keeping the first-seen order (AtlasLoot) — then `table.sort` only on the QuestieDB path, as today.
  `displayID = boss.displayID or raw.displayID`; `level = raw.level or bossLevel(field("npc", boss.npcID, "maxLevel"))` (guard `boss.npcID == nil`).
  Bosses with no match keep `items = {}` and stay in the list (Sneed shows; his drops come from 642).
- `atlasBosses`: additionally store `npcIDs` = every positive number in `boss.npcID` (number or nested table) so `{3865,3864}` matches; keep `npcID` as today.
  Iterate `content.items` with `pairs` over `1..table.maxn` (or a numeric for to `table.maxn`) instead of `ipairs`, so the `isForever and {...} or nil` holes do not cut the list.
- One exit helper `finish(area, list, src, reason)` used by **every** reply path of `L.bossesOf`, by `flushBosses` and by `cancelBosses`: if the official list
  exists, `list = officialRows(area, list or {})`; reason becomes nil when at least one row exists, except keep the cancel / no-source / no-table reason
  as-is so the page can show it. AtlasLoot "no table" (`list == false`) with an official list: reply the official rows with empty items, source `"AtlasLoot"`, reason
  `"AtlasLoot has no table for <name>."`. No loot source at all (`L.scan()` fails): reply the official rows with empty items, source `nil`, the scan note as reason.
  `done` is still called exactly once; the synchronous return values equal what `done` got.
- `questieBosses` keeps building its raw rows from the index (`kind == "npc"`, `sourceID "npc:<id>"`); add `npcIDs = {npcID}`; the level sort stays for the legacy path only.
- New tests appended to `tests/test_dungeon_journal_bosses.py` (names start with `test_official_`; inject the list with
  `g.run("NS.dungeonBossData.bosses[1581]={{name='Rhahk''Zor',order=1,npcID=644,npcIDs={644}},{name='Edwin VanCleef',order=2,npcID=639,npcIDs={639}}, ...}")`):
  official order wins over AtlasLoot order; trash/ExtraList/Chest/unknown rows are dropped; a boss with no drops is kept with `items == {}`; `lootNpcIDs`
  moves the Shredder's items to Sneed; match by `npcName`/`members` when ids differ; a raw row joins only one boss; AtlasLoot `npcID={3865,3864}` matches by the
  second id; QuestieDB path (`quest_game` + `QUESTIE`, boss `npcIDs={900}` in 1581) attaches item 951 and drops every other npc; "no table" and "no source" still return the
  official rows with their reason; name-only calls (no area) give the legacy answer; an area with no official list gives the legacy answer; a nil hole in
  `content.items` no longer cuts the list; `DungeonQuests.dropsIndex` still maps an item to the official boss name.
- L may update the existing **bossesOf** tests (before `test_page_rows_portrait_chain_and_badges`) only where the rule changes the expected answer
  (e.g. `test_atlas_matches_by_area_and_reports_unknown_dungeons` with area 718); list every changed assertion in `notes`.

### Stream U: ui (`QuestSharing/DungeonBossesUI.lua`, `T.round` / `T.badge`)
**Portrait chain (R2)**, `B.portrait(texture, boss, area)` returns the source string:
1. `"journal"`: `boss.ejFile` (FileDataID) -> `texture:SetTexture(boss.ejFile)`, texcoord `.25,.75,0,1`. Else, **only when `tonumber(area) < 16000`**, today's
   `GetFileIDFromPath` lookup over `B.journalNames(boss.name)` (and `boss.npcName`). Never by name in the Forever-only areas (false positives).
2. `"display"`: `boss.displayID` and `SetPortraitTextureFromCreatureDisplayID` exist -> **off-screen staging**, never on a visible texture:
   - one holding frame `W.stage` parented to `UIParent`, `SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 10000, 0)`, 64x64, shown;
   - render into a stage texture, wait `PORTRAIT_WAIT = 3` s (`ns.after`), then move it to the host: `SetParent(host frame)`, copy points/size, draw layer,
     texcoords, vertex colour; the host's own texture stays hidden while the staged one is attached. Until it arrives the host shows the placeholder (step 3 look).
   - cache by displayID, at most `MAX_LIVE = 24` live portrait textures, least-recently-used eviction of ones not on a shown row (`SetTexture(nil)`, reuse the object);
     release every live portrait (`SetTexture(nil)`) on `B.hide()`, on `B.show` of a different area, and on `PLAYER_LEAVING_WORLD` (`ns.on`).
   - a stale timer (row reused for another boss, page hidden, token changed) does nothing.
   - No mask is added to display portraits (the API already draws a round portrait).
3. `"skull"`: the muted placeholder: a dark disc behind the slot (`TempPortraitAlphaMask` tinted `.055,.047,.04,1`, always present as `portrait.back`), the skull
   texture on top with vertex colour `.55,.50,.45` and alpha `.6`. Never a full-bright skull.
Keep `texture.source`, `texture.journalPath` (by-name hit) and add `texture.ejFile` for tests.

**List (R3 calm spec):**
- Rows: `ROW_W, ROW_H, ROW_GAP = 314, 52, 8` (pitch 60), x inset 10, first row at y 44. `rowCount = floor((height-50)/60)` (8 at 560).
- No `T().panel(b, "row")` on boss rows or loot rows (no tooltip edge, no parchment). Flat fill `(.145,.094,.043,1)` on BACKGROUND, 1px top line `(.35,.24,.11,.6)`,
  1px bottom line `(0,0,0,.5)`. Selected: fill `(.34,.23,.11,1)` and a 1px outline `(.80,.57,.21,.8)` (four 1px textures, shown with `b.sel`). Hover: the existing
  `UI-QuestTitleHighlight` ADD highlight at alpha `.35`.
- Portrait 44px at `LEFT(+5,0)`, `T.round(t, b, 44, {ring = false})` (mask only). Name at x 62, Friz 12 (`T.font`), single line (no word wrap), width `ROW_W-72`,
  colour `(.82,.75,.60)`, selected `(.95,.75,.32)`.
- Badge: `T.badge(b, level, 24, {flat = true, font = 11})`, `CENTER` on the portrait's `BOTTOMLEFT` at `(+9,+3)` (hangs about 5px below the row; must stay above the next row).
- Left panel: `W.left.jPage` alpha `.05` or hidden (no other change to the panel). Footer `W.leftStatus` only when `#bosses > rowCount` (BRD, Strat, DM), muted, `"1-8 of 21"`
  (no "(mouse wheel)"). Deadmines (8 bosses) shows no footer.
- `group` rows: name as is; tooltip on hover lists `members` (one line each). `optional` rows: append ` (optional)` in muted text to the facts line, not the row name.

**Right side:**
- Header: portrait 68px at `(16,14)`, no ring; badge `T.badge(W.right, nil, 30, {flat = true, font = 13})`, `CENTER` on the portrait `BOTTOMLEFT` `(+7,+3)`.
  Name Friz 16, cream `(.93,.84,.66)`, TOPLEFT `(100, 30)`; facts Friz 10 muted TOPLEFT `(100, 54)`. `DESC_Y` stays 96.
- `W.right.jPage` alpha `.05` or hidden. Loot rows `LOOT_W, LOOT_H, LOOT_GAP = 384, 50, 9` (pitch 59), the same flat slot style as boss rows (no panel edge).
- `B.facts(boss)`: for `boss.official` rows, no QuestieDB rank (fixes "Rare Elite" on VanCleef): `"Level 21 · 10 drops"`; legacy rows keep today's rank logic.
- Notes: the drop counter `"1-7 of 54 drops"` only when items overflow (no "(mouse wheel)"); the AtlasLoot hint `"Install AtlasLoot for full drops."` at most once,
  muted, on its own line, only when `view.source ~= "AtlasLoot"`, never joined to a counter. A boss with no drops: status `"No drops listed for <name>."` (as today).
- One accent gold everywhere: `(.80,.57,.21)` rings and selection, `(.95,.75,.32)` selected text. No `MiniMap-TrackingBorder`, no `GoldRing` on this page.
- Keep the public API and test handles: `B.build/show/select/hide/refresh/scroll/scrollLoot/portrait/journalNames/facts/lore/neededFor/paintLore`, `W.rows`,
  `row.portrait/.badge/.name/.sel/.boss`, `W.portrait/.badge/.name/.facts/.status/.note/.leftStatus/.loot`. `B.neededFor` may try every id in `boss.npcIDs`.

**Theme (`JournalTheme.lua`, only these two functions, backward compatible):**
- `T.round(texture, parent, size, opts)`: `opts.ring == false` skips the GoldRing (`texture.jRing` stays nil). Default unchanged (DungeonQuests keeps its ring).
- `T.badge(parent, level, size, opts)`: `opts.flat` builds `f.ring` = `TempPortraitAlphaMask` disc `size+2` tinted `(.80,.57,.21,1)` behind `f.disc` (`size`, `(.055,.047,.04,1)`),
  both `CENTER`; number white `(1,1,1)` with `T.font(f.text, opts.font or 11)`, centered. Without `opts` the badge is unchanged (home test asserts `MiniMap-TrackingBorder`).
- `tests/test_dungeon_journal_bosses_ui.py` (new; may import helpers from `test_dungeon_journal_bosses` read-only; stub `NS.loot.bossesOf` to return official rows):
  geometry (row 314x52, pitch 60, portrait 44 at +5, name x 62, header 68 at (16,14), loot 384x50 pitch 59); no `jEdge`/`jPage` on boss and loot rows; no GoldRing on the
  page; badge flat look (24/30, ring size+2, white text) and its anchor; chain order ejFile -> by-name (classic area only) -> staged display -> muted skull;
  a by-name hit is ignored in area 16611; staged display: host not set before 3 s, moved after, `MAX_LIVE` cap and LRU, release on hide / area change /
  `PLAYER_LEAVING_WORLD`, stale timer ignored; official facts without rank; footer only on overflow; AtlasLoot hint once; group tooltip lists members;
  `T.round` and `T.badge` defaults unchanged. Also keep `tests/test_dungeon_journal_home.py` and `tests/test_dungeon_journal_quests.py` green.

### Known overlap (for the integrate step, not the builders)
- The page/UI tests in `tests/test_dungeon_journal_bosses.py` (from `test_page_rows_portrait_chain_and_badges` on) use `page(g)` with area 1581 and will see the
  real official Deadmines list (D) and the new geometry (U), so some fail by design (row list `Edwin, Cookie, Chest`, sizes 315x55, `"Elite"` in facts,
  the joined note text). Each stream lists the failures it sees in `notes`; the integrate step updates those assertions (or removes the ones superseded by
  `test_dungeon_journal_bosses_ui.py`). Builders do not edit them.
- `DungeonQuests.dropsIndex` (:1452) needs no change: it already passes `area`; trash-only items lose their boss (correct).

### Verify (each stream before reporting)
- D: `python3 -I tools/build_boss_data.py` (online once), then `--offline`; `/tmp/qs-test-env/bin/python tests/test_dungeon_boss_data.py`.
- L: `/tmp/qs-test-env/bin/python tests/test_dungeon_journal_bosses.py` (all `test_official_*` and the bossesOf tests pass), `tests/test_loot.py`, `tests/test_dungeon_quests.py`.
- U: `/tmp/qs-test-env/bin/python tests/test_dungeon_journal_bosses_ui.py`, `tests/test_dungeon_journal_home.py`, `tests/test_dungeon_journal_quests.py`.
- All: `luac -p` (5.1) on the Lua files you changed if available; `git diff --stat` shows only your files.

### Follow-ups (out of scope this round)
- In-game display resolver for Forever-only bosses (hidden PlayerModel `SetCreature(npcID)` -> `GetDisplayInfo()`, one at a time, not during loading screens),
  dumped once and baked into `DungeonBossData.lua` by the generator. Until then those bosses show the muted placeholder.
- No npc for Ezra Grimm (enc 2797), The Butcher (3355), Infurnus (3495); `Overseer Mugg -> Overlord Mugg 258968` is a fuzzy guess; Sunken Temple uses the official
  OrderIndex order, not the walking order.
- In-game check: `SetTexture(fdid)` for the EJ art on Forever, staged display portraits never flash a black square, badge readability at 24px.
- 2026-11-21 (run r-20261121-041134-dd71): resolver built (`QuestSharing/BossPortraitResolver.lua`, see section below). Ezra Grimm now npc 11058 / display 10475 (Wowhead Forever search suggestions). The Butcher and Infurnus still have no npc (no exact Wowhead match) and keep the skull.

## Forever boss portraits (2026-11-21, run r-20261121-041134-dd71, outcome "Forever portraits done")
- Result: reviews approved; uncommitted; mock harness + render `context/renders/bosses_forever.png` only (render_journal.py `FOREVER_MODEL` mock, made-up display IDs). Decision D16. Tests: test_boss_portrait_resolver 42/42, test_dungeon_journal_bosses 88/88, test_dungeon_journal_bosses_ui 34/34, test_dungeon_boss_data 20/20.
- Open low notes from the final review: no regression test for "No matching quests" hidden outside the Quests tab (`DungeonQuests.lua` applyView, `window.tab == "quests"`).

### Forever boss portraits: in-game checklist (unverified)
- Open a Forever dungeon's Bosses page (e.g. The Hall of Thanes), wait a few seconds: portraits replace the muted skulls row by row (The Butcher and Infurnus keep the skull).
- Two different uncached Forever bosses in a row get different portraits (no stale display of the previous creature).
- The hidden 1x1 alpha-0 PlayerModel on UIParent loads creatures and fires OnModelLoaded on the Forever client (also after Alt+Z).
- No lookups in combat or during a loading screen; no stutter while the page fills.
- Run `/qs bossdump` and send the printed `npcID=displayID` lines (and the "not found" line) so they can be baked into `tools/build_boss_data.py` / `DungeonBossData.lua`.

### Bosses fix: follow-ups from the reviews (the integrate step fixes these)
- L: `officialRows` (Loot.lua about lines 797-805): take `displayID` and `level` only from raw rows matched by
  `npcIDs`, `altNpcIDs` or name, never from rows matched only by `lootNpcIDs` (Sneed must not get the Shredder's
  level or model). Otherwise fall back to `bossLevel(maxLevel of boss.npcID)`. Add a test.
- D: `tools/build_boss_data.py` ejFile: prefer `ejFileByName` when the stem of the `creatures[0]` file matches
  neither the boss name nor the creature name. Gahz'rilla must use `ui-ej-boss-gahzrilla` (607604), not
  `ui-ej-boss-ghazan`; Magistrate Barthilas must use 607704, not The Ravenian's 607791. Regenerate offline, then
  check that both are fixed. Also skip the sleep after the last failed Wowhead attempt.
