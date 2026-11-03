# Pre-launch compliance checklist (CMP-04)

Go through this before the live experience is made public, and again before any big update that adds a
new kind of purchase, a new store of player data, or player-written text. DEVELOPMENT.md §32 has the
background. **Done** items were checked in November 2026; **Will** items need the owner's account.

## 1. Names (DESIGN §6.4)

| Check | Status |
|---|---|
| Every airframe module has `DisplayName`, `NameStatus` and `FallbackName` (the validator requires them) | Done |
| No manufacturer names or logos in game | Done: "Eurofighter Typhoon" became "Typhoon" (Will, November 2026); every other name is a designation plus an official nickname |
| The one programme name (Tempest) is semi-fictional: "Tempest-class concept" | Done |
| Review every `Real` name against the manufacturers' published trademark guidance (§6.4: a design policy, not legal clearance) | **Will** |
| Skins, camos, titles and cosmetics use no real squadron, display-team or brand names | Done (Display Team, Tiger Meet and the rest are generic phrases) |

## 2. Assets

| Check | Status |
|---|---|
| Jet models, textures, camos, wing art, badges and shop cards are our own (Blender and Python tools in `tools/`) | Done |
| Sounds are our own or from Roblox's library with the right to use them (AUD tasks) | Done. Checked 1 November 2026: Betty, RWR, UI, radio and kill-confirm sounds are Will's own uploads (Will confirmed he made them); music and stings are APM / DistroKid tracks from Roblox's licensed library; the engine, wind, gun, explosion, impact and missile-launch sounds are public Creator Store audio from other creators |
| No marketplace asset with unclear rights in the place | Done (1 November 2026): every scripted instance is in our code folders; a sample of 400 mesh and texture ids were all uploaded by Will; sky, grass and road textures are ours; the sun and moon images are public Creator Store images |

## 3. Experience questionnaire and settings (Creator Hub, live experience)

| Check | Status |
|---|---|
| Maturity and compliance questionnaire answered honestly: stylised aircraft combat, no blood or gore, no real-world violence, cosmetic purchases, no paid random items | Done (Will, 1 November 2026) |
| Genre and description say what the game is; no promises it doesn't keep | Done (1 November 2026): Shooter › Deathmatch Shooter (changeable every 3 months); description lists the modes, training, parties, squadrons, leaderboards and the season pass |
| Private servers price set, if wanted (DESIGN §8.2) | **Will** (optional) |
| Reach under-16s: the page shows Ages 16+ until the experience has **250 highly engaged players**. Only after that can Will pay the optional, refundable 1,000 R$ fee to speed up the review; the fee doesn't replace the 250 (Will, 2 November 2026) | **Will**, after launch |

## 4. Purchases (DESIGN §8, DEVELOPMENT.md §27)

| Check | Status |
|---|---|
| Never pay-to-win: `PayToWin.spec` fails if a product or cosmetic could give power; premium jets copy a free jet's stats | Done |
| No paid random items. The free spin is earned only, never sold; its odds are behind the (i) button | Done |
| Tier II and III Unlocks (dropped from the game) are off sale in both experiences (1 November 2026) | Done |
| Every developer product has a name, a price matching `Config/Products` and a description saying exactly what you get (all 12 on the live experience read back from Roblox) | Done |
| Every game pass description says exactly what you get | Done (2026-11-01): VIP Pilot now reads "+25% Credits from every match, a VIP tag by your name, an extra daily challenge reroll, and the VIP Gold camo and VIP Gold contrails." in both experiences (saved and read back from Creator Hub), matching `Config/Passes`. Extra Lineup Slot and Custom Callsign are fine. |
| Real prices before the purchase window; no fake timers (the weekly bundle and events show real dates) | Done |
| Policy checks: anything regulated asks `Shared/Policy` first (CMP-02) | Done (nothing regulated yet) |

## 5. Text and safety (§32.1, §32.2)

| Check | Status |
|---|---|
| Callsigns, squadron names and tags go through `TextService` filtering for every viewer (CMP-01) | Done |
| Chat is `TextChatService` (Roblox filters it) | Done |
| Report a cheater in game (CMP-03), Roblox's own report flow for everything else | Done |
| Admin announcements and event names are written by admins only | Done |

