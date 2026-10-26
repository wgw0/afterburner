# Network test checklist (TST-02)

Run this whenever guns, missiles, damage or anything else networked changes. Note the results in that phase's playtest log.

## Setting up simulated lag in Studio

The incoming lag (what the client sees from the server) can be set from the **client** command bar during a play session:

```lua
settings().Network.IncomingReplicationLag = 0.15 -- seconds; set back to 0 when done
```

Or use **File → Studio Settings → Network → Incoming Replication Lag**.

> **Limitation:** Studio's simulated lag does **not** show up in `Player:GetNetworkPing()` (it reads ~1 ms), so the server's lag compensation can't see it. Studio tests prove the game *stays correct* under lag (hits still register, nothing desyncs or errors). They can't prove the compensation *amount* is right. Check that on a live test server with real latency (Phase 5, REL-02).

## Checklist

| # | Test | How | Pass when |
|---|---|---|---|
| 1 | Guns register under lag | 150 ms lag; spawn a drone (P panel → "Spawn target drone (ahead)"), fire | Hits and a kill register; hit markers and tracers line up with the target |
| 2 | Tracers match | Two clients (Test → Server & Clients); one fires | The watching client sees the stream come from the shooter's nose and go the same way |
| 3 | No double kills | Kill a jet with two players firing | Exactly one kill feed line; the assist goes to the other shooter if they did ≥25% |
| 4 | Crash detection | Fly into the ground | Explosion, death cam, "You crashed"; server log has no errors |
| 5 | Fake crash report ignored | Client command bar while flying high: `game.ReplicatedStorage.Remotes.ReportCrash:FireServer()` | Jet keeps flying |
| 6 | Leaving mid-fight | Damage another player's jet, then they leave | Kill feed credits you |
| 7 | Remote spam | Fire `GunFire` 50 times in one frame from the client | Rate-limited (one summary line in the server log), no errors |

## Results log

| Date | Build | Lag | Results |
|---|---|---|---|
| 2026-10-26 | phase-2/guns-damage | 0 ms | #1 drone shot down in 1.07 s (23 hits); #4 server crash detection 0.45 s; #5 fake report ignored |
| 2026-10-26 | phase-2/guns-damage | 150 ms | #1 drone shot down in 1.56 s (28 hits) |
