# Changelog

## 0.4.10
- Added opt-in **Auto-update spells to highest learned rank** under **Extra tools**, plus **Check spell ranks
  now**. Updates lower-ranked player spell buttons on normal action-bar pages, including duplicate buttons
  and hidden/form pages, using ranks actually learned in your spell book.
- Checks on enable, login, learned-spell changes and placed actions. Numeric rank comparison handles ranks
  above 9 and localized rank labels; passive, unlearned, off-spec and ambiguous spells are excluded.
- Waits during combat, temporary/vehicle bars or cursor dragging, then resumes when ready. Macros, items,
  empty slots, pet actions and unranked abilities remain unchanged; this does not buy or train spells.
- Confirms cursor contents and replacement before continuing. Unsupported client APIs explain the limitation;
  a refused/unconfirmed replacement pauses updates until reload rather than repeatedly changing buttons.

## 0.4.9
- Opening **Instance drops** inside a recognized dungeon automatically selects that dungeon and brings its
  navigation row into view. Works on first load and reopening, including a catalogue loaded in batches.
- Clears stale item/dungeon searches and encounter selection when focusing; an explicit `/qs loot [search]`
  keeps its search inside the current dungeon. Shared type, level and stat filters remain in effect.
- Uses native instance IDs, exact localized names and provider subarea names for dungeon wings. Unknown,
  ambiguous, raid and outdoor locations preserve browsing. Manual navigation remains in control after opening.
- Renamed the **Optional** settings tab to **Extra tools**, with tab widths adjusted to keep every label inside
  the settings window. Existing actions, settings and internal tab identifiers remain compatible.

## 0.4.8
- Added three shared **stat filters** to quest rewards and instance drops, each with a searchable bonus selector
  and an inclusive minimum. Combine conditions such as Intellect ≥ 10 and Stamina ≥ 5; every selected condition
  must match. Blank minimum means 1, Any stat removes a condition, and Clear filters resets all three.
- Includes primary attributes, armor, health/mana, attack/spell bonuses, healing, mana regeneration,
  combat ratings and resistances. Uses client-reported bonuses; ratings are points, not percentages.
  Unreported bonuses, procs and missing data do not match; clients without a stat API show an explanation.
- Filters update while typing, survive tab changes and refresh when item data arrives. The stat row stays
  inside the existing explorer; Rare+ quality, class/faction eligibility and Classic/Forever dungeon scope remain.

## 0.4.7
- Replaced click-through filter controls with **searchable dropdowns**: choose equipment, item type, slot,
  level measure, class, faction and dungeon source directly. A single reusable popup supports scrolling,
  keyboard arrows/Enter, and Escape to dismiss.
- **Live search** updates quest, item and dungeon lists while typing; Clear buttons and Escape clear the text.
  Level bounds and character level also update without Enter. **My level** sets an inclusive required-level cap.
- Browse result and dungeon lists with the **mouse wheel**; use Up/Down in the result search field to select
  items and cross pages. Previous/Next remain available and fade/disable at list boundaries.
- **Sort** either tab by highest item level, lowest required level, or name. Details appear automatically for the
  first visible item, and your selected item stays selected across data refreshes when it is still visible.
- **Clear filters** now also clears the active tab's searches and dungeon/source selection. On the quest tab it
  broadens quest levels, keeps completed quests hidden, and preserves class/faction/character level.
- Clearer loading/empty messages, brighter item-name colors, selection highlighting and difficulty labels make
  results easier to read. Map directions explicitly tell you to open M. Rare+ and dungeon scope remain enforced.

## 0.4.6
- Both equipment tabs now show only **Rare (blue) quality and above**. Green, white and grey items are excluded
  from quest rewards, dungeon results and source choices, including the partial QuestieDB fallback.
- This minimum remains in effect after Reset filters. Items with unknown quality stay hidden until the game
  supplies their details; normal item-cache updates then show eligible equipment automatically.

## 0.4.5
- Quest rewards and dungeon drops now share one **Equipment explorer** window with tabs, item icons,
  quality colors, highlighted selection and an inline route/source panel. Selecting an item or changing tabs
  reuses this window; closing it or leaving a tab cancels that tab's unfinished work.
