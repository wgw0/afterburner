# Releasing and rolling back

How to put a new version of Afterburner live, and how to take it back if it goes wrong
(DEVELOPMENT.md §35, REL-03 and REL-04). The version number lives in `src/shared/Version.luau`, what
changed lives in [CHANGELOG.md](../CHANGELOG.md), and every release gets a Git tag (`v0.6.0`).

Players can see the version and build at the bottom of **Settings** ("Afterburner v0.6.0 · build 214").
"build" is Roblox's place version for the server they're on. The admin command `server.info` gives the
same for a server, with its save version, role and uptime.

## Before release day

1. **Everything for the release is merged and ticked** in [PROGRESS.md](PROGRESS.md), each tested.
2. **Pick the version.** Bump `Version.NUMBER` in `src/shared/Version.luau`: the middle number for a
   normal release (0.6.0 → 0.7.0), the last number for a fix (0.6.0 → 0.6.1). Until launch the first
   number stays 0.
3. **Write the changelog section:** `## [0.7.0] - Unreleased` at the top of CHANGELOG.md, with what changed
   in plain words, grouped under Added / Changed / Fixed. CI fails if the version has no section.
4. **Check save changes.** If `PlayerData.VERSION` went up, the release has a migration. It must be safe to
   roll back from (see [Saves](#saves-and-rollbacks)): the previous release must still be able to play on a
   migrated save. Run the migration tests against a fixture of a real save from the test experience.
5. **Merge to master** (CI green).

## Release day

1. **Playtest the release build in the test experience.** Publish from Studio to *Afterburner (TEST)*,
   join from the Roblox app (not Studio), and play: the hangar, a match, training, a purchase, the menus.
   Check Settings shows the new version, "· Test" and the new build.
2. **Note the current production build** before publishing: in the Creator Dashboard, the production
   experience → the start place → Version History; write down the newest version number. That is the build
   to roll back to.
3. **Publish to production** from Studio (File → Publish to Roblox As… → the production experience). If the
   experience has more than one place (a separate Battle place in `Config/Places`), publish every place.
   Production is worked out from the experience (`Config/Environment`): there is no switch to flip.
4. **Restart the servers** so nobody stays on the old version: the experience's ⋯ menu in the Creator
   Dashboard → **Restart servers** (Roblox has also called it "Restart Servers for Updates" and "Migrate to
   Latest Update"; it moves players to the new version). Old servers otherwise run until they empty.
5. **Check it live:** join production, open Settings: the new version, no "· Test", the new build.
6. **Tag it:** on an up-to-date master, `bash scripts/release.sh` (try `--dry-run` first). It dates the
   changelog section, commits "Release v0.7.0", and makes the tag. Then push both:
   `git push origin master v0.7.0`.
7. **Watch the first hour:** the Creator Dashboard's error report and analytics (sessions, the onboarding
   funnel, `DataLoadFailed`), and the server logs if anything looks off. Decide within the hour whether to
   keep it or roll back.
8. **First launch only:** the store thumbnail and badges (DEVELOPMENT.md §35.3 steps 5 and 6).

## Rolling back

Roll back when the new version breaks something players need (they can't join, fly, finish a match or keep
their progress) and the fix isn't quick. Two quicker options first:

- **The problem is a number** (rewards too high, a jet's battle rating, a bad event message): fix it with
  live config (`config.set` / `config.clear`), which reaches every server in seconds. No rollback.
- **A small, certain fix:** release a patch version (0.7.1) through the steps above.

Otherwise:

1. **Restore the previous build:** Creator Dashboard → the production experience → the place → Version
   History → the build noted on release day → **Restore**. Do it for every place in the experience, all to
   the builds of the same release. (Restoring adds a new version on top; nothing is deleted, so the bad
   build can be restored again later.)
2. **Restart the servers** (⋯ menu → Restart servers) so everyone moves off the bad build.
3. **Check it:** join, open Settings: the previous version, a new build number. Play a match.
4. **Fix forward in Git:** revert the bad change on master (`git revert`), bump to a patch version, and
   release that the normal way. Don't move or delete the bad version's tag: it records what went out.
5. **Write it down** in the release notes of the fix: what broke, when it was rolled back.

### Saves and rollbacks

Rolling back the place doesn't roll back saves: players keep everything they earned on the bad version, and
the older code then loads saves the newer code wrote. That's safe because:

- An older server never downgrades a save. A save from a newer release keeps its version and every field
  the older code doesn't know (`PlayerData.migrate`, tested in `PlayerData.spec`), so the newer release
  finds them again. The server logs `DataNewerThanCode` when this happens.
- **The rule for migrations:** a release may *add* save fields, but must not rename, remove or change the
  meaning of an existing field in the same release that starts writing the new shape. Do it in two releases:
  the first writes both the old and new field, the next (once rolling back past the first is no longer
  possible) stops using the old one.

The same goes for anything shared between servers on different versions while servers restart: the
matchmaking queue and match records (MemoryStore), live config, and reports. Only add fields.

## Rollback drill (REL-04)

Practise once on the **test experience** so the steps are familiar before launch. About 15 minutes.

1. Publish the current master to *Afterburner (TEST)*. Join it from the app; in Settings note the version
   and build (say v0.6.0 · Test · build *N*).
2. In Studio, change `Version.NUMBER` to `"0.6.99"` (don't commit it) and publish again: build *N+1*.
3. Join again (a new server): Settings shows v0.6.99, build *N+1*. Leave this server running in one client.
4. Roll back: Creator Dashboard → *Afterburner (TEST)* → the place → Version History → Restore build *N*.
   Note the time.
5. Restart the servers. The client from step 3 should be moved to a new server.
6. Join: Settings shows v0.6.0, build *N+2* (the restore). Play briefly; your save loads with everything
   from step 3. Note how long steps 4–6 took.
7. In Studio, set `Version.NUMBER` back to `"0.6.0"`.
8. Record the result in [PROGRESS.md](PROGRESS.md) under REL-04: the date, the builds, and how long the
   rollback took.
