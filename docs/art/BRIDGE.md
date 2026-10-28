# Strait bridge

The bridges from each landmass to the central island are one model, after the **Severn Bridge** (1966): the first
suspension bridge with an aerofoil box-girder deck, and the one with the inclined, zig-zag hangers. It is built at
real size, so a jet can fly under the main span: 47 m clear of the water at midspan (as on the real bridge), 988 m
between the towers.

## Files

| What | Where |
|---|---|
| Generator | `tools/blender/bridge_generate.py` |
| Textures | `tools/blender/bridge_textures.py` |
| Preview renders | `tools/blender/bridge_preview.py` |
| Manifest | `tools/Manifests/Scenery/SevernBridge.luau` (parts, sets, tile sizes) |
| References | `docs/art/reference/SevernBridge/` (kept out of git; see its SOURCES.md) |

```
blender -b --python tools/blender/bridge_generate.py -- --out <abs>/tools/blender/out --manifest-luau tools/Manifests/Scenery/SevernBridge.luau
blender -b --python tools/blender/bridge_textures.py -- --out <abs>/tools/blender/out/textures --skin Severn
blender -b <abs>/tools/blender/out/SevernBridge.blend --python tools/blender/bridge_preview.py -- --out <abs>/tools/blender/out --textures <abs>/tools/blender/out/textures --skin Severn
```

Outputs in `tools/blender/out/`: `SevernBridge.fbx`, `textures/SevernBridge_<Skin>_<Set>_<Map>.png` (4 sets x 4 maps
per skin) and `SevernBridge_<Skin>_{wide,quarter,tower,deck,anchorage}.png`.

## The model

- 1,890 m from abutment to abutment: the 988 m main span, two 305 m side spans, a concrete anchorage at each end of
  them, then a short approach viaduct (two portal piers) and an abutment. The deck follows a parabolic vertical
  curve, 50 m above the water at midspan and 18 m at the ends.
- Two 136 m steel towers (`TowerA`, `TowerB`), each two tapering legs with three cross-beams (top, middle and just
  under the deck), on concrete piers (`TowerPiers`). `TowerLightsA`/`B` are the red aviation lights on the tower
  tops (make them Neon).
- `Deck` (the aerofoil box girder), `Road` (the carriageway surface), `Walkways` (the cantilevered footpath and
  cycle track), `Barriers` (central reservation, verge and outer parapets), `LampPosts`.
- `MainCables` and `Hangers`: the hangers lean alternately, meeting in V-shapes at the deck, as on the Severn Bridge.
- 14 parts, 19,044 triangles, each part under Roblox's limits (the longest is 1,890 m).

Axes: Blender X across the bridge, Y along it, Z up; in Roblox (after the FBX export) x across, y up, z along. The
origin is the middle of the main span at the water line. Units are metres, so 1 stud = 1 m.

## Textures

The bridge is too long for one unique texture to stay sharp, so its surfaces use four tiling PBR sets and their UVs
run past 0..1 (the textures repeat):

| Set | Parts | Tile |
|---|---|---|
| Steel | towers, deck girder, barriers, lamp posts, lights | 6 m, box-projected |
| Concrete | piers, anchorages, approach viaduct, walkways | 8 m, box-projected |
| Road | the carriageway | 22.86 m across x 24 m along: one tile spans the road's width |
| Cable | main cables and hangers | round the cable, every 1.5 m along it |

Steel is painted plate with welded seams, bolt rows, mottling, grime running down and small rust spots; concrete is
board-marked with lift lines, tie holes and rain streaks; the road is asphalt with wheel-path polish, a concrete
central reservation and UK motorway markings (solid edge lines, 3 m lane dashes every 12 m, road studs); the cables
carry their helical wrapping wire. Vertical faces map height to v, so streaks run down them.

Two skins: `Severn` (the real bridge's off-white paint; the default) and `Weathered` (duller grey steel, darker
concrete).

## Placing it in the Strait

The channels run north to south, so the bridge's length goes along world x (turn the model 90 degrees about y). Its
deck needs about 1.7 km of water or less to land on both shores. Without the coastline noise, the two channels are
closest to that width on the line z = -400:

| Crossing | Gap at z = -400 | Bridge centre |
|---|---|---|
| West | 1,724 m (x -2,463 to -739) | (-1,601, -1.68, -400) |
| East | 1,700 m (x 739 to 2,439) | (1,589, -1.68, -400) |

y = -1.68 puts the model's water line on the sea (`WorldEdge.WATER`). The real coasts wobble by up to about 100 m
from the noise in `StraitBuilder`, so check both ends against `StraitBuilder.height(x, z)` in Studio and slide the
centre along x (or the line along z) until the abutments sit on land. The 790 m from each tower to its end leaves
room for that.

Collision: set the towers, tower piers, anchorages, approaches and deck to precise collision; the cables, hangers,
lamp posts and lights can have `CanCollide` off.
