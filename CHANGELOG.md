# Changelog

## 0.3.2
- **Fixed "NamePlateX:GetCenter(): Can't measure restricted regions"** (shown when a fight starts or ends): to find
  the "nearest" quest creature, the ping key measured nameplates on screen, which the game forbids around combat.
  Now it never measures them: your target first (if it is a quest creature), then the creature the game soft-targets
  in front of you, then your mouseover, then one within about 28 yards; and nothing is refreshed as combat starts.
- **Fixed "protected function UNKNOWN()" in fights:** the quest icons over creatures were written onto the game's
  nameplates ("Lua Taint: QuestSharing"). They are now the addon's own frames, kept in its own list and only placed
  over the nameplates; none are made during a fight (new nameplates get theirs right after it). The quest item icons
  in the tracker are placed at a spot on the screen instead of being tied to the tracker's own buttons.

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