## 6. Privacy and Right to Erasure (§32.3)

| Check | Status |
|---|---|
| Only Roblox UserIds are stored, never names or other personal data | Done |
| `erasure.run { userId }` removes everything stored under a UserId: the save (every store version), reports against them and their id in others' reports, their bug reports and daily counts, every leaderboard entry, their squadron membership | Done |
| Right to Erasure webhook set up in Creator Hub, on the account or group that owns the live experience (steps in §32.3) | Done (1 November 2026): account webhook "Afterburner erasure requests" posts to the private #alerts Discord channel; test notification received |
| Each request handled within 30 days: run `erasure.run` for each UserId (live server, as an admin), note the date | **Will**, as requests arrive |

## 7. Badges and achievements

| Check | Status |
|---|---|
| Every achievement has a badge on the live experience (`Config/Badges`) | In progress (5 free a day) |

## 8. Rewards for joining the group, playing with friends, likes and favourites

Checked 3 November 2026 against Roblox's own pages: the [Community Standards](https://about.roblox.com/community-standards),
the Creator Hub docs ([Friend Invite Reward System](https://create.roblox.com/docs/production/promotion/referral-system),
[Discovery](https://create.roblox.com/docs/discovery), [GroupService](https://create.roblox.com/docs/reference/engine/classes/GroupService))
and DevForum posts. The Help Center (Terms of Use, Friend Rewards Program Terms) couldn't be fetched and needs
reading by hand.

- **Group join:** no official rule allows or forbids it by name. Roblox gives developers the tools for it
  (`GroupService:PromptJoinAsync`, `Player:IsInGroupAsync`), it's widely done, and developers on the DevForum agree
  it's fine. The general rules still apply. Nothing misleading "to drive discoverability, monetization, or
  engagement" (Community Standards), the bonus must be paid as described, and joining must be optional.
  Groups were renamed Communities in November 2024, but the API still says Group.
- **Likes, upvotes, favourites:** the old Community Rules banned rewards "in exchange for a thumb up on your game".
  Today's Community Standards don't name it, but rewarding ratings counts as rating manipulation, and an enforcement
  category for "artificially inflating experience statistics" has been reported. **We don't reward likes or
  favourites.** Asking players to like the game without a reward is fine.
- **Friends:** Roblox officially supports rewarding friend invites (the Friend Invite Reward System,
  `GetJoinData().ReferredByPlayerId`). No rule stops a bonus for playing with friends. Our friends bonus pays for
  flying in the same match as a friend or party mate. It doesn't pay for sending invites.
- **Prompts:** no spam and no false "free" claims. The hangar chip is passive, and no join prompt pops up by itself.

| Check | Status |
|---|---|
| Group bonus (+10% Credits and XP) is optional, honest and paid as described (`Config/Social`, DEVELOPMENT.md §25.8) | Done; off until the group id is set |
| No reward for likes, upvotes or favourites (`Social.spec` checks the config) | Done |
| Friends bonus pays for flying together, not for sending invites | Done |
| Store description: only claim the group bonus once `GROUP_ID` is set and published | **Will** |
| Read the Help Center's Terms of Use and Friend Rewards Program Terms (couldn't be fetched) | **Will** |

## When a Right to Erasure request arrives

Roblox posts it to the private #alerts Discord channel ("Roblox Webhooks"). A real one names the UserId(s) and the
experience (universe) id(s); the test one says "Sample Notification" and needs nothing.

1. Check it's for the live Afterburner (universe 10773807904). Requests for other experiences need nothing here.
2. Join the live game (or any live server), press **F9** to open the Developer Console, pick **Server**, and type
   in the command line at the bottom, with the UserId from the request:
   `print(table.concat(require(game.ServerScriptService.Server.Lib.Erasure).run(123456789), "
"))`
3. It prints one line per store. Every line should say it removed something or found nothing; a line saying
   FAILED means run it again.
4. Note the UserId and the date in a reply under the alert in Discord. Roblox expects it done within 30 days.

There is nothing to reply to Roblox. The player never needs to have played: running it for an unknown UserId just
finds nothing.

