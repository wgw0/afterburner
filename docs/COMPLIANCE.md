# Pre-launch compliance checklist (CMP-04)

Go through this before the live experience is made public, and again before any big update that adds a
new kind of purchase, a new store of player data, or player-written text. DEVELOPMENT.md §32 has the
background. **Done** items were checked in November 2026; **Will** items need the owner's account.

## 1. Names (DESIGN §6.4)

| Check | Status |
|---|---|
| Every airframe module has `DisplayName`, `NameStatus` and `FallbackName` (the validator requires them) | Done |
| No manufacturer names or logos in game | **Will: decide on "Eurofighter Typhoon"**. "Eurofighter" is the consortium that builds it, and §6.4 says manufacturer names never appear. Its fallback is `Typhoon "EF-2000"`; plain "Typhoon" would also do. Every other name is a designation plus an official nickname. |
| The one programme name (Tempest) is semi-fictional: "Tempest-class concept" | Done |
| Review every `Real` name against the manufacturers' published trademark guidance (§6.4: a design policy, not legal clearance) | **Will** |
| Skins, camos, titles and cosmetics use no real squadron, display-team or brand names | Done (Display Team, Tiger Meet and the rest are generic phrases) |

## 2. Assets

| Check | Status |
|---|---|
| Jet models, textures, camos, wing art, badges and shop cards are our own (Blender and Python tools in `tools/`) | Done |
| Sounds are our own or from Roblox's library with the right to use them (AUD tasks) | Done |
| No marketplace asset with unclear rights in the place | **Will: one last look** in Studio (Toolbox inserts show in the Explorer) |

## 3. Experience questionnaire and settings (Creator Hub, live experience)

| Check | Status |
|---|---|
| Maturity and compliance questionnaire answered honestly: stylised aircraft combat, no blood or gore, no real-world violence, cosmetic purchases, no paid random items | **Will** |
| Genre and description say what the game is; no promises it doesn't keep | **Will** |
| Private servers price set, if wanted (DESIGN §8.2) | **Will** (optional) |

## 4. Purchases (DESIGN §8, DEVELOPMENT.md §27)

| Check | Status |
|---|---|
| Never pay-to-win: `PayToWin.spec` fails if a product or cosmetic could give power; premium jets copy a free jet's stats | Done |
| No paid random items. The free spin is earned only, never sold; its odds are behind the (i) button | Done |
| Every developer product has a name, a price matching `Config/Products` and a description saying exactly what you get (all 12 on the live experience read back from Roblox) | Done |
| Every game pass description says exactly what you get | **Will: VIP Pilot** (both experiences, Creator Hub → Passes → VIP Pilot → Basic Settings) leaves out the camo and contrails. Suggested: "+25% Credits from every match, a VIP tag by your name, an extra daily challenge reroll, and the VIP Gold camo and VIP Gold contrails." Extra Lineup Slot and Custom Callsign are fine. |
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
| Right to Erasure webhook set up in Creator Hub, on the account or group that owns the live experience (steps in §32.3) | **Will** |
| Each request handled within 30 days: run `erasure.run` for each UserId (live server, as an admin), note the date | **Will**, as requests arrive |

## 7. Badges and achievements

| Check | Status |
|---|---|
| Every achievement has a badge on the live experience (`Config/Badges`) | In progress (5 free a day) |
