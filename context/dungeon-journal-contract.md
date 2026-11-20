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
