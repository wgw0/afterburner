# Multiplayer and mobile test guide

Two exit checks carried over from Phases 4 and 5 need real players: an 8-player match, and saving when one account
is on two servers. Mobile (MAP-04, PRF-03, UI-09) needs a real phone. This page says how to run each, from the
cheapest check to the real thing. Write the results in a playtest log (`docs/playtests/TEMPLATE.md`).

## 1. Several players on one PC (Studio)

Quick, private, and enough to catch replication bugs. Every client loads the whole map, so keep it to 2–4.

1. Studio: **Test** tab → **Clients and Servers** → set **Local Server**, choose the number of players (start with 2),
   then **Start**.
2. Studio opens one server window and a window per player, signed in as test players (`Player1`, `Player2`…).
   Test players get no saved data and no owner access, so they start with the starter jets.
3. Fly at each other. Check the [network checklist](NETWORK.md), plus:
   - each player sees the other's jet, skin, control surfaces moving, contrails and missiles;
   - a kill on one window shows in both kill feeds and scoreboards;
   - radar locks warn the target (RWR, LOCKED, Betty) and missiles guide on the right jet.
4. **Cleanup** on the Test tab closes every window.

Simulated lag is in NETWORK.md. Studio can't prove the lag compensation amount; that needs a live server (below).

## 2. A real match with friends (the test experience)

This is the Phase 4 exit test: 8 players and bots, a full match, then a chat about it.

1. **Publish** the current place to the test experience, **Afterburner (TEST)** (place 72582604278324): File →
   **Publish to Roblox**. The test experience always runs as `Test` (`Config/Environment`), so it uses the test save
   store and the debug tools; nobody's progress mixes with the future live game.
2. **Let your friends in.** The experience is private. In Studio, **Home → Game Settings → Permissions**, set
   **Playability** to **Friends** if it's offered (only your Roblox friends can join), or Public for the session
   and back to Private afterwards. Friends join from your profile, the experience page or a link you send.
3. **Play a full match** (10 minutes, AI fill tops the server up to 8). Watch for: spawns, kills and assists, the
   scoreboard and results screen, rewards arriving, rejoining mid-match, and the server's frame rate (Developer
   Console, below).
4. **Developer Console** (F9 on PC, or type `/console` in chat on any device): the **Server** tab shows server
   errors and the server step meter (`ServerStepMs`, `ServerHz` attributes); the **Memory** tab shows client
   memory.
5. Set Playability back to **Private** when you're done.

### Matchmaking (MMK-03/04)

Publish the place to the test experience first: matchmaking needs real servers, and Studio only switches roles in place.

1. Join: you land in a **lobby** (PLAY, a mode picker over it, TRAINING top right).
2. Press PLAY alone: after about 30 s you should be teleported to a match with 5 AI (a loading screen shows during the trip).
3. With friends: everyone picks the same mode (or Any) and presses PLAY within a few seconds. You should all land in the **same** match, and the AI fill the rest of the 6 seats.
4. Finish or LEAVE MATCH: you go back to a lobby (maybe a different lobby server from the one you started on; that's expected).
5. TRAINING from the lobby, then MULTIPLAYER: private server and back.
6. Note how long each queue took and anything odd, in the results log below.

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
controls (virtual stick, throttle, FIRE / MSL / LOCK / FLR / CHF / WPN / CAM) fit the screen. It does not show
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
