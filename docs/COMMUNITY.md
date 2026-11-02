# Afterburner Discord: setup plan

The checklist for setting up the Afterburner Discord server before the v0.6.0 soft launch. Will does each step in the Discord UI, top to bottom. Each step says where to go, what to set and why.

**Starting point (1 November 2026):** server "Afterburner", Will is the only member and moderator. It has the default `# general` text channel, the `General` voice channel and the private `# alerts` channel. `# alerts` receives the Roblox Right to Erasure webhook (COMPLIANCE.md, DEVELOPMENT.md §32.3). **Leave `# alerts` and its webhook alone**: they are compliance plumbing.

**Status (2 November 2026):** §1–§9 done by Will: channels, roles, Community, Safety Setup, AutoMod, Onboarding, Server Guide, rules, invite and the Roblox Social Link. Left: the v0.6.0 patch-notes post and the launch starter post in `# announcements`, once the game goes live (§11).

**Assumptions:** a small launch (£50 of ads), one moderator, and players who skew young. That means a small server, strict safety settings, Discord's built-in tools instead of bots, and nothing that depends on Will watching it live.

---

## 1. Server basics

Server name ▸ **Server Settings → Server Profile** (older clients: **Overview**)

- **Icon:** upload `C:\Users\willw\Documents\PlaneGame\docs\art\marketing\discord_icon.png`.
- **Banner** (needs boost level 2, so skip it for now).

**Server Settings → Overview** (older clients: **Engagement**)

