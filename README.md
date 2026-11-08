# Quest Sharing

A World of Warcraft addon for playing quests together.

1. **Shares your quests, once, at three moments only:**
   - when you **join or form a party** (your quests in the current area),
   - when a **new member joins** (only what that person has not been offered yet),
   - when you **accept a new quest** while in a party (just that quest; several accepts within 3 seconds
     become one round).

   Within one round the quests go out a few seconds apart (`/qs gap`, default 4) so nobody is flooded with
   popups. That spacing applies only inside a round: **nothing is ever repeated on a timer.** A quest is
   offered to each member at most once, and a quest someone **declined** is never offered to them again
   automatically. `/qs share` is the manual override that repeats everything. Afterwards it tells the party
   which quests you have in common:

   > Hey Anna! Looks like we have these quests in common: [Wolves Among Us], [Report to Goldshire] Let's do them together :)

   It also shows you, privately, who accepted, declined or already finished each quest you shared.

2. **Posts your progress when you click a quest in the tracker:**

   > /p {star} [Wolves Among Us] - still need: Wolf slain 3/8, Wolf Pelt 0/4 (Anna has it too!)
   > /p [Report to Goldshire] - I'm done with this one, ready to turn in!

   The star and the names appear only when a party member has that quest. Shift-clicking a quest link into
   the chat box appends the same status.

3. **Talks to other Quest Sharing users (sync).** Party members who also run the addon exchange their
   exact quest lists and objective progress in the background. For them "who has what" is exact instead
   of guessed, and no popup is needed to find out. Players without the addon still work (see below).

4. **Announces when a shared quest is done.** When all objectives of a quest that a party member also
   has are finished, it says so in party chat. Synced players also see `Anna finished the objectives of
   [Wolves Among Us]` on their screen when it is their quest.

5. **Shows who shares what.** A star and the names next to shared quests in the game's quest log, and a
   small movable panel (shown while you are in a party, drag it to move it; `/qs panel` hides it):

   ```
   Party: Anna (addon), Bob
   * Wolves Among Us: Anna 5/8, 1/4 | Bob has it
   * Report to Goldshire (done): Anna done
   ```

