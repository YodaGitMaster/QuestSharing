# Quest Sharing

A World of Warcraft addon for playing quests together.

[Download the latest release](https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.22)

## Your first party, in four steps
1. **Install it** (see [Install](#install)) and log in. A short welcome in chat tells you it is ready. Everything is
   on, except the automatic party chat: **you** decide when to talk.
2. **Give the quick chat ring a key:** left-click the map button > *Quick chat* > **Quick chat key**, click, press the key
   (for example `V`, or `E` if you do not strafe with it).
3. **Group up.** Your quests of this area are offered to the newcomers (once each), and the
   **Party quests** window shows your nearest quests with a check or an X for every member. **Left click** a quest to
   offer it, **right click** to open its menu: tell the party your progress or choose **Ask in chat to do this quest** directly below it.
4. **Talk with one key:** hold it, point at *Hello*, *Team up?* ("Doing [your quest] here - anyone want to group up?"
   in /s), *What I need*... and let go. Each message's channel is yours to choose in the settings.

Hover the map button any time for a quick status (party, tracker, your key, problems). `/qs doctor` checks your setup.

## What it does

**Your messages go into the chat box, and you press Enter.** Some game clients do not let addons send chat messages
at all (the game says "tried to call the protected function UNKNOWN()"), but typing into the chat box always works.
So what the addon writes for you (the right-click menu, quest clicks, Post all) is typed into the chat box with the
right channel set (`/p`, `/s`, `/w Name`, ...). The quick chat ring has its own switch and sends at once by default
(see below). *Settings > General > How to send quest progress messages* (or
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
   quest offers that one. *Settings > Quest sharing > Require a Share click for each quest offer* (`/qs shareclick on|off`) shows and
   changes it. If the game refuses even a share from your click, sharing switches off until you `/reload`.

   If you switch on the party chat
   announcement (**off by default**: *Settings > Quest sharing > Messages in party chat*), it also tells the party which quests you have
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

   `/qs pickup on|off`, `/qs coords on|off`, or *Settings > Quest sharing > Messages in party chat*.

5. **Can announce when a shared quest is done** (off by default). When all objectives of a quest that a party
   member also has are finished, it says so in party chat, once for the whole party.

6. **Shows who shares what.** A star and the names next to shared quests in the game's quest log, and a small
   movable **Party quests** window (shown while you are in a party, on the left of the screen the first time; drag it
   anywhere and it stays there). It is a grid: **your 5 nearest quests** down the side, **one column per party member**:

   ```
   Party quests                                 [Share] [Post all] [-]  Settings
   Quest                           [mage] Anna QS   [priest] Bob
   Wolves Among Us          3/8 +1        v              x
   Report to Goldshire        done        v*             ?
   A Personal Quest            ...        x              x
   ```

   - **v** (green check) = has the quest, **v\*** (gold check) = has it and finished it, **x** (red) = does not have
     it, **?** = the game cannot tell (the player is out of range or offline; players running Quest Sharing are
     always known exactly, **QS** after their name).
   - Close it with the x in its corner; it stays off until you type `/qs panel on` or turn it on in
     *Settings > Party window*. While quests are being offered, the **Share** button reads **Stop** - click it to stop sharing.
   - **Only the quests of the zone you are in**, never filled up with quests from elsewhere.
   - **Also when you are alone** (*Settings > Party window > Also show the Party quests window when playing alone*, on by default; `/qs solo off`): then it is
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
     - **Ask in chat to do this quest**: fills your current chat with `Anyone need [quest]? Wanna group up?`; select World chat first to ask there, then press Enter to send,
     - **Offer it to the party** (the same as a left click),
     - **Tell them where to get it**: with the [Questie](https://github.com/Questie/Questie) addon installed, the party
       hears where it starts, which quest comes before it, **where that earlier quest starts**, and how many steps lie
       before that: `Bob: [Wolves Among Us] starts at Marshal McBride in Elwynn Forest (48.9, 41.6), after "A Threat
       Within" (from Deputy Willem in Elwynn Forest (48.2, 42.9)), 1 more step before that.` (Also "starts from the item
       ..., dropped by ..." when an item starts it.)
     - **How to do it** (with Questie): **one chat line** with what is still open and where, the spot nearest to you
       for each, then where to turn it in: `[Wolves Among Us]: kill Wolf (Elwynn Forest 42.5, 61.5); Wolf Pelt from
       Wolf (Elwynn Forest 42.5, 61.5); then turn in at Marshal McBride (Elwynn Forest 48.9, 41.6)`. Objectives the game
       already counts as done are left out; a finished quest says only where to turn it in. Also objects to use ("use
       Kobold Crate"), items from chests and places to go. In a party it goes to the party, alone only to you.
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
   - **Tell the party how I am doing** puts this line into your chat box (press Enter to send it), or sends it at
     once when *Settings > General > How to send quest progress messages* is **Send immediately**:
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
     your party, and *Settings > Party window > Move back* finds it if you lost it.

7. **Shows each other where you are.**
   - **Quest Sharing users on your world map:** a class icon where each of them is (their addons send their position
     every 10 seconds while they move, at most once a minute when they stand still), and yours to them.
   - **A map pin where a teammate found the items** of a quest you still work on, when they right-click it in their
     Party quests window. `/qs waypoint off` stops that. A waypoint you set yourself in the last 5 minutes is kept; the
     chat line then names the zone and offers a clickable [Set waypoint] link.
   - **The game's quest marker prefers a quest you share:** in a party it follows the nearest quest someone else also
     has, otherwise simply your nearest quest.

8. **Pings the quest target for the party** (where the game has its ping system: `/qs doctor` says so).
   Bind a **ping key** (*Settings > Pings > Key to target and ping a quest enemy*: click, press the key; or `/qs pingkey G`). Each press:
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
   - **Quest item key** (*Settings > Quest items*, or `/qs itemkey Q`): uses the item of your **nearest** quest that
     has one, also in combat (the item it had before the fight).
   - **A small button** with that item (Shift + drag to move it): cooldown, count, red when your target is out of range.
   - Using an item is protected by the game, so these are secure buttons prepared outside combat; during a fight they
     keep what they had and the tracker icons are put in place again afterwards.
   - **Quest items marked in your bags** (*Settings > Quest items > Mark quest items in my bags*, `/qs bagmarks
     on|off`, on by default): a **gold** border on items for a quest of the zone you are in, a **blue** one on items
     for one of your quests somewhere else, so the bank can keep those and you only carry what this zone needs. The
     item's tooltip says which quest and where. An item counts for a quest when an objective names it ("Wolf Pelt:
     2/4"), when the bag says it belongs to that quest, or (with QuestieDB) when the quest asks for, hands out or
     needs that exact item. The game's own bags and the bank's main slots; bag replacement addons (Bagnon, ...) use
     their own buttons and are not marked. Clicks go through to the item.
   - **Bag helpers** (*Settings > Bags*, all work on the game's own bags only):
     **Bookmark** an item by pointing at it in your bags and pressing **Space** (again to remove; `/qs bookmarks
     list|clear`, on by default). A bookmarked item shows a small note icon and its tooltip says so; it is never sold
     by this addon, even if the Space key is switched off later. The bookmark belongs to the item type, so it stays
     when you move the item. **Sell gray items** (off by default, `/qs sellgray on|off`) sells every gray item when a
     vendor opens, except bookmarked ones and gray items one of your quests still needs; the game's Buyback tab keeps
     the last 12. **Arrange by topic** (`/qs sort` once, or *Arrange my bags automatically*, off by default)
     treats all bags, the backpack included, as one long bag: quest items, consumables, equipment, materials,
     recipes, other, then gray items last, each group by type, quality and name. *How to arrange my bags* chooses
     the order (Topic, Quality best first, or Name A to Z; `/qs sort by topic|quality|name`), which bags (all, all but
     the backpack, or the backpack only; `/qs sort bags all|bags|backpack`), where the items gather (start or end of the
     bags; `/qs sort from start|end`) and whether bookmarked items stay in their slot (`/qs sort keep on|off`). It waits until your bags have been
     quiet for 3 seconds, never runs in a fight or while you hold an item, leaves quivers and profession bags alone
     and never splits or merges stacks. Every helper has its switch in Settings; the *Arrange my bags now* and
     *Remove all my bookmarks* buttons sit beside them, so no command is needed.

10. **Keeps your quest tracker on what is near you.** It is on by default; `/qs near off` stops it. **Hide the game's
    tracker** altogether: *Settings > Quest list > Hide the game's quest list on the right* (`/qs hidetracker on`; outside fights, as
    the game requires; the Party quests window still shows your quests). It fills the
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

   **Sent at once.** A message you pick on the ring is sent straight away, no Enter (*Settings > Quick chat >
   Send quick chat messages without pressing Enter*, or `/qs quick send on|off`; on by default). Off: it goes into the chat box and you press
   Enter. Messages to everybody nearby (`/s`, `/y`) only go out at once from a **click** on the slot, because the game
   wants a real click for those; **releasing the key on them puts them in your chat box** (press Enter), so a release
   always does something. **If the game refuses a channel** (some game clients do not let addons post in `/s` at all,
   not even from a click), that message goes into your chat box instead and the addon remembers it **for that channel
   only**: from then on `/s` messages go straight into your chat box (press Enter), while whispers and party messages
   still go out at once. The ring's hint says so ("the game does not let addons send this here"). Ticking
   *Send quick chat messages without pressing Enter* again gives the refused channels another try.

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

   **Only emotes your game has are on the ring** (the addon reads the game's own list of emotes). After each emote the
   addon waits for the game's answer ("You dance."); without one it says so ("the game did not show /hug, 1.2 s after
   the emote before"): the game may hold back emotes done quickly one after another, so try it again in a moment.
   A quick flick onto a message sends it; only a tap with nothing pointed at keeps the ring open for a click.

   **Test the whole ring:** `/qs quick test` (or **Settings > Quick chat > Test the ring**) runs every slot of every ring,
   one every 3 seconds, and shows what the game really did: emotes are done for real and the game's line awaited
   ("You dance."); messages are **whispered to yourself** (nobody else gets them) and the game's "To you" awaited.
   Pings and invites are skipped. The window lists `[OK]` / `[--]` for each slot with the game's answer, ready to
   copy. `/qs quick test emotes` or `messages` runs only those, `/qs quick test fast` runs the emotes back to back (to
   see whether the game holds quick ones back), `/qs quick test stop` ends it. Emotes are seen by players near you.
   A refusal during the test is only reported, nothing is switched off for it. The game's own chat log is another
   way to check: `/chatlog` writes every chat line to `Logs/WoWChatLog.txt` in your game folder.

   **Where it goes.** Every message has its **own channel**. In `/qs settings > Quick chat`, click a message and pick
   one in the **Channel** row under it (the list shows each message's channel), or type `/qs quick route N <channel>`:

   | Channel | Goes to |
   |---|---|
   | **Auto** (most messages) | a whisper to the player you picked if they are not in your party (`/w`, and `{name}` is their name); otherwise the party (`/p`; `/i` in a dungeon group); alone with nobody picked `/s` |
   | **Nearby** (*Hello*) | a whisper to the player you picked, otherwise `/s`: greetings never go to the party chat |
   | **/s Say**, **/y Yell**, **/p Party**, **/w Whisper** | always that channel (Whisper = the player you picked) |

   The setting *Who receives messages set to Automatic* (or `/qs quick channel auto|say|party|whisper`) changes only the messages left on
   Auto.

   **You see where it goes before you send it.** Every dot on the ring has the colour of the chat it goes to, the
   game's own chat colours: **party blue**, **whisper pink**, **say white**, **yell red**, gold for the invite. The
   middle of the ring shows the message and, under it, "to the party", "whispered to Lia" or "to everybody nearby
   (/s)". *Settings > Quick chat > Message ring size*: small, normal or large.

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
   Party quests window (hiding it says how to bring it back), drag it around the minimap edge to move it (`/qs minimap off` hides it).
   Three shortcut buttons sit beside it: a map icon opens the Quest guide, a key icon opens Dungeon quests, a
   spyglass opens the Party finder picker (see below).
14. **An "Invite" action on the wheel.** A message that starts with `@invite` invites the player you target to
    your party and whispers them the rest of the text. The last default wheel slot is
    `@invite Sending you a party invite - let's quest together!`. It checks first that you have a target, are
    the party leader (if you are in one) and that the party is not full.
15. **Built-in help for problems.** Diagnostic recording is **on by default**, including once for existing
    installs when updating to this change. `/qs debug off` stops recording and that choice is preserved afterward.
    Errors are always captured. Open `/qs log`, `/qs errors`, `/qs doctor`, or **Settings > Errors & logs > Check my setup, errors and logs** (**Open report**):
    they open **one window with a readable issue overview**: newest issues first, plain-language headings,
    last-seen times, repeat counts, paused features and separate setup notes. Opening the report does not dump
    technical output into game chat. Click **Copy all**, then **Ctrl+C** (Windows) or **Cmd+C** (Mac) to copy the
    **entire report**, including every retained error/stack, setup check, feature setting and log line, even when
    those details are hidden from the overview. **Show full report / Show overview** switches views in the same
    window; full settings have one readable entry per line. Text stays fixed while reading or copying;
    **Refresh** takes a new snapshot.

    The debug log records addon actions and outcomes, commands, setting changes, game replies, your own chat,
    combat, target/party/zone changes and quest events. Repeated adjacent lines have a count. Recording is bounded
    to about 1000 lines (trimmed in batches); the newest 30 distinct error records are retained. The report includes
    everything still retained, with no extra 1000-line or 10-error display limit. The game saves the records on
    `/reload` or logout to `WTF/Account/<account>/SavedVariables/QuestSharing.lua` (`QuestSharingLog` and
    `QuestSharingDB.errors`). **Clear records** (click it twice) empties both lists; `/qs log clear` and `/qs errors clear`
    clear only their respective list. **Clear errors**, **Clear logs** and **Reset settings** in Settings > Errors & logs
    also ask for a second click. The ring test is in **Settings > Quick chat > Test the ring**.

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
17. **Aggro for tanks** (off by default: Settings > General > During a fight, or `/qs aggro on|off`). Every
    enemy always shows how much of its aggro you hold, right above its nameplate, and the colour follows the
    fight: white = nobody is fighting it yet (you walk into the room); red with a small flame = it is on you,
    100 %; green = below 50 %, someone's spell pulled it away; orange = 50-99 %, you hit it and it is coming
    back. In a fight, when 2 or more enemies are next to you (about 10 yards) and one of them is not on you, the
    lowest one (below 50 %) and every one within 10 points of it get the alarm: the enemy's portrait in a
    pulsing red ring, with "Losing aggro 20%" in grey under it: Tab to it or click it and taunt. The game does not let addons pick your target in a fight, so the addon marks it and you select it.
    Switching it on also turns on enemy nameplates (an addon only sees the enemies that have one); switching it off
    puts your own setting back. During a fight that change waits until the fight is over.

## Settings window
Open `/qs settings`, left-click the minimap button, click **Settings** in the Party quests window, or use
*Game Menu > Options > AddOns > Quest Sharing*. Choose what you want to change from the left-hand menu, or type a word
in **Search settings** at the top (for example *sort*, *key* or *map*): every matching setting from every page shows under
its page and section, works right there, and a click on the gold page line opens that page. A setting that has no effect
until another switch is on is greyed and says which switch (for example *Wait before arranging automatically* needs
*Arrange my bags automatically*).

The categories are grouped by topic:

| Group | Category | What you can change |
|---|---|---|
| **Basics** | **General** | Turn the addon on/off, show its minimap button, choose how progress messages are sent, sound |
| **Questing** | **Quest markers** | **Show ! above quest enemies**, turn on the enemy health bars those marks need, follow the nearest quest with a waypoint |
| | **Quest list** | Hide the game's tracker or automatically fill it with nearby quests; choose how many and how long to pause after your own edits |
| | **Accept & turn in** | Automatically accept quest offers and turn in ready quests; each has its own switch |
| | **Quest items** | Mark quest items in your bags, usable item buttons, the quest-item key, and the leftover-items review (Bag cleanup) |
| | **Bags** | Space-bar bookmarks, selling gray items, arranging bags automatically or now, the order, which bags, where items gather, the wait before arranging, keeping bookmarked items in place |
| **Party** | **Quest sharing** | Offer quests to your party, require a manual Share click, announce progress, sync quest information, mark shared quests in the quest log, write a quest invitation |
| | **Party window** | Show/hide/resize the separate Party quests window, restore its position, post progress by clicking, add party friends and the friend slots to keep free |
| | **Party finder** | Who to invite (roles, supercharge, levels, item level, re-invite wait, whisper), the picker and its key, one switch per class, item levels of other players |
| | **Pings** | Bind the target-ping key and choose the ping delay |
| | **Quick chat** | Set the ring key, preview the ring, choose hold/press, choose where messages go, edit each message or emote |
| **Map & route** | **Map** | Show zone level ranges, dungeon entrances, boats, zeppelins, your trainers and party members on the world map; a faction choice and shared item-location waypoints |
| | **Quest guide** | The quest route guide, its goal, camps, learned pace and report |
| **Look up** | **Items & dungeons** | The Adventurer's Journal (Quest rewards, Instance drops, Dungeon quests), item/vendor search and item source tooltips |
| | **Professions & character** | Cooking recipes, spell ranks, saved fishing spots |
| **Help** | **Errors & logs** | Open one report with your setup, errors and logs (copy it for a bug report), clear the recorded errors or the logs, switch log recording, reset all settings (each clear or reset asks for a second click) |

Every option has a visible explanation of what turning it on does and any requirements.
For example, **Quest markers > Show ! above quest enemies** adds a gold ! above enemies needed for your active
quests; **Turn on enemy health bars and nearby object icons** enables the game's nameplates those marks need.
The shared-quest star in the quest log has its own setting under **Quest sharing**.

Checkboxes show **On** or **Off**. For choices, click the named option you want; the selected option is marked
**[x]** and its explanation appears below. Numbers have separate **-** and **+** buttons (Shift changes five steps).
For a key binding, click **Set key**, then press the key; Escape cancels. Actions use named buttons such as
**Open report** and **Browse rewards**. Changes save automatically.

Long pages scroll, including the Quick chat message editor. Use your mouse wheel or the visible **Scroll up** /
**Scroll down** buttons. Changing a setting keeps your reading position; changing category starts at the top.
Your existing saved choices and defaults are kept. Quest automation, map extras, spell-rank automation, fishing,
reward browsing, friend automation, and the game-settings helper remain opt-in.

**The map button's tooltip** shows how things are right now: your party and how many quests you share, whether the
tracker follows you, your quick chat key (or that it is not set) and how many problems were recorded.

**Good news has a sound** (switch it off under General): a soft ping when someone accepts a quest you shared or a
party member running Quest Sharing finishes one you share. Never during combat.

## Party finder: find and invite players

For a group leader who wants a healer (or a tank, or damage dealers) without scrolling the game's party finder.

1. List your group in the game's party finder for a dungeon. The addon only searches and invites while you are
   listed, and only players listed for that same dungeon.
2. Click the **spyglass** beside the minimap button. A small picker opens: tick **Healer**, **Tank** or **Damage**,
   untick classes you do not want (e.g. healers only Paladin and Priest), set the lowest item level.
3. Click **Find**. The game allows one search per click (or per press of the "Party finder: search and invite" key),
   so click again to search again. Invited players get a whisper: "Hi! I invited you to my group for The Deadmines
   as healer."

Who is invited: per role only what is still open (1 healer, 1 tank, 3 damage), highest level first; a player
listed for two roles takes whichever is open. Tick **Supercharge** to fill every free spot at once (open invites count as spots, as in the game): the first to accept gets the spot, and extra players who accept may need to be removed. A decline frees the
spot at once. Item levels: the party finder shows none, so the addon remembers players you inspected nearby and
asks other Quest Sharing users; with a lowest item level set, unknown players are invited or skipped as you choose.
All options: right click the spyglass, or **Settings > Party finder**.

## Tools and lookups

Open `/qs settings` > **Quest items** for bag cleanup, **Quest sharing** for quest invitations, **Professions & character** for spell ranks and fishing spots, and **Quest guide** for the quest route. **Items & dungeons** collects the equipment, dungeon quest and item/vendor lookups; **Map** contains zone level ranges, dungeon entrances, boats, zeppelins, your trainers and party locations (its **More map features on other pages** section opens the map search, gathering marks and fishing spots). Quest automation stays under **Accept & turn in**.

Each tool has a card with its purpose, data requirements and a named Open action where available. Its persistent switch appears below the description. Clicking a card description does not change a setting. Database searches run when you use a tool, not when you browse settings; map search explains how to use the world map search box.

**Leftover quest items.** Open **Quest items > Bag cleanup** or type `/qs cleanup`. QuestieDB is required. The tool checks carried bags against every quest in your log, including completed quests awaiting hand-in and quests in other zones. It keeps known active objective/source/special items and items that start quests; unknown and locked items are skipped. Review each possible leftover, then confirm **Delete stack** to permanently remove that whole stack. These are candidates, and may still have a use in a future quest. Each confirmation rechecks current quests and the exact bag slot/item/count before deletion. After a deletion the list stays, so you can review the next stack; other bag or quest changes cancel the review; click **Refresh bags**. Cleanup waits during combat, never scans the bank, and runs only when opened/refreshed or after a confirmed deletion. If the client refuses deletion, it returns the picked-up item and explains how to delete it manually.

**Quest guide.** Open **Quest guide** or type `/qs plan`. It is off by default. Open it when you need it; saving the enabled switch does not open it or scan the database on login. While the guide is visible, it updates when you enter a different zone or your quest log changes. Closing it stops database work until you open it again. Use it outdoors in a zone: it will not scan in towns, cities, dungeons, or continent maps, and it clears or rebuilds the plan if you enter a town or change zones. Questie and a recent QuestieDB are needed for its quest catalogue, prerequisites and locations. If Questie is missing or too old, the guide says what to do; type `/qs questie` to check. To keep memory use down, each quest first gets one small check (your race, faction and class, your level, and whether its zone is on this continent): a quest that fails it is not loaded further. `/qs plan why` says how many were left out.

The Quest guide plans the zone's own quests: the ones Questie files under the current zone or one of its sub-zone maps. Profession, event and other-zone quests stay out even when their giver or a mob is here; a class quest you can take counts when its giver is here (a gnome mage's *Glyphic Memorandum* in Anvilmar); a quest from another zone appears only for its hand-in here once it is ready. Quests up to three levels above you join the route at the point where quest and kill XP get you there (a level-1 gnome takes *A Refugee's Quandary* at level 3 and the Mornbrew quests at level 4 before leaving Coldridge Valley). Each kill or collect step goes to a real camp: a group of at least three spawns within about 100 yards of one creature (or its biggest group, if it never gathers that many), or a spot the step's creatures share, such as 2 + 2 spawns of two creatures. Lone stray spawns are ignored and the step stays put while you walk. Up to four real camps are considered per step; the guide picks the one that suits the whole route, such as the camp beside the hand-in or one already farmed for another quest on the same creature. A step keeps the camp it chose until another one is clearly cheaper (by a quarter of the visit's travel and work and at least 20 seconds), so it does not flip between two camps as you walk. A camp the guide used only because you marked another one busy is not kept once the wait ends, and **Clear camp waits** lets every step choose its camp afresh. Your position is only where the route starts. It checks real acceptance restrictions and follows locally attainable chains without a fixed depth limit. The default goal is to complete the zone's compatible, non-repeatable quests. The guide's **Plan** button opens **Settings > Quest guide**, where *What the route aims for* chooses **Complete zone**, **Quest XP/hour**, **Chosen quests** or **Time limit** (minutes). **Level range** chooses **Every level** or **Green and yellow only**. **Chosen quests** takes quest names or IDs (e.g. `/qs plan selected Local Harvest, 9001`; hover a guide step to see its quest IDs), and **Time limit** takes 5-240 minutes. Every change is confirmed in chat, and the Plan button tooltip shows the current goal. Quests requiring a future level, work elsewhere or missing facts appear in the plan report.

The Quest guide compares nearest-ready instructions with alternative pickup, unlock and farming orders. It prices travel, estimated work and known waits, and gives time credit when the same verified creature action can progress accepted quests together. One item drop stream can share kills with kill quotas. An unaccepted follow-up receives no earlier kill credit. Independent objectives at the same camp share travel. Unknown quantities/rates use labelled work estimates. The guide explains measured differences between the schedules it compares. After the first route appears, a background local search moves short runs of steps and reverses short segments, re-checking prerequisites, log slots and budgets for every change, and swaps in a faster route while keeping your selected step, including a step you chose while it was running. It runs again only when your quests, goal or level range change or after you move about a tenth of the map; smaller moves reuse the refined order. The refinement is idle work: it runs only while no other data work (map search, the dungeon scan) is waiting.

Times are forecasts from a bounded search. Default estimates are 10 seconds per kill, 3 seconds per interaction and 60 seconds for work whose count/rate is unknown. Native map dimensions and movement speed scale geometric distances. When dimensions are unavailable, the report identifies its illustrative zone scale. Every leg uses a straight-line travel estimate. Shortest Path Forever is never used for planning, so camps and step order are the same with or without it. Camps (about 100 yards) and stops that share one step (about 45 yards, such as two quest givers in one building) are measured in yards on the map, so the same spacing groups the same way in a small or a large zone. Kill XP in the level forecast assumes creatures of your own level (5 × level + 45 each). Multiple separate loot streams, transport, inventory consumption and custom escort state require further verified data. Live Forever behavior needs in-game confirmation.

The report includes expected travel, kills, hand-ins, same-work nearest-first comparison and unavailable quests, each listed by name and ID with one plain reason. If other players are farming a camp, click **Busy** on the guide (shown on kill and collect steps) or type `/qs plan busy`: the route uses another camp for 5 minutes and the chat names it. **Mark selected camp busy (5 min)** marks the selected objective's camp busy for five minutes: the step moves to a free alternative camp when there is one, and if every camp is busy the guide prices a wait for the camp that frees up first. Visible quest, bag, spell and level changes refresh from the zone cache. Meaningful movement can update the order every three seconds while open. Small estimated improvements retain the prior feasible route. The first explicit discovery reads the quest-ID catalogue cooperatively through the shared data scheduler. Later updates reuse the last two zone ID lists and a bounded source cache.

Commands include `/qs plan all`, `/qs plan xp`, `/qs plan selected 123 456`, `/qs plan budget 30`, `/qs plan range`, `/qs plan unrestricted` and `/qs plan why`. The guide's Plan button and `/qs plan options` open **Settings > Quest guide**, where the goal, time limit, quest IDs and level range are saved settings (a command such as `/qs plan xp` saves them too), with **Mark selected camp busy**, **Clear camp waits**, the learned pace and the plan report. While the guide is open it times your kills (the gap between two kills of the same objective) and quest giver visits (quest window open to accept or hand-in). After 5 samples each, your own median (4-40 s per kill, 1-15 s per quest giver) replaces the 10 s and 3 s defaults; **Reset learned pace** forgets it.

**Shared camps.** Turn on *Show shared camps on the world map* in **Settings > Quest guide** (off by default), or type `/qs plan camps`. With the Quest guide open, the world map of your zone shows a circle for each camp of your planned kill and collect quests: at least 5 spawns within 100 yards, the guide's own camp size. A blue circle serves 2 or more quests, so one visit helps several of them; a grey one serves one quest. Hover the small label (A1, A2, ...) for the mobs, their spawn counts and quests; click it for a waypoint. The circles never block map clicks and hide during combat. The **Camps** button on the Quest guide (beside the step counter), **Camps table** in Settings, or `/qs plan camps table` opens the **Shared camps** window with three views: a network (quest → mob or object → camp, line width = spawns there), a map of the zone with every spawn, the camps and the quest givers, and a matrix of camps against objectives with the spawns in each cell (darker = more). Click an objective button at the top, or a mob in the network, to highlight it in all three; click a camp for a waypoint. Camps are named by the nearest quest giver, such as "A2 - 120 yd SW of Talin".

The route appears in an opaque dark guide beside the game's quest tracker; drag its header to place it where you want, then use **Lock** to keep it there for the session. The header shows the zone and current/total step. The current step is highlighted in gold on dark red; up to five upcoming steps are muted beneath it. **< / >** reviews previous/next steps and marks the destination; this does not complete quests. **− / +** switches between expanded and current-step-only views. Each step says where to go and which quests to take, complete or hand in; pickup and hand-in steps name the quest giver once, e.g. "Pick up from Sentinel Hill Giver:" then the quests. Click a step to set its waypoint (this also works in combat), or use **Waypoint**. Open the map with `M` to see the pin. Changing zones immediately clears old steps before building the new zone's plan. With the green/yellow filter enabled, if every mapped quest in the zone is below green, the guide says **This zone is too low level for you.** Long rows grow to fit their text while scrolling. With Shortest Path Forever installed, **Follow with SPF** hands the selected stop to SPF to draw and guide the walk on both maps. This is an explicit action and replaces the route currently being followed. You can also use `/qs plan follow`. It updates after quest progress, and **Refresh** is available if needed. Completing an objective or quest rescans eligibility; progress-only count changes rebuild the current steps. `/qs plan next` selects the next step and sets its regular waypoint; `/qs plan refresh` rediscovers the zone list; `/qs plan hide` closes the panel; `/qs plan on` enables the tool; `/qs plan off` disables it and closes the panel. Following a step does not move your character or accept/complete quests for you.

**Direction arrow and map route.** While the guide is open, a green arrow above it points toward the selected stop relative to your facing. The caption names the action and destination; the distance is in direct yards, with a compass direction. At the destination it says to follow the quest step; arrival does not accept, finish or skip a quest. Missing position/distance/facing data is labelled rather than guessed; delayed measurements recover automatically while the guide is open. The arrow follows the guide when you move it and disappears when you close it.

Open the world map normally to see numbered quest stops and connecting lines; the selected stop is highlighted. Click a number to select that step and set its waypoint. Stops at the same spot share numbers, and repeated clicks cycle through them; the selected number remains visible and its marker uses its exact position. The connections show stop order, not a path around terrain; **Follow with SPF** remains the way to request terrain-aware guidance. Map interactions hide during combat while the read-only arrow keeps updating. The overlay uses addon-owned drawings, and it reads no extra quest database data. Stationary map geometry is reused and all guidance updates stop when the guide closes.

**Travel limits:** SPF is optional and only draws the walk for **Follow with SPF**. That guidance follows SPF's data and water-walking settings; no strict no-swimming promise is made, and SPF may combine travel modes when guiding. The plan itself uses map-distance estimates for every stop, so a river or cliff between you and a camp is not priced in. Questie points often have no height, so cave entrances, stacked floors, elevators and underground connections need in-game checking; an unknown floor is not guaranteed correct. Without SPF, the game's waypoint marks the stop but does not draw a path. The guide may miss quests whose Questie points cannot be mapped to your current area.

**Item source hints and map search.** Turn on **Show where items come from when I hover over them** to add vendor types such as
**General Goods** to bag and recipe item tooltips. Known mining nodes are labelled **Mining**. Questie stores vendor links
and object names, but does not mark every gathering profession or craft recipe, so unrecognized source types are not guessed.
**Where to gather.** With the same setting on, hover a hide, leather, cloth, meat, herb or ore item (in your bags, the bank or the Professions window) to see the three best places for you, one line each with name, zone and chance, for example "1. Plains Wolf · Westfall · 61%" (a node says "node"). Places that fit come first: creatures at most 3 levels above you, outside the other faction's home zones (its starting zones and the zones right after them); then the most items per visit (known spawns × chance). If nothing fits you, the best places overall are shown. One creature per zone, friendly creatures and chests are skipped. A cooking ingredient's own "Where to gather" lines then keep only fish and vendors, so drops are not listed twice. The map pins add the creature level and spawn count. **Ctrl+right-click** the item to mark every one of those spawn points on the world map with the item's own icon and to set the game's waypoint on the first zone; Ctrl+right-click it again to remove the marks. The addon never opens the map itself: press `M` and zoom out to see zones elsewhere. On a Mac, Cmd+right-click works too. Skinned items (hides, leather, scales) come from a small bundled table of which creatures can be skinned for what and how often, because QuestieDB has no skinning loot (data from CMaNGOS classic-db, regenerated with `tools/build_skinning_data.py`); herbs and ore list their nodes. If an item shows nothing, `/qs gather` says why in one sentence, for example "Copper Bar is not something you gather, so no places are listed.". Needs QuestieDB; the first hover of a common hide reads many creatures in the background, so the lines may appear a moment later, and not during combat.

**Map search requires a recent QuestieDB database; it cannot search on its own. QuestieDB can run without the full Questie addon.**
Install/enable QuestieDB and `/reload`, then run `/qs questie` to check that its data is available.
The map panel explains when the database is missing or too old, instead of reporting a misleading empty search.
Turn on **Search items and vendors on the map**, open the map with `M`, and type an item name or vendor type such as
`General Goods`. Type `vendor` (or `all vendors`) to highlight all known sellers on the displayed map; type
`general vendor` to highlight only its general sellers. These searches never add pins from another map; browsing a new
map updates the results. Sellers are recognized from Questie item links, vendor flags (including NPCs without titles),
or known merchant titles; unrelated titled NPCs such as trainers are excluded from `vendor` results without seller evidence.
The search panel sits in the map's bottom-right corner. Suggestions appear above it in a solid dark panel with a border
and larger white text; click one or press
Tab to complete it. Suggestions only include roles and buyable items with known locations on the displayed map;
changing maps updates both suggestions and pins. Partial titles also match, so `tail` finds local **Tailor**,
**Senior Tailor** or **Senior Master Tailor** roles. Choosing **General Goods** searches matching NPC titles even when
Questie has no item-to-seller links for that NPC. Choosing an item searches sellers of that exact item.
Class trainers such as `Druid Trainer` and `Paladin Trainer` are also searched by their NPC titles; they do not need
an item seller link. Discovering these unlinked trainers requires Questie's enumerable NPC list.
Role search accepts common English profession names and variants: `skinner trainer` finds **Skinning Trainer**,
`miner trainer` finds **Mining Trainer**, and `leatherworker trainer` finds **Leatherworking Trainer**. Plurals,
punctuation and word order are flexible. A small typo such as `paladin tranier` is also tolerated; exact or partial
matches on the displayed map take priority, and suggestions show the actual role title. Typo correction is limited to
one spelling error in role words of at least five ASCII letters; short/localized words retain literal matching.
Item searches keep their existing literal matching, and choosing an item still searches that exact item name.
The panel names the map and reports the search text and number of known locations. Hover a pin to see the matching role,
query and coordinates; click it to set a waypoint. Click **Clear** or delete the search text to
remove the pins. The magnifying-glass button inside the search bar runs the search. Buyable items and reagents appear when
Questie links them to vendors. Searches stay on the displayed map by default. If there are no local pins but known matches
exist, click **Elsewhere**: it finds the closest known match on your continent by map distance and sets the waypoint at once, naming its zone. Changing the query or displayed map restores local search. Ctrl-right-click also searches only
the displayed map. Search needs a recent QuestieDB NPC or item list; older providers with only item enumeration have
partial role coverage. Missing item seller links are explained; drops, gathering and crafting are not searched.
Results use one map view; there is no separate location-list view. Suggestions are labelled by kind (Trainer: Paladin Trainer,
Vendor: General Goods); single words are offered only while you are still typing a word. In combat the search waits until the fight ends.

**Lightweight data loading.** Login, a closed map and an empty search do not build these catalogues. The first letter you type starts building reusable NPC role metadata once; later keystrokes continue that work instead of restarting it, and it pauses while the map is hidden or the search box is empty. A matching role query does not load the item catalogue, and a "vendor" query reads no item at all when QuestieDB marks vendors with its vendor flag. Item fallback checks each item's name against what you type and reads the seller links only of the items whose name has your words (typing a longer text with the same words keeps that scan, other words scan again). NPCs that are friendly only to the other faction get no entry. The search itself starts after a brief pause in typing. Suggestions appear as soon as the first match on the displayed map is found, earlier suggestions stay visible while you refine the text, and the panel shows progress such as "Indexing 3,200 / 10,122 NPCs". Locations are decoded only for the current query's candidates, including spelling alternatives, and kept in a bounded cache between keystrokes; the cache is cleared on a map change, on **Clear** or an empty search, and when the database goes away. Disabling map search releases its indexes. The guide and map search share a soft 2 ms work budget per 100 ms slice (searches you type get 8 ms while the map is open) and suspend database work in combat; a single provider call can exceed that budget. Hiding a tool stops its scans. Questie and QuestieDB manage their own loading and caches independently. Quest reward and dungeon catalogues also start only when you open their Adventurer's Journal tabs.

**Quest acceptance and turn-ins.** Under `/qs settings` > **Accept & turn in**, enable **Accept quest offers automatically** to
accept a quest when an NPC or party member presents it. Enable **Turn in completed quests automatically** to continue a ready
turn-in and take its reward when there is no choice or only one reward choice. Quests with multiple choices or a
required payment stay open for you. Both options are independent and off by default.

**Dungeons, boats and zeppelins on the world map.** Open the map with `M`: a skull marks every dungeon and raid
entrance (one pin per entrance, so Blackrock Mountain lists its five instances), and a lettered square marks each boat
(B), zeppelin (Z) and Deeprun Tram (T) stop, coloured blue for the Alliance, red for the Horde and white for neutral ones.
Hover a transport stop to see where it goes and the lines to its other stops (the whole line shows on the Azeroth map;
on a continent map the tooltip says so when the other end is overseas). Hover a dungeon to see its instances with level
ranges and, for each faction, the closest town with a flight master that faction can use, with a line and a label to each.
Click a dungeon or transport pin to set a waypoint there. It is **on by default**; switch it off with **Show dungeons, boats and zeppelins on the world map** in Map, and pick **My faction** (the default), **Both factions**, **Alliance only** or **Horde only** with **Whose boats, zeppelins and towns to show** (neutral routes and towns always show, in white). It needs no
QuestieDB. The positions are typed in from memory of the Classic Era world, so expect them to be 1-3 % off.

**Your trainers on the map.** On a zone or continent map (not the Azeroth overview) the trainers for your class and
for the professions you know, cooking, fishing and first aid included, appear by themselves with a gold rim, using the
class icon or the profession's tool. Only trainers your faction can use are shown; trainers standing together share one
icon. Hover for names and places; click to set a waypoint. It is on by default, needs QuestieDB (it reads the trainer
list once in the background after you first open a map) and is switched with **Show my class and profession trainers
on the map** in Map. The search box's pins use the same icons per kind of NPC.

**Zone levels on the world map.** Open the map normally with `M`: continent maps display level badges
over outdoor zones, and a small **Zone levels** panel shows the range for the zone you view or hover.
Badges are coloured like quests for your level (yellow: your level, orange/red: above you, green/grey: below you; grey ? = unknown), and the panel shows your level.
Choose a continent/zone from the world overview to see its details. This is **off by default**; enable
**Show zone questing level ranges** in Map to display it. Labels do not intercept map clicks and
follow map resizing/zoom.
When upgrading from v0.4.11, the option is switched off once; your subsequent choice stays saved across reloads.

Valid player-level map data from the client takes priority. When it is missing or zero, built-in **Zone guide**
ranges cover the 39 Classic questing zones, Zephras Isle and Riverglades, without another addon. Mount Hyjal
and Shen'dralas have explicitly labelled **Known quests** spans from verified quest records; these show the
levels of known quests, rather than claiming a complete recommended bracket. Hover/view a zone to see the
source label. Cities and Moonglade show **City** or **Sanctuary**. Native data arriving later replaces a guide.
**?** or **range unavailable** is reserved for areas without either valid native data or a verified fallback.
Ranges do not guarantee quest availability for your class or faction. Quest/minimap symbols remain removed.

**Highest learned spell ranks on your action bars.** Enable **Auto-update spells to highest learned rank**
in Professions & character (off by default). It upgrades existing player spell buttons across normal action-bar pages,
including hidden/form pages and duplicate copies, to the highest rank you have learned. It checks when enabled,
at login, after learning spells and when spell buttons change. **Update ranks** runs one update now and reports
its result, even with the automatic option off. This does not train or buy spells; macros, items, pet actions and unranked abilities stay unchanged.
While enabled, deliberately placing a lower-ranked spell on a normal bar also upgrades it.

Updates wait until you leave combat, temporary/vehicle bars end and you finish dragging anything on the cursor.
Unknown or ambiguous rank data is skipped; if the client refuses a replacement, updates pause until `/reload`
and report the problem. Turn the option off to keep lower-ranked buttons; disabling it does not undo upgrades.
Action bars supplied by other addons work when they use the game's normal action slots; custom secure actions
and spells written inside macros are not edited.

**Ask in chat to do this quest.** Right-click a quest in the Party quests window and choose this action to put
`Anyone need [quest]? Wanna group up?` straight into your current chat. The actual quest is linked; no invitation
editor opens. Select World (or another chat channel) first to ask there, review the message, then press Enter.
An existing draft is kept, and duplicate quests or messages that exceed the chat limit are rejected.

**Quest invitation (optional editor).** For a longer role-play invitation, use `/qs adventure`
(optionally followed by a quest ID, exact title or quest link), or *Settings > Quest sharing > Quest invitation*.
It chooses an unfinished quest from your log; **Next quest** browses the others. Pick a chat, edit the text,
and click **Prepare chat** before pressing Enter to send.

> Hail, fellow adventurers! I seek brave companions for [Wolves Among Us] in Elwynn Forest. Who will join me and share the adventure?

Edit the invitation if you wish. Pick the chat with a button: **Current chat** keeps the active chat (including its whisper
recipient or a channel such as World), or **Say**, **Party**, **Raid**, **Guild**, **Channel 1** (usually General) or
**Whisper target** (the player you have targeted). **Prepare chat** writes the message into your chat
box; **press Enter to send**. This also applies when the other features send immediately. With Current chat, an existing
draft is kept and the invitation is appended only if it fits; changing channels asks you to send or clear that draft
first. Completed/abandoned quests cannot be advertised. Generated invitations fit the 255-byte chat limit; unusually
long quest links fall back to a shortened plain title. This works without a party or Questie.

**Fishing spots on the big map.** `/qs fishing` opens the Fishing spots window. Add a lake, river, coast or fishing pool by name,
map ID (the zone name shows beside it) and X/Y coordinates (0–100); **Use my position** fills the coordinates of where you stand.
On clients with map cursor support, enable the fishing layer and **Alt-click a body of water on the big map** to
start a new marker at that exact location.
Enter its minimum fishing skill, skill needed to avoid getaways, fish list and notes such as season or time of day. Leave unknown
skills blank. **Save water**, then turn on **Show saved spots on the world map** (Settings > Professions & character): the map has a fishing icon,
water name and minimum skill (or skill unknown) at that location. Hover for the fish and other details; click the icon to edit it.
Use the editor's saved-water list to revisit any location, with Previous/Next for more waters. Each body of water
has its own record, including multiple waters in the same zone. Your notes persist across sessions and settings
resets; **Delete selected** removes just that water.

Installing [AnglerAtlas](https://www.curseforge.com/wow/addons/angler-atlas) adds a scrollable **zone overview** with
the zone's fishing skill and fish. That overview is read from the installed addon; zone estimates and provisional
Forever data remain labelled. **There is no built-in verified catalogue of every individual water:** markers and
their specific fish/skill values are entered by you, and zone summaries are not copied onto individual waters.
The fishing layer works alongside Questie.

**Cooking inside the game's profession window.** Open Cooking normally. The native window now contains
one scrollable list of all reference recipes, with a separate **Skill** column and a short source line.
Learned recipes use gold text; unlearned recipes use readable grey text and remain clickable. Search
recipes, ingredients or acquisition sources without paging through separate screens.

Select a learned recipe to use WoW's existing crafting pane and controls. Select an unlearned recipe to
see **Requires Cooking**, **Where to learn**, and **Ingredients** in the same right-hand space; hover an
ingredient for mob/zone/fishing information. Unknown learned status or source data is explicitly labelled.
The list uses 133 bundled Forever reference records plus additional live Cooking recipes when available;
unsupported/obsolete client records can still appear. Native recipe filters are left unchanged.

The fishing editor's **Cooking / recipes** button, `/qs cooking`, and `/qs professions` target this embedded
view; if the native window is closed, open it with K and choose Cooking. No separate addon window opens.

Installed Questie supplies ingredient drop mobs, mob levels, coordinates and sellers; the existing zone
reference supplies zone brackets. Seven example fish waters have guide-backed routes, and AnglerAtlas can
add zone estimates. Fishing skill numbers that are not recorded say **not known**, separate from the recommended
route skill; "fish stay hooked from skill N" counts pole and lure bonuses. Waters in a faction home zone are tagged **(Horde area)** or **(Alliance area)**, and your own faction's waters come first. Catches may vary by water, season and time.
Recipe facts are checked **2026-11-17**, using the MIT-licensed [Profit Forever dataset](https://github.com/ExcEssIv3/profit)
and [Forever profession guides](https://www.wow-professions.com/forever); some guide details remain beta-derived.

The integration is on by explicit request. Disable it in **Professions & character > Cooking recipes** or `/qs professions off` to restore the native view and suppress item farming hints.
Manual `/qs cooking` or `/qs professions` re-enables it. No login catalogue scan, filter toggling, automatic
crafting or runtime downloads; live recipe reads pause in combat and stop on close or profession changes.

**One search window.** `/qs rewards`, `/qs loot` and `/qs dungeons` open the same **Adventurer's Journal** window. Switch between
**Quest rewards**, **Instance drops** and **Dungeon quests** with its tabs. Item rows have icons, quality colors, item/required levels
and a source line; hover for the game's comparison tooltip. Click a row to update the route or drop-source pane
on the right. Selecting more items never opens additional route/source windows.
Each equipment name appears **once**, with every matching mob or quest listed together in its details.
The Adventurer's Journal has a WoW-style look: native red/gold buttons and tabs, warm framed lists,
item-slot borders, gold selection highlights and readable parchment source/quest pages with dark text.
The look is shared by all three tabs, including their search fields and dropdowns; existing filters and actions are retained.
Different item IDs sharing a name are grouped too; details show each version's level, and the comparison
tooltip uses the highest-level matching version. Filters apply before grouping, so only matching sources remain.
**Only Rare (blue) quality and above are listed** in both tabs; green, white and grey items are excluded.
Items with unknown quality stay hidden until their details load. Clear filters keeps this quality minimum, and an
empty list says so: most quest rewards at levelling levels are green, so the Quest rewards tab often has few or no
results below the last levels.

The filter bar applies to both tabs. Click a **dropdown** and choose directly; type in its search field to
find an option, scroll for more choices, or use Up/Down and Enter. Escape dismisses the list. Choose **Weapons**,
**Armor** or **Accessories**, then a specific **Item type** and/or **Slot**. Changing category clears an incompatible
slot/type selection. Class, faction and dungeon source also use direct dropdowns.

**Search as you type** for an item, quest, boss, zone or dungeon; Enter still applies immediately. The **Clear**
button or Escape in a search field clears it. Scroll over results or the dungeon list with the **mouse wheel**;
Up/Down while the result search field has focus selects items and moves between pages. Previous/Next are still
available and become inactive at list boundaries. Details open automatically for the first visible result;
click or arrow to another item, and selection stays put across item-data refreshes when still visible.

For **Level range measures**, choose **Required level** or **Item level**, then enter **Min**/**Max**. Bounds update
while typing; Enter or **Apply** works too. Bounds are inclusive and blank means unrestricted. Invalid or reversed
ranges keep the last valid range and explain the problem. **My level** sets the required-level maximum to your
current level without a lower bound. **Sort** by highest item level, lowest required level, or name.

**Stat filters** work in both tabs. Choose up to three bonuses from the searchable stat dropdowns and enter a
**Min bonus** for each: for example, **Intellect ≥ 10** and **Stamina ≥ 5**. Every selected condition must match;
minimums are inclusive, blank means 1, and choosing **Any stat** removes that condition. Minimums update while
typing or on Enter; invalid values keep the last valid filter. Primary attributes, armor, attack/spell bonuses,
healing, regeneration, combat ratings and resistances are available. Ratings use points, not percentages.
Only bonuses reported by the client's item-stat API can match; procs and unreported bonuses are not evaluated.
Missing stat data stays hidden while a condition is active; clients without the API show an explanation.

**Clear filters** clears the shared type/slot/range/stat/sort controls and the active tab's searches. On the dungeon tab
it also returns to All dungeons/All encounters; on the quest tab it shows all quest levels while keeping completed
quests hidden and preserving character/class/faction. Blue quality and above remains enforced. Empty results
explain how to broaden the search; pending item data is labelled as loading.

**Find quest equipment for your character.** `/qs rewards` opens the Adventurer's Journal on its **Quest rewards** tab. It starts with your
class, current level and faction. Change class or faction with their buttons, edit the character level and
wait briefly or press Enter, or search for an item, quest or zone. **Quest levels: near** shows quests from ten levels below to three
above your selected level, while still requiring their minimum acceptance level and the item's required level to
be within reach. Switch that filter off to browse lower-level rewards too; untick **Hide completed quests** to include quests you already completed. **My character** restores your own filters.

Each result shows the item, its item/required levels, quest and starting zone; the details pane includes the slot and quest level. Hover to see the
game's item tooltip and equipped-item comparison. Click for the quest giver, coordinates and prerequisite quests.
For example, a level-20 Alliance Druid sees the few blue staffs, leather and cloth rewards of ordinary and Druid
quests; the many green rewards at that level are not listed. Results start sorted by item level; compare the actual stats for healing, casting or feral play.
Class equipment families follow Classic rules, so item-specific restrictions and any Forever proficiency changes
must be checked in the tooltip. Race restrictions use QuestieDB's active faction masks and your own race when
browsing your faction. Prerequisites, reputation, skills and other quest conditions may still block acceptance;
the list is a planning tool, not a promise that every quest is immediately available. Reward choices are alternatives.

The Quest rewards tab needs a recent **QuestieDB** (its item list, quest rewards and class/race data); without it the
tab says "Install or update QuestieDB (see /qs questie)". It scans only when opened/refreshed, in batches,
and stops if disabled or its tab/window is closed. Uncached item details update when the game supplies them. **Refresh data** rereads the source.
**Mark quest giver (then press M)** puts a map pin on the first listed quest's giver, the same as in Dungeon quests;
open the map yourself with `M`, avoiding this client's protected-map restrictions.
Both tools are covered by Lua mock tests; their rendering and item tooltips still need verification in the game.

**All quests for a dungeon, inside and outside.** `/qs dungeons` (or **Items & dungeons → Dungeon quests**)
opens the **Dungeon quests** tab. Inside a dungeon it opens on that dungeon. Choose a dungeon to see its known quests, including pickups outside the entrance,
outdoor preparation chains and explicit follow-ups. This lists quests regardless of their rewards; equipment quality,
slot and stat filters apply only to the equipment tabs. The tab opens for your character: your faction, class and level,
including completed quests, and reads only the quests that match (a quest for the other faction or class, or one that needs
a higher level, is not loaded, which keeps memory use down). Select **Alliance/Horde**, a **class**, or enter your
**character level** to change the list; a filter that reaches past what was read (another faction or class, a higher level,
**Quest levels: all**) reads the rest, and a narrower one reuses what was read. **My character** applies your current
faction/class/level; **All quests** broadens these filters while keeping the selected dungeon.
Tick **Hide completed quests** or **Hide quests in my log** to shorten the list. **Plan route to get them all** opens a read-only route: the shortest way from where you stand to pick up every quest of the chosen dungeon you can take now, with your known flight paths, boats/zeppelins/tram and your hearthstone, ending at the dungeon entrance (click a step for a map pin; times are estimates). Each row uses the game's own quest-giver marks: a yellow **!** for a quest you can still pick up, a yellow **?**
for one already in your quest log, and a green tick for a done quest. A quest you cannot take yet (level, faction)
keeps a plain note icon and shows its level requirement in red. Gold only marks the selected row.
Search by quest name, ID or dungeon; scroll or use Previous/Next. Preparation and follow-up entries are labelled.
Each row labels **Chain quest** (prerequisite, dungeon step or follow-up) or **Standalone quest**, separately from its
**Task**: **Talk only — speak to [NPC]**, collect items, defeat enemies, explore, deliver an item, or complete an event.
A chain step can also be talk-only. Chain steps are nested in the list (each step under the earlier one it needs, one tab
deeper; a chain that fits on one page stays on one page). A done step gets a green check mark and grey text, and so does an earlier step whose later step you finished
(nobody offers it any more). Click a step: the right panel shows its status, what to do, where (click the giver or the hand-in NPC for a map pin), rewards (hover an item for its stats) and its previous/next quests.
Unknown tasks are labelled for checking the quest details.
**Pickup** and **Turn-in** giver/location lines remain visible; five taller rows fit each page.
Hover for **base XP**, all known item rewards (including non-equipment), and full pickup/turn-in locations.
XP is before character-level/bonus adjustments; listed items can be reward choices. Missing data stays labelled unknown.
Item rewards load on the first hover, in small background slices, and refresh the tooltip when ready.
Click a quest for its pickup giver/item, coordinates, requirements, chain and objective/turn-in directions.
Right-click for the usual Quest Sharing menu plus **Where to pick it up** and **Mark quest giver (then press M)**.
Pickup actions mark a native waypoint when supported and print directions; open the map yourself with `M`.
Quest-log actions explain when you must accept the quest first; unknown dungeon coordinates are never pinned at `-1,-1`.
Needs a recent QuestieDB (see `/qs questie`). Association uses dungeon categories and known quest-source/objective locations;
common materials also dropped outdoors do not associate unrelated quests with a dungeon. The list depends on installed
data, and filters do not check every reputation, profession, event or acceptance condition. Scans run only on explicit
open/refresh (reward links on first hover), share the small data-work budget, pause in combat and cancel when the tab closes;
no login scan or new saved setting.

**Instance drops and who drops them.** Opening the **Instance drops** tab inside a recognized dungeon selects that dungeon
and brings its navigation row into view. This also works after the catalogue finishes loading. Old item/dungeon
searches and encounter choices are cleared; an explicit `/qs loot [search]` keeps that query inside your current
dungeon. Shared equipment and stat filters remain. Browse other dungeons normally afterward; unknown or
ambiguous locations, raids and outdoor areas keep your browsing context.

Click **Browse drops** under *Settings > Items & dungeons > Instance drops*, click the
**Instance drops** tab in the Adventurer's Journal, or type `/qs loot`. Use **Find dungeon** to narrow
the list on the left, then click a dungeon to browse its drops. **Search item, ID, boss or dungeon** searches
within the selected dungeon; **All dungeons** searches the dungeon catalogue. You can also start with
`/qs loot VanCleef` or `/qs loot 5191`. The **Source** dropdown lets you choose an encounter directly, including
trash and chest groups with equipment drops. Both instance and item lists have Previous/Next pages.
Only weapons and wearable equipment are shown: armor, shields, necklaces, rings, trinkets and offhands;
materials, consumables, bags and other non-equipment are excluded.

Every result shows the item, instance, boss/creature or loot group, and difficulty when supplied. Hover for its item
tooltip and equipped-item comparison; click for all matching sources. Multiple bosses share one item row,
with each mob listed once and its difficulty labels combined. Shared quest rewards likewise list every eligible
quest route in one pane; **Mark quest giver** uses the first quest listed. Trash tables describe a shared group rather than a particular creature; the Adventurer's Journal does not invent a
specific NPC or a drop percentage when the catalogue does not provide one.

For encounter loot tables, install/enable a compatible **AtlasLoot** and its **DungeonsAndRaids** module, such as
[AtlasLootClassic (Forever & Era Fix)](https://www.curseforge.com/wow/addons/atlaslootclassic-forever-era-fix).
The **Instance drops** tab reads the installed catalogue at runtime and includes **Classic and Forever dungeons**.
**Raids, world bosses and unidentified encounter collections are excluded**, even if they contain equipment.
Dungeon classification comes from AtlasLoot's content category or known dungeon IDs; coverage follows the installed
catalogue. Dire Maul wings without InstanceID are supported by their known dungeon area. Without compatible AtlasLoot tables, **QuestieDB** provides a clearly labelled **partial**
list of item sources whose creatures or objects are known to be inside recognized dungeons; raid interiors and
unknown instance areas are excluded. Some Forever areas cannot be identified by that fallback. QuestieDB alone is not a complete
dungeon loot database. Without either source, the tab's status line says what to install. No loot database is bundled here.

Indexing and game item-name requests happen only while the Adventurer's Journal is open, in small batches. Names update when the
game supplies cached data; items stay hidden until a recognized equipment slot is available. **Refresh data** rereads the catalogue.
If an unloaded AtlasLoot module cannot load during combat, it is retried after combat. These flows are tested with
Lua mocks and actual AtlasLoot source data; the GUI still needs an in-game check.

## Install
**Easiest:** download the [latest Quest Sharing release](https://github.com/YodaGitMaster/QuestSharing/releases/tag/v0.4.22), unzip `QuestSharing-<version>.zip` and drop the
`QuestSharing` folder into `Interface\AddOns`. Or:
1. Copy the folder `QuestSharing` (the one containing `QuestSharing.toc`, not this README's folder) into
   the game's `Interface\AddOns` folder, so you have `...\AddOns\QuestSharing\QuestSharing.toc`.
2. Start the game; on the character screen click **AddOns** and make sure **Quest Sharing** is ticked
   (tick **Load out of date AddOns** if the game says it is out of date).
3. Optional: install **Questie** too. Quest Sharing only reads its quest database (where quests start, which
   quests come first) for the Quest guide and "Tell them where to get it", and on clients where the game cannot say which creatures your
   quests need, it adds their names (only when Questie's language is the game's: names on screen are in the game's
   language). Core party sharing works without it; map search and other database-backed tools require compatible QuestieDB data.
   QuestieDB can also run without the full Questie addon. **Questie 12 comes as two folders, `Questie` and `QuestieDB`** (its
   quest data): download the `Questie-v...+v....zip` under *Assets* of
   [Questie's latest release](https://github.com/Questie/Questie/releases/latest) (not "Source code") and copy **both**
   folders into `Interface/AddOns`. QuestieDB alone: [QuestieDB's releases](https://github.com/Questie/QuestieDB/releases/latest). Type `/qs questie` to check it: it says, for each of the two,
   whether it is loaded (with its version) or why not (not installed, switched off in the AddOns list, marked out of
   date, a folder with another name such as `Questie-master`), what to do about it, how the data is read, the language
   of its names, and looks up a few quests of your quest log.
4. Optional: install [Shortest Path Forever](https://www.curseforge.com/wow/addons/shortest-path-forever) for walkable guidance from the Quest guide. Quest Sharing still works without it.
5. In game type `/qs probe`. It tells you what your game client supports. **If something looks wrong,
   open an issue at https://github.com/YodaGitMaster/QuestSharing/issues and paste that output.**

## Commands (`/qs` or `/questsharing`)
| Command | What it does |
|---|---|
| `/qs lfg` | party finder: search your listing's dungeon and invite (needs your group listed) |
| `/qs lfg healer\|tank\|dps on\|off` | which roles the party finder invites |
| `/qs lfg ilvl <n>` / `level <low> <high>` / `unknown invite\|skip` / `watch on\|off` | party finder filters |
| `/qs ilvl` | your item level and how many players' item levels are remembered |
| `/qs share` | share your quests in this area with the party now, repeating earlier offers and declines (one quest per use where the game only allows sharing on a click) |
| `/qs shareclick on\|off` | share only when you click Share (comes on by itself where the game refuses automatic sharing) |
| `/qs stop` | cancel a share in progress |
| `/qs on` / `off` | switch the addon on / off |
| `/qs auto on\|off` | share automatically when you join a party or someone new joins (default on) |
| `/qs new on\|off` | share a quest once when you accept it while in a party (default on) |
| `/qs area zone\|all` | share only this zone's quests (default) or every quest |
| `/qs gap N` | seconds between two shared quests (default 4, from 2 to 30) |
| `/qs chat on\|off` | announce quests in common in party chat (default off) |
| `/qs click on\|off` | clicking a tracked quest fills the chat box (default on) |
| `/qs link on\|off` | shift-click links get the status appended (default on) |
| `/qs mode box\|send\|print` | how your messages go out (the ring, the menu, quest clicks): **box** types them into the chat box and you press Enter (default; works on every client), **send** sends straight away where the game allows it, **print** only shows them to you |
| `/qs sync on\|off` | exchange exact quest lists with other Quest Sharing users (default on) |
| `/qs announce on\|off` | say in party chat when a quest we share is done (default off) |
| `/qs markers on\|off` | star and names next to shared quests in the quest log (default on) |
| `/qs panel [on\|off]` | `/qs panel` or `on` shows the "Party quests" window while in a party (default on), `off` hides it; drag it to move it, click a row to put your progress in the chat box |
| `/qs near [on\|off]` | keep the quest tracker filled with the quests closest to you (default on) |
| `/qs near N` | how many quests it keeps (default 5) |
| `/qs near mode auto\|distance\|zone` | `auto` uses distance if your client can measure it, otherwise your zone |
| `/qs near now` / `resume` | refresh now / end a pause early |
| `/qs` | two lines pointing to `/qs settings` and `/qs help` |
| `/qs help` | every command |
| `/qs settings` | open the settings window |
| `/qs map` | the world map switches and where they are in the settings |
| `/qs adventure [quest ID or exact title]` | preview a role-play invitation for an unfinished quest, then prepare it in any chosen chat |
| `/qs friends` | (beta) add everybody in your party to your friends list now |
| `/qs friends on\|off` | (beta) do it automatically when a party forms or someone joins (default off) |
| `/qs key [KEY]` | bind the quick chat wheel to a key, e.g. `/qs key V` or `/qs key ALT-E`; `/qs key none` removes it |
| `/qs quick ...` | the quick chat messages: `add [label \|] <text>`, `edit`, `label`, `route`, `remove`, `move`, `reset`, `editor`, `mode hold\|toggle`, `channel auto\|say\|party\|whisper`, `on\|off` |
| `/qs highlight mobs\|pin\|cvars [on\|off]` | quest icons over creatures / pin the nearest quest / the game-settings helper |
| `/qs doctor` | readable issue overview; Copy all includes setup, settings, errors and logs |
| `/qs memory` | memory used by Quest Sharing and QuestieDB, and which catalogues (dungeon quests, rewards, dungeon loot, map search) are loaded; they are kept until you log out |
| `/qs memory purge` | free everything read from QuestieDB and delete the saved ID lists (same as Settings > Items & dungeons > Purge); each reads again the next time you use it |
| `/qs errors [clear]` | open the combined diagnostic report; `clear` empties only recorded errors |
| `/qs bagmarks on\|off` | quest items marked in your bags: gold for quests of this zone, blue for quests elsewhere (default on) |
| `/qs bookmarks [on\|off\|list\|clear]` | Space on a bag item bookmarks it so it is never sold (default on); `list` and `clear` manage the bookmarks |
| `/qs sellgray on\|off` | sell gray items when a vendor opens; bookmarked and quest items stay (default off) |
| `/qs sort [on\|off]` | arrange all bags by topic now; `on`/`off` switches doing it automatically when the bags change (default off) |
| `/qs chatlock on\|off` | no chat typing box while you are in a fight (default off) |
| `/qs cleanup` | review leftover quest item stacks in carried bags and confirm individual deletions; requires Questie |
| `/qs hidetracker on\|off` | hide the game's quest tracker, outside fights (default off) |
| `/qs fishing [on\|off]` | open the Fishing spots window; on/off switches its world-map layer |
| `/qs cooking` | Cooking recipe catalogue, acquisition sources and ingredient farming hints |
| `/qs professions [on\|off]` | embedded Cooking recipe list; no argument opens it, on/off toggles the integration |
| `/qs rewards` | open quest reward equipment for your class, level and faction |
| `/qs loot [search]` | search instance drops by item/name/ID, boss or instance and inspect who drops each item |
| `/qs dungeons [search]` | the Adventurer's Journal's **Dungeon quests** tab: every quest of a dungeon, inside and outside, with pickup places and chains |
| `/qs debug on\|off` | the debug log: every action and its outcome, saved to the addon's file on `/reload` or logout (default on) |
| `/qs log [clear]` | open the combined diagnostic report; `clear` empties only the debug log |
| `/qs minimap on\|off` | the minimap button (default on) |
| `/qs reset` | put every setting and the quick chat messages back to their defaults (saved fishing notes are kept) |
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
- **Party finder.** Searches need a click or key press (the game blocks timed searches); no gear or item level of
  listed players comes from the game (only remembered or shared numbers); the armory cannot be read from inside the
  game; roles of party members who did not join through the finder are only known for damage-only classes.
- **Not tested in the real game.** Everything is tested in a Lua 5.1 interpreter against a mock of the WoW
  API (both the modern `C_QuestLog` style and the classic `GetQuestLogTitle` style, 1043 tests), but I could
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
  not need: for example **E is "strafe right" by default**; `/qs key E` (and the quest item, ping and party finder keys) tells you what the key used to do, in plain words,
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
python tests/test_settings.py         # 77 tests: defaults, migration, direct settings controls, scrolling and enemy ! switch
python tests/test_friends.py          # 42 tests: the friends beta (manual and automatic, safeguards)
python tests/test_quick.py            # 131 tests: the quick chat ring, placeholders, editing, key binding, performance
python tests/test_extras.py           # 45 tests: error log + doctor, invite action, minimap buttons, release zip
python tests/test_highlight.py        # 23 tests: quest icons over creatures, the world pin, the game-settings helper
python tests/test_look.py             # 44 tests: the settings window layout, the key capture, welcome, sounds, ring colours
python tests/test_together.py         # 30 tests: several Quest Sharing users in one party, fewer messages
python tests/test_team.py             # 30 tests: picked up a quest someone has, where the items were, the message budget
python tests/test_where.py            # 18 tests: no raid mark, map icons, a teammate's pin, the pin preferring shared quests
python tests/test_menu.py             # 62 tests: the right-click menu, Questie's where-to-get-it and chain, the sound-key guard
python tests/test_done.py             # 20 tests: a quest you finished is never shared, announced or listed
python tests/test_box.py              # 46 tests: messages into the chat box, refused calls written down (line, stack), sharing on your clicks
python tests/test_ping.py             # 27 tests: the ping key, nearest quest creature, anti-spam, the ring's ping slot
python tests/test_usability.py        # 30 tests: direct choices, live searches, sorting, scrolling, selection and recovery
python tests/test_vendor_map.py       # 108 tests: roles, local sellers/trainers, missing/late data, scope, flags and loading
python tests/test_travel_map.py       # 20 tests (x2 styles): dungeon/boat/zeppelin pins, hover lines, nearest town per faction, my trainers
python tests/test_zone.py             # 10 tests: only the quests of where you are (Teldrassil vs Stormwind)
python tests/test_items.py            # 24 tests: quest item icons in the tracker, the item key and button
python tests/test_emotes.py           # 34 tests: the emote rings behind the mouse wheel, editing them, only the ones that work
python tests/test_bags.py             # 16 tests: quest items marked in the bags, hiding the game's quest tracker
python tests/test_quest_cleanup.py    # 38 checks: cleanup candidates, active/starter protection, fresh confirmation, cursor safeguards and keeping the list after your own delete
python tests/test_questmap.py         # 15 tests: How to do it, and guards against the retired quest map symbols
python tests/test_ringtest.py         # 14 tests: /qs quick test: every slot run, checked against what the game did
python tests/test_log.py              # 47 tests: the debug log: every action and its outcome, kept small, the log window
python tests/test_optional.py         # 42 tests: fishing water notes, map drawing, reward filters and item comparisons
python tests/test_professions.py      # 52 tests: embedded native GUI, grey recipes, scrolling, craft handoff, sources and lifecycle
python tests/test_adventure.py        # 44 tests: direct quest questions, role-play invitations, channels and preserved drafts
python tests/test_equipment.py        # 36 tests: one window, shared filters, rare+ quality, dungeon/raid identity and cancellation
python tests/test_equipment_grouping.py # 28 tests: unique names, merged sources/routes, variants, filtering, counts and selection
python tests/test_instance_focus.py   # 24 tests: current dungeon, batched loads, manual browsing, wing identity and settings tab labels
python tests/test_stats.py            # 20 tests: combined stat minimums, native APIs, cache refresh, live inputs and reset
python tests/test_spell_ranks.py      # 54 tests: learned rank upgrades, normal pages, cursor/combat guards, client APIs and the one-time Update ranks button
python tests/test_ux_b5.py             # 19 tests: Adventurer's Journal wording, row marks, map buttons and README accuracy
python tests/test_zone_levels.py      # 48 tests: native/fallback ranges, full-map missing data, hover, geometry, lifecycle and opt-in overlays
python tests/test_loot.py             # 58 tests: equipment-only instance loot, item/boss searches, source catalogues and asynchronous names
python tests/test_quest_planner_path.py # 4 tests: SPF API detection, the Follow hand-off, fallbacks and no walking estimates in planning
python tests/test_quest_planner_ui.py   # 6 tests: movable panel, wrapped rows, level filter, pickup list and map actions
python tests/test_quest_planner_zone_steps.py # 56 tests: zone isolation, grouped travel/actions, prerequisites, refresh, camp choice, busy camps and planning without SPF
python tests/test_coldridge_valley.py      # 8 tests: the reference case, a level-1 gnome mage in Coldridge Valley on real QuestieDB data
python tests/test_camp_map.py            # 20 tests: shared camps on the world map and the camps table (real Coldridge Valley data)
python tests/test_planner_calibration.py # 12 tests: learned kill/quest giver pace, saved goal settings, goal commands and the plan report
python tests/test_quest_planner_guide.py # 10 tests: current/upcoming states, arrows, mini mode and position lock
```
Expected: every line ends in `passed` with all tests green.

For a local guide emulation, run `python tools/preview_quest_planner.py OUTPUT.html` using the same Lua test environment.
The fragment contains eight illustrative Westfall steps exported from the actual planner, with working step navigation,
mini mode, lock and waypoint preview; it is not the live game or the character's real quest log.

## Files
| File | Purpose |
|---|---|
| `QuestSharing/Compat.lua` | the only place that knows classic vs modern APIs |
| `QuestSharing/Core.lua` | settings, timers, events, chat queue, `/qs` commands |
| `QuestSharing/Share.lua` | party detection, the push queue, reading the game's replies, announcing quests in common |
| `QuestSharing/Sync.lua` | addon-to-addon protocol: hello, full quest list, updates (see the header of the file) |
| `QuestSharing/Progress.lua` | notices finished quests, announces them, sends changes to synced players |
| `QuestSharing/Panel.lua` | the "Party quests" grid (nearest 5 quests x party members) and the quest-log markers |
| `QuestSharing/Track.lua` | keeps the quest tracker on the quests nearest to you (distance or zone mode); can hide the game's tracker |
| `QuestSharing/Highlight.lua` | quest icons over creatures on their nameplates, and the game-settings helper |
| `QuestSharing/Diagnostics.lua` | the error log, `/qs doctor` and the copyable report window |
| `QuestSharing/MinimapButton.lua` | the minimap button |
| `build_release.py`, `CHANGELOG.md` | builds `dist/QuestSharing-<version>.zip` from the .toc allowlist (plus `Bindings.xml`) and verifies it; versions must progress one step from the last `vX.Y.Z` tag (`--bump` starts the next release, `--check` writes nothing, `--force` rebuilds a tagged version) |
| `QuestSharing/Quick.lua`, `QuestSharing/Bindings.xml` | the quick chat ring, its placeholders, the message commands and the key binding |
| `QuestSharing/Friends.lua` | (beta) adds party members to your friends list, with safeguards |
| `QuestSharing/ItemLevel.lua` | item levels of other players: inspect nearby, remember 14 days, ask/share with Quest Sharing users |
| `QuestSharing/LFGFinderUI.lua` | the party finder picker (roles, classes per role, lowest item level, Find) |
| `QuestSharing/LFGInvite.lua` | party finder: one click searches, solo players with the chosen roles are invited |
| `QuestSharing/QuestItems.lua` | usable quest items: icons next to the quests in the tracker, the item key and button |
| `QuestSharing/Bags.lua` | quest items marked in the bags: gold for quests of this zone, blue for quests elsewhere |
| `QuestSharing/QuestCleanup.lua` | on-demand leftover quest item review and confirmed per-stack bag deletion |
| `QuestSharing/Ping.lua` | the ping key: Attack ping on the nearest quest creature, "look here" on quest objects, anti-spam |
| `QuestSharing/Menu.lua` | the right-click menu of the Party quests window |
| `QuestSharing/Questie.lua` | reads Questie's quest database (when installed): where a quest starts, which quests come first, where objectives are done and quests turned in |
| `QuestSharing/Fishing.lua` | optional world-map water markers, saved water editor and AnglerAtlas zone summaries |
| `QuestSharing/Professions.lua` | Cooking source/learned-state model, ingredient tooltips and guarded native-window lifecycle |
| `QuestSharing/ProfessionUI.lua` | embedded scroll list, native learned-recipe crafting and in-place source panes |
| `QuestSharing/CookingReference.lua` | pinned MIT Forever Cooking snapshot with recipe spells, ingredients and acquisition hints |
| `QuestSharing/ProfessionReference.lua` | dated guide-backed starter recipe sources and example fish waters |
| `QuestSharing/Rewards.lua` | optional QuestieDB equipment rewards, filters, item comparisons and quest routes |
| `QuestSharing/EquipmentUI.lua` | one equipment window, shared item type/slot/level/stat filters, item cards and inline details |
| `QuestSharing/SpellRanks.lua` | opt-in highest learned spell ranks on existing normal action-bar buttons |
| `QuestSharing/TravelData.lua` | typed-in dungeon entrances, boat/zeppelin/tram stops and routes, and flight-master towns per faction |
| `QuestSharing/TrainerIndex.lua` | one background scan of QuestieDB for class/profession trainers, and which of them are yours |
| `QuestSharing/CampMap.lua` | the Quest guide's shared camps: world-map circles (blue = 2+ quests) and the camps table |
| `QuestSharing/TravelMap.lua` | world-map pins for dungeons and transports, hover lines and the closest town per faction |
| `QuestSharing/ZoneLevels.lua` | native outdoor-zone questing ranges, click-through map badges and hover panel |
| `QuestSharing/OptionalUI.lua` | shared controls for the optional tools |
| `QuestSharing/Adventure.lua` | role-play quest invitation preview and chat preparation in a chosen channel |
| `QuestSharing/Loot.lua` | searchable instance loot, encounter sources, AtlasLoot adapter and partial QuestieDB fallback |
| `QuestSharing/Marker.lua` | positions on the world map, a pin where a teammate found the items |
| `QuestSharing/Team.lua` | "picked up a quest someone has - let's do it together?" (once per quest, not for shared ones) |
| `QuestSharing/QuestAutomation.lua` | optional quest acceptance and safe quest turn-ins |
| `QuestSharing/Style.lua` | one classic WoW menu look for every window (opaque stone inside the gold dialog border, red panel buttons, recessed edit boxes, check boxes, chat colours) and the good-news sound |
| `QuestSharing/Settings.lua` | the sidebar settings window (plain explanations, direct choices, scrolling, key capture) with the message editor, and the options entry |
| `QuestSharing/Status.lua` | the status message, tracker / link hooks, `/qs probe` |
| `tests/` | the Lua 5.1 test harness with a WoW API mock, and the two test files |
