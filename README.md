# Quest Sharing

A World of Warcraft addon for playing quests together.

## Your first party, in four steps
1. **Install it** (see [Install](#install)) and log in. A short welcome in chat tells you it is ready. Everything is
   on, except the automatic party chat: **you** decide when to talk.
2. **Give the quick chat ring a key:** left-click the map button > *General* > **Quick chat key**, click, press the key
   (for example `V`, or `E` if you do not strafe with it).
3. **Group up.** Your quests of this area are offered to the newcomers (once each), and the
   **Party quests** window shows your nearest quests with a check or an X for every member. **Left click** a quest to
   offer it, **right click** to tell the party "I still need Wolf Pelt 2/4 (Wolf Pelt at 42.3, 61.8). What about you?"
4. **Talk with one key:** hold it, point at *Hello*, *Team up?* ("Doing [your quest] here - anyone want to group up?"
   in /s), *What I need*... and let go. Each message's channel is yours to choose in the settings.

Hover the map button any time for a quick status (party, tracker, your key, problems). `/qs doctor` checks your setup.

## What it does

**Your messages go into the chat box, and you press Enter.** Some game clients do not let addons send chat messages
at all (the game says "tried to call the protected function UNKNOWN()"), but typing into the chat box always works.
So what the addon writes for you (the right-click menu, quest clicks, Post all) is typed into the chat box with the
right channel set (`/p`, `/s`, `/w Name`, ...). The quick chat ring has its own switch and sends at once by default
(see below). *Settings > General > My messages* (or
`/qs mode send`) sends at once instead where the game allows it; if the game refuses, the addon switches back to the
chat box by itself and says so once. The automatic party messages need "sent at once" (typing them into your chat box
unasked would take your keys while you play).

**When the game refuses something** ("Interface action failed because of an AddOn"), `/qs errors` says what the addon
was doing at that moment ("while sharing a quest with the party", "while putting a pin on your map", ...) and
that one feature switches itself off until you `/reload`, so the message does not keep coming back. Its window also
says **where it came from**: the line of the addon that made the call ("from QuestItems.lua:150 paint"), the real
name of the function when the game only says `UNKNOWN()`, what the addon was running ("a timer set at
QuestItems.lua:342", "the event QUEST_LOG_UPDATE"), whether you were in combat, and the stack (what called what).
When none of the addon's code is on the stack, it says so (the game noticed it later, often "taint") and names what
the addon ran last. Lua errors keep their stack too.

**One rule everywhere: a quest you have finished is never shared, announced, listed or marked as something to do
together.** It is not offered to the party, not part of "in common", not on the ring's quest lists, not in the Party
quests window, not starred in the quest log, and not preferred by the map pin as a quest you share. (Clicking it in
the game's tracker still tells the party you are done, because that is your own choice.)

1. **Shares your quests, once, at three moments only:**
   - when you **join or form a party** (your quests in the current area),
   - when a **new member joins** (only what that person has not been offered yet),
   - when you **accept a new quest** while in a party (just that quest; several accepts within 3 seconds
     become one round).

   Within one round the quests go out a few seconds apart (`/qs gap`, default 4) so nobody is flooded with
   popups. That spacing applies only inside a round: **nothing is ever repeated on a timer.** A quest is
   offered to each member at most once, and a quest someone **declined** is never offered to them again
   automatically. `/qs share` is the manual override that repeats everything.

   **Where the game only lets an addon share from your own click** (it refuses an automatic share: "tried to call
   the protected function QuestLogPushQuest()"), the addon notices it, says so once and remembers it: a round then
   waits, and each click on **Share** in the Party quests window (or `/qs share`) offers the next quest; clicking a
   quest offers that one. *Settings > Sharing > Share only when I click Share* (`/qs shareclick on|off`) shows and
   changes it. If the game refuses even a share from your click, sharing switches off until you `/reload`.

   If you switch on the party chat
   announcement (**off by default**: *Settings > Sharing > Party chat*), it also tells the party which quests you have
   in common:

   > Hey Anna! Looks like we have these quests in common: [Wolves Among Us], [Report to Goldshire] Let's do them together :)

   Afterwards you get **one short line** (only you see it), and only when something was shared:
   `shared 2 quests with the party: Anna took 1, 1 declined`.

2. **Puts your progress in the chat box when you click a quest in the game's tracker** (the list on the right).
   **Click more quests and they are added**, not replaced, so you send them all with one Enter (the Party quests
   window has its own clicks: see below):

   > /p [Wolves Among Us] - still need: Wolf slain 3/8, Wolf Pelt 0/4 (Anna has it too!) + [Report to Goldshire] - I'm done with this one, ready to turn in!

   - The names appear only when a party member has that quest, and not once you have finished it.
   - A quest already in the box is not added twice. Anything you typed first stays; your status goes after it.
   - One chat message holds 255 letters; when the next one does not fit, the addon says so instead of cutting it.
     Press Enter, then click again.
   - Enter or Esc closes the box; the next click starts a new message.
   - `/qs mode send` sends it to the party at once instead (then the game shows a star when the party has the quest);
     `/qs mode print` only shows it to you. Shift-clicking a quest link into the chat box adds the status too.

3. **Talks to other Quest Sharing users (sync).** Party members who also run the addon exchange their
   exact quest lists and objective progress in the background. For them "who has what" is exact instead
   of guessed, and no popup is needed to find out. Players without the addon still work (see below).

   **When several of you run it, they take turns instead of all talking at once:**
   - **One popup per quest.** A quest one of you offered is not offered again by the others (their addons are told
     at once), and each addon looks again right before offering. Accepting a quest someone shared does not make
     your addon offer it around again.
   - **One "in common" message.** The addons go in alphabetical order of the players' names, a moment apart; each
     leaves out the quests somebody already named in party chat in the last two minutes, and says nothing if
     nothing is left.
   - **One "done" per quest.** When you finish a quest together (the last kill counts for everybody), only the first
     one says it.
   - **Your own chat stays quiet**: no line per answer, no line when a round starts; one line when something was
     shared; "the tracker paused" is explained once per session.

4. **Helps the party play the same quests together, without spam** (the automatic messages below are **off by
   default**; you talk with a right click in the Party quests window or with the ring):
   - **"Picked up [Boar Tusks] - Anna has it too. Want to do it together?"** when you take a quest from a quest giver
     and someone in the party already has it. Quests from one quest giver go into one message; each quest is said once
     per party; never for a quest somebody shared with you (they know), never for one somebody just named in chat.
   - **Where the quest items were.** For objectives you collect or use (items, objects, things to click), the addon
     remembers where your last progress happened and adds it to the messages you send anyway, but only while someone
     in the party still needs it: `[Wolves Among Us] - still need: Wolf slain 3/8, Wolf Pelt 2/4 (Anna has it too!) -
     Wolf Pelt: 42.3, 61.8 in Elwynn Forest`. Not for kills, not inside dungeons (no map spot there).
   - **A budget for automatic messages:** at most 4 a minute for the whole addon, and the "in common" message never
     takes more than two lines (the rest is "and 6 more"). What you send yourself (quest clicks, the ring) is never
     limited.

   `/qs pickup on|off`, `/qs coords on|off`, or *Settings > Sharing > Party chat*.

5. **Can announce when a shared quest is done** (off by default). When all objectives of a quest that a party
   member also has are finished, it says so in party chat, once for the whole party.

6. **Shows who shares what.** A star and the names next to shared quests in the game's quest log, and a small
   movable **Party quests** window (shown while you are in a party, on the left of the screen the first time; drag it
   anywhere and it stays there). It is a grid: **your 5 nearest quests** down the side, **one column per party member**:

   ```
   Party quests (2 of 5 shared)                 [Share] [Post all] [-]  Settings
   Quest                           [mage] Anna QS   [priest] Bob
   Wolves Among Us          3/8 +1        v              x
   Report to Goldshire        done        v*             ?
   A Personal Quest            ...        x              x
   ```

   - **v** (green check) = has the quest, **v\*** (gold check) = has it and finished it, **x** (red) = does not have
     it, **?** = the game cannot tell (the player is out of range or offline; players running Quest Sharing are
     always known exactly, **QS** after their name).
   - **Only the quests of the zone you are in**, never filled up with quests from elsewhere.
   - **Also when you are alone** (*Show it when I am not in a party too*, on by default; `/qs solo off`): then it is
     "Quests here", your quests of the zone with your progress, without member columns or party buttons.
   - **The 5 nearest quests, re-sorted as you move** (every few seconds). A quest only moves up, or onto the list, when
     it is clearly closer (about 20 %), so the rows stay calm while you walk. On a client that cannot measure distance,
     the quests of the zone you are in come first.
   - Your own progress is next to the quest name (`3/8 +1`, `done`); a finished quest of yours is green.
   - **Scroll down** (mouse wheel) for **all your other quests in this zone**, below the 5 nearest.
   - **Left click** a quest: it is **offered** to the members who do not have it (the quest popup; a click is your
     decision, so it is offered even to someone who declined before). It says why when it cannot: everybody has it,
     the game does not let this quest be shared, a share is already running, you are in a raid.
   - **Right click** a quest: a **small menu** opens (Esc or moving away closes it; a grey line says why it cannot be
     used right now):
     - **Tell the party how I am doing** (see below),
     - **Offer it to the party** (the same as a left click),
     - **Tell them where to get it**: with the [Questie](https://github.com/Questie/Questie) addon installed, the party
       hears where it starts, which quest comes before it, **where that earlier quest starts**, and how many steps lie
       before that: `Bob: [Wolves Among Us] starts at Marshal McBride in Elwynn Forest (48.9, 41.6), after "A Threat
       Within" (from Deputy Willem in Elwynn Forest (48.2, 42.9)), 1 more step before that.` (Also "starts from the item
       ..., dropped by ..." when an item starts it.)
     - **Trace back the chain** (with Questie): **one chat line** with the level it needs, every quest that comes
       before it from the first one, where that **first** quest starts, and where this one starts:
       `[Wolves Among Us] (level 5+): 2 quests before it: "Kobold Camp Cleanup" at Deputy Willem in Elwynn Forest 48.2,
       42.9 > "A Threat Within" > then this one at Marshal McBride in Elwynn Forest 48.9, 41.6`. "(or 1 other)" means
       another quest leads there too, "(+2 more)" that more quests are needed. It always fits one chat message: in a
       long chain the middle steps become "(5 more)", the first one stays. In a party it goes to the party (sent at
       once or into the chat box, like your other messages); alone it is shown only to you. Use it when a party member
       does not have a quest you have: they see which quest they still need first and where to get it.
     - **Focus it on my map** (the game's quest marker and arrow; the nearest-quest pin waits a minute),
     - **Open it in the quest log** (the old quest log window). Where the quest log is inside the world map, this is
       **Select it in the quest log**: the addon never opens the map itself (the game would refuse part of that in the
       addon's name: "protected function SetPassThroughButtons()"), so you press L or M.
   - **Tell the party how I am doing** sends at once:
     `[Wolves Among Us] - I still need Wolf slain 3/8, Wolf Pelt 2/4 (Wolf Pelt at 42.3, 61.8). What about you?`. The spot is added only for things you
     collect or use, and only while someone in the party still needs them; Quest Sharing users also get a pin there on
     their map.
   - A **grey dash** means that member **cannot take** the quest (did it before, quest log full, not eligible), so you
     do not keep offering it. Quests you have finished are not listed at all.
   - **Hover** a row for everybody's status and progress (and, with Questie, where the quest starts).
   - In a raid the window says so: the game only lets quests be shared in a 5-player party.
   - **Share** offers your quests of this area to the party now. **Post all** puts your progress on the quests someone
     in the party has in the chat box, in one message. **-** folds the window to its title.
   - It **hides during combat** and comes back afterwards, its **size** can be changed (70-150 %), it is as wide as
     your party, and *Settings > Party > Move back* finds it if you lost it.

7. **Shows each other where you are.**
   - **Quest Sharing users on your world map:** a class icon where each of them is (their addons send their position
     every 10 seconds while they move, at most once a minute when they stand still), and yours to them.
   - **A map pin where a teammate found the items** of a quest you still work on, when they right-click it in their
     Party quests window. `/qs waypoint off` stops that.
   - **The game's quest marker prefers a quest you share:** in a party it follows the nearest quest someone else also
     has, otherwise simply your nearest quest.

8. **Pings the quest target for the party** (where the game has its ping system: `/qs doctor` says so).
   Bind a **ping key** (*Settings > Tracker > Ping key*: click, press the key; or `/qs pingkey G`). Each press:
   - **the nearest creature one of your quests needs** becomes your target and gets the game's **Attack** ping, so
     the party sees what to kill ("nearest" = within about 28 yards, then the one closest to the middle of your
     screen: the game gives addons no distance to enemies);
   - with no such creature in sight, **the quest object you are facing** (the thing to pick up or use, with the gear or
     hand icon) gets the game's **"look here"** ping (*Ping quest objects too*, on by default).
   - **Anti-spam:** a new ping only once the creature you pinged is **dead** (or no longer your target), or, outside
     combat, after **5, 10 or 15 seconds** (*Ping again after*, default 10). **Shift** + the key pings anyway.
   - **Every press says what happened** (pinged, nothing to ping, held back), and the game's own ping errors are
     shown. **`/qs ping`** checks every step and says where it stops (the ping system, the key, quest creatures,
     enemy nameplates, what the next press does).
   - A message `@ping` on the quick chat ring is a **ping slot** (`/qs quick add Ping | @ping`): click it outside
     combat.

   Why a key and not fully automatic: the game lets an addon neither ping nor choose a target by itself; both only
   happen as the direct result of your key press or click. So the addon keeps a hidden secure button loaded with
   the nearest quest creature (outside combat; in combat it keeps the last one) and your key presses it. The
   anti-spam check runs inside the game's secure code, so it also works in combat (there it has no clock: in
   combat only "dead or no longer your target" and Shift unlock it).

9. **Quest items you can use, one click away.** The game's tracker shows a button only for the quest items it calls
   "special"; Quest Sharing adds an **icon next to the quest in the tracker** for the other usable quest items in your
   bags (a torch to light, a flare to throw...). Click it to use the item. Which item goes with which quest: the bag's
   own quest info, an objective that names the item, or (with Questie) the item the quest gives you or needs; items
   without a "Use:" effect get nothing, and quests that already have the game's button are left to the game.
   - **Quest item key** (*Settings > Pings & items*, or `/qs itemkey Q`): uses the item of your **nearest** quest that
     has one, also in combat (the item it had before the fight).
   - **A small button** with that item (Shift + drag to move it): cooldown, count, red when your target is out of range.
   - Using an item is protected by the game, so these are secure buttons prepared outside combat; during a fight they
     keep what they had and the tracker icons are put in place again afterwards.

10. **Keeps your quest tracker on what is near you.** It is on by default; `/qs near off` stops it. It fills the
   tracker (the list on the right) with the quests closest to you and **re-checks every 2 seconds as you
   move**, so the list follows you instead of changing only when you cross into another zone.
   - **Distance mode** (needs a client that can tell how far a quest is) ranks quests by distance. A quest
     already in your tracker keeps its place unless another one is clearly closer, and a change must be
     seen twice in a row (about 4 seconds), so a short detour never reshuffles the list.
   - **Zone mode** (works on every client) tracks the quests of the zone you are standing in and swaps them
     when you change zone.
   - `/qs near N` sets how many quests it keeps (default 5, limited by the tracker's maximum).
   - It manages the whole tracker list while it is on, and **`/qs near off` puts your old list back**.
     If you change the tracker yourself it steps aside for 10 seconds (a setting; `/qs near resume` to continue). It waits
     during combat and inside instances.
   - Note this fills the tracker list. It does not touch the single highlighted "waypoint" quest.

11. **(Beta) Adds the people you group with to your friends list.** `/qs friends` adds everybody in your
   party now. `/qs friends on` also does it automatically when a party forms or someone joins; this is
   **off by default** because it changes a list that matters to you. Safeguards: people already on your
   list and ignored players are skipped; players from another realm are skipped where the client cannot
   add them; random dungeon-finder groups are skipped in automatic mode; automatic mode never fills the
   last 5 friend slots; and the adds go out one every 1.5 seconds. Each add gets a note ("Quest Sharing:
   <zone>"). The game's answers (added, already a friend, not found, list full, other faction) are read and
   summarised for you.

12. **A quick chat ring, like in Diablo 4.** Bind a key (Game Menu > Options > Key Bindings > Quest Sharing,
   or `/qs key V`). **Hold the key**: a clean ring of up to 8 messages opens around the mouse, each with a short
   label (14 letters at most) outside the ring. **Point at one**: its full text appears in the middle. Then
   **release the key** or **click** it. By default the ring has:
   *Hello - Team up? - What I need - Same quests? - Thanks - Wait - Follow me - Invite*. *Team up?* says
   "Doing [your nearest quest] here - anyone want to group up?" in `/s`.

   **Sent at once.** A message you pick on the ring is sent straight away, no Enter (*Settings > Quick chat > Send
   the message at once*, or `/qs quick send on|off`; on by default). Off: it goes into the chat box and you press
   Enter. Messages to everybody nearby (`/s`, `/y`) only go out at once from a **click** on the slot, because the game
   wants a real click for those; **releasing the key on them puts them in your chat box** (press Enter), so a release
   always does something. **If the game refuses a channel** (some game clients do not let addons post in `/s` at all,
   not even from a click), that message goes into your chat box instead and the addon remembers it **for that channel
   only**: from then on `/s` messages go straight into your chat box (press Enter), while whispers and party messages
   still go out at once. The ring's hint says so ("the game does not let addons send this here"). Ticking *Send the
   message at once* again gives the refused channels another try.

   Different messages and emotes can follow each other right away (*Hug*, then *Salute*); only the **same** slot
   picked twice within a second is held back, so a double click never sends it twice.

   **The player a message is for** is your **target** if it is a friendly player, otherwise the friendly player
   **under your mouse when you open the ring** (the one you highlight). The middle of the ring shows where the message
   goes ("whispered to Lia") before you let go. Players of the other faction are never picked (they cannot read it).

   **More rings with the mouse wheel.** While the ring is open, **scroll the mouse wheel** to flip to the other rings
   (and around): **Emotes** (*Thank, Bow, Dance, Wave, Cheer, Point, No, Wait*), **Group calls** (*Follow me, Charge,
   Attack!, Heal me, Help me, Incoming, Flee, Out of mana*) and **Fun** (*Train, Laugh, Applaud, Salute, Hug, Flex,
   Chicken, Roar*). The name of the ring is shown above it, and the ring you used last opens first. **All rings
   are yours to edit**: *Settings > Quick chat*, pick the ring at the top of the editor (*Messages, Emotes, Group
   calls, Fun*), then change a slot's label and text: type an emote as `/dance`, `/salute`... (any emote the game
   knows), or a message; Up / Down / Remove / Add / Reset (Reset puts back that ring's defaults). Emotes are the
   game's own (with their animations and voices), not chat: a release does them. If your game refuses emotes from
   addons, the emote is typed into the chat box instead (`/bow`, press Enter), and so are the next ones. (There is no
   "stop" emote in the game; *Wait* is the closest.)

   **Where it goes.** Every message has its **own channel**. In `/qs settings > Quick chat`, click a message and pick
   one in the **Channel** row under it (the list shows each message's channel), or type `/qs quick route N <channel>`:

   | Channel | Goes to |
   |---|---|
   | **Auto** (most messages) | a whisper to the player you picked if they are not in your party (`/w`, and `{name}` is their name); otherwise the party (`/p`; `/i` in a dungeon group); alone with nobody picked `/s` |
   | **Nearby** (*Hello*) | a whisper to the player you picked, otherwise `/s`: greetings never go to the party chat |
   | **/s Say**, **/y Yell**, **/p Party**, **/w Whisper** | always that channel (Whisper = the player you picked) |

   The setting *Auto messages go to* (or `/qs quick channel auto|say|party|whisper`) changes only the messages left on
   Auto.

   **You see where it goes before you send it.** Every dot on the ring has the colour of the chat it goes to, the
   game's own chat colours: **party blue**, **whisper pink**, **say white**, **yell red**, gold for the invite. The
   middle of the ring shows the message and, under it, "to the party", "whispered to Lia" or "to everybody nearby
   (/s)". *Settings > Quick chat > Ring size*: small, normal or large.

   **Why `/say` needs a click.** The game only lets an addon say things to everybody nearby (`/say`, `/yell`,
   `/emote`) as the direct result of a key *press* or a mouse *click*, never from a key *release*; that is what
   caused the "Interface action failed because of an AddOn" message in an earlier version. So:
   whispers and party chat send the moment you release the key; for `/say` (and for the invite action) a release
   keeps the ring open on your choice and **one click, or one more press of the key,** sends it. A quick tap of the
   key also keeps the ring open so you can click a message.

   **Messages are filled in when you point at them.** `{name}` is the friendly player you target (or "there"),
   `{here}` your subzone or zone, `{need}` what you still have to do in this area (your unfinished
   objectives, nearest quest first where the client can measure distance), `{mine}` links to your
   unfinished quests of this area, `{common}` the quests you and your party share, `{quest}` the nearest
   unfinished quest, `{zone}` the zone, and `{shared}`, a whole sentence that fits the moment.
   **`{shared}` knows you cannot see a stranger's quests**, so with someone who is not in your party it asks a
   question that links yours (they can click a link and tell you): *"Are you doing any of these quests here?
   [Wolves Among Us], [A Personal Quest] Want to do them together?"*. Once you are in a party it says *"We have
   these quests in common: ..."*, or *"No quest in common yet - I'm on ... Any of these yours?"*.

   **Arrange the messages as you please.** Open `/qs settings`, tab **Quick chat**: click a message, change its
   label and text, press Enter, use Up / Down / Remove / Add / Reset, and **Show the ring** to see it as it looks in
   play. Or by command: `/qs quick` lists them; `/qs quick add [label |] <text>`, `edit N <text>`, `label N <label>`,
   `remove N`, `move N M`, `reset`.

13. **A minimap button.** Left click opens the settings window, right click shows or hides the
   quests-in-common panel, drag it around the minimap edge to move it (`/qs minimap off` hides it).
14. **An "Invite" action on the wheel.** A message that starts with `@invite` invites the player you target to
    your party and whispers them the rest of the text. The last default wheel slot is
    `@invite Sending you a party invite - let's quest together!`. It checks first that you have a target, are
    the party leader (if you are in one) and that the party is not full.
15. **Built-in help for problems.** `/qs doctor` shows what works on your client and opens the report in a
    window where the text is already selected (Ctrl+C to copy it). `/qs errors` shows any error the addon has
    caused (also kept between sessions). If something misbehaves in your game, paste the `/qs doctor` report
    into a GitHub issue.

    **The debug log** (*Settings > General > Debug log*, or `/qs debug on|off`; off by default) writes down **every
    action and its outcome**, errors or not, one line each with the time: what you picked on the ring, who it was
    for and where it went ("chat: sent to WHISPER Lia: Thanks!", "chat box: /s Hey there! o/"), each ping press,
    each quest share and its answer ("offered", "refused by the game"), every call the game may refuse, your `/qs`
    commands and setting changes, everything the addon told you, the game's own answers ("No player named ... is
    currently playing"), combat, target, party and zone changes, quests accepted or turned in, and every error with
    its stack. The same line again becomes one line with a count; the newest 3000 lines are kept. The game saves it
    with the addon's settings when you `/reload` or log out, in
    `WTF/Account/<account>/SavedVariables/QuestSharing.lua` (the `QuestSharingLog` part). `/qs log` (or **Show the
    debug log**) shows the newest 1000 lines in a window; `/qs errors` (or **Show the errors**) the errors. The window
    **scrolls** (mouse wheel), however long the text, and has buttons: **Select all** (then Cmd+C on a Mac, Ctrl+C on
    Windows: the game gives addons no way to copy by themselves), **Debug log** / **Errors** to switch between them,
    **Clear** and **Close**.

16. **Quest objectives are easier to find.**
    - **Quest icons over creatures:** every creature that is part of one of your quests gets a gold quest icon
      above its nameplate (the game itself tells the addon which creatures those are).
    - **The nearest quest is pinned in the world:** while "tracker follows me" is on, the game's own
      highlighted-quest marker (waypoint) follows the closest quest as you move. A quest only takes over after
      it has been the clear winner twice in a row, and if you pin a quest yourself it steps aside for 10 seconds.
      Switching it off gives back the quest you had pinned.
    - **Optional game-settings helper** (`/qs highlight cvars on`, off by default because it changes game
      settings): turns on enemy nameplates (the icons need them) and the game's icons over objects you can
      interact with. Switching it off puts your own values back.
    - `/qs highlight mobs|pin|cvars [on|off]`; the same switches are in `/qs settings`.

## Settings window
**Everything is switched on by default** (except the friends beta and the game-settings helper). To change
anything, left-click the map button, type `/qs settings`, click **Settings** on the Party quests window, or open
*Game Menu > Options > AddOns > Quest Sharing*. Each tab is about one thing you do, opens with a one-line
explanation, and groups its settings in short sections:

| Tab | What is on it |
|---|---|
| **General** | *Getting started*: your **quick chat key** (click, then press the key), **Show the ring**, **Check my setup**. *Basics*: the master switch, how your messages go out, the map button, a soft sound for good news; *Debugging*: the debug log and **Show the debug log**; reset |
| **Sharing** | *When I join a party*, *Party chat* (in common, done, picked up a quest someone has, where the items were), *Behind the scenes* (sync, quest-log markers) |
| **Party** | the Party quests window (show it in a party, hide it in combat, its size, move it back), *Clicking a quest* (what a click on the game's tracker posts) *Showing where we are* (the map icons, a teammate's pin) and *Friends* (the beta) |
| **Tracker** | *The quest list on the right* (follows you, how many, distance or zone, the pause), *Finding objectives* (the world pin, quest icons over creatures, the game-settings helper)  |
| **Quick chat** | the ring, its key, hold or toggle, its size, where Auto messages go, and the **message editor** |
| **Pings & items** | *Pinging quest targets* (the ping key, the anti-spam time, objects too) and *Quest items* (icons in the tracker, the quest item key, the item button) |

Every line is one click: a **check box** switches, a **choice** (`< value >`) moves to the next one (right click goes
back), a **number** (`- 10 +`) counts up with the left button and down with the right one (Shift = bigger steps), and
**buttons** do what they say. The grey line under a setting says what it does; with the master switch off the other
lines are greyed. The same things can be done with `/qs` commands, and a change in either place shows up in the other
at once. Settings saved by an earlier version get the new defaults; every other choice you made is kept.

**The map button's tooltip** shows how things are right now: your party and how many quests you share, whether the
tracker follows you, your quick chat key (or that it is not set) and how many problems were recorded.

**Good news has a sound** (switch it off under General): a soft ping when someone accepts a quest you shared or a
party member running Quest Sharing finishes one you share. Never during combat.

## Install
**Easiest:** download `QuestSharing-<version>.zip` from the GitHub *Releases* page, unzip it and drop the
`QuestSharing` folder into `Interface\AddOns`. Or:
1. Copy the folder `QuestSharing` (the one containing `QuestSharing.toc`, not this README's folder) into
   the game's `Interface\AddOns` folder, so you have `...\AddOns\QuestSharing\QuestSharing.toc`.
2. Start the game; on the character screen click **AddOns** and make sure **Quest Sharing** is ticked
   (tick **Load out of date AddOns** if the game says it is out of date).
3. Optional: install **Questie** too. Quest Sharing only reads its quest database (where quests start, which
   quests come first) for "Tell them where to get it", and on clients where the game cannot say which creatures your
   quests need, it adds their names (only when Questie's language is the game's: names on screen are in the game's
   language). Everything else works without it. **Questie 12 comes as two folders, `Questie` and `QuestieDB`** (its
   quest data): copy **both** into `Interface/AddOns`. Type `/qs questie` to check it: it says, for each of the two,
   whether it is loaded (with its version) or why not (not installed, switched off in the AddOns list, marked out of
   date, a folder with another name such as `Questie-master`), what to do about it, how the data is read, the language
   of its names, and looks up a few quests of your quest log.
4. In game type `/qs probe`. It tells you what your game client supports. **If something looks wrong,
   open an issue at https://github.com/YodaGitMaster/QuestSharing/issues and paste that output.**

## Commands (`/qs` or `/questsharing`)
| Command | What it does |
|---|---|
| `/qs share` | share your quests in this area with the party now, repeating earlier offers and declines (one quest per use where the game only allows sharing on a click) |
| `/qs shareclick on\|off` | share only when you click Share (comes on by itself where the game refuses automatic sharing) |
| `/qs stop` | cancel a share in progress |
| `/qs on` / `off` | switch the addon on / off |
| `/qs auto on\|off` | share automatically when you join a party or someone new joins (default on) |
| `/qs new on\|off` | share a quest once when you accept it while in a party (default on) |
| `/qs area zone\|all` | share only this zone's quests (default) or every quest |
| `/qs gap N` | seconds between two shared quests (default 4, minimum 2) |
| `/qs chat on\|off` | announce quests in common in party chat (default on) |
| `/qs click on\|off` | clicking a tracked quest fills the chat box (default on) |
| `/qs link on\|off` | shift-click links get the status appended (default on) |
| `/qs mode box\|send\|print` | how your messages go out (the ring, the menu, quest clicks): **box** types them into the chat box and you press Enter (default; works on every client), **send** sends straight away where the game allows it, **print** only shows them to you |
| `/qs sync on\|off` | exchange exact quest lists with other Quest Sharing users (default on) |
| `/qs announce on\|off` | say in party chat when a quest we share is done (default on) |
| `/qs markers on\|off` | star and names next to shared quests in the quest log (default on) |
| `/qs panel [on\|off]` | show the "Party quests" window while in a party (default on); drag it to move it, click a row to put your progress in the chat box |
| `/qs near [on\|off]` | keep the quest tracker filled with the quests closest to you (default on) |
| `/qs near N` | how many quests it keeps (default 5) |
| `/qs near mode auto\|distance\|zone` | `auto` uses distance if your client can measure it, otherwise your zone |
| `/qs near now` / `resume` | refresh now / end a pause early |
| `/qs settings` | open the settings window |
| `/qs friends` | (beta) add everybody in your party to your friends list now |
| `/qs friends on\|off` | (beta) do it automatically when a party forms or someone joins (default off) |
| `/qs key [KEY]` | bind the quick chat wheel to a key, e.g. `/qs key V` or `/qs key ALT-E`; `/qs key none` removes it |
| `/qs quick ...` | the quick chat messages: `add [label \|] <text>`, `edit`, `label`, `route`, `remove`, `move`, `reset`, `editor`, `mode hold\|toggle`, `channel auto\|say\|party\|whisper`, `on\|off` |
| `/qs highlight mobs\|pin\|cvars [on\|off]` | quest icons over creatures / pin the nearest quest / the game-settings helper |
| `/qs doctor` | a report of what works on this client, in a window you can copy from |
| `/qs errors [clear]` | errors this addon has caused; the window adds where each came from (line, what was running, stack) |
| `/qs debug on\|off` | the debug log: every action and its outcome, saved to the addon's file on `/reload` or logout (default off) |
| `/qs log [clear]` | show the debug log in a window you can copy from; `clear` empties it |
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

## About your game client
The API documentation lists **World of Warcraft: Forever 1.60.1** as a client that "shares Mainline WoW's UI
architecture, including the vast majority of APIs available in 12.1.5". So the modern calls this addon uses
(`C_QuestLog`, `C_NamePlate`, `C_SuperTrack`, distances to quests, ...) are documented for it. The classic-style
fallbacks stay in for other clients. Very recent clients also hide some values from addons in combat and in
instances ("secret values"); everything that reads such a value is wrapped so it fails quietly instead of
breaking. `/qs doctor` tells you exactly what works on your copy.

## Sound
Quest Sharing **never changes your game's sound settings**: its only sound is the soft good-news ping
(`/qs sound off`, or *Settings > General*). It also refuses to put the quick chat on a key the game uses for its
sound (toggle sound, toggle music, volume up/down) or for the game menu, so a stray Ctrl+S while choosing a key
cannot leave you without sound control. `/qs doctor` shows how the game's sound is set right now (only read).
If the game's sound goes away, check `/qs doctor` and `/qs errors`; another program that records or captures the
computer's audio can also take the sound device away from the game.

## Known limits (please read)
- **Not tested in the real game.** Everything is tested in a Lua 5.1 interpreter against a mock of the WoW
  API (both the modern `C_QuestLog` style and the classic `GetQuestLogTitle` style, 866 tests), but I could
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
  before it takes it over. Chat to everybody nearby (`/say`) is only allowed from a key press or a click, so the
  ring waits for one (see the quick chat section). The ring needs a free mouse pointer (not mouse-look). It is untested in the real game: `/qs probe` shows `quick chat wheel: key ...`.
- **Quest icons over creatures** only appear where the game shows nameplates: enemy nameplates must be on
  (`/qs highlight cvars on` does that), and creatures farther away than your nameplate distance have none.
  Objects (items on the ground, chests) are not creatures, so they get no icon from this addon; the helper
  above turns on the game's own icon for objects you are close to. The pin uses the game's quest marker; I could
  not confirm from the documentation exactly how that marker looks on your client.
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
python tests/test_questsharing.py     # 68 tests: sharing, replies, announcements, tracker clicks, commands
python tests/test_features.py         # 96 tests: sync, completion, the Party quests grid, quest-log markers
python tests/test_triggers.py         # 34 tests: when it shares (once per join / new member / new quest), no nagging
python tests/test_tracker.py          # 29 tests: the tracker follows you (distance and zone modes)
python tests/test_settings.py         # 44 tests: everything on by default, migration, the tabbed settings window
python tests/test_friends.py          # 42 tests: the friends beta (manual and automatic, safeguards)
python tests/test_quick.py            # 127 tests: the quick chat ring, placeholders, editing, key binding, performance
python tests/test_extras.py           # 35 tests: error log + doctor, invite action, minimap button, release zip
python tests/test_highlight.py        # 23 tests: quest icons over creatures, the world pin, the game-settings helper
python tests/test_look.py             # 42 tests: the settings window layout, the key capture, welcome, sounds, ring colours
python tests/test_together.py         # 30 tests: several Quest Sharing users in one party, fewer messages
python tests/test_team.py             # 30 tests: picked up a quest someone has, where the items were, the message budget
python tests/test_where.py            # 18 tests: no raid mark, map icons, a teammate's pin, the pin preferring shared quests
python tests/test_menu.py             # 60 tests: the right-click menu, Questie's where-to-get-it and chain, the sound-key guard
python tests/test_done.py             # 20 tests: a quest you finished is never shared, announced or listed
python tests/test_box.py              # 46 tests: messages into the chat box, refused calls written down (line, stack), sharing on your clicks
python tests/test_ping.py             # 27 tests: the ping key, nearest quest creature, anti-spam, the ring's ping slot
python tests/test_zone.py             # 10 tests: only the quests of where you are (Teldrassil vs Stormwind)
python tests/test_items.py            # 24 tests: quest item icons in the tracker, the item key and button
python tests/test_emotes.py           # 26 tests: the emote rings behind the mouse wheel, and editing them
python tests/test_log.py              # 35 tests: the debug log: every action and its outcome, kept small, the log window
```
Expected: every line ends in `passed` with all tests green (866 in total).

## Files
| File | Purpose |
|---|---|
| `QuestSharing/Compat.lua` | the only place that knows classic vs modern APIs |
| `QuestSharing/Core.lua` | settings, timers, events, chat queue, `/qs` commands |
| `QuestSharing/Share.lua` | party detection, the push queue, reading the game's replies, announcing quests in common |
| `QuestSharing/Sync.lua` | addon-to-addon protocol: hello, full quest list, updates (see the header of the file) |
| `QuestSharing/Progress.lua` | notices finished quests, announces them, sends changes to synced players |
| `QuestSharing/Panel.lua` | the "Party quests" grid (nearest 5 quests x party members) and the quest-log markers |
| `QuestSharing/Track.lua` | keeps the quest tracker on the quests nearest to you (distance or zone mode) |
| `QuestSharing/Highlight.lua` | quest icons over creatures on their nameplates, and the game-settings helper |
| `QuestSharing/Diagnostics.lua` | the error log, `/qs doctor` and the copyable report window |
| `QuestSharing/MinimapButton.lua` | the minimap button |
| `build_release.py`, `CHANGELOG.md` | builds `dist/QuestSharing-<version>.zip` and the release notes |
| `QuestSharing/Quick.lua`, `QuestSharing/Bindings.xml` | the quick chat ring, its placeholders, the message commands and the key binding |
| `QuestSharing/Friends.lua` | (beta) adds party members to your friends list, with safeguards |
| `QuestSharing/QuestItems.lua` | usable quest items: icons next to the quests in the tracker, the item key and button |
| `QuestSharing/Ping.lua` | the ping key: Attack ping on the nearest quest creature, "look here" on quest objects, anti-spam |
| `QuestSharing/Menu.lua` | the right-click menu of the Party quests window |
| `QuestSharing/Questie.lua` | reads Questie's quest database (when installed): where a quest starts, which quests come first |
| `QuestSharing/Marker.lua` | positions on the world map, a pin where a teammate found the items |
| `QuestSharing/Team.lua` | "picked up a quest someone has - let's do it together?" (once per quest, not for shared ones) |
| `QuestSharing/Style.lua` | one look for every window (dialog and on-screen frames, buttons, check boxes, chat colours) and the good-news sound |
| `QuestSharing/Settings.lua` | the tabbed settings window (sections, check boxes, key capture) with the message editor, and the options entry |
| `QuestSharing/Status.lua` | the status message, tracker / link hooks, `/qs probe` |
| `tests/` | the Lua 5.1 test harness with a WoW API mock, and the two test files |
