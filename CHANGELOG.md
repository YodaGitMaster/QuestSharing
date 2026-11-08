# Changelog

## 0.2.0
- **A quest you finished is never shared, announced, listed or marked as something to do together** (one rule,
  `C.doneByMe`, used by the sharing rounds, `/qs share`, the left-click offer, "in common", the ring's `{shared}` /
  `{common}`, the Party quests window and Post all, the quest-log star and the map pin's preference). Clicking it in the
  game's tracker still says you are done. The "turn in!" hint is gone with it.
- **Right click opens a small menu** on a Party quests line: tell the party how I am doing, offer it, **tell them where
  to get it** (with Questie: quest giver, zone, coordinates and the quests that come first; or the item and who drops
  it), focus it on my map, open it in the quest log. Grey lines say why they cannot be used.
- **Questie support** (optional, read only): the QuestieDB API of Questie 12 (`QuestDB.Get`) and the older
  `QuestieLoader:ImportModule("QuestieDB")`, every call guarded; the row tooltip says where a quest starts.
- **Sound:** checked that the addon never changes sound settings or game globals; the quick chat now refuses keys
  the game uses for sound, music, volume or its menu; `/qs doctor` shows the game's sound settings; `/qs sound`.
- **You decide when to talk:** the automatic party chat ("in common", "done", "picked up") is **off by default** (and
  switched off once for existing settings). **Party quests window:** scroll down for all your quests in the zone below
  the 5 nearest; **left click offers** the quest to whoever does not have it; **right click tells the party** "I still
  need Wolf Pelt 2/4 (Wolf Pelt at 42.3, 61.8). What about you?";
  a grey dash for members who cannot take it; a note in raids.
- **Showing each other where you are:** the star over your head in a party (not in dungeons, never taken back from a
  tank), Quest Sharing users as class icons on your world map, a map pin where a teammate found the items, and the
  quest marker preferring the nearest quest you share. The ring's *Team up?* says "Doing [your quest] here - anyone
  want to group up?" in /s.
- **The Party quests window is a grid:** *Quest | member 1 | member 2 ...*, with a check (has it), a gold check (has it
  and finished it), an X (does not have it) or a ? (the game cannot tell: out of range, offline) under each member.
  It always shows **your 5 nearest quests**, re-sorted every few seconds as you move; a quest only moves up when it is
  clearly closer, so the rows do not flicker. Post all posts the quests someone in the party has.
- **Playing together:** "Picked up [quest] - Anna has it too. Want to do it together?" when you take a quest someone in
  the party has (one message per quest giver, once per quest, never for shared quests or ones just named in chat).
  **Where the quest items were**: for collect / use objectives the spot of your last progress is added to your done and
  progress messages while someone in the party still needs it. A **budget** for automatic party messages (4 a minute)
  and at most two lines for "in common". Settings > Sharing > Party chat; `/qs pickup`, `/qs coords`. The "Party
  window" tab is now "Party" and also holds the quest-click settings.
- **Fewer messages, and several Quest Sharing users in one party work together.** A quest one of you offered is
  not offered again by the others (an `O|` sync message), and every offer is checked again right before it goes out;
  accepting a shared quest no longer makes your addon offer it around and announce it. The "in common" message and
  the "done" message are said once for the whole party: the addons take turns in alphabetical order and leave out
  what someone already said in party chat. Your own chat: the per-answer lines and the `verbose` setting are gone,
  automatic rounds start silently and end with one short line only when something was shared, and the tracker pause
  is explained once per session. The start line of `/qs share` counts only quests that can be shared.
- **A more beautiful, easier addon.** A four-step start in the README and a welcome in chat (once; after an update, a
  short "what's new"). The settings window has the game's dialog look, six tabs that each open with one line on what
  they are for, sections, real check boxes, `< choice >` and `- number +` controls, a grey line under every setting,
  buttons for actions, and greyed lines while the addon is off. **Set the quick chat key by pressing it.**
  **Check my setup** and **Show the ring** are one click away.
- **Party quests window:** a header with the number of quests in common and **Share**, **Post all** (every shared quest
  in one chat message) and **fold** buttons; names in class colour with a **QS** tag for Quest Sharing users; striped
  rows; it **hides during combat**, has a **size** setting and a **move back** button.
- **Quick chat ring:** each dot has the colour of the chat it goes to (party blue, whisper pink, say white, yell red);
  the middle says where the message goes; three ring sizes.
- **Map button tooltip** with a live status (party, quests in common, tracker, your key, problems). It used to show a stray
  `\n` in its text.
- A **soft sound for good news** (someone accepted your quest, a party member finished one you share), never in combat.
- **Quick chat ring** (hold a key, point, release or click): a clean ring with short labels, editable messages and
  placeholders, a whisper to the player you target, and `/say` sent on a click or key press (the game forbids it from a
  release); light on the game (messages are only filled in when you point at them); with a stranger the
  message is a question that links your quests of the area; an `@invite` action invites your target to your party
- **Tracker follows you**: keeps the quest tracker on the nearest quests (distance mode, or zone mode on clients that
  cannot measure distance); steps aside for 10 seconds (a setting) when you change the tracker yourself, with or without game events
- Once a quest is finished, the messages no longer add "Anna has it too!" (the finished-quest announcement and the
  status you share by clicking). It is still said for quests you are working on.
- **Party quests window redesigned**: a row of class icons for who has each quest, the quest name, and your own
  progress; hover for everybody's progress, click to tell the party how you are doing.
- Long messages are cut without breaking a quest link or an accented letter, and a `|` you type is escaped: the game
  refuses all three otherwise. The Party quests window first opens on the left instead of mid-screen.
- Clicking a quest (the game's tracker or a Party quests row) **adds** its status to the chat box instead of replacing
  it: click several, press Enter once. No raw `{rt1}` in the chat box any more. A Party quests row now does exactly
  what a tracker click does (fills the chat box by default) instead of sending at once.
- Every quick chat message has its own channel, picked in the editor (a Channel row under the selected message) or with
  `/qs quick route N auto|nearby|say|yell|party|whisper`. *Hello* and *Team up?* are Nearby (`/w` your target, else
  `/s`, never the party); the rest is Auto (party, else `/w`, else `/s`).
- Quick chat "auto" goes to the party first (`/p`), then a whisper to a targeted player (`/w`), then `/s`.
- If the game blocks a send from the ring ("protected function UNKNOWN()"), the sentence is put in your chat box so you
  only press Enter, and `/qs errors` says which message was blocked;
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
