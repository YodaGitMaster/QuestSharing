# Changelog

## Unreleased
- Party finder invites only levels that fit your listed dungeon: **Levels to invite > From the dungeon** (default) uses the dungeon's suggested levels, the same "18-23" the game's party finder shows (`minLevelSuggestion`-`maxLevelSuggestion`); above that the game itself calls the dungeon trivial and the mobs soon give no experience. Several listed dungeons: from the lowest start to the highest end. When the game gives no levels, the addon's own dungeon list is used; unknown dungeons fall back to your manual range. `/qs lfg level 20 30` switches to Manual, `/qs lfg level dungeon` back. The picker and tooltip show the range in use.
- **Every tool is now a module you can switch off**: Settings > General > **Tools** has one switch per tool (Quest sharing, Markers & pings, Quest list helper, Accept & turn in, Quest items, Bags, Fight tools, Quest guide, World map tools, Dungeon journal, Reward browser, Professions, Party finder, Quick chat) and a **Reload** button. An off tool stops listening to the game at once, its `/qs` commands say it is off, and its settings are dimmed; after `/reload` it installs nothing at all.
- Party finder remembers who you invited, who joined and who left (saved across /reload, kept 24 h): none of them is invited again for an hour (**Settings > Party finder > Minutes before inviting the same player again**, 60-1440; replaces the 5-minute wait). `/qs lfg history` lists them, `/qs lfg forget` or the **Forget** button clears it; the spyglass tooltip shows the counts. New **Who goes first**: Level and nearness (default), Highest level, or Nearest to the dungeon - nearness uses the zone the party finder shows for each player (what /who would tell) against the dungeon entrance; the invite line says where they are ("... in Westfall").
- Dungeon quests, Bosses page: bosses of **Forever-only dungeons** now get their portraits from the game: the addon asks the client for each boss's model in the background (one at a time, never in combat or on a loading screen) and remembers it, so the skull shows only until the model is found. Ezra Grimm (Stratholme) now has his portrait. New `/qs bossdump` lists the found boss models.
- Dungeon quests, Bosses page: it lists only the dungeon's **official bosses**, in fight order (new boss list for all 28 dungeons), with no trash, chest or helper rows; a boss without known drops still shows. Portraits use the client's Encounter Journal art, else the creature's portrait (loaded out of sight, so no black squares), else a dimmed skull. Calmer rows, flat level badges, no "Elite" guess on official bosses, "(optional)" on optional ones, and the "Install AtlasLoot" hint shown once on its own line. Sneed now gets his Shredder's drops (but not its level or model); Gahz'rilla and Magistrate Barthilas show their own art.
- Party finder keeps the party at most 1 tank, 1 healer and 3 damage, **you included**: new **I am** button in the picker (and Settings > Party finder > My role in the party): Automatic (the game's role, your one party finder role, or a damage-only class; else damage), Tank, Healer or Damage. Members whose role is unknown count as damage, so the tank and healer spots stay open. The picker shows the party: "Party: tank 0/1, healer 1/1, damage 2/3". Supercharge also stops at these limits.
- Party finder: only people really in your party count for free spots and roles. An invite nobody answers, or a player who left, no longer makes it say "the party is full"; the next Find simply invites the next player. Normal mode invites per Find only what the members leave open (1 healer, 1 tank, 3 damage); Supercharge invites every match at once again (up to 10). Replaces the previous entry that held spots for open invites.
- Bag arranging, new options in Settings > Bags (and `/qs sort ...`): **Layout** can start each group (topic, or quality) on a new row, so crafting materials, equipment and the rest each get their own lines. **How my bags are shown** sets what a row is: the game's bag windows (4 a row, per bag) or one big bag from a bag addon (set **Columns**, 4-16). **Split crafting materials by kind** gives cloth, herbs, metal, leather and the rest their own rows. **Join partial stacks first** merges half-full stacks to free slots. If the rows do not fit, the items are packed and the chat says so. Commands: `/qs sort layout packed|rows`, `view bags|onebag`, `columns 4-16`, `crafts on|off`, `merge on|off`.
- Dungeon quests: the dungeon page no longer has a legend line above the header; the page range sits in the list heading ("Quests | 1-8 of 20") and the icon legend is a small two-line note at the foot of the quest list. Boss ability texts no longer say "Nature damage and an additional Nature damage" (now "...and more Nature damage over time").
- New Dungeon quests look (a dungeon journal). `/qs dungeons` opens on a home page of dungeon cards: the loading-screen art, the level range, open/total quests, the faction crests and a tick when you have done them all. Search by dungeon or quest name, or click a crest to show one faction. A card opens the dungeon page with four tabs: **Quests** (the list and a parchment quest page with reward items in 3 columns and XP, gold and reputation chips), **Bosses** (bosses in encounter order with portraits, levels and their drops; full drops with AtlasLoot, partial ones from QuestieDB), **Map** (the game's own dungeon map with floors, zoom and drag; a dungeon without map art offers a pin on its entrance) and **Route** (the route to pick up every quest, in the page). All art comes from the game client; no new image files.
- Dungeon quests, closer to the Dungeon Journal look: the home cards fill the page width in 2 columns, the home search has a clear button and is the only search there (the quest filters show on a dungeon page only), and the cards follow Hide completed, Hide quests in my log and the chosen crest. A done dungeon has a soft glow behind its tick. Quest rows show class icons for class quests, a dungeon icon when you pick the quest up inside, and a chain icon (hover: the chain). The quest page says e.g. "DRUID / WARRIOR ONLY" in the class colours, has a **Share** button (green when you can offer the quest to your party, grey with the reason otherwise) and its status strip has the badge colour. Item tooltips say "Drops from <boss>", and a click on such an item opens the Bosses tab on that boss. Boss portraits also find Encounter Journal art spelled without spaces. **Plan route** opens the Route tab.
- Dungeon quests, round 3: the Bosses page shows each boss's Encounter Journal description, abilities with spell icons and **Needed for** (the quests that ask you to kill it; a click opens the quest, resetting filters that hide it). Home cards have a hover tooltip with levels, quest counts and the dungeon's description, and the dungeon header has a one-line description. The quest filter bar is one row (Level, Quest levels, Class and Faction behind **Filters**, which closes on Escape or a click outside). Class icons have a class-coloured ring, the Map opens on your floor and keeps a floor you picked, and the Route says when planning failed and marks the next step.
- Party finder: fixed "Your party is full." while inviting. The game counts open invites as party spots, so Supercharge now fills only the free spots (open invites and players still being asked about their item level included) instead of up to 10 invites. A player listed twice gets one invite. An open invite holds its spot 75 s (was 60 s, the game keeps it open about a minute). If the game still says the party is full, a plain chat line explains it.
- Fixed: map search found nothing outside some places (e.g. Hillsbrad fish and General Goods sellers) after playing a character of the other faction. The saved NPC list is now kept per faction. If it still finds nothing, run `/qs memory purge` once.
- Removed the on-screen quest item button (the icon below the middle of the screen), its switch, its Move back button and `/qs itembutton`. The **Key to use my nearest quest's item** still works, and the item icons beside tracked quests stay.
- Quest guide stays on: it no longer rebuilds itself (and empties its list for seconds) on every loot, reputation gain, skill-up or spell change, and no longer re-sorts its steps while you walk. It recalculates when a quest is accepted, progresses, is done or abandoned, on a level-up, in a new zone, or when you click Refresh; a reputation gain recalculates only when it unlocks or closes a planned quest. While it recalculates the current steps stay visible. Walking into a mine, cave, town or dungeon keeps the plan ("paused") and coming back out continues it without starting over. Hiding the interface (Alt+Z, a cinematic) no longer ends the guide.
- Settings usability pass: **Arrange my bags automatically** (was "...by topic automatically", wrong when ordering by quality or name). The Party finder page is split into Roles, Invite whisper, Level and item level filters, Picker and key, Classes to invite, Item levels; its intro says to list your group first, and the role switches read the same way. More rows dim with the switch they need: the waypoint (automatic tracking), party map icons (Sync), the ping key and the quick chat key; the unknown-item-level rows dim while the lowest item level is 0. Search also understands everyday words such as keybind, hotkey, junk, threat, sort. **Show shared camps on the world map** (was "Shared camps").
- Dungeon quests route: **Assume I know all flight paths** is now remembered between sessions and has its own switch in Settings > Items & dungeons > Dungeon route (before, it reset on every reload and was only in the route window).
- Party quests window: one name everywhere (minimap tooltip, Settings, error message). New close button in its corner; it says how to bring the window back (`/qs panel on`, or Settings > Party window). While quests are being offered, **Share** reads **Stop**; click it to stop sharing.
- `/qs gap` keeps the time between shared quests between 2 and 30 seconds, like the Settings row, and says so when it changes your number.
- Chat: the "Quest Sharing:" prefix is now gold. Counts use proper singular and plural ("1 bookmark removed", "2 problems recorded", "no bookmarks to remove"). Settings help no longer repeats a dependency the "Has no effect until ..." note already gives.
- Quest guide: left and right click on a step both set its waypoint, also in combat. Pickup and hand-in steps name the quest giver once ("Pick up from Sentinel Hill Giver:"). Steps show only advice you can act on; route notes stay in the report. When Questie is missing or too old, the guide says what to do and points to `/qs questie`. The panel uses the classic stone background and button art.
- Quick chat ring: the Invite slot says "click it (or press the key again) to invite", or "no target: target a player first".
- One name per feature: "Zone levels" on the world map, "Fishing spots" for the fishing window and map box, "Where to gather" for gathering lists. Item tooltips say "Sold by: ..." and "Mined from veins" instead of "Questie sources: ...". Dungeon pins say "Closest flight master towns:" (both factions) or "Closest flight master town you can use:". The map search box has the stone and bronze frame and a gold heading.
- Dungeon quests opens on the dungeon you are in; a dungeon you pick stays until the next open. Details redraw when a filter changes. The faction and class dropdowns are labelled.
- Quest rewards no longer has its own on/off switch or `/qs rewards on|off`: the button, tab and `/qs rewards` just open it. `/qs panel` with no argument shows the Party quests window instead of toggling it; hiding it from the minimap says how to bring it back. A share round says "click Stop or type /qs stop to cancel". Settings say "Zone levels" and "Fishing spots". Quest rewards and Dungeon quests share the "Hide completed quests" checkbox and the "Quest levels: ..." wording.
- New, optional: **Shared camps** (Settings > Quest guide, or `/qs plan camps`). The world map shows the Quest guide's camps for your planned kill and collect quests: blue when one visit helps 2 or more quests, grey for one. Hover a camp's label for its mobs and quests, click for a waypoint. The **Camps** button on the Quest guide (or `/qs plan camps table`) opens the Shared camps window: a quest → mob → camp network, a map of spawns, camps and quest givers, and a camps × objectives matrix; pick an objective to highlight it in all three.
- Quest guide, from a real Coldridge Valley test (level-1 gnome mage, real QuestieDB data): quests up to three levels ahead join the route where quest and kill XP reach them, so the valley's level 3-4 quests are done before you leave instead of after a walk back from Kharanos. Your own class quests count when their giver is in the zone. Camps and merged steps are measured in yards: two quest givers 185 yards apart (Balir and Mountaineer Thalos) are no longer shown as one step.
- Map: boats, zeppelins and dungeon tooltips show your own faction by default (**My faction**); pick **Both factions** to see both.
- Adventurer's Journal: no "req 0" / "req 1"; "1 item"; "scroll to browse" only with more than one page; source lines are parchment tan (grey means done); the chosen dungeon in Instance drops is gold. Invitations are limited to "255 letters". The party finder log says "item level".
- Plainer messages: cooking ingredient fishing lines ("Fish stay hooked from skill 75", "(Horde area)", your faction's waters first, "Sold by vendors (seller not known)"), spell ranks ("spell ranks paused until /reload - your cursor was busy"), bag cleanup needs QuestieDB, and bag marks say "(in this zone)".
- Party messages: **Announce quests in common in party chat**, **Tell the party when I finish a shared quest** and **Tell the party when I accept a quest a teammate has** are greyed while **How to send quest progress messages** is not **Send immediately**, and switching one on then says in one line that nothing is sent and how to change it (`/qs mode send`). Fixed: **Tell the party when I finish a shared quest** now works on its own, without **Announce quests in common**.
- **Reset settings**, **Clear errors**, **Clear logs** and the report's **Clear records** now ask for a second click within 5 seconds. The reset message says the quick chat messages are reset too (no more "(everything on)").
- Slash commands: every on/off command now prints one line naming the setting and where it is ("Sell gray items when I open a vendor: on (Settings > Bags)"); the full status is only for `/qs status`. `/qs` alone prints two short lines, an unknown command prints one line, and a wrong value shows that command's usage. `/qs help` now lists the Quest guide commands, `/qs status`, `/qs sound`, `/qs itembutton`, `/qs pingobjects` and `/qs solo`; new `/qs map` lists the world map switches.
- Settings > Errors & logs: one **Open report** button replaces Run check, Show errors, Show logs and Open report (they opened the same window). Setup notes say in plain words what is unavailable. **Test the ring** moved to **Settings > Quick chat**.
- Settings: the Map page names the dungeon, boat, zeppelin and trainer pins and links to the pages with map search, gathering marks and fishing spots. Settings search knows more words (*gather*, *junk*, *trash*, *keybind*, *hotkey*, *sell*, *vendor*, *merchant*).
- Quest guide: one name everywhere ("Quest guide"), and goal and level names match Settings. Chosen quests takes quest names as well as IDs (`/qs plan selected Local Harvest, 9001`), and the row tooltip shows each quest's ID. Every goal change is confirmed in chat and shown in the Plan button tooltip. The Time limit is 5-240 minutes everywhere. The `...` button opens Settings > Quest guide.
- Quest guide: new **Busy** button and `/qs plan busy` for kill and collect steps; the chat names the next free camp. A finished zone says so, and an empty one points to Plan > Show report. The report lists quests by name and ID with one plain reason each.
- Keys: setting the quest item, ping or party finder key now says what the key used to do in plain words ("W used to do: move forward"), like the quick chat key. Fixed: choosing a refused key (such as Escape) no longer removes your old key.
- Grey lines in the right-click quest menu say why on hover. The **Quest invitation** window (was "Seek fellow adventurers") picks the chat from buttons (Current chat, Say, Party, Raid, Guild, Channel 1, Whisper target) instead of a typed name.
- Map: dungeon, boat, zeppelin and tram pins set a waypoint when clicked. Zone level badges are coloured by quest difficulty for your level, and the panel shows your level. A teammate's item spot no longer replaces a waypoint you set in the last 5 minutes; the chat offers a [Set waypoint] link instead.
- Map search: one click on **Elsewhere** sets the waypoint and names the zone. Suggestions are labelled by kind ("Trainer: Paladin Trainer") and single words appear only while you type a word. In combat it says the search waits until the fight ends.
- Fishing spots: after Save water the hint names the real setting (**Show saved spots on the world map**). The saved list, the Map ID field and the pin tooltip show the zone name; pins say "skill unknown". `/qs gather` answers in one plain sentence.
- Bag cleanup: deleting a stack keeps the list for the next stack. **Update ranks** works even with automatic spell rank updates off.
- Adventurer's Journal: empty lists say only blue and better items are listed (most levelling rewards and drops are green), and missing data says to install or update QuestieDB. Dungeon quests use the game's yellow ! (to pick up) and ? (in your log); gold now only marks the selected row. Plainer wording: "quest level 20", "(quest ID 2)", no raw quest-data fields, and a **Mark quest giver (then press M)** button in both tabs that puts a map pin on the giver.
- README: current setting names and defaults, the Errors & logs report, `/qs dungeons`, `/qs map`, the Quest guide and Quest invitation changes.
- Everything read from QuestieDB is now read **once per session**: Dungeon quests, Quest rewards, Dungeon loot, the map search, trainers, gather spots and the Quest guide's zone lists. Closing and reopening a window (even much later) is instant, and a half-read list continues where it stopped instead of starting over (before, most were freed 2 minutes after closing and a half-read one restarted). One **Purge** button, **Settings > Items & dungeons > Free the loaded quest database data**, or `/qs memory purge`, frees all of it; each reads again the next time you use it. `/qs memory` also lists the Dungeon loot catalogue.
- Faster after a `/reload` or a new login: Quest Sharing now saves **which** QuestieDB entries each catalogue needs (a small list of IDs in the new saved file `QuestSharingCache`, not the data itself). The next session reads only those entries instead of searching the whole database: Dungeon quests, Quest rewards, Dungeon loot (without AtlasLoot), the map search's NPC list, trainers and the Quest guide's zone lists. The lists are rebuilt by themselves when the game, Quest Sharing, Questie or QuestieDB updates; **Refresh data** in a window reads the whole database again, and **Purge** also deletes the saved lists. `/qs memory` shows how many are saved.
- Where to get it: the item tooltip now lists the three best places **for you**, one short line each with name, zone and chance ("1. Plains Wolf · Westfall · 61%", a vein or herb says "node"). Creatures more than 3 levels above you and the other faction's home zones are left out (unless nothing else is known), and places are ranked by items per visit (spawns × chance) instead of spawn count only. Level and spawn count moved to the map pins. Cooking ingredients no longer list their drops twice. When nothing fits you the header says so ("none for your level and faction; best known"), the list ranks again when you level up, and `/qs gather` says how many zones were left out and why.
- Party finder: the picker's **Settings** button and a right click on the spyglass now open **Settings > Party finder** (they opened the Party window page). Messages say "item level 33" / "item level unknown" instead of "ilvl". Class rows say "damage dealer" and no longer repeat their requirement. Both picker switches turn gold when on; the Find tooltip describes the open-roles rule. New README section "Party finder: find and invite players", `/qs lfg` and `/qs ilvl` in the commands table and `/qs help`.
- Where to gather polish: map pins on a vein or herb say "Gather it here for ..." (not "Drops"), pins and tooltips show the chance the same way (61%), the tooltip says Cmd+right-click on a Mac, and `/qs gather` explains which items are looked up. Pressing Space over your bags in a fight now says once that bookmarks wait until the fight is over.
- Party finder matching fixes: a player listed for several roles (a druid as healer and damage) now takes whichever wanted role is still open, hardest to find first (tank, healer, damage), instead of being skipped once their first role was filled; after waiting for an item level answer the role is checked again; supercharge no longer invites more of a role your party members already fill; party members whose class can only deal damage (rogue, mage, warlock, hunter) count as damage; older party finder versions (one `activityID`, leader info only) are understood.
- Fixed: in-combat errors from the v0.4.26 report. The Space bookmark key no longer triggers "the game blocked an addon action" (SetPropagateKeyboardInput) on every key in a fight (bookmarking with Space works out of combat only), and the activity log no longer errors when the game hides the target's name in combat (it writes "target: (hidden by the game in combat)").
- Fixed: "Where to gather" was missing for most gathering items (Light Leather, hides, cloth, ore, stone, meat, elementals): the Classic item data files them as plain Trade Goods or Reagent, and only herbs have their own subclass. They now show their skinning, drop and node sources, and chests and crates are no longer listed as gathering spots (ore now lists its vein).
- Party finder invites by role need: normally only what each role still needs (1 healer, 1 tank, 3 damage, counting members who joined through an invite, roles the game knows, and open invites), highest level first; a decline frees the role for the next one. New **Supercharge** box in the picker (and Settings > Party finder): invite every matching player of the ticked roles/classes at once (up to 10 per Find) so one who does not answer cannot hold you up; the whisper adds "First to accept gets the spot." Extra players who accept may need to be removed.
- Settings are easier to find: a **Search settings** box at the top of the window finds a setting on any page by a word from its name or help (for example *sort*, *key*, *map*), shows each match under its "Page > Section" line, lets you change it right there, and opens that page when you click the gold line. Picking a page on the left leaves the search.
- Settings that do nothing until another switch is on are now greyed and say which switch, for example **Wait before arranging automatically** until **Arrange my bags by topic automatically** is on, the quick chat options until the ring is on, and the class switches until their role is invited.
- New **Party finder** page (under Party): the party finder options, the class switches and the item level options moved off the crowded Party window page. New switch **Invite every match at once (supercharge)**, the same choice as in the finder window.
- Messages that point to a setting now name the right place: the ping key check (`/qs doctor`) said "Pings & items" and the gather hint said "Look up"; they now give the full path, for example *Settings > Items & dungeons > Show where items come from when I hover over them*.
- Settings: everything you can choose is now in the Settings window. New rows: **Bags > Wait before arranging automatically** (1-30 s, default 3, the quiet time before the automatic bag arrangement); **General > Seconds between chat lock reminders** (5-120, default 20); **Party window > Friend slots to keep free** (0-20, default 5); **Minutes before inviting the same player again** (1-30, default 5); **Days to remember item levels** (1-60, default 14); **Key to search the party finder and invite** (Set key, as for the other keys); and **Party finder: classes to invite**, one switch per role and class (the same choices as the finder window's class buttons). The party finder picker button moved into the Party finder section.
- Party finder: each invite is followed by a whisper saying which dungeon it is for: "Hi! I invited you to my group for The Deadmines as healer." Switch it in the picker ("Whisper them which dungeon the invite is for") or Settings > Party window, where the text can be edited (`{dungeon}`, `{role}`; empty = the standard text). If the game ever refuses an addon chat message, the whisper stops and the line is offered for the chat box, like the other automatic messages.
- Party finder polish: the picker shows class icons, gold dividers, the level range and free spots, greys **Find** and says why it cannot search (not listed, no role, party full, not leader), keeps the last invite line visible, and updates by itself when the party or your listing changes. A declined invite ("... declines your group invitation", "already in a group", "cannot find player") frees its spot at once; a player who joins no longer counts twice; a search the game never answers no longer blocks Find. Inspected item levels are kept even when the mouse moves away before the game answers.
- New **Show my aggro on enemies (for tanks)** (Settings > General > During a fight, off by default, `/qs aggro on|off`): while you fight, each enemy nameplate shows your aggro as a plain number (`73%`, 100% = it is attacking you). Switching it on prints what the addon can see (threat data, nameplates). Needs enemy nameplates (press V).
- Party finder: now needs your group **listed** in the party finder with a dungeon; it searches only your listing's activities (like the game's "search my listing") and invites only solo players listed for one of them, so random healers for other dungeons are no longer invited. The best match goes first: **highest level first**, then the highest known item level. The minimap spyglass now opens a small **picker**: tick Healer / Tank / Damage, untick the classes you do not want for each (e.g. healers only Paladin and Priest, damage only Rogue and Warrior), set the lowest item level, click **Find** (one search per click, as the game requires). The key binding still searches at once. The chat line names the dungeon ("... for The Deadmines").
- New **Party finder** spyglass button beside the minimap button. Each left click searches the game's party finder and invites the solo players listed with the roles you chose (Settings > Party window > Party finder: healers on by default, tanks, damage dealers), up to the free spots of your party, never the same player twice within 5 minutes, only as leader or when solo. Right click opens those settings. Key binding "Party finder: search and invite" (Key Bindings > Quest Sharing) and `/qs lfg`, `/qs lfg healer|tank|dps on|off`, `/qs lfg watch on|off` (also invite from your own searches in the game's window, off by default). The game allows one search per click or key press, so it cannot search by itself every second, and it shows no gear or item level for listed players.
- Party finder filters (Settings > Party window): **Lowest / Highest character level to invite**, **Lowest item level to invite** (0 = any), **When their item level is unknown** (Invite anyway / Skip them), **Ask Quest Sharing users for their item level first** (waits up to 2 s). The chat line shows the number: "invited Lia 24 Priest (healer, ilvl 33)". Slash: `/qs lfg ilvl 30`, `/qs lfg level 20 30`, `/qs lfg unknown invite|skip`.
- New **Item levels of other players** (Settings > Party window), like GearScore did: players you target or point at nearby (out of combat) are inspected and their average item level is remembered for 14 days; Quest Sharing users answer "what is your item level?" and share the numbers they remember. `/qs ilvl` shows yours. The armory cannot be read from inside the game (addons have no internet).
- Quest guide: quests that ask you to pick an item up from the world (a flower, a crate, a chest) are now planned properly. They are priced at a few seconds per pickup instead of a guessed minute, the guide sends you to the nearest such object instead of a far cluster, a pickup that lies on your way is taken on the way, and the step reads "Pick up <item>" instead of "Collect <item> from <item>".
- Settings: every saved option now has a control in the window (a new test fails if a future option ships without one). New **Quest items > Move the item button back to its starting position** (the item button had no way back after a shift-drag).
- Sell gray items is off by default; a vendor visit with it off now says once per session how many gray items could be sold and how to turn it on (`/qs sellgray on` or Settings > Bags), instead of doing nothing silently.
- Bag arranging options (Settings > Bags > How to arrange my bags): **Order items by** Topic (as before), Quality (best first) or Name (A to Z); **Bags to arrange** All bags, Bags without the backpack, or Backpack only (the others are left alone); **Where items gather** start or end of the bags; **Leave bookmarked items where they are** (off by default). Slash: `/qs sort by topic|quality|name`, `/qs sort bags all|bags|backpack`, `/qs sort from start|end`, `/qs sort keep on|off`. The done message says the order used ("bags arranged by quality").
- Quest guide map: step numbers are now round gold-ringed coins in the classic WoW style: a dark outline, a gold ring and a deep-brown face with a larger cream number. A spot shared by several steps stretches the coin into a pill with round ends, and the selected step is a slightly larger coin with a bright gold ring and a gold number.
- Quest guide map: a step number for a quest giver or turn-in now hangs slightly up and to the right of the spot (8 px, at every zoom), so the game's own ! and ? icon no longer covers it. Camp markers stay exactly on their camp.
- Settings: the bag helpers (Space bookmarks, sell gray items, arrange bags) now have their own **Bags** category instead of sitting at the bottom of Quest items; the window is 26 px taller to fit it. Two settings that only had a slash command or no control now show in the window: **Pings > Enable quest pings** (`/qs ping on|off`) and **Quest sharing > Seconds to wait after the party forms** (1-30, default 5).
- Lower memory use: the Dungeon quests, Quest rewards and map-search catalogues now free themselves two minutes after their window or search closes (reopening inside those two minutes is still instant; later it re-reads in the background as before), and switching Quest rewards off frees its half-read list at once. The debug log keeps 1,000 lines instead of 3,000 (still on by default). New `/qs memory` shows what Quest Sharing and QuestieDB use and which catalogues are loaded.
- Cleanup, no visible change: removed code nothing used (an unused outbox clear, an error-lines helper, a panel-click helper and a few unused tables and helpers) and the one-time upgrade steps for saves from 0.4.11 and older. A very old save now keeps its choices instead of having a few switched once; the saved settings of current versions are unaffected.
- Removed the profession **Upgrades** guide (the Upgrades tab in the game's profession window, the "Upgrades" card in Settings > Professions & character, and its bundled trainer/rank data). `/qs professions` with no argument now opens the Cooking recipe list; `/qs professions on|off` is unchanged. Trainer icons on the map are not affected.
- Bag helpers, each with its own switch. **Bookmarks** (Settings > Bags > Bookmark bag items with the Space bar, `/qs bookmarks on|off|list|clear`, on by default): point at an item in your bags and press Space (again to remove); it shows a small note icon and is never sold by the addon. **Sell gray items** (Settings > Quest items, `/qs sellgray on|off`, off by default): when a vendor opens, every gray item is sold except bookmarked ones and gray items a quest still needs. **Arrange bags by topic** (Settings > Quest items, `/qs sort on|off` for automatic, `/qs sort` or the Arrange button for once, automatic off by default): all your bags, the backpack included, are ordered as one bag (quest items, consumables, equipment, materials, recipes, other, gray items), a few seconds after they stop changing and never during a fight; quivers and profession bags are left alone.
- **Block the chat box during combat** (Settings > General > During a fight, `/qs chatlock on|off`, off by default): the chat box cannot be opened while you fight, and an open one closes when the fight starts. The quick chat ring still sends its messages.
- Travel map: choose whose transports and towns to show (Settings > Map > Whose boats, zeppelins and towns to show: Both factions, Alliance only or Horde only). Neutral boats, zeppelins and towns now draw in white, with a white pin and a white line, and always show. Dungeon hover shows only the chosen faction's closest town.
- Travel map: transport pins now sit above the game's own city icons and above your trainer icons, so a zeppelin tower at the Undercity (or any town icon) can be hovered and shows its route; a trainer standing on a transport is moved beside it.
- Gathering items now tell you where to get them. With "Show where items come from when I hover over them" on, hover a hide, leather, cloth, meat, herb or ore item in your bags or the Professions window and the tooltip lists the three zones with the most known spawn points of what drops it (creature, level range, zone, spawn count, drop chance when known). Ctrl+right-click the item to mark those spawn points on the world map with the item's icon and set the game waypoint on the first one; Ctrl+right-click again to remove them. Needs QuestieDB; the map must be opened by you (M). Hides and leather list the creatures you can skin for them (QuestieDB has no skinning data, so a small table from CMaNGOS classic-db is bundled); herbs and ore list their nodes; Cmd+right-click works on a Mac; `/qs gather` says why an item shows nothing.
- "Show where items come from when I hover over them" now also works in the Professions window: hovering a recipe's result or an ingredient there adds the "Questie sources" line, like it already did in bags. The old tooltip hook is not fired for those tooltips on this game version; the addon now uses the same tooltip-data hook as the cooking farm hints. Still needs the setting on and QuestieDB.
- Quest guide, Dungeon quests and map search now check your level, faction and place before they read QuestieDB's big tables, so they hold far fewer records in memory. **Quest guide:** a quest that needs another race, faction or class, needs more than one level above yours (the next level stays: XP can unlock it), is past its maximum level or is filed under a zone on another continent is ruled out by one small read each, before its quest givers and creatures are loaded; `/qs plan why` and the plan report say how many were not read ("Not read (one cheap check each): ..."), and those quests are no longer listed one by one under blocked. A level-up scans again. **Dungeon quests:** the tab opens for your character (faction, class and level) and reads only those quests; All quests, All levels or a higher level or other faction or class read the rest, and a narrower filter reuses what was read. **Map search:** item names are checked against what you type and the sellers of only the matching items are loaded (a longer text with the same words keeps the scan; other words scan again), the other faction's NPCs get no entry, and a "vendor" search no longer reads any item when your QuestieDB marks vendors with its vendor flag. The progress line now says "Searching ... items".
- Your own trainers are now on the map without searching: on any zone or continent map (not the Azeroth overview) every trainer for your class and for the professions you know, cooking, fishing and first aid included, that your faction can use gets a gold-rimmed icon (the class icon, or the profession's tool). Hover for names and places, click to set a waypoint; trainers standing together share one icon. Needs QuestieDB; the first map you open reads its trainer list in the background. Switch off with Settings > Map > Show my class and profession trainers on the map.
- Cooking trainers and food or drink vendors no longer share one icon: the cooking pot is for the trainer, vendors show the bag.
- The world map now marks every dungeon and raid entrance with a skull and every boat, zeppelin and Deeprun Tram stop with a lettered square (blue Alliance, red Horde, gold both). Hover a transport stop to see where it goes and the lines to its other stops; hover a dungeon to see its instances and level ranges and, for each faction, the closest town with a flight master it can use, with a line and a label to each. On by default (Settings > Map > Show dungeons, boats and zeppelins on the world map); needs no QuestieDB. Positions are approximate.
- Regrouped the settings by topic. The sidebar now has six groups: **Basics** (General), **Questing** (Quest markers, Quest list, Accept & turn in, and the new **Quest items**), **Party** (Quest sharing, Party window, Pings, Quick chat), **Map & route** (Map, Quest guide), **Look up** (Items & dungeons, Professions & character) and **Help** (Errors & logs). The old **Extra tools** and **Browser DB** grab-bags are gone: Bag cleanup moved to Quest items, Quest invitation to Quest sharing, Cooking recipes and Profession upgrades to Professions & character, and the quest-item switches that sat beside Pings have their own tab. The Quick chat key and its Preview ring button now live only in the Quick chat tab.
- New **Settings > Errors & logs** tab: Check my setup (`/qs doctor`), the errors the addon recorded with Show/Clear (`/qs errors`), the log with the recording switch and Show/Clear (`/qs log`), Copy logs, errors and setup, and Reset everything. These used to be scattered at the bottom of General.
- Map search pins now show what you searched for instead of one gold coin: class trainers show their class icon, profession trainers and supplies their tool (pickaxe, anvil, herb, needle...), innkeepers the hearthstone, flight masters a map, bankers and auctioneers a coin, weapon and armor masters a sword or shield, other trainers a book, and everything else a bag.
- Two shortcut buttons now sit beside the Quest Sharing minimap button: a map icon opens the Quest guide (quest optimizer) and a key icon opens Dungeon quests, so you no longer search the menus. They move with the main button when you drag it, and hide with it (`/qs minimap off`).
- Dungeon quests: the two filters are now check boxes: **Hide completed quests** (it also hides earlier steps that a finished later step made pointless) and **Hide quests in my log** (hides quests you have already taken). Quests that are in your quest log show a yellow "!" instead of the picture, and say "In your quest log"; quests you still have to pick up (not done, not taken) get a gold border. The line under the list explains the gold border, the "!" and the green tick.
- Dungeon quests: all nine new WoW Forever dungeons are listed: The Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of Dalaran, The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold and The Shaper's Terrace. Questie files no quests under most of them, so the tab now also uses Wowhead's per-dungeon quest lists ("Every Dungeon Quest in WoW Forever" and the Blackmaw Hold guide, 367 quests over 27 dungeons, in the new `DungeonQuestData.lua`). This also adds quests Questie files outdoors to the classic dungeons (for example Uldaman 35 quests, Sunken Temple 18, Zul'Farrak 16, Stratholme 26).
- Dungeon quests: many dungeons were missing. The dungeon list was a fixed table of 23 areas. It now also reads QuestieDB's instance list (every 5-player dungeon, raids and battlegrounds left out), so quests filed under a dungeon's second area id count too (for example Uldaman's quests use 1517, Gnomeregan's 133, Dire Maul's wings 10022-10027). Forever dungeons are added: City of Dalaran, The Hall of Thanes, Manor Mistmantle, plus the Forever Blackrock Depths and Blackrock Spire areas. Creatures in a Forever dungeon's sub-area (Excavation Site: Lost Marsh, Stalkers' Thicket, Site of the Guardian, Lost Dig Site; Ruins of Lordaeron: King's Alley, Graveyard, Lordamere Overlook, Market Street; City of Dalaran parts) now count for that dungeon.
- Route window polish: it says **nothing left to pick up** when every quest you can take is done or in your log (instead of routing you to the entrance), and **Can't plan from here** inside a dungeon. Dungeon entrances now come from QuestieDB's own dungeon list first, so Forever dungeons such as the Excavation Site get an entrance step. Walk steps say where the NPC stands (zone and coordinates), and each pickup or hand-in counts about 5 s in the total time.
- Dungeon quests: new **Plan route to get them all** button. After choosing a dungeon it opens a read-only route window with the shortest way to pick up every quest of that dungeon you can take now, starting where you stand: walking (or riding from level 40), the flight paths you know, boats, zeppelins and the Deeprun Tram, and your hearthstone once when it saves time and is ready. Talk-only lead-ins (like Seeking Caitlin) are taken and handed in on the way, before the quest they unlock; the route ends at the dungeon entrance. Steps are numbered with an icon and an estimated time, pickups at the same NPC are grouped (hover for the quest names), and clicking a step puts a pin on your world map. The window also lists quests to do first (they need a kill or collect quest before), quests that cannot be placed on the map, and how many need a higher level, another class or the other faction. Flight paths you know are learned each time you open a flight master; until then all of your faction's paths are assumed, and an **Assume I know all flight paths** check box forces that. Quests for another class no longer get the gold "to take" border, and their status says **Not for your class**.
- Dungeon quests: every kind of keyword now has its own colour, in the list and in the details panel: NPC names (teal on the panel, white in the list), places and coordinates (brown-orange / light orange), numbers such as counts, levels, XP and reputation (magenta / pink), quest names in the chain (crimson), objective items (amber), the dungeon (navy), and done / in your log / blocked states (green / amber / red). The quest's objective text colours its numbers, NPCs, items and dungeon inside the sentence. The quest name, the status, the section headings, the *Pick up from* / *Hand in to* lines and the XP line are bold. Labels in More details are dimmed so the values stand out.
- Dungeon quests: the quest details panel is rebuilt to be read in a few seconds. The quest name is the header; a coloured status strip says the one thing to know (**To pick up**, **In your quest log**, **Done**, **Skip it**, **Needs level 40**, **Not for your faction**); then **What to do** (the quest's own objective text, in large type), **Where** with *Pick up from …* and *Hand in to …* lines you can click to put a pin on your world map, **Rewards** with XP in large type, reputation, and up to six item rewards with icons and quality colours (hover for the full item tooltip with stats and comparison, shift-click to link in chat), **Quest chain** with plain *Before:* / *Next:* lines marked done or in your log, and only then the small print under **More details** (faction, class, quest ID, prerequisites, Questie data). The separate "Show pickup on map" button is gone: the pickup line is the button.
- Dungeon quests: rewards are visible without hovering. Each row shows the quest's XP (reduced for your level when the quest is 6 or more levels below you, using the classic falloff), and the right panel has a **Rewards** section with base XP and the amount at your level, reputation gains, and the item rewards (loaded the first time you click a quest; the panel fills in when they are ready). Money rewards are not in Questie's data, so they are not shown.
- Dungeon quests: a chain that fits on one page is never split across pages any more (the page before it ends early, so a step is always shown under the step it needs). Hovering a quest now also says "Not needed", "Completed" or "In your quest log".
- Dungeon quests polish: a lead-in is labelled "optional lead-in" even when it is itself listed for the dungeon; the gold "to take" border now marks only quests your character can take now (a quest above your level shows its requirement in red, a quest for the other faction has no border); "req 0+" is gone (the panel says "no level requirement"); the panel says "Not needed" instead of "Done" for a quest you skipped, and marks next chain quests "- done" or "- in your quest log"; the legend under the list is shorter.
- Dungeon quests: a lead-in or earlier step is now also greyed with a green check ("Not needed (next step done or taken)") as soon as the quest it leads to is in your quest log, not only after you finish it, because the game stops offering it then (for example Llana no longer gives Seeking Caitlin once you have Caitlin Grassman's quest).
- Dungeon quests: fixed "Seeking Caitlin" (and quests like it) still being offered as a quest to pick up for the dungeon after you had done the quest she sends you to. Questie holds no link at all for these "go and speak to X" quests, so the list now infers it: a talk-only quest that starts a chain and ends at an NPC who offers a quest of the same dungeon (with no prerequisite of its own, for the same faction) is nested above that quest and greyed with a green check once it is done. The right panel's "Questie data:" line says when a link was guessed this way. Only quests handed out by an NPC are treated this way, so a final "return to X" step started by an item (for example Fallen in the Fen) is never greyed because X's first quest is taken.
- Dungeon quests: the right panel ends with a "Questie data:" line listing the raw chain fields Questie holds for the quest (previous, next, breadcrumb, available-until, exclusive, parent), so a wrong chain can be diagnosed from a screenshot.
- Dungeon quests: a lead-in that Questie lists as only one of several "any one of" prerequisites of a dungeon quest is now also ticked green and greyed ("Not needed") once every quest it leads to is done, not only when the later quest strictly needs it. The previous/next chain lines in the right panel now say "- done" for finished quests.
- Dungeon quests: fixed "go and speak to X" lead-in quests (like Seeking Caitlin) being missing or shown as standalone. Questie often records them only on the earlier quest (the next quest does not list them as a prerequisite), or as breadcrumb / "available until" quests; these are now listed with the dungeon quest they point to, labelled "Chain quest: optional lead-in", nested above it, and ticked grey as "Not needed" once that quest is done.
- Dungeon quests: chain quests are now nested in the left list. A step sits directly under the earlier step it needs, one tab deeper, so you read a chain top to bottom. A finished step gets a green check mark and grey text, and so does every earlier step of a chain whose later step you have finished (for example the "go and speak to X" step that only leads to a quest you already did), marked "Not needed: a later step is done", so you do not travel to a giver who has nothing left. A later step only counts when it truly needs the earlier one: finishing a quest reachable through "any one of" several prerequisites does not tick them. Clicking a step shows only that step in the right panel (its previous and next chain quests and whether it is done), not the whole chain. The right panel drops its textured picture and keeps the plain yellow parchment. Quest names and places are easier to spot: in the list the quest name is gold, Pickup is light blue and Turn-in light violet; in the panel the quest name is crimson, Pick up lines deep blue and Turn in lines purple.

## 0.4.22
- New **Settings > Quest guide** tab holds every quest guide option in one place: the on/off switch with Open plan, the goal (Complete zone, Quest XP/hour, Chosen quests, Time limit), the time limit minutes, the chosen quest IDs, the level range, Mark selected camp busy, Clear camp waits, Reset learned pace, Show plan report and Copy plan debug. The goal, minutes, IDs and level range are now saved between sessions (they used to last only until you logged out), the open guide replans as soon as you change one, and `/qs plan xp`, `/qs plan budget 30` and `/qs plan range` save them too. The guide's Plan button and `/qs plan options` open this tab; the small options window inside the guide is gone, and `/qs plan why` or Show plan report opens the report window.
- The quest guide now learns your pace. While it is open it times your kills and your quest giver visits; after 5 of each, your own median time (4-40 s per kill, 1-15 s per quest giver) replaces the default 10 s and 3 s, so route estimates fit how you play. Settings > Quest guide shows the times in use, Reset learned pace forgets them, and the plan report states them.
- The quest guide now chooses *where* to do each kill or collect step, not only the order: it considers up to four real camps per step and picks the one that suits the route, so it prefers a camp next to the hand-in or one you are already farming for another quest. Camps are now grouped per creature, so two quests on the same mob point to the same camp and share their kills.
- The quest guide now improves its route after showing it: a background local search (moving short runs of steps and reversing short segments, each change fully re-checked for prerequisites, log slots and budgets) removes detours the nearest-first route leaves, in zones of any size, and swaps the better route in while keeping your selected step.
- Kill and collect steps no longer always switch to whichever camp is nearest to you; the route decides among the real camps.
- Fixed the Adventurer's Journal tabs (Dungeon quests, Quest rewards, Instance drops) opening as an almost empty black page with only the top dropdowns and the Character level box: the restyled text boxes set their font in a way the game client rejects, which stopped the window from building its list, buttons and details. Dropdown option lists open again too.
- Redesigned every Quest Sharing window in the classic WoW menu style: fully opaque dark stone inside the gold dialog border (settings, Adventurer's Journal, reports, fishing, cleanup, Party quests, quest guide, quick menu and map panels), red-and-gold Blizzard panel buttons, recessed black edit boxes and warm brown setting cards instead of the see-through dark-blue look.
- Redesigned the settings window for clarity in classic WoW gold: the twelve categories on the left are grouped under gold captions (Basics, Questing, Group play, Map & route, Look up & tools), the open category is gold on a gold wash, and its settings sit in a recessed panel. Every setting name is gold, values are white, explanations are soft white, and section headings are larger. The picked choice of a multiple-choice setting is lit with a gold rule while the others are dimmed. All blue text is gone from the settings window and the quick chat message editor.
- Quest guide: the step you choose (arrows, `/qs plan next`, a map click) stays selected when the background refinement swaps in a better route.
- The quest guide no longer uses Shortest Path Forever walking estimates to choose camps or order steps (SPF is only used for the optional Follow arrow), so the guide behaves the same with or without it. An objective keeps the camp it chose until another one is clearly cheaper (by a quarter of the visit's cost and at least 20 seconds), so it no longer flips between two camps as you walk.
- Quest guide: a camp that two creatures share (for example 2 + 2 spawns) counts as a real camp again, so its quest no longer disappears and the guide no longer sends you to a far single-creature camp instead.
- Quest guide: the background route refinement yields more often and runs again only when your quests, goal or level range change or after you move about a tenth of the map.
- The background route refinement now runs only when no other data work is waiting, so map search and the dungeon scan keep full speed while the guide is open. A map search that stopped on an internal error now retries when you search the same text again.
- "Camp busy 5 min" now also works when the guide sent you to an alternative camp. A busy camp gives way to a free one, and when every camp is busy the guide waits for the one that frees up first. The camp used only because of the busy mark is not kept: when the wait ends the guide returns to the camp it chose before, and **Clear camp wait** lets it choose afresh.
- Fixed map search showing no suggestions while typing (since 0.4.19). The first letter you type now starts reading the QuestieDB catalogue once, in larger slices while the map is open. Nothing is read on login, on a blank map, in combat or with the map closed, and later keystrokes continue that work instead of restarting it. Suggestions appear as soon as the first match on the shown map is found, earlier suggestions stay visible while you refine the text, and the panel shows progress such as "Indexing 3,200 / 10,122 NPCs". Vendor locations already read are kept between keystrokes; this cache is bounded and is cleared on a map change, on Clear, or when the database goes away. With a Classic-size database the first suggestion now arrives about 0.3 s after you stop typing (was about 3 s); item searches take about 1.4 s (was about 8 s).
- Dungeon quests: the quest right-click menu no longer closes by itself 0.2 s after any quest-log update (kills, loot, accepting a quest). It now closes only when its quest leaves the list, for example when you turn it in while completed quests are hidden. Menus opened from other Quest Sharing windows are no longer closed when the quest log updates.
- Quest guide map: the numbered step markers on the world map no longer slip under the map's own pins or other addons' pins. They now always draw on top, also after the map changes its layering or is closed and reopened. They are also easier to read: larger outlined numbers with a shadow on a dark solid face with a bright light-grey border (gold for the selected step), on a slightly bigger marker that keeps the same size at every zoom level. Markers that would overlap their neighbours merge into one label instead.
- Quest guide: the route no longer jumps between two nearly equal orders as you move. The previous order stays unless a new one hands in more quests or saves at least 12 seconds (or 5 % of the route's time, never more than 60 seconds). For the XP goal, a new order must earn at least 5 % more XP per second.
- Quest guide: the background polish reorders the whole route when it has up to 40 actions (about 13 quests) and only your next 12 actions on longer routes; later steps are polished as you get to them. On a 50-quest zone this cuts the background work by about three quarters.

## 0.4.21
- Fixed the quest guide's first step landing on your own character and following you as you walked. Kill and collect steps now go to the nearest real camp (a group of at least three spawns, or the mob's biggest group) instead of the single spawn nearest to you, and switch only when another camp becomes nearer.
- The quest guide now plans only the zone's own quests, the ones Questie files under the current zone or its sub-zone maps. Class, profession, event and other-zone quests stay out even when their giver or one stray mob spawn is here; a quest from another zone appears only for its hand-in here once it is ready, including breadcrumb quests with no objectives. `/qs plan why` lists the quests left out and why.
- Made **Dungeon quests** usable sooner on first open: the visible list now reads the quest catalogue in larger time slices than background work, and closing the window, pressing Esc or switching tabs pauses the scan so reopening continues it instead of restarting. Disabling Quest Sharing or **Refresh data** still discards it.

## 0.4.20
- Added predictive zone planning with complete-zone, quest-XP/hour, selected-quest and time-budget goals, local chains, OR prerequisite choices, reputation and known skill gates, carried-item and one-level XP state, shared single-loot-stream/kill estimates, two-drop uncertainty bounds, and bounded route search. The Plan menu shows estimates, data gaps, external requirements and a temporary camp-wait action; movement and visible progress trigger replanning through the shared worker. All acceptance levels are the default, with an explicit green/yellow option. Corrected sub-one-percent DropDB handling and preserved objective evidence. Flight routes, adaptive timing, larger-zone beam search and native game calibration remain open.

- Restyled all three search tabs as a WoW-style Adventurer's Journal: native red/gold controls, warm framed lists, item-slot borders, gold selection highlights, larger text and parchment quest/source details with dark ink. Dropdowns and search fields share the theme; filters, comparisons, quest actions and loading behavior are retained.
- Redesigned Extra tools into readable cards for the quest planner, bag cleanup, spell ranks, fishing spots and invitations. Added **Browser DB** for quest rewards, dungeon loot/quests, Cooking recipes, profession upgrades and item/vendor lookup controls; each card explains its purpose and data requirements, with separate primary actions and persistent switches. **Map** now focuses on zone levels and party locations.
- Made troubleshooting easier to read: a plain-language issue overview, newest-first numbered issues with repeat counts, separate setup notes, larger spaced text and optional full details in the same window. **Copy all** selects every retained error/stack/setting/log even from the overview; settings are one per line, snapshots stay stable until Refresh, and opening reports no longer dumps technical output into game chat.
- Replaced the standalone Cooking companion with views embedded inside WoW's profession window: one scrollable all-recipe list, grey clickable unlearned rows, separate skill/source labels, readable in-place acquisition/ingredient details, native crafting controls for learned recipes, and an embedded Upgrades page with direct faction choices. Preserves the selected unlearned recipe across native refreshes; never toggles native recipe filters or opens another addon window.
- Made dungeon quests easier to distinguish: separate chain/prerequisite/follow-up status and task labels, including **Talk only** with the NPC name, collection, combat, exploration, item delivery and events. Hover/details show known previous and next chain quests; five taller rows retain pickup and turn-in lines.
- Clarified that map search requires QuestieDB data, which can run without the full Questie addon. The map panel now explains missing/outdated databases with `/qs questie` and installation/reload guidance, clears stale results when data disappears, and retries the query when data becomes available; no catalogue scan for dependency checks.
- Enabled diagnostic recording by default, including a one-time migration for existing installs. `/qs log`, `/qs errors`, `/qs doctor` and the General report button now open one copyable setup/settings/blocked-feature/error-stack/debug-log snapshot with all retained entries, explicit refresh and combined clear; a later recording opt-out is preserved.

## 0.4.19
- Added a Cooking companion from the fishing panel, `/qs cooking`, and the native Cooking window: 133 Forever reference records, live Known/Missing/Unconfirmed states, acquisition sources and ingredient farming tooltips with Questie mob levels/locations, zone levels and available fishing skills. Added an **Upgrades** tab and `/qs professions` for static Alliance/Horde Apprentice-to-Artisan requirements, trainers, books and quests across all 12 professions; dated sources/unknowns, native guide buttons, refresh and an integration off switch. No native recipe-filter changes or login catalogue scans.
- Fixed guide positioning on submaps, automatic recovery when map measurements arrive late, and selected-stop labels/positions in grouped map markers; missing measurements retry at most once per second while the guide is active.
- Dungeon quest rows now show pickup and turn-in givers/locations; hovering shows base XP, all known item rewards and full locations. Reward links load only on first hover in cancellable background slices; six taller rows keep the new lines readable.
- Added **Dungeon quests** in the shared explorer and `/qs dungeons`: select a dungeon to list its quests inside/outside, outdoor preparation chains and explicit follow-ups, with faction/class/level/completion filters. Includes pickup/chain/objective details, the usual right-click menu and pickup map waypoints; scans only on demand with combat/close cancellation, independently of equipment filters.
- Added **Extra tools > Review quest items left in my bags** and `/qs cleanup`: Questie-backed carried-bag review, active quest/starter protection, individual whole-stack confirmation, fresh bag/quest/cursor checks, and client-refusal fallback; no background or bank scans.
- Added selected-step direction guidance above the guide: action/destination, facing-relative green arrow, direct yards and an arrival message without completing or skipping quests.
- Added own numbered world-map stops with readable straight connections and selected-stop highlight; click to select and waypoint, or cycle colocated steps. Cached drawing adds no database scans, hides map interactions in combat and stops on guide close; SPF remains optional for terrain-aware paths.
- Removed automatic guide/map catalogue scans on login and ordinary closed-tool events. Guide and map search share small time-budgeted work slices, suspend scans in combat, and stop work when hidden.
- Made map search debounced and lazy: reuse role metadata, load item links only when needed, decode only matching NPC locations and release locations after query changes. The guide reuses discovered IDs for its last two zones and caches repeated source reads during a scan; explicit Refresh rediscovers data.
- Restyled the planner as a compact dark quest guide with one gold/red highlighted current step, up to five muted upcoming steps, previous/next arrows, current-step counter, session position lock and mini/expanded modes. Added a Westfall UI emulation generated from actual Lua planner output.
- Fixed worldwide quests leaking into a zone plan through unrelated/zero map rectangles. Plans now require verified local locations, exclude remote-only new quests, clear stale steps immediately after zone changes, and prevent premature hand-ins/follow-up pickups.
- Replaced planner trip labels with numbered **Go to… → Take these quests → Complete these quests here → Hand in these quests** instructions, known place/giver names, consistent quest numbers and every grouped task shown.
- Made map role searches flexible: profession aliases such as **skinner → Skinning**, plurals, punctuation and word order; small spelling errors fall back to nearby role names with exact local matches taking priority. Suggestions use the same matching and item selections remain exact.
- Made map-search suggestions easier to read with an opaque dark background and border above map content, larger white text and wider, taller rows.
- `vendor` / `all vendors` now highlights all known sellers on the displayed map; `general vendor` narrows to local general sellers. Added provider vendor-flag support for sellers without titles, with trainers excluded from generic vendor results unless they also sell items.
- Map seller search now includes matching NPC titles without item links, scopes suggestions to the displayed map, keeps selected vendor types separate from item matches, and shows the map, query and location count. Off-map nearest searches require clicking **Elsewhere**; missing item seller data is explained.
- Validation: 44 automated suites / 1,617 checks and Lua 5.1 syntax checks pass. Native game rendering, live provider coverage, profession learned-state APIs and protected item deletion still require in-game validation.

## 0.4.18
- Made the quest planner movable; after you drag it, it stays where you placed it for the rest of the session.
- Fixed long quest names and wrapped details overlapping while scrolling; rows now grow to fit their text.
- Added a new-zone pickup list: available green/yellow quests appear line by line under their giver, even when you have no quests active. Right-click a stop to mark its location; open the map yourself to see the pin.
- The planner now uses WoW's quest difficulty colors to show only green and yellow quests. Empty plans explain when a zone is too low level or when quest levels/locations are unavailable.

## 0.4.17
- Shortest Path Forever is now an optional route engine for the quest planner: **Follow with SPF** (or `/qs plan follow`) draws guidance on the map/minimap, and its walking costs can promote the closest reachable first outing. Existing map-distance and waypoint behavior remains when SPF or its API is unavailable.
- Quest planner now builds on login/zone entry, updates after quest changes and progress, and groups giver-to-objective-to-turn-in trips from your current location; stops show trip numbers and known giver names.
- Replaced the large quest-plan window with a compact panel beside the quest tracker. Read the stops there and click one to put its marker on the map; the list scrolls for longer plans.
- Fixed the quest planner stopping after its last Questie batch; it now works only in outdoor zones, clears its plan in towns, and restarts when you change zones.
- Simplified world-map item search to one map view, moved the search box to the bottom-right, added an in-field search icon and Clear button, and made clearing the query hide its pins.
- Reorganized settings into clear categories with plain explanations, visible On/Off states, direct choices, separate +/- controls and scrolling pages. Fixed quest planner Questie data edge cases, distant-camp merging and safe next-stop handling.

## 0.4.16
- Added an optional quest planner to Extra tools and `/qs plan`. Questie prerequisites build up to four local quest layers; shared objectives and nearby camps become route stops, with pickups, objectives and turn-ins ordered by dependencies and straight map distance. Known Questie drop percentages are shown but do not affect route order. A selected stop can set a game waypoint. The planner is off by default and does not calculate walkable paths or cave/floor routing.
- Right-click a quest and choose **Ask in chat to do this quest** to fill the current chat with a linked question directly; press Enter to send. The optional role-play invite editor remains available in Extra tools and `/qs adventure`.
- Reorganized settings into clear categories with plain explanations, visible On/Off states, direct choices, separate +/- buttons, and scrolling pages. Quest markers, the quest list, and quest acceptance/turn-ins have their own categories. Existing saved settings stay intact.
- Made the enemy option say **Show ! above quest enemies** and explained that game nameplates must be on for it to work.
- Added optional Questie item-source hints and world-map seller search, including multi-word partial matching, autocomplete, map pins and a Sellers list with every known location. Item suggestions open the seller list; the Map tab shows matching pins.

## 0.4.15
- Added optional, independent quest-dialog automation switches under **Tracker**. Auto-accept accepts NPC and party quest offers when they are shown; auto-complete advances a ready turn-in and claims a reward when there is no choice or only one choice.
- Multi-choice rewards and quests that require paying money remain open for you. Both switches are off by default.

## 0.4.14
- Fixed world-map questing levels showing question marks across the map when the client supplies empty,
  zero or invalid level metadata. Includes standalone fallback guides for all 39 Classic questing zones,
  plus Zephras Isle and Riverglades; no additional addon is required.
- Mount Hyjal and Shen'dralas can show explicitly labelled **Known quests** spans from verified quest data
  when native ranges are absent. These describe known quests, not a complete recommended level bracket.
- Cities and Moonglade show **City** or **Sanctuary**. Hover/view a zone to see whether its fallback comes
  from a **Zone guide** or **Known quests**; valid native ranges still take priority and can arrive later.
- Zone levels remain optional/off by default. Unknown future areas retain an honest unavailable state;
  map navigation, click-through labels and the removal of quest/minimap symbols remain unchanged.

## 0.4.13
- Equipment explorer now shows **one row per item name** in both quest rewards and instance drops.
- Shared dungeon drops list every matching boss, creature or loot group together in the existing details pane;
  each supplier appears once with its combined difficulty labels. Shared quest rewards list all eligible routes,
  locations and prerequisites together. Counts and pagination refer to unique equipment names.
- Different item IDs with the same name stay together, with each version's level shown in details. Native
  tooltips compare the highest-level matching version. Quality, equipment, level, stat, source and quest
  eligibility filters apply before grouping, and selection survives newly loaded matching versions.

## 0.4.12
- Zone questing ranges are now **optional and off by default**, like other Extra tools features. Enable
  **Extra tools > Show zone questing level ranges** when you want the map badges and panel.
- Existing v0.4.11 installations are switched off once on update; your subsequent explicit choice is saved
  across reloads. Reset settings returns the option to off.

## 0.4.11
- Added **zone questing level ranges** to the world map, enabled by default with an **Extra tools > Show zone
  questing level ranges** toggle. Continent maps show a level badge over each mapped outdoor zone; a compact
  panel shows the selected or hovered zone's range. World/cosmic views prompt you to choose a continent/zone.
- Reads the game's player level ranges and zone bounds, including supported Forever zones, without requiring
  another addon. Missing/invalid ranges show **?** or **range unavailable**; no zone levels are guessed.
- Labels follow map size/zoom, remain click-through and hide when disabled or the map closes. Native map
  navigation, pins, quest symbols and minimap markers are not changed or restored.

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
