# Reading Afterburner's analytics

A guide to the Roblox Creator Dashboard for Afterburner: where each chart is, and what it tells you. The events themselves are described in DEVELOPMENT.md §30.3.

Open it at **Creator Hub → Creations → Afterburner → Analytics** (the left-hand menu). Roblox renames these pages now and then, so look for the closest name.

## Before you start

- **Events only come from the published game.** Roblox records nothing from Studio or from the client. We read analytics on the **live (prod) experience, Afterburner** only. The TEST experience has a dashboard of its own, so test play never mixes with live numbers; ignore it. Custom events also carry `env=Test` or `env=Prod` in Custom Field 3.
- **Charts lag by about a day.** Each analytics page has a **View Events** button that lists the latest events within minutes. Use it to check that something is arriving.
- **Small games see less.** Funnels, Economy and Custom events appear once events arrive. The full set of KPIs needs more than 10 daily active users and 10 hours of play a day for 7 days in a row.

## Retention: do players come back?

**Retention** (and **Engagement**) pages are built in. You don't have to set anything up.

- **D1 / D7 retention:** the share of new players who return the next day, or a week later. This is the headline number. D1 below about 20% usually means the first session isn't landing, so look at the onboarding funnel next.
- **Session length and sessions per user:** a short first session alongside a normal later session usually means the start is the problem.
- In **Custom events**, `DailyReward` (value: streak day) and `Spin` show whether the login streak and the free spin keep people coming back. Look at the count of unique users per day.

## Onboarding: where do new players drop off?

Go to **Funnels**, then the **Onboarding** tab. This is a one-time funnel: each player counts once, grouped by the day they first joined.

| Step | Name | Reached when |
|---|---|---|
| 1 | Joined | the save loads, on the player's first ever visit |
| 2 | Onboarded | the player leaves the welcome flow by any route: chooses multiplayer, stays in training (KEEP TRAINING), or closes the welcome window |
| 3 | FirstMatch | the player finishes their first scored multiplayer match |
| 4 | FirstKill | the player gets their first kill in a scored match |
| 5 | FirstResearch | the player researches their first jet |

- **A big drop at 1 → 2** means new players leave during the welcome window or the lessons. Check the training funnel below.
- **A big drop at 2 → 3** means players chose multiplayer but didn't finish a match. Causes include queue waits (`QueueLeft` value = seconds waited before giving up), failed teleports (`TeleportFailed`), or quitting mid-match.
- **A big drop at 3 → 4** means the first match is too hard. Compare `MatchQuality` for matches with new players.
- **A big drop at 4 → 5** means players don't find, or can't afford, research.
- **How players left the welcome flow:** in Custom events, look at `Onboarded`. Break it down by Custom Field 1 (`how=Multiplayer`, `how=Training` or `how=Skipped`). The value is how many lessons they had finished. `FirstSessionTraining` counts new players who clicked GO TO TRAINING.

Roblox counts a logged step as completing every step before it. To keep the funnel honest, the game logs a step only after every earlier step has happened. A kill in a player's first match therefore shows up when that match ends. A player who researches a jet before getting a kill shows at step 5 only once they get their first kill. Lessons are optional, so they have a funnel of their own (below).

*Players from before November 2026 went through an older six-step version (Joined, Lesson1, Lesson3, FirstMatch, FirstKill, FirstResearch). Read the funnel from the release date of this change onwards. The dashboard warns about step names changing in older date ranges.*

## Training: how far do players get through the lessons?

Go to **Funnels**, then the **Training** tab. Each player counts once.

| Step | Name |
|---|---|
| 1 | Arrived (first time on a training server) |
| 2 | Flight (lesson 1) |
| 3 | Energy (lesson 2) |
| 4 | Guns (lesson 3: lessons 1–3 pay the 2,000 Credits) |
| 5 | Missiles (lesson 4) |
| 6 | Defend (lesson 5) |
| 7 | Fight (lesson 6) |

A steep drop at one lesson means that lesson is too long, unclear or too hard. Players can pick lessons out of order, and a later lesson counts the earlier ones as done, so treat this funnel as "got at least this far". `LessonCompleted` in Custom events (broken down by `lesson`) gives the true count for each lesson.

## Match quality: are matches fair and quick to find?

All of these are in **Custom events**. Pick the event, choose the aggregation (Average, Sum, Count, and so on), then break it down by a custom field.

