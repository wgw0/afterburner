# Multiplayer and mobile test guide

Two exit checks carried over from Phases 4 and 5 need real players: a full match with real players, and saving when
one account is on two servers. Matchmaking (MMK-02/03/04/06) and parties (MMK-05) are built and checked in Studio
but wait for this test before they're ticked, and squadrons and leaderboards need more than one server to prove.
Mobile (MAP-04, PRF-03, UI-09) needs a real phone. This page says how to run each, from the cheapest check to the
real thing. Write the results in a playtest log (`docs/playtests/TEMPLATE.md`).

## 1. Several players on one PC (Studio)

Quick, private, and enough to catch replication bugs. Every client loads the whole map, so keep it to 2–4.

1. Studio: **Test** tab → **Clients and Servers** → set **Local Server**, choose the number of players (start with 2),
   then **Start**.
2. Studio opens one server window and a window per player, signed in as test players (`Player1`, `Player2`…).
   Test players get no saved data and no owner access, so they start with the starter jets.
3. The server starts as a lobby (no flying). Everyone picks the same mode and presses PLAY. Studio can't reserve
   servers or teleport, so when the match forms this server becomes the match in place (after about 4 s, not 30).
4. Fly at each other. Check the [network checklist](NETWORK.md), plus:
   - each player sees the other's jet, skin or camo, control surfaces moving, contrails and missiles;
   - a kill on one window shows in both kill feeds and scoreboards, outlined red only for the pilots in it;
   - radar locks warn the target (RWR, LOCKED, Betty) and missiles guide on the right jet;
   - in Team Deathmatch or Zones, two players on one team can't hurt or lock each other, and show blue to each other.
5. **Cleanup** on the Test tab closes every window.

Simulated lag is in NETWORK.md. Studio can't prove the lag compensation amount; that needs a live server (below).

## 2. Real matches with friends (the test experience)

This is the Phase 4 exit test: real players and bots, a full match, then a chat about it. A match seats 6 pilots
(`Queue.MATCH_SIZE`), with AI in the empty seats.

1. **Publish** the current place to the test experience, **Afterburner (TEST)** (place 72582604278324): File →
   **Publish to Roblox**. The test experience always runs as `Test` (`Config/Environment`), so it uses the test save
   store and the debug tools; nobody's progress mixes with the live game.
2. **Let your friends in.** The experience is private. In Studio, **Home → Game Settings → Permissions**, set
   **Playability** to **Friends** if it's offered (only your Roblox friends can join), or Public for the session
   and back to Private afterwards. Friends join from your profile, the experience page or a link you send.
3. **Play a full match** through matchmaking (below). Watch for: spawns, kills and assists, the scoreboard and
   results screen, rewards arriving, rejoining mid-match, and the server's frame rate (Developer Console, below).
4. **Developer Console** (F9 on PC, or type `/console` in chat on any device): the **Server** tab shows server
   errors and the server step meter (`ServerStepMs`, `ServerHz` attributes); the **Memory** tab shows client
   memory.
5. Set Playability back to **Private** when you're done.

### Matchmaking (MMK-02/03/04/06)

Matchmaking needs real servers: in Studio the queue is local and roles switch in place.

1. Join: you land in a **lobby** (PLAY, the mode picker over it, TRAINING to the left of PLAY).
2. Press PLAY alone: after about 30 s you should be teleported to a match with 5 AI (a loading screen shows during
   the trip). The match launches you in the jet you pressed PLAY with.
3. With friends: everyone picks the same mode (or ANY MODE) and presses PLAY within a few seconds. You should all land
   in the **same** match, and the AI fill the rest of the 6 seats. The rules loosen the longer a pilot waits (BR
   spread up to 3.0, any mode after two minutes), so far-apart jets should still meet in the end.