- Both tabs share equipment category, item type and slot filters, plus an inclusive minimum/maximum level
  range. Choose **Required level** or **Item level**; blank bounds are unrestricted. Invalid ranges keep the
  previous valid filter and explain the error. Right-click a choice to cycle backwards; Reset filters clears it.
- Dungeon equipment includes **Classic and Forever dungeons**, as requested, and excludes raids, world bosses
  and unidentified encounter tables. Uses AtlasLoot's dungeon category with known dungeon identities for older
  catalogues and the partial QuestieDB fallback. Dire Maul wings without InstanceID remain included.

## 0.4.4
- In a quest's right-click menu, **Seek fellow adventurers** now appears directly after
  **Tell the party how I am doing**, before **Offer it to the party**. Selecting it opens the invitation
  composer for that quest.

## 0.4.3
- Instance drop search now shows only weapons and wearable equipment, including armor, shields, rings,
  necklaces, trinkets and offhands. Materials, consumables, bags and other non-equipment are excluded.
- Applies to both AtlasLoot and the partial QuestieDB fallback; source choices omit encounters with no known
  equipment. Items remain hidden until the game supplies a recognized equipment slot, then appear automatically.

## 0.4.2
- **Instance drops** GUI (*Settings > Optional*, the quest reward browser's **Instance drops** button, or
  `/qs loot [search]`): browse instances, search item names/IDs and bosses, and see the encounter or creature that
  supplies each item. Includes encounter filtering, pagination, item tooltips/comparisons and source details.
- Reads compatible installed **AtlasLoot** DungeonsAndRaids encounter tables, including available difficulty
  variants, trash and chest groups. Without those tables, **QuestieDB** supplies clearly labelled partial sources
  for creatures/objects known to be inside instances. Coverage follows the installed catalogue; no drop rates
  or missing dungeon data are invented.
- Data is indexed only on request, in batches; item names load in small batches and update as the game supplies
  them. Closing the window or disabling the addon cancels unfinished work. Quest map symbols remain removed.

## 0.4.1
- Removed Quest Sharing's quest-objective and turn-in symbols from the world map and minimap, including their
  renderer, setting and background refresh; old enabled settings are discarded on load.
- **Seek fellow adventurers**: a role-play quest invitation from a quest's right-click menu, *Settings > Optional*,
  or `/qs adventure [quest ID or exact title]`. Choose an unfinished quest, cycle through three wordings and edit
  the preview. It includes a quest link and the current zone when the quest is in that area.
- Choose the current chat, say/yell, party/raid, guild/officer, instance, a whisper recipient, or any joined channel
  by number/name. **Prepare chat** fills the chat box; press Enter to send, including when other features send
  immediately. Existing drafts are preserved; switching channels with an unfinished draft asks you to clear it first.
- Invitations respect the 255-byte chat limit and never recruit for completed or abandoned quests.

## 0.4.0
- **Optional** settings tab: both new tools start switched off.
- **Fishing waters** (`/qs fishing`): add, edit and delete a marker for each body of water, with map coordinates,
  minimum and no-getaway fishing skill, fish and notes. Markers appear on the big world map when enabled.
  Alt-clicking a water starts a new marker there on clients with normalized map cursor support. Notes
  survive logout/reload and settings resets. Unknown skills stay unknown. Optional **AnglerAtlas** adds a separate
  zone summary; provisional Forever data stays labelled. Individual water records are entered by the user;
  this release does not include a verified catalogue of every lake and river.
- **Quest reward equipment** (`/qs rewards`): browse QuestieDB item rewards by class, character level, faction,
  equipment slot and item/quest/zone search. Starts with your character, hides completed quests where the game
  reports completion, and sorts by item level. Hover for the game's equipment comparison; click for the quest
  giver, coordinates and prerequisites. Classic equipment families narrow class results; check item tooltips for
  item-specific restrictions and build suitability. Requires a recent QuestieDB item catalogue and enum tables.
- Catalogue scanning happens only on request, in small batches; disabling it cancels pending work. Full-width
  Forever race masks are respected. The new tools never open/redraw the game's protected world map.