6. **Keeps your quest tracker on what is near you.** It is on by default; `/qs near off` stops it. It fills the
   tracker (the list on the right) with the quests closest to you and **re-checks every 2 seconds as you
   move**, so the list follows you instead of changing only when you cross into another zone.
   - **Distance mode** (needs a client that can tell how far a quest is) ranks quests by distance. A quest
     already in your tracker keeps its place unless another one is clearly closer, and a change must be
     seen twice in a row (about 4 seconds), so a short detour never reshuffles the list.
   - **Zone mode** (works on every client) tracks the quests of the zone you are standing in and swaps them
     when you change zone.
   - `/qs near N` sets how many quests it keeps (default 5, limited by the tracker's maximum).
   - It manages the whole tracker list while it is on, and **`/qs near off` puts your old list back**.
     If you change the tracker yourself it pauses for 5 minutes (`/qs near resume` to continue). It waits
     during combat and inside instances.
   - Note this fills the tracker list. It does not touch the single highlighted "waypoint" quest.

7. **(Beta) Adds the people you group with to your friends list.** `/qs friends` adds everybody in your
   party now. `/qs friends on` also does it automatically when a party forms or someone joins; this is
   **off by default** because it changes a list that matters to you. Safeguards: people already on your
   list and ignored players are skipped; players from another realm are skipped where the client cannot
   add them; random dungeon-finder groups are skipped in automatic mode; automatic mode never fills the
   last 5 friend slots; and the adds go out one every 1.5 seconds. Each add gets a note ("Quest Sharing:
   <zone>"). The game's answers (added, already a friend, not found, list full, other faction) are read and
   summarised for you.

8. **A quick chat wheel, like in Diablo 4.** Bind a key (Game Menu > Options > Key Bindings > Quest Sharing,
   or `/qs key V`). **Hold the key**: a wheel of up to 8 messages opens around the mouse. **Point at one and
   release the key** to say it. A quick tap opens the wheel and keeps it open so you can click a slot
   instead; Esc or a right click closes it. By default the wheel says:

   > Hey {name}! o/ - Want to quest together here? ({here}) - I need to: {need} - {shared} - Thanks! - Wait for me, one sec! - Follow me! - Ready when you are!

   Messages are filled in when you send them: `{name}` is the friendly player you target (or "there"),
   `{here}` your subzone or zone, `{need}` what you still have to do in this area (your unfinished
   objectives, nearest quest first where the client can measure distance), `{mine}` links to your
   unfinished quests of this area, `{common}` the quests you and your party share, `{quest}` the nearest
   unfinished quest, `{zone}` the zone, and `{shared}`, a whole sentence that fits the moment.
   **`{shared}` knows you cannot see a stranger's quests**, so with someone who is not in your party it asks a
   question that links yours (they can click a link and tell you): *"Are you doing any of these quests here?
   [Wolves Among Us], [A Personal Quest] Want to do them together?"*. Once you are in a party it says *"We have
   these quests in common: ..."*, or *"No quest in common yet - I'm on ... Any of these yours?"*. It goes to the party when
   you are in one, otherwise to everybody nearby (`/qs quick channel auto|say|party|whisper`; `whisper`
   sends it to your target).
   **Arrange them as you please:** `/qs quick` lists them; `/qs quick add <text>`, `edit N <text>`,
   `remove N`, `move N M`, `reset`; or `/qs quick editor` for a small window (click a line, change the text,
   press Enter, use Up / Down / Delete / Add).

9. **A minimap button.** Left click opens the settings window, right click shows or hides the
   quests-in-common panel, drag it around the minimap edge to move it (`/qs minimap off` hides it).
10. **An "Invite" action on the wheel.** A message that starts with `@invite` invites the player you target to
    your party and whispers them the rest of the text. The last default wheel slot is
    `@invite Sending you a party invite - let's quest together!`. It checks first that you have a target, are
    the party leader (if you are in one) and that the party is not full.
11. **Built-in help for problems.** `/qs doctor` shows what works on your client and opens the report in a
    window where the text is already selected (Ctrl+C to copy it). `/qs errors` shows any error the addon has
    caused (also kept between sessions). If something misbehaves in your game, paste the `/qs doctor` report
    into a GitHub issue.

## Settings window
**Everything is switched on by default.** To change anything, type `/qs settings` (or the minimap button, or click **Settings** on
the quests-in-common panel, or open *Game Menu > Options > AddOns > Quest Sharing*). Every line is one
click:

```
[ON]  Share my quests when I join a party or someone joins
[ON]  Share a quest when I accept it (in a party)
      Which quests to share: this zone only          (click to change)
      Seconds between shared quests: 4               (left click +, right click -, Shift = 5 at a time)
[ON]  Announce quests in common in party chat
[OFF] Sync quest lists with other Quest Sharing users
...
      Reset everything to the defaults (all on)
```
On/off lines switch with a click; lines with a choice cycle through the choices (right click goes back);
number lines count up with the left button and down with the right one. Hover a line for a short
explanation. The same things can be done with `/qs` commands, and a change in either place shows up in the
other at once. Settings saved by an earlier version get the new defaults (tracker and panel on); every
other choice you made is kept.

## Install
**Easiest:** download `QuestSharing-<version>.zip` from the GitHub *Releases* page, unzip it and drop the
`QuestSharing` folder into `Interface\AddOns`. Or:
1. Copy the folder `QuestSharing` (the one containing `QuestSharing.toc`, not this README's folder) into
   the game's `Interface\AddOns` folder, so you have `...\AddOns\QuestSharing\QuestSharing.toc`.
2. Start the game; on the character screen click **AddOns** and make sure **Quest Sharing** is ticked
   (tick **Load out of date AddOns** if the game says it is out of date).
3. In game type `/qs probe`. It tells you what your game client supports. **If something looks wrong,
   open an issue at https://github.com/YodaGitMaster/QuestSharing/issues and paste that output.**

## Commands (`/qs` or `/questsharing`)
| Command | What it does |
|---|---|
| `/qs share` | share your quests in this area with the party now, repeating earlier offers and declines |
| `/qs stop` | cancel a share in progress |
| `/qs on` / `off` | switch the addon on / off |
| `/qs auto on\|off` | share automatically when you join a party or someone new joins (default on) |
| `/qs new on\|off` | share a quest once when you accept it while in a party (default on) |
| `/qs area zone\|all` | share only this zone's quests (default) or every quest |
| `/qs gap N` | seconds between two shared quests (default 4, minimum 2) |
| `/qs chat on\|off` | announce quests in common in party chat (default on) |
| `/qs click on\|off` | clicking a tracked quest fills the chat box (default on) |
| `/qs link on\|off` | shift-click links get the status appended (default on) |
| `/qs mode box\|send\|print` | what a click does: **box** fills the chat box and you press Enter (default, so a stray click never spams), **send** sends straight away, **print** only shows it to you |
| `/qs sync on\|off` | exchange exact quest lists with other Quest Sharing users (default on) |
| `/qs announce on\|off` | say in party chat when a quest we share is done (default on) |
| `/qs markers on\|off` | star and names next to shared quests in the quest log (default on) |
| `/qs panel [on\|off]` | show the "quests in common" panel while in a party (default on); drag it to move it |
| `/qs near [on\|off]` | keep the quest tracker filled with the quests closest to you (default on) |
| `/qs near N` | how many quests it keeps (default 5) |
| `/qs near mode auto\|distance\|zone` | `auto` uses distance if your client can measure it, otherwise your zone |
| `/qs near now` / `resume` | refresh now / end a pause early |
| `/qs settings` | open the settings window |
| `/qs friends` | (beta) add everybody in your party to your friends list now |
| `/qs friends on\|off` | (beta) do it automatically when a party forms or someone joins (default off) |
| `/qs key [KEY]` | bind the quick chat wheel to a key, e.g. `/qs key V` or `/qs key ALT-E`; `/qs key none` removes it |
| `/qs quick ...` | the quick chat messages: `add`, `edit`, `remove`, `move`, `reset`, `editor`, `mode hold\|toggle`, `channel auto\|say\|party\|whisper`, `on\|off` |
| `/qs doctor` | a report of what works on this client, in a window you can copy from |
| `/qs errors [clear]` | errors this addon has caused |
| `/qs minimap on\|off` | the minimap button (default on) |
| `/qs reset` | put every setting back to its default (everything on) |
| `/qs probe` | show what this game client supports |

## How it knows
**Can we know right away that we have a quest in common?**
- **With another Quest Sharing user: yes, exactly.** Their addon sends their quest list (and progress).
- **Without the addon: probably yes for party members.** WoW has a call for it (`IsUnitOnQuest` /
  `C_QuestLog.IsUnitOnQuest`). Only a **yes** from it can be trusted: a **no** can also mean "the game has
  no data about that player yet". For quests the game does not confirm, the addon shares the quest and the
  reply decides: a player who has it answers "X is already on that quest".
  `/qs probe` runs a live test on your first party member so you can see whether it works on your client.

**Do we know whether they accept a quest we shared?**
Yes. The game answers every share with a system message per member: accepted, declined, already on it,
already completed, busy, quest log full, and so on. The addon reads them by the game's own message
strings (so it works in any language) and shows them to you.

## Known limits (please read)
- **Not tested in the real game.** Everything is tested in a Lua 5.1 interpreter against a mock of the WoW
  API (both the modern `C_QuestLog` style and the classic `GetQuestLogTitle` style, 351 tests), but I could
  not run it inside your client. The risky parts are what only the real game can show: whether the tracker
  click hook and the quest-log markers match your client's interface, whether the "right away" check works,
  and the exact wording of the game's replies. `/qs probe` is there to find out quickly.
- **Tracker clicks and quest-log markers** hook the game's own interface (modern tracker / quest log and
  the classic ones). If your client is different, `/qs probe` says `NO` for that hook. Shift-clicking a quest
  link into the chat box and the panel (`/qs panel`) work on any client. On the modern quest log the markers
  appear the next time the game redraws the list (open/close it or scroll).
- **Tracker by distance needs a client that reports quest distances.** WoW's modern interface does
  (`C_QuestLog.GetDistanceSqToQuest`); the classic one gives addons no quest locations at all, which is why
  addons like Questie carry their own database. On such a client `/qs near` falls back to zone mode.
  `/qs probe` shows `distance to quests: yes/NO` and which mode is in use. Quests whose next step is on
  another continent are ignored.
- **Quick chat key:** an addon cannot press a key for you, so you choose the key yourself. Pick one you do
  not need: for example **E is "strafe right" by default**; `/qs key E` tells you what the key used to do
  before it takes it over. Chat to nearby players (`/say`) is only allowed as the direct result of a key or
  mouse press, which is exactly what choosing a slot is. The wheel needs a free mouse pointer (not
  mouse-look). It is untested in the real game: `/qs probe` shows `quick chat wheel: key ...`.
- **Friends (beta):** the game's friends list is small (about 100) and, on classic-style clients, belongs to
  your realm, so players from other realms can only be added where the client allows it. Adding someone is
  silent for them. Whether `AddFriend` is allowed to an addon on your client is something only the game can
  tell: `/qs probe` shows `friends (beta): add call yes/NO`, and `/qs friends` reports what the game answers.
- **Sync only works between players who both run Quest Sharing.** Everyone else is handled by the
  share-and-read-the-reply method. Messages are small, spaced 0.4 s apart, and only go to your party.
- **Sharing pops up a window on each member's screen** for every quest they don't have; that is how WoW
  quest sharing works, and the game shares with the whole party at once (it cannot target one player). So
  when a new member joins, the others only see a popup for quests they do not have yet and have not
  declined. If you accept a quest that someone in the party shared with you, the addon offers it back to
  the party like any new quest; the person who shared it already has it, so they only get a short
  "already on that quest" reply. Raise the spacing with `/qs gap 8` if rounds feel too busy.
- **5-player parties only.** WoW cannot share quests in a raid group, so the addon stays quiet there.
- **The chat icon is the star.** A chat message can only carry the raid target icons; any other picture
  would show only on your own screen (the `print` mode and the panel do show it to you).
- **Classic-style quest logs hide quests under a collapsed zone header** from addons. Expand your zone
  headers if a quest is not being shared.

## Tests
```
pip install lupa
python tests/test_questsharing.py     # 63 tests: sharing, replies, announcements, tracker clicks, commands
python tests/test_features.py         # 50 tests: sync, completion, panel, quest-log markers
python tests/test_triggers.py         # 34 tests: when it shares (once per join / new member / new quest), no nagging
python tests/test_tracker.py          # 28 tests: the tracker follows you (distance and zone modes)
python tests/test_settings.py         # 36 tests: everything on by default, migration, the settings window
python tests/test_friends.py          # 42 tests: the friends beta (manual and automatic, safeguards)
python tests/test_quick.py            # 63 tests: the quick chat wheel, placeholders, editing, key binding
python tests/test_extras.py           # 35 tests: error log + doctor, invite action, minimap button, release zip
```
Expected: `63/63`, `50/50`, `34/34`, `28/28`, `36/36`, `42/42`, `63/63` and `35/35 passed`.

## Files
| File | Purpose |
|---|---|
| `QuestSharing/Compat.lua` | the only place that knows classic vs modern APIs |
| `QuestSharing/Core.lua` | settings, timers, events, chat queue, `/qs` commands |
| `QuestSharing/Share.lua` | party detection, the push queue, reading the game's replies, announcing quests in common |
| `QuestSharing/Sync.lua` | addon-to-addon protocol: hello, full quest list, updates (see the header of the file) |
| `QuestSharing/Progress.lua` | notices finished quests, announces them, sends changes to synced players |
| `QuestSharing/Panel.lua` | the "quests in common" panel and the quest-log markers |
| `QuestSharing/Track.lua` | keeps the quest tracker on the quests nearest to you (distance or zone mode) |
| `QuestSharing/Diagnostics.lua` | the error log, `/qs doctor` and the copyable report window |
| `QuestSharing/MinimapButton.lua` | the minimap button |
| `build_release.py`, `CHANGELOG.md` | builds `dist/QuestSharing-<version>.zip` and the release notes |
| `QuestSharing/Quick.lua`, `QuestSharing/Bindings.xml` | the quick chat wheel, its placeholders, the message editor and the key binding |
| `QuestSharing/Friends.lua` | (beta) adds party members to your friends list, with safeguards |
| `QuestSharing/Settings.lua` | the settings window (plain clickable lines, no game UI templates) and the options entry |
| `QuestSharing/Status.lua` | the status message, tracker / link hooks, `/qs probe` |
| `tests/` | the Lua 5.1 test harness with a WoW API mock, and the two test files |