4. Try each mode in the picker: DOGFIGHT, TEAMS, ZONES and GUNS ONLY.
5. Finish or LEAVE MATCH (left of PLAY on a match server): you go back to a lobby (maybe a different lobby server
   from the one you started on; that's expected).
6. TRAINING from the lobby, then MULTIPLAYER: private server and back.
7. Admin `matchmaking.stats` on a lobby: the waits and matches formed should match what you saw.
8. Note how long each queue took and anything odd, in the results log below.

### Parties (MMK-05)

Two or three players, all in one lobby to start with.

1. One player opens the party panel (right of the Hangar, above MATCHMAKING) and presses INVITE for someone on the
   same server. The invite pops up at the top of their screen: ACCEPT. Both see the party, the leader starred.
2. INVITE FRIENDS opens Roblox's invite window. A friend who joins from it on a different lobby server should be
   moved to yours and join the party. A fourth player can't join (3 at most).
3. The leader presses PLAY: the whole party queues as one, at the highest BR in it, and lands in the same match.
   In TEAMS and ZONES the party is on the same team.
4. After the results, the party is sent home together and is still a party in the new lobby.
5. REMOVE (leader) and LEAVE work; changing the party while queued cancels the search.

### Squadrons (LIV-06)

Needs two accounts; the second should join from a different server where it can, since records are shared through
a DataStore and cached for 30 s per server.

1. Career → SQUADRON: create one (name and tag; 10,000 Credits). A name or tag the filter changes is refused.
2. The second player joins by tag, or by an invite. Both show the tag before their names (jet label, scoreboard,
   kill feed).
3. Promote to officer, remove a member, leave: each shows on both screens (allow up to 30 s across servers).
4. Play a scored match together: player kills and the win add to the weekly score. At 100 points each member can
   claim the 5,000 Credits once that week.
5. The squadron appears on the Squadrons this week board.

### Leaderboards (LIV-05)

1. Note your scores on Career → LEADERBOARDS (Kills this week, Wins this week, Season XP, All-time kills).
2. Play a scored match with a player kill and a win. Kills of AI pilots don't count.
3. From another server (a friend's lobby, or after rejoining), check the boards show the new scores. Boards are
   cached for 60 s per server, so allow a minute.
4. Admin `leaderboard.remove` takes a player off every current board.

### The two-servers save check (Phase 5)

ProfileStore locks a pilot's data to one server. To check a hand-over loses nothing:

1. Play on the PC and earn something you can see (a match's Credits and RP).
2. Straight after the results screen, join the experience on your phone with the same account. Roblox closes the
   PC session.
3. Pass: the phone shows the Credits and RP from the PC match, nothing doubled or lost, and no data errors in the
   Developer Console.

## 3. Mobile

### Studio's device emulator (layout only)

Test tab → **Device**, pick a phone (an iPhone and a small Android), and play. It shows how the HUD, menus and touch
controls (virtual stick, throttle, FIRE / MSL / LOCK / FLR / CHF / WPN / CAM / AUTO) fit the screen. It does not show
mobile performance or memory: that needs a real phone.

### A real phone

1. Install the Roblox app and sign in as the owner account (it can join the private test experience).
2. Open **Afterburner (TEST)** from your creations, or from a link.
3. Note, ideally on an older phone as well as a new one:
   - **Join time**: from tapping Play to the PLAY button working (`MapReady`).
   - **Frame rate**: in-game Roblox menu → Settings → **Performance Stats** on; note it in the menu, over the
     towns, in a dogfight with missiles and flares, and after a death and respawn.
   - **Memory**: `/console` → Memory; note the total and the biggest categories.
   - **Touch controls**: can you fly, aim the gun, lock and fire, flare, and get through every menu with your thumbs.
   - **Heat and battery** after 15 minutes.
   - **Crashes**: whether the app closed and when.
4. Send the numbers: they decide what MAP-04 (streaming radius, fog) and PRF-03 (quality levels, draw distance,
   texture sizes) need to change.

## Results log

| Date | Test | Devices / players | Result | Follow-ups |
|---|---|---|---|---|
| | | | | |