## 0.3.9
- **Quest items marked in your bags** (*Settings > Pings & items*, `/qs bagmarks`, on by default): gold for a quest
  of the zone you are in, blue for one of your quests elsewhere (the bank can keep it), so you only carry what this
  zone needs. The tooltip says which quest and where. Matched by objective names, the bag's quest info and (with
  QuestieDB) the exact items a quest asks for, hands out or needs. The game's bags and the bank's main slots.
- **Hide the game's quest tracker** (*Settings > Tracker*, `/qs hidetracker`, off by default): outside fights (the
  game does not allow it during one, so it happens right after), and again whenever the game shows it.
- **How to do it** (right click a quest in the Party quests window; with QuestieDB): one chat line with what is still
  open and where - the spot nearest to you for each creature to kill, who or what drops each item, objects to use,
  places to go - then where to turn it in. Objectives the game already counts as done are left out; a finished quest
  says only where to turn it in. Always one chat message. In a party to the party, alone only to you.
- **A light quest map** on the world map and the minimap (*Settings > Tracker > Quest map*, `/qs questmap`): small
  icons where your quests' open objectives are done (the 6 nearest per objective) and a yellow ? where a finished
  quest is turned in; hover for the quest and what to do there. From QuestieDB, drawn only while the Questie addon
  itself is off (it draws its own; said once): switch Questie off at the character screen and keep QuestieDB to use
  it. Our own frames over the maps, never the game's map pins; works with a rotating minimap. `/qs questie` and
  `/qs doctor` say whether it is on and why not.

## 0.3.8
- **Test the whole ring: `/qs quick test`** (or *Test the ring* in the log window). Every slot of every ring is run,
  one every 3 seconds, and checked against what the game really did: emotes are done and the game's line ("You
  dance.") awaited; messages are whispered to yourself (nobody else gets them) and the game's "To you" awaited; pings
  and invites are skipped. A window lists `[OK]` / `[--]` per slot with the game's answer and where the message goes on
  the ring. `emotes` / `messages` run only those, `fast` runs the emotes back to back (does the game hold quick ones
  back?), `stop` ends it. A refusal during the test changes nothing.