- **Default Notification Settings: Only @mentions.** If this stays on "All Messages", new members get a ping for every message and leave.
- **System Messages Channel:** `# general`. Leave "random welcome message" on (it's friendly). Turn **off** the boost messages and the "sticker reply" prompt.
- **Inactive channel:** none.

## 2. Roles

**Server Settings → Roles.** Order them top to bottom as listed. Will is the owner, so he needs no role.

| Role | Colour | Permissions | Who gets it |
|---|---|---|---|
| **Moderator** | red | Manage Messages, Manage Threads, Timeout Members, Kick Members, View Audit Log, Mention @everyone. **Not** Administrator, Ban Members or Manage Server. Display separately: on | Nobody yet. It's ready for a trusted helper later |
| **Patch Pings** | none | Nothing extra. *Allow anyone to @mention this role*: **off** | Members choose it in Onboarding (§7) |
| **Event Pings** | none | as above | as above |
| **LFG** | none | Nothing extra. *Allow anyone to @mention this role*: **on**, so players can call "@LFG 2v2 anyone?" | as above |

**Edit `@everyone`** (the bottom row, "Default permissions"), turn **off**:

- **Mention @everyone, @here and All Roles**: stops anyone pinging the whole server.
- **Create Expressions / Manage Expressions**: no uploaded emoji or stickers from members.
- **Use External Apps**: stops apps a user brings in from posting in the server.
- **Create Events**: only Will makes events.

Leave on: View Channels, Send Messages, Send Messages in Threads, Create Public Threads, Embed Links, Attach Files, Add Reactions, Use External Emoji, Read Message History, Connect, Speak, Video, Use Voice Activity, Create Invite.

Ping roles mean announcements can ping only the people who asked for them. Will never needs `@everyone`.

## 3. Categories and channels

Rename the default **Text channels** category to **COMMUNITY**, keep `# general` in it, and move the `General` voice channel into **VOICE**. Then build this:

```
INFO                       (everyone reads, only Will posts)
  # rules
  # announcements          Announcement channel
  # patch-notes            Announcement channel
COMMUNITY
  # general                (existing) slowmode 5s
  # lfg                    slowmode 10s
  # squadron-recruiting    Forum channel
  # clips-and-screenshots  slowmode 30s
FEEDBACK
  # bug-reports            Forum channel
  # suggestions            Forum channel
VOICE
  🔊 General               (existing)
  🔊 Wing 1                user limit 4
STAFF                      (private: only Will and Moderator)
  # alerts                 (existing, don't touch)
  # mod-log
```

The Announcement and Forum types are only available after Community is turned on (§4). Make those channels as plain text channels for now: Discord offers to convert `# announcements` to an Announcement channel in the Community setup. Convert `# patch-notes` afterwards in its settings. Create the two Forum channels after §4.

**Category permissions** (category ▸ Edit Category → Permissions). Channels synced to their category pick these up:

- **INFO:** `@everyone`: Send Messages ✗, Create Public/Private Threads ✗, Send Messages in Threads ✗, Add Reactions ✓.
- **STAFF:** turn on **Private Category** and add only `Moderator`. Check `# alerts` still shows only Will after the move. Its webhook isn't affected by moving it.
- The others keep the default permissions.

**Per-channel details:**

- **`# rules`:** the text is in §8. It's also the Community "Rules or Guidelines" channel.
- **`# announcements`:** launches, event weekends and maintenance. Other servers can Follow it.
- **`# patch-notes`:** one post per release, copied from CHANGELOG.md, ending with `@Patch Pings`.
- **`# lfg`:** channel topic: "Looking for a wingman or a 2v2? Post your mode and region. Use @LFG to ping." 
- **`# squadron-recruiting`:** a Forum channel, one post per squadron. Guidelines: "One post per squadron. Title = [TAG] Squadron Name. Say what you play and when. Bump by replying, not by reposting." Tags: `Recruiting`, `Full`, `Casual`, `Competitive`.
- **`# clips-and-screenshots`:** topic: "Your best kills, crashes and screenshots. Keep it about Afterburner."
- **`# bug-reports`:** a Forum channel. Turn on **Require people to select tags when posting**. Tags: `Bug`, `Lag`, `Crash`, `UI`, `Mobile`, `Console`. Staff-only tags (Moderate tags = on): `Known`, `Fixed`, `Can't reproduce`. Post guidelines:
  > Best way to report: **REPORT BUG** in the hangar (under DETAILS) or **Settings → REPORT A BUG**. That sends your device info straight to the dev.
  > Posting here? Include: what happened, what you expected, your device (PC / phone / console), the mode and jet, and a clip or screenshot if you can.
- **`# suggestions`:** a Forum channel with tags `Jets`, `Maps`, `Modes`, `UI`, `Progression`, plus staff-only `Planned`, `Added`, `Not planned`. Default reaction emoji 👍, so posts can be sorted by votes.
- **`🔊 Wing 1`:** an extra voice room for a squad. Keep voice to two rooms: AutoMod doesn't cover voice and nobody can watch it live, so don't add more until there's a second moderator.
- **`# mod-log`:** AutoMod alerts and Discord's own Community Updates land here (§4, §6).

## 4. Turn on Community

**Server Settings → Enable Community → Get Started.** Discord walks through it:

1. **Safety checks:** it requires a verified email (we raise this in §5) and **Scan media content from all members**. Accept both.
2. **Basics:** Rules channel = `# rules`. Community Updates channel = `# mod-log`. This is where Discord sends notices meant for admins, so it must not go to a public channel.
3. **Finishing:** Default notifications = Only @mentions; remove moderation permissions from @everyone = yes. Accept.

Afterwards: convert `# announcements` and `# patch-notes` to **Announcement** channels (channel settings → Overview → Announcement Channel) and create the two Forum channels from §3.

Community turns on Onboarding, the Server Guide, Announcement and Forum channels, and Server Insights. Server Discovery needs 1,000+ members, so ignore it for now.

## 5. Safety Setup

**Server Settings → Safety Setup** (in older clients these are spread over Moderation and Safety Setup):

- **Verification Level: Medium.** Members need a verified email *and* a Discord account more than 5 minutes old. This stops throwaway raid accounts without much friction. Raise it to **High** (10 minutes in the server) if there's ever a raid.
- **Sensitive content filters:** set to filter for **all members**, in direct messages and the server. Turn on **Block sensitive media for everyone** wherever it's offered.
- **DM and spam protection:** turn on everything available here: hide DMs from suspicious users, flag possible spammers, and so on. On a young server, a stranger's DM is where most of the harm happens.
- **Raid protection / Security actions:** turn on raid alerts and send them to `# mod-log`. If a raid happens: **Security actions → Pause invites** and **Pause DMs**.
- **Permissions → Require 2FA for moderator actions: on.** Will's account needs 2FA turned on first (User Settings → My Account). This stops a stolen token from being used to wipe the server.

## 6. AutoMod

**Server Settings → Safety Setup → AutoMod.** For every rule: action **Block message**, **Send alert** to `# mod-log`, and **Exempt** `Moderator` and the STAFF category. Start with the timeouts shown and adjust them once you see real traffic.

| # | Rule | Settings |
|---|---|---|
| 1 | **Block commonly flagged words** (Discord's preset) | Turn on all three lists: Insults & Slurs, Sexual Content, Severe Profanity |
| 2 | **Block mention spam** | 5 unique mentions per message, plus **Timeout 10 min**. Turn on raid restriction ("Restrict mentions when a raid is detected") |
| 3 | **Block suspected spam content** | On |
| 4 | **Custom: scams** | Keywords: `*free robux*`, `*robux generator*`, `*free nitro*`, `*nitro gift*`, `*steamcommunity*gift*`, `*claim your*`, `*robux for*`, `*selling account*`, `*buying account*`, `*account trade*`. Plus **Timeout 1 hour** |
| 5 | **Custom: invite links and other servers** | Keywords: `discord.gg/*`, `*discord.com/invite*`, `*dsc.gg*`, `*.gg/*`. Stops players advertising other servers |
| 6 | **Custom: child safety (alert only)** | Action: **Send alert only**, don't block. Keywords: `*how old are you*`, `*how old r u*`, `*what's your age*`, `*whats ur age*`, `*send pics*`, `*send a pic*`, `*add me on snap*`, `*snapchat*`, `*my snap*`, `*telegram*`, `*whatsapp*`, `*dm me*`, `*where do you live*`, `*irl*`. Will reads these alerts and steps in. Most are innocent, but this is how grooming starts, so these alerts get looked at first |
| 7 | **Block words in member profile names** | Same word lists as 1 and 4, action "Block from interacting" until they change their name |

Will also gets the AutoMod alerts as pings, so turn **mobile notifications for `# mod-log`** on (channel bell ▸ All Messages). Leave every other channel on mentions only.

## 7. Onboarding and Server Guide

**Server Settings → Onboarding.**

**Default Channels:** `# rules`, `# announcements`, `# patch-notes`, `# general`, `# lfg`, `# squadron-recruiting`, `# clips-and-screenshots`, `# bug-reports`, `# suggestions`. Discord needs at least 7 default channels, with at least 5 that members can post in. This list meets both.

**Questions** (the answers hand out roles):

1. *"What pings do you want?"* (multiple choice, not required)
   - **Patch notes**: role Patch Pings
   - **Events (double XP weekends etc.)**: role Event Pings
   - **Looking for group**: role LFG
2. *"How do you play?"* (multiple choice, not required, no roles. It just shows Will the player mix in Insights)
   - PC / Phone or tablet / Console

**Rules screening ("Members must agree to rules"): on.** Members can't post until they've accepted. Paste the same rules as §8.

**Server Guide:**

- **Welcome message:** "Welcome to the Afterburner Discord, pilot. Read the rules, pick your pings, and find a wingman in #lfg." Avatar: Will.
- **New member to-dos:** "Read the rules" → `# rules`. "Say hi" → `# general`. "Find a wingman" → `# lfg`. "Report a bug" → `# bug-reports`.
- **Resource pages:** "How to play" → `# announcements` (pin a short starter post there at launch: controls, modes, how to unlock jets). "Report a bug" → `# bug-reports`.

**Check it:** Server name ▸ **View Server As Role** (or Onboarding → Preview) and go through it as a new member.

## 8. Rules text

Post this in `# rules` (and paste it into Rules screening):

> **Afterburner server rules**
> 1. **Be nice to each other.** Banter about who shot who down is fine. Insults, slurs and picking on people will get you removed, and that includes DMs to people you met here.
> 2. **Keep it clean.** A lot of players are young. Nothing sexual or gory anywhere on the server, and that means your name, avatar and status too.
> 3. **Don't ask people for personal stuff.** Ages, real names, where someone lives, what school they go to, their Snapchat. Don't post yours either. This isn't a dating server.
> 4. **No trading or scams.** Don't sell or trade accounts or Robux here. Posting "free Robux" links is an instant ban. I will never DM you asking for your password.
> 5. **No exploits.** Don't post scripts or explain how to cheat. If you find a bug that lets you cheat, report it in #bug-reports or DM me and I'll fix it.
> 6. **No advertising.** That covers other Discord servers, your own channel and mass pings.
> 7. **Use the right channel and write in English** so I can actually keep an eye on things.
> 8. **You need to be 13 or over** (Discord's rule), and Roblox's Community Standards apply here as well.
>
> Break a rule and you'll get a warning, a timeout or a ban depending on how bad it was. If something's wrong, DM me (Will) or ping a mod instead of arguing about it in #general.

## 9. Invites and the Roblox link

**Make one permanent invite** (right-click `# rules` ▸ Invite People ▸ Edit invite link: **Expire after: Never**, **Max uses: No limit**). **Done (2 November 2026): https://discord.gg/J2NpeQjTv2.** Everything uses this link. Make a second one only if a separate source is worth tracking, such as a YouTube trailer description. **Server Settings → Invites** shows each link's use count. A vanity URL (`discord.gg/afterburner`) needs boost level 3, so skip it.

**Link it from the Roblox experience:** Creator Hub → Creations → Afterburner (the live experience) → **Social Links** → Add → Discord.

- Paste the **`discord.gg/...`** form. Creator Hub has been known to reject the `discord.com/invite/...` form with "The URL must match the social media type".
- Title: "Afterburner Discord".
- **Roblox's current rule:** the owner must be **age-checked 16+** to add social links, and links are **shown only to age-checked 16+ users**. If Will's account isn't age-checked, the link stays hidden until it is. Most young players won't see the link at all. That's intended, and it means the server will skew older than the game.
- **Don't put a Discord link or invite inside the game itself.** Roblox doesn't allow links in experiences unless they're gated by `PolicyService`. The game has that check (`Policy.linkAllowed(rules, "Discord")`, DEVELOPMENT.md §32.5), but nothing in it links out, and that's fine for launch. The Social Links on the game page are enough.

The £50 Roblox ad campaign points at the game, not the Discord. Roblox ads can't link off-platform.

## 10. Linking the game and the server (what to do at launch)

No bots at launch. Discord's AutoMod, Onboarding and Server Guide already do what Carl-bot, MEE6 or Dyno would.

| What | At launch | Later, if it's worth it |
|---|---|---|
| **Patch notes** | At each release (RELEASE.md), copy the new CHANGELOG.md section into `# patch-notes`, add `@Patch Pings`, and press **Publish** so following servers get it | A webhook posted by the release script, so it happens automatically (a game-repo change, on its own branch) |
| **Event weekends** (`event.add`, §31.4) | Make a matching Discord **Event** (server name ▸ Create Event, "Somewhere else" = "In Afterburner on Roblox", the same UTC times) and post it in `# announcements` with `@Event Pings`. Members get reminded when it starts | |
| **In-game announcements** (`announce`, §31.4) | Post maintenance or restart notices in `# announcements` too | |
| **Bug reports** (§32.4) | Read them with `feedback.recent` as now. `# bug-reports` is for players who'd rather post publicly | A private `# bug-feed` with the game posting each report through a webhook. Discord has blocked or rate-limited webhook calls from Roblox servers before, so this may need a proxy; test before relying on it. Game-code change, on a branch |
| **Roblox account linking** | Not needed | **Bloxlink** or **RoVer**, if you want a "Verified" role or a role for VIP Pilot owners. Only worth it once the server is busy |

## 11. Launch-day checklist

- [ ] Check the server as a new member (View Server As Role): onboarding, rules screening and the default channels all work.
- [ ] Post the welcome and starter post in `# announcements` (controls, modes, how to report bugs).
- [ ] Post the v0.6.0 notes in `# patch-notes`.
- [ ] Make the Discord Event for any launch weekend event.
- [x] Add the Social Link in Creator Hub (done 2 November 2026, shows on the game page). Check it appears on the game page while signed in to an age-checked 16+ account.
- [ ] Mobile notifications on for `# mod-log` and `# alerts`.
- [ ] Glance at `# mod-log` once a day for the first two weeks. Change any AutoMod rule that fires on harmless messages.

**When to revisit:** past ~200 members, or when Will can't keep up, add a Moderator (someone known and trusted, ideally an adult). Only then think about more voice rooms, more channels, or a bot.