| Event | Look at | What it tells you |
|---|---|---|
| `MatchQuality` | Average value, by Field 1 (`mode`) | How close matches finish. 100 is level, 50 is 1–0, and 9 is 10–0. An average below about 40 means too many walkovers. Field 2 (`humans`) separates matches with few humans in them. |
| `QueueMatched` | Average value, by `mode` | Seconds waited before getting a match. |
| `QueueLeft` | Count, and Average value | How many players gave up waiting, and how long they waited first. |
| `MatchFormed` | Average value; by Field 2 (`spread`) | The longest wait in each match formed, and how wide the BR spread had to stretch. |
| `MatchArrived` | Average value | The percentage of pilots sent to a match who made it there. Under 100 means failed teleports. |
| `MatchEnded` | Average value, by `mode` | Match length in seconds. |
| `VsAIRewards` | Count of unique users, Sum | How many players play Vs AI, and the pilot XP it pays. |

**Balance**, from scored matches only (this is the weekly report, ANL-05):

- **Win rate per jet:** `AirframeResult`, average value, by Field 1 (`airframe`).
- **K/D per jet:** `Kill` count ÷ `ShotDown` count, each by `airframe`.
- **Missile hit rate:** `MissileResult`, average value, by Field 2 (`weapon`).
- **Popularity:** `Spawn`, count by `airframe`.

Only human pilots count: `Kill` and the missile events are human vs human, and `ShotDown` is a human downed by a human or by nothing (a crash). AI seats in matches never move these numbers. Missiles fired with no target (an IR shot without a lock) still count.

## Economy: where do Credits and Wings come from and go?

Go to the **Economy** page. Pick the currency at the top: **Credits** (earned) or **Wings** (premium, for cosmetics).

- **Sources vs sinks over time:** the totals should roughly balance. Sources running well ahead of sinks means players pile up Credits with nothing to spend them on, and prices or rewards need tuning.
- **Average wallet balance:** a balance that keeps climbing points the same way. Compare payers with non-payers.
- **Top sources and sinks:** these come from the transaction type plus the item SKU.

| Sources | Type | SKU |
|---|---|---|
| Match Credits | `Gameplay` | `Match` |
| Pilot levels and their milestones | `LevelUp` | `Level` |
| Mastery stars | `Mastery` | the jet |
| Daily and weekly challenges | `Challenge` | `Challenge` |
| Login streak | `TimedReward` | `Day1` to `Day7` |
| Free spin (Credits or Wings) | `Spin` | the prize rarity |
| Lessons 1–3 reward | `Onboarding` | `TrainingComplete` |
| Wings bought with Robux | `IAP` | the product, e.g. `Wings550` |

| Sinks | Type | SKU |
|---|---|---|
| Buying a jet | `BuyAircraft` | the jet |
| Modules | `BuyModule` | the jet |
| Skins (Credits or Wings) | `BuySkin` | the jet |
| Cosmetics (Wings) | `BuyCosmetic` | the cosmetic |

Robux sales themselves are on the **Monetization** pages, not Economy. Credits and Wings given with admin commands aren't logged as economy events, so they never skew the totals.

## What you have to do in Creator Hub

Nothing has to be configured by hand. Funnels, the Economy page and Custom events build themselves from the events once they arrive. The one-off checks:

1. **Analytics access.** Your account needs a verified email and 2-step verification. If the Analytics pages ask you to accept their terms, do so once on the experience's overview page.
2. **Check the events arrive on the live game.** Once this build is published to Afterburner (prod), play it from the Roblox app, not Studio:
   - finish a lesson;
   - go to a lobby;
   - play a match to the end;
   - research or buy something.

   Then, in Creator Hub → Afterburner → Analytics:
   - **Funnels → View Events:** look for an `Onboarding` step and a `Training` step.
   - **Economy → View Events:** look for a `Gameplay` source and your purchase as a sink.
   - **Custom events → View Events:** look for `MatchEnded`, `MatchQuality`, `Onboarded` and `LessonCompleted`.
3. **The next day,** open Funnels and check that the **Onboarding** and **Training** tabs are there. Then open Economy and check that **Credits** and **Wings** are both listed.
4. **The weekly balance report (ANL-05).** In the live game's Custom events, build the four balance charts listed above (last 7 days, by airframe or weapon). Save or bookmark each view, if the page offers it, so the report is a few clicks each week.