- The debug log writes your own chat as the game showed it ("you whispered Lia: Thanks!", "you told the party:
  ...", "You dance."): the proof that what the ring did really happened.
- **Only emotes your game has are on the ring** (the addon reads the game's own emote list).
- **"Something works sometimes, not always" on the ring:** letting go of the key within a quarter second of opening
  the ring kept it open and did nothing, even when you were pointing at a message: a quick flick onto a message now
  sends it (only a tap with nothing pointed at keeps the ring open for a click). Letting go in the middle is written in
  the debug log.
- **Emotes the game does not show are said.** After each emote the addon waits for the game's answer ("You dance.")
  and writes it in the debug log; without one it says "the game did not show /hug (1.2 s after the emote before)" (at
  most every 10 seconds): the game may hold back emotes done quickly one after another. The emote stays on the ring.
- **Errors name the line on newer clients too.** Their stack lines read `[Quick.lua]:382`, which the error log did
  not recognise: it said "no Quest Sharing line on the stack" (taint) for a plain refused send from a ring click.
  The send is also called by its own name now, so a refusal says `SendChatMessage`.

## 0.3.7
- **Optional: Questie, with its quest data QuestieDB.** *Tell them where to get it* and *Trace back the chain* need
  Questie 12 **and** QuestieDB: two folders in one download. Get it from
  [Questie's releases](https://github.com/Questie/Questie/releases/latest): take the `Questie-v...+v....zip` under
  *Assets* (not "Source code") and copy **both** folders, `Questie` and `QuestieDB`, into `Interface/AddOns`. QuestieDB
  on its own: [QuestieDB's releases](https://github.com/Questie/QuestieDB/releases/latest). `/qs questie` checks it.
- **A channel the game refuses no longer stops the whole ring.** Some clients do not let addons post in `/s` at all,
  not even from a click ("tried to call the protected function send()" from a click on the ring). One such refusal
  used to switch off sending at once for everything, for the whole session, even after ticking the box again: whispers
  to the player you picked went into the chat box too. Now the refusal is remembered for that channel only: `/s` goes
  straight into the chat box (press Enter), whispers and party messages still go out at once. The hint says so,
  `/qs doctor` lists the refused channels, and ticking *Send the message at once* again gives them another try.
- **"Questie is installed but Quest Sharing says it is missing" now says why.** Questie 12 keeps its quest data in
  a second folder, QuestieDB, from the same download. `/qs questie` gives, for Questie and for QuestieDB, "loaded,
  version ..." or the reason from the game's AddOns list (not installed, switched off, marked out of date, missing an
  addon it needs), finds Questie folders with another name (`Questie-master`), says what the game has (QuestDB,
  LibQuestieDB, QuestieLoader), and ends with what to do ("copy BOTH folders of the Questie download..."). The grey
  menu lines, `/qs doctor` and the debug log's session line give the same reason.
- **Emotes and messages can follow each other right away** (Hug, then Salute): only the same slot twice within a
  second is held back (it used to be any two picks, silently).
- **The log and errors window scrolls** (mouse wheel) however long the text, shows up to 1000 log lines, and has
  buttons: Select all (then Cmd+C / Ctrl+C: the game gives addons no clipboard), Debug log / Errors to switch, Clear,
  Close. *Settings > General > Debugging* has *Show the debug log* and *Show the errors*.

## 0.3.6
- **A debug log of everything, not only errors** (*Settings > General > Debug log*, `/qs debug on|off`, off by
  default). Every action and its outcome, one line each with the time: what you picked on the ring, who it was for
  and where it went (sent, chat box, nothing and why), each ping press, each quest share and its answer, every call the
  game may refuse, your `/qs` commands and setting changes, everything the addon told you, the game's own answers
  (system messages and errors), combat / target / party / zone changes, quests accepted or turned in, and every error
  with its stack. It starts with a line saying what the session is (versions, language, Questie). Repeats are counted
  on one line, the newest 3000 lines are kept. Saved as `QuestSharingLog` in the addon's SavedVariables file on
  `/reload` or logout; `/qs log` (or *Show the debug log*) shows it in a window to copy, `/qs log clear` empties it.
- **Trace back the chain** (right click a quest in the Party quests window; needs Questie): one chat line with the
  level the quest needs, every quest before it from the first one, where the first one starts and where this one
  starts ("(or 1 other)" / "(+2 more)" where other quests lead there too or are needed). Always one chat message (255
  letters): a long chain keeps its first step and shortens the middle to "(5 more)". In a party it goes to the party,
  alone only to you. For when someone does not have a quest you have: what they need first, and where.
- *Friends* moved to the *Party* tab of the settings (room for *Debugging* in *General*).
- Fixed: a quest share that went through, followed within a second by some other call the game refused, switched
  sharing off (found with the new log). The "Auto messages go to" choices describe the 0.3.5 routing.

## 0.3.5
- **The quick chat ring always does something on a release.** `/s` and `/y` only go out at once from a click (the
  game wants a real click for them); a release used to leave the ring open waiting for one, so "Hello", "Team up?" or
  "What I need" alone seemed to do nothing. Now a release puts them in your chat box (press Enter), and a click on the
  message still says it at once. The ring says so once.
- **Whispers to the player you highlight.** The player a message is for is your target, or, with nobody targeted,
  the player under your mouse when you open the ring. Auto messages whisper that player when they are not in your
  party, even while you are in one (before, a party always got them). A party member targeted: the party. Players of
  the other faction are never picked.

## 0.3.4
- **The quick chat ring sends at once.** A message you pick on the ring is sent straight away, no Enter: its own
  switch, *Settings > Quick chat > Send the message at once* (`/qs quick send on|off`), on by default. Off: it goes
  into the chat box and you press Enter, as before. Messages to everybody nearby (`/s`, `/y`) still need a click on
  the slot. If the game refuses a message from the ring, it goes into your chat box and the switch turns itself off
  (remembered), so the refusal does not come back every session. The other messages (menu, quest clicks, Post all)
  keep following *My messages*.
- The settings window is a little taller (630 instead of 600), so the Quick chat tab fits with its editor.

## 0.3.3
- **Fixed "tried to call the protected function UNKNOWN()" during fights** (once a second): the quest item icons turn
  red when your target is out of range, and asked the game for that range in combat too, which the game refuses for
  enemies. The range is now only checked outside combat. The ping key's "within about 28 yards" check is also never
  made in combat (`/qs ping` could do it there).
- **The star over your head is gone:** the game refuses raid marks set by an addon, even outside combat ("while
  putting the star over your head"). The setting and `/qs star` are removed.
- **Sharing on your clicks where the game refuses automatic sharing** ("tried to call the protected function
  QuestLogPushQuest()"): the first refused share switches the addon to it, says so once and remembers it. A round then
  waits, and each click on **Share** in the Party quests window (or `/qs share`) offers the next quest; clicking a quest
  offers that one. A refused quest is no longer counted as offered. *Settings > Sharing > Share only when I click Share*
  / `/qs shareclick on|off`. Only if the game refuses a share from your click too, sharing is off until `/reload`.
- **Errors say where they came from.** A call the game refuses is written down with the line of the addon that made
  it ("tried to call the protected function UNKNOWN() from QuestItems.lua:150 paint"), the function's real name when
  the game's stack has it, what the addon was running ("a timer set at QuestItems.lua:342", "the event
  QUEST_LOG_UPDATE"), whether you were in combat, the game's event (ADDON_ACTION_BLOCKED or _FORBIDDEN), and the stack. With none of the addon's code on the stack, it says so
  and names what the addon ran last. Lua errors in timers, events and frame scripts keep their stack too. `/qs errors`
  stays short in the chat; its window (and the `/qs doctor` report) has the details to copy.

## 0.3.2
- **Fixed "NamePlateX:GetCenter(): Can't measure restricted regions"** (shown when a fight starts or ends): to find
  the "nearest" quest creature, the ping key measured nameplates on screen, which the game forbids around combat.
  Now it never measures them: your target first (if it is a quest creature), then the creature the game soft-targets
  in front of you, then your mouseover, then one within about 28 yards; and nothing is refreshed as combat starts.
- **Fixed "protected function UNKNOWN()" in fights:** the quest icons over creatures were written onto the game's
  nameplates ("Lua Taint: QuestSharing"). They are now the addon's own frames, kept in its own list and only placed
  over the nameplates; none are made during a fight (new nameplates get theirs right after it). The quest item icons
  in the tracker are placed at a spot on the screen instead of being tied to the tracker's own buttons.
- **Pings that do nothing are no longer a mystery:** every press of the ping key says what happened ("ping: Kobold
  Vermin (attack)", "nothing to ping: no quest creature in sight", "held back..."), the game's own ping errors are shown
  ("the game did not send the ping: ..."), and **`/qs ping`** checks every step: the game's ping system, pings switched
  on, the ping key, telling quest creatures apart, enemy nameplates, the nearest quest creature now, what the next
  press does. A press with nothing loaded is no longer reported as "held back".
- **Pings, as agreed:** the enemy you need gets Attack, the object you need gets "look here"; at most one ping every
  10 seconds and a new one after each fight; with several things to collect, the next press waits until you picked
  one up (your quest counter goes up) and then points at the next.
- **Quest creatures are recognised on more clients:** without the game's "is this unit part of a quest" call, the
  addon uses the creature names in your quest log ("Kobold Vermin slain: 3/8", in your language) and, with Questie,
  the creatures to kill and the ones that drop your quest items. This makes the ping key and the quest icons over
  creatures work there. The ping system is also recognised by its key bindings, not only by `C_Ping`.
- **Questie's creature names, done right:** creatures that count for another one ("kill credit", e.g. any of several
  gnolls for one objective) are recognised too. Questie's names are only used when Questie's language is the game's
  (Questie can be set to another language, or falls back to English): otherwise they never matched a name on screen.
  `/qs questie` names the language of Questie's names, and `/qs ping` says when they differ from the game's.
- A test now compiles every file under Lua 5.1.

## 0.3.1
- **Your messages go into the chat box and you press Enter**, by default. Some game clients do not let addons send
  chat messages at all ("tried to call the protected function UNKNOWN()"); typing into the chat box always works.
  The ring (no extra click needed for `/s` any more), the right-click menu, quest clicks and Post all all do this,
  with the channel set (`/p`, `/s`, `/w Name`). *Settings > General > My messages* / `/qs mode send` sends at once
  where the game allows it; if the game refuses, the addon switches back to the chat box by itself and says so once.
  The automatic party messages need "sent at once".
- **Calls the game refuses are written down and switched off:** the error log says what the addon was doing ("while
  putting the star over your head", "while sharing a quest with the party", ...), and that feature stays off until
  `/reload`, so the error cannot repeat. The star over your head is never set during combat.
- **Emote rings:** while the quick chat ring is open, the mouse wheel flips to rings with the game's emotes: Emotes
  (thank, bow, dance, wave, cheer, point, no, wait), Group calls (follow, charge, attack my target, heal me, help me,
  incoming, flee, out of mana) and Fun (train, laugh, applaud, salute, hug, flex, chicken, roar). The ring used last
  opens first. Emotes are done with the game's own call; if the game refuses, they are typed into the chat box.
  **Every ring is editable** in Settings > Quick chat (a ring picker on top of the editor; type `/dance` for an emote
  slot; Reset puts back that ring's defaults).
- **The Party quests window when you are alone** (option, on by default): "Quests here", your quests of the zone.
- **Quest items one click away:** an icon next to the quest in the game's tracker for usable quest items in your bags
  that the game does not show itself (matched by the bag's quest info, an objective naming the item, or Questie's
  "item this quest gives / needs"); a **quest item key** and a small movable button for the item of your nearest
  quest, with count, cooldown and an out-of-range tint. Secure item buttons, prepared outside combat. Settings: a new
  **Pings & items** tab (pings moved there; the friends beta is now on General).
- **`/qs questie`** says whether Quest Sharing can read Questie's quest database on your client: is Questie (and
  QuestieDB) loaded, which way it is read (QuestieDB of Questie 12, LibQuestieDB, or the older Questie), is it ready,
  and a real lookup on the first quests of your quest log. Also reads `LibQuestieDB.Quest.Get` when the short global
  names are missing. `/qs doctor` names the way it is read.
- **Fixed: quests from far away in Teldrassil** (Stormwind quests in the Party quests window, also with "by zone").
  The Party quests window now lists only the quests of the zone you are in (the 5 nearest first, then the rest of the
  zone) and is never filled up with quests from elsewhere. The tracker and the map pin take a quest of another zone
  only when it is within about 1000 yards and the game says it is on your continent; a client that does not say so
  (or reports nonsense distances) cannot pull far quests in any more.
- **Ping the quest target:** a ping key (and an `@ping` slot on the ring) gives the nearest creature your quests need
  the game's **Attack** ping and makes it your target; with none in sight, the quest object you face gets **"look
  here"**. Anti-spam: a new ping once the one you pinged is dead (or no longer your target), or after 5 / 10 / 15
  seconds outside combat; Shift pings anyway. The game allows pings only from your key press, so the addon prepares a
  secure button outside combat and your key presses it; the anti-spam check runs in the game's secure code.
- **Fixed "tried to call the protected function SetPassThroughButtons()".** The addon never calls it, but the menu's
  "Open it in the quest log" opened the world map from addon code on clients whose quest log is inside the map; the
  map then built its pins in the addon's name and the game refused. The addon no longer opens the map: there the
  quest is selected ("Select it in the quest log") and you press L or M. The old quest log window still opens. A test
  now fails if the code ever names a map-opening function or `SetPassThroughButtons`.

## 0.3.0
- **You decide when to talk.** The automatic party chat ("in common", "done", "picked up") is **off by default**, and
  switched off once for existing settings. Your own chat gets one short line after quests were shared
  (`shared 2 quests with the party: Anna took 1, 1 declined`); the per-answer lines and the `verbose` setting are gone;
  the tracker pause is explained once per session.
- **The Party quests window is a grid:** *Quest | member 1 | member 2 ...* with a **check** (has it), a **gold check**
  (finished it), an **X** (does not have it), a **grey dash** (cannot take it) or a **?** (the game cannot tell: out of
  range, offline). Your **5 nearest quests**, re-sorted as you move without flicker, then **scroll** for the rest of
  the zone. **Left click offers** the quest to whoever does not have it. **Right click opens a small menu:** tell the
  party how I am doing ("I still need Wolf Pelt 2/4 (Wolf Pelt at 42.3, 61.8). What about you?"), offer it, **tell
  them where to get it**, focus it on my map, open it in the quest log. Header with Share, Post all and fold; names
  in class colour, **QS** for Quest Sharing users; it hides in combat, has a size setting and a "move back" button.
- **Questie support** (optional, read only): where a quest starts, the earlier step and where that one starts, how
  many steps lie before it; or the item that starts it and who drops it. Shown in the row tooltip and sent by "tell
  them where to get it".
- **A quest you finished is never shared, announced, listed or marked as something to do together.**
- **Playing together without spam:** "Picked up [quest] - Anna has it too. Want to do it together?" (optional); where
  you found the quest items is added to your messages while someone in the party still needs them; at most 4
  automatic messages a minute; "in common" never takes more than two lines.
- **Several Quest Sharing users in one party take turns:** one popup per quest (offers are shared between the addons),
  one "in common" and one "done" per party; accepting a shared quest no longer re-offers or announces it.
- **Showing each other where you are:** the star over your head in a party (not in dungeons, never taken back from a
  tank), Quest Sharing users as class icons on your world map, a map pin where a teammate found the items, and the
  quest marker preferring the nearest quest you share.
- **Quick chat ring:** a channel for every message (Auto, Nearby, /s, /y, /p, /w) chosen in the editor; dots in the
  colour of the chat they go to and the destination under the message; three sizes; *Team up?* says "Doing [your
  quest] here - anyone want to group up?" in /s; a blocked send lands in your chat box; it never takes the game's
  sound, music, volume or menu keys.
- **Clicking a quest in the game's tracker** adds its status to the chat box instead of replacing it (click several,
  press Enter once); no raw `{rt1}` in the chat box; finished quests no longer say "Anna has it too".
- **A more beautiful, easier addon:** a settings window with six tabs, sections, check boxes and a line under every
  setting; set the quick chat key by pressing it; Check my setup and Show the ring buttons; a welcome once and a short
  "what's new" after an update; a live status in the map button's tooltip (it showed a stray `\n` before); a soft
  sound for good news (`/qs sound off`).
- **Fixes:** long messages are cut without breaking a quest link or an accented letter; a `|` you type is escaped;
  the Party quests window first opens on the left of the screen; `/qs doctor` shows the game's sound settings.

## 0.2.0
- **Quick chat ring** (hold a key, point, release or click): a clean ring with short labels, editable messages and
  placeholders, a whisper to the player you target, and `/say` sent on a click or key press (the game forbids it from a
  release); light on the game (messages are only filled in when you point at them); with a stranger the
  message is a question that links your quests of the area; an `@invite` action invites your target to your party
- **Tracker follows you**: keeps the quest tracker on the nearest quests (distance mode, or zone mode on clients that
  cannot measure distance); steps aside for 10 seconds (a setting) when you change the tracker yourself, with or without game events
- **Tabbed settings window** (`/qs settings`) with a message editor, minimap button, entry in the game's options; everything on by default
- **Friends (beta)**: add the people you group with to your friends list, with safeguards
- Sharing happens once per member: when you join a party, when someone new joins, and when you accept a quest;
  a quest someone declined is never offered to them again automatically
- Addon-to-addon sync of exact quest lists and progress; "quest finished" announcements; a quests-in-common panel and
  quest log markers
- **Easier-to-find objectives**: a quest icon above the nameplate of creatures that are part of your quests, the
  game's own waypoint marker follows the nearest quest, and an optional helper for the game settings these need
- `/qs doctor` (a report you can copy) and `/qs errors` (an error log) for problems on a real game client

## 0.1.0
- First release: shares your quests with a new party, announces the quests you have in common, reads the game's
  accepted / declined / already-on-it replies, and posts a friendly status when you click a tracked quest
