# Changelog

## 0.2.0
- **Quick chat ring** (hold a key, point, release or click): a clean ring with short labels, editable messages and
  placeholders, a whisper to the player you target, and `/say` sent on a click or key press (the game forbids it from a
  release); light on the game (messages are only filled in when you point at them); with a stranger the
  message is a question that links your quests of the area; an `@invite` action invites your target to your party
- **Tracker follows you**: keeps the quest tracker on the nearest quests (distance mode, or zone mode on clients that
  cannot measure distance); steps aside for 10 seconds (a setting) when you change the tracker yourself, with or without game events
- **Party quests window redesigned**: a row of class icons for who has each quest, the quest name, and your own
  progress; hover for everybody's progress, click to tell the party how you are doing.
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
